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
echo -e "${YELLOW}   GROUP4 Token & SSH Setup (One-Time)${NC}"
echo -e "${YELLOW}======================================${NC}"
echo

echo "This will set up your tokens and SSH access PERMANENTLY."
echo "You'll only need to do this once!"
echo

# Setup SSH agent and passphrase automation
echo -e "${YELLOW}Setting up SSH passphrase automation...${NC}"
echo

# Check if SSH key exists
if [ ! -f "$SSH_KEY" ]; then
    echo -e "${RED}Error: SSH key not found at $SSH_KEY${NC}"
    echo "Please ensure your SSH key is properly set up first."
    exit 1
fi

# Prompt for SSH passphrase
read -s -p "Enter your SSH key passphrase (will be stored securely): " SSH_PASSPHRASE
echo
if [ -z "$SSH_PASSPHRASE" ]; then
    echo -e "${YELLOW}No SSH passphrase provided. You'll need to enter it manually.${NC}"
else
    echo -e "${GREEN}SSH passphrase will be configured for automation.${NC}"
fi

# Get tokens from user
echo
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

echo
echo -e "${YELLOW}Teammate's Ngrok Configuration (for Prometheus):${NC}"
read -p "Enter teammate's Ngrok auth token (or press Enter to skip): " TEAMMATE_NGROK_TOKEN
if [ -z "$TEAMMATE_NGROK_TOKEN" ]; then
    echo -e "${YELLOW}No teammate token provided. Prometheus will not be exposed.${NC}"
else
    echo -e "${GREEN}Teammate token will be saved for Prometheus endpoint.${NC}"
    # Always set the teammate's permanent domain when token is provided
    TEAMMATE_NGROK_DOMAIN="decayless-brenna-unadventurous.ngrok-free.dev"
    echo -e "${GREEN}Using teammate's domain: $TEAMMATE_NGROK_DOMAIN${NC}"
fi

# Setup local SSH automation if passphrase provided
if [ -n "$SSH_PASSPHRASE" ]; then
    echo
    echo -e "${GREEN}Configuring SSH automation...${NC}"

    # Create an expect script for SSH automation
    cat > ~/.ssh_group4_login.exp << EXPECT_SCRIPT
#!/usr/bin/expect -f
set timeout 30
set passphrase "$SSH_PASSPHRASE"
set ssh_key "$SSH_KEY"
set vm_user "$VM_USER"
set vm_host "$VM_HOST"
set vm_port "$VM_PORT"

# Get the command to run from arguments
set cmd [lindex \$argv 0]

if {\$cmd eq ""} {
    # Interactive session
    spawn ssh -i \$ssh_key -p \$vm_port \$vm_user@\$vm_host
} else {
    # Run command
    spawn ssh -i \$ssh_key -p \$vm_port \$vm_user@\$vm_host "\$cmd"
}

expect {
    "Enter passphrase for key*" {
        send "\$passphrase\r"
        exp_continue
    }
    "Are you sure you want to continue connecting*" {
        send "yes\r"
        exp_continue
    }
    eof
}
EXPECT_SCRIPT

    chmod 700 ~/.ssh_group4_login.exp
    echo -e "${GREEN}✅ SSH automation script created at ~/.ssh_group4_login.exp${NC}"

    # Alternative: Create SSH config with sshpass wrapper
    cat > ~/.ssh_group4_connect.sh << SSH_SCRIPT
#!/bin/bash
# SSH connection wrapper with passphrase
export SSH_ASKPASS_REQUIRE=never
export SSH_ASKPASS=/bin/false

# Use expect if available
if command -v expect &> /dev/null; then
    expect ~/.ssh_group4_login.exp "\$@"
else
    # Fallback to regular SSH (will prompt for passphrase)
    ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST "\$@"
fi
SSH_SCRIPT

    chmod +x ~/.ssh_group4_connect.sh
    echo -e "${GREEN}✅ SSH wrapper script created at ~/.ssh_group4_connect.sh${NC}"
fi

# Create .envrc file on the VM
echo
echo -e "${GREEN}Setting up permanent token storage on VM...${NC}"

# Test SSH connection with passphrase if provided
if [ -n "$SSH_PASSPHRASE" ] && command -v expect &> /dev/null; then
    # Use expect to automate the passphrase
    expect << EXPECT_EOF
spawn ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST "bash -s"
expect {
    "Enter passphrase for key*" {
        send "$SSH_PASSPHRASE\r"
        expect "$ " {send ""}
    }
    "$ " {send ""}
}
send "cat > ~/.envrc << 'ENVRC'\r"
send "# GROUP4 Environment Variables\r"
send "export HF_TOKEN=\"$HF_TOKEN\"\r"
send "export NGROK_AUTHTOKEN=\"$NGROK_AUTHTOKEN\"\r"
send "\r"
send "# Teammate's Ngrok for Prometheus (4th service)\r"
send "export TEAMMATE_NGROK_TOKEN=\"$TEAMMATE_NGROK_TOKEN\"\r"
send "export TEAMMATE_NGROK_DOMAIN=\"$TEAMMATE_NGROK_DOMAIN\"\r"
send "\r"
send "# Auto-export for docker-compose\r"
send "export DOCKER_CONTENT_TRUST=0\r"
send "ENVRC\r"
send "\r"
send "# Make it secure\r"
send "chmod 600 ~/.envrc\r"
send "\r"
send "# Add to bashrc to auto-source\r"
send "if ! grep -q 'source ~/.envrc' ~/.bashrc; then\r"
send "    echo '' >> ~/.bashrc\r"
send "    echo '# Auto-load GROUP4 environment' >> ~/.bashrc\r"
send "    echo '[ -f ~/.envrc ] && source ~/.envrc' >> ~/.bashrc\r"
send "fi\r"
send "\r"
send "# Source it now\r"
send "source ~/.envrc\r"
send "\r"
send "# Configure ngrok with the token\r"
send "if [ -n \"\${NGROK_AUTHTOKEN}\" ]; then\r"
send "    ngrok config add-authtoken \${NGROK_AUTHTOKEN}\r"
send "fi\r"
send "\r"
send "echo '✅ Tokens saved permanently in ~/.envrc'\r"
send "echo '✅ Will auto-load on login'\r"
send "echo ''\r"
send "echo 'Current environment:'\r"
send "echo \"HF_TOKEN: \${HF_TOKEN:0:10}...'\r"
send "echo \"NGROK_AUTHTOKEN: \${NGROK_AUTHTOKEN:0:10}...'\r"
send "exit\r"
expect eof
EXPECT_EOF
else
    # Fallback to regular SSH (will prompt for passphrase)
    ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << REMOTE_SETUP
# Create .envrc file with tokens
cat > ~/.envrc << 'ENVRC'
# GROUP4 Environment Variables
export HF_TOKEN="$HF_TOKEN"
export NGROK_AUTHTOKEN="$NGROK_AUTHTOKEN"

# Teammate's Ngrok for Prometheus (4th service)
export TEAMMATE_NGROK_TOKEN="$TEAMMATE_NGROK_TOKEN"
export TEAMMATE_NGROK_DOMAIN="$TEAMMATE_NGROK_DOMAIN"

# Auto-export for docker-compose
export DOCKER_CONTENT_TRUST=0
ENVRC

# Replace placeholders with actual values
sed -i "s|\$HF_TOKEN|${HF_TOKEN}|g" ~/.envrc
sed -i "s|\$NGROK_AUTHTOKEN|${NGROK_AUTHTOKEN}|g" ~/.envrc
sed -i "s|\$TEAMMATE_NGROK_TOKEN|${TEAMMATE_NGROK_TOKEN}|g" ~/.envrc
sed -i "s|\$TEAMMATE_NGROK_DOMAIN|${TEAMMATE_NGROK_DOMAIN}|g" ~/.envrc

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
fi

echo
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}   Setup Complete!${NC}"
echo -e "${GREEN}======================================${NC}"
echo
echo "✅ Your tokens are now permanently stored on the VM."
echo "✅ They will automatically load every time you log in."

if [ -n "$SSH_PASSPHRASE" ]; then
    echo "✅ SSH passphrase automation configured."
    echo
    echo "You can now connect to the VM without entering passphrase:"
    echo "  Using expect:  expect ~/.ssh_group4_login.exp"
    echo "  Using wrapper: ~/.ssh_group4_connect.sh"
    echo
    echo "To update deployment scripts to use automation, add this to them:"
    echo "  export SSH_COMMAND='~/.ssh_group4_connect.sh'"
fi

echo
echo "Next steps:"
echo "  1. Run deployment: ./deploy_to_vm.sh group4"
echo "  2. Setup ngrok:    ./setup_group4_ngrok.sh"
echo