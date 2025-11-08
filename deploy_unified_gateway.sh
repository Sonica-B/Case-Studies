#!/bin/bash

# ============================================================================
# UNIFIED GATEWAY DEPLOYMENT
# Single endpoint for both models with toggle functionality
# Only needs 1 ngrok endpoint!
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SSH_KEY="$HOME/.ssh/vm"
VM_USER="group4"
VM_HOST="melnibone.wpi.edu"
VM_PORT="2222"

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}   UNIFIED GATEWAY DEPLOYMENT${NC}"
echo -e "${GREEN}======================================${NC}"
echo

ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << 'DEPLOY_GATEWAY'

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

cd ~/Case-Studies

# Source environment
if [ -f ~/.envrc ]; then
    source ~/.envrc
fi

echo -e "${YELLOW}Step 1: Installing Flask for smart proxy...${NC}"
pip install flask requests --user

echo -e "${YELLOW}Step 2: Stopping any existing gateway...${NC}"
pkill -f "smart_proxy.py" || true
pkill -f "unified_gateway.py" || true

echo -e "${YELLOW}Step 3: Starting the Smart Proxy Gateway...${NC}"

# Start the smart proxy (it will manage routing to both models)
cd fusion-app
nohup python3 smart_proxy.py > gateway.log 2>&1 &
GATEWAY_PID=$!
echo "Started Smart Proxy with PID: $GATEWAY_PID"
cd ..

sleep 3

echo -e "${YELLOW}Step 4: Configuring ngrok (only 1 endpoint needed!)...${NC}"

# Kill existing ngrok
pkill -u group4 -f ngrok
sleep 2

# Create simple ngrok config - only expose the gateway!
cat > ngrok-unified.yml << EOF
version: "2"
authtoken: $NGROK_AUTHTOKEN
web_addr: 127.0.0.1:5008
tunnels:
  gateway:
    proto: http
    addr: 8000
    hostname: unremounted-unejective-tracey.ngrok-free.dev
    host_header: "localhost:8000"
    inspect: false
EOF

# Start ngrok
nohup ngrok start --all --config ngrok-unified.yml > ngrok.log 2>&1 &
sleep 5

echo -e "${YELLOW}Step 5: Verifying setup...${NC}"

# Check if gateway is running
if curl -s http://localhost:8000/health > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Gateway is running${NC}"
    curl -s http://localhost:8000/health | python3 -m json.tool
else
    echo -e "${RED}❌ Gateway failed to start${NC}"
fi

# Check if ngrok is running
if curl -s http://localhost:5008/api/tunnels > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Ngrok is running${NC}"
    echo
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   YOUR SINGLE PUBLIC URL${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
    echo -e "${GREEN}🚀 Unified Gateway:${NC}"
    echo -e "${YELLOW}   https://unremounted-unejective-tracey.ngrok-free.dev${NC}"
    echo
    echo -e "${GREEN}Features:${NC}"
    echo "  • Single URL for both models"
    echo "  • Toggle between API and Local models"
    echo "  • User preference saved in cookies"
    echo "  • Both models stay running"
    echo
else
    echo -e "${RED}❌ Ngrok failed to start${NC}"
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}   SERVICE ARCHITECTURE${NC}"
echo -e "${BLUE}========================================${NC}"
echo
echo "Port Mapping:"
echo "  • 8000: Smart Gateway (EXPOSED via ngrok)"
echo "  • 5000: API Model Backend (INTERNAL)"
echo "  • 5003: Local Model Backend (INTERNAL)"
echo "  • 5007: Grafana (can be exposed separately if needed)"
echo
echo "Benefits:"
echo "  ✅ Only 1 ngrok endpoint needed!"
echo "  ✅ Seamless model switching"
echo "  ✅ User preference persistence"
echo "  ✅ Both models always available"
echo

# Show running services
echo -e "${YELLOW}Running services:${NC}"
ps aux | grep -E "app_api|app_local|smart_proxy" | grep -v grep

DEPLOY_GATEWAY

echo
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}   Deployment Complete!${NC}"
echo -e "${GREEN}======================================${NC}"
echo
echo "Access your unified interface at:"
echo -e "${YELLOW}https://unremounted-unejective-tracey.ngrok-free.dev${NC}"
echo
echo "To switch models:"
echo "1. Click the toggle on the main page"
echo "2. Or use the URL paths:"
echo "   - /app → Uses your selected model"
echo "   - Toggle saves preference for 30 days"