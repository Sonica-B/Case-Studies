#!/bin/bash

# ============================================================================
# CHECK STATUS OF MULTIPLE NGROK PROCESSES
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

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}   GROUP4 Multi-Ngrok Status Check${NC}"
echo -e "${BLUE}======================================${NC}"
echo

ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << 'REMOTE_CHECK'

# Colors for remote
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}Checking ngrok processes...${NC}"
echo

# Check running ngrok processes
NGROK_PROCESSES=$(pgrep -u group4 -f ngrok -a 2>/dev/null)

if [ -z "$NGROK_PROCESSES" ]; then
    echo -e "${RED}No ngrok processes running${NC}"
    exit 1
fi

echo "Running ngrok processes:"
echo "$NGROK_PROCESSES" | while read line; do
    echo "  $line"
done
echo

# Function to check ngrok API
check_ngrok() {
    local port=$1
    local name=$2

    echo -e "${YELLOW}$name (localhost:$port):${NC}"

    if curl -s http://localhost:$port/api/tunnels > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓ API responding${NC}"

        # Get tunnels
        curl -s http://localhost:$port/api/tunnels | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    tunnels = data.get('tunnels', [])
    if not tunnels:
        print('  No tunnels active')
    for tunnel in tunnels:
        if tunnel.get('proto') == 'https':
            name = tunnel.get('name', 'unknown')
            url = tunnel.get('public_url', 'N/A')
            addr = tunnel.get('config', {}).get('addr', 'N/A')
            print(f'  → {name}: {url}')
            print(f'     (routing to localhost:{addr})')
except Exception as e:
    print(f'  Error parsing response: {e}')
"
    else
        echo -e "  ${RED}✗ Not responding${NC}"
    fi
    echo
}

echo -e "${BLUE}Checking all ngrok web interfaces:${NC}"
echo

# Check each ngrok process
check_ngrok 5008 "ML-API Ngrok"
check_ngrok 5009 "ML-LOCAL Ngrok"
check_ngrok 5010 "Monitoring Ngrok"

# Check if services are accessible
echo -e "${BLUE}Service Connectivity:${NC}"
for port in 5000 5003 5006 5007; do
    if timeout 2 curl -s -o /dev/null http://localhost:$port; then
        case $port in
            5000) echo -e "  Port 5000 (CLIP API): ${GREEN}✓${NC}" ;;
            5003) echo -e "  Port 5003 (Wav2Vec2): ${GREEN}✓${NC}" ;;
            5006) echo -e "  Port 5006 (Prometheus): ${GREEN}✓${NC}" ;;
            5007) echo -e "  Port 5007 (Grafana): ${GREEN}✓${NC}" ;;
        esac
    else
        echo -e "  Port $port: ${RED}✗${NC}"
    fi
done

echo
echo -e "${BLUE}Summary:${NC}"
NGROK_COUNT=$(pgrep -u group4 -f ngrok | wc -l)
echo "  Total ngrok processes running: $NGROK_COUNT"
echo "  Expected: 3 (one per service group)"

if [ "$NGROK_COUNT" -eq 3 ]; then
    echo -e "  Status: ${GREEN}✓ All ngrok processes running${NC}"
else
    echo -e "  Status: ${YELLOW}⚠ Expected 3 processes, found $NGROK_COUNT${NC}"
fi

REMOTE_CHECK