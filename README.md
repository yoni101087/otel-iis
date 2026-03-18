# OpenTelemetry .NET Auto-Instrumentation for IIS + Coralogix

Setup for auto-instrumenting .NET apps running on IIS and shipping traces, metrics, and logs to Coralogix via an OpenTelemetry Collector.

## Files

| File | Purpose |
|------|---------|
| `5-changed.ps1` | Installation script — run once per IIS server |
| `config.yaml` | OpenTelemetry Collector configuration |

## Prerequisites

- Windows Server with IIS installed
- OpenTelemetry Collector running on `localhost:4318` (http/protobuf)
- PowerShell 5.1 (Desktop), run as Administrator

## Usage

### 1. Deploy the Collector

Place `config.yaml` on the server and run the collector with it:

```
otelcol --config config.yaml
```

### 2. Run the Installation Script

```powershell
# Default — uses windows-prod / MyVIP12
.\5-changed.ps1

# Override subsystem per server
.\5-changed.ps1 -CxApplicationName "windows-prod" -CxSubsystemName "MyVIP9"
```

The script will:
- Stop IIS, fix permissions, download and install OTel .NET auto-instrumentation
- Set all required environment variables
- Fix duplicate logger sections in web.config files
- Restart IIS

### 3. Verify

After IIS restarts, trigger requests to the app and check:
- Logs: `E:\otel-logs\`
- Coralogix: traces should appear under the application/subsystem set via params

## Coralogix Routing

The collector routes telemetry dynamically based on resource attributes set by the script:

| Attribute | Set by | Controls |
|-----------|--------|---------|
| `cx.application.name` | `OTEL_RESOURCE_ATTRIBUTES` in script | Application in Coralogix |
| `cx.subsystem.name` | `OTEL_RESOURCE_ATTRIBUTES` in script | Subsystem in Coralogix |

Fallback values (`windows-prod` / `unknown`) apply if the attributes are missing.

## Collector Pipelines

| Pipeline | Receivers | Exporters |
|----------|-----------|-----------|
| traces | otlp | spanmetrics, coralogix |
| metrics | otlp, hostmetrics, prometheus, iis, spanmetrics | coralogix |
| logs | otlp, filelog | coralogix |
| logs/resource_catalog | hostmetrics | coralogix/resource_catalog |
