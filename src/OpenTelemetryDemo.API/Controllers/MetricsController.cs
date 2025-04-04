using Microsoft.AspNetCore.Mvc;
using OpenTelemetryDemo.API.Services;

namespace OpenTelemetryDemo.API.Controllers;

[ApiController]
[Route("api/[controller]")]
public class MetricsController : ControllerBase
{
    private readonly IMimirService _mimirService;
    private readonly ILogger<MetricsController> _logger;

    public MetricsController(IMimirService mimirService, ILogger<MetricsController> logger)
    {
        _mimirService = mimirService;
        _logger = logger;
    }

    [HttpGet("query")]
    public async Task<IActionResult> GetMetrics(
        [FromQuery] string query,
        [FromQuery] DateTime? start = null,
        [FromQuery] DateTime? end = null,
        [FromQuery] string step = "1m")
    {
        try
        {
            start ??= DateTime.UtcNow.AddHours(-1);
            end ??= DateTime.UtcNow;

            var result = await _mimirService.GetMetricsDataAsync(query, start.Value, end.Value, step);
            return Ok(result);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error fetching metrics");
            return StatusCode(500, "Error fetching metrics data");
        }
    }

    [HttpGet("test-counter")]
    public async Task<IActionResult> GetTestCounter(
        [FromQuery] DateTime? start = null,
        [FromQuery] DateTime? end = null,
        [FromQuery] string step = "1m")
    {
        try
        {
            start ??= DateTime.UtcNow.AddHours(-1);
            end ??= DateTime.UtcNow;

            var result = await _mimirService.GetMetricsDataAsync("test_counter_total", start.Value, end.Value, step);
            return Ok(result);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error fetching test counter metrics");
            return StatusCode(500, "Error fetching test counter data");
        }
    }
} 