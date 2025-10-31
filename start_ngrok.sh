#!/bin/bash
# Ngrok setup script for GROUP4 services

# Configuration
NGROK_AUTHTOKEN="${NGROK_AUTHTOKEN}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_color() {
    echo -e "${1}${2}${NC}"
}

print_header() {
    echo
    print_color "$BLUE" "========================================="
    print_color "$BLUE" "$1"
    print_color "$BLUE" "========================================="
}

# Check if ngrok authtoken is set
if [ -z "$NGROK_AUTHTOKEN" ]; then
    print_color "$RED" "Error: NGROK_AUTHTOKEN not set"
    echo "Please set: export NGROK_AUTHTOKEN='your-token'"
    exit 1
fi

print_header "Starting Ngrok Tunnels for GROUP4 Services"

# Kill any existing ngrok processes
print_color "$YELLOW" "Stopping any existing ngrok processes..."
pkill -f ngrok || true
sleep 2

# Configure ngrok
print_color "$GREEN" "Configuring ngrok..."
ngrok config add-authtoken $NGROK_AUTHTOKEN

# Create ngrok configuration
cat > ngrok-group4.yml << EOF
version: "2"
authtoken: $NGROK_AUTHTOKEN
tunnels:
  group4-api:
    proto: http
    addr: 5000
    inspect: false
    bind_tls: true
  group4-api-metrics:
    proto: http
    addr: 5001
    inspect: false
  group4-local:
    proto: http
    addr: 5003
    inspect: false
    bind_tls: true
  group4-local-metrics:
    proto: http
    addr: 5004
    inspect: false
  group4-prometheus:
    proto: http
    addr: 5006
    inspect: false
  group4-grafana:
    proto: http
    addr: 5007
    inspect: false
EOF

# Start ngrok with all tunnels
print_color "$GREEN" "Starting ngrok tunnels..."
nohup ngrok start --all --config ngrok-group4.yml > ngrok-group4.log 2>&1 &
NGROK_PID=$!

print_color "$GREEN" "Ngrok started with PID: $NGROK_PID"

# Wait for ngrok to start
sleep 5

# Get tunnel URLs
print_header "Public URLs for GROUP4 Services"

# Function to get ngrok URL
get_ngrok_url() {
    local tunnel_name=$1
    local url=$(curl -s http://localhost:4040/api/tunnels | python3 -c "
import json, sys
data = json.load(sys.stdin)
for tunnel in data.get('tunnels', []):
    if tunnel.get('name') == '$tunnel_name':
        print(tunnel.get('public_url', 'Not available'))
        break
else:
    print('Not available')
")
    echo $url
}

# Display URLs
echo
print_color "$GREEN" "API Product (Gradio):"
echo "  $(get_ngrok_url 'group4-api')"
echo
print_color "$GREEN" "API Metrics:"
echo "  $(get_ngrok_url 'group4-api-metrics')"
echo
print_color "$GREEN" "Local Product (Gradio):"
echo "  $(get_ngrok_url 'group4-local')"
echo
print_color "$GREEN" "Local Metrics:"
echo "  $(get_ngrok_url 'group4-local-metrics')"
echo
print_color "$GREEN" "Prometheus:"
echo "  $(get_ngrok_url 'group4-prometheus')"
echo
print_color "$GREEN" "Grafana:"
echo "  $(get_ngrok_url 'group4-grafana')"

# Save URLs to file
print_color "$YELLOW" "Saving URLs to ngrok-urls.txt..."
{
    echo "GROUP4 Ngrok Public URLs - $(date)"
    echo "=================================="
    echo "API Product: $(get_ngrok_url 'group4-api')"
    echo "API Metrics: $(get_ngrok_url 'group4-api-metrics')"
    echo "Local Product: $(get_ngrok_url 'group4-local')"
    echo "Local Metrics: $(get_ngrok_url 'group4-local-metrics')"
    echo "Prometheus: $(get_ngrok_url 'group4-prometheus')"
    echo "Grafana: $(get_ngrok_url 'group4-grafana')"
} > ngrok-urls.txt

echo
print_color "$GREEN" "✅ Ngrok tunnels are running!"
print_color "$YELLOW" "URLs saved to: ngrok-urls.txt"
print_color "$YELLOW" "Logs available at: ngrok-group4.log"
print_color "$YELLOW" "To stop: pkill -f ngrok"
echo