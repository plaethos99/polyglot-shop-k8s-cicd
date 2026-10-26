#!/usr/bin/env bash
# ==============================================================================
# SCRIPT: deploy-eks.sh
# Deploys Polyglot Shop to an AWS EKS Cluster using images from AWS ECR
# ==============================================================================
set -euo pipefail

DEFAULT_CLUSTER="retail-store"
DEFAULT_REGION="eu-north-1"
DEFAULT_TAG="latest"
NAMESPACE="retail-store"

EKS_CLUSTER_NAME="${1:-${EKS_CLUSTER_NAME:-${DEFAULT_CLUSTER}}}"
AWS_REGION="${2:-${AWS_REGION:-${DEFAULT_REGION}}}"
AWS_ACCOUNT_ID="${3:-${AWS_ACCOUNT_ID:-}}"
IMAGE_TAG="${4:-${IMAGE_TAG:-${DEFAULT_TAG}}}"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║      🚀 DEPLOY POLYGLOT SHOP FROM AWS ECR TO AWS EKS         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# 1. Verify Prerequisites
if ! command -v aws >/dev/null 2>&1; then
    echo "❌ Error: 'aws' CLI command not found. Please install AWS CLI v2."
    exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
    echo "❌ Error: 'kubectl' command not found. Please install kubectl."
    exit 1
fi

# 2. Resolve AWS Account ID
if [ -z "$AWS_ACCOUNT_ID" ]; then
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text 2>/dev/null || true)
fi

if [ -z "$AWS_ACCOUNT_ID" ]; then
    read -rp "👉 Enter AWS Account ID: " AWS_ACCOUNT_ID
fi

if [ -z "$AWS_ACCOUNT_ID" ]; then
    echo "❌ Error: AWS Account ID is required."
    exit 1
fi

ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "Configuration:"
echo "  • EKS Cluster  : $EKS_CLUSTER_NAME"
echo "  • AWS Region   : $AWS_REGION"
echo "  • AWS Account  : $AWS_ACCOUNT_ID"
echo "  • ECR Registry : $ECR_REGISTRY"
echo "  • Image Tag    : $IMAGE_TAG"
echo "  • Namespace    : $NAMESPACE"
echo ""

# 3. Update Kubeconfig for EKS
echo "── Step 1/6: Updating kubeconfig for EKS cluster '$EKS_CLUSTER_NAME'..."
aws eks update-kubeconfig --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION"

echo "Verifying cluster access & worker nodes..."
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
if [ "$NODE_COUNT" -eq 0 ]; then
    echo "⚠️ Waiting up to 3 minutes for worker nodes to join the cluster..."
    for i in {1..18}; do
        sleep 10
        NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
        if [ "$NODE_COUNT" -gt 0 ]; then
            break
        fi
    done
fi

kubectl get nodes -o wide
if [ "$NODE_COUNT" -eq 0 ]; then
    echo "❌ ERROR: Cluster has 0 worker nodes! Pods cannot schedule without worker nodes."
    exit 1
fi
echo "✔ Successfully connected to EKS cluster with $NODE_COUNT worker node(s)."

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

# 4. StorageClass Setup
echo ""
echo "── Step 2/6: Ensuring StorageClass (local-path) is installed for database PVCs..."
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' 2>/dev/null || true
kubectl get storageclass

# 5. Namespace and ECR Pull Secret
echo ""
echo "── Step 3/6: Creating Namespace '$NAMESPACE' & ECR Pull Secret..."
kubectl apply -f "${MANIFEST_DIR}/00-namespace.yaml"

ECR_AUTH_TOKEN=$(aws ecr get-login-password --region "$AWS_REGION")
kubectl -n "$NAMESPACE" create secret docker-registry ecr-secret \
    --docker-server="$ECR_REGISTRY" \
    --docker-username=AWS \
    --docker-password="$ECR_AUTH_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NAMESPACE" patch serviceaccount default -p '{"imagePullSecrets": [{"name": "ecr-secret"}]}' 2>/dev/null || true
echo "   ✔ ECR secret created and attached to ServiceAccount."

# 6. Deploy Databases & Messaging
echo ""
echo "── Step 4/6: Deploying Secrets and Database Backends..."
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
echo "   ✔ Database backends applied."

# 7. Deploy Microservices from ECR
echo ""
echo "── Step 5/6: Deploying Microservices from AWS ECR..."

apply_eks_manifest() {
    local file="$1"
    local service="$2"
    local full_image="${ECR_REGISTRY}/${service}:${IMAGE_TAG}"

    echo "   Deploying $service ($full_image)..."
    sed -E \
        -e "s|image: .*/${service}:.*|image: ${full_image}|g" \
        -e "s|YOUR_DOCKERHUB_USERNAME/${service}:[a-zA-Z0-9._-]+|${full_image}|g" \
        -e "s|DOCKERHUB_USERNAME/${service}:[a-zA-Z0-9._-]+|${full_image}|g" \
        "$file" | kubectl apply -f -
}

apply_eks_manifest "${MANIFEST_DIR}/40-catalog.yaml" "catalog"
apply_eks_manifest "${MANIFEST_DIR}/41-orders.yaml" "orders"
apply_eks_manifest "${MANIFEST_DIR}/42-cart.yaml" "cart"
apply_eks_manifest "${MANIFEST_DIR}/43-checkout.yaml" "checkout"
apply_eks_manifest "${MANIFEST_DIR}/50-ui.yaml" "ui"

# Expose UI service via LoadBalancer on EKS (listening on both port 80 and 8080)
echo "   Configuring UI service as LoadBalancer on EKS (ports 80 and 8080)..."
kubectl -n "$NAMESPACE" patch svc ui -p '{"spec": {"type": "LoadBalancer", "ports": [{"name": "http", "port": 80, "targetPort": 8080}, {"name": "http-alt", "port": 8080, "targetPort": 8080}]}}' 2>/dev/null || true

# 8. Check Rollout & LoadBalancer URL
echo ""
echo "── Step 6/6: Verifying Pods & Retrieving LoadBalancer URL..."
kubectl -n "$NAMESPACE" rollout status deployment/ui --timeout=180s || true

echo ""
kubectl -n "$NAMESPACE" get pods -o wide
echo ""
kubectl -n "$NAMESPACE" get svc ui

echo ""
echo "⏳ Waiting for AWS LoadBalancer external hostname (may take 1-2 minutes)..."
LB_URL=""
for i in {1..20}; do
    LB_URL=$(kubectl -n "$NAMESPACE" get svc ui -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
    if [ -n "$LB_URL" ]; then
        break
    fi
    sleep 6
done

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          🎉 EKS DEPLOYMENT COMPLETED SUCCESSFULLY!           ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
if [ -n "$LB_URL" ]; then
    echo "🌐 Access your Polyglot Web Store in the browser at:"
    echo "   http://${LB_URL}:8080"
else
    echo "ℹ AWS LoadBalancer is still provisioning. Run this command to check its URL:"
    echo "   kubectl -n $NAMESPACE get svc ui -w"
fi
echo ""
