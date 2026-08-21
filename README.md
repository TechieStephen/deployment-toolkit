# deployment-toolkit

Reusable GitHub Actions workflows for building, publishing, and deploying applications. Hosts more than one deployment *strategy* side by side, an app repo picks whichever one fits its hosting target:

- **Web Deploy / IIS** — ASP.NET Core apps published and synced via `msdeploy.exe` (e.g. SmarterASP, IIS with the Web Management Service). PowerShell-scripted, runs on `windows-latest`.
- **Docker / VPS** — any app built as a Docker image, pushed to GHCR, deployed via `docker compose` over SSH. Runs on `ubuntu-latest`.

## Overview

This repository centralizes deployment logic so application repositories can:

- reuse shared, versioned GitHub workflows instead of copy-pasting CI/CD YAML into every repo
- pick a deployment strategy without needing to know how it works internally
- keep project-specific configuration and secrets inside the consuming repository

## Repository structure

```text
deployment-toolkit/
├── .github/
│   └── workflows/
│       ├── build.yml               # reusable: dotnet publish -> artifacts/publish(.zip)          [Web Deploy]
│       ├── deploy-uat.yml          # reusable: deploy an artifact via Web Deploy (uat)             [Web Deploy]
│       ├── deploy-prod.yml         # reusable: deploy an artifact via Web Deploy (production)      [Web Deploy]
│       ├── build-docker.yml        # reusable: docker build -> push to GHCR                        [Docker]
│       ├── deploy-docker-uat.yml   # reusable: docker compose pull && up over SSH (uat)             [Docker]
│       └── deploy-docker-prod.yml  # reusable: docker compose pull && up over SSH (production)      [Docker]
├── docs/
│   ├── README.md
│   ├── STRUCTURE.md
│   └── NOTE.md
├── scripts/
│   ├── Publish.ps1                # discover project, dotnet publish, zip                [Web Deploy only]
│   ├── Deploy-WebDeploy.ps1       # generate appsettings, sync artifacts/publish via msdeploy.exe [Web Deploy only]
│   ├── GenerateAppSettings.ps1    # merge deployment/appsettings.config.ps1 + env vars into appsettings.json [Web Deploy only]
│   ├── Compress-Publish.ps1       # zip artifacts/publish -> artifacts/publish.zip      [Web Deploy only]
│   ├── ConfigHelpers.ps1          # JSON read/save/patch helpers                        [Web Deploy only]
│   └── Helpers.ps1                # project discovery, logging, misc shared helpers    [Web Deploy only]
└── README.md
```

The Docker strategy has no `scripts/` of its own, `docker/build-push-action` and a couple of SSH steps cover it directly in the workflow YAML; there's no per-project artifact-patching step to script, config reaches the container as environment variables instead (see "Reusable workflows" and "Runtime configuration (Docker)" below).

## Core scripts

- `scripts/Publish.ps1` publishes the ASP.NET Core web project and creates the standard artifacts:
  - `artifacts/publish/`
  - `artifacts/publish.zip` (unless `-SkipZip` is passed)
- `scripts/Deploy-WebDeploy.ps1` regenerates `appsettings.json` with real secrets, then calls `msdeploy.exe -verb:sync` directly to push the already-published `artifacts/publish` folder to the target site — no rebuild, so it works from a fresh runner that only has the downloaded build artifact (not the original `bin`/`obj` state from the build job).
- `scripts/GenerateAppSettings.ps1` / `scripts/ConfigHelpers.ps1` merge values from environment variables into `appsettings.json`, driven entirely by the consuming repo's `deployment/appsettings.config.ps1`.
- `scripts/Helpers.ps1` contains `Get-WebProject` (auto-discovers the single `Microsoft.NET.Sdk.Web` project, or validates `-Project` if given) and `Get-MSDeploy` (locates `msdeploy.exe`, fails fast with a clear error if Web Deploy isn't installed on the runner).

## Visibility

This repository must stay **public**. Consuming repos check it out via `actions/checkout` using their own default `GITHUB_TOKEN`, which cannot read a different *private* repo even under the same account. Since this toolkit contains no secrets or app-specific config by design, there's no downside to keeping it public.

## Reusable workflows

### Web Deploy / IIS

- `.github/workflows/build.yml` — checks out the app repo + this toolkit, runs `Publish.ps1`, uploads `artifacts/` as a workflow artifact.
- `.github/workflows/deploy-uat.yml` / `deploy-prod.yml` — check out the app repo + this toolkit, download the build artifact, and run `Deploy-WebDeploy.ps1` against the `UAT` / `Production` GitHub Environment. **These jobs run on `windows-latest`** because Web Deploy (`msdeploy.exe`) is Windows-only.

Both deploy workflows dump every inherited secret into the job's environment (see "Secrets and Variables" below), so the toolkit never needs to know a consuming project's secret names ahead of time.

A `test` environment/workflow (for running unit tests, not deploying anywhere) is planned but not implemented yet — see `docs/NOTE.md`.

### Docker / VPS

- `.github/workflows/build-docker.yml` — checks out the app repo, builds an image from the given `context`/`dockerfile`, pushes it to GHCR tagged with both the commit SHA (immutable, for rollback reference) and the branch name (a floating tag, e.g. `:uat`/`:production`). Call it once per image an app builds, Vendlo calls it three times (storefront, dashboard, api).
- `.github/workflows/deploy-docker-uat.yml` / `deploy-docker-prod.yml` — build a `.env` file from the `UAT`/`Production` GitHub Environment's vars and secrets (same generic-forwarding approach as the Web Deploy path, just handed to the container as environment variables instead of patched into `appsettings.json`), copy it plus the app repo's own `docker-compose.yml` to the VPS, then SSH in and run `docker compose pull && docker compose up -d`. Runs on `ubuntu-latest`, no Windows runner needed.

The app's `docker-compose.yml` should reference each image by the `TAG` variable the deploy workflow injects (e.g. `image: ghcr.io/techiestephen/vendlo-api:${TAG}`), so `docker compose pull` always grabs exactly what `build-docker.yml` just pushed for that branch.

## App settings pattern (Web Deploy)

Each backend repository owns its own configuration mapping:

1. Keep a base `appsettings.json` in the application repository (checked into source, with empty/placeholder values for anything secret).
2. Add `deployment/appsettings.config.ps1` defining a `$configMap` of `"Json:Path" = "ENV_VAR_NAME"` pairs — see `docs/NOTE.md` for the full contract and an example.
3. `GenerateAppSettings.ps1` reads that map and, for every entry with a non-empty environment variable, patches the value into `appsettings.json` before it's deployed.
4. This toolkit only handles publishing and deploying artifacts — it never needs to know what any of those config keys mean.

## Runtime configuration (Docker)

No patching script needed here, ASP.NET Core (and most frameworks) already bind configuration from environment variables natively. The deploy workflow writes every var/secret from the GitHub Environment straight into `.env` on the VPS, and `docker compose` passes that through to each container, e.g. a `ConnectionStrings__Default` entry becomes `ConnectionStrings:Default` in .NET's config system automatically. Nothing in this toolkit needs to know what any of those keys mean.

## Secrets and Variables

### Web Deploy / IIS

The deploy jobs load **both** [GitHub Environment Variables](https://docs.github.com/actions/learn-github-actions/variables) (`vars`) and [Environment Secrets](https://docs.github.com/actions/security-guides/using-secrets-in-github-actions) into the job's environment before deploying — a `Load environment configuration` step dumps `toJSON(vars)` and `toJSON(secrets)` into `$GITHUB_ENV` generically, so the toolkit never needs to know a consuming project's variable/secret names ahead of time. Note that **variables are not covered by `secrets: inherit`** — they're picked up automatically because the job is scoped to the environment (`environment: UAT` / `environment: Production`), no extra wiring needed on the caller's side.

Split what you configure in each [GitHub Environment](https://docs.github.com/actions/deployment/targeting-different-environments/using-environments-for-deployment) (`UAT` / `Production`) accordingly:

- **Variables** (plain text, fine to view in the UI): `MSDEPLOY_URL`, `MSDEPLOY_SITE`, `MSDEPLOY_USERNAME` are required for the `msdeploy.exe` sync command; `SITE_URL` is optional (logged for visibility only, not otherwise used). None of these are secret on their own — they're URLs/identifiers, not credentials.
- **Secrets** (masked, encrypted): `MSDEPLOY_PASSWORD` — the only one this toolkit itself requires — plus anything referenced on the right-hand side of your `deployment/appsettings.config.ps1` map (e.g. `DB_CONNECTION`, `JWT_SECRET`, `SENDGRID_API_KEY`, ...), since those are genuinely sensitive.

### Docker / VPS

- **Variables:** `VPS_HOST`, `VPS_DEPLOY_USER` (the `deploy` user the `infrastructure-vps` repo's Ansible run already created), plus anything your app needs at runtime that isn't sensitive.
- **Secrets:** `VPS_SSH_PRIVATE_KEY` (the private half of the keypair whose public half is `infrastructure-vps`'s `deploy_user_ssh_key` variable, the same keypair for every app since they all deploy as the same `deploy` user), `GHCR_PAT` (a PAT with `read:packages`, used by the VPS to pull images from GHCR), plus anything your app needs at runtime that is sensitive (`DB_CONNECTION`, `JWT_SECRET`, `PAYSTACK_SECRET_KEY`, ...).

Using GitHub Environments this way lets you reuse the same variable/secret names across `UAT` and `Production` with different values per environment, and lets you gate production with required reviewers.

## Usage example

### Web Deploy / IIS

A consuming repository needs one orchestrator workflow that triggers on push and calls the reusable workflows with `secrets: inherit`. `main` is treated as the trunk (build/validate only, never deployed directly); a dedicated `production` branch is what actually triggers a production deploy — merging into it is a deliberate, separate step, which matters when the repo is private and can't use GitHub's native branch protection (Free plan doesn't support it on private repos):

```yaml
name: CI/CD

on:
  push:
    branches: [main, uat, production]
  pull_request:

jobs:
  build:
    uses: TechieStephen/deployment-toolkit/.github/workflows/build.yml@main

  deploy-uat:
    if: github.event_name == 'push' && github.ref == 'refs/heads/uat'
    needs: build
    uses: TechieStephen/deployment-toolkit/.github/workflows/deploy-uat.yml@main
    with:
      artifact_name: ${{ needs.build.outputs.artifact_name }}
    secrets: inherit

  deploy-prod:
    if: github.event_name == 'push' && github.ref == 'refs/heads/production'
    needs: build
    uses: TechieStephen/deployment-toolkit/.github/workflows/deploy-prod.yml@main
    with:
      artifact_name: ${{ needs.build.outputs.artifact_name }}
    secrets: inherit
```

### Docker / VPS

An app with more than one container (Vendlo: storefront, dashboard, api) calls `build-docker.yml` once per image, each needs `permissions: packages: write` at the caller job level too, a reusable workflow's effective permissions are the intersection of both:

```yaml
name: CI/CD

on:
  push:
    branches: [main, uat, production]
  pull_request:

jobs:
  build-api:
    permissions:
      contents: read
      packages: write
    uses: TechieStephen/deployment-toolkit/.github/workflows/build-docker.yml@main
    with:
      image_name: ghcr.io/techiestephen/vendlo-api
      context: api

  build-storefront:
    permissions:
      contents: read
      packages: write
    uses: TechieStephen/deployment-toolkit/.github/workflows/build-docker.yml@main
    with:
      image_name: ghcr.io/techiestephen/vendlo-storefront
      context: storefront

  build-dashboard:
    permissions:
      contents: read
      packages: write
    uses: TechieStephen/deployment-toolkit/.github/workflows/build-docker.yml@main
    with:
      image_name: ghcr.io/techiestephen/vendlo-dashboard
      context: dashboard

  deploy-uat:
    if: github.event_name == 'push' && github.ref == 'refs/heads/uat'
    needs: [build-api, build-storefront, build-dashboard]
    uses: TechieStephen/deployment-toolkit/.github/workflows/deploy-docker-uat.yml@main
    with:
      compose_project_dir: /opt/apps/vendlo
    secrets: inherit

  deploy-prod:
    if: github.event_name == 'push' && github.ref == 'refs/heads/production'
    needs: [build-api, build-storefront, build-dashboard]
    uses: TechieStephen/deployment-toolkit/.github/workflows/deploy-docker-prod.yml@main
    with:
      compose_project_dir: /opt/apps/vendlo
    secrets: inherit
```

An app with a single container just calls `build-docker.yml` once and skips the `needs` list down to one job.

Do not copy any of these workflow files into the consuming repository — call them via `uses:` so future fixes to this toolkit apply automatically.

## Documentation

See [docs/STRUCTURE.md](docs/STRUCTURE.md) for repository structure/conventions and [docs/NOTE.md](docs/NOTE.md) for the architecture and the `appsettings.config.ps1` contract.
