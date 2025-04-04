using Microsoft.AspNetCore.Mvc;
using OpenTelemetryDemo.API.Models;
using OpenTelemetryDemo.API.Services;

namespace OpenTelemetryDemo.API.Controllers;

[ApiController]
[Route("[controller]")]
public class WeatherForecastController : ControllerBase
{
    private readonly WeatherService _weatherService;
    private readonly ILogger<WeatherForecastController> _logger;

    public WeatherForecastController(WeatherService weatherService, ILogger<WeatherForecastController> logger)
    {
        _weatherService = weatherService;
        _logger = logger;
    }

    /// <summary>
    /// Gets a 5-day weather forecast
    /// </summary>
    /// <returns>A list of weather forecasts for the next 5 days</returns>
    /// <response code="200">Returns the list of weather forecasts</response>
    [HttpGet(Name = "GetWeatherForecast")]
    [ProducesResponseType(typeof(IEnumerable<WeatherForecast>), StatusCodes.Status200OK)]
    public IEnumerable<WeatherForecast> Get()
    {
        _logger.LogInformation("Generating weather forecast");
        return _weatherService.GetForecast();
    }
} 