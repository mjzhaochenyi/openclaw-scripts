#Requires -RunAsAdministrator
<#
.SYNOPSIS
    OpenClaw Node NSSM Installer (PowerShell)
    Installs OpenClaw node as a Windows service via NSSM, running as Local System.
.DESCRIPTION
    - Finds NSSM, Node.js, and OpenClaw automatically
    - Runs as Local System (no password needed, no logon failure)
    - Sets OPENCLAW_HOME to current user's home so pairing token is preserved
    - Grants SYSTEM ACL on .openclaw directory
#>

param(
    [string]$GatewayHost,
    [int]$Port = 443,
    [switch]$NoTLS,
    [string]$ServiceName = "OpenClaw Node",
    [int]$RestartDelay = 5000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "   OpenClaw Node NSSM Installer (PS)" -ForegroundColor Cyan
Write-Host "   (Local System + User Home)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# --- User Input ---
if (-not $GatewayHost) {
    $GatewayHost = Read-Host "Gateway host (IP or hostname)"
    if (-not $GatewayHost) {
        Write-Host "ERROR: Gateway host is required." -ForegroundColor Red
        exit 1
    }
}

$portInput = Read-Host "Port (default: $Port)"
if ($portInput) { $Port = [int]$portInput }

if (-not $NoTLS) {
    $tlsInput = Read-Host "Use TLS? (Y/n)"
    if ($tlsInput -eq 'n') { $NoTLS = $true }
}

$nameInput = Read-Host "Service name (default: $ServiceName)"
if ($nameInput) { $ServiceName = $nameInput }

# --- Find NSSM ---
$nssm = (Get-Command nssm -ErrorAction SilentlyContinue).Source
if (-not $nssm) {
    $nssm = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter "nssm.exe" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "win64" } |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $nssm) {
    Write-Host "ERROR: nssm not found. Install with: winget install nssm" -ForegroundColor Red
    exit 1
}
Write-Host "NSSM: $nssm" -ForegroundColor Green

# --- Find Node.js ---
$nodePath = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $nodePath) {
    Write-Host "ERROR: node.exe not found in PATH" -ForegroundColor Red
    exit 1
}
Write-Host "Node: $nodePath" -ForegroundColor Green

# --- Find OpenClaw ---
$npmGlobal = & npm root -g 2>$null
$openclawJs = $null
if ($npmGlobal -and (Test-Path "$npmGlobal\openclaw\dist\index.js")) {
    $openclawJs = "$npmGlobal\openclaw\dist\index.js"
}
if (-not $openclawJs -and (Test-Path "$env:APPDATA\npm\node_modules\openclaw\dist\index.js")) {
    $openclawJs = "$env:APPDATA\npm\node_modules\openclaw\dist\index.js"
}
if (-not $openclawJs) {
    Write-Host "ERROR: openclaw dist/index.js not found. Install with: npm i -g openclaw" -ForegroundColor Red
    exit 1
}
Write-Host "OpenClaw: $openclawJs" -ForegroundColor Green

# --- Resolve paths ---
$openclawDir = Join-Path $env:USERPROFILE ".openclaw"
$logOut = Join-Path $openclawDir "node.log"
$logErr = Join-Path $openclawDir "node-error.log"

# --- Grant SYSTEM access to .openclaw dir ---
Write-Host "Granting Local System access to $openclawDir..." -ForegroundColor Yellow
icacls $openclawDir /grant "SYSTEM:(OI)(CI)F" /T /Q 2>$null | Out-Null

# --- Build args ---
$nodeArgs = "$openclawJs node run --host $GatewayHost --port $Port"
if (-not $NoTLS) { $nodeArgs += " --tls" }

$tlsLabel = if ($NoTLS) { "plain" } else { "TLS" }

# --- Summary ---
Write-Host ""
Write-Host "--- Configuration ---" -ForegroundColor Cyan
Write-Host "Service:       $ServiceName"
Write-Host "Gateway:       ${GatewayHost}:${Port} ($tlsLabel)"
Write-Host "Run as:        Local System (no password needed)"
Write-Host "OPENCLAW_HOME: $env:USERPROFILE (state dir: $openclawDir)"
Write-Host "Log (out):     $logOut"
Write-Host "Log (err):     $logErr"
Write-Host "Restart:       ${RestartDelay}ms after crash"
Write-Host "Command:       $nodePath $nodeArgs"
Write-Host ""

$confirm = Read-Host "Proceed? (Y/n)"
if ($confirm -eq 'n') {
    Write-Host "Aborted."
    exit 0
}

# --- Remove old scheduled task if exists ---
$task = Get-ScheduledTask -TaskName $ServiceName -ErrorAction SilentlyContinue
if ($task) {
    Write-Host "Removing old scheduled task '$ServiceName'..."
    Stop-ScheduledTask -TaskName $ServiceName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $ServiceName -Confirm:$false -ErrorAction SilentlyContinue
}

# --- Stop existing NSSM service if running ---
$svcStatus = & $nssm status $ServiceName 2>&1
if ($svcStatus -match "SERVICE_RUNNING|SERVICE_PAUSED|SERVICE_STOPPED") {
    Write-Host "Stopping existing service..."
    & $nssm stop $ServiceName 2>$null | Out-Null
    & $nssm remove $ServiceName confirm 2>$null | Out-Null
    Start-Sleep -Seconds 2
}

# --- Install ---
Write-Host "Installing NSSM service..." -ForegroundColor Yellow
& $nssm install $ServiceName $nodePath $nodeArgs
& $nssm set $ServiceName AppDirectory $openclawDir
& $nssm set $ServiceName AppRestartDelay $RestartDelay
& $nssm set $ServiceName AppStdout $logOut
& $nssm set $ServiceName AppStderr $logErr

# --- Run as Local System ---
# OPENCLAW_HOME = user's home dir (NOT .openclaw dir)
# OpenClaw appends /.openclaw internally via resolveStateDir()
& $nssm set $ServiceName AppEnvironmentExtra `
    "OPENCLAW_HOME=$env:USERPROFILE" `
    "HOME=$env:USERPROFILE" `
    "USERPROFILE=$env:USERPROFILE" `
    "TMPDIR=$env:TEMP" `
    "NODE_ENV=production"

& $nssm set $ServiceName ObjectName "LocalSystem"

# --- Start ---
Write-Host "Starting service..." -ForegroundColor Yellow
& $nssm start $ServiceName

Start-Sleep -Seconds 3
$finalStatus = & $nssm status $ServiceName 2>&1

Write-Host ""
Write-Host "=== Result ===" -ForegroundColor Cyan
Write-Host "Status: $finalStatus"
Write-Host "Run as: Local System"
Write-Host "Config: $openclawDir"
Write-Host ""
Write-Host "Useful commands:" -ForegroundColor Gray
Write-Host "  nssm status  `"$ServiceName`""
Write-Host "  nssm restart `"$ServiceName`""
Write-Host "  nssm stop    `"$ServiceName`""
Write-Host "  Get-Content $logErr"
Write-Host ""
Write-Host "NOTE: OPENCLAW_HOME=$env:USERPROFILE" -ForegroundColor Yellow
Write-Host "      OpenClaw resolves state dir as OPENCLAW_HOME/.openclaw" -ForegroundColor Yellow
Write-Host "      ACL granted for SYSTEM to read $openclawDir" -ForegroundColor Yellow
Write-Host ""
Read-Host "Press Enter to exit"
