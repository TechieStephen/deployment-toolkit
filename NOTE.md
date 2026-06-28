# Deployment Toolkit Architecture

## Goal

Create a reusable deployment toolkit for all ASP.NET Core backend projects to eliminate duplicated GitHub Actions workflows and deployment scripts.

---

## Repository Structure

```text
deployment-toolkit/
│
├── .github/
│   └── workflows/
│       ├── DeployToSmarterASP.yml
│       ├── DeployToIIS.yml
│       └── (future providers)
│
├── scripts/
│   ├── Publish.ps1
│   ├── Deploy-SmarterASP.ps1
│   ├── Deploy-IIS.ps1
│   └── Helpers.ps1
│
└── docs/
```

---

## Responsibilities

### Deployment Toolkit

- Publish ASP.NET Core projects.
- Auto-discover a single `Microsoft.NET.Sdk.Web` project.
- Allow explicit `-Project` when multiple web projects exist.
- Produce a standard artifact:

```text
artifacts/
├── publish/
└── publish.zip
```

- Deploy artifacts to hosting providers.
- Provide reusable GitHub Actions workflows.
- Contain shared deployment logic only.

### Individual Projects

Each backend project contains:

```text
deployment/
└── Build-AppSettings.ps1
```

Responsibilities:

- Generate `appsettings.{Environment}.json`.
- Read repository secrets and variables.
- Handle project-specific configuration.

---

## Deployment Flow

```text
Checkout Project
        │
        ▼
Checkout deployment-toolkit
        │
        ▼
Build-AppSettings.ps1
        │
        ▼
Publish.ps1
        │
        ▼
artifacts/publish.zip
        │
        ▼
Deploy-<Provider>.ps1
```

---

## Design Principles

- Single Responsibility Principle.
- Build once, deploy anywhere.
- Centralize deployment logic.
- Keep project-specific configuration within each repository.
- Standardize artifact output.
- Minimize per-project GitHub workflow code.
- Make adding new deployment providers straightforward.

---

## Roadmap

### Phase 1
- Create `deployment-toolkit` repository.
- Implement `Publish.ps1`.
- Implement `Deploy-SmarterASP.ps1`.
- Create reusable GitHub workflow.

### Phase 2
- Migrate one backend project.
- Validate deployment.
- Release `v1`.

### Phase 3
- Migrate remaining backend projects.

### Phase 4
Add support for:

- IIS
- Azure
- Linux
- Docker
- Health checks
- Rollback
- Notifications
- Versioned workflows (`v1`, `v2`, ...)
- Shared helper functions
- PowerShell tests
- Documentation and examples