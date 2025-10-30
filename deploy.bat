@echo off
REM Deployment Script following rcpaffenroth/DSCS553_example pattern

echo =================================================
echo ML Products Docker Deployment
echo =================================================

REM Check if .env file exists
if not exist .env (
    echo Creating .env file from template...
    copy .env.example .env
    echo Please edit .env file with your HF_TOKEN and NGROK_AUTHTOKEN
    exit /b 1
)

REM Build and start containers
echo Building Docker images...
docker-compose build

echo Starting services...
docker-compose up -d

REM Wait for services to be ready
echo Waiting for services to start...
timeout /t 10 /nobreak >nul

REM Check service status
echo.
echo =================================================
echo Service Status:
echo =================================================
docker-compose ps

echo.
echo =================================================
echo Service URLs:
echo =================================================
echo API Product:       http://localhost:5000
echo API Metrics:       http://localhost:5001/metrics
echo API Node Exporter: http://localhost:5002/metrics
echo.
echo Local Product:       http://localhost:5003
echo Local Metrics:       http://localhost:5004/metrics
echo Local Node Exporter: http://localhost:5005/metrics
echo.
echo Prometheus:    http://localhost:5006
echo Grafana:       http://localhost:5007 (admin/admin)
echo.
echo =================================================
echo To view logs: docker-compose logs -f [service]
echo To stop:      docker-compose down
echo =================================================
pause