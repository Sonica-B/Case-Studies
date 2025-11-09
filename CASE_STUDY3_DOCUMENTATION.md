# Case Study 3 – Checklist Status (Latest Update)

This document captures the current state of every Case Study 3 requirement after aligning the repo with the professor’s monitoring expectations (Prometheus metrics on port **8000**, Grafana exposed on host **5007** (container port 3000), two ngrok accounts, etc.).

---

## 1. API Product Dockerized
- **Container**: `group4-ml-api-product`
- **Definition**: `Dockerfile.api` (python:3.10-slim, installs app plus `prometheus-node-exporter`)
- **Ports**: 5000 (Gradio), 8000 (Prometheus custom metrics), 9100 (node exporter)
- **Compose Service**: `ml-api` in `docker-compose.yml` / `docker-compose.prod.yml`
- **Notes**: Runs `prometheus-node-exporter` alongside `app_api_prometheus.py`, health-checked via curl on 5000.

## 2. Local Product Dockerized
- **Container**: `group4-ml-local-product`
- **Definition**: `Dockerfile.local` (same base image, pre-downloads CLIP + Wav2Vec2 weights)
- **Ports**: 5003 (Gradio), 8000 in-container mapped to host 8001, node exporter 9100 mapped to 9101
- **Volumes**: `group4-model-cache` for HuggingFace cache reuse
- **Notes**: GPU support disabled to fit the shared VM; metrics-enabled entrypoint `app_local_prometheus.py`.

## 3. Prometheus Node Exporters
- Both Dockerfiles install and start `prometheus-node-exporter --web.listen-address=:9100`.
- **Exposure**:
  - API container: host 9100 → container 9100
  - Local container: host 9101 → container 9100
- Verified in `deploy_to_vm.sh` via `curl http://localhost:9100/metrics` and `curl http://localhost:9101/metrics`.

## 4. Prometheus Client Metrics (Python)
- **API app** (`fusion-app/app_api_prometheus.py`) exposes:
  - Counters: `ml_requests_total`, `ml_successful_requests_total`, `ml_failed_requests_total`, `ml_inference_total`, `ml_api_calls_total`, `ml_errors_by_type_total`
  - Summary: `ml_request_duration_seconds`
  - Histograms: `ml_fusion_alpha`, `ml_prediction_confidence`
  - Gauges: `ml_active_users`
- **Local app** (`fusion-app/app_local_prometheus.py`) adds `ml_model_loaded`, `ml_gpu_available`, `ml_frames_processed_total`, `ml_audio_samples_processed`.
- Both start the exporter on **port 8000** (standard Prometheus client port) and `docker-compose` maps them to `8000` (API) / `8001` (Local) on the host.
- Grafana dashboard updated so every panel references the actual metric names (`ml_request_duration_seconds_*`, `ml_errors_by_type_total`, etc.).

## 5. Container IP Addresses
Run the following after deployment to capture IPs for the grading spreadsheet:
```bash
docker inspect group4-ml-api-product --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
docker inspect group4-ml-local-product --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
docker inspect group4-prometheus --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
docker inspect group4-grafana --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
```
`deploy_to_vm.sh` already prints these four addresses right after the containers start.

## 6–7. Ngrok URLs (API vs. Local/Grafana)
- **Two ngrok accounts** required:
  1. **GROUP4 token** → dedicated to the API product with the permanent domain `https://unremounted-unejective-tracey.ngrok-free.dev`.
  2. **Teammate token** (`TEAMMATE_NGROK_TOKEN` + optional `TEAMMATE_NGROK_DOMAIN`) → exposes **local product (5003)**, **Grafana (5007 → 3000)**, and **Prometheus (5006)** simultaneously via `ngrok-teammate.yml`.
- `deploy_to_vm.sh`, `setup_group4_ngrok.sh`, and `fix_group4.sh` all start the API tunnel on port 5008 (group account) and the teammate tunnels on port 5009. The scripts display every public URL plus the ngrok admin endpoints.
- If the teammate token is missing, the scripts warn that Local + Grafana+Prometheus are **not** publicly reachable (requirement gap).

## 8. Grafana Server Exposure
- **Service**: `group4-grafana` (Grafana OSS) now mapped to host **5007** (still serving on port 3000 inside the container).
- **Provisioning**: Datasource `grafana/datasources/prometheus.yml`, dashboards under `grafana/dashboards/`.
- **Ngrok**: Routed via the teammate account; `setup_*` scripts test `http://localhost:5007` locally before tunneling.

---

## Monitoring Stack Validation
- `prometheus.yml` scrapes:
  - `ml-api:8000` (Python metrics) and `ml-api:9100`
  - `ml-local:8000` and `ml-local:9100`
  - `localhost:9090`
- `grafana/dashboards/ml-monitoring.json` panels now align with the metric names emitted by the code (inference rates, avg latency, API calls, fusion alpha heatmap, prediction confidence median, model loaded gauges, node exporter CPU/memory charts).
- `monitor.py` checks the correct host ports (5000/5003, 8000/8001, 9100/9101, Grafana 5007) and queries `ml_errors_by_type_total` for error-rate reporting.

---

## Quick Reference – Ports
| Purpose                     | Host Port | Container Port |
|-----------------------------|-----------|----------------|
| API Gradio UI               | 5000      | 5000           |
| API Prometheus metrics      | 8000      | 8000           |
| API Node exporter           | 9100      | 9100           |
| Local Gradio UI             | 5003      | 5003           |
| Local Prometheus metrics    | 8001      | 8000           |
| Local Node exporter         | 9101      | 9100           |
| Prometheus UI/API           | 5006      | 9090           |
| Grafana                     | 5007      | 3000           |

---

## Outstanding Risks / Follow-ups
1. **Teammate ngrok token required** – without it, Local product, Grafana, and Prometheus cannot be exposed publicly; deployment scripts warn about this, but the grading checklist expects those URLs.
2. **HF_TOKEN availability** – both apps still require a valid HuggingFace token; ensure it is populated in `.env` or `~/.envrc` before deploying.
3. **Ngrok limits** – free tier allows three tunnels per account. Using two accounts (one for API, one for the other three services) is baked into the scripts; document this when submitting.

Everything else on the checklist now reflects the current repo state.
