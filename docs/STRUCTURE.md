deployment-toolkit/
├── .git/ (repo metadata)
├── .github/
│   └── workflows/
│       ├── build.yml        # reusable workflow: checkout app+toolkit -> Publish.ps1 -> upload artifact
│       ├── deploy-uat.yml   # reusable workflow: checkout app+toolkit -> download artifact -> Deploy-WebDeploy.ps1 (environment: UAT)
│       └── deploy-prod.yml  # reusable workflow: same as above (environment: Production)
├── docs/
│   ├── README.md   # docs index
│   ├── NOTE.md     # architecture, deployment flow, appsettings.config.ps1 contract
│   └── STRUCTURE.md # this file
├── scripts/
│   ├── Publish.ps1                # discover web project, dotnet restore/publish to artifacts/publish, zip, generate appsettings
│   ├── Deploy-WebDeploy.ps1       # Get-MSDeploy preflight, regenerate appsettings, generate publish profile, dotnet publish /p:PublishProfile
│   ├── GenerateAppSettings.ps1    # apply deployment/appsettings.config.ps1 mapping (env vars) onto appsettings.json
│   ├── GeneratePublishProfile.ps1 # render templates/WebDeploy.pubxml into Properties/PublishProfiles/<Profile>.pubxml
│   ├── Compress-Publish.ps1       # zip artifacts/publish -> artifacts/publish.zip
│   ├── ConfigHelpers.ps1          # Read-AppSettings / Save-AppSettings / Set-ConfigValue
│   └── Helpers.ps1                # Get-WebProject, Get-MSDeploy, New-CleanDirectory, Get-(Required)EnvironmentVariable, logging helpers
├── templates/
│   └── WebDeploy.pubxml   # MSDeploy publish profile template with __PLACEHOLDER__ tokens
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

  1. Push to `uat`/`main` triggers the consuming repo's `ci-cd.yml`.
  2. It calls this toolkit's `build.yml`, which checks out the app repo + toolkit and runs `Publish.ps1` (build & package), uploading `artifacts/` as a workflow artifact.
  3. It calls `deploy-uat.yml` (on `uat`) or `deploy-prod.yml` (on `main`) with `secrets: inherit`. That job checks out the app repo + toolkit, downloads the artifact, loads every inherited secret into the job environment, and runs `Deploy-WebDeploy.ps1`, which patches `appsettings.json` via `GenerateAppSettings.ps1` and deploys via a generated Web Deploy publish profile.

- Extending the toolkit:
  - Add a new `scripts/Deploy-<Provider>.ps1` for a hosting provider that isn't Web Deploy (e.g. plain FTP, Azure App Service).
  - Add a corresponding reusable workflow under `.github/workflows/`.
  - Keep provider-specific and project-specific secrets in the consuming repository's GitHub Secrets/Environments — never hardcode them here.
