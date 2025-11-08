#!/bin/bash

# ============================================================================
# GATEWAY TESTING AND VERIFICATION SCRIPT
# Tests the smart gateway toggle functionality
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
echo -e "${BLUE}   GATEWAY FUNCTIONALITY TEST${NC}"
echo -e "${BLUE}======================================${NC}"
echo

ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << 'TEST_GATEWAY'

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}Test 1: Checking backend services...${NC}"
# Check if ML services are running
echo "Checking Docker containers..."
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "NAMES|group4" || echo "No GROUP4 containers found"

if docker ps | grep -q group4-ml-api; then
    echo -e "${GREEN}✅ ML-API service is running${NC}"
else
    echo -e "${RED}❌ ML-API service is not running${NC}"
    echo "  Try: docker start group4-ml-api-product"
fi

if docker ps | grep -q group4-ml-local; then
    echo -e "${GREEN}✅ ML-Local service is running${NC}"
else
    echo -e "${RED}❌ ML-Local service is not running${NC}"
    echo "  Try: docker start group4-ml-local-product"
fi

# Check if gateway is running (Docker or Python)
if docker ps | grep -q group4-gateway; then
    echo -e "${GREEN}✅ Gateway container is running${NC}"
elif pgrep -f "python.*smart_proxy.py" > /dev/null; then
    echo -e "${GREEN}✅ Gateway is running (non-Docker)${NC}"
else
    echo -e "${YELLOW}⚠️ Gateway is not running${NC}"
fi

echo
echo -e "${YELLOW}Test 2: Checking gateway health...${NC}"
GATEWAY_HEALTH=$(curl -s http://localhost:5009/health 2>/dev/null)

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Gateway is responding${NC}"
    echo "$GATEWAY_HEALTH" | python3 -m json.tool 2>/dev/null || echo "$GATEWAY_HEALTH"
else
    echo -e "${RED}❌ Gateway is not responding${NC}"
fi

echo
echo -e "${YELLOW}Test 3: Testing model toggle...${NC}"

# Get current model preference
CURRENT_MODEL=$(curl -s http://localhost:5009/health 2>/dev/null | python3 -c "import json, sys; print(json.load(sys.stdin).get('current_model', 'unknown'))" 2>/dev/null)
echo -e "Current model: ${BLUE}$CURRENT_MODEL${NC}"

# Toggle the model
echo "Toggling model..."
TOGGLE_RESPONSE=$(curl -s -X POST http://localhost:5009/toggle 2>/dev/null)
NEW_MODEL=$(echo "$TOGGLE_RESPONSE" | python3 -c "import json, sys; print(json.load(sys.stdin).get('model', 'unknown'))" 2>/dev/null)

if [ "$NEW_MODEL" != "$CURRENT_MODEL" ] && [ "$NEW_MODEL" != "unknown" ]; then
    echo -e "${GREEN}✅ Model toggled successfully to: $NEW_MODEL${NC}"
else
    echo -e "${RED}❌ Model toggle failed${NC}"
fi

# Toggle back
sleep 1
curl -s -X POST http://localhost:5009/toggle > /dev/null 2>&1
echo "Toggled back to original model"

echo
echo -e "${YELLOW}Test 4: Testing proxy functionality...${NC}"

# Test if the proxy forwards requests correctly
TEST_URL="http://localhost:5009/app"
RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}" $TEST_URL 2>/dev/null)

if [ "$RESPONSE_CODE" = "200" ] || [ "$RESPONSE_CODE" = "302" ]; then
    echo -e "${GREEN}✅ Proxy forwarding works (HTTP $RESPONSE_CODE)${NC}"
else
    echo -e "${RED}❌ Proxy forwarding failed (HTTP $RESPONSE_CODE)${NC}"
fi

echo
echo -e "${YELLOW}Test 5: Checking ngrok tunnel...${NC}"

if curl -s http://localhost:5008/api/tunnels > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Ngrok is running${NC}"

    # Get the public URL
    PUBLIC_URL=$(curl -s http://localhost:5008/api/tunnels | python3 -c "
import json, sys
data = json.load(sys.stdin)
for t in data.get('tunnels', []):
    if t.get('proto') == 'https':
        print(t['public_url'])
        break
" 2>/dev/null)

    if [ -n "$PUBLIC_URL" ]; then
        echo -e "${GREEN}Public URL: $PUBLIC_URL${NC}"
    else
        echo -e "${YELLOW}No public URL found${NC}"
    fi
else
    echo -e "${YELLOW}Ngrok is not running (optional for local testing)${NC}"
fi

echo
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}   TEST SUMMARY${NC}"
echo -e "${BLUE}======================================${NC}"

# Count services
SERVICES_UP=$(docker ps --format "{{.Names}}" | grep -c "group4-" | tr -d ' ')
echo -e "Services running: ${GREEN}$SERVICES_UP${NC}"

# Gateway cookie test
echo
echo -e "${YELLOW}Test 6: Cookie persistence test...${NC}"

# Make request with cookie
COOKIE_TEST=$(curl -s -c /tmp/cookies.txt -b /tmp/cookies.txt http://localhost:5009/ 2>/dev/null | grep -o "model_preference" | head -1)

if [ -n "$COOKIE_TEST" ]; then
    echo -e "${GREEN}✅ Cookie-based preference works${NC}"
else
    echo -e "${YELLOW}⚠️ Could not verify cookie persistence${NC}"
fi

rm -f /tmp/cookies.txt

echo
echo -e "${GREEN}All tests completed!${NC}"

TEST_GATEWAY

echo
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}   Gateway testing complete${NC}"
echo -e "${GREEN}======================================${NC}"