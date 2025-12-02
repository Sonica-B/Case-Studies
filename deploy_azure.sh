#!/bin/bash
# ============================================================================
# AZURE APP SERVICE DEPLOYMENT - Scene Mood API
# Uses Web App for Containers (Microsoft.Web - allowed on student accounts)
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
RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-cs553}"
LOCATION="${AZURE_LOCATION:-eastus}"
APP_SERVICE_PLAN="plan-cs553"
WEB_APP_NAME="scene-mood-api-${RANDOM}"  # Must be globally unique
CONTAINER_PORT="7860"

DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME:-}"
HF_TOKEN="${HF_TOKEN:-}"

# ============================================================================
# PRE-FLIGHT CHECKS
# ============================================================================
print_header "Pre-flight Checks"

command -v az &>/dev/null || { print_color "$RED" "❌ Azure CLI not found"; exit 1; }
print_color "$GREEN" "✅ Azure CLI found"

command -v docker &>/dev/null || { print_color "$RED" "❌ Docker not found"; exit 1; }
print_color "$GREEN" "✅ Docker found"

[ -f "Dockerfile.api" ] || { print_color "$RED" "❌ Dockerfile.api not found"; exit 1; }
print_color "$GREEN" "✅ Dockerfile.api found"

# ============================================================================
# AZURE LOGIN
# ============================================================================
print_header "Azure Login"

if ! az account show &>/dev/null; then
    print_color "$YELLOW" "Please log in to Azure..."
    az login
fi

ACCOUNT_NAME=$(az account show --query "name" -o tsv)
print_color "$GREEN" "✅ Logged in: $ACCOUNT_NAME"

# ============================================================================
# GET CONFIGURATION
# ============================================================================
print_header "Configuration"

[ -z "$HF_TOKEN" ] && read -p "HuggingFace Token (required): " HF_TOKEN
[ -z "$HF_TOKEN" ] && { print_color "$RED" "❌ HF_TOKEN required!"; exit 1; }
print_color "$GREEN" "✅ HF_TOKEN configured"

[ -z "$DOCKERHUB_USERNAME" ] && read -p "Docker Hub username: " DOCKERHUB_USERNAME
DOCKERHUB_IMAGE="${DOCKERHUB_USERNAME}/scene-mood-api:latest"
print_color "$GREEN" "Image: $DOCKERHUB_IMAGE"

# Allow custom web app name
read -p "Web App name (must be globally unique) [$WEB_APP_NAME]: " CUSTOM_NAME
[ -n "$CUSTOM_NAME" ] && WEB_APP_NAME="$CUSTOM_NAME"

# ============================================================================
# BUILD AND PUSH IMAGE
# ============================================================================
print_header "Building Docker Image"

print_color "$YELLOW" "Building from Dockerfile.api..."
docker build -t scene-mood-api -f Dockerfile.api .

print_color "$YELLOW" "Pushing to Docker Hub..."
docker tag scene-mood-api "$DOCKERHUB_IMAGE"
docker push "$DOCKERHUB_IMAGE"
print_color "$GREEN" "✅ Image pushed: $DOCKERHUB_IMAGE"

# ============================================================================
# AZURE SETUP
# ============================================================================
print_header "Azure Setup"

# Create Resource Group
if ! az group show --name "$RESOURCE_GROUP" &>/dev/null; then
    print_color "$YELLOW" "Creating resource group: $RESOURCE_GROUP..."
    az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none
fi
print_color "$GREEN" "✅ Resource group: $RESOURCE_GROUP"

# Create App Service Plan (Linux, B1 tier)
if ! az appservice plan show --name "$APP_SERVICE_PLAN" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    print_color "$YELLOW" "Creating App Service Plan (Linux B1)..."
    az appservice plan create \
        --name "$APP_SERVICE_PLAN" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --is-linux \
        --sku B1 \
        --output none
fi
print_color "$GREEN" "✅ App Service Plan: $APP_SERVICE_PLAN"

# ============================================================================
# DEPLOY WEB APP
# ============================================================================
print_header "Deploying Web App for Containers"

# Create Web App with Docker container
print_color "$YELLOW" "Creating web app: $WEB_APP_NAME..."
az webapp create \
    --name "$WEB_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --plan "$APP_SERVICE_PLAN" \
    --deployment-container-image-name "$DOCKERHUB_IMAGE" \
    --output none

# Configure container settings
print_color "$YELLOW" "Configuring container settings..."
az webapp config appsettings set \
    --name "$WEB_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --settings \
        HF_TOKEN="$HF_TOKEN" \
        PORT="$CONTAINER_PORT" \
        WEBSITES_PORT="$CONTAINER_PORT" \
    --output none

# Enable container logging
az webapp log config \
    --name "$WEB_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --docker-container-logging filesystem \
    --output none

print_color "$GREEN" "✅ Web app deployed"

# Get the URL
SERVICE_URL="${WEB_APP_NAME}.azurewebsites.net"

# ============================================================================
# DEPLOYMENT COMPLETE
# ============================================================================
print_header "Deployment Complete!"

echo
print_color "$GREEN" "🎉 Scene Mood Classifier deployed to Azure App Service!"
echo
print_color "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_color "$BLUE" "URL: https://$SERVICE_URL"
print_color "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
print_color "$YELLOW" "Note: First load may take 1-2 minutes (cold start)"
echo
print_color "$YELLOW" "Useful Commands:"
echo "  View logs:  az webapp log tail --name $WEB_APP_NAME --resource-group $RESOURCE_GROUP"
echo "  Restart:    az webapp restart --name $WEB_APP_NAME --resource-group $RESOURCE_GROUP"
echo "  Delete:     az webapp delete --name $WEB_APP_NAME --resource-group $RESOURCE_GROUP"
echo

# Save deployment info
cat > azure_deployment_info.txt << EOF
Azure App Service Deployment
============================
Date: $(date)
URL: https://$SERVICE_URL
Resource Group: $RESOURCE_GROUP
Web App: $WEB_APP_NAME
App Service Plan: $APP_SERVICE_PLAN
Location: $LOCATION
Image: $DOCKERHUB_IMAGE

Configuration:
- SKU: B1 (Basic)
- Port: $CONTAINER_PORT
EOF

print_color "$GREEN" "✅ Saved: azure_deployment_info.txt"