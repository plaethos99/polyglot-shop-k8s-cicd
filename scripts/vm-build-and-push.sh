#!/usr/bin/env bash
# ==============================================================================
# SCRIPT 1: vm-build-and-push.sh
# Run this on your NEW VM instance to build Docker images & push to Docker Hub
# ==============================================================================
set -euo pipefail

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║      🐳 VM DOCKER BUILD & PUSH TO DOCKER HUB                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# 1. Check if Docker is installed, and offer to install if missing (for a fresh VM)
if ! command -v docker >/dev/null 2>&1; then
    echo "⚠️  Docker is not installed on this VM."
    read -rp "👉 Would you like to automatically install Docker now? (y/N): " INSTALL_DOCKER
    if [[ "$INSTALL_DOCKER" =~ ^[Yy]$ ]]; then
        echo "⚙ Installing Docker..."
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update
            sudo apt-get install -y docker.io
            sudo systemctl enable --now docker
            sudo usermod -aG docker "$USER" || true
        elif command -v yum >/dev/null 2>&1; then
            sudo yum install -y docker
            sudo systemctl enable --now docker
            sudo usermod -aG docker "$USER" || true
        fi
        echo "✔ Docker installed successfully."
    else
        echo "❌ Docker is required to build images. Exiting."
        exit 1
    fi
fi

# Ensure Docker daemon is accessible (handle sudo if needed)
DOCKER_CMD="docker"
if ! docker info >/dev/null 2>&1; then
    if sudo docker info >/dev/null 2>&1; then
        DOCKER_CMD="sudo docker"
    else
        echo "❌ Cannot connect to Docker daemon. Please run 'sudo systemctl start docker'."
        exit 1
    fi
fi

# 2. Get Docker Hub Username
DOCKERHUB_USERNAME="${1:-}"
if [ -z "$DOCKERHUB_USERNAME" ]; then
    read -rp "👉 Enter your Docker Hub Username: " DOCKERHUB_USERNAME
fi

if [ -z "$DOCKERHUB_USERNAME" ]; then
    echo "❌ Error: Docker Hub username is required."
    exit 1
fi

# 3. Log in to Docker Hub
echo ""
echo "🔐 Checking Docker Hub login..."
$DOCKER_CMD login

# 4. Locate project root (src folder)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ ! -d "$REPO_ROOT/src" ]; then
    echo "❌ Error: 'src' folder not found at $REPO_ROOT/src."
    echo "   Make sure you ran this from inside the polyglot-shop-k8s-cicd repository."
    exit 1
fi

# 5. Build and Push each of the 5 services
SERVICES=("catalog" "orders" "cart" "checkout" "ui")

echo ""
echo "🚀 Starting build and push for 5 microservices..."
echo ""

for SERVICE in "${SERVICES[@]}"; do
    IMAGE_TAG="${DOCKERHUB_USERNAME}/${SERVICE}:latest"
    CONTEXT_PATH="${REPO_ROOT}/src/${SERVICE}"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📦 [1/2] Building image: $IMAGE_TAG"
    echo "         Source path:   $CONTEXT_PATH"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    $DOCKER_CMD build -t "$IMAGE_TAG" "$CONTEXT_PATH"

    echo ""
    echo "⬆️  [2/2] Pushing to Docker Hub: $IMAGE_TAG"
    $DOCKER_CMD push "$IMAGE_TAG"
    echo "✔ Done: $IMAGE_TAG"
    echo ""
done

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       🎉 ALL 5 IMAGES BUILT & PUSHED TO DOCKER HUB!          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
for SERVICE in "${SERVICES[@]}"; do
    echo "  ✔ ${DOCKERHUB_USERNAME}/${SERVICE}:latest"
done
echo ""
echo "👉 NEXT STEP: Go to your AWS Master Node and run 'scripts/master-node-deploy.sh $DOCKERHUB_USERNAME'"
echo ""
