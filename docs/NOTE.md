# Deployment Toolkit Architecture

## Goal

A reusable deployment toolkit so application repos don't each carry their own copy of build/deploy GitHub Actions workflows. Hosts more than one deployment *strategy*, not tied to a single hosting target:

- **Web Deploy / IIS** — ASP.NET Core, PowerShell-scripted, `msdeploy.exe` sync.
- **Docker / VPS** — any containerized app, GHCR + `docker compose` over SSH.

---

## Repository Structure

```text
deployment-toolkit/
│
├── .github/
│   └── workflows/
│       ├── build.yml               # reusable: publish -> artifacts/publish(.zip)                    [Web Deploy]
│       ├── deploy-uat.yml          # reusable: publish -> Deploy-WebDeploy.ps1 (uat environment)      [Web Deploy]
│       ├── deploy-prod.yml         # reusable: publish -> Deploy-WebDeploy.ps1 (production)           [Web Deploy]
│       ├── build-docker.yml        # reusable: docker build -> push to GHCR                           [Docker]
│       ├── deploy-docker-uat.yml   # reusable: build .env -> scp -> ssh docker compose pull/up (uat)  [Docker]
│       └── deploy-docker-prod.yml  # reusable: same, production                                       [Docker]
│
├── scripts/                        # Web Deploy strategy only, Docker needs none, see below
│   ├── Publish.ps1
│   ├── Deploy-WebDeploy.ps1
│   ├── GenerateAppSettings.ps1
│   ├── Compress-Publish.ps1
│   ├── ConfigHelpers.ps1
│   └── Helpers.ps1
│
└── docs/
```

---

## Responsibilities

### Deployment Toolkit

- Publish ASP.NET Core projects.
- Auto-discover a single `Microsoft.NET.Sdk.Web` project (or accept an explicit `-Project`).
- Produce a standard artifact:

```text
artifacts/
├── publish/
└── publish.zip
```

- Sync the already-published output to a Web Deploy target via `msdeploy.exe -verb:sync` directly (no rebuild in the deploy job).
- Provide reusable GitHub Actions workflows (`build.yml`, `deploy-uat.yml`, `deploy-prod.yml`).
- Contain shared deployment logic only — no project-specific config keys or secret names.

### Individual Projects

Each backend project contains:

```text
deployment/
└── appsettings.config.ps1
```

`appsettings.config.ps1` defines a `$configMap` hashtable mapping a JSON path (colon-delimited, e.g. `"Jwt:SecretKey"`) to the name of an environment variable that should be injected there at deploy time, e.g.:

```powershell
$configMap = @{
    "ConnectionStrings:exampro" = "DB_CONNECTION"
    "Jwt:SecretKey"             = "JWT_SECRET"
    "Sendgrid:ApiKey"           = "SENDGRID_API_KEY"
}
```

Responsibilities of the consuming project:

- Keep a base `appsettings.json` in source control with placeholder/empty values for anything secret.
- Define `deployment/appsettings.config.ps1` mapping config keys to environment variable names.
- Configure the actual secret values as repository or [GitHub Environment](https://docs.github.com/actions/deployment/targeting-different-environments/using-environments-for-deployment) secrets (`UAT` / `Production`), plus the Web Deploy connection secrets (`SITE_URL`, `MSDEPLOY_URL`, `MSDEPLOY_SITE`, `MSDEPLOY_USERNAME`, `MSDEPLOY_PASSWORD`).
- Own a single orchestrator workflow that triggers on push and calls this toolkit's reusable workflows with `secrets: inherit` (see root `README.md` for the template). Never copy `build.yml`/`deploy-uat.yml`/`deploy-prod.yml` into the consuming repo.

---

## Docker Strategy

Added for Vendeck's Contabo VPS (see `TechieStephen/infrastructure-vps` and `trada-docs/docs/Infrastructure_Deployment_Architecture.md` for the VPS side). Deliberately has no PowerShell scripts of its own:

- `build-docker.yml` needs no toolkit checkout, `docker/build-push-action` does the whole build+push from its inputs (`image_name`, `context`, `dockerfile`) alone. Tags every image with both the commit SHA (immutable) and the branch name (a floating tag, `:uat`/`:production`).
- `deploy-docker-uat.yml` / `deploy-docker-prod.yml` build a `.env` file from the GitHub Environment's vars+secrets (mirrors the Web Deploy path's generic-forwarding trick, just without a PowerShell script or a JSON file to patch), copy it and the app's own `docker-compose.yml` to the VPS via `appleboy/scp-action`, then `appleboy/ssh-action` logs into GHCR and runs `docker compose pull && docker compose up -d`.
- No `appsettings.config.ps1` equivalent, config reaches the container as real environment variables, which ASP.NET Core (and most frameworks) already read natively. The toolkit still never needs to know what any of those variable names mean.
- Runs on `ubuntu-latest`, not `windows-latest`, nothing here needs Windows.

Responsibilities of a Docker-strategy consuming project: own a `docker-compose.yml` at its repo root referencing each image as `image: <registry>/<name>:${TAG}`, apply Caddy/Prometheus/backup Docker labels per `infrastructure-vps`'s README ("Labels applications must set"), and configure `VPS_HOST`/`VPS_DEPLOY_USER` (Variables) plus `VPS_SSH_PRIVATE_KEY`/`GHCR_PAT`/its own app secrets (Secrets) on its `UAT`/`Production` GitHub Environments.

---

## Deployment Flow (Web Deploy / IIS)

```text
Push to uat/production (main is trunk-only, never deployed)
        │
        ▼
build.yml (checkout app + toolkit, Publish.ps1)
        │
        ▼
artifacts/publish.zip  (uploaded as workflow artifact)
        │
        ▼
deploy-uat.yml / deploy-prod.yml
        │  (checkout app + toolkit, download artifact)
        ▼
Load all inherited secrets into the job environment
        │
        ▼
Deploy-WebDeploy.ps1
        │  ├─ GenerateAppSettings.ps1  (patches appsettings.json using deployment/appsettings.config.ps1)
        │  └─ msdeploy.exe -verb:sync (syncs artifacts/publish to the target directly)
        ▼
Deployed
```

Notes:

- `Publish.ps1` (in `build.yml`) also calls `GenerateAppSettings.ps1`, but at that point no environment-specific secrets are set, so it's effectively a no-op there — it exists so `Publish.ps1` can also be run locally with secrets already in the environment. The real config injection happens in the deploy job, where `Deploy-WebDeploy.ps1` calls `GenerateAppSettings.ps1` again against the downloaded artifact, after every inherited secret has been loaded.
- `deploy-uat.yml` / `deploy-prod.yml` run on `windows-latest` because Web Deploy (`msdeploy.exe`) is Windows-only; `Deploy-WebDeploy.ps1` calls `Get-MSDeploy` up front to fail fast if it's missing. Neither workflow needs a .NET SDK anymore — `Deploy-WebDeploy.ps1` never invokes `dotnet`, only `msdeploy.exe` directly, so the deploy job doesn't depend on `bin`/`obj` state carrying over from the build job's runner.
- A third environment, `test`, is reserved for running unit/integration tests (not a deploy target). It isn't wired into any workflow yet — see Roadmap.

## Deployment Flow (Docker / VPS)

```text
Push to uat/production (main is trunk-only, never deployed)
        │
        ▼
build-docker.yml × N  (one call per image an app builds)
        │  docker build -> push to GHCR, tagged :<sha> and :<branch>
        ▼
deploy-docker-uat.yml / deploy-docker-prod.yml
        │  build .env from every inherited var/secret + TAG=<branch>
        ▼
scp docker-compose.yml + .env to the VPS (appleboy/scp-action)
        │
        ▼
ssh: docker login ghcr.io, docker compose pull, docker compose up -d
        │
        ▼
Caddy/Prometheus/backups pick the new containers up automatically,
by the Docker labels the app's own compose file sets (see
TechieStephen/infrastructure-vps's README), no infra-repo change needed
        ▼
Deployed
```

Notes:

- Runs on `ubuntu-latest` throughout, nothing here needs Windows.
- No PowerShell, no `scripts/`, no artifact upload/download between jobs — `build-docker.yml` pushes straight to GHCR and `deploy-docker-*.yml` pulls straight from it, the registry is the handoff, not a workflow artifact.
- `TAG` is the one variable this toolkit injects itself (`github.ref_name`, i.e. the branch), every other line in `.env` comes from the calling repo's GitHub Environment. The app's `docker-compose.yml` references it as `image: <registry>/<name>:${TAG}`.

---

## Design Principles

- Single Responsibility Principle.
- Build once, deploy anywhere.
- Centralize deployment logic; keep project-specific configuration and secret *names* within each repository.
- The toolkit never needs to know a consuming project's secret names — deploy jobs forward every inherited secret into the environment generically, and `appsettings.config.ps1` decides what's relevant.
- Standardize artifact output.
- Minimize per-project GitHub workflow code to a single small orchestrator.

---

## Roadmap

### Done
- `Publish.ps1`, `Deploy-WebDeploy.ps1` (direct `msdeploy.exe` sync, no rebuild needed in the deploy job), `GenerateAppSettings.ps1`.
- Reusable `build.yml` / `deploy-uat.yml` / `deploy-prod.yml` workflows with generic secret forwarding and environment gating.
- Migrated `exampro-backend` to call the toolkit's reusable workflows instead of copying them.
- Docker strategy: `build-docker.yml` / `deploy-docker-uat.yml` / `deploy-docker-prod.yml`, for Vendeck's Contabo VPS. Not yet exercised against a live app repo or a real VPS, see Next.

### Next
- Actually run the Docker strategy end to end once Vendeck's `docker-compose.yml` and a provisioned VPS both exist, confirm the label-based Caddy/Prometheus/backup discovery (`TechieStephen/infrastructure-vps`) actually picks up a freshly-deployed container correctly.
- Split each consuming app's `UAT`/`Production` GitHub Environment into deploy-only vs. app-only secret groups. Today `deploy-docker-uat.yml`/`deploy-docker-prod.yml` dump the whole Environment into one `.env`, which the app's `docker-compose.yml` then loads wholesale via `env_file: .env` -- so deploy-mechanism secrets (`VPS_SSH_PRIVATE_KEY`, `GHCR_PAT`) end up sitting in the running app container's environment alongside its actual runtime config (`NUXT_PUBLIC_API_BASE`, etc.), not just used to reach the VPS. Not a real risk yet (nothing's live, this pipeline hasn't been exercised against a real deploy), but worth fixing before it is -- e.g. two separate `.env` files (one deploy-only, consumed by the SSH/compose step itself; one app-only, the only one referenced by `env_file:`), or two separate GitHub Environments per app.
- Add a `test.yml` reusable workflow that runs `dotnet test` against the `Test` GitHub Environment (for a test database connection string and similar). Triggered on PRs/pushes to any branch, not just `main`/`uat`, and doesn't deploy anything.
- Add a health-check step after deploy (hit `SITE_URL` and confirm a 2xx response) with an automatic rollback path. Applies to both strategies.
- Add Pester tests for the PowerShell scripts (Web Deploy strategy).
- Consider versioned workflow tags (`@v1`, `@v2`) once more than one consuming repo depends on this toolkit, so a breaking change in `main` doesn't break everyone at once.
