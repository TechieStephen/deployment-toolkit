# deployment-toolkit

Reusable GitHub Actions workflows and PowerShell scripts for building, publishing, and deploying ASP.NET Core applications via Web Deploy (MSDeploy).

## Overview

This repository centralizes deployment logic so backend repositories can:

- discover and publish a single `Microsoft.NET.Sdk.Web` project
- produce a standard artifact layout
- deploy artifacts to a Web Deploy (MSDeploy) target, e.g. SmarterASP or IIS with the Web Management Service
- reuse shared, versioned GitHub workflows instead of copy-pasting CI/CD YAML into every repo
- keep project-specific configuration and secrets inside the consuming repository

## Repository structure

```text
deployment-toolkit/
├── .github/
│   └── workflows/
│       ├── build.yml        # reusable: dotnet publish -> artifacts/publish(.zip)
│       ├── deploy-uat.yml   # reusable: deploy an artifact via Web Deploy (uat environment)
│       └── deploy-prod.yml  # reusable: deploy an artifact via Web Deploy (production environment)
├── docs/
│   ├── README.md
│   ├── STRUCTURE.md
│   └── NOTE.md
├── scripts/
│   ├── Publish.ps1                # discover project, dotnet publish, zip
│   ├── Deploy-WebDeploy.ps1       # generate appsettings + publish profile, deploy via dotnet publish /p:PublishProfile
│   ├── GenerateAppSettings.ps1    # merge deployment/appsettings.config.ps1 + env vars into appsettings.json
│   ├── GeneratePublishProfile.ps1 # render templates/WebDeploy.pubxml with connection details
│   ├── Compress-Publish.ps1       # zip artifacts/publish -> artifacts/publish.zip
│   ├── ConfigHelpers.ps1          # JSON read/save/patch helpers
│   └── Helpers.ps1                # project discovery, logging, misc shared helpers
├── templates/
│   └── WebDeploy.pubxml
└── README.md
```

## Core scripts

- `scripts/Publish.ps1` publishes the ASP.NET Core web project and creates the standard artifacts:
  - `artifacts/publish/`
  - `artifacts/publish.zip` (unless `-SkipZip` is passed)
- `scripts/Deploy-WebDeploy.ps1` regenerates `appsettings.json` with real secrets, generates a temporary Web Deploy publish profile from `templates/WebDeploy.pubxml`, and runs `dotnet publish /p:PublishProfile=...` to push the app to the target site.
- `scripts/GenerateAppSettings.ps1` / `scripts/ConfigHelpers.ps1` merge values from environment variables into `appsettings.json`, driven entirely by the consuming repo's `deployment/appsettings.config.ps1`.
- `scripts/GeneratePublishProfile.ps1` fills in `templates/WebDeploy.pubxml` using `SITE_URL`, `MSDEPLOY_URL`, `MSDEPLOY_SITE`, `MSDEPLOY_USERNAME`, `MSDEPLOY_PASSWORD`.
- `scripts/Helpers.ps1` contains `Get-WebProject` (auto-discovers the single `Microsoft.NET.Sdk.Web` project, or validates `-Project` if given) and `Get-MSDeploy` (fails fast if Web Deploy isn't installed on the runner).

## Visibility

This repository must stay **public**. Consuming repos check it out via `actions/checkout` using their own default `GITHUB_TOKEN`, which cannot read a different *private* repo even under the same account. Since this toolkit contains no secrets or app-specific config by design, there's no downside to keeping it public.

## Reusable workflows

- `.github/workflows/build.yml` — checks out the app repo + this toolkit, runs `Publish.ps1`, uploads `artifacts/` as a workflow artifact.
- `.github/workflows/deploy-uat.yml` / `deploy-prod.yml` — check out the app repo + this toolkit, download the build artifact, and run `Deploy-WebDeploy.ps1` against the `UAT` / `Production` GitHub Environment. **These jobs run on `windows-latest`** because Web Deploy (`msdeploy.exe`) is Windows-only.

Both deploy workflows dump every inherited secret into the job's environment (see "Secrets" below), so the toolkit never needs to know a consuming project's secret names ahead of time.

A `test` environment/workflow (for running unit tests, not deploying anywhere) is planned but not implemented yet — see `docs/NOTE.md`.

## App settings pattern

Each backend repository owns its own configuration mapping:

1. Keep a base `appsettings.json` in the application repository (checked into source, with empty/placeholder values for anything secret).
2. Add `deployment/appsettings.config.ps1` defining a `$configMap` of `"Json:Path" = "ENV_VAR_NAME"` pairs — see `docs/NOTE.md` for the full contract and an example.
3. `GenerateAppSettings.ps1` reads that map and, for every entry with a non-empty environment variable, patches the value into `appsettings.json` before it's deployed.
4. This toolkit only handles publishing and deploying artifacts — it never needs to know what any of those config keys mean.

## Secrets

Declare these as repository or [GitHub Environment](https://docs.github.com/actions/deployment/targeting-different-environments/using-environments-for-deployment) secrets in the **consuming repository**:

- `SITE_URL`, `MSDEPLOY_URL`, `MSDEPLOY_SITE`, `MSDEPLOY_USERNAME`, `MSDEPLOY_PASSWORD` — required by every deploy, used to build the Web Deploy publish profile.
- Anything referenced on the right-hand side of your `deployment/appsettings.config.ps1` map (e.g. `DB_CONNECTION`, `JWT_SECRET`, `SENDGRID_API_KEY`, ...).

Using GitHub Environments (named `UAT` and `Production`, matching the `environment:` field in `deploy-uat.yml`/`deploy-prod.yml`) lets you reuse the same secret names across environments with different values, and lets you gate production with required reviewers.

## Usage example

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

Do not copy `build.yml`/`deploy-uat.yml`/`deploy-prod.yml` into the consuming repository — call them via `uses:` so future fixes to this toolkit apply automatically.

## Documentation

See [docs/STRUCTURE.md](docs/STRUCTURE.md) for repository structure/conventions and [docs/NOTE.md](docs/NOTE.md) for the architecture and the `appsettings.config.ps1` contract.
