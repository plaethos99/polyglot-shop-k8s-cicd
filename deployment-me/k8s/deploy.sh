#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# deploy.sh — Deploy Retail Store to kubeadm cluster
#
# BEFORE RUNNING:
#   1. Replace YOUR_DOCKERHUB_USERNAME below with your actual Docker Hub username
#   2. Make this script executable:  chmod +x deploy.sh
#   3. Run it from this directory:   ./deploy.sh
# ═══════════════════════════════════════════════════════════════════════════════

set -e   # exit immediately if any command fails

# ─── CONFIG ────────────────────────────────────────────────────────────────────
DOCKERHUB_USERNAME="YOUR_DOCKERHUB_USERNAME"   # ← CHANGE THIS
MANIFEST_DIR="$(dirname "$0")/k8s"
NAMESPACE="retail-store"
# ───────────────────────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║   Retail Store — kubeadm Deployment Script       ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ── VALIDATE ──────────────────────────────────────────────────────────────────
if [ "$DOCKERHUB_USERNAME" = "YOUR_DOCKERHUB_USERNAME" ]; then
  echo "❌ ERROR: Please edit deploy.sh and set your DOCKERHUB_USERNAME"
  exit 1
fi

if ! kubectl cluster-info > /dev/null 2>&1; then
  echo "❌ ERROR: kubectl cannot reach the cluster. Is your kubeconfig set?"
  exit 1
fi

echo "✅ Cluster reachable"
echo "✅ Docker Hub username: $DOCKERHUB_USERNAME"
echo ""

# ── PATCH IMAGE NAMES ─────────────────────────────────────────────────────────
echo "🔧 Patching image names with Docker Hub username..."
for f in "$MANIFEST_DIR"/*.yaml; do
  sed -i "s|YOUR_DOCKERHUB_USERNAME|${DOCKERHUB_USERNAME}|g" "$f"
done
echo "   Done."
echo ""

# ── NAMESPACE ─────────────────────────────────────────────────────────────────
echo "📦 Step 1/10 — Creating namespace..."
kubectl apply -f "$MANIFEST_DIR/00-namespace.yaml"

echo "🔑 Step 2/10 — Applying secrets..."
kubectl apply -f "$MANIFEST_DIR/01-secrets.yaml"

# ── INFRASTRUCTURE ────────────────────────────────────────────────────────────
echo "🐰 Step 3/10 — Deploying RabbitMQ..."
kubectl apply -f "$MANIFEST_DIR/10-rabbitmq.yaml"

echo "🐘 Step 4/10 — Deploying PostgreSQL (orders-db)..."
kubectl apply -f "$MANIFEST_DIR/22-postgres.yaml"

echo "🟥 Step 5/10 — Deploying Redis (checkout-redis)..."
kubectl apply -f "$MANIFEST_DIR/30-redis.yaml"

echo "🦭 Step 6/10 — Deploying MariaDB (catalog-db)..."
kubectl apply -f "$MANIFEST_DIR/31-mariadb.yaml"

echo "🗄️  Step 7/10 — Deploying DynamoDB Local (carts-db)..."
kubectl apply -f "$MANIFEST_DIR/32-carts-db.yaml"

# ── WAIT FOR DATABASES ────────────────────────────────────────────────────────
echo ""
echo "⏳ Waiting for infrastructure to be ready (this takes 2-3 minutes)..."
kubectl -n $NAMESPACE rollout status statefulset/rabbitmq       --timeout=300s
echo "   ✅ RabbitMQ ready"
kubectl -n $NAMESPACE rollout status statefulset/orders-db      --timeout=300s
echo "   ✅ PostgreSQL ready"
kubectl -n $NAMESPACE rollout status statefulset/checkout-redis --timeout=300s
echo "   ✅ Redis ready"
kubectl -n $NAMESPACE rollout status statefulset/catalog-db     --timeout=300s
echo "   ✅ MariaDB ready"
kubectl -n $NAMESPACE rollout status deployment/carts-db        --timeout=300s
echo "   ✅ DynamoDB Local ready"
echo ""

# ── MICROSERVICES ─────────────────────────────────────────────────────────────
echo "🔵 Step 8/10  — Deploying Catalog (Go)..."
kubectl apply -f "$MANIFEST_DIR/40-catalog.yaml"

echo "🟡 Step 9/10  — Deploying Orders (Java)..."
kubectl apply -f "$MANIFEST_DIR/41-orders.yaml"

echo "🟢 Step 10/10 — Deploying Cart (Java)..."
kubectl apply -f "$MANIFEST_DIR/42-cart.yaml"

echo "🟠 Step 10/10 — Deploying Checkout (Node.js)..."
kubectl apply -f "$MANIFEST_DIR/43-checkout.yaml"

echo "🔴 Step 10/10 — Deploying UI (Java)..."
kubectl apply -f "$MANIFEST_DIR/50-ui.yaml"

# ── WAIT FOR MICROSERVICES ────────────────────────────────────────────────────
echo ""
echo "⏳ Waiting for microservices to be ready..."
kubectl -n $NAMESPACE rollout status deployment/catalog  --timeout=300s && echo "   ✅ Catalog ready"
kubectl -n $NAMESPACE rollout status deployment/orders   --timeout=300s && echo "   ✅ Orders ready"
kubectl -n $NAMESPACE rollout status deployment/cart     --timeout=300s && echo "   ✅ Cart ready"
kubectl -n $NAMESPACE rollout status deployment/checkout --timeout=300s && echo "   ✅ Checkout ready"
kubectl -n $NAMESPACE rollout status deployment/ui       --timeout=300s && echo "   ✅ UI ready"

# ── SUMMARY ───────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║            🎉 Deployment Complete!               ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

echo "All pods:"
kubectl -n $NAMESPACE get pods

echo ""
echo "UI Service (find your NodePort here):"
kubectl -n $NAMESPACE get svc ui

echo ""
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null || echo "<your-node-ip>")
NODE_PORT=$(kubectl -n $NAMESPACE get svc ui -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "<nodePort>")

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🌐 Open in browser:"
echo "     http://${NODE_IP}:${NODE_PORT}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
