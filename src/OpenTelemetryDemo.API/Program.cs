using OpenTelemetryDemo.API.Configuration;
using OpenTelemetryDemo.API.Services;
using System.Diagnostics.Tracing;

var builder = WebApplication.CreateBuilder(args);

// --- Removed internal diagnostics setup ---

// Add services to the container.
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();

// Configure OpenAPI
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.WriteIndented = true;
});

// Add OpenTelemetry services
builder.Services.AddOpenTelemetryServices(builder.Configuration);

// Add Serilog services
builder.Services.AddSerilogServices(builder.Configuration);

// Add TelemetryService
builder.Services.AddSingleton<ITelemetryService, TelemetryService>();

// Add WeatherService
builder.Services.AddScoped<WeatherService>();

// Add MimirService
builder.Services.AddHttpClient();
builder.Services.AddScoped<IMimirService, MimirService>();

var app = builder.Build();

// --- Setup OpenTelemetry Event Listener using ILogger ---
// Get logger factory from the built app's services
var loggerFactory = app.Services.GetRequiredService<ILoggerFactory>();
// Create and hold a reference to the listener (using ensures it's disposed)
// Log events under the category "OpenTelemetryDiagnostics"
using var telemetryListener = new OpenTelemetryEventListener(loggerFactory.CreateLogger("OpenTelemetryDiagnostics"));
// ------------------------------------------------------

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.UseDeveloperExceptionPage();
}

app.UseHttpsRedirection();
app.UseAuthorization();
app.MapControllers();

app.Run();

// Listener class that uses ILogger
internal sealed class OpenTelemetryEventListener : EventListener
{
    private readonly ILogger _logger;

    // Define the desired event level (e.g., Informational, Verbose)
    private readonly EventLevel _level = EventLevel.Informational;

    public OpenTelemetryEventListener(ILogger logger)
    {
        _logger = logger;
    }

    protected override void OnEventSourceCreated(EventSource eventSource)
    {
        // Only enable events from OpenTelemetry sources
        if (eventSource.Name.StartsWith("OpenTelemetry"))
        {
            EnableEvents(eventSource, _level, EventKeywords.All);
        }
    }

    protected override void OnEventWritten(EventWrittenEventArgs eventData)
    {
        if (!_logger.IsEnabled((LogLevel)eventData.Level)) // Check if the logger will actually log this level
        {
            return;
        }

        // Format the message using payload
        object[]? payload = eventData.Payload?.ToArray();
        string? message = eventData.Message;
        string formattedMessage = message != null && payload != null ? string.Format(message, payload) : (message ?? "(No message)");

        // Log using ILogger, mapping EventLevel to LogLevel
        _logger.Log((LogLevel)eventData.Level, "[{EventSourceName}] {Message}", eventData.EventSource.Name, formattedMessage);
    }
} 