<#
.SYNOPSIS
    Builds all 5 microservice Docker images locally and pushes them to Docker Hub.
.PARAMETER DockerHubUsername
    Your Docker Hub username.
.EXAMPLE
    .\scripts\build-and-push.ps1 -DockerHubUsername "plaethos"
#>
param (
    [Parameter(Mandatory=$false)]
    [string]$DockerHubUsername = ""
)

$ErrorActionPreference = "Stop"

if (-not $DockerHubUsername) {
    $DockerHubUsername = Read-Host "Enter your Docker Hub username"
}

if (-not $DockerHubUsername) {
    Write-Error "Docker Hub username is required."
    exit 1
}

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   🐳 Building & Pushing Images to Docker Hub     ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host "  Docker Hub User: $DockerHubUsername" -ForegroundColor Yellow
Write-Host ""

# Verify docker is running
try {
    docker info 2>$null | Out-Null
} catch {
    Write-Error "Docker Desktop daemon is not running. Please start Docker first."
    exit 1
}

$services = @("catalog", "orders", "cart", "checkout", "ui")
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir

foreach ($service in $services) {
    $imageName = "$DockerHubUsername/${service}:latest"
    $contextDir = Join-Path $repoRoot "src\$service"

    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    Write-Host "📦 [1/2] Building image: $imageName" -ForegroundColor Cyan
    Write-Host "         Context: $contextDir" -ForegroundColor DarkGray
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray

    docker build -t $imageName $contextDir
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to build image $imageName"
        exit 1
    }

    Write-Host ""
    Write-Host "🚀 [2/2] Pushing image: $imageName" -ForegroundColor Green
    docker push $imageName
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to push image $imageName. Make sure you are logged in via 'docker login'."
        exit 1
    }

    Write-Host "✅ Successfully pushed $imageName" -ForegroundColor Green
}

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║   🎉 All 5 Images Pushed to Docker Hub!         ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Green
foreach ($service in $services) {
    Write-Host "  ✔ $DockerHubUsername/${service}:latest" -ForegroundColor White
}
Write-Host ""
