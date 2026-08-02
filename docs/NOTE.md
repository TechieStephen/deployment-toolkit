# Deployment Toolkit Architecture

## Goal

A reusable deployment toolkit for ASP.NET Core backend projects, so backend repos don't each carry their own copy of build/deploy GitHub Actions workflows and PowerShell scripts.

---

## Repository Structure

```text
deployment-toolkit/
│
├── .github/
│   └── workflows/
│       ├── build.yml        # reusable: publish -> artifacts/publish(.zip)
│       ├── deploy-uat.yml   # reusable: publish -> Deploy-WebDeploy.ps1 (uat environment)
│       └── deploy-prod.yml  # reusable: publish -> Deploy-WebDeploy.ps1 (production environment)
│
├── scripts/
│   ├── Publish.ps1
│   ├── Deploy-WebDeploy.ps1
│   ├── GenerateAppSettings.ps1
│   ├── GeneratePublishProfile.ps1
│   ├── Compress-Publish.ps1
│   ├── ConfigHelpers.ps1
│   └── Helpers.ps1
│
├── templates/
│   └── WebDeploy.pubxml
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

- Generate a Web Deploy publish profile from a template and deploy via `dotnet publish /p:PublishProfile=...`.
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

## Deployment Flow

```text
Push to uat/main
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
        │  └─ GeneratePublishProfile.ps1 + dotnet publish /p:PublishProfile=WebDeploy
        ▼
Deployed
```

Notes:

- `Publish.ps1` (in `build.yml`) also calls `GenerateAppSettings.ps1`, but at that point no environment-specific secrets are set, so it's effectively a no-op there — it exists so `Publish.ps1` can also be run locally with secrets already in the environment. The real config injection happens in the deploy job, where `Deploy-WebDeploy.ps1` calls `GenerateAppSettings.ps1` again against the downloaded artifact, after every inherited secret has been loaded.
- `deploy-uat.yml` / `deploy-prod.yml` run on `windows-latest` because Web Deploy (`msdeploy.exe`) is Windows-only; `Deploy-WebDeploy.ps1` calls `Get-MSDeploy` up front to fail fast if it's missing.
- A third environment, `test`, is reserved for running unit/integration tests (not a deploy target). It isn't wired into any workflow yet — see Roadmap.

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
- `Publish.ps1`, `Deploy-WebDeploy.ps1`, `GenerateAppSettings.ps1`, `GeneratePublishProfile.ps1`.
- Reusable `build.yml` / `deploy-uat.yml` / `deploy-prod.yml` workflows with generic secret forwarding and environment gating.
- Migrated `exampro-backend` to call the toolkit's reusable workflows instead of copying them.

### Next
- Add a `test.yml` reusable workflow that runs `dotnet test` against the `Test` GitHub Environment (for a test database connection string and similar). Triggered on PRs/pushes to any branch, not just `main`/`uat`, and doesn't deploy anything.
- Add a health-check step after deploy (hit `SITE_URL` and confirm a 2xx response) with an automatic rollback path.
- Support additional providers beyond Web Deploy (plain FTP, Azure App Service, Docker/Linux) as separate `Deploy-<Provider>.ps1` scripts + matching reusable workflows, once a second project needs one.
- Add Pester tests for the PowerShell scripts.
- Consider versioned workflow tags (`@v1`, `@v2`) once more than one consuming repo depends on this toolkit, so a breaking change in `main` doesn't break everyone at once.
