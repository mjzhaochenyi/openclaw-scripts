#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Install OpenClaw Node as a Windows Service using NSSM.
.DESCRIPTION
    Replaces the default schtasks-based setup with NSSM for:
    - Auto-restart on crash (5s delay)
    - No CMD window
    - Boot-start (no login required)
.EXAMPLE
    .\install-node-nssm.ps1 -Host "ubuntu-gz.tail378315.ts.net" -Port 443 -TLS
    .\install-node-nssm.ps1 -Host "20.204.251.114" -Port 18789
#>

param(
    [string]$GatewayHost,
    [int]$Port = 0,
    [switch]$TLS,
    [string]$ServiceName = "OpenClaw Node",
    [int]$RestartDelay = 5000
)

Write-Host ""
Write-Host "╔══════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   OpenClaw Node NSSM Installer       ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# --- Known gateways menu ---
$gateways = @(
    @{ Name = "ubuntu-gz (Gaz/Jammy)";    Host = "ubuntu-gz.tail378315.ts.net";      Port = 443; TLS = $true },
    @{ Name = "ubuntu-ot (OneTable)";      Host = "ubuntu-ot.tail378315.ts.net";      Port = 443; TLS = $true },
    @{ Name = "ubuntu-shenma (Shenma)";    Host = "ubuntu-shenma.tail378315.ts.net";  Port = 443; TLS = $true },
    @{ Name = "ubuntu-excelia (Excelia)";   Host = "ubuntu-excelia.tail378315.ts.net"; Port = 443; TLS = $true },
    @{ Name = "L4L (Learn4Lead)";          Host = "aiserver01.tail378315.ts.net";      Port = 443; TLS = $true }
)

if (-not $GatewayHost) {
    Write-Host "Select gateway to connect to:" -ForegroundColor Yellow
    Write-Host ""
    for ($i = 0; $i -lt $gateways.Count; $i++) {
        $g = $gateways[$i]
        $tlsTag = if ($g.TLS) { " [TLS]" } else { "" }
        Write-Host "  [$($i+1)] $($g.Name) — $($g.Host):$($g.Port)$tlsTag"
    }
    Write-Host "  [0] Custom (enter manually)"
    Write-Host ""
    $choice = Read-Host "Choose (1-$($gateways.Count), or 0 for custom)"

    if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $gateways.Count) {
        $selected = $gateways[[int]$choice - 1]
        $GatewayHost = $selected.Host
        $Port = $selected.Port
        if ($selected.TLS) { $TLS = $true }
        Write-Host ""
        Write-Host "Selected: $($selected.Name)" -ForegroundColor Green
    } else {
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
$nssm = (Get-Command nssm -ErrorAction SilentlyContinue).Source
if (-not $nssm) {
    $wingetPath = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages"
    $nssm = Get-ChildItem -Path $wingetPath -Recurse -Filter "nssm.exe" -ErrorAction SilentlyContinue |
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
$openclawPaths = @(
    (Join-Path $env:APPDATA "npm\node_modules\openclaw\dist\index.js"),
    (Join-Path $env:LOCALAPPDATA "nvm\v22.22.0\node_modules\openclaw\dist\index.js")
)
# Also try: npm root -g
try {
    $npmGlobal = (& npm root -g 2>$null).Trim()
    if ($npmGlobal) {
        $openclawPaths = @((Join-Path $npmGlobal "openclaw\dist\index.js")) + $openclawPaths
    }
} catch {}

$openclawJs = $null
foreach ($p in $openclawPaths) {
    if (Test-Path $p) {
        $openclawJs = $p
        break
    }
}
if (-not $openclawJs) {
    Write-Host "ERROR: openclaw dist/index.js not found. Searched:" -ForegroundColor Red
    $openclawPaths | ForEach-Object { Write-Host "  $_" }
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
Write-Host "Gateway:    ${GatewayHost}:${Port} $(if($TLS){'(TLS)'}else{'(plain)'})"
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
$oldTask = schtasks /Query /TN $ServiceName 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "Removing old scheduled task '$ServiceName'..." -ForegroundColor Yellow
    schtasks /End /TN $ServiceName 2>$null
    schtasks /Delete /F /TN $ServiceName 2>$null
}

# --- Stop existing NSSM service if running ---
$existingStatus = & $nssm status $ServiceName 2>&1
if ($existingStatus -match "SERVICE_RUNNING|SERVICE_PAUSED|SERVICE_STOPPED") {
    Write-Host "Stopping existing service..." -ForegroundColor Yellow
    & $nssm stop $ServiceName 2>$null
    & $nssm remove $ServiceName confirm 2>$null
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
Write-Host "Status: $status" -ForegroundColor $(if($status -match "RUNNING"){"Green"}else{"Red"})
Write-Host ""
Write-Host "Useful commands:" -ForegroundColor Yellow
Write-Host "  nssm status  `"$ServiceName`""
Write-Host "  nssm restart `"$ServiceName`""
Write-Host "  nssm stop    `"$ServiceName`""
Write-Host "  type $logErr"
