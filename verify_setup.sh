#!/bin/bash
# Verification script for Case Study 3 setup

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_color() {
    color=$1
    message=$2
    echo -e "${color}${message}${NC}"
}

print_header() {
    echo
    print_color "$BLUE" "========================================="
    print_color "$BLUE" "$1"
    print_color "$BLUE" "========================================="
}

# Track errors
errors=0
warnings=0

print_header "Case Study 3 Setup Verification"

# Check required files
print_color "$YELLOW" "Checking required files..."
required_files=(
    "Dockerfile.api"
    "Dockerfile.local"
    "docker-compose.yml"
    "prometheus.yml"
    "fusion-app/app_api_prometheus.py"
    "fusion-app/app_local_prometheus.py"
    "monitor.py"
    "deploy_to_vm.sh"
    "ssh_tunnel.sh"
    "ssh_tunnel.bat"
)

for file in "${required_files[@]}"; do
    if [ -f "$file" ]; then
        print_color "$GREEN" "✅ $file exists"
    else
        print_color "$RED" "❌ Missing: $file"
        ((errors++))
    fi
done

# Check Grafana dashboards
if [ -d "grafana/dashboards" ]; then
    dashboard_count=$(ls grafana/dashboards/*.json 2>/dev/null | wc -l)
    if [ "$dashboard_count" -gt 0 ]; then
        print_color "$GREEN" "✅ Found $dashboard_count Grafana dashboard(s)"
    else
        print_color "$YELLOW" "⚠️ No Grafana dashboards found (optional)"
        ((warnings++))
    fi
else
    print_color "$YELLOW" "⚠️ Grafana dashboard directory not found (optional)"
    ((warnings++))
fi

# Check if GitHub repository is configured
print_header "GitHub Configuration"
if [ -d ".git" ]; then
    print_color "$GREEN" "✅ Git repository initialized"

    # Check remote
    if git remote -v | grep -q origin; then
        remote_url=$(git remote get-url origin)
        print_color "$GREEN" "✅ Remote configured: $remote_url"
    else
        print_color "$RED" "❌ No git remote configured"
        ((errors++))
    fi

    # Check current branch
    branch=$(git branch --show-current)
    print_color "$YELLOW" "Current branch: $branch"
else
    print_color "$RED" "❌ Not a git repository"
    ((errors++))
fi

# Check Docker
print_header "Docker Configuration"
if command -v docker &> /dev/null; then
    print_color "$GREEN" "✅ Docker is installed"
    docker --version

    # Check Docker daemon
    if docker ps &> /dev/null; then
        print_color "$GREEN" "✅ Docker daemon is running"
    else
        print_color "$RED" "❌ Docker daemon is not accessible"
        ((errors++))
    fi
else
    print_color "$RED" "❌ Docker is not installed"
    ((errors++))
fi

# Check Docker Compose
if command -v docker-compose &> /dev/null; then
    print_color "$GREEN" "✅ Docker Compose is installed"
    docker-compose --version
else
    print_color "$YELLOW" "⚠️ docker-compose command not found (may be using docker compose)"
    ((warnings++))
fi

# Check port configuration
print_header "Port Configuration"
print_color "$YELLOW" "Key ports: 5000, 5003, 5006, 5007, 8000, 8001, 9100, 9101"
ports=(5000 5003 5006 5007 8000 8001 9100 9101)
for port in "${ports[@]}"; do
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        print_color "$YELLOW" "⚠️ Port $port is currently in use locally"
        ((warnings++))
    else
        print_color "$GREEN" "✅ Port $port is available"
    fi
done

# Test SSH connection (optional)
print_header "VM Connection Test"
read -p "Do you want to test SSH connection to WPI VM? (y/n): " test_ssh
if [ "$test_ssh" = "y" ]; then
    read -p "Enter your WPI username: " username
    print_color "$YELLOW" "Testing connection to melnibone.wpi.edu..."
    if ssh -o ConnectTimeout=5 -p 2222 $username@melnibone.wpi.edu "echo 'Connection successful'" 2>/dev/null; then
        print_color "$GREEN" "✅ SSH connection successful"
    else
        print_color "$RED" "❌ SSH connection failed"
        print_color "$YELLOW" "Make sure you:"
        echo "  1. Have VPN connected (if off-campus)"
        echo "  2. Have correct username"
        echo "  3. Have SSH key configured"
        ((errors++))
    fi
fi

# Token checklist
print_header "Required Tokens"
print_color "$YELLOW" "Have you obtained these tokens?"
echo "  [ ] HF_TOKEN - HuggingFace API token"
echo "      Get from: https://huggingface.co/settings/tokens"
echo "  [ ] NGROK_AUTHTOKEN - Ngrok authentication token"
echo "      Get from: https://dashboard.ngrok.com/auth"
echo
print_color "$YELLOW" "You'll set these when running deploy_to_vm.sh"

# Summary
print_header "Verification Summary"
if [ $errors -eq 0 ]; then
    if [ $warnings -eq 0 ]; then
        print_color "$GREEN" "✅ All checks passed! Ready for deployment."
    else
        print_color "$GREEN" "✅ Setup complete with $warnings warning(s)"
    fi
    echo
    print_color "$BLUE" "Next steps:"
    echo "  1. Get HF_TOKEN and NGROK_AUTHTOKEN"
    echo "  2. Run: export HF_TOKEN='your-token'"
    echo "  3. Run: export NGROK_AUTHTOKEN='your-token'"
    echo "  4. Run: ./deploy_to_vm.sh your-username"
    echo "  5. Use ssh_tunnel script to access services"
else
    print_color "$RED" "❌ Found $errors error(s) that need to be fixed"
    if [ $warnings -gt 0 ]; then
        print_color "$YELLOW" "Also found $warnings warning(s)"
    fi
fi

# Port allocation info
print_header "Port Allocation for Google Sheet"
print_color "$BLUE" "Your team's port allocation:"
echo "  - 5000: API Product (Gradio UI)"
echo "  - 5003: Local Product (Gradio UI)"
echo "  - 5006: Prometheus Server"
echo "  - 5007: Grafana Dashboard (host) / 3000 in-container"
echo "  - 8000: API Prometheus metrics"
echo "  - 8001: Local Prometheus metrics"
echo "  - 9100: API Node Exporter"
echo "  - 9101: Local Node Exporter"

echo
