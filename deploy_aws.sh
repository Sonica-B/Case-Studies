#!/bin/bash
# ============================================================================
# AWS ECS FARGATE DEPLOYMENT - Scene Mood API
# Uses Dockerfile.api - port 7860
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
AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="cs553"
TASK_FAMILY="scene-mood-classifier"
CONTAINER_PORT="7860"
DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME:-}"
HF_TOKEN="${HF_TOKEN:-}"
CPU="256"
MEMORY="512"

# ============================================================================
# PRE-FLIGHT CHECKS
# ============================================================================
print_header "Pre-flight Checks"

command -v aws &>/dev/null || { print_color "$RED" "❌ AWS CLI not found"; exit 1; }
print_color "$GREEN" "✅ AWS CLI found"

command -v docker &>/dev/null || { print_color "$RED" "❌ Docker not found"; exit 1; }
print_color "$GREEN" "✅ Docker found"

[ -f "Dockerfile.api" ] || { print_color "$RED" "❌ Dockerfile.api not found"; exit 1; }
print_color "$GREEN" "✅ Dockerfile.api found"

[ -f "fusion-app/app_api.py" ] || { print_color "$RED" "❌ fusion-app/app_api.py not found"; exit 1; }
print_color "$GREEN" "✅ Application files found"

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
# AWS SETUP
# ============================================================================
print_header "AWS Setup"

# CloudWatch log group
aws logs create-log-group --log-group-name "/ecs/$TASK_FAMILY" --region "$AWS_REGION" 2>/dev/null || true
print_color "$GREEN" "✅ Log group ready"

# ECS Cluster
CLUSTER_EXISTS=$(aws ecs describe-clusters --clusters "$CLUSTER_NAME" --region "$AWS_REGION" \
    --query "clusters[?status=='ACTIVE'].clusterName" --output text 2>/dev/null)
if [ "$CLUSTER_EXISTS" != "$CLUSTER_NAME" ]; then
    aws ecs create-cluster --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null
fi
print_color "$GREEN" "✅ Cluster: $CLUSTER_NAME"

# VPC and Subnet
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" \
    --region "$AWS_REGION" --query 'Vpcs[0].VpcId' --output text)
SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" \
    --region "$AWS_REGION" --query 'Subnets[0].SubnetId' --output text)
print_color "$GREEN" "✅ VPC: $VPC_ID | Subnet: $SUBNET_ID"

# Security Group
SG_NAME="ecs-scene-mood-sg"
SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" \
    --region "$AWS_REGION" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)

if [ "$SG_ID" == "None" ] || [ -z "$SG_ID" ]; then
    SG_ID=$(aws ec2 create-security-group \
        --group-name "$SG_NAME" \
        --description "ECS Scene Mood Classifier" \
        --vpc-id "$VPC_ID" \
        --region "$AWS_REGION" \
        --query 'GroupId' --output text)
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port $CONTAINER_PORT \
        --cidr 0.0.0.0/0 \
        --region "$AWS_REGION" 2>/dev/null || true
fi
print_color "$GREEN" "✅ Security Group: $SG_ID (port $CONTAINER_PORT open)"

# IAM Role
ROLE_NAME="ecsTaskExecutionRole"
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text 2>/dev/null || echo "")

if [ -z "$ROLE_ARN" ]; then
    print_color "$YELLOW" "Creating IAM role..."
    cat > /tmp/trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "ecs-tasks.amazonaws.com"},
        "Action": "sts:AssumeRole"
    }]
}
EOF
    aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document file:///tmp/trust-policy.json >/dev/null
    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
    ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)
    rm -f /tmp/trust-policy.json
fi
print_color "$GREEN" "✅ IAM Role: $ROLE_NAME"

# ============================================================================
# TASK DEFINITION
# ============================================================================
print_header "Task Definition"

cat > /tmp/taskdef.json << EOF
{
    "family": "$TASK_FAMILY",
    "networkMode": "awsvpc",
    "requiresCompatibilities": ["FARGATE"],
    "cpu": "$CPU",
    "memory": "$MEMORY",
    "executionRoleArn": "$ROLE_ARN",
    "containerDefinitions": [{
        "name": "app",
        "image": "$DOCKERHUB_IMAGE",
        "essential": true,
        "portMappings": [{
            "containerPort": $CONTAINER_PORT,
            "protocol": "tcp"
        }],
        "environment": [
            {"name": "HF_TOKEN", "value": "$HF_TOKEN"},
            {"name": "PORT", "value": "$CONTAINER_PORT"}
        ],
        "logConfiguration": {
            "logDriver": "awslogs",
            "options": {
                "awslogs-group": "/ecs/$TASK_FAMILY",
                "awslogs-region": "$AWS_REGION",
                "awslogs-stream-prefix": "ecs"
            }
        }
    }]
}
EOF

aws ecs register-task-definition \
    --cli-input-json file:///tmp/taskdef.json \
    --region "$AWS_REGION" >/dev/null
rm -f /tmp/taskdef.json
print_color "$GREEN" "✅ Task definition registered"

# ============================================================================
# RUN TASK
# ============================================================================
print_header "Running Task"

# Stop any existing tasks
EXISTING_TASKS=$(aws ecs list-tasks --cluster "$CLUSTER_NAME" --family "$TASK_FAMILY" \
    --region "$AWS_REGION" --query 'taskArns[]' --output text 2>/dev/null)
if [ -n "$EXISTING_TASKS" ] && [ "$EXISTING_TASKS" != "None" ]; then
    print_color "$YELLOW" "Stopping existing tasks..."
    for task in $EXISTING_TASKS; do
        aws ecs stop-task --cluster "$CLUSTER_NAME" --task "$task" --region "$AWS_REGION" >/dev/null 2>&1 || true
    done
    sleep 5
fi

# Start new task
TASK_ARN=$(aws ecs run-task \
    --cluster "$CLUSTER_NAME" \
    --task-definition "$TASK_FAMILY" \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_ID],securityGroups=[$SG_ID],assignPublicIp=ENABLED}" \
    --region "$AWS_REGION" \
    --query 'tasks[0].taskArn' \
    --output text)

TASK_ID=$(echo "$TASK_ARN" | awk -F'/' '{print $NF}')
print_color "$GREEN" "✅ Task started: $TASK_ID"

# Wait for public IP
print_color "$YELLOW" "Waiting for public IP (60s)..."
sleep 60

ENI_ID=$(aws ecs describe-tasks \
    --cluster "$CLUSTER_NAME" \
    --tasks "$TASK_ID" \
    --region "$AWS_REGION" \
    --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' \
    --output text)

PUBLIC_IP=""
if [ -n "$ENI_ID" ] && [ "$ENI_ID" != "None" ]; then
    PUBLIC_IP=$(aws ec2 describe-network-interfaces \
        --network-interface-ids "$ENI_ID" \
        --region "$AWS_REGION" \
        --query 'NetworkInterfaces[0].Association.PublicIp' \
        --output text)
fi

# ============================================================================
# DEPLOYMENT COMPLETE
# ============================================================================
print_header "Deployment Complete!"

echo
print_color "$GREEN" "🎉 Scene Mood Classifier deployed to AWS ECS!"
echo
if [ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "None" ]; then
    print_color "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_color "$BLUE" "URL: http://$PUBLIC_IP:$CONTAINER_PORT"
    print_color "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
    print_color "$YELLOW" "IP pending. Get it with:"
    echo "  aws ecs describe-tasks --cluster $CLUSTER_NAME --tasks $TASK_ID --region $AWS_REGION"
fi
echo
print_color "$YELLOW" "Useful Commands:"
echo "  View logs: aws logs tail /ecs/$TASK_FAMILY --region $AWS_REGION --follow"
echo "  Stop task: aws ecs stop-task --cluster $CLUSTER_NAME --task $TASK_ID --region $AWS_REGION"
echo

# Save deployment info
cat > aws_deployment_info.txt << EOF
AWS ECS Fargate Deployment
==========================
Date: $(date)
URL: http://${PUBLIC_IP:-pending}:$CONTAINER_PORT
Cluster: $CLUSTER_NAME
Task ID: $TASK_ID
Image: $DOCKERHUB_IMAGE
Region: $AWS_REGION

Configuration:
- CPU: $CPU (0.25 vCPU)
- Memory: $MEMORY MB
- Port: $CONTAINER_PORT
EOF

print_color "$GREEN" "✅ Saved: aws_deployment_info.txt"