<#
.SYNOPSIS
    Deploys the Polyglot Shop application to the Kubernetes cluster.
    Runs from your Windows terminal. It connects to your AWS Master Node via SSH
    so you do NOT need kubectl installed on Windows!

.PARAMETER DockerHubUsername
    Your Docker Hub username.
.PARAMETER MasterIP
    The public IP of your AWS EC2 Master Node (default: 13.49.245.123).
.PARAMETER KeyPath
    Path to your AWS EC2 private key file (.pem).
.PARAMETER SSHUser
    SSH username for your EC2 instance (e.g., "ubuntu" or "ec2-user").
.PARAMETER DirectKubectl
    Switch to use local kubectl instead of SSH if you have kubectl configured locally.

.EXAMPLE
    .\scripts\deploy-k8s.ps1 -DockerHubUsername "plaethos" -KeyPath "C:\keys\my-k8s-key.pem"
#>
param (
    [Parameter(Mandatory=$false)]
    [string]$DockerHubUsername = "",

    [Parameter(Mandatory=$false)]
    [string]$MasterIP = "13.49.245.123",

    [Parameter(Mandatory=$false)]
    [string]$KeyPath = "",

    [Parameter(Mandatory=$false)]
    [string]$SSHUser = "ubuntu",

    [Parameter(Mandatory=$false)]
    [switch]$DirectKubectl
)

$ErrorActionPreference = "Stop"

if (-not $DockerHubUsername) {
    $DockerHubUsername = Read-Host "Enter your Docker Hub username"
}

if (-not $DockerHubUsername) {
    Write-Error "Docker Hub username is required."
    exit 1
}

$namespace = "retail-store"

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║      🚀 Deploying Polyglot Shop to K8s           ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host "  Docker Hub Username: $DockerHubUsername" -ForegroundColor Yellow
Write-Host "  Master Node IP:      $MasterIP" -ForegroundColor Yellow
Write-Host ""

if ($DirectKubectl) {
    Write-Host "Using local kubectl on Windows..." -ForegroundColor Cyan
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $repoRoot = Split-Path -Parent $scriptDir
    $manifestDir = Join-Path $repoRoot "deployment-me\k8s"

    kubectl apply -f (Join-Path $manifestDir "00-namespace.yaml")
    kubectl apply -f (Join-Path $manifestDir "01-secrets.yaml")
    kubectl apply -f (Join-Path $manifestDir "10-rabbitmq.yaml")
    kubectl apply -f (Join-Path $manifestDir "22-postgres.yaml")
    kubectl apply -f (Join-Path $manifestDir "30-redis.yaml")
    kubectl apply -f (Join-Path $manifestDir "31-mariadb.yaml")
    kubectl apply -f (Join-Path $manifestDir "32-carts-db.yaml")

    $microservices = @("40-catalog.yaml", "41-orders.yaml", "42-cart.yaml", "43-checkout.yaml", "50-ui.yaml")
    foreach ($file in $microservices) {
        $path = Join-Path $manifestDir $file
        $content = Get-Content $path -Raw
        $content = $content -replace "YOUR_DOCKERHUB_USERNAME", $DockerHubUsername
        $content | kubectl apply -f -
    }

    $nodePort = kubectl -n $namespace get svc ui -o jsonpath='{.spec.ports[0].nodePort}' 2>$null
    Write-Host ""
    Write-Host "Deployment complete! Access at: http://${MasterIP}:${nodePort}" -ForegroundColor Green
    exit 0
}

# Default mode: Deploy via SSH to Master Node (No kubectl required on Windows!)
if (-not $KeyPath) {
    $KeyPath = Read-Host "Enter the path to your AWS .pem private key (or press Enter to try default SSH key)"
}

$sshTarget = "${SSHUser}@${MasterIP}"
Write-Host "Connecting to AWS Master Node ($sshTarget) via SSH..." -ForegroundColor Cyan

$remoteCommands = @"
set -e
echo '==> Cloning/updating repository on master node...'
if [ ! -d "polyglot-shop-k8s-cicd" ]; then
    git clone https://github.com/plaethos99/polyglot-shop-k8s-cicd.git
fi
cd polyglot-shop-k8s-cicd
git fetch --all
git reset --hard origin/main

echo '==> Running deployment...'
chmod +x scripts/deploy-k8s.sh
./scripts/deploy-k8s.sh $DockerHubUsername
"@

if ($KeyPath -and (Test-Path $KeyPath)) {
    ssh -i "$KeyPath" -o StrictHostKeyChecking=no "$sshTarget" "$remoteCommands"
} else {
    ssh -o StrictHostKeyChecking=no "$sshTarget" "$remoteCommands"
}

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
Write-Host "✅ Deployment finished on your AWS Kubernetes cluster!" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
Write-Host ""
