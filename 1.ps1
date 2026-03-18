# Must be Windows PowerShell 5.1 (Desktop)
$PSVersionTable

# Force TLS 1.2 for GitHub downloads
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$moduleUrl  = "https://github.com/open-telemetry/opentelemetry-dotnet-instrumentation/releases/latest/download/OpenTelemetry.DotNet.Auto.psm1"
$modulePath = Join-Path $env:TEMP "OpenTelemetry.DotNet.Auto.psm1"

Invoke-WebRequest -Uri $moduleUrl -OutFile $modulePath -UseBasicParsing

# If execution policy blocks it (common), do this:
Unblock-File $modulePath
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

Import-Module $modulePath -Force

# sanity check: these should exist now
Get-Command Install-OpenTelemetryCore, Register-OpenTelemetryForIIS

Install-OpenTelemetryCore
Register-OpenTelemetryForIIS   # this does an IIS restart
