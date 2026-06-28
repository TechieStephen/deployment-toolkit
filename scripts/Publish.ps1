param(
    [string]$Project,
    [string]$Configuration = "Release",
    [string]$Output = "artifacts",
    [switch]$SkipZip
)

$ErrorActionPreference = "Stop"

Write-Host "Searching for ASP.NET Core project..."

if (-not $Project) {

    $projects = Get-ChildItem -Recurse -Filter *.csproj

    $webProjects = @()

    foreach ($proj in $projects) {

        $content = Get-Content $proj.FullName -Raw

        if ($content -match "Microsoft.NET.Sdk.Web") {
            $webProjects += $proj.FullName
        }
    }

    if ($webProjects.Count -eq 0) {
        throw "No ASP.NET Core Web project found."
    }

    if ($webProjects.Count -gt 1) {

        Write-Host ""
        Write-Host "Multiple Web projects found:"
        $webProjects | ForEach-Object { Write-Host "- $_" }

        throw "Specify -Project."
    }

    $Project = $webProjects[0]
}

Write-Host "Publishing:"
Write-Host $Project

dotnet restore $Project

dotnet publish `
    $Project `
    -c $Configuration `
    -o "$Output/publish" `
    --no-restore

if (-not $SkipZip) {

    Compress-Archive `
        -Path "$Output/publish/*" `
        -DestinationPath "$Output/publish.zip" `
        -Force
}

Write-Host "Done."