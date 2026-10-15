#!/usr/bin/env bash
# ==============================================================================
# SCRIPT 2: master-node-deploy.sh
# Run this on your AWS MASTER NODE (13.49.245.123) to deploy all manifests
# ==============================================================================
set -euo pipefail

NAMESPACE="retail-store"
DOCKERHUB_USERNAME="${1:-}"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║      🚀 KUBERNETES MASTER NODE DEPLOYMENT SCRIPT             ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# 1. Ask for Docker Hub username if not provided as argument
if [ -z "$DOCKERHUB_USERNAME" ]; then
    read -rp "👉 Enter your Docker Hub Username (where you pushed the images): " DOCKERHUB_USERNAME
fi

if [ -z "$DOCKERHUB_USERNAME" ]; then
    echo "❌ Error: Docker Hub username is required."
    exit 1
fi

echo "✔ Docker Hub User: $DOCKERHUB_USERNAME"
echo "✔ Target Namespace: $NAMESPACE"
echo ""

# 2. Check for kubectl
if ! command -v kubectl >/dev/null 2>&1; then
    echo "❌ Error: 'kubectl' command not found. Please run this script on your Kubernetes master node."
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

# 3. Check / Install StorageClass (local-path) for databases
echo "── Step 1/5: Ensuring StorageClass (local-path) is installed..."
if ! kubectl get storageclass local-path >/dev/null 2>&1; then
    echo "   ⚙ Installing rancher local-path-provisioner..."
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml
    kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
    echo "   ✔ StorageClass local-path ready."
else
    echo "   ✔ StorageClass local-path already exists."
fi

# 4. Namespace and Secrets
echo ""
echo "── Step 2/5: Creating Namespace & Database Secrets..."
kubectl apply -f "${MANIFEST_DIR}/00-namespace.yaml"
kubectl apply -f "${MANIFEST_DIR}/01-secrets.yaml"

# 5. Stateful Databases & Messaging
echo ""
echo "── Step 3/5: Deploying Databases & RabbitMQ..."
kubectl apply -f "${MANIFEST_DIR}/10-rabbitmq.yaml"
kubectl apply -f "${MANIFEST_DIR}/22-postgres.yaml"
kubectl apply -f "${MANIFEST_DIR}/30-redis.yaml"
kubectl apply -f "${MANIFEST_DIR}/31-mariadb.yaml"
kubectl apply -f "${MANIFEST_DIR}/32-carts-db.yaml"

# 6. Microservices & Frontend UI
echo ""
echo "── Step 4/5: Deploying Microservices using images from ${DOCKERHUB_USERNAME}..."
for file in "${MANIFEST_DIR}/40-catalog.yaml" \
            "${MANIFEST_DIR}/41-orders.yaml" \
            "${MANIFEST_DIR}/42-cart.yaml" \
            "${MANIFEST_DIR}/43-checkout.yaml" \
            "${MANIFEST_DIR}/50-ui.yaml"; do
    FILENAME=$(basename "$file")
    echo "   Applying $FILENAME..."
    sed "s|YOUR_DOCKERHUB_USERNAME|${DOCKERHUB_USERNAME}|g" "$file" | kubectl apply -f -
done

# 7. Verification and URL display
echo ""
echo "── Step 5/5: Checking Status..."
echo ""
kubectl -n "$NAMESPACE" get pods

echo ""
echo "UI Service details:"
kubectl -n "$NAMESPACE" get svc ui

# Extract NodePort
NODE_PORT=$(kubectl -n "$NAMESPACE" get svc ui -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "3XXXX")

# Detect master public IP (AWS metadata) or fall back to known master node IP
PUBLIC_IP=$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "13.49.245.123")

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                 🎉 DEPLOYMENT SUBMITTED!                     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  🌐 Open the Polyglot Shop in your browser:"
echo "     http://${PUBLIC_IP}:${NODE_PORT}"
echo ""
echo "  💡 TIP: Run 'kubectl -n retail-store get pods -w' to watch all"
echo "     pods transition to 'Running'."
echo ""
