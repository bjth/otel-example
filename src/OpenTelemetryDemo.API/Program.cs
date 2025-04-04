using OpenTelemetryDemo.API.Configuration;
using OpenTelemetryDemo.API.Services;

var builder = WebApplication.CreateBuilder(args);

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

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.UseDeveloperExceptionPage();
}

app.UseHttpsRedirection();
app.UseAuthorization();
app.MapControllers();

app.Run(); 