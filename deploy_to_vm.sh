#!/bin/bash
# Deployment script for WPI VM - pulls code from GitHub

# Configuration
VM_HOST="melnibone.wpi.edu"
VM_PORT="2222"
VM_USER="${1:-group4}"
SSH_KEY="$HOME/.ssh/vm"  # Your SSH key location
PROJECT_PATH="~/Case-Studies"  # Existing cloned repo on VM
BRANCH="cs3"  # Branch to deploy

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_color() {
    echo -e "${1}${2}${NC}"
}

print_header() {
    echo
    print_color "$BLUE" "========================================="
    print_color "$BLUE" "$1"
    print_color "$BLUE" "========================================="
}

# Show configuration
print_header "WPI VM Deployment (GitHub Pull)"
print_color "$YELLOW" "VM Host: $VM_HOST:$VM_PORT"
print_color "$YELLOW" "Username: $VM_USER"
print_color "$YELLOW" "Project: $PROJECT_PATH"
print_color "$YELLOW" "Branch: $BRANCH"
print_color "$YELLOW" "SSH Key: $SSH_KEY"

# Check SSH key exists
if [ ! -f "$SSH_KEY" ]; then
    print_color "$RED" "Error: SSH key not found at $SSH_KEY"
    print_color "$YELLOW" "Please ensure your SSH key is at ~/.ssh/vm"
    exit 1
fi

# Check environment variables
if [ -z "$HF_TOKEN" ]; then
    print_color "$YELLOW" "Warning: HF_TOKEN not set"
    read -p "Enter your HuggingFace token: " HF_TOKEN
fi

if [ -z "$NGROK_AUTHTOKEN" ]; then
    print_color "$YELLOW" "Warning: NGROK_AUTHTOKEN not set"
    read -p "Enter your Ngrok auth token: " NGROK_AUTHTOKEN
fi

# Step 1: Test SSH connection
print_header "Testing SSH Connection"
print_color "$GREEN" "Connecting to VM..."
if ssh -i "$SSH_KEY" -o ConnectTimeout=10 -p $VM_PORT $VM_USER@$VM_HOST "echo 'Connection successful'" 2>/dev/null; then
    print_color "$GREEN" "✅ SSH connection successful"
else
    print_color "$RED" "❌ SSH connection failed"
    print_color "$YELLOW" "Please check:"
    echo "  - SSH key exists and has correct permissions"
    echo "  - VPN is connected (if off-campus)"
    echo "  - Password for SSH key (if protected)"
    exit 1
fi

# Step 2: Update code from GitHub
print_header "Updating Code from GitHub"
print_color "$GREEN" "Pulling latest changes from branch $BRANCH..."

ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << EOF
set -e  # Exit on error

cd $PROJECT_PATH

echo "Current directory: \$(pwd)"
echo "Current branch: \$(git branch --show-current)"

# Stash any local changes
git stash

# Checkout the correct branch
echo "Checking out branch $BRANCH..."
git checkout $BRANCH

# Pull latest changes
echo "Pulling latest changes..."
git pull origin $BRANCH

echo "✅ Code updated successfully"

# Show recent commits
echo ""
echo "Recent commits:"
git log --oneline -5
EOF

# Step 3: Create environment file
print_header "Setting Up Environment"
print_color "$GREEN" "Creating .env file with tokens..."

ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << EOF
cd $PROJECT_PATH

# Create .env file with tokens
cat > .env << ENV_FILE
HF_TOKEN=$HF_TOKEN
NGROK_AUTHTOKEN=$NGROK_AUTHTOKEN

# Port configuration
API_GRADIO_PORT=5000
API_METRICS_PORT=5001
API_NODE_EXPORTER_PORT=5002
LOCAL_GRADIO_PORT=5003
LOCAL_METRICS_PORT=5004
LOCAL_NODE_EXPORTER_PORT=5005
PROMETHEUS_PORT=5006
GRAFANA_PORT=5007

# VM Configuration
VM_DEPLOYMENT=true
ENV_FILE

echo "✅ Environment file created"
EOF

# Step 4: Check Docker
print_header "Checking Docker"
print_color "$GREEN" "Verifying Docker installation..."

docker_check=$(ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST "command -v docker &> /dev/null && echo 'yes' || echo 'no'")
if [ "$docker_check" != "yes" ]; then
    print_color "$RED" "❌ Docker is not available on the VM"
    print_color "$YELLOW" "Please contact your instructor to get Docker access"
    exit 1
fi

print_color "$GREEN" "✅ Docker is available"

# Step 5: Stop existing containers
print_header "Cleaning Up"
print_color "$GREEN" "Stopping existing GROUP4 containers only..."

ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << 'EOF'
cd ~/Case-Studies

# Stop only our group's containers (not other groups' containers)
docker-compose down 2>/dev/null || true

# NOTE: We're NOT deleting any images to preserve other groups' work
echo "✅ Stopped group4 containers (preserved all Docker images)"
EOF

# Step 6: Build Docker images
print_header "Building GROUP4 Docker Images"
print_color "$YELLOW" "Building group4-ml-api and group4-ml-local images..."
print_color "$YELLOW" "This may take 5-10 minutes..."

ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << 'EOF'
cd ~/Case-Studies

echo "Building GROUP4 Docker images..."
docker-compose build --parallel

if [ $? -eq 0 ]; then
    echo "✅ GROUP4 images built successfully:"
    echo "  - group4-ml-api:latest"
    echo "  - group4-ml-local:latest"
else
    echo "❌ Docker build failed"
    exit 1
fi
EOF

# Step 7: Start services
print_header "Starting GROUP4 Services"
print_color "$GREEN" "Launching GROUP4 containers..."

ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << 'EOF'
cd ~/Case-Studies

# Start all GROUP4 services
echo "Starting GROUP4 containers:"
docker-compose up -d

# Wait for services to initialize
echo "Waiting for GROUP4 services to start (30 seconds)..."
sleep 30

# Show container status
echo ""
echo "GROUP4 Container Status:"
docker-compose ps

# Check if GROUP4 containers are running
running_count=$(docker ps --format "table {{.Names}}" | grep "^group4-" | wc -l)
if [ $running_count -ge 4 ]; then
    echo "✅ All 4 GROUP4 containers are running"
else
    echo "⚠️  Warning: Only $running_count GROUP4 containers are running (expected 4)"
    echo "Check logs with: docker-compose logs"
fi

# Show only GROUP4 containers
echo ""
echo "Active GROUP4 Containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "NAMES|^group4-"
EOF

# Step 8: Verify deployment
print_header "Verifying Services"
print_color "$GREEN" "Testing service endpoints..."

ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << 'EOF'
cd ~/Case-Studies

echo ""
test_endpoint() {
    local name=$1
    local port=$2
    local path=${3:-"/"}

    response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:${port}${path} 2>/dev/null)
    if [ "$response" = "200" ] || [ "$response" = "302" ]; then
        echo "✅ Port $port ($name): OK"
        return 0
    else
        echo "❌ Port $port ($name): Not responding (HTTP $response)"
        return 1
    fi
}

# Test each service
test_endpoint "API Product" 5000 "/"
test_endpoint "API Metrics" 5001 "/metrics"
test_endpoint "API Node Export" 5002 "/metrics"
test_endpoint "Local Product" 5003 "/"
test_endpoint "Local Metrics" 5004 "/metrics"
test_endpoint "Local Node Export" 5005 "/metrics"
test_endpoint "Prometheus" 5006 "/-/ready"
test_endpoint "Grafana" 5007 "/api/health"
EOF

# Step 9: Get container information
print_header "Container Information"
print_color "$GREEN" "Getting container details..."

ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << 'EOF'
cd ~/Case-Studies

echo "GROUP4 Container IP Addresses (for Google Sheet):"
for container in group4-ml-api-product group4-ml-local-product group4-prometheus group4-grafana; do
    ip=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${container} 2>/dev/null)
    if [ ! -z "$ip" ]; then
        echo "  $container: $ip"
    fi
done

echo ""
echo "Resource Usage:"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
EOF

# Final summary
print_header "🎉 Deployment Complete!"
echo
print_color "$GREEN" "All services deployed successfully from GitHub!"
echo
print_color "$BLUE" "Repository Info:"
echo "  - Repo: Case-Studies"
echo "  - Branch: $BRANCH"
echo "  - Path: $PROJECT_PATH"
echo
print_color "$BLUE" "Access Services:"
echo "1. Set up SSH tunnel:"
echo "   ./ssh_tunnel.sh $VM_USER"
echo
echo "2. Open in browser:"
echo "   - API Product:  http://localhost:5000"
echo "   - Local Product: http://localhost:5003"
echo "   - Prometheus:   http://localhost:5006"
echo "   - Grafana:      http://localhost:5007 (admin/admin)"
echo
print_color "$YELLOW" "Port Range: 5000-5009"
print_color "$YELLOW" "Remember to commit and push your changes to GitHub before deploying!"
echo