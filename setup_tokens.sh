#!/bin/bash

# ============================================================================
# ONE-TIME SETUP SCRIPT FOR PERMANENT TOKEN STORAGE
# Run this once to set up your tokens permanently on the VM
# ============================================================================

# Colors
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# SSH details
SSH_KEY="$HOME/.ssh/vm"
VM_USER="group4"
VM_HOST="melnibone.wpi.edu"
VM_PORT="2222"

echo -e "${YELLOW}======================================${NC}"
echo -e "${YELLOW}   GROUP4 Token Setup (One-Time)${NC}"
echo -e "${YELLOW}======================================${NC}"
echo

echo "This will set up your tokens PERMANENTLY on the VM."
echo "You'll only need to do this once!"
echo

# Get tokens from user
echo -e "${YELLOW}Please provide your tokens:${NC}"
echo

read -p "Enter your Hugging Face token (starts with hf_): " HF_TOKEN
if [ -z "$HF_TOKEN" ]; then
    echo -e "${RED}Error: HF_TOKEN is required!${NC}"
    echo "Get one from: https://huggingface.co/settings/tokens"
    exit 1
fi

read -p "Enter your Ngrok auth token (or press Enter to skip): " NGROK_AUTHTOKEN
if [ -z "$NGROK_AUTHTOKEN" ]; then
    echo -e "${YELLOW}Warning: No Ngrok token provided. You may have limited functionality.${NC}"
fi

# Create .envrc file on the VM
echo
echo -e "${GREEN}Setting up permanent token storage on VM...${NC}"

ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << REMOTE_SETUP
# Create .envrc file with tokens
cat > ~/.envrc << 'ENVRC'
# GROUP4 Environment Variables
export HF_TOKEN="$HF_TOKEN"
export NGROK_AUTHTOKEN="$NGROK_AUTHTOKEN"

# Auto-export for docker-compose
export DOCKER_CONTENT_TRUST=0
ENVRC

# Replace placeholders with actual values
sed -i "s|\$HF_TOKEN|${HF_TOKEN}|g" ~/.envrc
sed -i "s|\$NGROK_AUTHTOKEN|${NGROK_AUTHTOKEN}|g" ~/.envrc

# Make it secure
chmod 600 ~/.envrc

# Add to bashrc to auto-source
if ! grep -q "source ~/.envrc" ~/.bashrc; then
    echo "" >> ~/.bashrc
    echo "# Auto-load GROUP4 environment" >> ~/.bashrc
    echo "[ -f ~/.envrc ] && source ~/.envrc" >> ~/.bashrc
fi

# Source it now
source ~/.envrc

# Configure ngrok with the token
if [ -n "${NGROK_AUTHTOKEN}" ]; then
    ngrok config add-authtoken ${NGROK_AUTHTOKEN}
fi

echo "✅ Tokens saved permanently in ~/.envrc"
echo "✅ Will auto-load on login"
echo ""
echo "Current environment:"
echo "HF_TOKEN: \${HF_TOKEN:0:10}..."
echo "NGROK_AUTHTOKEN: \${NGROK_AUTHTOKEN:0:10}..."
REMOTE_SETUP

echo
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}   Setup Complete!${NC}"
echo -e "${GREEN}======================================${NC}"
echo
echo "Your tokens are now permanently stored on the VM."
echo "They will automatically load every time you log in."
echo
echo "Next step: Run the deployment"
echo "  ./deploy_to_vm.sh group4"
echo