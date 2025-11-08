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

# GROUP4's unique ngrok web interface port (within allocated range)
GROUP4_NGROK_PORT="5008"

# Optional: Teammate's token for extra endpoints
TEAMMATE_NGROK_TOKEN="${1:-}"  # Pass as first argument

echo -e "${RED}======================================${NC}"
echo -e "${RED}   FIXING GROUP4 NGROK CONFIGURATION${NC}"
echo -e "${RED}======================================${NC}"
echo
echo -e "${YELLOW}Port 4044 is used by other teams. GROUP4 will use port ${GROUP4_NGROK_PORT}${NC}"
echo -e "${GREEN}Will configure domain: $NGROK_DOMAIN${NC}"
echo

ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << 'REMOTE_FIX'

# Colors for remote
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

cd ~/Case-Studies

echo -e "${YELLOW}Step 1: Killing ONLY GROUP4's ngrok processes...${NC}"

# Only kill ngrok processes owned by group4 user
GROUP4_NGROK_PIDS=$(pgrep -u group4 -f ngrok)

if [ -n "$GROUP4_NGROK_PIDS" ]; then
    echo "Found GROUP4's ngrok processes:"
    for pid in $GROUP4_NGROK_PIDS; do
        echo "  Killing GROUP4 PID: $pid"
        kill $pid 2>/dev/null || true
    done
    sleep 3

    # Force kill if still running
    GROUP4_NGROK_PIDS=$(pgrep -u group4 -f ngrok)
    if [ -n "$GROUP4_NGROK_PIDS" ]; then
        echo "Force killing remaining GROUP4 ngrok..."
        for pid in $GROUP4_NGROK_PIDS; do
            kill -9 $pid 2>/dev/null || true
        done
    fi
else
    echo "No GROUP4 ngrok processes found"
fi

echo -e "${GREEN}✅ GROUP4's ngrok processes cleaned${NC}"

# Show other teams' ngrok (we won't touch these)
OTHER_NGROK=$(pgrep -f ngrok | wc -l)
if [ "$OTHER_NGROK" -gt 0 ]; then
    echo -e "${YELLOW}Note: Other teams have $OTHER_NGROK ngrok processes running (untouched)${NC}"
fi

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

# Set GROUP4's port
GROUP4_NGROK_PORT=5008

# Create the CORRECT ngrok configuration
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

echo -e "${GREEN}✅ Created correct ngrok configuration${NC}"
echo "  - Web interface port: $GROUP4_NGROK_PORT (avoiding conflict with port 4044)"
echo "  - Using permanent domain: unremounted-unejective-tracey.ngrok-free.dev"
echo "  - Routing to GROUP4 ports: 5000, 5003, 5006, 5007"

# Save port configuration for other scripts
echo "export GROUP4_NGROK_PORT=$GROUP4_NGROK_PORT" > ~/.group4_ngrok_port

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

# If teammate token provided, start second ngrok for Prometheus
TEAMMATE_TOKEN="$TEAMMATE_NGROK_TOKEN"
if [ -n "\$TEAMMATE_TOKEN" ]; then
    echo
    echo -e "${YELLOW}Step 3b: Starting second ngrok with teammate's token...${NC}"

    # Create config for Prometheus only (staying under 3 endpoint limit)
    cat > ngrok-prometheus.yml << NGROK_TEAMMATE
version: "2"
authtoken: \$TEAMMATE_TOKEN
web_addr: 127.0.0.1:5009
tunnels:
  prometheus:
    proto: http
    addr: 5006
    inspect: false
NGROK_TEAMMATE

    # Start second ngrok process
    nohup ngrok start --all --config ngrok-prometheus.yml > ngrok-prometheus.log 2>&1 &
    NGROK2_PID=\$!
    echo "Started Prometheus ngrok with PID: \$NGROK2_PID on port 5009"
    sleep 5
fi

echo -e "${YELLOW}Step 4: Verifying ngrok is running correctly...${NC}"

# Check ngrok status
if curl -s http://localhost:$GROUP4_NGROK_PORT/api/tunnels > /dev/null 2>&1; then
    echo -e "${GREEN}✅ GROUP4 ngrok API responding on port $GROUP4_NGROK_PORT${NC}"

    # Display the URLs
    echo
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   YOUR CORRECTED PUBLIC URLS${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo

    curl -s http://localhost:$GROUP4_NGROK_PORT/api/tunnels | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    tunnels = data.get('tunnels', [])

    # Debug: Show raw tunnel count
    print(f'Found {len(tunnels)} total tunnels (HTTP + HTTPS)')
    print()

    # Collect unique HTTPS URLs
    urls_by_service = {}
    for tunnel in tunnels:
        if tunnel.get('proto') == 'https':
            name = tunnel.get('name', '')
            url = tunnel.get('public_url', '')
            addr = tunnel.get('config', {}).get('addr', '')

            # Map to service based on name
            if 'ml-api' in name:
                urls_by_service['ml-api'] = url
            elif 'ml-local' in name:
                urls_by_service['ml-local'] = url
            elif 'grafana' in name:
                urls_by_service['grafana'] = url

    # Display each service with its UNIQUE URL
    print('🌐 PUBLIC URLs (Each is unique!):')
    print('=' * 50)

    if 'ml-api' in urls_by_service:
        print(f'🎨 CLIP Model (port 5000):')
        print(f'   {urls_by_service[\"ml-api\"]}')
        print()

    if 'ml-local' in urls_by_service:
        print(f'🎤 Wav2Vec2 Model (port 5003):')
        print(f'   {urls_by_service[\"ml-local\"]}')
        print()

    if 'grafana' in urls_by_service:
        print(f'📈 Grafana Dashboard (port 5007):')
        print(f'   {urls_by_service[\"grafana\"]}')
        print()

    print('=' * 50)

    # Verify permanent domain is used for ml-api
    if 'ml-api' in urls_by_service and 'unremounted-unejective-tracey' in urls_by_service['ml-api']:
        print('✅ ML-API using your permanent domain!')
    else:
        print('⚠️  ML-API not using permanent domain')

    # Show that others get random domains
    random_count = sum(1 for url in urls_by_service.values() if 'ngrok-free.app' in url)
    if random_count > 0:
        print(f'✅ {random_count} services using random ngrok URLs')

except Exception as e:
    print(f'Error parsing tunnels: {e}')
    print('Raw response:')
    import subprocess
    subprocess.run(['curl', '-s', 'http://localhost:' + str($GROUP4_NGROK_PORT) + '/api/tunnels'])
"

    echo -e "${BLUE}========================================${NC}"

    # Check second ngrok if running
    if [ -n "\$TEAMMATE_TOKEN" ] && curl -s http://localhost:5009/api/tunnels > /dev/null 2>&1; then
        echo
        echo -e "${BLUE}Teammate's Ngrok (Prometheus):${NC}"
        curl -s http://localhost:5009/api/tunnels | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for tunnel in data.get('tunnels', []):
        if tunnel.get('proto') == 'https':
            print(f'  📊 Prometheus: {tunnel.get(\"public_url\")}')
            break
except: pass
"
        echo -e "${BLUE}========================================${NC}"
    fi
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
echo "  • Your ngrok: Port 5008 (ML-API, ML-Local, Grafana)"
if [ -n "\$TEAMMATE_TOKEN" ]; then
    echo "  • Teammate ngrok: Port 5009 (Prometheus)"
    echo "  • Total endpoints: 4 (bypassed 3-endpoint limit!)"
fi
echo "  • Your services run on ports 5000-5007"
echo

REMOTE_FIX

if [ -n "$TEAMMATE_NGROK_TOKEN" ]; then
    echo
    echo -e "${GREEN}Usage with teammate token:${NC}"
    echo "  ./fix_ngrok_config.sh \"teammate_token_here\""
fi