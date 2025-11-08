#!/bin/bash

# ============================================================================
# SMART GATEWAY DEPLOYMENT WITH OPTIMIZED NGROK
# Single endpoint access with model toggle functionality
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
echo -e "${GREEN}   SMART GATEWAY DEPLOYMENT${NC}"
echo -e "${GREEN}======================================${NC}"
echo
echo -e "${YELLOW}Architecture:${NC}"
echo "• Single ngrok endpoint (port 8000)"
echo "• Smart proxy with model toggle"
echo "• Both ML models running in background"
echo "• Cookie-based session persistence"
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

echo -e "${YELLOW}Step 1: Stopping existing services...${NC}"
# Stop existing ngrok
pkill -u group4 -f ngrok
# Stop any existing gateway
docker stop group4-gateway 2>/dev/null
docker rm group4-gateway 2>/dev/null
sleep 2

echo -e "${YELLOW}Step 2: Building gateway Docker image...${NC}"

# Ensure we're in the right directory
cd ~/Case-Studies

# Create Dockerfile in main directory
cat > Dockerfile.gateway << 'EOF'
# Dockerfile for Smart Gateway
FROM python:3.9-slim

WORKDIR /app

# Install dependencies
RUN pip install flask requests gradio

# Copy gateway code from fusion-app directory
COPY fusion-app/smart_proxy.py .
COPY fusion-app/unified_gateway.py .

# Expose port
EXPOSE 8000

# Default to smart proxy (can override to use unified_gateway.py)
CMD ["python", "smart_proxy.py"]
EOF

# Build the image from Case-Studies directory
docker build -f Dockerfile.gateway -t group4-gateway:latest .

echo -e "${YELLOW}Step 3: Starting backend ML services...${NC}"
# Ensure both ML services are running
docker start group4-ml-api 2>/dev/null || echo "ML-API already running"
docker start group4-ml-local 2>/dev/null || echo "ML-Local already running"

echo -e "${YELLOW}Step 4: Starting smart gateway...${NC}"
docker run -d \
  --name group4-gateway \
  --network host \
  -e PYTHONUNBUFFERED=1 \
  group4-gateway:latest

# Wait for gateway to start
sleep 5

echo -e "${YELLOW}Step 5: Configuring optimized ngrok (single endpoint)...${NC}"
cd ~/Case-Studies

# Create ngrok config with ONLY gateway endpoint
cat > ngrok-gateway.yml << EOF
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

echo -e "${YELLOW}Step 6: Starting ngrok...${NC}"
nohup ngrok start --all --config ngrok-gateway.yml > ngrok-gateway.log 2>&1 &
sleep 5

echo -e "${YELLOW}Step 7: Verifying deployment...${NC}"

# Check gateway health
if curl -s http://localhost:8000/health > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Gateway is running${NC}"

    # Show health status
    echo -e "${BLUE}Gateway health status:${NC}"
    curl -s http://localhost:8000/health | python3 -m json.tool
else
    echo -e "${RED}❌ Gateway failed to start${NC}"
fi

echo
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   YOUR SINGLE PUBLIC URL${NC}"
echo -e "${BLUE}========================================${NC}"
echo
echo -e "${GREEN}🎯 Smart Gateway (with Model Toggle):${NC}"
echo "   https://unremounted-unejective-tracey.ngrok-free.dev"
echo
echo -e "${YELLOW}Features:${NC}"
echo "• Access both CLIP (API) and Wav2Vec2 (Local) models"
echo "• Toggle between models via web interface"
echo "• Cookie-based preference persistence"
echo "• Single endpoint for all ML functionality"
echo
echo -e "${YELLOW}How to use:${NC}"
echo "1. Visit the URL above"
echo "2. Toggle between API/Local models"
echo "3. Access model at /app endpoint"
echo "4. Your preference is saved for 30 days"
echo
echo -e "${BLUE}========================================${NC}"

# Optional: Add monitoring if needed
if [ "$1" == "--with-monitoring" ]; then
    echo -e "${YELLOW}Adding monitoring endpoint...${NC}"

    # Use teammate's token for Grafana if available
    if [ -n "$TEAMMATE_NGROK_TOKEN" ]; then
        cat > ngrok-monitoring.yml << EOF
version: "2"
authtoken: $TEAMMATE_NGROK_TOKEN
web_addr: 127.0.0.1:5009
tunnels:
  grafana:
    proto: http
    addr: 5007
    hostname: decayless-brenna-unadventurous.ngrok-free.dev
    host_header: "localhost:5007"
    inspect: false
EOF
        nohup ngrok start --all --config ngrok-monitoring.yml > ngrok-monitoring.log 2>&1 &
        sleep 3
        echo -e "${GREEN}📊 Monitoring Dashboard (Grafana):${NC}"
        echo "   https://decayless-brenna-unadventurous.ngrok-free.dev"
    fi
fi

echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   DEPLOYMENT COMPLETE!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo -e "${YELLOW}Services Status:${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "NAMES|group4"

DEPLOY_GATEWAY

echo
echo -e "${GREEN}Smart gateway deployed successfully!${NC}"
echo -e "${YELLOW}Only 1 ngrok endpoint needed for both ML models${NC}"