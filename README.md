# Case Study 3 - ML Products with Prometheus Monitoring

This project deploys two ML products (API-based and locally-executed) with comprehensive Prometheus monitoring to a WPI VM environment.

## 🎯 Features

- **Two ML Products**:
  - API-based product using HuggingFace APIs for CLIP and Wav2Vec2
  - Locally-executed product with downloaded models
- **Prometheus Monitoring** with 10+ custom metrics
- **Grafana Dashboard** for visualization
- **Docker Containerization** for all services
- **Port Range**: 5000-5009 (exclusive allocation)
- **GROUP4 Isolation**: All containers/images prefixed with `group4-` to avoid conflicts

## 📁 Project Structure

```
Case-Studies/
├── fusion-app/                   # ML applications
│   ├── app_api_prometheus.py     # API product with metrics
│   ├── app_local_prometheus.py   # Local product with metrics
│   ├── app_api.py               # Original API implementation
│   └── app_local.py             # Original local implementation
├── grafana/                      # Grafana configuration
│   ├── dashboards/              # Dashboard JSON files
│   └── datasources/             # Prometheus datasource
├── Dockerfile.api                # API product container
├── Dockerfile.local              # Local product container
├── docker-compose.yml            # Service orchestration
├── prometheus.yml                # Prometheus configuration
├── monitor.py                    # Health monitoring script
├── deploy_to_vm.sh              # Manual deployment script
├── ssh_tunnel.sh                # Linux/Mac SSH tunnel
├── ssh_tunnel.bat               # Windows SSH tunnel
└── verify_setup.sh              # Setup verification
```

## 🚀 Quick Start

### Prerequisites
- SSH access to melnibone.wpi.edu:2222 (username: group4)
- SSH key at `~/.ssh/vm` in WSL
- HuggingFace API token
- Ngrok authentication token
- Code pushed to GitHub branch `cs3`

### Deploy in 5 Minutes

1. **Open WSL and navigate to project**:
   ```bash
   wsl
   cd /mnt/d/WPI\ Assignments/MLOps/CaseStudy3/Case-Studies
   ```

2. **Push latest code to GitHub**:
   ```bash
   git add .
   git commit -m "Update configuration"
   git push origin cs3
   ```

3. **Set your tokens**:
   ```bash
   export HF_TOKEN="hf_xxxxxxxxxxxxxxxxxx"
   export NGROK_AUTHTOKEN="2xxxxxxxxxxxxxxxxxx"
   ```

4. **Deploy to VM** (pulls from GitHub):
   ```bash
   ./deploy_to_vm.sh  # Uses default username group4
   ```
   Enter your SSH key password when prompted.

5. **Access services** via Ngrok public URLs (automatically set up during deployment)
   - URLs will be displayed after deployment
   - No SSH tunnel needed for public access

   **Alternative: Local access via SSH tunnel**:
   ```bash
   # Windows
   ssh_tunnel.bat  # Uses default group4

   # Linux/Mac
   ./ssh_tunnel.sh  # Uses default group4
   ```
   Then access:
   - API Product: http://localhost:5000
   - Local Product: http://localhost:5003
   - Prometheus: http://localhost:5006
   - Grafana: http://localhost:5007 (admin/admin)

## 📊 Port Allocation

Your team's exclusive ports:
- **5000**: API Product (Gradio UI)
- **5001**: API Metrics endpoint
- **5002**: API Node Exporter
- **5003**: Local Product (Gradio UI)
- **5004**: Local Metrics endpoint
- **5005**: Local Node Exporter
- **5006**: Prometheus Server
- **5007**: Grafana Dashboard

## 🔍 Verification

Run the verification script to check your setup:
```bash
./verify_setup.sh
```

## 📈 Monitoring

Check service health:
```bash
python monitor.py
```

## 📝 Assignment Deliverables

### Screenshots Required:
1. Docker containers running (`docker ps`)
2. API Product inference
3. Local Product inference
4. Prometheus targets
5. Grafana dashboard

### Container IPs:
```bash
ssh -i ~/.ssh/vm -p 2222 group4@melnibone.wpi.edu
docker inspect group4-ml-api-product | grep IPAddress
docker inspect group4-ml-local-product | grep IPAddress
```

## 🛠️ Troubleshooting

### SSH Connection Failed
- Check VPN connection (if off-campus)
- Verify SSH key exists at `~/.ssh/vm`
- Ensure SSH key password is correct

### Services Not Starting
```bash
ssh -i ~/.ssh/vm -p 2222 group4@melnibone.wpi.edu
cd ~/Case-Studies
docker-compose logs
```

### Port Already in Use
```bash
docker-compose down
docker system prune -f
```

## 📚 Documentation

- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Fix common issues (GPU error, etc.)
- [GROUP4_ISOLATION.md](GROUP4_ISOLATION.md) - How GROUP4 resources are isolated
- [SSH_KEY_SETUP.md](SSH_KEY_SETUP.md) - SSH key configuration

## 🎯 Key Commands

```bash
# Deploy (pulls from GitHub)
./deploy_to_vm.sh  # Uses group4 by default

# Access services
./ssh_tunnel.sh  # Uses group4 by default

# Check status
ssh -i ~/.ssh/vm -p 2222 group4@melnibone.wpi.edu "cd ~/Case-Studies && docker ps"

# View logs
ssh -i ~/.ssh/vm -p 2222 group4@melnibone.wpi.edu "cd ~/Case-Studies && docker-compose logs"

# Restart services
ssh -i ~/.ssh/vm -p 2222 group4@melnibone.wpi.edu "cd ~/Case-Studies && docker-compose restart"

# Stop everything
ssh -i ~/.ssh/vm -p 2222 group4@melnibone.wpi.edu "cd ~/Case-Studies && docker-compose down"
```

---

**Note**: This project deploys from the GitHub repository already cloned on the VM. The deployment script pulls the latest code from the `cs3` branch and builds containers.