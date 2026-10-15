#!/usr/bin/env bash
# ==============================================================================
# SCRIPT 1: Build Docker Images and Push to Docker Hub (Linux / macOS / Git Bash)
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

# Ensure user is logged in
echo "Checking Docker login..."
if ! docker system info | grep -q "Username:"; then
    echo "Please log in to Docker Hub:"
    docker login
fi

# List of 5 microservices and their folder paths
SERVICES=("catalog" "orders" "cart" "checkout" "ui")

# Find repository root (where src/ is located)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

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
