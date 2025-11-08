#!/bin/bash

# ============================================================================
# OPTIMIZED NGROK SETUP - ONLY 2 SERVICES!
# Smart solution: Only expose what needs external access
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
echo -e "${GREEN}   OPTIMIZED 2-SERVICE SETUP${NC}"
echo -e "${GREEN}======================================${NC}"
echo
echo -e "${YELLOW}Smart Architecture:${NC}"
echo "1. ML Services: External access needed (for users)"
echo "2. Grafana: External access needed (for monitoring)"
echo "3. Prometheus: NO external access needed (Grafana accesses internally)"
echo

ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << 'OPTIMIZED_SETUP'

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

echo -e "${YELLOW}Step 1: Stopping existing ngrok...${NC}"
pkill -u group4 -f ngrok
sleep 2

echo -e "${YELLOW}Step 2: Creating OPTIMIZED ngrok config (only 2 endpoints!)...${NC}"

# Only expose what NEEDS external access
cat > ngrok-optimized.yml << EOF
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

echo -e "${GREEN}✅ Created optimized config with only 2 endpoints${NC}"

echo -e "${YELLOW}Step 3: Starting ngrok...${NC}"
nohup ngrok start --all --config ngrok-optimized.yml > ngrok-optimized.log 2>&1 &
sleep 5

echo -e "${YELLOW}Step 4: Verifying setup...${NC}"

if curl -s http://localhost:5008/api/tunnels > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Ngrok running successfully${NC}"
    echo
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   YOUR PUBLIC URLS (Only 2 needed!)${NC}"
    echo -e "${BLUE}========================================${NC}"

    curl -s http://localhost:5008/api/tunnels | python3 -c "
import json, sys
data = json.load(sys.stdin)
urls = {}
for t in data.get('tunnels', []):
    if t.get('proto') == 'https':
        name = t['name']
        url = t['public_url']
        if 'ml-api' in name:
            urls['ml-api'] = url
        elif 'grafana' in name:
            urls['grafana'] = url

print()
print('🎨 ML API (CLIP Model):')
print(f'   {urls.get(\"ml-api\", \"Not found\")}')
print()
print('📊 Monitoring Dashboard (Grafana):')
print(f'   {urls.get(\"grafana\", \"Not found\")}')
print('   (Grafana internally connects to Prometheus - no external access needed!)')
print()
"
else
    echo -e "${RED}Ngrok failed to start${NC}"
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}   OPTIMIZED SETUP COMPLETE!${NC}"
echo -e "${BLUE}========================================${NC}"
echo
echo -e "${YELLOW}What about the other services?${NC}"
echo "• ML-Local (Wav2Vec2): Access via port forwarding if needed"
echo "• Prometheus: Grafana accesses it internally on port 5006"
echo "• No complex multi-token setup required!"
echo
echo -e "${GREEN}Benefits:${NC}"
echo "✅ Only 2 endpoints (fits in FREE tier with room to spare!)"
echo "✅ No teammate token needed"
echo "✅ Simple and maintainable"
echo "✅ All monitoring still works (Grafana → Prometheus internally)"
echo

# Show docker services status
echo -e "${YELLOW}Internal services (accessible within VM):${NC}"
docker ps --format "table {{.Names}}\t{{.Ports}}" | grep -E "NAMES|group4"

OPTIMIZED_SETUP

echo
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}   Done! Much simpler, right?${NC}"
echo -e "${GREEN}======================================${NC}"