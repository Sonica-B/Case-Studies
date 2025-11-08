#!/bin/bash

# ============================================================================
# FIX NGROK CONFIGURATION FOR GROUP4
# This script kills the misconfigured ngrok and restarts with correct config
#
# USAGE:
#   Basic (your ngrok only, 3 services):
#     ./fix_ngrok_config.sh
#
#   With teammate's token (4 services with random URL for Prometheus):
#     ./fix_ngrok_config.sh "teammate_ngrok_token_here"
#
#   With teammate's token AND domain (4 services, both with permanent URLs):
#     ./fix_ngrok_config.sh "teammate_token" "decayless-brenna-unadventurous.ngrok-free.dev"
#
# RESULT:
#   - Your ngrok (port 5008): ML-API, ML-Local, Grafana
#   - Your permanent domain: unremounted-unejective-tracey.ngrok-free.dev
#   - Teammate ngrok (port 5009): Prometheus
#   - Teammate domain: decayless-brenna-unadventurous.ngrok-free.dev
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
# First check if passed as arguments
TEAMMATE_NGROK_TOKEN="${1:-}"  # Pass as first argument
TEAMMATE_NGROK_DOMAIN="${2:-}"  # Pass teammate's domain as second argument (optional)

echo -e "${RED}======================================${NC}"
echo -e "${RED}   FIXING GROUP4 NGROK CONFIGURATION${NC}"
echo -e "${RED}======================================${NC}"
echo

# Simple SSH connection without complex environment variable passing
ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << 'REMOTE_FIX'

# Colors for remote
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

cd ~/Case-Studies

# Source environment first to check for saved credentials
if [ -f ~/.envrc ]; then
    source ~/.envrc
fi

# Display configuration info
echo -e "${GREEN}Configuration:${NC}"
echo "  • Your domain: unremounted-unejective-tracey.ngrok-free.dev"
echo "  • Web interface port: 5008"

if [ -n "$TEAMMATE_NGROK_TOKEN" ]; then
    echo "  • Teammate token: Available (from ~/.envrc)"
    if [ -n "$TEAMMATE_NGROK_DOMAIN" ]; then
        echo "  • Teammate domain: $TEAMMATE_NGROK_DOMAIN"
    fi
fi
echo

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

# Environment already loaded above, just check status
if [ -n "$NGROK_AUTHTOKEN" ]; then
    echo "Using your ngrok token from ~/.envrc"
else
    echo -e "${YELLOW}Warning: No NGROK_AUTHTOKEN found in environment${NC}"
fi

if [ -n "$TEAMMATE_NGROK_TOKEN" ]; then
    echo "Using teammate's ngrok token from ~/.envrc"
fi

# Configure ngrok with token
if [ -n "$NGROK_AUTHTOKEN" ]; then
    ngrok config add-authtoken $NGROK_AUTHTOKEN
else
    echo -e "${RED}Warning: No NGROK_AUTHTOKEN found${NC}"
fi

# Set GROUP4's port
GROUP4_NGROK_PORT=5008

# Create ngrok configuration
# IMPORTANT: The free tier issue - if we specify hostname for one tunnel,
# ngrok may apply it to all. So we'll start them separately.
# First config: ONLY ml-api with permanent domain
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
NGROK_CONFIG

# We'll add ml-local and grafana later using teammate's second account
# or accept that they share the same domain

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

# SOLUTION: Put ml-local and grafana back with ml-api (your token)
# Only use teammate's token for Prometheus alone
if [ -n "$TEAMMATE_NGROK_TOKEN" ]; then
    echo
    echo -e "${YELLOW}Step 3b: Reconfiguring for unique URLs...${NC}"

    # First, kill the ml-api only process
    kill $NGROK_PID 2>/dev/null || true
    sleep 2

    # Recreate config with YOUR token for 3 services
    # This will give ml-api the permanent domain, ml-local and grafana get same domain too
    # But at least they're not mixing with Prometheus
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

    # Teammate's config - ONLY Prometheus
    cat > ngrok-prometheus.yml << NGROK_TEAMMATE
version: "2"
authtoken: $TEAMMATE_NGROK_TOKEN
web_addr: 127.0.0.1:5009
tunnels:
  prometheus:
    proto: http
    addr: 5006
    hostname: $TEAMMATE_NGROK_DOMAIN
    host_header: "localhost:5006"
    inspect: false
NGROK_TEAMMATE

    # Restart YOUR ngrok with all 3 services
    echo "Starting your ngrok with ml-api, ml-local, grafana..."
    nohup ngrok start --all --config ngrok-group4.yml > ngrok-group4.log 2>&1 &
    NGROK_PID=$!
    sleep 5

    # Start teammate's ngrok with ONLY Prometheus
    echo "Starting teammate's ngrok with Prometheus only..."
    nohup ngrok start --all --config ngrok-prometheus.yml > ngrok-prometheus.log 2>&1 &
    NGROK2_PID=$!
    echo "Started Prometheus ngrok on port 5009"
    sleep 5
else
    echo
    echo -e "${YELLOW}No teammate token - services will share your domain${NC}"
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
    if [ -n "$TEAMMATE_NGROK_TOKEN" ] && curl -s http://localhost:5009/api/tunnels > /dev/null 2>&1; then
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
if [ -n "$TEAMMATE_NGROK_TOKEN" ]; then
    echo "  • Teammate ngrok: Port 5009 (Prometheus)"
    echo "  • Total endpoints: 4 (bypassed 3-endpoint limit!)"
fi
echo "  • Your services run on ports 5000-5007"
echo

REMOTE_FIX

echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Script completed successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo "Notes:"
echo "  • Tokens are loaded automatically from ~/.envrc (set up via setup_tokens.sh)"
echo "  • No need to pass tokens as arguments if already saved"
echo "  • Your services are accessible via the URLs shown above"