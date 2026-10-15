#!/usr/bin/env bash
# ==============================================================================
# SCRIPT: build-and-push.sh (Linux / macOS / Git Bash)
# Builds all 5 microservice Docker images locally and pushes them to Docker Hub
# ==============================================================================
set -euo pipefail

DOCKERHUB_USERNAME="${1:-}"

if [ -z "$DOCKERHUB_USERNAME" ]; then
    read -rp "Enter your Docker Hub username: " DOCKERHUB_USERNAME
fi

if [ -z "$DOCKERHUB_USERNAME" ]; then
    echo "❌ Error: Docker Hub username is required."
    exit 1
fi

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║   🐳 Building & Pushing Images to Docker Hub     ║"
echo "╚══════════════════════════════════════════════════╝"
echo "  Docker Hub User: $DOCKERHUB_USERNAME"
echo ""

# Verify docker is running
if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker daemon is not running. Please start Docker first."
    exit 1
fi

# Detect buildx support
if ! docker buildx version >/dev/null 2>&1; then
    echo "ℹ  Note: docker-buildx not detected. Using standard Docker builder."
    export DOCKER_BUILDKIT=0
fi

# Ensure user is logged in
echo "Checking Docker login..."
docker login

# List of 5 microservices and their folder paths
SERVICES=("catalog" "orders" "cart" "checkout" "ui")

# Find repository root (where src/ is located)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Ensure checkout Dockerfile uses numeric 1000:1000 to prevent chown mapping errors
CHECKOUT_DOCKERFILE="$REPO_ROOT/src/checkout/Dockerfile"
if [ -f "$CHECKOUT_DOCKERFILE" ]; then
    sed -i 's/COPY --chown=[^ ]* package/COPY package/g' "$CHECKOUT_DOCKERFILE" 2>/dev/null || true
    sed -i 's/COPY --chown=[^ ]* \. \./COPY . ./g' "$CHECKOUT_DOCKERFILE" 2>/dev/null || true
    sed -i 's/--chown=node:node/--chown=1000:1000/g' "$CHECKOUT_DOCKERFILE" 2>/dev/null || true
    sed -i 's/--chown=appuser:appuser/--chown=1000:1000/g' "$CHECKOUT_DOCKERFILE" 2>/dev/null || true
fi

for SERVICE in "${SERVICES[@]}"; do
    IMAGE_NAME="${DOCKERHUB_USERNAME}/${SERVICE}:latest"
    CONTEXT_DIR="${REPO_ROOT}/src/${SERVICE}"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📦 [1/2] Building image: $IMAGE_NAME"
    echo "         Context: $CONTEXT_DIR"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    docker build -t "$IMAGE_NAME" "$CONTEXT_DIR"

    echo ""
    echo "🚀 [2/2] Pushing image: $IMAGE_NAME"
    docker push "$IMAGE_NAME"
    echo "✅ Successfully pushed $IMAGE_NAME"
done

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║   🎉 All 5 Images Pushed to Docker Hub!         ║"
echo "╚══════════════════════════════════════════════════╝"
for SERVICE in "${SERVICES[@]}"; do
    echo "  ✔ ${DOCKERHUB_USERNAME}/${SERVICE}:latest"
done
echo ""
