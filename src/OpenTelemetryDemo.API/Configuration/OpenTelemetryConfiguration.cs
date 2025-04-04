using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using OpenTelemetry.Metrics;

namespace OpenTelemetryDemo.API.Configuration;

public static class OpenTelemetryConfiguration
{
    public static IServiceCollection AddOpenTelemetryServices(this IServiceCollection services, IConfiguration configuration)
    {
        var openTelemetryConfig = configuration.GetSection("OpenTelemetry");
        var serviceName = openTelemetryConfig["ServiceName"] ?? "OpenTelemetryDemo.API";
        var serviceVersion = openTelemetryConfig["ServiceVersion"] ?? "1.0.0";
        var serviceInstanceId = openTelemetryConfig["ServiceInstanceId"] ?? "instance-1";

        var resourceBuilder = ResourceBuilder.CreateDefault()
            .AddService(serviceName: serviceName, serviceVersion: serviceVersion)
            .AddAttributes(new KeyValuePair<string, object>[]
            {
                new("service.instance.id", serviceInstanceId),
                new("deployment.environment", "Production")
            });

        var otlpEndpoint = new Uri(openTelemetryConfig.GetSection("Exporters:Otlp:Endpoint").Value ?? "http://host.docker.internal:4317");

        services.AddOpenTelemetry()
            .WithTracing(builder =>
            {
                builder
                    .AddSource(serviceName)
                    .SetResourceBuilder(resourceBuilder)
                    .AddOtlpExporter(opts =>
                    {
                        opts.Endpoint = otlpEndpoint;
                    })
                    .AddAspNetCoreInstrumentation()
                    .AddHttpClientInstrumentation();
            })
            .WithMetrics(builder =>
            {
                builder
                    .AddMeter(serviceName)
                    .SetResourceBuilder(resourceBuilder)
                    .AddOtlpExporter(opts =>
                    {
                        opts.Endpoint = otlpEndpoint;
                    })
                    .AddAspNetCoreInstrumentation()
                    .AddHttpClientInstrumentation()
                    .AddRuntimeInstrumentation();
            });

        return services;
    }
} 