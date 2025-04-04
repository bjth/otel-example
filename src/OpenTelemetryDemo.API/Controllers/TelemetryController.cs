using Microsoft.AspNetCore.Mvc;
using OpenTelemetryDemo.API.Services;
using Serilog;
using System.Diagnostics;

namespace OpenTelemetryDemo.API.Controllers;

[ApiController]
[Route("[controller]")]
public class TelemetryController : ControllerBase
{
    private readonly ILogger<TelemetryController> _logger;
    private readonly ITelemetryService _telemetryService;

    public TelemetryController(ILogger<TelemetryController> logger, ITelemetryService telemetryService)
    {
        _logger = logger;
        _telemetryService = telemetryService;
    }

    [HttpGet("test/trace")]
    public IActionResult TestTrace()
    {
        using var activity = _telemetryService.ActivitySource.StartActivity(
            "TestOperation",
            ActivityKind.Internal,
            parentContext: Activity.Current?.Context ?? default);

        activity?.SetTag("test.tag", "test value");
        activity?.SetTag("test.timestamp", DateTime.UtcNow.ToString("o"));
        activity?.SetTag("test.environment", Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") ?? "Production");
        activity?.SetTag("test.method", "GET");
        activity?.SetTag("test.endpoint", "/telemetry/test/trace");

        _logger.LogInformation("Test trace operation executed");
        return Ok("Trace test completed");
    }

    [HttpGet("test/metric")]
    public IActionResult TestMetric()
    {
        _telemetryService.TestCounter.Add(1);
        _logger.LogInformation("Incremented test_counter_total metric");
        return Ok("Metric test completed");
    }

    [HttpGet("test/log")]
    public IActionResult TestLog()
    {
        Log.Information("This is a test log message from Serilog");
        Log.Warning("This is a test warning message from Serilog");
        Log.Error("This is a test error message from Serilog");
        return Ok("Log test completed");
    }

    [HttpGet("test/exception")]
    public IActionResult TestException()
    {
        try
        {
            throw new Exception("This is a test exception");
        }
        catch (Exception ex)
        {
            Log.Error(ex, "An error occurred during the exception test");
            return StatusCode(500, "Exception test completed");
        }
    }
} 