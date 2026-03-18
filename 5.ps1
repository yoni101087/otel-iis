#Requires -RunAsAdministrator

# ================================================
# OpenTelemetry .NET Auto-Instrumentation
# Production Setup Script for IIS + Coralogix
# ================================================

$ErrorActionPreference = "Stop"
$installDir = "C:\Program Files\OpenTelemetry .NET Autoinstrumentation"
$moduleUrl  = "https://github.com/open-telemetry/opentelemetry-dotnet-instrumentation/releases/latest/download/OpenTelemetry.DotNet.Auto.psm1"
$modulePath = Join-Path $env:TEMP "OpenTelemetry.DotNet.Auto.psm1"
$logDir     = "E:\otel-logs"
$inetpub    = "D:\Inetpub"

function Write-Step($n, $msg) { Write-Host "`n[$n] $msg" -ForegroundColor Cyan }
function Write-OK($msg)       { Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Warn($msg)     { Write-Host "    WARN: $msg" -ForegroundColor Yellow }
function Write-Fail($msg)     { Write-Host "    FAIL: $msg" -ForegroundColor Red }

# ─── STEP 1: Pre-flight checks ───────────────────
Write-Step "1/9" "Running pre-flight checks..."

if (-not (Get-Service W3SVC -ErrorAction SilentlyContinue)) {
    Write-Fail "IIS (W3SVC) is not installed. Aborting."
    exit 1
}
Write-OK "IIS is installed"

# Check which port the collector is listening on (4317=grpc, 4318=http/protobuf)
$port4317 = netstat -ano | findstr "4317"
$port4318 = netstat -ano | findstr "4318"

if ($port4317) {
    $otlpProtocol = "grpc"
    $otlpEndpoint = "http://localhost:4317"
    Write-OK "Collector detected on port 4317 - using grpc"
} elseif ($port4318) {
    $otlpProtocol = "http/protobuf"
    $otlpEndpoint = "http://localhost:4318"
    Write-OK "Collector detected on port 4318 - using http/protobuf"
} else {
    Write-Fail "Nothing listening on port 4317 or 4318. Make sure your OTEL Collector is running."
    exit 1
}

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    Write-OK "Created log directory: $logDir"
} else {
    Write-OK "Log directory exists: $logDir"
}

# ─── STEP 2: Stop IIS to release locked DLLs ────
Write-Step "2/9" "Stopping IIS to release locked files..."
iisreset /stop | Out-Null
Stop-Service -Name "W3SVC" -Force -ErrorAction SilentlyContinue
Stop-Service -Name "WAS"   -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
Write-OK "IIS stopped"

# ─── STEP 3: Fix permissions ─────────────────────
Write-Step "3/9" "Fixing permissions on install directory..."
if (Test-Path $installDir) {
    takeown /f $installDir /r /d y | Out-Null
    icacls $installDir /grant "Administrators:F" /t | Out-Null
    Write-OK "Permissions fixed"
} else {
    Write-Warn "Install directory does not exist yet, will be created by installer"
}

# ─── STEP 4: Download OTel module ────────────────
Write-Step "4/9" "Downloading OpenTelemetry module..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (Test-Path $modulePath) { Remove-Item $modulePath -Force }

try {
    Invoke-WebRequest -Uri $moduleUrl -OutFile $modulePath -UseBasicParsing -MaximumRedirection 10
    $size = (Get-Item $modulePath).Length
    if ($size -lt 1000) { throw "File too small, download may have failed" }
    Write-OK "Downloaded OK ($size bytes)"
} catch {
    Write-Fail "Download failed: $_"
    exit 1
}

# ─── STEP 5: Install OTel ────────────────────────
Write-Step "5/9" "Installing OpenTelemetry..."
Unblock-File $modulePath -ErrorAction SilentlyContinue
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Import-Module $modulePath -Force

try {
    Install-OpenTelemetryCore -ErrorAction SilentlyContinue
    Write-OK "Core installed"
} catch {
    Write-Warn "Install-OpenTelemetryCore warning (non-fatal): $_"
}

try {
    Register-OpenTelemetryForIIS
    Write-OK "Registered for IIS"
} catch {
    Write-Fail "Register-OpenTelemetryForIIS failed: $_"
    exit 1
}

# ─── STEP 6: Set environment variables ───────────
Write-Step "6/9" "Setting environment variables..."
$envVars = @{
    "OTEL_SERVICE_NAME"               = "MyAva.Vue"
    "OTEL_EXPORTER_OTLP_ENDPOINT"    = $otlpEndpoint
    "OTEL_EXPORTER_OTLP_PROTOCOL"    = $otlpProtocol
    "OTEL_TRACES_EXPORTER"           = "otlp"
    "OTEL_METRICS_EXPORTER"          = "otlp"
    "OTEL_LOGS_EXPORTER"             = "otlp"
    "OTEL_LOG_LEVEL"                 = "debug"
    "OTEL_DOTNET_AUTO_LOG_DIRECTORY" = $logDir
    "OTEL_RESOURCE_ATTRIBUTES"       = "application.name=my-app,cx.application.name=my-app,cx.subsystem.name=my-subsystem"
    "COMPlus_gcConcurrent"           = "0"
}
foreach ($key in $envVars.Keys) {
    [System.Environment]::SetEnvironmentVariable($key, $envVars[$key], "Machine")
    Write-OK "$key = $($envVars[$key])"
}

# ─── STEP 7: Fix duplicate logger in web.configs ─
Write-Step "7/9" "Scanning web.config files for duplicate logger sections..."
$configs = Get-ChildItem -Path $inetpub -Filter "web.config" -Recurse -ErrorAction SilentlyContinue
foreach ($config in $configs) {
    try {
        $content = Get-Content $config.FullName -Raw
        $fixed   = $content -replace '(<logger[^>]*>.*?</logger>\s*)(<logger[^>]*>.*?</logger>)', '$1'
        if ($fixed -ne $content) {
            Copy-Item $config.FullName "$($config.FullName).bak" -Force
            $fixed | Set-Content $config.FullName -Force
            Write-Warn "Fixed duplicate logger in: $($config.FullName) (backup saved)"
        } else {
            Write-OK "Clean: $($config.FullName)"
        }
    } catch {
        Write-Warn "Could not process $($config.FullName): $_"
    }
}

# ─── STEP 8: Verify everything ───────────────────
Write-Step "8/9" "Verifying installation..."

if (Test-Path $installDir) {
    Write-OK "Install directory exists"
} else {
    Write-Fail "Install directory missing!"
    exit 1
}

$loadedVars = Get-ChildItem Env: | Where-Object { $_.Name -like "OTEL*" }
if ($loadedVars.Count -gt 0) {
    Write-OK "$($loadedVars.Count) OTEL environment variables set"
} else {
    Write-Fail "No OTEL environment variables found!"
    exit 1
}

# ─── STEP 9: Start IIS ───────────────────────────
Write-Step "9/9" "Starting IIS..."
Start-Service -Name "WAS"
Start-Service -Name "W3SVC"
iisreset /start | Out-Null
Write-OK "IIS started"

Write-Host "`n================================================" -ForegroundColor Green
Write-Host "  Done! Next steps:" -ForegroundColor Green
Write-Host "  1. Trigger some requests to your IIS app" -ForegroundColor Green
Write-Host "  2. Check logs at: $logDir" -ForegroundColor Green
Write-Host "  3. Check Coralogix for traces under: MyAva.Vue" -ForegroundColor Green
Write-Host "  4. Protocol used: $otlpProtocol on $otlpEndpoint" -ForegroundColor Green
Write-Host "================================================`n" -ForegroundColor Green