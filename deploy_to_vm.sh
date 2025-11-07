#!/bin/bash
# Deployment script for WPI VM - pulls code from GitHub

# Configuration
VM_HOST="melnibone.wpi.edu"
VM_PORT="2222"
VM_USER="${1:-group4}"
SSH_KEY="$HOME/.ssh/vm"  # Your SSH key location
PROJECT_PATH="~/Case-Studies"  # Existing cloned repo on VM
BRANCH="cs3"  # Branch to deploy

# Setup SSH command - use automation if available
if [ -f "$HOME/.ssh_group4_connect.sh" ]; then
    SSH_CMD="$HOME/.ssh_group4_connect.sh"
    echo "✨ Using SSH automation (no passphrase needed)..."
elif [ -f "$HOME/.ssh_group4_login.exp" ] && command -v expect &> /dev/null; then
    SSH_CMD() {
        expect "$HOME/.ssh_group4_login.exp" "$@"
    }
    echo "✨ Using expect for SSH automation..."
else
    SSH_CMD() {
        ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST "$@"
    }
fi

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

# Tokens are now stored on the VM in ~/.envrc
# No need to check locally - they will be loaded from the VM
print_color "$GREEN" "Using tokens from VM's ~/.envrc file"

# Step 1: Test SSH connection
print_header "Testing SSH Connection"
print_color "$GREEN" "Connecting to VM..."
if [ -f "$HOME/.ssh_group4_connect.sh" ]; then
    # Use automation script
    if $SSH_CMD "echo 'Connection successful'" 2>/dev/null; then
        print_color "$GREEN" "✅ SSH connection successful"
    else
        print_color "$RED" "❌ SSH connection failed"
        print_color "$YELLOW" "Please check your SSH automation setup"
        exit 1
    fi
else
    # Use regular SSH
    if ssh -i "$SSH_KEY" -o ConnectTimeout=10 -p $VM_PORT $VM_USER@$VM_HOST "echo 'Connection successful'" 2>/dev/null; then
        print_color "$GREEN" "✅ SSH connection successful"
    else
        print_color "$RED" "❌ SSH connection failed"
        print_color "$YELLOW" "Please check:"
        echo "  - SSH key exists and has correct permissions"
        echo "  - VPN is connected (if off-campus)"
        echo "  - Password for SSH key (if protected)"
        echo "  - Or run ./setup_tokens.sh to configure SSH automation"
        exit 1
    fi
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

# Source tokens from ~/.envrc if it exists
if [ -f ~/.envrc ]; then
    source ~/.envrc
fi

# Create .env file with tokens from .envrc
cat > .env << ENV_FILE
HF_TOKEN=\${HF_TOKEN}
NGROK_AUTHTOKEN=\${NGROK_AUTHTOKEN}

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

if [ -f "$HOME/.ssh_group4_connect.sh" ]; then
    docker_check=$($SSH_CMD "command -v docker &> /dev/null && echo 'yes' || echo 'no'")
else
    docker_check=$(ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST "command -v docker &> /dev/null && echo 'yes' || echo 'no'")
fi

if [ "$docker_check" != "yes" ]; then
    print_color "$RED" "❌ Docker is not available on the VM"
    print_color "$YELLOW" "Please contact your instructor to get Docker access"
    exit 1
fi

print_color "$GREEN" "✅ Docker is available"

# Step 5: Stop existing containers
print_header "Cleaning Up GROUP4 Only"
print_color "$GREEN" "Stopping ONLY GROUP4 containers (preserving all other teams)..."

ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << 'EOF'
cd ~/Case-Studies

# IMPORTANT: Only stop GROUP4 containers by name
echo "Stopping GROUP4 containers specifically..."
for container in group4-ml-api-product group4-ml-local-product group4-prometheus group4-grafana; do
    if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
        echo "  Stopping ${container}..."
        docker stop ${container} 2>/dev/null || true
        docker rm ${container} 2>/dev/null || true
    fi
done

# NOTE: We're NOT using docker-compose down to avoid any risk
# NOTE: We're NOT deleting ANY images to preserve all teams' work
# NOTE: We're NOT touching any non-GROUP4 containers
echo "✅ Stopped only GROUP4 containers (all other teams untouched)"
EOF

# Step 6: Build Docker images
print_header "Building GROUP4 Docker Images"
print_color "$YELLOW" "Building group4-ml-api and group4-ml-local images..."
print_color "$YELLOW" "This may take 5-10 minutes..."

ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << 'EOF'
cd ~/Case-Studies

# Source environment variables if they exist
if [ -f ~/.envrc ]; then
    source ~/.envrc
    echo "✅ Loaded environment variables from ~/.envrc"
else
    echo "⚠️  No ~/.envrc found. Run setup_tokens.sh first!"
fi

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

# Source environment variables
if [ -f ~/.envrc ]; then
    source ~/.envrc
    export HF_TOKEN
    export NGROK_AUTHTOKEN
fi

# Start ONLY GROUP4 services explicitly
echo "Starting GROUP4 containers:"
docker-compose up -d ml-api ml-local prometheus grafana

# Wait for services to initialize
echo "Waiting for GROUP4 services to start (30 seconds)..."
sleep 30

# Show container status for GROUP4 only
echo ""
echo "GROUP4 Container Status:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "NAMES|^group4-"

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

# Step 10: Start Ngrok tunnels
print_header "Setting up Ngrok Tunnels"
print_color "$GREEN" "Starting ngrok for public access..."

ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << 'EOF'
cd ~/Case-Studies

# Source environment variables
if [ -f ~/.envrc ]; then
    source ~/.envrc
fi

# Check if ngrok is installed
if ! command -v ngrok &> /dev/null; then
    echo "Installing ngrok..."
    curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
    echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | sudo tee /etc/apt/sources.list.d/ngrok.list
    sudo apt update && sudo apt install ngrok -y
fi

# Configure ngrok with token from .envrc
if [ -n "$NGROK_AUTHTOKEN" ]; then
    ngrok config add-authtoken $NGROK_AUTHTOKEN
else
    echo "⚠️  No NGROK_AUTHTOKEN found. Ngrok may not work properly."
fi

# IMPORTANT: Only stop GROUP4's ngrok, never touch other teams'
# Check for GROUP4 ngrok specifically (by config file or port 4044)
if pgrep -f "ngrok.*group4|ngrok.*4044" > /dev/null; then
    echo "Found existing GROUP4 ngrok process..."
    # Only kill GROUP4's ngrok processes
    for pid in $(pgrep -f "ngrok.*group4|ngrok.*4044"); do
        echo "  Stopping GROUP4 ngrok PID: $pid"
        kill $pid 2>/dev/null || true
    done
    sleep 2
else
    echo "No existing GROUP4 ngrok found"
fi

# Verify other teams' ngrok is still running
if pgrep -f "ngrok" | grep -v -E "group4|4044" > /dev/null; then
    echo "✅ Other teams' ngrok processes are still running"
fi

# Create ngrok config for GROUP4 with unique web address port
cat > ngrok-group4.yml << NGROK_EOF
version: "2"
authtoken: $NGROK_AUTHTOKEN
web_addr: 127.0.0.1:4044  # GROUP4's unique ngrok web port
tunnels:
  group4-api:
    proto: http
    addr: 5000
    inspect: false
  group4-local:
    proto: http
    addr: 5003
    inspect: false
  group4-prometheus:
    proto: http
    addr: 5006
    inspect: false
  group4-grafana:
    proto: http
    addr: 5007
    inspect: false
NGROK_EOF

# Start GROUP4's ngrok with unique config
nohup ngrok start --all --config ngrok-group4.yml > ngrok-group4.log 2>&1 &
sleep 8

# Get URLs
echo ""
echo "Fetching GROUP4 Ngrok public URLs..."
curl -s http://localhost:4044/api/tunnels | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print('\\n🌐 PUBLIC URLs (Share these):')
    print('=' * 40)
    for tunnel in data.get('tunnels', []):
        name = tunnel.get('name', 'unknown')
        url = tunnel.get('public_url', 'N/A')
        if 'group4' in name:
            if 'api' in name and 'https' in url:
                print(f'API Product: {url}')
            elif 'local' in name and 'https' in url:
                print(f'Local Product: {url}')
            elif 'prometheus' in name:
                print(f'Prometheus: {url}')
            elif 'grafana' in name:
                print(f'Grafana: {url}')
    print('=' * 40)
except:
    print('Could not fetch ngrok URLs - check ngrok.log')
"
EOF

# Final summary
print_header "🎉 Deployment Complete!"
echo
print_color "$GREEN" "GROUP4 services deployed successfully!"
echo
print_color "$BLUE" "Repository Info:"
echo "  - Repo: Case-Studies"
echo "  - Branch: $BRANCH"
echo "  - Path: $PROJECT_PATH"
echo
print_color "$BLUE" "Access Options:"
echo
echo "1. Via Ngrok Public URLs (shown above)"
echo "   - Share these URLs with anyone"
echo "   - No SSH tunnel needed"
echo
echo "2. Via SSH Tunnel (local access):"
echo "   ./ssh_tunnel.sh $VM_USER"
echo "   Then use: http://localhost:5000, etc."
echo
print_color "$YELLOW" "Port Range: 5000-5009"
print_color "$YELLOW" "To check GROUP4 ngrok status on VM: ssh to VM and run 'curl http://localhost:4044/api/tunnels'"
echo