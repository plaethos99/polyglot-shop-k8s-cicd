#!/usr/bin/env bash
# ==============================================================================
# SCRIPT 2: Deploy to Kubernetes Cluster (Run on Master Node or Linux)
# ==============================================================================
set -euo pipefail

DOCKERHUB_USERNAME="${1:-}"
NAMESPACE="retail-store"

if [ -z "$DOCKERHUB_USERNAME" ]; then
    read -rp "Enter your Docker Hub username: " DOCKERHUB_USERNAME
fi

if [ -z "$DOCKERHUB_USERNAME" ]; then
    echo "❌ Error: Docker Hub username is required."
    exit 1
fi

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║      🚀 Deploying Polyglot Shop to K8s           ║"
echo "╚══════════════════════════════════════════════════╝"
echo "  Docker Hub Username: $DOCKERHUB_USERNAME"
echo "  Namespace:           $NAMESPACE"
echo ""

# Find repository root & manifest directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST_DIR="${REPO_ROOT}/deployment-me/k8s"

if [ ! -d "$MANIFEST_DIR" ]; then
    echo "❌ Error: Manifest directory not found at $MANIFEST_DIR"
    exit 1
fi

# 1. Namespace
echo "==> [1/6] Namespace..."
kubectl apply -f "${MANIFEST_DIR}/00-namespace.yaml"

# 2. Secrets
echo "==> [2/6] Secrets..."
kubectl apply -f "${MANIFEST_DIR}/01-secrets.yaml"

# 3. Message Queue & Databases
echo "==> [3/6] Message Queue & Databases..."
kubectl apply -f "${MANIFEST_DIR}/10-rabbitmq.yaml"
kubectl apply -f "${MANIFEST_DIR}/22-postgres.yaml"
kubectl apply -f "${MANIFEST_DIR}/30-redis.yaml"
kubectl apply -f "${MANIFEST_DIR}/31-mariadb.yaml"
kubectl apply -f "${MANIFEST_DIR}/32-carts-db.yaml"

# 4. Microservices (replace placeholder with user's Docker Hub username)
echo "==> [4/6] Microservices (catalog, orders, cart, checkout)..."
for file in "${MANIFEST_DIR}/40-catalog.yaml" \
            "${MANIFEST_DIR}/41-orders.yaml" \
            "${MANIFEST_DIR}/42-cart.yaml" \
            "${MANIFEST_DIR}/43-checkout.yaml"; do
    sed "s|YOUR_DOCKERHUB_USERNAME|${DOCKERHUB_USERNAME}|g" "$file" | kubectl apply -f -
done

# 5. Frontend UI
echo "==> [5/6] Frontend UI..."
sed "s|YOUR_DOCKERHUB_USERNAME|${DOCKERHUB_USERNAME}|g" "${MANIFEST_DIR}/50-ui.yaml" | kubectl apply -f -

# 6. Status and Summary
echo ""
echo "==> [6/6] Checking Pod Status..."
echo ""
kubectl -n "$NAMESPACE" get pods
echo ""
echo "UI Service details:"
kubectl -n "$NAMESPACE" get svc ui

NODE_PORT=$(kubectl -n "$NAMESPACE" get svc ui -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "<nodePort>")

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║            🎉 Deployment Submitted!              ║"
echo "╚══════════════════════════════════════════════════╝"
echo "  Access the store in your browser:"
echo "  http://<MASTER_NODE_IP>:${NODE_PORT}"
echo ""
