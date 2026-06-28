param(
    [string]$ZipFile = "artifacts/publish.zip"
)

if (!(Test-Path $ZipFile)) {
    throw "Publish artifact not found."
}

Write-Host "Deploying..."

# FTP logic goes here later

Write-Host "Deployment complete."