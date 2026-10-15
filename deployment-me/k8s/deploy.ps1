# ═══════════════════════════════════════════════════════════════════════════════
# deploy.ps1 — Deploy Retail Store to kubeadm cluster (Windows PowerShell)
#
# PREREQUISITES (install once):
#   1. kubectl for Windows → https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/
#   2. Copy your kubeconfig from the master node:
#      On master node:  cat ~/.kube/config
#      On Windows: paste into C:\Users\<you>\.kube\config
#      Then test with:  kubectl get nodes
#
# BEFORE RUNNING:
#   Edit the DOCKERHUB_USERNAME variable below with your Docker Hub username
#   Then run from PowerShell:  .\deploy.ps1
# ═══════════════════════════════════════════════════════════════════════════════

# ─── CONFIG — CHANGE THIS ──────────────────────────────────────────────────────
$DOCKERHUB_USERNAME = "YOUR_DOCKERHUB_USERNAME"    # ← put your Docker Hub username here
$NAMESPACE          = "retail-store"
$MANIFEST_DIR       = "$PSScriptRoot"              # same folder as this script
# ───────────────────────────────────────────────────────────────────────────────

# Stop on any error
$ErrorActionPreference = "Stop"

# ─── HELPER FUNCTIONS ──────────────────────────────────────────────────────────
function Write-Step($msg)  { Write-Host "`n$msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "   ✅ $msg" -ForegroundColor Green }
function Write-Fail($msg)  { Write-Host "   ❌ $msg" -ForegroundColor Red; exit 1 }
function Write-Wait($msg)  { Write-Host "   ⏳ $msg" -ForegroundColor Yellow }

# ─── VALIDATE ─────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║   Retail Store — kubeadm Deployment (Windows)   ║" -ForegroundColor Magenta
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Magenta
Write-Host ""

if ($DOCKERHUB_USERNAME -eq "YOUR_DOCKERHUB_USERNAME") {
    Write-Fail "Please edit deploy.ps1 and set your DOCKERHUB_USERNAME at the top of the file."
}

# Check kubectl is installed
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Fail "kubectl not found. Install it from: https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/"
}

# Check cluster is reachable
Write-Wait "Checking cluster connectivity..."
kubectl cluster-info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Fail "kubectl cannot reach the cluster. Make sure your kubeconfig is set correctly. Run: kubectl get nodes"
}

Write-Ok "Cluster is reachable"
Write-Ok "Docker Hub username: $DOCKERHUB_USERNAME"

# ─── PATCH IMAGE NAMES ────────────────────────────────────────────────────────
Write-Step "🔧 Patching image names in manifests..."
$yamlFiles = Get-ChildItem -Path $MANIFEST_DIR -Filter "*.yaml"
foreach ($file in $yamlFiles) {
    (Get-Content $file.FullName) -replace "YOUR_DOCKERHUB_USERNAME", $DOCKERHUB_USERNAME |
        Set-Content $file.FullName
}
Write-Ok "Image names patched → $DOCKERHUB_USERNAME/<service>:latest"

# ─── NAMESPACE + SECRETS ──────────────────────────────────────────────────────
Write-Step "📦 Step 1 — Creating namespace..."
kubectl apply -f "$MANIFEST_DIR\00-namespace.yaml"
Write-Ok "Namespace '$NAMESPACE' ready"

Write-Step "🔑 Step 2 — Applying secrets..."
kubectl apply -f "$MANIFEST_DIR\01-secrets.yaml"
Write-Ok "Secrets applied"

# ─── INFRASTRUCTURE ───────────────────────────────────────────────────────────
Write-Step "🐰 Step 3 — Deploying RabbitMQ..."
kubectl apply -f "$MANIFEST_DIR\10-rabbitmq.yaml"

Write-Step "🐘 Step 4 — Deploying PostgreSQL (orders-db)..."
kubectl apply -f "$MANIFEST_DIR\22-postgres.yaml"

Write-Step "🟥 Step 5 — Deploying Redis (checkout-redis)..."
kubectl apply -f "$MANIFEST_DIR\30-redis.yaml"

Write-Step "🦭 Step 6 — Deploying MariaDB (catalog-db)..."
kubectl apply -f "$MANIFEST_DIR\31-mariadb.yaml"

Write-Step "🗄️  Step 7 — Deploying DynamoDB Local (carts-db)..."
kubectl apply -f "$MANIFEST_DIR\32-carts-db.yaml"

# ─── WAIT FOR DATABASES ───────────────────────────────────────────────────────
Write-Host ""
Write-Host "⏳ Waiting for databases to be ready (2-3 minutes)..." -ForegroundColor Yellow

Write-Wait "Waiting for RabbitMQ..."
kubectl -n $NAMESPACE rollout status statefulset/rabbitmq --timeout=300s
Write-Ok "RabbitMQ ready"

Write-Wait "Waiting for PostgreSQL..."
kubectl -n $NAMESPACE rollout status statefulset/orders-db --timeout=300s
Write-Ok "PostgreSQL ready"

Write-Wait "Waiting for Redis..."
kubectl -n $NAMESPACE rollout status statefulset/checkout-redis --timeout=300s
Write-Ok "Redis ready"

Write-Wait "Waiting for MariaDB..."
kubectl -n $NAMESPACE rollout status statefulset/catalog-db --timeout=300s
Write-Ok "MariaDB ready"

Write-Wait "Waiting for DynamoDB Local..."
kubectl -n $NAMESPACE rollout status deployment/carts-db --timeout=300s
Write-Ok "DynamoDB Local ready"

# ─── MICROSERVICES ────────────────────────────────────────────────────────────
Write-Step "🔵 Step 8  — Deploying Catalog (Go)..."
kubectl apply -f "$MANIFEST_DIR\40-catalog.yaml"

Write-Step "🟡 Step 9  — Deploying Orders (Java)..."
kubectl apply -f "$MANIFEST_DIR\41-orders.yaml"

Write-Step "🟢 Step 10 — Deploying Cart (Java)..."
kubectl apply -f "$MANIFEST_DIR\42-cart.yaml"

Write-Step "🟠 Step 11 — Deploying Checkout (Node.js)..."
kubectl apply -f "$MANIFEST_DIR\43-checkout.yaml"

Write-Step "🔴 Step 12 — Deploying UI (Java)..."
kubectl apply -f "$MANIFEST_DIR\50-ui.yaml"

# ─── WAIT FOR MICROSERVICES ───────────────────────────────────────────────────
Write-Host ""
Write-Host "⏳ Waiting for microservices to be ready..." -ForegroundColor Yellow

kubectl -n $NAMESPACE rollout status deployment/catalog  --timeout=300s; Write-Ok "Catalog ready"
kubectl -n $NAMESPACE rollout status deployment/orders   --timeout=300s; Write-Ok "Orders ready"
kubectl -n $NAMESPACE rollout status deployment/cart     --timeout=300s; Write-Ok "Cart ready"
kubectl -n $NAMESPACE rollout status deployment/checkout --timeout=300s; Write-Ok "Checkout ready"
kubectl -n $NAMESPACE rollout status deployment/ui       --timeout=300s; Write-Ok "UI ready"

# ─── SUMMARY ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║            🎉 Deployment Complete!               ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

Write-Host "All pods:" -ForegroundColor Cyan
kubectl -n $NAMESPACE get pods

Write-Host ""
Write-Host "UI Service:" -ForegroundColor Cyan
kubectl -n $NAMESPACE get svc ui

# Grab NodePort automatically
$nodePort = kubectl -n $NAMESPACE get svc ui -o jsonpath='{.spec.ports[0].nodePort}' 2>$null
$nodeIP   = kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>$null

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
Write-Host "  🌐 Open in your browser:" -ForegroundColor Green
Write-Host "     http://$($nodeIP):$($nodePort)" -ForegroundColor White
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
Write-Host ""
