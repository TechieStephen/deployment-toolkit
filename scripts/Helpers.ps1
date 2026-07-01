function Get-WebProject {

    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot,

        [string]$Project
    )

    if ($Project) {

        $projectPath = Join-Path $RepositoryRoot $Project

        if (!(Test-Path $projectPath)) {
            Write-ErrorLog "Project not found: $projectPath"
        }

        $content = Get-Content $projectPath -Raw

        if ($content -notmatch "Microsoft.NET.Sdk.Web") {
            Write-ErrorLog "Specified project is not an ASP.NET Core Web project."
        }

        return (Resolve-Path $projectPath).Path
    }

    $projects = Get-ChildItem `
        -Path $RepositoryRoot `
        -Recurse `
        -Filter *.csproj

    $webProjects = @()

    foreach ($proj in $projects) {

        $content = Get-Content $proj.FullName -Raw

        if ($content -match "Microsoft.NET.Sdk.Web") {
            $webProjects += $proj.FullName
        }
    }

    switch ($webProjects.Count) {

        0 {
            Write-ErrorLog "No ASP.NET Core Web project found."
        }

        1 {
            return $webProjects[0]
        }

        default {

            Write-Host ""
            Write-WarningLog "Multiple ASP.NET Core Web projects found:"
            Write-Host ""

            $webProjects | ForEach-Object {
                Write-Host "- $_"
            }

            Write-ErrorLog @"
Multiple ASP.NET Core Web projects found.

Please specify which project to publish.

Example:
    .\Publish.ps1 -Project "src\examPro\examPro.csproj"
"@
        }
    }
}

function Compress-PublishArtifact {

    param(
        [Parameter(Mandatory)]
        [string]$SourceDir,

        [Parameter(Mandatory)]
        [string]$DestinationZip
    )

    if (!(Test-Path $SourceDir)) {
        Write-ErrorLog "Publish directory not found: $SourceDir"
    }

    if (Test-Path $DestinationZip) {
        Remove-Item $DestinationZip -Force
    }

    Compress-Archive `
        -Path "$SourceDir/*" `
        -DestinationPath $DestinationZip `
        -Force
}

function Get-MSDeploy {

    Write-Info "Searching for Web Deploy..."

    $command = Get-Command "msdeploy.exe" -ErrorAction SilentlyContinue

    if ($command) {
        Write-Success "Web Deploy found in PATH."
        return $command.Source
    }

    $locations = @(
        "C:\Program Files\IIS\Microsoft Web Deploy V3\msdeploy.exe",
        "C:\Program Files (x86)\IIS\Microsoft Web Deploy V3\msdeploy.exe"
    )

    foreach ($location in $locations) {

        if (Test-Path $location) {
            Write-Success "Web Deploy found."
            return $location
        }
    }

    Write-ErrorLog @"
Web Deploy (msdeploy.exe) was not found.

Ensure your GitHub workflow installs Microsoft Web Deploy before calling DeployWithWebDeploy.ps1.
"@
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message"
}

function Write-WarningLog {
    param([string]$Message)
    Write-Host "[WARNING] $Message"
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message"
}

function Write-ErrorLog {
    param([string]$Message)
    throw "[ERROR] $Message"
}


function Get-DeploymentSetting {
    param(
        [string]$AppName,
        [string]$Name
    )

    $variable = "$($AppName.ToUpper())_$Name"

    return [Environment]::GetEnvironmentVariable($variable)
}