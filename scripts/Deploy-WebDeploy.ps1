param(
    [Parameter(Mandatory)]
    [string]$RepositoryRoot,

    [string]$ToolkitRoot,

    [Parameter()]
    [string]$Project,

    [string]$Configuration = "Release",

    [string]$PublishDirectory = "artifacts\publish",

    [string]$ProfileName = "WebDeploy"
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if ([string]::IsNullOrWhiteSpace($ToolkitRoot)) {
    $ToolkitRoot = Split-Path -Parent $scriptRoot
}

. (Join-Path $scriptRoot "Helpers.ps1")

Write-Host ""
Write-Host "===== Deploy WebDeploy ====="

Write-Info "Repository Root : $RepositoryRoot"
Write-Info "Toolkit Root    : $ToolkitRoot"

#
# Ensure Web Deploy is available before doing any work
#
Get-MSDeploy | Out-Null

#
# Locate project
#
$Project = Get-WebProject `
    -RepositoryRoot $RepositoryRoot `
    -Project $Project

Write-Success "Project:"
Write-Host "       $Project"

#
# Ensure publish directory exists
#
$publishPath = Join-Path `
    $RepositoryRoot `
    $PublishDirectory

if (!(Test-Path $publishPath)) {
    throw "Publish directory not found: $publishPath"
}

#
# Update published appsettings.json in the prepared publish output.
#
& (Join-Path $scriptRoot "GenerateAppSettings.ps1") `
    -ToolkitRoot $ToolkitRoot `
    -RepositoryRoot $RepositoryRoot `
    -Project $Project `
    -AppSettingsPath (Join-Path $publishPath "appsettings.json")

#
# Generate Publish Profile using the prepared publish output as the deployment payload.
#
$publishProfile = & (Join-Path $scriptRoot "GeneratePublishProfile.ps1") `
    -ToolkitRoot $ToolkitRoot `
    -RepositoryRoot $RepositoryRoot `
    -Project $Project `
    -ProfileName $ProfileName `
    -PublishDirectory $publishPath

try {

    Write-Host ""
    Write-Host "===== Deploying ====="

    dotnet publish `
        $Project `
        --configuration $Configuration `
        --output $publishPath `
        /p:PublishProfile=$ProfileName `
        /p:PublishDir=$publishPath `
        /p:NoBuild=true `
        /p:SkipBuild=true

    if ($LASTEXITCODE -ne 0) {
        throw "Deployment failed."
    }

    Write-Success "Deployment completed successfully."
}
finally {

    if (Test-Path $publishProfile) {

        Write-Info "Removing temporary publish profile..."

        Remove-Item `
            $publishProfile `
            -Force
    }
}