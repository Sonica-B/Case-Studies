#!/bin/bash

# ============================================================================
# FIX NGROK CONFIGURATION FOR GROUP4
# This script kills the misconfigured ngrok and restarts with correct config
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

# Your permanent ngrok domain
NGROK_DOMAIN="unremounted-unejective-tracey.ngrok-free.dev"

echo -e "${RED}======================================${NC}"
echo -e "${RED}   FIXING GROUP4 NGROK CONFIGURATION${NC}"
echo -e "${RED}======================================${NC}"
echo
echo -e "${YELLOW}Current issue: Ngrok using wrong domain and port${NC}"
echo -e "${GREEN}Will fix to use: $NGROK_DOMAIN${NC}"
echo

ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << 'REMOTE_FIX'

# Colors for remote
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

cd ~/Case-Studies

echo -e "${YELLOW}Step 1: Killing ALL ngrok processes...${NC}"

# Kill all ngrok processes to start fresh
pkill -f ngrok || true
sleep 3

# Verify all ngrok processes are dead
if pgrep -f ngrok > /dev/null; then
    echo -e "${RED}Some ngrok processes still running, force killing...${NC}"
    pkill -9 -f ngrok || true
    sleep 2
fi

echo -e "${GREEN}✅ All ngrok processes killed${NC}"

echo -e "${YELLOW}Step 2: Creating correct ngrok configuration...${NC}"

# Source environment for tokens
if [ -f ~/.envrc ]; then
    source ~/.envrc
    echo "Loaded environment variables"
fi

# Configure ngrok with token
if [ -n "$NGROK_AUTHTOKEN" ]; then
    ngrok config add-authtoken $NGROK_AUTHTOKEN
else
    echo -e "${RED}Warning: No NGROK_AUTHTOKEN found${NC}"
fi

# Create the CORRECT ngrok configuration
cat > ngrok-group4.yml << 'NGROK_CONFIG'
version: "2"
web_addr: 127.0.0.1:4044
tunnels:
  ml-api:
    proto: http
    addr: 5000
    hostname: unremounted-unejective-tracey.ngrok-free.dev
    host_header: "localhost:5000"
  ml-local:
    proto: http
    addr: 5003
  prometheus:
    proto: http
    addr: 5006
  grafana:
    proto: http
    addr: 5007
NGROK_CONFIG

echo -e "${GREEN}✅ Created correct ngrok configuration${NC}"
echo "  - Using permanent domain: unremounted-unejective-tracey.ngrok-free.dev"
echo "  - Routing to GROUP4 ports: 5000, 5003, 5006, 5007"

echo -e "${YELLOW}Step 3: Starting ngrok with correct configuration...${NC}"

# Start ngrok with the correct config
nohup ngrok start --all --config ngrok-group4.yml > ngrok-group4.log 2>&1 &
NGROK_PID=$!

echo "Started ngrok with PID: $NGROK_PID"
echo "Waiting for ngrok to initialize (10 seconds)..."
sleep 10

# Check if ngrok is running correctly
if ! ps -p $NGROK_PID > /dev/null; then
    echo -e "${RED}Ngrok failed to start. Check the log:${NC}"
    tail -20 ngrok-group4.log
    exit 1
fi

echo -e "${YELLOW}Step 4: Verifying ngrok is running correctly...${NC}"

# Check ngrok status
if curl -s http://localhost:4044/api/tunnels > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Ngrok API responding on port 4044${NC}"

    # Display the URLs
    echo
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   YOUR CORRECTED PUBLIC URLS${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo

    curl -s http://localhost:4044/api/tunnels | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    tunnels = data.get('tunnels', [])

    # Group by service
    services = {}
    for tunnel in tunnels:
        if tunnel.get('proto') == 'https':
            name = tunnel.get('name', 'unknown')
            url = tunnel.get('public_url', '')
            addr = tunnel.get('config', {}).get('addr', '')

            if 'ml-api' in name:
                services['ml-api'] = (url, addr)
            elif 'ml-local' in name:
                services['ml-local'] = (url, addr)
            elif 'prometheus' in name:
                services['prometheus'] = (url, addr)
            elif 'grafana' in name:
                services['grafana'] = (url, addr)

    # Display with correct names
    if 'ml-api' in services:
        print(f'🎨 CLIP Model (port 5000):')
        print(f'   {services[\"ml-api\"][0]}')
        print()
    if 'ml-local' in services:
        print(f'🎤 Wav2Vec2 Model (port 5003):')
        print(f'   {services[\"ml-local\"][0]}')
        print()
    if 'prometheus' in services:
        print(f'📊 Prometheus (port 5006):')
        print(f'   {services[\"prometheus\"][0]}')
        print()
    if 'grafana' in services:
        print(f'📈 Grafana (port 5007):')
        print(f'   {services[\"grafana\"][0]}')
        print()

    # Check if main domain is correct
    for tunnel in tunnels:
        if 'unremounted-unejective-tracey' in tunnel.get('public_url', ''):
            print('✅ Using your permanent domain correctly!')
            break
    else:
        print('⚠️  Permanent domain not found in URLs')

except Exception as e:
    print(f'Error parsing tunnels: {e}')
"

    echo -e "${BLUE}========================================${NC}"
else
    echo -e "${RED}✗ Ngrok API not responding${NC}"
    echo "Check ngrok-group4.log for errors"
fi

# Final verification
echo
echo -e "${YELLOW}Step 5: Final verification...${NC}"

# Check what port ngrok is routing to
curl -s http://localhost:4044/api/tunnels | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for tunnel in data.get('tunnels', []):
        addr = tunnel.get('config', {}).get('addr', '')
        if '32150' in addr:
            print('❌ ERROR: Still routing to port 32150!')
            sys.exit(1)
        if '5000' in addr or '5003' in addr:
            print('✅ Correctly routing to GROUP4 ports')
            break
except: pass
"

echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   NGROK CONFIGURATION FIXED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo "Your services are now accessible at:"
echo -e "${YELLOW}https://unremounted-unejective-tracey.ngrok-free.dev${NC}"
echo
echo "Notes:"
echo "  • Port 4044 is the ngrok web interface (this is correct)"
echo "  • Your services run on ports 5000-5007"
echo "  • Ngrok routes external traffic to these ports"
echo

REMOTE_FIX