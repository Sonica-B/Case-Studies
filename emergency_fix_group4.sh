#!/bin/bash

# ============================================================================
# EMERGENCY FIX SCRIPT FOR GROUP4 - FIXES ALL CRITICAL ISSUES
# ============================================================================
# This script will:
# 1. Diagnose why containers are failing
# 2. Fix Python startup issues
# 3. Clean up ngrok processes
# 4. Set up GROUP4 ngrok correctly
# 5. Restart all services properly
# ============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# SSH connection details
SSH_KEY="./.ssh/vm"
VM_USER="group4"
VM_HOST="melnibone.wpi.edu"
VM_PORT="2222"

echo -e "${RED}======================================${NC}"
echo -e "${RED}   EMERGENCY FIX FOR GROUP4${NC}"
echo -e "${RED}======================================${NC}"
echo

# Function to print headers
print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

print_header "Step 1: Diagnosing Container Failures"

ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << 'DIAGNOSE'
# Colors for remote
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}Checking why GROUP4 containers are failing...${NC}"
echo

# Check logs for ml-api container
echo "Last logs from group4-ml-api-product:"
docker logs --tail 20 group4-ml-api-product 2>&1 | head -20 || echo "No logs available"
echo

# Check logs for ml-local container
echo "Last logs from group4-ml-local-product:"
docker logs --tail 20 group4-ml-local-product 2>&1 | head -20 || echo "No logs available"
echo

# Stop the failing containers
echo -e "${YELLOW}Stopping failing containers...${NC}"
docker stop group4-ml-api-product group4-ml-local-product 2>/dev/null
docker rm group4-ml-api-product group4-ml-local-product 2>/dev/null
echo "Containers stopped and removed"
DIAGNOSE

print_header "Step 2: Cleaning Up Old Ngrok Processes"

ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << 'CLEANUP'
# Colors for remote
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Current ngrok processes:${NC}"
ps aux | grep ngrok | grep -v grep

echo -e "\n${YELLOW}Killing old GROUP4 ngrok processes...${NC}"

# Kill the old ngrok from Oct 31
if pgrep -f "ngrok http 5000 --log=stdout" > /dev/null; then
    echo "Killing old ngrok (port 5000) from Oct 31..."
    pkill -f "ngrok http 5000 --log=stdout"
fi

# Kill any ngrok on port 4044 that's misconfigured
if curl -s http://localhost:4044/api/tunnels | grep -q "32150"; then
    echo "Killing misconfigured ngrok on port 4044..."
    for pid in $(pgrep -f "ngrok.*4044"); do
        kill $pid 2>/dev/null
    done
fi

# Clean up any GROUP4 ngrok processes
for pid in $(pgrep -u group4 -f ngrok); do
    echo "Stopping GROUP4 ngrok PID: $pid"
    kill $pid 2>/dev/null
done

sleep 3
echo -e "${GREEN}Old ngrok processes cleaned up${NC}"
CLEANUP

print_header "Step 3: Fixing and Starting GROUP4 Containers"

ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << 'FIX_CONTAINERS'
# Colors for remote
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

cd ~/Case-Studies

echo -e "${YELLOW}Checking Dockerfile CMD issues...${NC}"

# Quick fix: Create a startup script that ensures Python starts correctly
cat > start_api.sh << 'SCRIPT_EOF'
#!/bin/sh
echo "Starting GROUP4 ML API..."
# Start node exporter in background
prometheus-node-exporter --web.listen-address=:5002 &
# Give it a moment to start
sleep 2
# Start the Python application
cd /opt/app
echo "Starting Gradio application on port 5000..."
python fusion-app/app_api_prometheus.py
SCRIPT_EOF

cat > start_local.sh << 'SCRIPT_EOF'
#!/bin/sh
echo "Starting GROUP4 ML Local..."
# Start node exporter in background
prometheus-node-exporter --web.listen-address=:5005 &
# Give it a moment to start
sleep 2
# Start the Python application
cd /opt/app
echo "Starting Gradio application on port 5003..."
python fusion-app/app_local_prometheus.py
SCRIPT_EOF

chmod +x start_api.sh start_local.sh

echo -e "${YELLOW}Starting GROUP4 containers with proper configuration...${NC}"

# Start ML API container with the fix
docker run -d \
    --name group4-ml-api-product \
    --network case-studies_group4-network \
    -p 5000:5000 -p 5001:5001 -p 5002:5002 \
    -e HF_TOKEN="${HF_TOKEN}" \
    -e GRADIO_SERVER_NAME=0.0.0.0 \
    -e GRADIO_SERVER_PORT=5000 \
    --restart unless-stopped \
    -v $(pwd)/start_api.sh:/start.sh \
    group4-ml-api:latest \
    sh /start.sh

# Start ML Local container with the fix
docker run -d \
    --name group4-ml-local-product \
    --network case-studies_group4-network \
    -p 5003:5003 -p 5004:5004 -p 5005:5005 \
    -e GRADIO_SERVER_NAME=0.0.0.0 \
    -e GRADIO_SERVER_PORT=5003 \
    -v group4-model-cache:/root/.cache/huggingface \
    -v $(pwd)/start_local.sh:/start.sh \
    --restart unless-stopped \
    group4-ml-api:latest \
    sh /start.sh

echo "Waiting for containers to stabilize (30 seconds)..."
sleep 30

# Check if containers are running
echo -e "\n${BLUE}Container Status:${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "NAMES|group4"

# Test if services are responding
echo -e "\n${BLUE}Testing services:${NC}"
for port in 5000 5003 5006 5007; do
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:$port | grep -q "200\|302"; then
        echo -e "  Port $port: ${GREEN}✓ Responding${NC}"
    else
        echo -e "  Port $port: ${RED}✗ Not responding${NC}"
    fi
done
FIX_CONTAINERS

print_header "Step 4: Setting Up GROUP4 Ngrok Correctly"

ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << 'SETUP_NGROK'
# Colors for remote
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

cd ~/Case-Studies

echo -e "${YELLOW}Setting up GROUP4 ngrok on port 4044...${NC}"

# Get ngrok auth token
NGROK_AUTHTOKEN=$(grep "NGROK_AUTHTOKEN=" /home/group4/.envrc 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "")

if [ -z "$NGROK_AUTHTOKEN" ]; then
    echo -e "${RED}Warning: No NGROK_AUTHTOKEN found${NC}"
    echo "Please set NGROK_AUTHTOKEN in your .envrc file"
else
    ngrok config add-authtoken $NGROK_AUTHTOKEN
fi

# Create proper GROUP4 ngrok configuration
cat > ngrok-group4.yml << NGROK_EOF
version: "2"
authtoken: $NGROK_AUTHTOKEN
web_addr: 127.0.0.1:4044
tunnels:
  ml-api:
    proto: http
    addr: 5000
    inspect: true
  ml-api-metrics:
    proto: http
    addr: 5001
    inspect: false
  ml-api-exporter:
    proto: http
    addr: 5002
    inspect: false
  ml-local:
    proto: http
    addr: 5003
    inspect: true
  ml-local-metrics:
    proto: http
    addr: 5004
    inspect: false
  ml-local-exporter:
    proto: http
    addr: 5005
    inspect: false
  prometheus:
    proto: http
    addr: 5006
    inspect: true
  grafana:
    proto: http
    addr: 5007
    inspect: true
NGROK_EOF

# Start ngrok with GROUP4 configuration
echo -e "${YELLOW}Starting GROUP4 ngrok...${NC}"
nohup ngrok start --all --config ngrok-group4.yml > ngrok-group4.log 2>&1 &
NGROK_PID=$!
echo "Started ngrok with PID: $NGROK_PID"

# Wait for ngrok to initialize
echo "Waiting for ngrok to initialize..."
sleep 5

# Check if ngrok is running
if ps -p $NGROK_PID > /dev/null; then
    echo -e "${GREEN}✓ Ngrok started successfully${NC}"

    # Display the public URLs
    echo -e "\n${BLUE}GROUP4 Public URLs:${NC}"
    curl -s http://localhost:4044/api/tunnels | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for tunnel in data.get('tunnels', []):
        if tunnel.get('proto') == 'https':
            name = tunnel.get('name', 'unknown')
            url = tunnel.get('public_url', '')
            addr = tunnel.get('config', {}).get('addr', '')
            if 'ml-api' in name and '5000' in addr:
                print(f'  🎨 CLIP Model (API): {url}')
            elif 'ml-local' in name and '5003' in addr:
                print(f'  🎤 Wav2Vec2 (Local): {url}')
            elif 'prometheus' in name:
                print(f'  📊 Prometheus: {url}')
            elif 'grafana' in name:
                print(f'  📈 Grafana: {url}')
except Exception as e:
    print(f'Error getting URLs: {e}')
"
else
    echo -e "${RED}✗ Ngrok failed to start${NC}"
    echo "Check ngrok-group4.log for errors"
fi
SETUP_NGROK

print_header "Step 5: Final Status Check"

ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << 'FINAL_CHECK'
# Colors for remote
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== FINAL STATUS ===${NC}"
echo

# Container status
echo -e "${YELLOW}GROUP4 Containers:${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "NAMES|group4"

echo

# Port status
echo -e "${YELLOW}GROUP4 Ports (5000-5009):${NC}"
for port in {5000..5009}; do
    if ss -tlnp 2>/dev/null | grep -q ":$port "; then
        echo -e "  Port $port: ${GREEN}IN USE${NC}"
    else
        echo -e "  Port $port: AVAILABLE"
    fi
done

echo

# Ngrok status
echo -e "${YELLOW}Ngrok Status:${NC}"
if curl -s http://localhost:4044/api/tunnels > /dev/null 2>&1; then
    tunnel_count=$(curl -s http://localhost:4044/api/tunnels | python3 -c "import json,sys; print(len(json.load(sys.stdin).get('tunnels',[])))" 2>/dev/null)
    echo -e "  GROUP4 Ngrok (port 4044): ${GREEN}✓ Running with $tunnel_count tunnels${NC}"
else
    echo -e "  GROUP4 Ngrok (port 4044): ${RED}✗ Not running${NC}"
fi

echo
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}   EMERGENCY FIX COMPLETE${NC}"
echo -e "${GREEN}======================================${NC}"
echo
echo "Next steps:"
echo "1. Run: ./check_group4_urls.sh to see your public URLs"
echo "2. Test your services via the ngrok URLs"
echo "3. Check Prometheus at port 5006 and Grafana at port 5007"

FINAL_CHECK