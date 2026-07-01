param(
    [Parameter(Mandatory)]
    [string]$ToolkitRoot,

    [string]$RepositoryRoot = (Get-Location).Path,

    [string]$Project,

    [string]$AppSettingsPath
)

$ErrorActionPreference = "Stop"

$toolkitScripts = Join-Path $ToolkitRoot "scripts"

. (Join-Path $toolkitScripts "Helpers.ps1")
. (Join-Path $toolkitScripts "ConfigHelpers.ps1")

Write-Host ""
Write-Host "========== Build AppSettings =========="
Write-Info "Repository Root : $RepositoryRoot"
Write-Info "Toolkit Root    : $ToolkitRoot"
Write-Host "======================================="
Write-Host ""

Write-Info "Locating ASP.NET Core Web project..."

if (-not $Project) {
    $Project = Get-WebProject -RepositoryRoot $RepositoryRoot
}
else {
    $Project = Get-WebProject `
        -RepositoryRoot $RepositoryRoot `
        -Project $Project
}

Write-Info "Web Project:"
Write-Host "       $Project"

if (-not $AppSettingsPath) {

    $publishDir = Join-Path $RepositoryRoot "artifacts\publish"
    $AppSettingsPath = Join-Path $publishDir "appsettings.json"
}

if (!(Test-Path $AppSettingsPath)) {
    Write-ErrorLog "appsettings.json not found: $AppSettingsPath"
}

Write-Info "Loading appsettings.json..."

$appSettings = Read-AppSettings -Path $AppSettingsPath

Write-Success "appsettings.json loaded."

$configFile = Join-Path $RepositoryRoot "deployment\appsettings.config.ps1"

if (!(Test-Path $configFile)) {
    Write-ErrorLog "Configuration file not found: $configFile"
}

Write-Info "Loading configuration mapping..."

. $configFile

Write-Success "Configuration mapping loaded."

Write-Info "Applying configuration..."

foreach ($mapping in $configMap.GetEnumerator()) {

    $jsonPath = $mapping.Key
    $environmentVariable = $mapping.Value

    # Write-Info ("Mapping '{0}' <- '{1}'." -f $jsonPath, $environmentVariable)

    $value = [Environment]::GetEnvironmentVariable($environmentVariable)

    $updated = Set-ConfigValue `
        -Object $appSettings `
        -Path $jsonPath `
        -Value $value

    if ($updated) {
        # Write-Success ("Updated '{0}'." -f $jsonPath)
    }
}

Write-Info "Saving appsettings.json..."

Save-AppSettings `
    -AppSettings $appSettings `
    -Path $AppSettingsPath

Write-Success "appsettings.json updated successfully."

return $AppSettingsPath