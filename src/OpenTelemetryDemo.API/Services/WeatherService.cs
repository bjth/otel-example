using OpenTelemetryDemo.API.Models;

namespace OpenTelemetryDemo.API.Services;

public class WeatherService
{
    private static readonly string[] Summaries = new[]
    {
        "Freezing", "Bracing", "Chilly", "Cool", "Mild", "Warm", "Balmy", "Hot", "Sweltering", "Scorching"
    };

    private readonly ITelemetryService _telemetryService;

    public WeatherService(ITelemetryService telemetryService)
    {
        _telemetryService = telemetryService;
    }

    public IEnumerable<WeatherForecast> GetForecast()
    {
        using var activity = _telemetryService.ActivitySource.StartActivity("GetWeatherForecast");
        activity?.SetTag("forecast.days", 5);
        
        var forecast = Enumerable.Range(1, 5).Select(index =>
            new WeatherForecast
            {
                Date = DateOnly.FromDateTime(DateTime.Now.AddDays(index)),
                TemperatureC = Random.Shared.Next(-20, 55),
                Summary = Summaries[Random.Shared.Next(Summaries.Length)]
            })
            .ToArray();

        activity?.SetTag("forecast.temperature.min", forecast.Min(f => f.TemperatureC));
        activity?.SetTag("forecast.temperature.max", forecast.Max(f => f.TemperatureC));
        
        return forecast;
    }
} 