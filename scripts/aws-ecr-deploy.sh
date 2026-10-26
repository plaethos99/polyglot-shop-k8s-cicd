#!/usr/bin/env bash
# ==============================================================================
# SCRIPT: aws-ecr-deploy.sh
# Run this on your AWS Kubeadm Master Node (or any host with kubectl configured)
# Deploys Polyglot Shop to Kubernetes pulling images directly from AWS ECR
# ==============================================================================
set -euo pipefail

DEFAULT_REGION="eu-north-1"
DEFAULT_TAG="latest"
NAMESPACE="retail-store"

AWS_ACCOUNT_ID="${1:-${AWS_ACCOUNT_ID:-}}"
AWS_REGION="${2:-${AWS_REGION:-${DEFAULT_REGION}}}"
IMAGE_TAG="${3:-${IMAGE_TAG:-${DEFAULT_TAG}}}"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║      🚀 DEPLOY POLYGLOT SHOP FROM AWS ECR TO KUBERNETES      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# 1. Verify Prerequisites
if ! command -v kubectl >/dev/null 2>&1; then
    echo "❌ Error: 'kubectl' command not found. Please run this script on your Kubernetes master node."
    exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
    echo "❌ Error: 'aws' CLI command not found. Please install AWS CLI."
    exit 1
fi

# 2. Resolve AWS Account ID
if [ -z "$AWS_ACCOUNT_ID" ]; then
    echo "🔍 Detecting AWS Account ID from AWS credentials..."
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text 2>/dev/null || true)
fi

if [ -z "$AWS_ACCOUNT_ID" ]; then
    read -rp "👉 Enter your 12-digit AWS Account ID: " AWS_ACCOUNT_ID
fi

if [ -z "$AWS_ACCOUNT_ID" ]; then
    echo "❌ Error: AWS Account ID is required."
    exit 1
fi

# 3. Resolve AWS Region
if [ -z "$AWS_REGION" ]; then
    AWS_REGION=$(aws configure get region 2>/dev/null || echo "$DEFAULT_REGION")
    read -rp "👉 Enter AWS Region [$AWS_REGION]: " USER_REGION
    AWS_REGION="${USER_REGION:-$AWS_REGION}"
fi

ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo ""
echo "Deployment Settings:"
echo "  • ECR Registry : $ECR_REGISTRY"
echo "  • AWS Region   : $AWS_REGION"
echo "  • Image Tag    : $IMAGE_TAG"
echo "  • Namespace    : $NAMESPACE"
echo ""

# Locate manifests directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -d "${REPO_ROOT}/deployment-me/k8s" ]; then
    MANIFEST_DIR="${REPO_ROOT}/deployment-me/k8s"
elif [ -d "${REPO_ROOT}/deployment-me/k8-manifests" ]; then
    MANIFEST_DIR="${REPO_ROOT}/deployment-me/k8-manifests"
else
    echo "❌ Error: Manifest directory not found."
    exit 1
fi

echo "📁 Using manifests from: $MANIFEST_DIR"
echo ""

# 4. Ensure StorageClass (local-path) exists for kubeadm PVs
echo "── Step 1/6: Checking StorageClass for Database volumes..."
if ! kubectl get storageclass local-path >/dev/null 2>&1; then
    echo "   ⚙ Installing rancher local-path-provisioner storage..."
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml
    kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
    echo "   ✔ StorageClass 'local-path' set as default."
else
    echo "   ✔ StorageClass 'local-path' already present."
fi

# 5. Ensure Namespace Exists
echo ""
echo "── Step 2/6: Creating / Updating Namespace '$NAMESPACE'..."
kubectl apply -f "${MANIFEST_DIR}/00-namespace.yaml"

# 6. Configure AWS ECR Pull Secret for Kubernetes
echo ""
echo "── Step 3/6: Generating ECR pull secret ('ecr-secret')..."
ECR_AUTH_TOKEN=$(aws ecr get-login-password --region "$AWS_REGION")

kubectl -n "$NAMESPACE" create secret docker-registry ecr-secret \
    --docker-server="$ECR_REGISTRY" \
    --docker-username=AWS \
    --docker-password="$ECR_AUTH_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -

# Patch default serviceaccount so every pod automatically inherits the pull secret
kubectl -n "$NAMESPACE" patch serviceaccount default -p '{"imagePullSecrets": [{"name": "ecr-secret"}]}' 2>/dev/null || true
echo "   ✔ Secret 'ecr-secret' configured and bound to default ServiceAccount."

# 7. Apply Database Secrets & Stateful Backends
echo ""
echo "── Step 4/6: Deploying Secrets, Databases & Message Broker..."
kubectl apply -f "${MANIFEST_DIR}/01-secrets.yaml"
kubectl apply -f "${MANIFEST_DIR}/10-rabbitmq.yaml"
kubectl apply -f "${MANIFEST_DIR}/22-postgres.yaml"
kubectl apply -f "${MANIFEST_DIR}/30-redis.yaml"
kubectl apply -f "${MANIFEST_DIR}/31-mariadb.yaml"

if [ -f "${MANIFEST_DIR}/32-carts-db.yaml" ]; then
    kubectl apply -f "${MANIFEST_DIR}/32-carts-db.yaml"
elif [ -f "${MANIFEST_DIR}/42-carts-db.yaml" ]; then
    kubectl apply -f "${MANIFEST_DIR}/42-carts-db.yaml"
fi
echo "   ✔ Backing services manifests submitted."

# 8. Deploy Microservices with AWS ECR image URLs
echo ""
echo "── Step 5/6: Deploying Microservices from AWS ECR..."

apply_manifest_with_ecr() {
    local file="$1"
    local service="$2"
    local full_image="${ECR_REGISTRY}/${service}:${IMAGE_TAG}"

    echo "   Deploying $service ($full_image)..."
    
    # Replace any previous image placeholder with ECR image URI
    sed -E \
        -e "s|image: .*/${service}:.*|image: ${full_image}|g" \
        -e "s|YOUR_DOCKERHUB_USERNAME/${service}:[a-zA-Z0-9._-]+|${full_image}|g" \
        -e "s|DOCKERHUB_USERNAME/${service}:[a-zA-Z0-9._-]+|${full_image}|g" \
        "$file" | kubectl apply -f -
}

apply_manifest_with_ecr "${MANIFEST_DIR}/40-catalog.yaml" "catalog"
apply_manifest_with_ecr "${MANIFEST_DIR}/41-orders.yaml" "orders"
apply_manifest_with_ecr "${MANIFEST_DIR}/42-cart.yaml" "cart"
apply_manifest_with_ecr "${MANIFEST_DIR}/43-checkout.yaml" "checkout"
apply_manifest_with_ecr "${MANIFEST_DIR}/50-ui.yaml" "ui"

# 9. Status and NodePort Info
echo ""
echo "── Step 6/6: Verifying Deployment Status..."
echo ""
kubectl -n "$NAMESPACE" get pods -o wide

echo ""
echo "Service status:"
kubectl -n "$NAMESPACE" get svc ui

NODE_PORT=$(kubectl -n "$NAMESPACE" get svc ui -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "<nodePort>")

# Try to get public IP from EC2 metadata, or fall back to node internal/external IP
NODE_IP=$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || true)
if [ -z "$NODE_IP" ]; then
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null || true)
fi
if [ -z "$NODE_IP" ]; then
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "<MASTER_NODE_IP>")
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║            🎉 DEPLOYMENT SUBMITTED SUCCESSFULLY!             ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "🌐 Access the Polyglot Web Store in your browser at:"
echo "   http://${NODE_IP}:${NODE_PORT}"
echo ""
echo "🔍 Helpful monitoring commands:"
echo "   kubectl -n $NAMESPACE get pods -w"
echo "   kubectl -n $NAMESPACE logs -l app=ui --tail=50"
echo ""
