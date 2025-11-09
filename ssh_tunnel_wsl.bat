@echo off
REM SSH Tunnel Script using WSL (for SSH key in WSL)

setlocal enabledelayedexpansion

REM Configuration
set VM_HOST=melnibone.wpi.edu
set VM_PORT=2222
set SSH_KEY=~/.ssh/vm

REM Check if username was provided (default to group4)
if "%1"=="" (
    set VM_USER=group4
    echo Using default username: group4
) else (
    set VM_USER=%1
    echo Using custom username: %1
)

echo =========================================
echo WPI VM SSH Tunnel Setup (via WSL)
echo =========================================
echo.
echo VM Host: %VM_HOST%
echo SSH Port: %VM_PORT%
echo Username: %VM_USER%
echo SSH Key: %SSH_KEY% (in WSL)
echo.

REM Check if WSL is available
where wsl >nul 2>&1
if %errorlevel% neq 0 (
    echo Error: WSL is not available. Please install WSL.
    pause
    exit /b 1
)

echo Starting SSH tunnel through WSL...
echo You may be prompted for your SSH key password
echo.

REM Create SSH tunnel using WSL
echo Starting tunnel to forward ports 5000,5003,5006,5007,8000,8001,5002,5005...
wsl ssh -i %SSH_KEY% -N ^
  -L 5000:localhost:5000 ^
  -L 8000:localhost:8000 ^
  -L 5002:localhost:9100 ^
  -L 5003:localhost:5003 ^
  -L 8001:localhost:8001 ^
  -L 5005:localhost:9100 ^
  -L 5006:localhost:5006 ^
  -L 5007:localhost:5007 ^
  -p %VM_PORT% %VM_USER%@%VM_HOST%
