#!/usr/bin/env python3
"""
Ngrok Setup Script for exposing services globally
This script helps set up ngrok tunnels without using Docker
"""

import subprocess
import json
import time
import os
import sys
import signal
from pathlib import Path

# Global process list for cleanup
processes = []

def signal_handler(sig, frame):
    """Clean up ngrok processes on exit"""
    print("\nStopping ngrok tunnels...")
    for process in processes:
        process.terminate()
    sys.exit(0)

def check_ngrok_installed():
    """Check if ngrok is installed"""
    try:
        result = subprocess.run(['ngrok', 'version'], capture_output=True, text=True)
        if result.returncode == 0:
            print(f"✅ ngrok is installed: {result.stdout.strip()}")
            return True
    except FileNotFoundError:
        pass

    print("❌ ngrok is not installed!")
    print("\nPlease install ngrok:")
    print("  1. Visit https://ngrok.com/download")
    print("  2. Download and install ngrok for your platform")
    print("  3. Sign up for a free account at https://dashboard.ngrok.com/signup")
    print("  4. Run: ngrok config add-authtoken YOUR_TOKEN")
    return False

def check_ngrok_auth():
    """Check if ngrok is authenticated"""
    config_path = Path.home() / '.ngrok2' / 'ngrok.yml'
    if not config_path.exists():
        print("⚠️ ngrok is not configured with an authtoken!")
        print("\nTo configure ngrok:")
        print("  1. Sign up at https://dashboard.ngrok.com/signup")
        print("  2. Get your authtoken from https://dashboard.ngrok.com/auth/your-authtoken")
        print("  3. Run: ngrok config add-authtoken YOUR_TOKEN")
        return False
    print("✅ ngrok is configured")
    return True

def start_ngrok_tunnel(name, port, web_port):
    """Start an ngrok tunnel for a specific service"""
    print(f"Starting ngrok tunnel for {name} on port {port}...")

    cmd = [
        'ngrok', 'http',
        str(port),
        '--log', 'stdout',
        '--log-format', 'json'
    ]

    # Add web interface port
    if web_port:
        cmd.extend(['--web-addr', f'127.0.0.1:{web_port}'])

    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    processes.append(process)

    # Wait for tunnel to be established
    time.sleep(3)

    # Get the public URL from ngrok API
    try:
        import requests
        response = requests.get(f'http://localhost:{web_port}/api/tunnels')
        if response.status_code == 200:
            data = response.json()
            if data.get('tunnels'):
                public_url = data['tunnels'][0].get('public_url')
                if public_url:
                    print(f"  ✅ {name}: {public_url}")
                    return public_url
    except Exception as e:
        print(f"  ⚠️ Could not get URL for {name}: {e}")

    return None

def main():
    """Main function to set up ngrok tunnels"""
    print("=" * 60)
    print("Ngrok Setup for ML Products")
    print("=" * 60)
    print()

    # Check prerequisites
    if not check_ngrok_installed():
        return 1

    if not check_ngrok_auth():
        return 1

    print()
    print("Starting ngrok tunnels...")
    print("-" * 40)

    # Services to expose
    services = [
        ("API Product", 5000, 4040),
        ("Local Product", 5003, 4041),
        ("Grafana", 5007, 4042),
        ("Prometheus", 5006, 4043)
    ]

    urls = {}

    for name, port, web_port in services:
        url = start_ngrok_tunnel(name, port, web_port)
        if url:
            urls[name] = url

    print()
    print("=" * 60)
    print("Public URLs Summary")
    print("=" * 60)

    # Save URLs to file for easy sharing
    with open('ngrok_urls.txt', 'w') as f:
        f.write("Public URLs for ML Products\n")
        f.write("=" * 40 + "\n")
        f.write(f"Generated at: {time.strftime('%Y-%m-%d %H:%M:%S')}\n\n")

        for name, url in urls.items():
            print(f"{name}: {url}")
            f.write(f"{name}: {url}\n")

    print()
    print("URLs saved to ngrok_urls.txt")
    print()
    print("Ngrok web interfaces:")
    print("  API Product: http://localhost:4040")
    print("  Local Product: http://localhost:4041")
    print("  Grafana: http://localhost:4042")
    print("  Prometheus: http://localhost:4043")
    print()
    print("Press Ctrl+C to stop all tunnels")

    # Keep running
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        signal_handler(None, None)

if __name__ == "__main__":
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    sys.exit(main())