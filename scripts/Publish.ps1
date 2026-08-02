param(
    [Parameter(Mandatory)]
    [string]$RepositoryRoot,

    [string]$ToolkitRoot,

    [string]$Project,

    [string]$Configuration = "Release",

    [string]$Output = "artifacts/publish",

    [switch]$SkipZip
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

. (Join-Path $scriptRoot "Helpers.ps1")

Write-Host ""
Write-Host "===== Publish Application ====="

Write-Info "Repository Root : $RepositoryRoot"
Write-Info "Configuration   : $Configuration"
Write-Info "Output          : $Output"

#
# Locate project
#
$Project = Get-WebProject `
    -RepositoryRoot $RepositoryRoot `
    -Project $Project

Write-Success "Project:"
Write-Host "       $Project"

#
# Prepare publish directory
#
$publishOutput = Join-Path `
    $RepositoryRoot `
    $Output

New-CleanDirectory `
    -Path $publishOutput

#
# Publish
#
Write-Host ""
Write-Host "===== dotnet restore ====="

dotnet restore $Project

if ($LASTEXITCODE -ne 0) {
    throw "dotnet restore failed."
}

Write-Host "===== dotnet publish ====="

dotnet publish `
    $Project `
    --configuration $Configuration `
    --output $publishOutput

if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish failed."
}

Write-Success "Publish completed."

#
# Generate appsettings.json in publish output
#
Write-Host ""
Write-Host "===== Generate AppSettings ====="

& (Join-Path $scriptRoot "GenerateAppSettings.ps1") `
    -ToolkitRoot $ToolkitRoot `
    -RepositoryRoot $RepositoryRoot `
    -Project $Project `
    -AppSettingsPath (Join-Path $publishOutput "appsettings.json")

#
# Compress
#
if (-not $SkipZip) {

    Write-Host ""
    Write-Host "===== Compress Publish ====="

    & (Join-Path $scriptRoot "Compress-Publish.ps1") `
        -RepositoryRoot $RepositoryRoot `
        -Output "artifacts"
}

Write-Host ""
Write-Success "Publish finished successfully."

return $publishOutput