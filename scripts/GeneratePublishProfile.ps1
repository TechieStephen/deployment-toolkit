param(
    [Parameter(Mandatory)]
    [string]$RepositoryRoot,

    [Parameter(Mandatory)]
    [string]$ToolkitRoot,

    [Parameter(Mandatory)]
    [string]$AppName,

    [Parameter()]
    [string]$Project,

    [string]$ProfileName = "WebDeploy"
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent

. "$scriptRoot/Helpers.ps1"

Write-Host ""
Write-Host "===== Generate Publish Profile ====="

Write-Info "Repository Root : $RepositoryRoot"
Write-Info "Toolkit Root    : $ToolkitRoot"
Write-Info "Application     : $AppName"
Write-Info "Profile Name    : $ProfileName"

$templatePath = Join-Path `
    $ToolkitRoot `
    "/templates/WebDeploy.pubxml"

if (!(Test-Path $templatePath)) {
    Write-ErrorLog "Template not found: $templatePath"
}

Write-Info "Loading template..."

$content = Get-Content $templatePath -Raw

$prefix = $AppName.ToUpper()

$replacements = @{
    "__SITE_URL__"          = [Environment]::GetEnvironmentVariable("${prefix}_SITE_URL")
    "__MSDEPLOY_URL__"      = [Environment]::GetEnvironmentVariable("${prefix}_MSDEPLOY_URL")
    "__MSDEPLOY_SITE__"     = [Environment]::GetEnvironmentVariable("${prefix}_MSDEPLOY_SITE")
    "__MSDEPLOY_USERNAME__" = [Environment]::GetEnvironmentVariable("${prefix}_MSDEPLOY_USERNAME")
    "__MSDEPLOY_PASSWORD__" = [Environment]::GetEnvironmentVariable("${prefix}_MSDEPLOY_PASSWORD")
}

Write-Info "Applying deployment configuration..."

foreach ($item in $replacements.GetEnumerator()) {

    if ([string]::IsNullOrWhiteSpace($item.Value)) {
        Write-ErrorLog ("Required deployment setting '{0}' is not configured." -f $item.Key)
    }

    Write-Info ("Mapping '{0}'." -f $item.Key)

    $content = $content.Replace(
        $item.Key,
        $item.Value
    )
}

$project = Get-WebProject `
    -RepositoryRoot $RepositoryRoot `
    -Project $Project

$projectDirectory = Split-Path `
    $project `
    -Parent

$publishProfilesDir = Join-Path `
    $projectDirectory `
    "Properties\PublishProfiles"

if (!(Test-Path $publishProfilesDir)) {

    Write-Info "Creating PublishProfiles directory..."

    New-Item `
        -ItemType Directory `
        -Force `
        -Path $publishProfilesDir | Out-Null
}

$profilePath = Join-Path `
    $publishProfilesDir `
    "$ProfileName.pubxml"

Write-Info "Writing publish profile..."

Set-Content `
    -Path $profilePath `
    -Value $content `
    -Encoding UTF8

Write-Success "Publish profile generated successfully."

Write-Info "Publish Profile:"
Write-Host "       $profilePath"

return $profilePath