#!/usr/bin/env bash
# ==============================================================================
# SCRIPT 3: End-to-End Pipeline (Build & Push -> Deploy to K8s)
# Works on Linux, macOS, and Git Bash on Windows
# ==============================================================================
set -euo pipefail

DOCKERHUB_USERNAME="${1:-}"
MASTER_IP="${2:-13.49.245.123}"

if [ -z "$DOCKERHUB_USERNAME" ]; then
    read -rp "Enter your Docker Hub username: " DOCKERHUB_USERNAME
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║      🔥 RUNNING END-TO-END PIPELINE              ║"
echo "║   1. Build & Push Images to Docker Hub           ║"
echo "║   2. Deploy to Kubernetes Cluster                ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# STEP 1: Build & Push
echo "========================================="
echo "  STAGE 1: BUILD & PUSH DOCKER IMAGES    "
echo "========================================="
chmod +x "${SCRIPT_DIR}/build-and-push.sh"
"${SCRIPT_DIR}/build-and-push.sh" "$DOCKERHUB_USERNAME"

# STEP 2: Deploy to K8s
echo ""
echo "========================================="
echo "  STAGE 2: DEPLOY TO KUBERNETES CLUSTER  "
echo "========================================="
chmod +x "${SCRIPT_DIR}/deploy-k8s.sh"
"${SCRIPT_DIR}/deploy-k8s.sh" "$DOCKERHUB_USERNAME"

echo ""
echo "🎉 Full Pipeline Execution Complete!"
echo "Check your application at: http://${MASTER_IP}:<NodePort>"
