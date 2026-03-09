#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Install OpenClaw Node as a Windows Service using NSSM.
.DESCRIPTION
    Auto-restart on crash, no CMD window, boot-start without login.
.EXAMPLE
    .\install-node-nssm.ps1 -GatewayHost "ubuntu-gz.tail378315.ts.net" -Port 443 -TLS
#>

param(
    [string]$GatewayHost,
    [int]$Port = 0,
    [switch]$TLS,
    [string]$ServiceName = "OpenClaw Node",
    [int]$RestartDelay = 5000
)

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "   OpenClaw Node NSSM Installer" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# --- Known gateways ---
$gwNames = @(
    "ubuntu-gz (Gaz/Jammy)",
    "ubuntu-ot (OneTable)",
    "ubuntu-shenma (Shenma)",
    "ubuntu-excelia (Excelia)",
    "L4L (Learn4Lead)"
)
$gwHosts = @(
    "ubuntu-gz.tail378315.ts.net",
    "ubuntu-ot.tail378315.ts.net",
    "ubuntu-shenma.tail378315.ts.net",
    "ubuntu-excelia.tail378315.ts.net",
    "aiserver01.tail378315.ts.net"
)

if (-not $GatewayHost) {
    Write-Host "Select gateway to connect to:" -ForegroundColor Yellow
    Write-Host ""
    for ($i = 0; $i -lt $gwNames.Count; $i++) {
        $num = $i + 1
        Write-Host "  [$num] $($gwNames[$i]) - $($gwHosts[$i]):443 [TLS]"
    }
    Write-Host "  [0] Custom (enter manually)"
    Write-Host ""
    $choice = Read-Host "Choose (1-$($gwNames.Count), or 0 for custom)"

    $choiceNum = 0
    if ($choice -match '^\d+$') { $choiceNum = [int]$choice }

    if ($choiceNum -ge 1 -and $choiceNum -le $gwNames.Count) {
        $GatewayHost = $gwHosts[$choiceNum - 1]
        $Port = 443
        $TLS = $true
        Write-Host ""
        Write-Host "Selected: $($gwNames[$choiceNum - 1])" -ForegroundColor Green
    }
    else {
        Write-Host ""
        $GatewayHost = Read-Host "Gateway host (IP or hostname)"
        if (-not $GatewayHost) {
            Write-Host "ERROR: Gateway host is required." -ForegroundColor Red
            exit 1
        }
        $portInput = Read-Host "Port (default: 18789)"
        if ($portInput) { $Port = [int]$portInput } else { $Port = 18789 }
        $tlsInput = Read-Host "Use TLS? (y/N)"
        if ($tlsInput -eq "y" -or $tlsInput -eq "Y") { $TLS = $true }
    }
}

if ($Port -eq 0) { $Port = 18789 }

Write-Host ""

# --- Find NSSM ---
$nssm = $null
$nssmCmd = Get-Command nssm -ErrorAction SilentlyContinue
if ($nssmCmd) { $nssm = $nssmCmd.Source }
if (-not $nssm) {
    $wingetPath = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages"
    $found = Get-ChildItem -Path $wingetPath -Recurse -Filter "nssm.exe" -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match "win64" } | Select-Object -First 1
    if ($found) { $nssm = $found.FullName }
}
if (-not $nssm) {
    Write-Host "ERROR: nssm not found. Install with: winget install nssm" -ForegroundColor Red
    exit 1
}
Write-Host "NSSM: $nssm" -ForegroundColor Green

# --- Find Node.js ---
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeCmd) {
    Write-Host "ERROR: node.exe not found in PATH" -ForegroundColor Red
    exit 1
}
$nodePath = $nodeCmd.Source
Write-Host "Node: $nodePath" -ForegroundColor Green

# --- Find OpenClaw ---
$openclawJs = $null
$searchPaths = @()

try {
    $npmGlobal = (& npm root -g 2>$null)
    if ($npmGlobal) {
        $npmGlobal = $npmGlobal.Trim()
        $searchPaths += (Join-Path $npmGlobal "openclaw\dist\index.js")
    }
} catch {}

$searchPaths += (Join-Path $env:APPDATA "npm\node_modules\openclaw\dist\index.js")
$searchPaths += (Join-Path $env:LOCALAPPDATA "nvm\v22.22.0\node_modules\openclaw\dist\index.js")

foreach ($p in $searchPaths) {
    if (Test-Path $p) {
        $openclawJs = $p
        break
    }
}
if (-not $openclawJs) {
    Write-Host "ERROR: openclaw dist/index.js not found. Searched:" -ForegroundColor Red
    foreach ($p in $searchPaths) { Write-Host "  $p" }
    exit 1
}
Write-Host "OpenClaw: $openclawJs" -ForegroundColor Green

# --- Resolve paths ---
$openclawDir = Join-Path $env:USERPROFILE ".openclaw"
$logOut = Join-Path $openclawDir "node.log"
$logErr = Join-Path $openclawDir "node-error.log"
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

# --- Build args ---
$nodeArgs = "$openclawJs node run --host $GatewayHost --port $Port"
if ($TLS) { $nodeArgs += " --tls" }

# --- Summary ---
Write-Host ""
Write-Host "--- Configuration ---" -ForegroundColor Yellow
Write-Host "Service:    $ServiceName"
$tlsLabel = "plain"
if ($TLS) { $tlsLabel = "TLS" }
Write-Host "Gateway:    ${GatewayHost}:${Port} ($tlsLabel)"
Write-Host "Run as:     $currentUser"
Write-Host "Log (out):  $logOut"
Write-Host "Log (err):  $logErr"
Write-Host "Restart:    ${RestartDelay}ms after crash"
Write-Host "Command:    $nodePath $nodeArgs"
Write-Host ""

$confirm = Read-Host "Proceed? (Y/n)"
if ($confirm -and $confirm -ne "Y" -and $confirm -ne "y") {
    Write-Host "Aborted." -ForegroundColor Yellow
    exit 0
}

# --- Remove old schtasks if exists ---
schtasks /Query /TN $ServiceName 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Removing old scheduled task '$ServiceName'..." -ForegroundColor Yellow
    schtasks /End /TN $ServiceName 2>$null | Out-Null
    schtasks /Delete /F /TN $ServiceName 2>$null | Out-Null
}

# --- Stop existing NSSM service if running ---
$existingStatus = & $nssm status $ServiceName 2>&1
if ("$existingStatus" -match "SERVICE_RUNNING|SERVICE_PAUSED|SERVICE_STOPPED") {
    Write-Host "Stopping existing service..." -ForegroundColor Yellow
    & $nssm stop $ServiceName 2>$null | Out-Null
    & $nssm remove $ServiceName confirm 2>$null | Out-Null
    Start-Sleep -Seconds 2
}

# --- Install ---
Write-Host "Installing NSSM service..." -ForegroundColor Cyan
& $nssm install $ServiceName $nodePath $nodeArgs
& $nssm set $ServiceName AppDirectory $openclawDir
& $nssm set $ServiceName AppRestartDelay $RestartDelay
& $nssm set $ServiceName AppStdout $logOut
& $nssm set $ServiceName AppStderr $logErr
& $nssm set $ServiceName AppEnvironmentExtra "TMPDIR=$env:TEMP"

# Run as current user (preserves node pairing)
$password = Read-Host "Password for $currentUser (blank if none)" -AsSecureString
$plainPwd = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))
& $nssm set $ServiceName ObjectName $currentUser $plainPwd

# --- Start ---
Write-Host "Starting service..." -ForegroundColor Cyan
& $nssm start $ServiceName

Start-Sleep -Seconds 3
$status = & $nssm status $ServiceName
Write-Host ""
Write-Host "=== Result ===" -ForegroundColor Cyan
$statusColor = "Red"
if ("$status" -match "RUNNING") { $statusColor = "Green" }
Write-Host "Status: $status" -ForegroundColor $statusColor
Write-Host ""
Write-Host "Useful commands:" -ForegroundColor Yellow
Write-Host "  nssm status  ""$ServiceName"""
Write-Host "  nssm restart ""$ServiceName"""
Write-Host "  nssm stop    ""$ServiceName"""
Write-Host "  type $logErr"
