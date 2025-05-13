using Serilog;
using Serilog.Events;
using Serilog.Sinks.OpenTelemetry;

namespace OpenTelemetryDemo.API.Configuration;

public static class SerilogConfiguration
{
    public static IServiceCollection AddSerilogServices(this IServiceCollection services, IConfiguration configuration)
    {
        var openTelemetryConfig = configuration.GetSection("OpenTelemetry");
        var serviceName = openTelemetryConfig["ServiceName"] ?? "OpenTelemetryDemo.API";
        var serviceVersion = openTelemetryConfig["ServiceVersion"] ?? "1.0.0";
        var serviceInstanceId = openTelemetryConfig["ServiceInstanceId"] ?? Environment.MachineName;
        var otlpEndpoint = new Uri(openTelemetryConfig.GetSection("Exporters:Otlp:Endpoint").Value ?? "http://localhost:4317");

        var loggerConfiguration = new LoggerConfiguration()
            .ReadFrom.Configuration(configuration)
            .Enrich.WithProperty("service", serviceName)
            .Enrich.WithProperty("version", serviceVersion)
            .Enrich.WithProperty("instance", serviceInstanceId)
            .Enrich.WithProperty("environment", Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") ?? "Production");

        // Add OpenTelemetry sink for logs
        loggerConfiguration.WriteTo.OpenTelemetry(options =>
        {
            options.Endpoint = new Uri(otlpEndpoint, "/v1/logs").ToString();
            options.ResourceAttributes = new Dictionary<string, object>
            {
                ["service.name"] = serviceName,
                ["service.version"] = serviceVersion,
                ["service.instance.id"] = serviceInstanceId
            };
            options.Protocol = OtlpProtocol.HttpProtobuf;
        });

        Log.Logger = loggerConfiguration.CreateLogger();

        services.AddLogging(loggingBuilder =>
        {
            loggingBuilder.ClearProviders();
            loggingBuilder.AddSerilog(dispose: true);
        });

        return services;
    }
} 