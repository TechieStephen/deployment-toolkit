param(
    [Parameter(Mandatory)]
    [string]$ToolkitRoot,

    [string]$RepositoryRoot = (Get-Location).Path,

    [string]$Project,

    [string]$AppSettingsPath
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

. (Join-Path $scriptRoot "Helpers.ps1")
. (Join-Path $scriptRoot "ConfigHelpers.ps1")

Write-Host ""
Write-Host "===== Generate AppSettings ====="

Write-Info "Repository Root : $RepositoryRoot"
Write-Info "Toolkit Root    : $ToolkitRoot"

#
# Locate Web Project
#
$Project = Get-WebProject `
    -RepositoryRoot $RepositoryRoot `
    -Project $Project

Write-Success "Project:"
Write-Host "       $Project"

#
# Locate appsettings.json
#
if (-not $AppSettingsPath) {

    $AppSettingsPath = Join-Path `
        $RepositoryRoot `
        "artifacts\publish\appsettings.json"
}

if (!(Test-Path $AppSettingsPath)) {
    throw "appsettings.json not found: $AppSettingsPath"
}

Write-Info "Loading appsettings.json..."

$appSettings = Read-AppSettings `
    -Path $AppSettingsPath

Write-Success "appsettings.json loaded."

#
# Load configuration mapping
#
$configFile = Join-Path `
    $RepositoryRoot `
    "deployment\appsettings.config.ps1"

if (!(Test-Path $configFile)) {
    throw "Configuration mapping not found: $configFile"
}

Write-Info "Loading configuration mapping..."

. $configFile

Write-Success "Configuration mapping loaded."

#
# Apply environment variables
#
Write-Info "Applying configuration..."

foreach ($mapping in $configMap.GetEnumerator()) {

    $jsonPath = $mapping.Key
    $environmentVariable = $mapping.Value
    $value = Get-EnvironmentVariable -Name $environmentVariable

    if ([string]::IsNullOrWhiteSpace($value)) {
        Write-WarningLog "[CONFIG] $jsonPath => $environmentVariable : MISSING, skipping update."
        continue
    }

    Write-Host "[CONFIG] $jsonPath => $environmentVariable = $value"

    Set-ConfigValue `
        -Object $appSettings `
        -Path $jsonPath `
        -Value $value | Out-Null
}

#
# Save
#
Write-Info "Saving appsettings.json..."

Save-AppSettings `
    -AppSettings $appSettings `
    -Path $AppSettingsPath

Write-Success "appsettings.json updated successfully."

return $AppSettingsPath