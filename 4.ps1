#Requires -RunAsAdministrator

# STEP 1 - Stop IIS first to release locked DLLs
Write-Host "`n[1/8] Stopping IIS to release locked files..." -ForegroundColor Cyan
iisreset /stop
Stop-Service -Name "W3SVC" -Force -ErrorAction SilentlyContinue
Stop-Service -Name "WAS" -Force -ErrorAction SilentlyContinue

# STEP 2 - Take ownership and fix permissions
Write-Host "[2/8] Fixing permissions..." -ForegroundColor Cyan
takeown /f "C:\Program Files\OpenTelemetry .NET Autoinstrumentation" /r /d y
icacls "C:\Program Files\OpenTelemetry .NET Autoinstrumentation" /grant Administrators:F /t

# STEP 3 - Download OTel module
Write-Host "[3/8] Downloading OpenTelemetry module..." -ForegroundColor Cyan
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$moduleUrl  = "https://github.com/open-telemetry/opentelemetry-dotnet-instrumentation/releases/latest/download/OpenTelemetry.DotNet.Auto.psm1"
$modulePath = Join-Path $env:TEMP "OpenTelemetry.DotNet.Auto.psm1"
Invoke-WebRequest -Uri $moduleUrl -OutFile $modulePath -UseBasicParsing -MaximumRedirection 10

# STEP 4 - Install OTel
Write-Host "[4/8] Installing OpenTelemetry..." -ForegroundColor Cyan
Unblock-File $modulePath -ErrorAction SilentlyContinue
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Import-Module $modulePath -Force
Install-OpenTelemetryCore -ErrorAction SilentlyContinue
Register-OpenTelemetryForIIS

# STEP 5 - Set environment variables
Write-Host "[5/8] Setting environment variables..." -ForegroundColor Cyan
$envVars = @{
    "OTEL_SERVICE_NAME"                  = "MyAva.Vue"
    "OTEL_EXPORTER_OTLP_ENDPOINT"        = "http://localhost:4317"
    "OTEL_EXPORTER_OTLP_PROTOCOL"        = "grpc"
    "OTEL_TRACES_EXPORTER"               = "otlp"
    "OTEL_METRICS_EXPORTER"              = "otlp"
    "OTEL_LOGS_EXPORTER"                 = "otlp"
    "OTEL_LOG_LEVEL"                     = "debug"
    "OTEL_DOTNET_AUTO_LOG_DIRECTORY"     = "E:\otel-logs"
    "OTEL_RESOURCE_ATTRIBUTES"           = "application.name=my-app,cx.application.name=my-app,cx.subsystem.name=my-subsystem"
    "COMPlus_gcConcurrent"               = "0"
}
foreach ($key in $envVars.Keys) {
    [System.Environment]::SetEnvironmentVariable($key, $envVars[$key], "Machine")
    Write-Host "   SET $key = $($envVars[$key])" -ForegroundColor Gray
}

# STEP 6 - Fix duplicate logger in web.config files
Write-Host "[6/8] Fixing duplicate logger in web.config files..." -ForegroundColor Cyan
$webConfigPaths = Get-ChildItem -Path "D:\Inetpub" -Filter "web.config" -Recurse -ErrorAction SilentlyContinue
foreach ($config in $webConfigPaths) {
    $content = Get-Content $config.FullName -Raw
    $fixed = $content -replace '(<logger[^>]*>.*?</logger>\s*)(<logger[^>]*>.*?</logger>)', '$1'
    if ($fixed -ne $content) {
        Copy-Item $config.FullName "$($config.FullName).bak" -Force
        $fixed | Set-Content $config.FullName -Force
        Write-Host "   FIXED: $($config.FullName)" -ForegroundColor Yellow
    } else {
        Write-Host "   OK: $($config.FullName)" -ForegroundColor Gray
    }
}

# STEP 7 - Verify installation
Write-Host "[7/8] Verifying installation..." -ForegroundColor Cyan
$installDir = "C:\Program Files\OpenTelemetry .NET Autoinstrumentation"
if (Test-Path $installDir) {
    Write-Host "   OK: Install directory exists" -ForegroundColor Green
} else {
    Write-Error "   Install directory not found!"
    exit 1
}
Get-ChildItem Env: | Where-Object { $_.Name -like "OTEL*" } |
    ForEach-Object { Write-Host "   $($_.Name) = $($_.Value)" -ForegroundColor Gray }

# STEP 8 - Start IIS
Write-Host "[8/8] Starting IIS..." -ForegroundColor Cyan
Start-Service -Name "WAS"
Start-Service -Name "W3SVC"
iisreset /start

Write-Host "`n✅ Done! Check logs at E:\otel-logs`n" -ForegroundColor Green