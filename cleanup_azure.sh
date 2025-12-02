#!/bin/bash
# ============================================================================
# AZURE CONTAINER APPS CLEANUP
# ============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_color() { echo -e "${1}${2}${NC}"; }

RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-cs553}"
CONTAINER_APP_NAME="scene-mood-api"
ENVIRONMENT_NAME="env-cs553"

print_color "$BLUE" "Azure Container Apps Cleanup"
print_color "$BLUE" "============================"
echo

# Check Azure login
if ! az account show &>/dev/null; then
    print_color "$YELLOW" "Please log in to Azure..."
    az login
fi

# Delete Container App
print_color "$YELLOW" "Deleting container app: $CONTAINER_APP_NAME..."
az containerapp delete \
    --name "$CONTAINER_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --yes 2>/dev/null || echo "Container app not found"

# Optionally delete environment
read -p "Delete Container Apps Environment? (y/n): " DELETE_ENV
if [ "$DELETE_ENV" = "y" ]; then
    print_color "$YELLOW" "Deleting environment: $ENVIRONMENT_NAME..."
    az containerapp env delete \
        --name "$ENVIRONMENT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --yes 2>/dev/null || echo "Environment not found"
fi

# Optionally delete resource group (CAUTION: deletes everything!)
read -p "Delete entire resource group '$RESOURCE_GROUP'? (y/n): " DELETE_RG
if [ "$DELETE_RG" = "y" ]; then
    print_color "$RED" "Deleting resource group (this removes ALL resources)..."
    az group delete --name "$RESOURCE_GROUP" --yes --no-wait
    print_color "$YELLOW" "Resource group deletion initiated (runs in background)"
fi

rm -f azure_deployment_info.txt

print_color "$GREEN" "✅ Azure cleanup complete"