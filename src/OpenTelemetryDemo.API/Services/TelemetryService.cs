using System.Diagnostics;
using System.Diagnostics.Metrics;

namespace OpenTelemetryDemo.API.Services;

public interface ITelemetryService
{
    ActivitySource ActivitySource { get; }
    Meter Meter { get; }
    Counter<long> TestCounter { get; }
}

public class TelemetryService : ITelemetryService, IDisposable
{
    public ActivitySource ActivitySource { get; }
    public Meter Meter { get; }
    public Counter<long> TestCounter { get; }

    public TelemetryService()
    {
        ActivitySource = new ActivitySource("OpenTelemetryDemo.API");
        Meter = new Meter("OpenTelemetryDemo.API", "1.0.0");
        TestCounter = Meter.CreateCounter<long>("test_counter_total", description: "Test counter for OpenTelemetry demo");
    }

    public void Dispose()
    {
        ActivitySource.Dispose();
        Meter.Dispose();
    }
} 