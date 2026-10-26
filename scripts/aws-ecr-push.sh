#!/usr/bin/env bash
# ==============================================================================
# SCRIPT: aws-ecr-push.sh
# Run this on your Docker build instance (EC2 VM) where repo is cloned
# Builds all 5 microservices and pushes them to AWS ECR (Artifactory)
# ==============================================================================
set -euo pipefail

# Default configuration (can be overridden via environment variables or CLI arguments)
DEFAULT_REGION="eu-north-1"
DEFAULT_TAG="latest"

AWS_ACCOUNT_ID="${1:-${AWS_ACCOUNT_ID:-}}"
AWS_REGION="${2:-${AWS_REGION:-${DEFAULT_REGION}}}"
IMAGE_TAG="${3:-${IMAGE_TAG:-${DEFAULT_TAG}}}"

SERVICES=("catalog" "orders" "cart" "checkout" "ui")

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║      🐳 BUILD & PUSH IMAGES TO AWS ECR (ARTIFACTORY)         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# 1. Verify Prerequisites
if ! command -v docker >/dev/null 2>&1; then
    echo "❌ Error: Docker is not installed or not in PATH."
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    if sudo docker info >/dev/null 2>&1; then
        DOCKER_CMD="sudo docker"
    else
        echo "❌ Error: Cannot connect to Docker daemon. Is Docker running?"
        exit 1
    fi
else
    DOCKER_CMD="docker"
fi

if ! command -v aws >/dev/null 2>&1; then
    echo "❌ Error: AWS CLI is not installed or not in PATH."
    echo "   Install AWS CLI: curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip' && unzip awscliv2.zip && sudo ./aws/install"
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
echo "Configuration Summary:"
echo "  • AWS Account ID : $AWS_ACCOUNT_ID"
echo "  • AWS Region     : $AWS_REGION"
echo "  • ECR Registry   : $ECR_REGISTRY"
echo "  • Image Tag      : $IMAGE_TAG"
echo "  • Services       : ${SERVICES[*]}"
echo ""

# 4. Authenticate Docker with AWS ECR
echo "🔐 [1/4] Logging in to AWS ECR..."
aws ecr get-login-password --region "$AWS_REGION" | $DOCKER_CMD login --username AWS --password-stdin "$ECR_REGISTRY"
echo "✔ Successfully authenticated with $ECR_REGISTRY"

# 5. Ensure ECR Repositories Exist
echo ""
echo "📦 [2/4] Ensuring ECR repositories exist..."
for SERVICE in "${SERVICES[@]}"; do
    if ! aws ecr describe-repositories --repository-names "$SERVICE" --region "$AWS_REGION" >/dev/null 2>&1; then
        echo "   Creating repository: $SERVICE in $AWS_REGION..."
        aws ecr create-repository \
            --repository-name "$SERVICE" \
            --region "$AWS_REGION" \
            --image-scanning-configuration scanOnPush=true \
            --encryption-configuration encryptionType=AES256 >/dev/null
        echo "   ✔ Repository '$SERVICE' created."
    else
        echo "   ✔ Repository '$SERVICE' exists."
    fi
done

# 6. Locate source code directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Fix checkout Dockerfile permissions if needed (prevents chown mapping errors on Linux builders)
CHECKOUT_DOCKERFILE="$REPO_ROOT/src/checkout/Dockerfile"
if [ -f "$CHECKOUT_DOCKERFILE" ]; then
    sed -i 's/COPY --chown=[^ ]* package/COPY package/g' "$CHECKOUT_DOCKERFILE" 2>/dev/null || true
    sed -i 's/COPY --chown=[^ ]* \. \./COPY . ./g' "$CHECKOUT_DOCKERFILE" 2>/dev/null || true
    sed -i 's/--chown=node:node/--chown=1000:1000/g' "$CHECKOUT_DOCKERFILE" 2>/dev/null || true
    sed -i 's/--chown=appuser:appuser/--chown=1000:1000/g' "$CHECKOUT_DOCKERFILE" 2>/dev/null || true
fi

# Detect buildx support
if ! $DOCKER_CMD buildx version >/dev/null 2>&1; then
    echo "ℹ Note: docker-buildx not detected. Using standard Docker builder."
    export DOCKER_BUILDKIT=0
fi

# 7. Build and Push Each Microservice
echo ""
echo "🔨 [3/4] Building and pushing container images..."
for SERVICE in "${SERVICES[@]}"; do
    TARGET_IMAGE="${ECR_REGISTRY}/${SERVICE}:${IMAGE_TAG}"
    CONTEXT_DIR="${REPO_ROOT}/src/${SERVICE}"

    if [ ! -d "$CONTEXT_DIR" ]; then
        echo "❌ Error: Directory not found: $CONTEXT_DIR"
        exit 1
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📦 Building $SERVICE -> $TARGET_IMAGE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    $DOCKER_CMD build -t "$TARGET_IMAGE" "$CONTEXT_DIR"

    # Also tag as latest if custom tag was passed
    if [ "$IMAGE_TAG" != "latest" ]; then
        $DOCKER_CMD tag "$TARGET_IMAGE" "${ECR_REGISTRY}/${SERVICE}:latest"
    fi

    echo ""
    echo "🚀 Pushing $TARGET_IMAGE to AWS ECR..."
    $DOCKER_CMD push "$TARGET_IMAGE"

    if [ "$IMAGE_TAG" != "latest" ]; then
        echo "🚀 Pushing ${ECR_REGISTRY}/${SERVICE}:latest to AWS ECR..."
        $DOCKER_CMD push "${ECR_REGISTRY}/${SERVICE}:latest"
    fi

    echo "✔ Done with $SERVICE"
done

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   🎉 ALL 5 IMAGES SUCCESSFULLY PUSHED TO AWS ECR!            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
for SERVICE in "${SERVICES[@]}"; do
    echo "  ✔ ${ECR_REGISTRY}/${SERVICE}:${IMAGE_TAG}"
done
echo ""
echo "👉 Next step: Deploy to your kubeadm cluster by running:"
echo "   ./scripts/aws-ecr-deploy.sh $AWS_ACCOUNT_ID $AWS_REGION $IMAGE_TAG"
echo ""
