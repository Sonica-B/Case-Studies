#!/bin/bash

# ============================================================================
# QUICK FIX SCRIPT FOR GATEWAY ISSUES
# This script addresses all diagnostic issues
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
echo -e "${GREEN}   QUICK FIX FOR GATEWAY${NC}"
echo -e "${GREEN}======================================${NC}"
echo

ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << 'QUICK_FIX'

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

cd ~/Case-Studies

echo -e "${YELLOW}Step 1: Loading environment variables...${NC}"
# Source the environment file
if [ -f ~/.envrc ]; then
    source ~/.envrc
    echo -e "${GREEN}✅ Environment loaded${NC}"

    # Check if tokens are set
    if [ -n "$NGROK_AUTHTOKEN" ]; then
        echo -e "${GREEN}✅ NGROK_AUTHTOKEN is set${NC}"
    else
        echo -e "${RED}❌ NGROK_AUTHTOKEN not set!${NC}"
        echo "Please run: source ~/.envrc"
        echo "Or set: export NGROK_AUTHTOKEN=your_token_here"
    fi
else
    echo -e "${RED}❌ .envrc not found${NC}"
fi

echo -e "${YELLOW}Step 2: Since Docker build is complex, using Python directly...${NC}"

# Kill any existing Python gateway
pkill -f "python.*smart_proxy.py" 2>/dev/null
sleep 2

# Create the smart_proxy.py file
mkdir -p fusion-app

cat > fusion-app/smart_proxy.py << 'PYTHON_CODE'
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
    model_color = '#2196F3' if current_model == 'local' else '#4CAF50'

    return """
    <html>
    <head>
        <title>Smart Model Gateway</title>
        <style>
            body {
                font-family: Arial;
                background: linear-gradient(135deg, #667eea, #764ba2);
                color: white;
                display: flex;
                justify-content: center;
                align-items: center;
                min-height: 100vh;
                margin: 0;
            }
            .container {
                text-align: center;
                background: white;
                color: #333;
                padding: 50px;
                border-radius: 15px;
                box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            }
            button {
                padding: 15px 40px;
                font-size: 18px;
                margin: 10px;
                border: none;
                border-radius: 5px;
                cursor: pointer;
                background: #667eea;
                color: white;
            }
            button:hover { background: #764ba2; }
            a {
                display: inline-block;
                padding: 15px 40px;
                background: #4CAF50;
                color: white;
                text-decoration: none;
                border-radius: 5px;
                margin: 10px;
            }
            a:hover { background: #45a049; }
            .model-status {
                font-size: 24px;
                margin: 20px 0;
                color: """ + model_color + """;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>🚀 Smart Model Gateway</h1>
            <div class="model-status">
                Current Model: <strong>""" + current_model.upper() + """</strong>
            </div>
            <form action="/toggle" method="post" style="display: inline;">
                <button type="submit">
                    Switch to """ + ('LOCAL' if current_model == 'api' else 'API') + """
                </button>
            </form>
            <br><br>
            <a href="/app">Access Model Interface →</a>
        </div>
    </body>
    </html>
    """

@app.route('/toggle', methods=['POST'])
def toggle_model():
    current = request.cookies.get('model_preference', 'api')
    new_model = 'local' if current == 'api' else 'api'

    response = make_response("""
    <html>
    <head>
        <meta http-equiv="refresh" content="1;url=/">
        <style>
            body {
                font-family: Arial;
                background: #667eea;
                color: white;
                display: flex;
                justify-content: center;
                align-items: center;
                min-height: 100vh;
            }
        </style>
    </head>
    <body>
        <h2>Switching to """ + new_model.upper() + """...</h2>
    </body>
    </html>
    """)

    response.set_cookie('model_preference', new_model, max_age=86400*30)
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

        resp = session.get(target_url, headers=request.headers, timeout=30)
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
PYTHON_CODE

echo -e "${GREEN}✅ smart_proxy.py created${NC}"

echo -e "${YELLOW}Step 3: Installing dependencies...${NC}"
pip install flask requests --user --quiet
echo -e "${GREEN}✅ Dependencies installed${NC}"

echo -e "${YELLOW}Step 4: Starting gateway...${NC}"

# Start the gateway in background
cd fusion-app
nohup python3 smart_proxy.py > ~/gateway.log 2>&1 &
GATEWAY_PID=$!
echo "Gateway started with PID: $GATEWAY_PID"
cd ..

# Wait for it to start
sleep 3

echo -e "${YELLOW}Step 5: Verifying gateway...${NC}"

if curl -s http://localhost:5009/health > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Gateway is running on port 5009${NC}"

    # Show health status
    echo "Gateway health:"
    curl -s http://localhost:5009/health | python3 -m json.tool
else
    echo -e "${RED}❌ Gateway failed to start${NC}"
    echo "Check logs with: tail ~/gateway.log"
fi

echo
echo -e "${YELLOW}Step 6: Checking ngrok status...${NC}"

# Ngrok is already running, just verify
if curl -s http://localhost:5008/api/tunnels 2>/dev/null | grep -q "5009"; then
    echo -e "${GREEN}✅ Ngrok is already configured for port 5009${NC}"

    echo
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   ACCESS URLS${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
    echo -e "${GREEN}Local Gateway: http://localhost:5009${NC}"
    echo -e "${GREEN}Public URL: https://unremounted-unejective-tracey.ngrok-free.dev${NC}"
    echo
    echo "Gateway PID: $GATEWAY_PID"
else
    echo -e "${YELLOW}Ngrok may need reconfiguration${NC}"
fi

echo
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}   QUICK FIX COMPLETE!${NC}"
echo -e "${GREEN}======================================${NC}"

QUICK_FIX

echo
echo -e "${GREEN}Fix applied! Test with:${NC}"
echo "  ./test_gateway.sh"