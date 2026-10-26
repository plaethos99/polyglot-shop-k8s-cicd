#!/usr/bin/env bash
# ==============================================================================
# SCRIPT: destroy-eks.sh
# Deletes Polyglot Shop Kubernetes resources, AWS LoadBalancers, and the EKS cluster
# ==============================================================================
set -euo pipefail

DEFAULT_CLUSTER="retail-store"
DEFAULT_REGION="eu-north-1"
NAMESPACE="retail-store"

EKS_CLUSTER_NAME="${1:-${EKS_CLUSTER_NAME:-${DEFAULT_CLUSTER}}}"
AWS_REGION="${2:-${AWS_REGION:-${DEFAULT_REGION}}}"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       🗑️  DESTROY AWS EKS CLUSTER & ASSOCIATED RESOURCES     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

echo "Target Cluster: $EKS_CLUSTER_NAME"
echo "AWS Region    : $AWS_REGION"
echo ""

# 1. Check prerequisites
if ! command -v aws >/dev/null 2>&1; then
    echo "❌ Error: 'aws' CLI command not found."
    exit 1
fi

if ! command -v eksctl >/dev/null 2>&1; then
    echo "❌ Error: 'eksctl' command not found."
    exit 1
fi

# 2. Check if cluster exists
if ! aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
    echo "ℹ EKS Cluster '$EKS_CLUSTER_NAME' does not exist in $AWS_REGION. Nothing to destroy."
    exit 0
fi

# 3. Clean up Kubernetes LoadBalancer & Namespace first
# (Crucial: prevents lingering AWS ELBs from blocking VPC deletion)
echo "── Step 1/2: Deleting Kubernetes namespace '$NAMESPACE' and LoadBalancers..."
if command -v kubectl >/dev/null 2>&1; then
    aws eks update-kubeconfig --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" 2>/dev/null || true
    if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        echo "   Deleting LoadBalancer services..."
        kubectl -n "$NAMESPACE" delete svc ui --ignore-not-found --timeout=60s || true
        echo "   Deleting namespace '$NAMESPACE'..."
        kubectl delete namespace "$NAMESPACE" --ignore-not-found --timeout=90s || true
    fi
fi
echo "   ✔ Kubernetes services released."

# 4. Delete the EKS cluster via eksctl
echo ""
echo "── Step 2/2: Deleting EKS cluster and managed nodegroups..."
echo "⏳ This will take approximately 8-12 minutes to delete CloudFormation stacks..."

eksctl delete cluster --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --wait

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          🎉 EKS CLUSTER SUCCESSFULLY DESTROYED!              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo "All EKS nodes, VPC resources, and LoadBalancers have been deleted."
echo ""
