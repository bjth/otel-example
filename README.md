# OpenTelemetry Sample

This project demonstrates how to use OpenTelemetry with .NET to collect metrics, traces, and logs, and send them to Grafana's observability stack (Mimir, Tempo, and Loki).

## Architecture

The project consists of:

- A .NET API that generates telemetry data
- OpenTelemetry Collector that receives and forwards telemetry data
- Grafana Mimir for metrics storage
- Grafana Tempo for trace storage
- Grafana Loki for log storage
- Grafana for visualization

## Getting Started

### Prerequisites

- Docker and Docker Compose
- .NET 9.0 SDK

### Running the Application

1. Start the observability stack:
   ```
   docker-compose up -d
   ```

2. Run the .NET API:
   ```
   cd src/OpenTelemetryDemo.API
   dotnet run
   ```

3. Access the services:
   - Grafana: http://localhost:3000
   - Mimir: http://localhost:9009
   - Tempo: http://localhost:3200
   - Loki: http://localhost:3100

## API Endpoints

- `/telemetry/test/trace` - Generates a test trace
- `/telemetry/test/metric` - Increments a test counter metric
- `/telemetry/test/log` - Generates test log messages
- `/api/metrics/query` - Query metrics from Mimir (for Power BI integration)
- `/api/metrics/test-counter` - Get the test counter metric (for Power BI integration)

## Power BI Integration

This project includes a custom API endpoint that allows Power BI to consume metrics data from Mimir. The endpoints return data in a format that Power BI can easily parse and visualize. 