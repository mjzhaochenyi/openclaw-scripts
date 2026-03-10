@echo off
setlocal enabledelayedexpansion

:: --- UAC Elevation ---
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo Requesting administrative privileges...

    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "%~s0", "", "", "runas", 1 >> "%temp%\getadmin.vbs"
    echo WScript.Sleep 1000 >> "%temp%\getadmin.vbs"
    echo CreateObject^("WScript.Shell"^).Run "cmd /c exit", 0, true >> "%temp%\getadmin.vbs"

    start "" /wait "%temp%\getadmin.vbs"

    if exist "%temp%\getadmin.vbs" del "%temp%\getadmin.vbs"
    exit
)
if exist "%temp%\getadmin.vbs" del "%temp%\getadmin.vbs"
cd /d "%~dp0"

echo.
echo ========================================
echo    OpenClaw Node NSSM Installer
echo ========================================
echo.

:: --- User Input ---
set "GATEWAY_HOST="
set /p "GATEWAY_HOST=Gateway host (IP or hostname): "
if "%GATEWAY_HOST%"=="" (
    echo ERROR: Gateway host is required.
    goto :fail
)

set "PORT=443"
set /p "PORT=Port (default: 443): "

set "USE_TLS=1"
set "TLS_INPUT="
set /p "TLS_INPUT=Use TLS? (Y/n): "
if /i "%TLS_INPUT%"=="n" set "USE_TLS=0"

set "SERVICE_NAME=OpenClaw Node"
set /p "SERVICE_NAME=Service name (default: OpenClaw Node): "

set "RESTART_DELAY=5000"

:: --- Find NSSM ---
set "NSSM="
where nssm >nul 2>&1
if %errorlevel%==0 (
    for /f "delims=" %%i in ('where nssm') do set "NSSM=%%i"
)
if "%NSSM%"=="" (
    for /f "delims=" %%i in ('dir /s /b "%LOCALAPPDATA%\Microsoft\WinGet\Packages\nssm.exe" 2^>nul ^| findstr /i "win64"') do set "NSSM=%%i"
)
if "%NSSM%"=="" (
    echo ERROR: nssm not found. Install with: winget install nssm
    goto :fail
)
echo NSSM: %NSSM%

:: --- Find Node.js ---
set "NODE_PATH="
where node >nul 2>&1
if %errorlevel%==0 (
    for /f "delims=" %%i in ('where node') do set "NODE_PATH=%%i"
)
if "%NODE_PATH%"=="" (
    echo ERROR: node.exe not found in PATH
    goto :fail
)
echo Node: %NODE_PATH%

:: --- Find OpenClaw ---
set "OPENCLAW_JS="
for /f "delims=" %%i in ('npm root -g 2^>nul') do set "NPM_GLOBAL=%%i"
if defined NPM_GLOBAL (
    if exist "%NPM_GLOBAL%\openclaw\dist\index.js" set "OPENCLAW_JS=%NPM_GLOBAL%\openclaw\dist\index.js"
)
if "%OPENCLAW_JS%"=="" (
    if exist "%APPDATA%\npm\node_modules\openclaw\dist\index.js" set "OPENCLAW_JS=%APPDATA%\npm\node_modules\openclaw\dist\index.js"
)
if "%OPENCLAW_JS%"=="" (
    echo ERROR: openclaw dist/index.js not found. Install with: npm i -g openclaw
    goto :fail
)
echo OpenClaw: %OPENCLAW_JS%

:: --- Resolve paths ---
set "OPENCLAW_DIR=%USERPROFILE%\.openclaw"
set "LOG_OUT=%OPENCLAW_DIR%\node.log"
set "LOG_ERR=%OPENCLAW_DIR%\node-error.log"

:: --- Build args ---
set "NODE_ARGS=%OPENCLAW_JS% node run --host %GATEWAY_HOST% --port %PORT%"
if "%USE_TLS%"=="1" set "NODE_ARGS=%NODE_ARGS% --tls"

:: --- Summary ---
set "TLS_LABEL=plain"
if "%USE_TLS%"=="1" set "TLS_LABEL=TLS"
echo.
echo --- Configuration ---
echo Service:    %SERVICE_NAME%
echo Gateway:    %GATEWAY_HOST%:%PORT% (%TLS_LABEL%)
echo Log (out):  %LOG_OUT%
echo Log (err):  %LOG_ERR%
echo Restart:    %RESTART_DELAY%ms after crash
echo Command:    %NODE_PATH% %NODE_ARGS%
echo.

set "CONFIRM=Y"
set /p "CONFIRM=Proceed? (Y/n): "
if /i "%CONFIRM%"=="n" (
    echo Aborted.
    goto :end
)

:: --- Remove old schtasks if exists ---
schtasks /Query /TN "%SERVICE_NAME%" >nul 2>&1
if %errorlevel%==0 (
    echo Removing old scheduled task '%SERVICE_NAME%'...
    schtasks /End /TN "%SERVICE_NAME%" >nul 2>&1
    schtasks /Delete /F /TN "%SERVICE_NAME%" >nul 2>&1
)

:: --- Stop existing NSSM service if running ---
for /f "delims=" %%s in ('"%NSSM%" status "%SERVICE_NAME%" 2^>^&1') do set "SVC_STATUS=%%s"
echo %SVC_STATUS% | findstr /i "SERVICE_RUNNING SERVICE_PAUSED SERVICE_STOPPED" >nul 2>&1
if %errorlevel%==0 (
    echo Stopping existing service...
    "%NSSM%" stop "%SERVICE_NAME%" >nul 2>&1
    "%NSSM%" remove "%SERVICE_NAME%" confirm >nul 2>&1
    timeout /t 2 /nobreak >nul
)

:: --- Install ---
echo Installing NSSM service...
"%NSSM%" install "%SERVICE_NAME%" "%NODE_PATH%" %NODE_ARGS%
"%NSSM%" set "%SERVICE_NAME%" AppDirectory "%OPENCLAW_DIR%"
"%NSSM%" set "%SERVICE_NAME%" AppRestartDelay %RESTART_DELAY%
"%NSSM%" set "%SERVICE_NAME%" AppStdout "%LOG_OUT%"
"%NSSM%" set "%SERVICE_NAME%" AppStderr "%LOG_ERR%"
"%NSSM%" set "%SERVICE_NAME%" AppEnvironmentExtra "TMPDIR=%TEMP%"

:: Run as current user (preserves node pairing)
set "PASSWORD="
set /p "PASSWORD=Password for current user (blank if none): "
for /f "tokens=*" %%u in ('whoami') do set "CURRENT_USER=%%u"
"%NSSM%" set "%SERVICE_NAME%" ObjectName "%CURRENT_USER%" "%PASSWORD%"

:: --- Start ---
echo Starting service...
"%NSSM%" start "%SERVICE_NAME%"

timeout /t 3 /nobreak >nul
for /f "delims=" %%s in ('"%NSSM%" status "%SERVICE_NAME%"') do set "FINAL_STATUS=%%s"
echo.
echo === Result ===
echo Status: %FINAL_STATUS%
echo.
echo Useful commands:
echo   nssm status  "%SERVICE_NAME%"
echo   nssm restart "%SERVICE_NAME%"
echo   nssm stop    "%SERVICE_NAME%"
echo   type %LOG_ERR%
goto :end

:fail
echo.
echo Installation failed.

:end
echo.
pause
