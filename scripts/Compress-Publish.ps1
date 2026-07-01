param(
    [string]$RepositoryRoot = (Get-Location).Path,
    [string]$Output = "artifacts"
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
. "$scriptRoot/Helpers.ps1"

Write-Host ""
Write-Host "========== Compress Publish =========="
Write-Info "Repository Root : $RepositoryRoot"
Write-Info "Output          : $Output"
Write-Host "======================================"
Write-Host ""

$outputDir = Join-Path $RepositoryRoot $Output
$publishDir = Join-Path $outputDir "publish"
$zipPath = Join-Path $outputDir "publish.zip"

if (!(Test-Path $publishDir)) {
    Write-ErrorLog "Publish directory not found: $publishDir"
}

Write-Info "Publish Directory:"
Write-Host "       $publishDir"

if (Test-Path $zipPath) {
    Write-Info "Removing existing publish.zip..."
    Remove-Item $zipPath -Force
}

Write-Info "Creating publish.zip..."

Compress-PublishArtifact `
    -SourceDir $publishDir `
    -DestinationZip $zipPath

$file = Get-Item $zipPath

Write-Host ""
Write-Success "publish.zip created successfully."

Write-Info "Zip File:"
Write-Host "       $zipPath"

Write-Info "Package Size:"
Write-Host ("       {0:N2} MB" -f ($file.Length / 1MB))