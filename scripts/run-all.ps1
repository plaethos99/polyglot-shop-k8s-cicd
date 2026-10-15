<#
.SYNOPSIS
    End-to-End Pipeline runner on Windows:
    1. Builds and pushes all 5 microservice Docker images to Docker Hub.
    2. Deploys manifests to your AWS Kubernetes cluster (via SSH without needing kubectl on Windows!).
.PARAMETER DockerHubUsername
    Your Docker Hub username.
.PARAMETER MasterIP
    Your AWS EC2 Master Node public IP (default: 13.49.245.123).
.PARAMETER KeyPath
    Path to your AWS .pem private key for SSH access.
.PARAMETER SSHUser
    Username on EC2 instance (default: ubuntu).
.EXAMPLE
    .\scripts\run-all.ps1 -DockerHubUsername "plaethos" -KeyPath "C:\keys\aws.pem"
#>
param (
    [Parameter(Mandatory=$false)]
    [string]$DockerHubUsername = "",

    [Parameter(Mandatory=$false)]
    [string]$MasterIP = "13.49.245.123",

    [Parameter(Mandatory=$false)]
    [string]$KeyPath = "",

    [Parameter(Mandatory=$false)]
    [string]$SSHUser = "ubuntu"
)

$ErrorActionPreference = "Stop"

if (-not $DockerHubUsername) {
    $DockerHubUsername = Read-Host "Enter your Docker Hub username"
}

if (-not $KeyPath) {
    $KeyPath = Read-Host "Enter the path to your AWS .pem private key file"
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║      🔥 RUNNING END-TO-END PIPELINE              ║" -ForegroundColor Cyan
Write-Host "║   1. Build & Push Images to Docker Hub           ║" -ForegroundColor Cyan
Write-Host "║   2. Deploy to AWS Kubernetes Cluster (via SSH)  ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# STAGE 1: Build & Push
Write-Host "=========================================" -ForegroundColor Yellow
Write-Host "  STAGE 1: BUILD & PUSH DOCKER IMAGES    " -ForegroundColor Yellow
Write-Host "=========================================" -ForegroundColor Yellow
& (Join-Path $scriptDir "build-and-push.ps1") -DockerHubUsername $DockerHubUsername

# STAGE 2: Deploy to K8s
Write-Host ""
Write-Host "=========================================" -ForegroundColor Green
Write-Host "  STAGE 2: DEPLOY TO KUBERNETES CLUSTER  " -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
& (Join-Path $scriptDir "deploy-k8s.ps1") -DockerHubUsername $DockerHubUsername -MasterIP $MasterIP -KeyPath $KeyPath -SSHUser $SSHUser

Write-Host ""
Write-Host "🎉 Full Pipeline Execution Complete!" -ForegroundColor Green
Write-Host "Access your web shop in your browser at: http://${MasterIP}:<NodePort>" -ForegroundColor White
