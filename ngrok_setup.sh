#!/bin/bash
# Ngrok Setup Script following deployment pattern

echo "================================================="
echo "Setting up Ngrok tunnels for global access"
echo "================================================="

# Check if ngrok is installed
if ! command -v ngrok &> /dev/null; then
    echo "ngrok is not installed. Please install it first:"
    echo "  https://ngrok.com/download"
    exit 1
fi

# Check if authenticated
ngrok config check > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Please authenticate ngrok first:"
    echo "  ngrok config add-authtoken YOUR_TOKEN"
    exit 1
fi

echo "Starting ngrok tunnels..."

# Start tunnels in background
ngrok http 5000 --log=stdout > ngrok-api.log 2>&1 &
NGROK_API_PID=$!
sleep 2

ngrok http 5003 --log=stdout > ngrok-local.log 2>&1 &
NGROK_LOCAL_PID=$!
sleep 2

ngrok http 5007 --log=stdout > ngrok-grafana.log 2>&1 &
NGROK_GRAFANA_PID=$!
sleep 2

ngrok http 5006 --log=stdout > ngrok-prometheus.log 2>&1 &
NGROK_PROM_PID=$!
sleep 2

echo ""
echo "================================================="
echo "Ngrok tunnels started!"
echo "================================================="
echo "Check the following URLs for public access:"
echo ""
echo "API Product:  Check http://localhost:4040"
echo "Local Product: Run 'ngrok api tunnels' to get URLs"
echo ""
echo "Process IDs:"
echo "  API: $NGROK_API_PID"
echo "  Local: $NGROK_LOCAL_PID"
echo "  Grafana: $NGROK_GRAFANA_PID"
echo "  Prometheus: $NGROK_PROM_PID"
echo ""
echo "To stop tunnels:"
echo "  kill $NGROK_API_PID $NGROK_LOCAL_PID $NGROK_GRAFANA_PID $NGROK_PROM_PID"
echo "================================================="