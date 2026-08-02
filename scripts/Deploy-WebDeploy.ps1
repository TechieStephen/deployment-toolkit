param(
    [Parameter(Mandatory)]
    [string]$RepositoryRoot,

    [string]$ToolkitRoot,

    [Parameter()]
    [string]$Project,

    [string]$PublishDirectory = "artifacts\publish"
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
$msDeployPath = Get-MSDeploy

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
# Sync the already-published output straight to the Web Deploy target via
# msdeploy.exe directly. This deploys exactly what Publish.ps1 already
# built and zipped -- no rebuild, no dependency on bin/obj state carrying
# over from a different job/runner (dotnet publish /p:NoBuild=true still
# needs an intact obj\...\staticwebassets.build.json from the original
# build, which a freshly checked-out deploy job never has).
#
$msDeployUrl = Get-RequiredEnvironmentVariable "MSDEPLOY_URL"
$msDeploySite = Get-RequiredEnvironmentVariable "MSDEPLOY_SITE"
$msDeployUsername = Get-RequiredEnvironmentVariable "MSDEPLOY_USERNAME"
$msDeployPassword = Get-RequiredEnvironmentVariable "MSDEPLOY_PASSWORD"

$siteUrl = Get-EnvironmentVariable "SITE_URL"

Write-Host ""
Write-Host "===== Deploying ====="

if ($siteUrl) {
    Write-Info "Site: $siteUrl"
}

$sourceArg = "-source:contentPath=$publishPath"
$destArg = "-dest:contentPath=$msDeploySite,computerName=$msDeployUrl,userName=$msDeployUsername,password=$msDeployPassword,authtype=Basic"

& $msDeployPath `
    -verb:sync `
    $sourceArg `
    $destArg `
    -allowUntrusted `
    -enableRule:DoNotDeleteRule `
    -enableRule:AppOffline

if ($LASTEXITCODE -ne 0) {
    throw "Deployment failed."
}

Write-Success "Deployment completed successfully."
