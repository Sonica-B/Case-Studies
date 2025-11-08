#!/bin/bash

# ============================================================================
# SIMPLE GATEWAY DEPLOYMENT (NON-DOCKER)
# Fallback deployment without Docker containerization
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
echo -e "${GREEN}   SIMPLE GATEWAY DEPLOYMENT${NC}"
echo -e "${GREEN}======================================${NC}"
echo
echo -e "${YELLOW}Deploying gateway without Docker...${NC}"
echo

ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << 'SIMPLE_DEPLOY'

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

echo -e "${YELLOW}Step 1: Stopping existing gateway...${NC}"
# Kill any existing Python gateway process
pkill -f "python.*smart_proxy.py" 2>/dev/null
pkill -u group4 -f ngrok 2>/dev/null
sleep 2

echo -e "${YELLOW}Step 2: Creating smart_proxy.py...${NC}"
mkdir -p fusion-app

cat > fusion-app/smart_proxy.py << 'PYTHON_GATEWAY'
#!/usr/bin/env python3
from flask import Flask, request, make_response, jsonify
import requests
from requests.adapters import HTTPAdapter

app = Flask(__name__)

SERVICES = {
    'api': 'http://localhost:5000',
    'local': 'http://localhost:5003'
}

session = requests.Session()
adapter = HTTPAdapter(pool_connections=10, pool_maxsize=10)
session.mount('http://', adapter)

@app.route('/')
def index():
    current_model = request.cookies.get('model_preference', 'api')
    return f"""
    <html>
    <body style="font-family: Arial; padding: 50px; text-align: center;">
        <h1>Smart Model Gateway</h1>
        <h2>Current Model: {current_model.upper()}</h2>
        <br>
        <form action="/toggle" method="post" style="display: inline;">
            <button type="submit" style="padding: 10px 30px; font-size: 18px;">
                Toggle to {'LOCAL' if current_model == 'api' else 'API'}
            </button>
        </form>
        <br><br>
        <a href="/app" style="padding: 10px 30px; background: blue; color: white; text-decoration: none; display: inline-block;">
            Access Model Interface
        </a>
    </body>
    </html>
    """

@app.route('/toggle', methods=['POST'])
def toggle_model():
    current = request.cookies.get('model_preference', 'api')
    new_model = 'local' if current == 'api' else 'api'
    response = make_response(f'<html><body>Switched to {new_model.upper()}<br><a href="/">Go back</a></body></html>')
    response.set_cookie('model_preference', new_model, max_age=86400*30)
    response.headers['Refresh'] = '1;url=/'
    return response

@app.route('/app')
@app.route('/app/<path:path>')
def proxy_app(path=''):
    model = request.cookies.get('model_preference', 'api')
    backend_url = SERVICES[model]

    try:
        target_url = f"{backend_url}/{path}"
        if request.query_string:
            target_url += f"?{request.query_string.decode()}"

        resp = session.get(target_url, headers=request.headers)
        response = make_response(resp.content)
        response.status_code = resp.status_code

        for key, value in resp.headers.items():
            if key.lower() not in ['content-encoding', 'content-length', 'transfer-encoding', 'connection']:
                response.headers[key] = value

        return response
    except Exception as e:
        return jsonify({'error': str(e), 'model': model}), 500

@app.route('/health')
def health():
    status = {}
    for name, url in SERVICES.items():
        try:
            r = session.get(f"{url}/health", timeout=2)
            status[name] = 'healthy' if r.status_code == 200 else 'unhealthy'
        except:
            status[name] = 'offline'

    current_model = request.cookies.get('model_preference', 'api')
    return jsonify({
        'gateway': 'healthy',
        'current_model': current_model,
        'services': status
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5009, debug=False)
PYTHON_GATEWAY

echo -e "${GREEN}✅ smart_proxy.py created${NC}"

echo -e "${YELLOW}Step 3: Installing Python dependencies...${NC}"
pip install flask requests --user --quiet

echo -e "${YELLOW}Step 4: Starting gateway in background...${NC}"
cd fusion-app
nohup python3 smart_proxy.py > ~/gateway.log 2>&1 &
GATEWAY_PID=$!
echo "Gateway started with PID: $GATEWAY_PID"
cd ..

sleep 3

echo -e "${YELLOW}Step 5: Checking gateway status...${NC}"
if curl -s http://localhost:5009/health > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Gateway is running on port 5009${NC}"
    curl -s http://localhost:5009/health | python3 -m json.tool
else
    echo -e "${RED}❌ Gateway failed to start${NC}"
    echo "Last 10 lines of gateway log:"
    tail -10 ~/gateway.log
    exit 1
fi

echo -e "${YELLOW}Step 6: Configuring ngrok...${NC}"
cat > ngrok-simple.yml << EOF
version: "2"
authtoken: $NGROK_AUTHTOKEN
web_addr: 127.0.0.1:5008
tunnels:
  gateway:
    proto: http
    addr: 5009
    hostname: unremounted-unejective-tracey.ngrok-free.dev
    host_header: "localhost:5009"
    inspect: false
EOF

pkill -u group4 -f ngrok 2>/dev/null
sleep 2

nohup ngrok start --all --config ngrok-simple.yml > ngrok-simple.log 2>&1 &
sleep 5

echo
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   DEPLOYMENT COMPLETE${NC}"
echo -e "${BLUE}========================================${NC}"
echo
echo -e "${GREEN}Gateway URL (local): http://localhost:5009${NC}"
echo -e "${GREEN}Public URL: https://unremounted-unejective-tracey.ngrok-free.dev${NC}"
echo
echo "Gateway PID: $GATEWAY_PID"
echo "To stop: kill $GATEWAY_PID"
echo

SIMPLE_DEPLOY

echo
echo -e "${GREEN}Simple gateway deployed successfully!${NC}"