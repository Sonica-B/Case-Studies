@echo off
REM SSH Tunnel Script for WPI VM Access (Windows)

setlocal enabledelayedexpansion

REM Configuration
set VM_HOST=melnibone.wpi.edu
set VM_PORT=2222

REM Check if username was provided (default to group4)
if "%1"=="" (
    set VM_USER=group4
    echo Using default username: group4
) else (
    set VM_USER=%1
    echo Using custom username: %1
)

echo =========================================
echo WPI VM SSH Tunnel Setup
echo =========================================
echo.
echo VM Host: %VM_HOST%
echo SSH Port: %VM_PORT%
echo Username: %VM_USER%
echo.

REM Check if SSH is available
where ssh >nul 2>&1
if %errorlevel% neq 0 (
    echo Error: SSH is not available. Please ensure OpenSSH is installed.
    echo You can enable it in Windows Settings under Optional Features.
    pause
    exit /b 1
)

echo Setting up SSH tunnels to WPI VM...
echo You may be prompted for your WPI password
echo.

REM Create SSH tunnel with all ports
echo Starting SSH tunnel...
start "WPI VM SSH Tunnel" ssh -N ^
    -L 5000:localhost:5000 ^
    -L 8000:localhost:8000 ^
    -L 9100:localhost:9100 ^
    -L 5003:localhost:5003 ^
    -L 8001:localhost:8001 ^
    -L 9101:localhost:9101 ^
    -L 5006:localhost:5006 ^
    -L 5007:localhost:5007 ^
    -p %VM_PORT% ^
    %VM_USER%@%VM_HOST%

REM Wait for tunnel to establish
timeout /t 5 /nobreak >nul

echo.
echo =========================================
echo Services should now be accessible at:
echo =========================================
echo.
echo   API Product:         http://localhost:5000
echo   API Metrics:         http://localhost:8000/metrics
echo   API Node Exporter:   http://localhost:9100/metrics
echo   Local Product:       http://localhost:5003
echo   Local Metrics:       http://localhost:8001/metrics
echo   Local Node Exporter: http://localhost:9101/metrics
echo   Prometheus:          http://localhost:5006
echo   Grafana:             http://localhost:5007 (admin/admin)
echo.
echo To stop the tunnel, close the SSH window that opened.
echo.
echo Press any key to test connections...
pause >nul

REM Test connections
echo.
echo Testing service availability...
echo.

REM Test each service
for %%p in (5000 5003 5006 5007) do (
    echo Checking port %%p...
    curl -s -o nul -w "Port %%p: HTTP %%{http_code}\n" http://localhost:%%p
)

echo.
echo Keep this window open to maintain the SSH tunnel.
echo Press any key to exit and close the tunnel...
pause >nul
