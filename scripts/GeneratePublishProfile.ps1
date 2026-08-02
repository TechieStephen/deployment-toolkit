param(
    [Parameter(Mandatory)]
    [string]$RepositoryRoot,

    [string]$ToolkitRoot,

    [Parameter()]
    [string]$Project,

    [string]$ProfileName = "WebDeploy",

    [string]$PublishDirectory = "artifacts\publish"
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if ([string]::IsNullOrWhiteSpace($ToolkitRoot)) {
    $ToolkitRoot = Split-Path -Parent $scriptRoot
}

. "$scriptRoot/Helpers.ps1"

Write-Host ""
Write-Host "===== Generate Publish Profile ====="

Write-Info "Repository Root : $RepositoryRoot"
Write-Info "Toolkit Root    : $ToolkitRoot"
Write-Info "Profile Name    : $ProfileName"

$templatePath = Join-Path `
    $ToolkitRoot `
    "templates\WebDeploy.pubxml"

if (!(Test-Path $templatePath)) {
    $fallbackTemplatePath = Join-Path `
        (Split-Path -Parent $scriptRoot) `
        "templates\WebDeploy.pubxml"

    if (Test-Path $fallbackTemplatePath) {
        $templatePath = $fallbackTemplatePath
    }
    else {
        throw "Template not found: $templatePath"
    }
}

Write-Info "Loading template..."

$content = Get-Content `
    -Path $templatePath `
    -Raw

$resolvedPublishDirectory = if ([System.IO.Path]::IsPathRooted($PublishDirectory)) {
    $PublishDirectory
}
else {
    Join-Path $RepositoryRoot $PublishDirectory
}

$resolvedPublishDirectory = [System.IO.Path]::GetFullPath($resolvedPublishDirectory)

$replacements = @{
    "__SITE_URL__"          = Get-RequiredEnvironmentVariable "SITE_URL"
    "__MSDEPLOY_URL__"      = Get-RequiredEnvironmentVariable "MSDEPLOY_URL"
    "__MSDEPLOY_SITE__"     = Get-RequiredEnvironmentVariable "MSDEPLOY_SITE"
    "__MSDEPLOY_USERNAME__" = Get-RequiredEnvironmentVariable "MSDEPLOY_USERNAME"
    "__MSDEPLOY_PASSWORD__" = Get-RequiredEnvironmentVariable "MSDEPLOY_PASSWORD"
    "__PUBLISH_DIRECTORY__" = $resolvedPublishDirectory
}

Write-Info "Applying deployment configuration..."

foreach ($item in $replacements.GetEnumerator()) {

    if ([string]::IsNullOrWhiteSpace($item.Value)) {
        throw "Required deployment setting '$($item.Key)' is not configured."
    }

    Write-Info "Mapping '$($item.Key)'."

    $content = $content.Replace(
        $item.Key,
        $item.Value
    )
}

$project = Get-WebProject `
    -RepositoryRoot $RepositoryRoot `
    -Project $Project

$projectDirectory = Split-Path `
    -Path $project `
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