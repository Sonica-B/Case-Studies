#!/bin/bash

# ============================================================================
# SMART 3-SERVICE SETUP (If you need both ML models exposed)
# Uses your token for 2 services, teammate's for 1
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
echo -e "${GREEN}   SMART 3-SERVICE SETUP${NC}"
echo -e "${GREEN}======================================${NC}"
echo
echo -e "${YELLOW}Architecture Decision:${NC}"
echo "• Prometheus doesn't need external access (Grafana queries it internally)"
echo "• We only expose: ML-API, ML-Local, and Grafana"
echo "• This fits perfectly in ngrok free tier!"
echo

ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << 'SMART_SETUP'

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

echo -e "${YELLOW}Step 1: Cleaning up...${NC}"
pkill -u group4 -f ngrok
sleep 2

echo -e "${YELLOW}Step 2: Smart configuration...${NC}"

# Option A: All 3 on your account (they'll share domain but who cares?)
if [ -z "$TEAMMATE_NGROK_TOKEN" ]; then
    echo "Using single account setup (services will share domain)..."

    cat > ngrok-smart.yml << EOF
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

    nohup ngrok start --all --config ngrok-smart.yml > ngrok.log 2>&1 &

    echo -e "${GREEN}✅ Started all 3 services on your account${NC}"

else
    # Option B: Split across 2 accounts for unique domains
    echo "Using dual account setup for unique domains..."

    # Your account: ML-API and Grafana
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
  grafana:
    proto: http
    addr: 5007
    inspect: false
EOF

    # Teammate account: ML-Local only
    cat > ngrok-teammate.yml << EOF
version: "2"
authtoken: $TEAMMATE_NGROK_TOKEN
web_addr: 127.0.0.1:5009
tunnels:
  ml-local:
    proto: http
    addr: 5003
    hostname: ${TEAMMATE_NGROK_DOMAIN:-decayless-brenna-unadventurous.ngrok-free.dev}
    host_header: "localhost:5003"
    inspect: false
EOF

    nohup ngrok start --all --config ngrok-yours.yml > ngrok-yours.log 2>&1 &
    nohup ngrok start --all --config ngrok-teammate.yml > ngrok-teammate.log 2>&1 &

    echo -e "${GREEN}✅ Started services across 2 accounts${NC}"
fi

sleep 5

echo
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   SERVICE ARCHITECTURE${NC}"
echo -e "${BLUE}========================================${NC}"
echo
echo "EXTERNALLY ACCESSIBLE (via ngrok):"
echo "  • ML-API (CLIP) - Port 5000"
echo "  • ML-Local (Wav2Vec2) - Port 5003"
echo "  • Grafana Dashboard - Port 5007"
echo
echo "INTERNAL ONLY (no ngrok needed):"
echo "  • Prometheus - Port 5006"
echo "    (Grafana connects to it internally)"
echo
echo -e "${GREEN}This is the optimal setup!${NC}"
echo "No need to expose Prometheus - it's a backend service!"

SMART_SETUP

echo
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}   Smart setup complete!${NC}"
echo -e "${GREEN}======================================${NC}"