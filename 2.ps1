$env:TEMP
$env:TMP

# If both are empty, set a temp folder:
if (-not $env:TEMP) { $env:TEMP = "C:\Windows\Temp" }

$moduleUrl  = "https://github.com/open-telemetry/opentelemetry-dotnet-instrumentation/releases/latest/download/OpenTelemetry.DotNet.Auto.psm1"
$modulePath = Join-Path $env:TEMP "OpenTelemetry.DotNet.Auto.psm1"

$modulePath

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Invoke-WebRequest -Uri $moduleUrl -OutFile $modulePath -UseBasicParsing -MaximumRedirection 10

Test-Path $modulePath
(Get-Item $modulePath).Length
Get-Content $modulePath -TotalCount 5


Unblock-File $modulePath -ErrorAction SilentlyContinue
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

Import-Module "OpenTelemetry.DotNet.Auto.psm1"
#Import-Module $modulePath -Force -Verbose

#Get-Command -Module OpenTelemetry.DotNet.Auto | Select-Object Name

Install-OpenTelemetryCore
Register-OpenTelemetryForIIS

