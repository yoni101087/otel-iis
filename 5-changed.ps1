#Requires -RunAsAdministrator

# ================================================
# OpenTelemetry .NET Auto-Instrumentation
# Production Setup Script for IIS + Coralogix
# ================================================

$ErrorActionPreference = "Stop"
$installDir = "C:\Program Files\OpenTelemetry .NET Autoinstrumentation"
$moduleUrl  = "https://github.com/open-telemetry/opentelemetry-dotnet-instrumentation/releases/latest/download/OpenTelemetry.DotNet.Auto.psm1"
$modulePath = "C:\Temp\OpenTelemetry.DotNet.Auto.psm1"
$logDir     = "E:\otel-logs"
$inetpub    = "D:\Inetpub"

# Fixed to port 4318 (http/protobuf) - CRITICAL: Must include /v1/traces path
$otlpProtocol = "http/protobuf"
$otlpEndpoint = "http://localhost:4318"
$otlpTracesEndpoint = "http://localhost:4318/v1/traces"
$otlpMetricsEndpoint = "http://localhost:4318/v1/metrics"
$otlpLogsEndpoint = "http://localhost:4318/v1/logs"

function Write-Step($n, $msg) { Write-Host "`n[$n] $msg" -ForegroundColor Cyan }
function Write-OK($msg)       { Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Warn($msg)     { Write-Host "    WARN: $msg" -ForegroundColor Yellow }
function Write-Fail($msg)     { Write-Host "    FAIL: $msg" -ForegroundColor Red }

# ─── STEP 1: Pre-flight checks ───────────────────
Write-Step "1/10" "Running pre-flight checks..."

if (-not (Get-Service W3SVC -ErrorAction SilentlyContinue)) {
    Write-Fail "IIS (W3SVC) is not installed. Aborting."
    exit 1
}
Write-OK "IIS is installed"

# Check if collector is listening on port 4318
$port4318 = netstat -ano | findstr ":4318"

if ($port4318) {
    Write-OK "Collector detected on port 4318 - using http/protobuf"
} else {
    Write-Warn "Nothing listening on port 4318. Make sure your OTEL Collector is running on http://localhost:4318"
    $continue = Read-Host "Continue anyway? (y/n)"
    if ($continue -ne 'y') {
        exit 1
    }
}

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    Write-OK "Created log directory: $logDir"
} else {
    Write-OK "Log directory exists: $logDir"
}

# ─── STEP 2: Clean previous installation ─────────
Write-Step "2/10" "Cleaning previous installation..."

# Remove old environment variables that might conflict
$oldVars = @(
    "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT",
    "OTEL_EXPORTER_OTLP_METRICS_ENDPOINT", 
    "OTEL_EXPORTER_OTLP_LOGS_ENDPOINT"
)
foreach ($varName in $oldVars) {
    [System.Environment]::SetEnvironmentVariable($varName, $null, "Machine")
    [System.Environment]::SetEnvironmentVariable($varName, $null, "Process")
}
Write-OK "Cleaned old environment variables"

# ─── STEP 3: Stop IIS to release locked DLLs ────
Write-Step "3/10" "Stopping IIS to release locked files..."
iisreset /stop | Out-Null
Stop-Service -Name "W3SVC" -Force -ErrorAction SilentlyContinue
Stop-Service -Name "WAS"   -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
Write-OK "IIS stopped"

# ─── STEP 4: Fix permissions ─────────────────────
Write-Step "4/10" "Fixing permissions on install directory..."
if (Test-Path $installDir) {
    takeown /f $installDir /r /d y | Out-Null
    icacls $installDir /grant "Administrators:F" /t | Out-Null
    Write-OK "Permissions fixed"
} else {
    Write-Warn "Install directory does not exist yet, will be created by installer"
}

# ─── STEP 5: Download OTel module ────────────────
Write-Step "5/10" "Downloading OpenTelemetry module..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not (Test-Path "C:\Temp")) {
    New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null
}

if (Test-Path $modulePath) { 
    Remove-Item $modulePath -Force -ErrorAction SilentlyContinue
}

try {
    Invoke-WebRequest -Uri $moduleUrl -OutFile $modulePath -UseBasicParsing -MaximumRedirection 10
    $size = (Get-Item $modulePath).Length
    if ($size -lt 1000) { throw "File too small, download may have failed" }
    Write-OK "Downloaded OK ($size bytes) to $modulePath"
} catch {
    Write-Fail "Download failed: $_"
    exit 1
}

# ─── STEP 6: Install OTel ────────────────────────
Write-Step "6/10" "Installing OpenTelemetry..."
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

# ─── STEP 7: Set environment variables ───────────
Write-Step "7/10" "Setting environment variables..."
$envVars = @{
    # Service identification
    "OTEL_SERVICE_NAME"               = "MyAva.Vue"
    
    # Base OTLP endpoint (without /v1/traces path)
    "OTEL_EXPORTER_OTLP_ENDPOINT"    = $otlpEndpoint
    
    # Specific endpoints with full paths (these take precedence)
    "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT"  = $otlpTracesEndpoint
    "OTEL_EXPORTER_OTLP_METRICS_ENDPOINT" = $otlpMetricsEndpoint
    "OTEL_EXPORTER_OTLP_LOGS_ENDPOINT"    = $otlpLogsEndpoint
    
    # Protocol MUST be http/protobuf for port 4318
    "OTEL_EXPORTER_OTLP_PROTOCOL"    = $otlpProtocol
    
    # Exporters
    "OTEL_TRACES_EXPORTER"           = "otlp"
    "OTEL_METRICS_EXPORTER"          = "otlp"
    "OTEL_LOGS_EXPORTER"             = "otlp"
    
    # Logging
    "OTEL_LOG_LEVEL"                 = "debug"
    "OTEL_DOTNET_AUTO_LOG_DIRECTORY" = $logDir
    
    # Resource attributes for Coralogix
    "OTEL_RESOURCE_ATTRIBUTES"       = "application.name=my-app,cx.application.name=my-app,cx.subsystem.name=my-subsystem"
    
    # Performance
    "COMPlus_gcConcurrent"           = "0"
}

foreach ($key in $envVars.Keys) {
    [System.Environment]::SetEnvironmentVariable($key, $envVars[$key], "Machine")
    Write-OK "$key = $($envVars[$key])"
}

# ─── STEP 8: Fix duplicate logger in web.configs ─
Write-Step "8/10" "Scanning web.config files for duplicate logger sections..."
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

# ─── STEP 9: Verify everything ───────────────────
Write-Step "9/10" "Verifying installation..."

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

# Verify correct endpoint configuration
$tracesEndpoint = [System.Environment]::GetEnvironmentVariable("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT", "Machine")
if ($tracesEndpoint -like "*:4318*") {
    Write-OK "Traces endpoint correctly configured: $tracesEndpoint"
} else {
    Write-Warn "Traces endpoint may be incorrect: $tracesEndpoint"
}

# ─── STEP 10: Start IIS ───────────────────────────
Write-Step "10/10" "Starting IIS..."
Start-Service -Name "WAS"
Start-Service -Name "W3SVC"
iisreset /start | Out-Null
Write-OK "IIS started"

Write-Host "`n================================================" -ForegroundColor Green
Write-Host "  Done! Configuration Summary:" -ForegroundColor Green
Write-Host "  - Service Name: MyAva.Vue" -ForegroundColor Green
Write-Host "  - Protocol: http/protobuf (NOT grpc)" -ForegroundColor Green  
Write-Host "  - Traces Endpoint: $otlpTracesEndpoint" -ForegroundColor Green
Write-Host "  - Metrics Endpoint: $otlpMetricsEndpoint" -ForegroundColor Green
Write-Host "  - Logs Endpoint: $otlpLogsEndpoint" -ForegroundColor Green
Write-Host "  - Log Directory: $logDir" -ForegroundColor Green
Write-Host "`n  Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Trigger requests to your IIS app" -ForegroundColor Yellow
Write-Host "  2. Check logs: $logDir" -ForegroundColor Yellow
Write-Host "  3. Verify NO errors about port 4317" -ForegroundColor Yellow
Write-Host "  4. Check Coralogix for traces" -ForegroundColor Yellow
Write-Host "================================================`n" -ForegroundColor Green