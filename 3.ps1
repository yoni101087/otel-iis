# 1. Ensure temp folder exists
if (-not $env:TEMP) { $env:TEMP = "C:\Windows\Temp" }
$tempDir = $env:TEMP
$moduleName = "OpenTelemetry.DotNet.Auto.psm1"
$modulePath = Join-Path $tempDir $moduleName
$moduleUrl = "https://github.com/open-telemetry/opentelemetry-dotnet-instrumentation/releases/download/v1.9.0/OpenTelemetry.DotNet.Auto.psm1"
Write-Host "`n[1/6] Temp path: $modulePath" -ForegroundColor Cyan
# 2. Set TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Write-Host "[2/6] TLS 1.2 enforced" -ForegroundColor Cyan
# 3. Clean old module file if exists, then download fresh
if (Test-Path $modulePath) {
Remove-Item $modulePath -Force
Write-Host "[3/6] Removed old module file" -ForegroundColor Yellow
}
Write-Host "[3/6] Downloading OpenTelemetry module..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $moduleUrl -OutFile $modulePath -UseBasicParsing -MaximumRedirection 10

#part2
# Verify download
if (-not (Test-Path $modulePath)) {
    Write-Error "Download failed - file not found at $modulePath"
    exit 1
}
$fileSize = (Get-Item $modulePath).Length
Write-Host "[3/6] Downloaded OK — Size: $fileSize bytes" -ForegroundColor Green

# 4. Unblock and set execution policy
Unblock-File $modulePath -ErrorAction SilentlyContinue
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Write-Host "[4/6] Execution policy set to Bypass for this session" -ForegroundColor Cyan

# 5. Import module
Write-Host "[5/6] Importing module..." -ForegroundColor Cyan
Import-Module $modulePath -Force

#part3
# Verify module loaded
$commands = Get-Command -Module OpenTelemetry.DotNet.Auto | Select-Object -ExpandProperty Name
if (-not $commands) {
    Write-Error "Module import failed - no commands found"
    exit 1
}
Write-Host "[5/6] Module loaded. Available commands:" -ForegroundColor Green
$commands | ForEach-Object { Write-Host "       - $_" -ForegroundColor Gray }

# 6. Install and register for IIS
Write-Host "[6/6] Installing OpenTelemetry Core..." -ForegroundColor Cyan
Install-OpenTelemetryCore

Write-Host "[6/6] Registering for IIS..." -ForegroundColor Cyan
Register-OpenTelemetryForIIS

# 7. Restart IIS to apply changes
Write-Host "`n[Done] Restarting IIS..." -ForegroundColor Yellow
iisreset /restart

Write-Host "`n✅ OpenTelemetry successfully installed and registered for IIS`n" -ForegroundColor Green