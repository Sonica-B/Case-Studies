#!/bin/bash

# Quick script to diagnose Docker issues on the VM

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# SSH details
SSH_KEY="$HOME/.ssh/vm"
VM_USER="group4"
VM_HOST="melnibone.wpi.edu"
VM_PORT="2222"

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}   Docker Status Check for GROUP4${NC}"
echo -e "${BLUE}======================================${NC}"
echo

ssh -i "$SSH_KEY" -p $VM_PORT $VM_USER@$VM_HOST << 'REMOTE_CHECK'
# Colors for remote
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}System Information:${NC}"
echo "  Hostname: $(hostname)"
echo "  User: $(whoami)"
echo "  Groups: $(groups)"
echo

# Check for system restart requirement
if [ -f /var/run/reboot-required ]; then
    echo -e "${RED}*** System restart required ***${NC}"
    echo "The VM needs to be restarted. This might be why Docker isn't working."
    echo
fi

echo -e "${YELLOW}Docker Installation Check:${NC}"
# Check if Docker is installed
if command -v docker &> /dev/null; then
    echo -e "  ${GREEN}✓ Docker is installed${NC}"
    echo "  Location: $(which docker)"

    # Try to get Docker version
    if docker version &> /dev/null; then
        echo -e "  ${GREEN}✓ Docker daemon is running${NC}"
        echo "  Server version: $(docker version --format '{{.Server.Version}}' 2>/dev/null)"
        echo "  Client version: $(docker version --format '{{.Client.Version}}' 2>/dev/null)"
    else
        echo -e "  ${RED}✗ Cannot connect to Docker daemon${NC}"

        # Check with sudo
        if sudo docker version &> /dev/null; then
            echo -e "  ${YELLOW}⚠ Docker works with sudo${NC}"
            echo "  This is a permissions issue"
        fi

        # Check Docker service status
        echo
        echo "  Docker service status:"
        systemctl is-active docker || echo "    Service not running"
    fi
else
    echo -e "  ${RED}✗ Docker is NOT installed${NC}"
fi

echo
echo -e "${YELLOW}User Permissions:${NC}"
# Check if user is in docker group
if groups | grep -q docker; then
    echo -e "  ${GREEN}✓ User is in 'docker' group${NC}"
else
    echo -e "  ${RED}✗ User is NOT in 'docker' group${NC}"
    echo "  To fix, ask admin to run:"
    echo "    sudo usermod -aG docker $USER"
    echo "  Then logout and login again"
fi

# Check Docker socket permissions
echo
echo -e "${YELLOW}Docker Socket:${NC}"
if [ -S /var/run/docker.sock ]; then
    echo "  Socket exists: /var/run/docker.sock"
    ls -l /var/run/docker.sock
else
    echo -e "  ${RED}Docker socket not found${NC}"
fi

echo
echo -e "${BLUE}Quick Fix Attempts:${NC}"

# Try newgrp if not in docker group
if ! groups | grep -q docker; then
    echo "You're not in the docker group. After admin adds you, run:"
    echo "  newgrp docker"
else
    # Test Docker access
    echo "Testing Docker access..."
    if docker ps &> /dev/null; then
        echo -e "${GREEN}✅ Docker is working!${NC}"
        echo
        echo "Docker containers currently running:"
        docker ps --format "table {{.Names}}\t{{.Status}}" | head -5
    else
        echo -e "${YELLOW}Trying to refresh group membership...${NC}"
        echo "Run this command on the VM:"
        echo "  newgrp docker"
        echo
        echo "Or logout and login again to refresh permissions"
    fi
fi

echo
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}Summary:${NC}"

if [ -f /var/run/reboot-required ]; then
    echo -e "${RED}⚠ SYSTEM NEEDS RESTART${NC}"
    echo "Ask your instructor to restart the VM"
elif ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker is not installed${NC}"
    echo "Contact your instructor to install Docker"
elif ! groups | grep -q docker; then
    echo -e "${YELLOW}Permission issue: Not in docker group${NC}"
    echo "Ask instructor to run: sudo usermod -aG docker group4"
elif ! docker ps &> /dev/null; then
    echo -e "${YELLOW}Docker installed but not accessible${NC}"
    echo "Try: logout and login again, or run: newgrp docker"
else
    echo -e "${GREEN}Docker appears to be working correctly${NC}"
fi
echo -e "${BLUE}======================================${NC}"
REMOTE_CHECK