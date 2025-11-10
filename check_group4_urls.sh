#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# SSH connection details
# Use Windows path if on Windows, otherwise Linux path
if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "win32" ]]; then
    SSH_KEY="$USERPROFILE/.ssh/vm"
else
    SSH_KEY="$HOME/.ssh/vm"
fi
VM_USER="group4"
VM_HOST="melnibone.wpi.edu"
VM_PORT="2222"

# GROUP4's ngrok web interface port (avoiding conflicts with other teams)
GROUP4_NGROK_PORT="5008"

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}   GROUP4 Public URLs Checker${NC}"
echo -e "${BLUE}======================================${NC}"
echo

# Function to check URLs on the VM
ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << 'EOF'
# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}Checking GROUP4 ngrok status...${NC}"
echo

# Try to load saved port configuration
if [ -f ~/.group4_ngrok_port ]; then
    source ~/.group4_ngrok_port
else
    GROUP4_NGROK_PORT=5008
fi

# Check if ngrok is running on GROUP4's port
if curl -s http://localhost:$GROUP4_NGROK_PORT/api/tunnels > /dev/null 2>&1; then
    echo -e "${GREEN}✅ GROUP4 ngrok is running on port $GROUP4_NGROK_PORT${NC}"
    echo
    echo -e "${BLUE}Your GROUP4 Public URLs:${NC}"
    echo -e "${BLUE}========================${NC}"

    # Get and parse the tunnels
    curl -s http://localhost:$GROUP4_NGROK_PORT/api/tunnels | python3 -c "
import json
import sys

try:
    data = json.load(sys.stdin)
    tunnels = data.get('tunnels', [])

    if not tunnels:
        print('  No active tunnels found!')
    else:
        # Group tunnels by name
        tunnel_map = {}
        for tunnel in tunnels:
            name = tunnel.get('name', 'unknown')
            public_url = tunnel.get('public_url', '')
            config_addr = tunnel.get('config', {}).get('addr', '')
            proto = tunnel.get('proto', '')

            if name not in tunnel_map:
                tunnel_map[name] = []
            tunnel_map[name].append({
                'url': public_url,
                'local': config_addr,
                'proto': proto
            })

        # Display tunnels organized by service
        services = {
            'ml-api': 'CLIP API (Gradio UI)',
            'ml-api-metrics': 'CLIP API Metrics',
            'ml-api-exporter': 'CLIP Node Exporter',
            'ml-local': 'Wav2Vec2 (Gradio UI)',
            'ml-local-metrics': 'Wav2Vec2 Metrics',
            'ml-local-exporter': 'Wav2Vec2 Node Exporter',
            'prometheus': 'Prometheus Dashboard',
            'grafana': 'Grafana Dashboard'
        }

        for tunnel_name, configs in sorted(tunnel_map.items()):
            service_desc = services.get(tunnel_name, tunnel_name)
            print(f'\n  📡 {service_desc}:')
            for config in configs:
                if config['proto'] == 'https':
                    print(f'     🌐 Public URL: {config[\"url\"]}'.replace('https://', '\033[1;32mhttps://\033[0m'))
                    print(f'     🏠 Local port: {config[\"local\"]}'.replace('localhost:', '\033[1;33mlocalhost:\033[0m'))

        print('\n  ℹ️  Use the https:// URLs to access your services from anywhere!')
        print('  ℹ️  These are your PUBLIC URLs that anyone can access.')
except Exception as e:
    print(f'  Error parsing tunnels: {e}')
"

    echo
    echo -e "${BLUE}================================${NC}"
    echo -e "${GREEN}Quick Links (copy and paste):${NC}"
    echo

    # Extract just the HTTPS URLs for easy copying
    curl -s http://localhost:$GROUP4_NGROK_PORT/api/tunnels | python3 -c "
import json
import sys

try:
    data = json.load(sys.stdin)
    tunnels = data.get('tunnels', [])

    services = {
        'ml-api': '🎨 CLIP Model (Gradio)',
        'ml-local': '🎤 Wav2Vec2 Model (Gradio)',
        'prometheus': '📊 Prometheus',
        'grafana': '📈 Grafana'
    }

    seen_urls = set()
    for service_key, service_name in services.items():
        for tunnel in tunnels:
            if tunnel.get('name', '').startswith(service_key) and tunnel.get('proto') == 'https':
                url = tunnel.get('public_url', '')
                if url and url not in seen_urls:
                    print(f'  {service_name}: {url}')
                    seen_urls.add(url)
                    break
except:
    pass
"

else
    echo -e "${RED}❌ GROUP4 ngrok is not running on port $GROUP4_NGROK_PORT${NC}"
    echo
    echo -e "${YELLOW}To start GROUP4 ngrok, run:${NC}"
    echo "  ./fix_ngrok_config.sh"
    echo "  Or with teammate token: ./fix_ngrok_config.sh \"teammate_token_here\""
    echo
    echo -e "${YELLOW}Checking for conflicts on other ports:${NC}"

    # Check if another team is using 4044
    if curl -s http://localhost:4044/api/tunnels > /dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  Port 4044 is in use (another team's ngrok)${NC}"
        echo "  GROUP4 uses port $GROUP4_NGROK_PORT instead"
    fi

    if curl -s http://localhost:4040/api/tunnels > /dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  Port 4040 is also in use (another team's ngrok)${NC}"
        echo "  GROUP4 uses port $GROUP4_NGROK_PORT instead"
    else
        echo "  No ngrok found on port 4040 either."
    fi
fi

# Check for second ngrok on port 5004 (teammate's account)
echo
if curl -s http://localhost:5004/api/tunnels > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Second ngrok running on port 5004 (teammate account)${NC}"
    echo -e "${BLUE}Prometheus URL:${NC}"
    curl -s http://localhost:5004/api/tunnels | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for tunnel in data.get('tunnels', []):
        if tunnel.get('proto') == 'https':
            print(f'  📊 Prometheus: {tunnel.get(\"public_url\")}')
            break
except: pass
"
fi

echo
echo -e "${BLUE}================================${NC}"
echo -e "${YELLOW}Checking GROUP4 Docker containers:${NC}"
echo

# Check GROUP4 containers
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "NAMES|^group4-" || echo "  No GROUP4 containers running"

EOF

echo
echo -e "${BLUE}======================================${NC}"
echo -e "${GREEN}Need help?${NC}"
echo "  - To deploy: ${YELLOW}./deploy_to_vm.sh group4${NC}"
echo "  - To fix ngrok: ${YELLOW}./fix_all_ngrok_issues.sh${NC}"
echo "  - Ngrok web UI: ${YELLOW}http://localhost:$GROUP4_NGROK_PORT${NC} (via SSH tunnel)"
echo -e "${BLUE}======================================${NC}"
