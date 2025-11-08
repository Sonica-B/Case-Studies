# Smart Gateway Solution for GROUP4

## Overview

This document describes the Smart Gateway solution that enables toggling between API and Local ML models through a single endpoint, solving the ngrok free tier limitations and providing a seamless user experience.

## Problem Statement

- **Original Issue**: Ngrok misconfiguration routing to wrong ports (32150 instead of GROUP4's 5000-5007)
- **Constraint**: Ngrok free tier limits to 3 endpoints per auth token
- **Requirement**: Need to expose 4 services (ML-API, ML-Local, Grafana, Prometheus)
- **Final Challenge**: Toggle between API and Local models through single endpoint

## Solution Architecture

### Smart Proxy Gateway

The solution implements a smart proxy gateway that:

1. **Single Endpoint Access**: Runs on port 8000, requiring only 1 ngrok tunnel
2. **Model Toggle**: Cookie-based preference system to switch between models
3. **Session Persistence**: User preferences saved for 30 days
4. **Transparent Routing**: Automatically routes to correct backend based on selection

### Components

```
┌──────────────────────────────────────┐
│         Smart Gateway (8000)         │
│        smart_proxy.py (Flask)        │
│   ┌────────────────────────────┐     │
│   │   Cookie-based Routing     │     │
│   │   model_preference=api/local│     │
│   └────────────────────────────┘     │
└──────────┬───────────────┬──────────┘
           │               │
           ▼               ▼
    ┌──────────┐    ┌──────────┐
    │ ML-API   │    │ML-Local  │
    │ (5000)   │    │ (5003)   │
    │  CLIP    │    │Wav2Vec2  │
    └──────────┘    └──────────┘
```

## Implementation Files

### Core Files

1. **fusion-app/smart_proxy.py**
   - Flask application implementing the gateway
   - Cookie-based model selection
   - Health check endpoints
   - Transparent request forwarding

2. **fusion-app/Dockerfile.gateway**
   - Container definition for the gateway
   - Minimal Python 3.9 image
   - Flask and requests dependencies

3. **docker-compose.gateway.yml**
   - Overlay configuration for Docker Compose
   - Integrates gateway with existing services
   - Network mode: host for local service access

### Deployment Scripts

1. **deploy_smart_gateway.sh**
   - Complete deployment automation
   - Builds gateway Docker image
   - Configures single ngrok endpoint
   - Verifies deployment health

2. **test_gateway.sh**
   - Comprehensive testing suite
   - Verifies backend services
   - Tests model toggle functionality
   - Checks proxy forwarding

## Usage Instructions

### Deploy the Gateway

```bash
# Make script executable
chmod +x deploy_smart_gateway.sh

# Deploy the gateway
./deploy_smart_gateway.sh

# Optional: Include monitoring
./deploy_smart_gateway.sh --with-monitoring
```

### Access the Gateway

1. **Visit the Gateway URL**:
   ```
   https://unremounted-unejective-tracey.ngrok-free.dev
   ```

2. **Toggle Between Models**:
   - Use the web interface toggle switch
   - Or programmatically: `POST /toggle`

3. **Access Model Interface**:
   - Navigate to `/app` endpoint
   - Gateway automatically routes to selected model

### Test the Gateway

```bash
# Run test suite
chmod +x test_gateway.sh
./test_gateway.sh
```

## API Endpoints

### Main Endpoints

- `GET /` - Gateway homepage with toggle interface
- `POST /toggle` - Switch between API/Local models
- `GET /app` - Access current model's Gradio interface
- `GET /health` - Gateway health status

### Response Examples

**Health Check**:
```json
{
  "gateway": "healthy",
  "current_model": "api",
  "services": {
    "api": "healthy",
    "local": "healthy"
  }
}
```

**Toggle Response**:
```json
{
  "model": "local"
}
```

## Benefits

1. **Single Ngrok Endpoint**: Only needs 1 tunnel instead of 4
2. **Seamless Switching**: No URL changes when toggling models
3. **User Preference**: Cookie-based persistence across sessions
4. **Resource Efficient**: Both models run but only one is accessed
5. **Monitoring Ready**: Grafana can still access Prometheus internally

## Optimizations Applied

### Ngrok Optimization

- **Before**: 4 endpoints needed (exceeds free tier)
- **After**: 1 endpoint for gateway, optional 1 for monitoring
- **Result**: Fits within free tier with room to spare

### Service Exposure

- **ML Services**: Not exposed externally, accessed via gateway
- **Prometheus**: No external access needed (Grafana queries internally)
- **Grafana**: Optional external access for monitoring
- **Gateway**: Single public endpoint for all ML functionality

## Troubleshooting

### Common Issues

1. **Gateway Not Starting**:
   ```bash
   docker logs group4-gateway
   ```

2. **Models Not Accessible**:
   ```bash
   docker ps | grep group4
   # Ensure ml-api and ml-local are running
   ```

3. **Toggle Not Working**:
   - Clear browser cookies
   - Check health endpoint: `curl http://localhost:8000/health`

### Verification Commands

```bash
# Check running services
docker ps --format "table {{.Names}}\t{{.Status}}" | grep group4

# Test model toggle
curl -X POST http://localhost:8000/toggle

# Check ngrok status
curl -s http://localhost:5008/api/tunnels | python3 -m json.tool
```

## Summary

The Smart Gateway solution successfully:

- ✅ Fixes original port misconfiguration
- ✅ Works within ngrok free tier limits
- ✅ Provides single endpoint access
- ✅ Enables model toggling without URL changes
- ✅ Maintains all existing functionality
- ✅ Adds user preference persistence
- ✅ Reduces complexity and resource usage

This solution elegantly addresses all requirements while improving the overall architecture and user experience.