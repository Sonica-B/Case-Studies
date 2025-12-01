#!/bin/bash
# ============================================================================
# GCP CLOUD RUN DEPLOYMENT - Scene Mood API
# Uses Dockerfile.api - reads PORT env var set by Cloud Run
# ============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_color() { echo -e "${1}${2}${NC}"; }
print_header() {
    echo
    print_color "$BLUE" "========================================="
    print_color "$BLUE" "$1"
    print_color "$BLUE" "========================================="
}

# ============================================================================
# CONFIGURATION
# ============================================================================
PROJECT_ID="${GCP_PROJECT_ID:-}"
REGION="${GCP_REGION:-us-central1}"
REPO_NAME="scene-mood-classifier"
IMAGE_NAME="scene-mood-api"
SERVICE_NAME="scene-mood-api"
HF_TOKEN="${HF_TOKEN:-}"

# Cost-optimized settings
MEMORY="512Mi"
CPU="1"
MIN_INSTANCES="0"
MAX_INSTANCES="1"

# ============================================================================
# PRE-FLIGHT CHECKS
# ============================================================================
print_header "Pre-flight Checks"

command -v gcloud &>/dev/null || { print_color "$RED" "❌ gcloud CLI not found"; exit 1; }
print_color "$GREEN" "✅ gcloud CLI found"

[ -f "Dockerfile.api" ] || { print_color "$RED" "❌ Dockerfile.api not found"; exit 1; }
print_color "$GREEN" "✅ Dockerfile.api found"

[ -f "fusion-app/app_api.py" ] || { print_color "$RED" "❌ fusion-app/app_api.py not found"; exit 1; }
print_color "$GREEN" "✅ Application files found"

# ============================================================================
# GET CONFIGURATION
# ============================================================================
print_header "Configuration"

if [ -z "$PROJECT_ID" ]; then
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" == "(unset)" ]; then
        read -p "Enter GCP Project ID: " PROJECT_ID
    fi
fi
print_color "$GREEN" "Project: $PROJECT_ID"
print_color "$GREEN" "Region: $REGION"

if [ -z "$HF_TOKEN" ]; then
    read -p "HuggingFace Token (required): " HF_TOKEN
fi
[ -z "$HF_TOKEN" ] && { print_color "$RED" "❌ HF_TOKEN required!"; exit 1; }
print_color "$GREEN" "✅ HF_TOKEN configured"

# ============================================================================
# GCP SETUP
# ============================================================================
print_header "GCP Setup"

gcloud config set project "$PROJECT_ID" --quiet
print_color "$GREEN" "✅ Project set: $PROJECT_ID"

# Enable required APIs
for API in run.googleapis.com artifactregistry.googleapis.com cloudbuild.googleapis.com; do
    gcloud services enable "$API" --quiet 2>/dev/null || true
done
print_color "$GREEN" "✅ APIs enabled"

# Create Artifact Registry repository
if ! gcloud artifacts repositories describe "$REPO_NAME" --location="$REGION" &>/dev/null; then
    print_color "$YELLOW" "Creating Artifact Registry repository..."
    gcloud artifacts repositories create "$REPO_NAME" \
        --repository-format=docker \
        --location="$REGION" \
        --quiet
fi
print_color "$GREEN" "✅ Artifact Registry ready"

# ============================================================================
# PREPARE BUILD
# ============================================================================
print_header "Preparing Build"

# Create .gcloudignore
cat > .gcloudignore << 'EOF'
.git
__pycache__
*.pyc
.env*
*.md
docs/
tests/
monitoring/
grafana/
*.log
.venv
venv/
docker-compose*.yml
prometheus.yml
*.sh
Dockerfile.local
!Dockerfile.api
EOF

# Cloud Build expects 'Dockerfile' by default
if [ -f "Dockerfile" ]; then
    mv Dockerfile Dockerfile.backup
fi
cp Dockerfile.api Dockerfile
print_color "$GREEN" "✅ Dockerfile.api → Dockerfile"

# ============================================================================
# BUILD IMAGE
# ============================================================================
print_header "Building Image with Cloud Build"

IMAGE_TAG="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${IMAGE_NAME}:latest"

print_color "$YELLOW" "Building image (2-3 min for minimal API image)..."
gcloud builds submit \
    --tag "$IMAGE_TAG" \
    --timeout=600 \
    --quiet .

BUILD_STATUS=$?

# Restore original Dockerfile
rm -f Dockerfile
[ -f "Dockerfile.backup" ] && mv Dockerfile.backup Dockerfile

if [ $BUILD_STATUS -ne 0 ]; then
    print_color "$RED" "❌ Build failed!"
    rm -f .gcloudignore
    exit 1
fi
print_color "$GREEN" "✅ Image built: $IMAGE_TAG"

# ============================================================================
# DEPLOY TO CLOUD RUN
# ============================================================================
print_header "Deploying to Cloud Run"

# NOTE: Cloud Run sets PORT env var automatically
# Our app reads PORT and binds to 0.0.0.0:$PORT
gcloud run deploy "$SERVICE_NAME" \
    --image="$IMAGE_TAG" \
    --region="$REGION" \
    --platform=managed \
    --allow-unauthenticated \
    --memory="$MEMORY" \
    --cpu="$CPU" \
    --min-instances="$MIN_INSTANCES" \
    --max-instances="$MAX_INSTANCES" \
    --timeout=300s \
    --concurrency=10 \
    --set-env-vars="HF_TOKEN=${HF_TOKEN}" \
    --cpu-throttling \
    --quiet

SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" \
    --region="$REGION" \
    --format='value(status.url)')

# Cleanup
rm -f .gcloudignore

# ============================================================================
# DEPLOYMENT COMPLETE
# ============================================================================
print_header "Deployment Complete!"

echo
print_color "$GREEN" "🎉 Scene Mood Classifier deployed to GCP Cloud Run!"
echo
print_color "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_color "$BLUE" "URL: $SERVICE_URL"
print_color "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
print_color "$YELLOW" "Useful Commands:"
echo "  View logs:  gcloud run services logs read $SERVICE_NAME --region=$REGION"
echo "  Delete:     gcloud run services delete $SERVICE_NAME --region=$REGION --quiet"
echo

# Save deployment info
cat > gcp_deployment_info.txt << EOF
GCP Cloud Run Deployment
========================
Date: $(date)
Project: $PROJECT_ID
Region: $REGION
Service: $SERVICE_NAME
URL: $SERVICE_URL
Image: $IMAGE_TAG

Configuration:
- Memory: $MEMORY
- CPU: $CPU
- Min Instances: $MIN_INSTANCES (scale-to-zero)
- Max Instances: $MAX_INSTANCES
EOF

print_color "$GREEN" "✅ Saved: gcp_deployment_info.txt"