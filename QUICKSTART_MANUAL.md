# 🚀 Quick Start Guide - VM Deployment
## Deploys from GitHub Repository on VM

The deployment pulls the latest code from your GitHub repository that's already cloned on the VM.

## Prerequisites
- ✅ WSL with SSH key (`~/.ssh/vm`)
- ✅ Access to melnibone.wpi.edu:2222 (username: group4)
- ✅ HuggingFace token
- ✅ Ngrok auth token
- ✅ Code pushed to GitHub branch `cs3`

## Step-by-Step Deployment

### 1️⃣ Open WSL and Navigate to Project
```bash
# Open WSL
wsl

# Navigate to project
cd /mnt/d/WPI\ Assignments/MLOps/CaseStudy3/Case-Studies
```

### 2️⃣ Set Your Tokens
```bash
# Set environment variables
export HF_TOKEN="hf_xxxxxxxxxxxxxxxxxx"
export NGROK_AUTHTOKEN="2xxxxxxxxxxxxxxxxxx"
```

To get tokens:
- HuggingFace: https://huggingface.co/settings/tokens
- Ngrok: https://dashboard.ngrok.com/auth

### 3️⃣ Push Your Code to GitHub
```bash
# Commit and push your changes
git add .
git commit -m "Update configuration for deployment"
git push origin cs3
```

### 4️⃣ Run Deployment Script
```bash
# Make sure script is executable
chmod +x deploy_to_vm.sh

# Deploy (defaults to group4 username)
./deploy_to_vm.sh

# Or with custom username
./deploy_to_vm.sh your-username
```

**You'll be prompted for your SSH key password** - this is normal.

### 5️⃣ Wait for Deployment
The script will:
1. Connect to VM via SSH
2. Pull latest code from GitHub (branch cs3)
3. Build Docker images (5-10 minutes)
4. Start all services
5. Verify endpoints

### 6️⃣ Set Up SSH Tunnel (New Terminal)
Open a **new terminal** and run:

**From Windows CMD/PowerShell:**
```cmd
ssh_tunnel.bat   # Uses default group4
# OR
ssh_tunnel.bat your-username
```

**From WSL:**
```bash
./ssh_tunnel.sh   # Uses default group4
# OR
./ssh_tunnel.sh your-username
```

### 7️⃣ Access Your Services
With tunnel running, open browser to:
- 🎨 **API Product**: http://localhost:5000
- 🖼️ **Local Product**: http://localhost:5003
- 📊 **Prometheus**: http://localhost:5006
- 📈 **Grafana**: http://localhost:5007 (admin/admin)

## Quick Commands Reference

### Check Status on VM
```bash
ssh -i ~/.ssh/vm -p 2222 group4@melnibone.wpi.edu
cd ~/Case-Studies
docker ps
```

### View Logs
```bash
ssh -i ~/.ssh/vm -p 2222 group4@melnibone.wpi.edu
cd ~/Case-Studies
docker-compose logs ml-api
```

### Restart Services
```bash
ssh -i ~/.ssh/vm -p 2222 group4@melnibone.wpi.edu
cd ~/Case-Studies
docker-compose restart
```

### Stop Everything
```bash
ssh -i ~/.ssh/vm -p 2222 group4@melnibone.wpi.edu
cd ~/Case-Studies
docker-compose down
```

## For Assignment Submission

### Get Container IPs:
```bash
ssh -i ~/.ssh/vm -p 2222 group4@melnibone.wpi.edu
docker inspect ml-api-product | grep IPAddress
docker inspect ml-local-product | grep IPAddress
```

### Your Port Range:
**5000-5009** (Add this to Google Sheet)

### Take Screenshots:
1. Docker containers running (`docker ps`)
2. API Product UI (http://localhost:5000)
3. Local Product UI (http://localhost:5003)
4. Prometheus targets (http://localhost:5006/targets)
5. Grafana dashboard (http://localhost:5007)

## Troubleshooting

### "Permission denied"
- Check username is correct
- Ensure you're connected to VPN (if off-campus)

### Services not starting
- Check Docker logs: `docker-compose logs`
- Verify tokens are set correctly
- Check disk space: `df -h`

### Port already in use
- Another team might be using ports
- Run: `docker-compose down` first

### Can't connect to services
- Make sure SSH tunnel is running
- Check containers are up: `docker ps`

## Complete Deployment in 5 Minutes

```bash
# Quick copy-paste commands:

# 1. In WSL
cd /mnt/d/WPI\ Assignments/MLOps/CaseStudy3/Case-Studies

# 2. Push code to GitHub
git add .
git commit -m "Update for deployment"
git push origin cs3

# 3. Set tokens
export HF_TOKEN="your-token-here"
export NGROK_AUTHTOKEN="your-token-here"

# 4. Deploy (uses group4 by default)
./deploy_to_vm.sh

# 5. In new terminal (Windows)
ssh_tunnel.bat

# 6. Open browser to http://localhost:5000
```

That's it! Your ML products are deployed! 🎉