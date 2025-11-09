#!/usr/bin/env python3
"""
Health Monitoring Script for ML Products
Checks the status of all deployed services and displays metrics
"""

import requests
import json
import sys
import time
from datetime import datetime

# Service endpoints
SERVICES = {
    "API Product (Gradio)": "http://localhost:5000",
    "Local Product (Gradio)": "http://localhost:5003",
    "API Node Exporter": "http://localhost:5002/metrics",
    "API Python Metrics": "http://localhost:8000/metrics",
    "Local Node Exporter": "http://localhost:5005/metrics",
    "Local Python Metrics": "http://localhost:8001/metrics",
    "Prometheus": "http://localhost:5006/-/ready",
    "Grafana": "http://localhost:5007/api/health",
    "Ngrok API": "http://localhost:4040/api/tunnels",
    "Ngrok Local": "http://localhost:4041/api/tunnels",
    "Ngrok Grafana": "http://localhost:4042/api/tunnels"
}

def check_service(name, url):
    """Check if a service is responding"""
    try:
        response = requests.get(url, timeout=5)
        if response.status_code == 200:
            return True, "✅ Running"
        else:
            return False, f"⚠️ Status: {response.status_code}"
    except requests.exceptions.ConnectionError:
        return False, "❌ Not reachable"
    except requests.exceptions.Timeout:
        return False, "⏱️ Timeout"
    except Exception as e:
        return False, f"❌ Error: {str(e)}"

def get_prometheus_metrics():
    """Get key metrics from Prometheus"""
    metrics = {}
    try:
        # Query for total inferences
        query = "sum(ml_inference_total)"
        response = requests.get(f"http://localhost:5006/api/v1/query",
                               params={"query": query}, timeout=5)
        if response.status_code == 200:
            data = response.json()
            if data['data']['result']:
                metrics['Total Inferences'] = int(float(data['data']['result'][0]['value'][1]))

        # Query for active users
        query = "sum(ml_active_users)"
        response = requests.get(f"http://localhost:5006/api/v1/query",
                               params={"query": query}, timeout=5)
        if response.status_code == 200:
            data = response.json()
            if data['data']['result']:
                metrics['Active Users'] = int(float(data['data']['result'][0]['value'][1]))

        # Query for error rate
        query = "sum(rate(ml_errors_by_type_total[5m]))"
        response = requests.get(f"http://localhost:5006/api/v1/query",
                               params={"query": query}, timeout=5)
        if response.status_code == 200:
            data = response.json()
            if data['data']['result']:
                metrics['Error Rate (5m)'] = f"{float(data['data']['result'][0]['value'][1]):.4f}"

    except Exception as e:
        print(f"Could not fetch Prometheus metrics: {e}")

    return metrics

def get_ngrok_urls():
    """Get public URLs from ngrok"""
    urls = {}

    ports = [("API", 4040), ("Local", 4041), ("Grafana", 4042)]

    for name, port in ports:
        try:
            response = requests.get(f"http://localhost:{port}/api/tunnels", timeout=5)
            if response.status_code == 200:
                data = response.json()
                if data.get('tunnels'):
                    public_url = data['tunnels'][0].get('public_url')
                    if public_url:
                        urls[f"{name} Product"] = public_url
        except:
            pass

    return urls

def main():
    """Main monitoring function"""
    print("=" * 60)
    print(f"ML Products Health Monitor - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 60)
    print()

    # Check all services
    print("Service Status:")
    print("-" * 40)

    all_healthy = True
    for name, url in SERVICES.items():
        is_healthy, status = check_service(name, url)
        if not is_healthy:
            all_healthy = False
        print(f"  {name:<25} {status}")

    print()

    # Get Prometheus metrics if available
    metrics = get_prometheus_metrics()
    if metrics:
        print("Key Metrics:")
        print("-" * 40)
        for key, value in metrics.items():
            print(f"  {key:<25} {value}")
        print()

    # Get ngrok URLs
    urls = get_ngrok_urls()
    if urls:
        print("Public URLs (ngrok):")
        print("-" * 40)
        for name, url in urls.items():
            print(f"  {name}: {url}")
        print()

    # Overall status
    print("=" * 60)
    if all_healthy:
        print("✅ All services are healthy!")
    else:
        print("⚠️ Some services are not healthy. Check the status above.")
    print("=" * 60)

    return 0 if all_healthy else 1

if __name__ == "__main__":
    try:
        while True:
            exit_code = main()
            print("\nPress Ctrl+C to exit, or wait for next check...")
            time.sleep(30)  # Check every 30 seconds
            print("\n" * 2)
    except KeyboardInterrupt:
        print("\nMonitoring stopped.")
        sys.exit(0)
