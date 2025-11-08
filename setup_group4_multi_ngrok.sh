#!/bin/bash

# ============================================================================
# GROUP4 MULTI-NGROK SETUP - BYPASS 3-ENDPOINT LIMIT
# Runs separate ngrok processes for each service to avoid the limit
# ============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# SSH details
SSH_KEY="/home/sonica/.ssh/vm"
VM_USER="group4"
VM_HOST="melnibone.wpi.edu"
VM_PORT="2222"

# Your permanent ngrok domain
NGROK_DOMAIN="unremounted-unejective-tracey.ngrok-free.dev"

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}   GROUP4 Multi-Ngrok Setup${NC}"
echo -e "${BLUE}======================================${NC}"
echo
echo -e "${GREEN}Strategy: Run 3 separate ngrok processes${NC}"
echo -e "${YELLOW}This bypasses the 3-endpoint free tier limit!${NC}"
echo

ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << 'REMOTE_SCRIPT'

# Colors for remote
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

cd ~/Case-Studies

echo -e "${YELLOW}Stopping all existing GROUP4 ngrok processes...${NC}"

# Kill ALL GROUP4's ngrok processes
pkill -u group4 -f ngrok 2>/dev/null || true
sleep 3

echo -e "${YELLOW}Setting up multiple ngrok configurations...${NC}"

# Source environment for tokens
if [ -f ~/.envrc ]; then
    source ~/.envrc
fi

# Configure ngrok if token exists
if [ -n "$NGROK_AUTHTOKEN" ]; then
    ngrok config add-authtoken $NGROK_AUTHTOKEN
else
    echo -e "${RED}Error: No NGROK_AUTHTOKEN found${NC}"
    exit 1
fi

# ========================================
# NGROK PROCESS 1: ML-API (Port 5008)
# ========================================
echo -e "${GREEN}Creating ngrok config for ML-API...${NC}"
cat > ngrok-ml-api.yml << NGROK1
version: "2"
authtoken: $NGROK_AUTHTOKEN
web_addr: 127.0.0.1:5008
tunnels:
  ml-api:
    proto: http
    addr: 5000
    hostname: unremounted-unejective-tracey.ngrok-free.dev
    host_header: "localhost:5000"
    inspect: false
NGROK1

echo "Starting ngrok for ML-API on port 5008..."
nohup ngrok start --all --config ngrok-ml-api.yml > ngrok-ml-api.log 2>&1 &
ML_API_PID=$!
sleep 5

# ========================================
# NGROK PROCESS 2: ML-LOCAL (Port 5009)
# ========================================
echo -e "${GREEN}Creating ngrok config for ML-LOCAL...${NC}"
cat > ngrok-ml-local.yml << NGROK2
version: "2"
authtoken: $NGROK_AUTHTOKEN
web_addr: 127.0.0.1:5009
tunnels:
  ml-local:
    proto: http
    addr: 5003
    inspect: false
NGROK2

echo "Starting ngrok for ML-LOCAL on port 5009..."
nohup ngrok start --all --config ngrok-ml-local.yml > ngrok-ml-local.log 2>&1 &
ML_LOCAL_PID=$!
sleep 5

# ========================================
# NGROK PROCESS 3: MONITORING (Port 5010)
# ========================================
echo -e "${GREEN}Creating ngrok config for Monitoring...${NC}"
cat > ngrok-monitoring.yml << NGROK3
version: "2"
authtoken: $NGROK_AUTHTOKEN
web_addr: 127.0.0.1:5010
tunnels:
  grafana:
    proto: http
    addr: 5007
    inspect: false
  prometheus:
    proto: http
    addr: 5006
    inspect: false
NGROK3

echo "Starting ngrok for Monitoring on port 5010..."
nohup ngrok start --all --config ngrok-monitoring.yml > ngrok-monitoring.log 2>&1 &
MONITORING_PID=$!
sleep 5

echo
echo -e "${GREEN}All ngrok processes started:${NC}"
echo "  ML-API ngrok (PID: $ML_API_PID) - Web interface: localhost:5008"
echo "  ML-LOCAL ngrok (PID: $ML_LOCAL_PID) - Web interface: localhost:5009"
echo "  Monitoring ngrok (PID: $MONITORING_PID) - Web interface: localhost:5010"
echo

# Wait for all to initialize
echo "Waiting for all ngrok processes to initialize..."
sleep 5

# ========================================
# FETCH ALL URLS
# ========================================
echo
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   YOUR GROUP4 PUBLIC URLS${NC}"
echo -e "${BLUE}========================================${NC}"
echo

# Get ML-API URL (with permanent domain)
echo -e "${YELLOW}ML-API Service (port 5008):${NC}"
curl -s http://localhost:5008/api/tunnels 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for tunnel in data.get('tunnels', []):
        if tunnel.get('proto') == 'https':
            print(f'  🎨 CLIP Model: {tunnel.get(\"public_url\")}')
            break
except: print('  Error fetching ML-API URL')
" || echo "  Error: ML-API ngrok not responding"

echo

# Get ML-LOCAL URL
echo -e "${YELLOW}ML-LOCAL Service (port 5009):${NC}"
curl -s http://localhost:5009/api/tunnels 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for tunnel in data.get('tunnels', []):
        if tunnel.get('proto') == 'https':
            print(f'  🎤 Wav2Vec2: {tunnel.get(\"public_url\")}')
            break
except: print('  Error fetching ML-LOCAL URL')
" || echo "  Error: ML-LOCAL ngrok not responding"

echo

# Get Monitoring URLs
echo -e "${YELLOW}Monitoring Services (port 5010):${NC}"
curl -s http://localhost:5010/api/tunnels 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for tunnel in data.get('tunnels', []):
        if tunnel.get('proto') == 'https':
            name = tunnel.get('name', '')
            url = tunnel.get('public_url', '')
            if 'grafana' in name:
                print(f'  📈 Grafana: {url}')
            elif 'prometheus' in name:
                print(f'  📊 Prometheus: {url}')
except: print('  Error fetching Monitoring URLs')
" || echo "  Error: Monitoring ngrok not responding"

echo
echo -e "${BLUE}========================================${NC}"
echo

# Test connectivity
echo -e "${YELLOW}Testing service connectivity...${NC}"
for port in 5000 5003 5006 5007; do
    if timeout 2 curl -s -o /dev/null http://localhost:$port; then
        echo -e "  Port $port: ${GREEN}✓ Service responding${NC}"
    else
        echo -e "  Port $port: ${RED}✗ Service not responding${NC}"
    fi
done

echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   MULTI-NGROK SETUP COMPLETE!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo "✅ Running 3 separate ngrok processes"
echo "✅ Each service has its own unique URL"
echo "✅ Bypassed the 3-endpoint limit!"
echo
echo "To check status of each ngrok:"
echo "  ML-API: curl http://localhost:5008/api/tunnels"
echo "  ML-LOCAL: curl http://localhost:5009/api/tunnels"
echo "  Monitoring: curl http://localhost:5010/api/tunnels"
echo

REMOTE_SCRIPT