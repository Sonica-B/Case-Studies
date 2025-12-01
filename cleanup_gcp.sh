#!/bin/bash
# Cleanup GCP Cloud Run deployment

set -e

REGION="${GCP_REGION:-us-central1}"
SERVICE_NAME="scene-mood-api"
REPO_NAME="scene-mood-classifier"

echo "Deleting Cloud Run service..."
gcloud run services delete "$SERVICE_NAME" --region="$REGION" --quiet 2>/dev/null || echo "Service not found"

echo "Deleting images from Artifact Registry..."
gcloud artifacts docker images delete \
    "${REGION}-docker.pkg.dev/$(gcloud config get-value project)/${REPO_NAME}/${SERVICE_NAME}" \
    --quiet 2>/dev/null || echo "Images not found"

rm -f gcp_deployment_info.txt .gcloudignore

echo "✅ GCP cleanup complete"