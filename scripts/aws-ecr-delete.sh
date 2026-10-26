#!/usr/bin/env bash
# ==============================================================================
# SCRIPT: aws-ecr-delete.sh
# Deletes images or repositories from AWS ECR (Artifactory)
# ==============================================================================
set -euo pipefail

DEFAULT_REGION="eu-north-1"
SERVICES=("catalog" "orders" "cart" "checkout" "ui")

AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-}"
AWS_REGION="${AWS_REGION:-${DEFAULT_REGION}}"
ACTION=""
TARGET_TAG=""
DRY_RUN=false
FORCE=false

# Parse flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        --account)
            AWS_ACCOUNT_ID="$2"
            shift 2
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --tag)
            ACTION="tag"
            TARGET_TAG="$2"
            shift 2
            ;;
        --untagged)
            ACTION="untagged"
            shift
            ;;
        --all-images)
            ACTION="all_images"
            shift
            ;;
        --delete-repos)
            ACTION="delete_repos"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force|-f)
            FORCE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --account <id>       AWS Account ID"
            echo "  --region <region>    AWS Region (default: eu-north-1)"
            echo "  --tag <tag>          Delete images with a specific tag (e.g., 'latest')"
            echo "  --untagged           Delete untagged/dangling images only"
            echo "  --all-images         Delete all images in all 5 repositories"
            echo "  --delete-repos       Delete the ECR repositories themselves"
            echo "  --dry-run            List what would be deleted without deleting"
            echo "  --force, -f          Skip interactive confirmation"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Run '$0 --help' for usage."
            exit 1
            ;;
    esac
done

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║        🗑️  AWS ECR (ARTIFACTORY) IMAGE CLEANUP UTILITY       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Verify AWS CLI
if ! command -v aws >/dev/null 2>&1; then
    echo "❌ Error: 'aws' CLI command not found. Please install AWS CLI."
    exit 1
fi

# Resolve Account ID if not set
if [ -z "$AWS_ACCOUNT_ID" ]; then
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text 2>/dev/null || true)
fi

if [ -z "$AWS_ACCOUNT_ID" ]; then
    read -rp "👉 Enter AWS Account ID: " AWS_ACCOUNT_ID
fi

# Resolve Region if not set
if [ -z "$AWS_REGION" ]; then
    AWS_REGION=$(aws configure get region 2>/dev/null || echo "$DEFAULT_REGION")
fi

echo "Connected Configuration:"
echo "  • AWS Account ID : $AWS_ACCOUNT_ID"
echo "  • AWS Region     : $AWS_REGION"
echo "  • Services       : ${SERVICES[*]}"
if [ "$DRY_RUN" = true ]; then
    echo "  • MODE           : ⚠️  DRY RUN (No images will actually be deleted)"
fi
echo ""

# Interactive menu if action was not passed via CLI flag
if [ -z "$ACTION" ]; then
    echo "Select an operation to perform:"
    echo "  1) Delete a specific tag (e.g. 'latest') across all service repositories"
    echo "  2) Delete all untagged / orphaned images (saves storage)"
    echo "  3) Delete ALL images from all 5 service repositories (empty repos)"
    echo "  4) Delete the 5 ECR repositories completely"
    echo "  5) Cancel and exit"
    echo ""
    read -rp "Enter choice [1-5]: " MENU_CHOICE

    case "$MENU_CHOICE" in
        1)
            ACTION="tag"
            read -rp "👉 Enter image tag to delete [default: latest]: " INPUT_TAG
            TARGET_TAG="${INPUT_TAG:-latest}"
            ;;
        2)
            ACTION="untagged"
            ;;
        3)
            ACTION="all_images"
            ;;
        4)
            ACTION="delete_repos"
            ;;
        *)
            echo "Exiting without making changes."
            exit 0
            ;;
    esac
fi

# Confirmation prompt unless --force was passed
if [ "$FORCE" = false ] && [ "$DRY_RUN" = false ]; then
    echo ""
    echo "⚠️  WARNING: You are about to perform a destructive deletion operation:"
    echo "    Action: $ACTION ${TARGET_TAG:+(tag: $TARGET_TAG)}"
    echo "    Region: $AWS_REGION"
    read -rp "👉 Are you sure you want to proceed? (yes/no): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Operation cancelled."
        exit 0
    fi
fi

echo ""

# Perform action
case "$ACTION" in
    tag)
        echo "🔍 Searching and deleting images with tag '$TARGET_TAG'..."
        for SERVICE in "${SERVICES[@]}"; do
            echo "── Repository: $SERVICE"
            if ! aws ecr describe-repositories --repository-names "$SERVICE" --region "$AWS_REGION" >/dev/null 2>&1; then
                echo "   ⚠️  Repository '$SERVICE' does not exist in $AWS_REGION. Skipping."
                continue
            fi

            # Check if image with tag exists
            DIGEST=$(aws ecr describe-images --repository-name "$SERVICE" --region "$AWS_REGION" \
                --image-ids imageTag="$TARGET_TAG" --query "imageDetails[0].imageDigest" --output text 2>/dev/null || true)

            if [ -n "$DIGEST" ] && [ "$DIGEST" != "None" ]; then
                echo "   Found image tag '$TARGET_TAG' (Digest: $DIGEST)"
                if [ "$DRY_RUN" = true ]; then
                    echo "   [DRY RUN] Would delete: imageTag=$TARGET_TAG"
                else
                    aws ecr batch-delete-image --repository-name "$SERVICE" --region "$AWS_REGION" \
                        --image-ids imageTag="$TARGET_TAG" >/dev/null
                    echo "   ✔ Successfully deleted tag '$TARGET_TAG' from $SERVICE."
                fi
            else
                echo "   ℹ No image found with tag '$TARGET_TAG'."
            fi
        done
        ;;

    untagged)
        echo "🔍 Searching and deleting untagged images..."
        for SERVICE in "${SERVICES[@]}"; do
            echo "── Repository: $SERVICE"
            if ! aws ecr describe-repositories --repository-names "$SERVICE" --region "$AWS_REGION" >/dev/null 2>&1; then
                echo "   ⚠️  Repository '$SERVICE' does not exist. Skipping."
                continue
            fi

            UNTAGGED_DIGESTS=$(aws ecr list-images --repository-name "$SERVICE" --region "$AWS_REGION" \
                --filter "tagStatus=UNTAGGED" --query "imageIds[*].imageDigest" --output text 2>/dev/null || true)

            if [ -n "$UNTAGGED_DIGESTS" ] && [ "$UNTAGGED_DIGESTS" != "None" ]; then
                IMAGE_IDS_JSON=""
                for DIGEST in $UNTAGGED_DIGESTS; do
                    IMAGE_IDS_JSON="${IMAGE_IDS_JSON} imageDigest=${DIGEST}"
                done

                COUNT=$(echo "$UNTAGGED_DIGESTS" | wc -w)
                echo "   Found $COUNT untagged image(s)."

                if [ "$DRY_RUN" = true ]; then
                    echo "   [DRY RUN] Would delete $COUNT untagged image(s)."
                else
                    aws ecr batch-delete-image --repository-name "$SERVICE" --region "$AWS_REGION" \
                        --image-ids $IMAGE_IDS_JSON >/dev/null
                    echo "   ✔ Deleted $COUNT untagged image(s) from $SERVICE."
                fi
            else
                echo "   ℹ No untagged images found."
            fi
        done
        ;;

    all_images)
        echo "🔍 Deleting ALL images across all service repositories..."
        for SERVICE in "${SERVICES[@]}"; do
            echo "── Repository: $SERVICE"
            if ! aws ecr describe-repositories --repository-names "$SERVICE" --region "$AWS_REGION" >/dev/null 2>&1; then
                echo "   ⚠️  Repository '$SERVICE' does not exist. Skipping."
                continue
            fi

            ALL_DIGESTS=$(aws ecr list-images --repository-name "$SERVICE" --region "$AWS_REGION" \
                --query "imageIds[*].imageDigest" --output text 2>/dev/null || true)

            if [ -n "$ALL_DIGESTS" ] && [ "$ALL_DIGESTS" != "None" ]; then
                IMAGE_IDS_JSON=""
                for DIGEST in $ALL_DIGESTS; do
                    IMAGE_IDS_JSON="${IMAGE_IDS_JSON} imageDigest=${DIGEST}"
                done

                COUNT=$(echo "$ALL_DIGESTS" | wc -w)
                echo "   Found $COUNT total image(s)."

                if [ "$DRY_RUN" = true ]; then
                    echo "   [DRY RUN] Would delete $COUNT image(s)."
                else
                    aws ecr batch-delete-image --repository-name "$SERVICE" --region "$AWS_REGION" \
                        --image-ids $IMAGE_IDS_JSON >/dev/null
                    echo "   ✔ Emptied repository $SERVICE ($COUNT images deleted)."
                fi
            else
                echo "   ℹ Repository is already empty."
            fi
        done
        ;;

    delete_repos)
        echo "⚠️  Deleting ECR repositories..."
        for SERVICE in "${SERVICES[@]}"; do
            echo "── Repository: $SERVICE"
            if ! aws ecr describe-repositories --repository-names "$SERVICE" --region "$AWS_REGION" >/dev/null 2>&1; then
                echo "   ℹ Repository '$SERVICE' does not exist. Skipping."
                continue
            fi

            if [ "$DRY_RUN" = true ]; then
                echo "   [DRY RUN] Would delete repository '$SERVICE' (--force)."
            else
                aws ecr delete-repository --repository-name "$SERVICE" --region "$AWS_REGION" --force >/dev/null
                echo "   ✔ Repository '$SERVICE' deleted."
            fi
        done
        ;;
esac

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                  🎉 OPERATION COMPLETE                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
