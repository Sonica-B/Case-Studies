#!/bin/bash

# ============================================================================
# GROUP4 NGROK SETUP WITH YOUR PERMANENT DOMAIN
# ============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# SSH connection details
SSH_KEY="/home/sonica/.ssh/vm"
VM_USER="group4"
VM_HOST="melnibone.wpi.edu"
VM_PORT="2222"

# Your permanent ngrok domain
NGROK_DOMAIN="unremounted-unejective-tracey.ngrok-free.dev"

# GROUP4's unique ngrok web interface port (avoiding conflicts)
GROUP4_NGROK_PORT="5008"

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}   GROUP4 Ngrok Setup${NC}"
echo -e "${BLUE}======================================${NC}"
echo
echo -e "${GREEN}Using your permanent domain:${NC}"
echo -e "${YELLOW}  $NGROK_DOMAIN${NC}"
echo -e "${GREEN}Using port ${GROUP4_NGROK_PORT} for web interface (avoiding port 4044 conflicts)${NC}"
echo

ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << 'REMOTE_SCRIPT'

# Colors for remote
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

cd ~/Case-Studies

echo -e "${YELLOW}Stopping any existing GROUP4 ngrok...${NC}"

# Kill only GROUP4's ngrok processes (not other teams')
GROUP4_NGROK_PIDS=$(pgrep -u group4 -f ngrok)
if [ -n "$GROUP4_NGROK_PIDS" ]; then
    for pid in $GROUP4_NGROK_PIDS; do
        echo "  Killing GROUP4 ngrok PID: $pid"
        kill $pid 2>/dev/null || true
    done
else
    echo "  No existing GROUP4 ngrok processes found"
fi

sleep 3

echo -e "${YELLOW}Setting up ngrok with your permanent domain...${NC}"

# Source environment for tokens
if [ -f ~/.envrc ]; then
    source ~/.envrc
fi

# Configure ngrok if token exists
if [ -n "$NGROK_AUTHTOKEN" ]; then
    ngrok config add-authtoken $NGROK_AUTHTOKEN
fi

# Set GROUP4's port
GROUP4_NGROK_PORT=5008

# Save port configuration for other scripts
echo "export GROUP4_NGROK_PORT=$GROUP4_NGROK_PORT" > ~/.group4_ngrok_port

# Create proper ngrok config for GROUP4 with permanent domain
# NOTE: Free plan limited to 3 endpoints - using only essential services
# IMPORTANT: Only ml-api uses the permanent domain; others get random URLs
cat > ngrok-group4.yml << NGROK_CONFIG
version: "2"
authtoken: $NGROK_AUTHTOKEN
web_addr: 127.0.0.1:$GROUP4_NGROK_PORT
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
    inspect: false
  grafana:
    proto: http
    addr: 5007
    inspect: false
NGROK_CONFIG

echo -e "${YELLOW}Starting ngrok with GROUP4 configuration...${NC}"

# Start ngrok with all tunnels
nohup ngrok start --all --config ngrok-group4.yml > ngrok-group4.log 2>&1 &
NGROK_PID=$!

echo "Started ngrok with PID: $NGROK_PID"
echo "Waiting for ngrok to initialize..."
sleep 10

# Check if ngrok is running and show URLs
if curl -s http://localhost:$GROUP4_NGROK_PORT/api/tunnels > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Ngrok started successfully on port $GROUP4_NGROK_PORT!${NC}"
    echo
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   YOUR GROUP4 PUBLIC URLS${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo

    # Show main permanent domain
    echo -e "${GREEN}Main Domain (ML-API):${NC}"
    echo -e "${YELLOW}  https://unremounted-unejective-tracey.ngrok-free.dev${NC}"
    echo

    # Get all tunnel URLs
    echo -e "${GREEN}All Service URLs:${NC}"
    curl -s http://localhost:$GROUP4_NGROK_PORT/api/tunnels | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    services = {}

    # Collect unique HTTPS URLs
    for tunnel in data.get('tunnels', []):
        if tunnel.get('proto') == 'https':
            name = tunnel.get('name', '')
            url = tunnel.get('public_url', '')

            # Map to service, avoid duplicates
            if 'ml-api' in name and 'ml-api' not in services:
                services['ml-api'] = url
            elif 'ml-local' in name and 'ml-local' not in services:
                services['ml-local'] = url
            elif 'grafana' in name and 'grafana' not in services:
                services['grafana'] = url

    # Display each with its unique URL
    if services.get('ml-api'):
        print(f'  🎨 CLIP Model (API):     {services[\"ml-api\"]}')
    if services.get('ml-local'):
        print(f'  🎤 Wav2Vec2 (Local):     {services[\"ml-local\"]}')
    if services.get('grafana'):
        print(f'  📈 Grafana Dashboard:    {services[\"grafana\"]}')

    print()
    if len(services) == 3:
        print('  ✅ All 3 services have unique URLs!')
    else:
        print(f'  ⚠️  Only {len(services)} services detected')

except Exception as e:
    print(f'  Error parsing URLs: {e}')
"

    echo
    echo -e "${BLUE}========================================${NC}"

    # Test if services are responding
    echo
    echo -e "${YELLOW}Testing service connectivity...${NC}"

    for port in 5000 5003 5006 5007; do
        if timeout 2 curl -s -o /dev/null http://localhost:$port; then
            echo -e "  Port $port: ${GREEN}✓ Service responding${NC}"
        else
            echo -e "  Port $port: ${RED}✗ Service not responding${NC}"
        fi
    done

else
    echo -e "${RED}✗ Ngrok failed to start${NC}"
    echo "Check ngrok-group4.log for errors"
    tail -20 ngrok-group4.log
fi

echo
echo -e "${GREEN}Done! Your services should be accessible at:${NC}"
echo -e "${YELLOW}  https://unremounted-unejective-tracey.ngrok-free.dev${NC}"

REMOTE_SCRIPT