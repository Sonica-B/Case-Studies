#!/bin/bash
# Cleanup AWS ECS deployment

set -e

AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="cs553"
TASK_FAMILY="scene-mood-classifier"

echo "Stopping tasks..."
TASKS=$(aws ecs list-tasks --cluster "$CLUSTER_NAME" --family "$TASK_FAMILY" \
    --region "$AWS_REGION" --query 'taskArns[]' --output text 2>/dev/null)
for task in $TASKS; do
    aws ecs stop-task --cluster "$CLUSTER_NAME" --task "$task" --region "$AWS_REGION" >/dev/null 2>&1 || true
done

echo "Deregistering task definitions..."
TASK_DEFS=$(aws ecs list-task-definitions --family-prefix "$TASK_FAMILY" \
    --region "$AWS_REGION" --query 'taskDefinitionArns[]' --output text 2>/dev/null)
for td in $TASK_DEFS; do
    aws ecs deregister-task-definition --task-definition "$td" --region "$AWS_REGION" >/dev/null 2>&1 || true
done

rm -f aws_deployment_info.txt

echo "✅ AWS cleanup complete (cluster and security group preserved)"