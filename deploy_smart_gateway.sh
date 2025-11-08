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
echo "• Single ngrok endpoint (port 5009)"
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

echo -e "${YELLOW}Step 2: Creating and building gateway...${NC}"

# Ensure we're in the right directory
cd ~/Case-Studies

# Always create/update the smart_proxy.py file to ensure it's correct
echo -e "${YELLOW}Creating/updating smart_proxy.py file...${NC}"
mkdir -p fusion-app

# Create the smart proxy script directly on the VM
cat > fusion-app/smart_proxy.py << 'PROXY_SCRIPT'
#!/usr/bin/env python3
"""
Smart Proxy with Cookie-based Model Selection
Remembers user's model preference and routes accordingly
"""

from flask import Flask, request, make_response, redirect, jsonify
import requests
from requests.adapters import HTTPAdapter
from urllib.parse import urlparse
import os

app = Flask(__name__)

# Backend services
SERVICES = {
    'api': 'http://localhost:5000',
    'local': 'http://localhost:5003'
}

# Create session with connection pooling
session = requests.Session()
adapter = HTTPAdapter(pool_connections=10, pool_maxsize=10)
session.mount('http://', adapter)

@app.route('/')
def index():
    """Main page with model selector"""
    current_model = request.cookies.get('model_preference', 'api')

    # Determine styles based on current model
    slider_left = '105px' if current_model == 'local' else '5px'
    slider_bg = '#2196F3' if current_model == 'local' else '#4CAF50'
    model_color = '#2196F3' if current_model == 'local' else '#4CAF50'
    model_name = current_model.upper()

    html = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Smart Model Gateway</title>
        <style>
            body {
                font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                margin: 0;
                padding: 20px;
                min-height: 100vh;
            }
            .container {
                max-width: 900px;
                margin: auto;
                background: white;
                border-radius: 15px;
                padding: 30px;
                box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            }
            h1 {
                color: #333;
                text-align: center;
            }
            .toggle-container {
                display: flex;
                justify-content: center;
                margin: 30px 0;
            }
            .toggle {
                position: relative;
                display: inline-block;
                width: 200px;
                height: 40px;
                background: #ddd;
                border-radius: 20px;
                cursor: pointer;
            }
            .toggle-slider {
                position: absolute;
                top: 5px;
                left: """ + slider_left + """;
                width: 90px;
                height: 30px;
                background: """ + slider_bg + """;
                border-radius: 15px;
                transition: all 0.3s;
                display: flex;
                align-items: center;
                justify-content: center;
                color: white;
                font-weight: bold;
            }
            .status {
                text-align: center;
                padding: 20px;
                background: #f0f0f0;
                border-radius: 10px;
                margin: 20px 0;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>🚀 Smart Model Gateway</h1>
            <div class="status">
                <h3>Current Model: <span style="color: """ + model_color + """">
                    """ + model_name + """</span>
                </h3>
            </div>
            <div class="toggle-container">
                <div class="toggle" onclick="toggleModel()">
                    <div class="toggle-slider" id="slider">
                        """ + model_name + """
                    </div>
                </div>
            </div>
            <center>
                <a href="/app" style="display: inline-block; margin: 20px; padding: 15px 30px; background: linear-gradient(45deg, #667eea, #764ba2); color: white; text-decoration: none; border-radius: 25px; font-size: 18px;">
                    Access Model Interface →
                </a>
            </center>
        </div>
        <script>
            function toggleModel() {
                fetch('/toggle', {method: 'POST'})
                    .then(response => response.json())
                    .then(data => {
                        location.reload();
                    });
            }
        </script>
    </body>
    </html>
    """
    return html

@app.route('/toggle', methods=['POST'])
def toggle_model():
    """Toggle between API and Local models"""
    current = request.cookies.get('model_preference', 'api')
    new_model = 'local' if current == 'api' else 'api'

    response = make_response(jsonify({'model': new_model}))
    response.set_cookie('model_preference', new_model, max_age=86400*30)  # 30 days
    return response

@app.route('/app')
@app.route('/app/<path:path>')
def proxy_app(path=''):
    """Proxy requests to the selected model"""
    model = request.cookies.get('model_preference', 'api')
    backend_url = SERVICES[model]

    try:
        target_url = f"{backend_url}/{path}"
        if request.query_string:
            target_url += f"?{request.query_string.decode()}"

        if request.method == 'GET':
            resp = session.get(target_url, headers=request.headers)
        elif request.method == 'POST':
            resp = session.post(target_url, data=request.data, headers=request.headers)
        else:
            resp = session.request(
                method=request.method,
                url=target_url,
                headers=request.headers,
                data=request.data
            )

        response = make_response(resp.content)
        response.status_code = resp.status_code

        exclude_headers = ['content-encoding', 'content-length', 'transfer-encoding', 'connection']
        for key, value in resp.headers.items():
            if key.lower() not in exclude_headers:
                response.headers[key] = value

        return response

    except Exception as e:
        return jsonify({'error': str(e), 'model': model}), 500

@app.route('/health')
def health():
    """Health check endpoint"""
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
PROXY_SCRIPT

echo -e "${GREEN}✅ smart_proxy.py created successfully${NC}"

# Create Dockerfile in main directory
cat > Dockerfile.gateway << 'EOF'
# Dockerfile for Smart Gateway
FROM python:3.9-slim

WORKDIR /app

# Install dependencies
RUN pip install flask requests

# Copy only the smart proxy
COPY fusion-app/smart_proxy.py .

# Expose port 5009 (within GROUP4's allocated range)
EXPOSE 5009

# Run the smart proxy
CMD ["python", "smart_proxy.py"]
EOF

# Verify the file exists before building
if [ -f fusion-app/smart_proxy.py ]; then
    echo -e "${GREEN}✅ fusion-app/smart_proxy.py exists, size: $(wc -c < fusion-app/smart_proxy.py) bytes${NC}"
else
    echo -e "${RED}❌ fusion-app/smart_proxy.py not found!${NC}"
    ls -la fusion-app/
    exit 1
fi

# Build the image from Case-Studies directory
echo -e "${YELLOW}Building Docker image...${NC}"
if docker build -f Dockerfile.gateway -t group4-gateway:latest .; then
    echo -e "${GREEN}✅ Docker image built successfully${NC}"
else
    echo -e "${RED}❌ Docker build failed${NC}"
    echo "Checking current directory:"
    pwd
    echo "Checking fusion-app contents:"
    ls -la fusion-app/
    exit 1
fi

echo -e "${YELLOW}Step 3: Starting backend ML services...${NC}"
# Ensure both ML services are running
docker start group4-ml-api 2>/dev/null || echo "ML-API already running"
docker start group4-ml-local 2>/dev/null || echo "ML-Local already running"

echo -e "${YELLOW}Step 4: Starting smart gateway...${NC}"

# Remove any existing container
docker stop group4-gateway 2>/dev/null
docker rm group4-gateway 2>/dev/null

# Start the gateway container
if docker run -d \
  --name group4-gateway \
  --network host \
  -e PYTHONUNBUFFERED=1 \
  group4-gateway:latest; then
    echo -e "${GREEN}✅ Gateway container started${NC}"
else
    echo -e "${RED}❌ Failed to start gateway container${NC}"
    docker logs group4-gateway 2>&1 | tail -20
    exit 1
fi

# Wait for gateway to start
echo "Waiting for gateway to initialize..."
sleep 5

# Check if container is still running
if docker ps | grep -q group4-gateway; then
    echo -e "${GREEN}✅ Gateway container is running${NC}"
else
    echo -e "${RED}❌ Gateway container stopped unexpectedly${NC}"
    echo "Container logs:"
    docker logs group4-gateway 2>&1 | tail -20
    exit 1
fi

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
    addr: 5009
    hostname: unremounted-unejective-tracey.ngrok-free.dev
    host_header: "localhost:5009"
    inspect: false
EOF

echo -e "${YELLOW}Step 6: Starting ngrok...${NC}"
nohup ngrok start --all --config ngrok-gateway.yml > ngrok-gateway.log 2>&1 &
sleep 5

echo -e "${YELLOW}Step 7: Verifying deployment...${NC}"

# Check gateway health
if curl -s http://localhost:5009/health > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Gateway is running${NC}"

    # Show health status
    echo -e "${BLUE}Gateway health status:${NC}"
    curl -s http://localhost:5009/health | python3 -m json.tool
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
web_addr: 127.0.0.1:5010
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