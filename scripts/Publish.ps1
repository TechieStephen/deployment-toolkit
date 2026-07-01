param(
    [string]$Project,
    [string]$RepositoryRoot = (Get-Location).Path,
    [string]$Configuration = "Release",
    [string]$Output = "artifacts",

    [string]$Runtime,
    [switch]$SelfContained,
    [string]$Environment = "Production",
    [switch]$EnableStdOutLog,
    [string]$Project
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
. "$scriptRoot/Helpers.ps1"

Write-Host ""
Write-Host "========== Publish =========="
Write-Info "Repository Root : $RepositoryRoot"
Write-Info "Configuration   : $Configuration"
Write-Info "Output          : $Output"
Write-Info "Environment     : $Environment"

if ($Runtime) {
    Write-Info "Runtime         : $Runtime"
}

Write-Info "SelfContained   : $SelfContained"
Write-Info "StdOut Log      : $EnableStdOutLog"
Write-Host "============================="
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

$outputDir = Join-Path $RepositoryRoot $Output

if (!(Test-Path $outputDir)) {
    Write-Info "Creating output directory..."
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

$publishDir = Join-Path $outputDir "publish"

if (Test-Path $publishDir) {
    Write-Info "Cleaning previous publish output..."
    Remove-Item $publishDir -Recurse -Force
}

Write-Info "Restoring NuGet packages..."

dotnet restore "$Project"

if ($LASTEXITCODE -ne 0) {
    Write-ErrorLog "Package restore failed."
}

$publishArgs = @(
    "publish"
    $Project
    "-c"
    $Configuration
    "-o"
    $publishDir
    "--no-restore"
)

if ($Runtime) {
    $publishArgs += @(
        "-r"
        $Runtime
    )
}

if ($SelfContained) {
    $publishArgs += "--self-contained"
}
else {
    $publishArgs += "--no-self-contained"
}

$publishArgs += "/p:EnvironmentName=$Environment"

if ($EnableStdOutLog) {
    $publishArgs += "/p:AspNetCoreHostedModeStdoutLogEnabled=true"
}

Write-Info "Publishing application..."

& dotnet $publishArgs

if ($LASTEXITCODE -ne 0) {
    Write-ErrorLog "Publish failed."
}

Write-Host ""
Write-Success "Publish completed successfully."

Write-Info "Publish Directory:"
Write-Host "       $publishDir"

return $publishDir