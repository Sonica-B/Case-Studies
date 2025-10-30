"""
Prometheus Metrics Server for Local Product
Serves Prometheus metrics on port 8001
"""
from prometheus_client import start_http_server, REGISTRY
import time
import signal
import sys

def signal_handler(sig, frame):
    """Handle shutdown gracefully"""
    print('\nShutting down metrics server...')
    sys.exit(0)

if __name__ == '__main__':
    # Set up signal handler
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Start HTTP server on port 8001
    port = 8001
    start_http_server(port)
    print(f"Prometheus metrics server (Local) started on port {port}")
    print(f"Metrics available at http://localhost:{port}/metrics")

    # Keep the server running
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("Metrics server stopped")