# deployment-toolkit

Reusable GitHub Actions workflows and PowerShell scripts for building, publishing, and deploying ASP.NET Core applications.

## Overview

This repository centralizes ASP.NET Core deployment logic so backend repositories can:

- discover and publish a single `Microsoft.NET.Sdk.Web` project
- produce a standard artifact layout
- deploy artifacts to hosting providers
- reuse shared GitHub workflows

## Components

- `scripts/Publish.ps1` - builds and publishes a web project into `artifacts/publish` and `artifacts/publish.zip`
- `scripts/Deploy-SmarterASP.ps1` - deploys published files to SmarterASP over FTP
- `scripts/Deploy-IIS.ps1` - deploys published files to an IIS physical path
- `scripts/Helpers.ps1` - shared helper functions for discovery and packaging
- `.github/workflows/DeployToSmarterASP.yml` - reusable SmarterASP workflow
- `.github/workflows/DeployToIIS.yml` - reusable IIS workflow
- `docs/README.md` - usage and architecture guidance

## Artifact layout

Publish produces the standard artifact structure:

```text
artifacts/
  publish/
  publish.zip
```

## Usage

Call the reusable workflow from a backend repository:

```yaml
jobs:
  deploy:
    uses: owner/deployment-toolkit/.github/workflows/DeployToSmarterASP.yml@main
    with:
      configuration: Release
      ftpHost: ${{ secrets.SMARTERASP_FTP_HOST }}
    secrets:
      SMARTERASP_FTP_USERNAME: ${{ secrets.SMARTERASP_FTP_USERNAME }}
      SMARTERASP_FTP_PASSWORD: ${{ secrets.SMARTERASP_FTP_PASSWORD }}
```

## Project responsibilities

Each repository keeps project-specific configuration and secrets handling, such as `deployment/Build-AppSettings.ps1` and environment config generation.

A recommended pattern is to keep a base `appsettings.json` in the application repo and use `Build-AppSettings.ps1` to merge secrets and environment-specific values into `deployment/appsettings.{Environment}.json`.

The deployment toolkit is responsible only for publishing and deploying artifacts, not application-specific settings.
