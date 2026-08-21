deployment-toolkit/
├── .git/ (repo metadata)
├── .github/
│   └── workflows/
│       ├── build.yml               # reusable: checkout app+toolkit -> Publish.ps1 -> upload artifact          [Web Deploy]
│       ├── deploy-uat.yml          # reusable: checkout app+toolkit -> download artifact -> Deploy-WebDeploy.ps1 (environment: UAT) [Web Deploy]
│       ├── deploy-prod.yml         # reusable: same as above (environment: Production)                          [Web Deploy]
│       ├── build-docker.yml        # reusable: checkout app -> docker build -> push to GHCR                     [Docker]
│       ├── deploy-docker-uat.yml   # reusable: build .env from environment -> scp compose+.env -> ssh docker compose pull/up (environment: UAT) [Docker]
│       └── deploy-docker-prod.yml  # reusable: same as above (environment: Production)                          [Docker]
├── docs/
│   ├── README.md   # docs index
│   ├── NOTE.md     # architecture, deployment flow, appsettings.config.ps1 contract
│   └── STRUCTURE.md # this file
├── scripts/
│   ├── Publish.ps1                # discover web project, dotnet restore/publish to artifacts/publish, zip, generate appsettings
│   ├── Deploy-WebDeploy.ps1       # Get-MSDeploy preflight, regenerate appsettings, msdeploy.exe -verb:sync directly
│   ├── GenerateAppSettings.ps1    # apply deployment/appsettings.config.ps1 mapping (env vars) onto appsettings.json
│   ├── Compress-Publish.ps1       # zip artifacts/publish -> artifacts/publish.zip
│   ├── ConfigHelpers.ps1          # Read-AppSettings / Save-AppSettings / Set-ConfigValue
│   └── Helpers.ps1                # Get-WebProject, Get-MSDeploy, New-CleanDirectory, Get-(Required)EnvironmentVariable, logging helpers
└── README.md

Notes
- Artifact output (standard):

  artifacts/
  ├── publish/     # published files (dotnet publish -o)
  └── publish.zip  # compressed artifact used for deployment

- Recommended per-backend repo layout:

  my-backend-repo/
  ├── src/
  │   └── <ProjectName>/
  │       ├── appsettings.json         # base configuration, checked into source with empty/placeholder secrets
  │       └── Properties/PublishProfiles/ # generated at deploy time, not checked in
  ├── deployment/
  │   └── appsettings.config.ps1       # $configMap: "Json:Path" -> "ENV_VAR_NAME"
  └── .github/
      └── workflows/
          └── ci-cd.yml                # thin orchestrator calling this toolkit's reusable workflows

- How the flow works (high level):

  1. Push to `main`/`uat`/`production` triggers the consuming repo's `ci-cd.yml`. `main` is the trunk (build/validate only); `production` is a separate branch that only moves forward when someone deliberately merges into it, since a private repo on GitHub Free can't use branch protection to block direct pushes to `main` itself.
  2. It calls this toolkit's `build.yml`, which checks out the app repo + toolkit and runs `Publish.ps1` (build & package), uploading `artifacts/` as a workflow artifact.
  3. It calls `deploy-uat.yml` (on `uat`) or `deploy-prod.yml` (on `production`) with `secrets: inherit`. That job checks out the app repo + toolkit, downloads the artifact, loads every inherited variable/secret into the job environment, and runs `Deploy-WebDeploy.ps1`, which patches `appsettings.json` via `GenerateAppSettings.ps1` and syncs `artifacts/publish` straight to the target via `msdeploy.exe -verb:sync` (no rebuild, no .NET SDK needed in this job).

- Extending the toolkit:
  - Add a new `scripts/Deploy-<Provider>.ps1` for a hosting provider that isn't Web Deploy (e.g. plain FTP, Azure App Service) — or, if the provider needs no PowerShell of its own, just off-the-shelf GitHub Actions (the Docker strategy is exactly this: `docker/build-push-action` + `appleboy/ssh-action`, no `scripts/` needed at all).
  - Add a corresponding reusable workflow under `.github/workflows/`.
  - Keep provider-specific and project-specific secrets in the consuming repository's GitHub Secrets/Environments — never hardcode them here.

- **Docker strategy, added for Vendlo's Contabo VPS.** Unlike Web Deploy, `build-docker.yml` doesn't checkout this toolkit repo, there's no script to run, `docker/build-push-action` does the whole job from inputs alone. Config reaches the app as environment variables (`docker compose` reads `.env`), not a patched `appsettings.json`, so there's no `GenerateAppSettings.ps1` equivalent, ASP.NET Core (and most frameworks) already bind config from environment variables natively. See root `README.md`'s "Docker / VPS" sections and `TechieStephen/infrastructure-vps` for how the VPS side is provisioned.
