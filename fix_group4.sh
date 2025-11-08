#!/bin/bash
# Fix GROUP4 deployment without affecting other teams

VM_HOST="melnibone.wpi.edu"
VM_PORT="2222"
VM_USER="${1:-group4}"
SSH_KEY="$HOME/.ssh/vm"

# Check environment
if [ -z "$NGROK_AUTHTOKEN" ]; then
    echo "❌ NGROK_AUTHTOKEN not set"
    read -p "Enter your Ngrok token: " NGROK_AUTHTOKEN
fi

echo "🔧 FIXING GROUP4 DEPLOYMENT"
echo "==========================="
echo "This will:"
echo "1. Setup GROUP4's ngrok (port 4044)"
echo "2. Not affect other teams"
echo

# Fix ngrok for GROUP4 only
ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << EOF
cd ~/Case-Studies

echo "Setting up GROUP4 ngrok (web port 4044)..."
echo "==========================================="

# Check if GROUP4 ngrok already running
# IMPORTANT: Only kill processes that specifically match GROUP4
if pgrep -f "ngrok.*group4|ngrok.*4044" > /dev/null; then
    echo "Found existing GROUP4 ngrok process..."
    # Only kill GROUP4's ngrok (not other teams')
    for pid in $(pgrep -f "ngrok.*group4|ngrok.*4044"); do
        echo "  Stopping GROUP4 ngrok PID: $pid"
        kill $pid 2>/dev/null || true
    done
    sleep 2
else
    echo "No existing GROUP4 ngrok found"
fi

# Configure ngrok with GROUP4 token
ngrok config add-authtoken $NGROK_AUTHTOKEN

# Create GROUP4-specific config with unique web port
cat > ngrok-group4.yml << 'NGROK_EOF'
version: "2"
authtoken: $NGROK_AUTHTOKEN
web_addr: 127.0.0.1:4044
tunnels:
  group4-api:
    proto: http
    addr: 5000
    inspect: false
  group4-local:
    proto: http
    addr: 5003
    inspect: false
  group4-grafana:
    proto: http
    addr: 5007
    inspect: false
NGROK_EOF

# Replace token in config
sed -i "s/\\\$NGROK_AUTHTOKEN/$NGROK_AUTHTOKEN/" ngrok-group4.yml

# Start GROUP4's ngrok
echo "Starting GROUP4 ngrok on port 4044..."
nohup ngrok start --all --config ngrok-group4.yml > ngrok-group4.log 2>&1 &
NGROK_PID=\$!
echo "Started with PID: \$NGROK_PID"

# Wait for it to start
sleep 10

# Get GROUP4's URLs (from port 4044)
echo ""
echo "🌐 GROUP4 NGROK URLS (Port 4044):"
echo "=================================="
curl -s http://localhost:4044/api/tunnels 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    tunnels = data.get('tunnels', [])
    if tunnels:
        for t in tunnels:
            name = t.get('name', 'unknown')
            url = t.get('public_url', '')
            if 'https' in url:
                if 'api' in name:
                    print(f'API Product: {url}')
                elif 'local' in name:
                    print(f'Local Product: {url}')
                elif 'grafana' in name:
                    print(f'Grafana: {url}')
    else:
        print('No GROUP4 tunnels found yet')
        print('Check: curl http://localhost:4044/api/tunnels')
except Exception as e:
    print(f'GROUP4 ngrok not ready yet. Check port 4044')
    print('Debug: curl http://localhost:4044/api/tunnels')
"

echo ""
echo "Checking other teams' ngrok (should still be running):"
echo "======================================================="
# Check default ngrok port (other teams)
curl -s http://localhost:4040/api/tunnels 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    if data.get('tunnels'):
        print('✅ Other teams ngrok still running on port 4040')
    else:
        print('No other ngrok on port 4040')
except:
    print('No other ngrok on port 4040')
" || echo "No other teams' ngrok detected"

echo ""
echo "GROUP4 Status:"
echo "=============="
echo "Containers:"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "NAMES|group4"

echo ""
echo "Test endpoints:"
for port in 5000 5003 5006 5007; do
    response=\$(curl -s -o /dev/null -w "%{http_code}" -m 2 http://localhost:\$port 2>/dev/null)
    if [ "\$response" == "200" ] || [ "\$response" == "302" ] || [ "\$response" == "303" ]; then
        echo "✅ Port \$port: HTTP \$response"
    else
        echo "❌ Port \$port: Not responding"
    fi
done

EOF

echo ""
echo "✅ GROUP4 Fix Complete!"
echo "======================="
echo ""
echo "Your GROUP4 services:"
echo "- Use ngrok web port 4044 (not 4040)"
echo "- URLs shown above are GROUP4's"
echo "- Other teams' services unaffected"
echo ""
echo "To check GROUP4 URLs again:"
echo "  ssh to VM"
echo "  curl http://localhost:4044/api/tunnels"