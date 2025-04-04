using System.Text.Json;
using Microsoft.Extensions.Configuration;

namespace OpenTelemetryDemo.API.Services;

public interface IMimirService
{
    Task<JsonDocument> GetMetricsDataAsync(string query, DateTime start, DateTime end, string step = "1m");
}

public class MimirService : IMimirService
{
    private readonly HttpClient _httpClient;
    private readonly ILogger<MimirService> _logger;
    private readonly string _mimirEndpoint;

    public MimirService(ILogger<MimirService> logger, IConfiguration configuration)
    {
        _httpClient = new HttpClient();
        _logger = logger;
        
        var openTelemetryConfig = configuration.GetSection("OpenTelemetry");
        _mimirEndpoint = openTelemetryConfig.GetSection("Exporters:Mimir:Endpoint").Value 
            ?? throw new InvalidOperationException("Mimir endpoint not configured");
    }

    public async Task<JsonDocument> GetMetricsDataAsync(string query, DateTime start, DateTime end, string step = "1m")
    {
        try
        {
            var url = $"{_mimirEndpoint}/prometheus/api/v1/query_range?query={Uri.EscapeDataString(query)}&start={start.ToUniversalTime():yyyy-MM-ddTHH:mm:ssZ}&end={end.ToUniversalTime():yyyy-MM-ddTHH:mm:ssZ}&step={step}";
            
            _logger.LogInformation("Fetching metrics from Mimir: {Url}", url);
            
            var response = await _httpClient.GetAsync(url);
            response.EnsureSuccessStatusCode();
            
            var content = await response.Content.ReadAsStringAsync();
            return JsonDocument.Parse(content);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error fetching metrics from Mimir");
            throw;
        }
    }
} 