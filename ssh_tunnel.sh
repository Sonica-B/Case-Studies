#!/bin/bash
# SSH Tunnel Script for WPI VM Access

# Configuration
VM_HOST="melnibone.wpi.edu"
VM_PORT="2222"
VM_USER="${1:-group4}"  # Pass username as first argument (defaults to group4)
SSH_KEY="$HOME/.ssh/vm"  # SSH key location

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    color=$1
    message=$2
    echo -e "${color}${message}${NC}"
}

# Check SSH key exists
if [ ! -f "$SSH_KEY" ]; then
    print_color "$RED" "Error: SSH key not found at $SSH_KEY"
    print_color "$YELLOW" "Please ensure your SSH key is at ~/.ssh/vm"
    exit 1
fi

# Show configuration
if [ -n "$1" ]; then
    print_color "$YELLOW" "Using custom username: $VM_USER"
else
    print_color "$GREEN" "Using default username: group4"
fi

print_color "$BLUE" "========================================="
print_color "$BLUE" "WPI VM SSH Tunnel Setup"
print_color "$BLUE" "========================================="
echo

# Function to check if port is available locally
check_port() {
    port=$1
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        print_color "$YELLOW" "Warning: Port $port is already in use locally"
        return 1
    fi
    return 0
}

# Check local ports
print_color "$YELLOW" "Checking local port availability..."
ports_available=true
for port in 5000 5003 5006 5007 8000 8001 5002 5005; do
    if ! check_port $port; then
        ports_available=false
    fi
done

if [ "$ports_available" = false ]; then
    print_color "$RED" "Some ports are in use. Continue anyway? (y/n)"
    read -r response
    if [ "$response" != "y" ]; then
        exit 1
    fi
fi

# SSH tunnel commands
print_color "$GREEN" "Setting up SSH tunnels to WPI VM..."
print_color "$YELLOW" "VM Host: $VM_HOST"
print_color "$YELLOW" "SSH Port: $VM_PORT"
print_color "$YELLOW" "Username: $VM_USER"
echo

# Create the SSH tunnel with all ports
SSH_CMD="ssh -i $SSH_KEY -N \
    -L 5000:localhost:5000 \
    -L 8000:localhost:8000 \
    -L 5002:localhost:9100 \
    -L 5003:localhost:5003 \
    -L 8001:localhost:8001 \
    -L 5005:localhost:9100 \
    -L 5006:localhost:5006 \
    -L 5007:localhost:5007 \
    -p $VM_PORT \
    $VM_USER@$VM_HOST"

print_color "$GREEN" "Establishing SSH tunnel using key: $SSH_KEY"
print_color "$YELLOW" "You may be prompted for your SSH key password (if protected)"
echo

# Start SSH tunnel in background
$SSH_CMD &
SSH_PID=$!

# Wait a moment for connection
sleep 3

# Check if SSH tunnel is running
if kill -0 $SSH_PID 2>/dev/null; then
    print_color "$GREEN" "✅ SSH tunnel established successfully! (PID: $SSH_PID)"
    echo
    print_color "$BLUE" "========================================="
    print_color "$BLUE" "Services are now accessible at:"
    print_color "$BLUE" "========================================="
    echo
    echo "  API Product:       http://localhost:5000"
    echo "  API Metrics:       http://localhost:8000/metrics"
    echo "  API Node Exporter: http://localhost:5002/metrics"
    echo "  Local Product:     http://localhost:5003"
    echo "  Local Metrics:     http://localhost:8001/metrics"
    echo "  Local Node Exporter: http://localhost:5005/metrics"
    echo "  Prometheus:        http://localhost:5006"
    echo "  Grafana:           http://localhost:5007 (admin/admin)"
    echo
    print_color "$YELLOW" "To stop the tunnel, press Ctrl+C or run: kill $SSH_PID"
    echo
    print_color "$GREEN" "Tunnel is running. Press Ctrl+C to stop."

    # Wait for user to stop
    wait $SSH_PID
else
    print_color "$RED" "❌ Failed to establish SSH tunnel"
    print_color "$YELLOW" "Please check:"
    echo "  1. Your WPI credentials"
    echo "  2. VPN connection (if off-campus)"
    echo "  3. Network connectivity"
    exit 1
fi
