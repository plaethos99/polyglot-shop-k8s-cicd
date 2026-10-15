#!/usr/bin/env bash
# ==============================================================================
# master-deploy.sh: Run this directly on your AWS Master Node
# Deploys Polyglot Shop manifests to your kubeadm Kubernetes cluster
# ==============================================================================
set -euo pipefail

DOCKERHUB_USERNAME="${1:-}"
NAMESPACE="retail-store"

# Clear terminal screen for clean view
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║      🚀 POLYGLOT SHOP: AWS MASTER NODE DEPLOYMENT            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# 1. Ask for Docker Hub username if not passed as an argument
if [ -z "$DOCKERHUB_USERNAME" ]; then
    read -rp "👉 Enter your Docker Hub Username: " DOCKERHUB_USERNAME
fi

if [ -z "$DOCKERHUB_USERNAME" ]; then
    echo "❌ Error: Docker Hub username is required so Kubernetes knows where to pull your images."
    exit 1
fi

echo ""
echo "✔ Using Docker Hub Username: $DOCKERHUB_USERNAME"
echo "✔ Target Namespace:         $NAMESPACE"
echo ""

# 2. Check if kubectl is available
if ! command -v kubectl >/dev/null 2>&1; then
    echo "❌ Error: kubectl command not found on this machine. Are you on the master node?"
    exit 1
fi

# Locate the manifests folder
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST_DIR="${REPO_ROOT}/deployment-me/k8s"

if [ ! -d "$MANIFEST_DIR" ]; then
    echo "❌ Error: Manifest directory not found at $MANIFEST_DIR"
    exit 1
fi

# 3. Ensure StorageClass (local-path) exists for Databases
echo "── Step 1/5: Checking StorageClass for Databases..."
if ! kubectl get storageclass local-path >/dev/null 2>&1; then
    echo "   ⚙ Installing local-path-provisioner storage..."
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml
    kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
    echo "   ✔ StorageClass local-path ready."
else
    echo "   ✔ StorageClass local-path is already installed."
fi

# 4. Namespace and Secrets
echo ""
echo "── Step 2/5: Creating Namespace & Secrets..."
kubectl apply -f "${MANIFEST_DIR}/00-namespace.yaml"
kubectl apply -f "${MANIFEST_DIR}/01-secrets.yaml"

# 5. Stateful Databases & Messaging
echo ""
echo "── Step 3/5: Deploying Databases & Message Queue..."
kubectl apply -f "${MANIFEST_DIR}/10-rabbitmq.yaml"
kubectl apply -f "${MANIFEST_DIR}/22-postgres.yaml"
kubectl apply -f "${MANIFEST_DIR}/30-redis.yaml"
kubectl apply -f "${MANIFEST_DIR}/31-mariadb.yaml"
kubectl apply -f "${MANIFEST_DIR}/32-carts-db.yaml"

# 6. Microservices & Frontend UI
echo ""
echo "── Step 4/5: Deploying 5 Microservices with Docker Hub images..."
for file in "${MANIFEST_DIR}/40-catalog.yaml" \
            "${MANIFEST_DIR}/41-orders.yaml" \
            "${MANIFEST_DIR}/42-cart.yaml" \
            "${MANIFEST_DIR}/43-checkout.yaml" \
            "${MANIFEST_DIR}/50-ui.yaml"; do
    FILENAME=$(basename "$file")
    echo "   Applying $FILENAME with image ${DOCKERHUB_USERNAME}/..."
    sed "s|YOUR_DOCKERHUB_USERNAME|${DOCKERHUB_USERNAME}|g" "$file" | kubectl apply -f -
done

# 7. Verification and URL display
echo ""
echo "── Step 5/5: Fetching Deployment Details..."
echo ""
kubectl -n "$NAMESPACE" get pods

echo ""
echo "Checking UI Service:"
kubectl -n "$NAMESPACE" get svc ui

# Get NodePort
NODE_PORT=$(kubectl -n "$NAMESPACE" get svc ui -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "3XXXX")

# Try to detect Public IP from AWS metadata service, default to known master IP
PUBLIC_IP=$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "13.49.245.123")

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                 🎉 DEPLOYMENT SUBMITTED!                     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  🌐 Open the Polyglot Shop in your browser:"
echo "     http://${PUBLIC_IP}:${NODE_PORT}"
echo ""
echo "  💡 TIP: Run 'kubectl -n retail-store get pods -w' to watch"
echo "     pods transition to 'Running' status."
echo ""
