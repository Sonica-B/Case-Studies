#!/bin/bash

# ============================================================================
# GATEWAY DIAGNOSTIC SCRIPT
# Comprehensive diagnostics for troubleshooting gateway issues
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

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}   GATEWAY DIAGNOSTICS${NC}"
echo -e "${BLUE}======================================${NC}"
echo

ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << 'DIAGNOSE'

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}1. Checking file structure...${NC}"
cd ~/Case-Studies

if [ -d fusion-app ]; then
    echo -e "${GREEN}✅ fusion-app directory exists${NC}"
    echo "Contents:"
    ls -la fusion-app/ | head -10
else
    echo -e "${RED}❌ fusion-app directory not found${NC}"
fi

if [ -f fusion-app/smart_proxy.py ]; then
    echo -e "${GREEN}✅ smart_proxy.py exists ($(wc -l < fusion-app/smart_proxy.py) lines)${NC}"
else
    echo -e "${RED}❌ smart_proxy.py not found${NC}"
fi

echo
echo -e "${YELLOW}2. Checking Docker images...${NC}"
if docker images | grep -q group4-gateway; then
    echo -e "${GREEN}✅ Gateway Docker image exists${NC}"
    docker images | grep group4-gateway
else
    echo -e "${RED}❌ Gateway Docker image not found${NC}"
fi

echo
echo -e "${YELLOW}3. Checking running containers...${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "NAMES|group4"

echo
echo -e "${YELLOW}4. Checking port availability...${NC}"
for port in 5000 5003 5006 5007 5008 5009 5010; do
    if lsof -i :$port > /dev/null 2>&1; then
        echo -e "${GREEN}Port $port: IN USE${NC}"
        lsof -i :$port | grep LISTEN | head -1
    else
        echo -e "${YELLOW}Port $port: AVAILABLE${NC}"
    fi
done

echo
echo -e "${YELLOW}5. Checking Python processes...${NC}"
if pgrep -f "python.*smart_proxy" > /dev/null; then
    echo -e "${GREEN}✅ Gateway Python process running${NC}"
    ps aux | grep -E "python.*smart_proxy" | grep -v grep
else
    echo -e "${YELLOW}No gateway Python process found${NC}"
fi

echo
echo -e "${YELLOW}6. Checking ngrok processes...${NC}"
if pgrep -u group4 -f ngrok > /dev/null; then
    echo -e "${GREEN}✅ Ngrok is running${NC}"
    ps aux | grep ngrok | grep -v grep

    # Check ngrok API
    if curl -s http://localhost:5008/api/tunnels > /dev/null 2>&1; then
        echo "Ngrok tunnels:"
        curl -s http://localhost:5008/api/tunnels | python3 -c "
import json, sys
data = json.load(sys.stdin)
for t in data.get('tunnels', []):
    print(f\"  - {t['name']}: {t.get('public_url', 'N/A')} -> {t.get('config', {}).get('addr', 'N/A')}\")
" 2>/dev/null || echo "  Could not parse ngrok tunnels"
    fi
else
    echo -e "${YELLOW}Ngrok is not running${NC}"
fi

echo
echo -e "${YELLOW}7. Testing service endpoints...${NC}"

# Test ML-API
echo -n "ML-API (port 5000): "
if curl -s -o /dev/null -w "%{http_code}" http://localhost:5000 2>/dev/null | grep -q "200\|302"; then
    echo -e "${GREEN}✅ Responding${NC}"
else
    echo -e "${RED}❌ Not responding${NC}"
fi

# Test ML-Local
echo -n "ML-Local (port 5003): "
if curl -s -o /dev/null -w "%{http_code}" http://localhost:5003 2>/dev/null | grep -q "200\|302"; then
    echo -e "${GREEN}✅ Responding${NC}"
else
    echo -e "${RED}❌ Not responding${NC}"
fi

# Test Gateway
echo -n "Gateway (port 5009): "
if curl -s -o /dev/null -w "%{http_code}" http://localhost:5009 2>/dev/null | grep -q "200\|302"; then
    echo -e "${GREEN}✅ Responding${NC}"
else
    echo -e "${RED}❌ Not responding${NC}"
fi

echo
echo -e "${YELLOW}8. Checking logs...${NC}"

# Check gateway container logs if exists
if docker ps -a | grep -q group4-gateway; then
    echo "Gateway container logs (last 5 lines):"
    docker logs group4-gateway 2>&1 | tail -5
fi

# Check Python gateway log if exists
if [ -f ~/gateway.log ]; then
    echo "Python gateway log (last 5 lines):"
    tail -5 ~/gateway.log
fi

echo
echo -e "${YELLOW}9. Environment check...${NC}"
if [ -f ~/.envrc ]; then
    echo -e "${GREEN}✅ .envrc exists${NC}"
    if [ -n "$NGROK_AUTHTOKEN" ]; then
        echo -e "${GREEN}✅ NGROK_AUTHTOKEN is set${NC}"
    else
        echo -e "${RED}❌ NGROK_AUTHTOKEN not set${NC}"
    fi
    if [ -n "$HF_TOKEN" ]; then
        echo -e "${GREEN}✅ HF_TOKEN is set${NC}"
    else
        echo -e "${YELLOW}⚠️ HF_TOKEN not set${NC}"
    fi
else
    echo -e "${RED}❌ .envrc not found${NC}"
fi

echo
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}   DIAGNOSTIC SUMMARY${NC}"
echo -e "${BLUE}======================================${NC}"

ISSUES=0

# Check critical issues
if [ ! -f fusion-app/smart_proxy.py ]; then
    echo -e "${RED}• Missing smart_proxy.py - run deployment script${NC}"
    ISSUES=$((ISSUES + 1))
fi

if ! docker ps | grep -q "group4-ml-api"; then
    echo -e "${RED}• ML-API not running - start with: docker start group4-ml-api-product${NC}"
    ISSUES=$((ISSUES + 1))
fi

if ! docker ps | grep -q "group4-ml-local"; then
    echo -e "${RED}• ML-Local not running - start with: docker start group4-ml-local-product${NC}"
    ISSUES=$((ISSUES + 1))
fi

if ! curl -s http://localhost:5009 > /dev/null 2>&1; then
    echo -e "${RED}• Gateway not accessible on port 5009${NC}"
    ISSUES=$((ISSUES + 1))
fi

if [ $ISSUES -eq 0 ]; then
    echo -e "${GREEN}✅ No critical issues found!${NC}"
else
    echo -e "${RED}Found $ISSUES critical issue(s)${NC}"
fi

DIAGNOSE

echo
echo -e "${GREEN}Diagnostics complete!${NC}"