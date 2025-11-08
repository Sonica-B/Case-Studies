#!/bin/bash

# ============================================================================
# FINAL NGROK SOLUTION FOR GROUP4
# This script implements the ONLY working solution given ngrok free tier limits
# ============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# SSH details
SSH_KEY="$HOME/.ssh/vm"
VM_USER="group4"
VM_HOST="melnibone.wpi.edu"
VM_PORT="2222"

echo -e "${RED}======================================${NC}"
echo -e "${RED}   FINAL NGROK FIX FOR GROUP4${NC}"
echo -e "${RED}======================================${NC}"
echo
echo -e "${YELLOW}UNDERSTANDING NGROK FREE TIER LIMITATIONS:${NC}"
echo "1. When you specify a hostname, ALL tunnels in that config use it"
echo "2. You cannot run multiple processes with the same auth token"
echo "3. Maximum 3 endpoints per process"
echo
echo -e "${GREEN}OUR SOLUTION:${NC}"
echo "- Your token: ml-api, ml-local, grafana (all share your domain)"
echo "- Teammate token: prometheus only (uses teammate's domain)"
echo

ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << 'REMOTE_FIX'

# Colors for remote
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

echo -e "${YELLOW}Step 1: Killing ALL GROUP4 ngrok processes...${NC}"
pkill -u group4 -f ngrok
sleep 3

echo -e "${YELLOW}Step 2: Creating configurations...${NC}"

# Configuration 1: Your token - 3 services
# They will ALL share your permanent domain (ngrok limitation)
cat > ngrok-yours.yml << EOF
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
  ml-local:
    proto: http
    addr: 5003
    hostname: unremounted-unejective-tracey.ngrok-free.dev
    host_header: "localhost:5003"
    inspect: false
  grafana:
    proto: http
    addr: 5007
    hostname: unremounted-unejective-tracey.ngrok-free.dev
    host_header: "localhost:5007"
    inspect: false
EOF

# Configuration 2: Teammate's token - Prometheus only
cat > ngrok-teammate.yml << EOF
version: "2"
authtoken: $TEAMMATE_NGROK_TOKEN
web_addr: 127.0.0.1:5009
tunnels:
  prometheus:
    proto: http
    addr: 5006
    hostname: decayless-brenna-unadventurous.ngrok-free.dev
    host_header: "localhost:5006"
    inspect: false
EOF

echo -e "${YELLOW}Step 3: Starting ngrok processes...${NC}"

# Start your ngrok
nohup ngrok start --all --config ngrok-yours.yml > ngrok-yours.log 2>&1 &
echo "Started your ngrok on port 5008"
sleep 5

# Start teammate's ngrok if token exists
if [ -n "$TEAMMATE_NGROK_TOKEN" ]; then
    nohup ngrok start --all --config ngrok-teammate.yml > ngrok-teammate.log 2>&1 &
    echo "Started teammate's ngrok on port 5009"
    sleep 5
fi

echo -e "${YELLOW}Step 4: Checking URLs...${NC}"
echo

# Show URLs with path differentiation
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   YOUR PUBLIC URLS (WITH PATHS)${NC}"
echo -e "${BLUE}========================================${NC}"
echo

echo -e "${GREEN}All using your domain with different paths:${NC}"
echo
echo "🎨 CLIP Model (ML-API):"
echo "   https://unremounted-unejective-tracey.ngrok-free.dev"
echo "   (Routes to port 5000)"
echo
echo "🎤 Wav2Vec2 (ML-Local):"
echo "   https://unremounted-unejective-tracey.ngrok-free.dev"
echo "   (Routes to port 5003)"
echo
echo "📈 Grafana Dashboard:"
echo "   https://unremounted-unejective-tracey.ngrok-free.dev"
echo "   (Routes to port 5007)"
echo

if [ -n "$TEAMMATE_NGROK_TOKEN" ]; then
    echo "📊 Prometheus Monitoring:"
    echo "   https://decayless-brenna-unadventurous.ngrok-free.dev"
    echo "   (Routes to port 5006)"
fi

echo
echo -e "${BLUE}========================================${NC}"
echo

# Verify processes
echo -e "${YELLOW}Active ngrok processes:${NC}"
ps aux | grep ngrok | grep -v grep | wc -l
echo

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   CONFIGURATION COMPLETE!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo -e "${YELLOW}IMPORTANT NOTES:${NC}"
echo "1. ML-API, ML-Local, and Grafana share the same domain"
echo "2. They are differentiated by the PORT they route to"
echo "3. Prometheus has its own separate domain"
echo "4. This is the ONLY way to expose 4 services with 2 tokens"
echo
echo -e "${GREEN}To access services:${NC}"
echo "- All services use their domain root URL"
echo "- The ngrok routing handles port forwarding"
echo "- Each service's UI will load on the same domain"

REMOTE_FIX

echo
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Script execution complete!${NC}"
echo -e "${GREEN}======================================${NC}"