deployment-toolkit/
├── .git/ (repo metadata)
├── .github/
│   └── workflows/
│       ├── DeployToIIS.yml        # reusable workflow: publish -> Deploy-IIS.ps1
│       └── DeployToSmarterASP.yml # reusable workflow: publish -> Deploy-SmarterASP.ps1
├── docs/
│   ├── README.md                  # docs index and guidance
│   ├── Build-AppSettings.sample.ps1 # sample merge-based Build-AppSettings script
│   └── STRUCTURE.md               # this file
├── scripts/
│   ├── Publish.ps1                # discover web project, publish to artifacts/publish and create publish.zip
│   ├── Deploy-SmarterASP.ps1      # deploy publish.zip via FTP to SmarterASP
│   ├── Deploy-IIS.ps1             # copy published files to an IIS physical path
│   └── Helpers.ps1                # shared functions: Get-WebProject, Compress-PublishArtifact
├── README.md                      # repository overview and usage
├── NOTE.md
└── (other files)

Notes
- Artifact output (standard):

  artifacts/
  ├── publish/     # published files (dotnet publish -o)
  └── publish.zip  # compressed artifact used for deployment

- Recommended per-backend repo layout:

  my-backend-repo/
  ├── src/
  ├── appsettings.json             # base configuration (kept in repo)
  └── deployment/
      └── Build-AppSettings.ps1    # repo-specific script that merges secrets/overrides into deployment/appsettings.{Environment}.json

- How the flow works (high level):

  1. Backend repo CI checks out code and runs `deployment/Build-AppSettings.ps1` to produce merged appsettings
  2. CI calls `deployment-toolkit` workflow to `./scripts/Publish.ps1` (build & package)
  3. CI calls provider-specific `Deploy-<Provider>.ps1` to deploy the artifact

- Extending the toolkit:
  - Add new `scripts/Deploy-<Provider>.ps1` for each hosting provider
  - Add a corresponding reusable workflow under `.github/workflows/`
  - Keep provider-specific secrets in the consuming repository's GitHub Secrets
