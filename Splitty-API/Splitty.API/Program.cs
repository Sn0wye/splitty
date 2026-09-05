using System.Globalization;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Channels;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.RateLimiting;
using System.Threading.RateLimiting;
using Splitty.API;
using Splitty.API.Controllers;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Splitty.API.Middleware;
using Splitty.Background;
using Splitty.DTO.Response;
using Splitty.Infrastructure;
using Splitty.Repository;
using Splitty.Repository.Interfaces;
using Splitty.Seeder;
using Splitty.Service;
using Splitty.Service.Interfaces;
using Scalar.AspNetCore;

// Before CreateBuilder, so the file lands in the environment ahead of the configuration
// providers reading it. `docker compose` supplies the same values through `env_file`.
DotEnvFile.Load(Directory.GetCurrentDirectory());

var builder = WebApplication.CreateBuilder(args);
builder.Logging.AddConsole();

// Add services to the container.
// Learn more about configuring OpenAPI at https://aka.ms/aspnet/openapi
builder.Services.AddOpenApi();
builder.Services.AddControllers(options =>
    {
        if (!builder.Environment.IsDevelopment())
        {
            options.Conventions.Add(new RemoveControllerConvention<DevAuthController>());
        }
    })
    .AddJsonOptions(options =>
    {
        options.JsonSerializerOptions.Converters.Add(
            new JsonStringEnumConverter(JsonNamingPolicy.SnakeCaseLower));
    });
// Secrets arrive as Jwt__SecretKey / Google__ClientId / Google__ClientSecret from .env.
// Failing here beats minting tokens signed with "" or exchanging codes as an empty client.
//
// The signing key is checked in every environment, Development included: an empty key
// throws inside the JwtBearer handler, which runs per request, so skipping the check
// turns a config fault into a 400 on every route rather than a startup crash.
if (string.IsNullOrWhiteSpace(builder.Configuration["Jwt:SecretKey"]))
{
    throw new InvalidOperationException("Configuration 'Jwt:SecretKey' is required.");
}

// Google credentials only matter to the real token exchanger, which the test suite
// replaces with a fake, so these stay scoped to non-Development hosts.
if (!builder.Environment.IsDevelopment())
{
    foreach (var key in new[] { "Google:ClientId", "Google:ClientSecret" })
    {
        if (string.IsNullOrWhiteSpace(builder.Configuration[key]))
        {
            throw new InvalidOperationException($"Configuration '{key}' is required outside Development.");
        }
    }
}

builder.Services.AddDbContext<ApplicationDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection")));

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(opts =>
    {
        opts.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = builder.Configuration["Jwt:Issuer"],
            ValidateAudience = false,
            ValidateLifetime = true,
            ClockSkew = TimeSpan.FromMinutes(5),
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(builder.Configuration["Jwt:SecretKey"]))
        };
        
        opts.Events = new JwtBearerEvents
        {
            OnChallenge = async context =>
            {
                // Suppress the default response
                context.HandleResponse();

                // Write custom 401 response
                context.Response.StatusCode = StatusCodes.Status401Unauthorized;
                context.Response.ContentType = "application/json";
                var response = new ErrorResponse
                {
                    StatusCode = StatusCodes.Status401Unauthorized,
                    Message = "You must be authenticated to access this resource.",
                };
                
                await context.Response.WriteAsJsonAsync(response);
            }
        };
    });
    

// Rate limiting: guards invite-code guessing. Partitioned on the JWT subject claim,
// not User.Identity.Name, which holds the display name here and is not unique.
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;

    options.AddPolicy(RateLimitPolicies.InviteRedemption, context =>
        RateLimitPartition.GetFixedWindowLimiter(
            context.User.FindFirstValue(ClaimTypes.NameIdentifier) ?? "anonymous",
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 10,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0
            }));

    options.OnRejected = async (context, cancellationToken) =>
    {
        if (context.Lease.TryGetMetadata(MetadataName.RetryAfter, out var retryAfter))
        {
            context.HttpContext.Response.Headers.RetryAfter =
                ((int)retryAfter.TotalSeconds).ToString(NumberFormatInfo.InvariantInfo);
        }

        context.HttpContext.Response.StatusCode = StatusCodes.Status429TooManyRequests;
        context.HttpContext.Response.ContentType = "application/json";

        await context.HttpContext.Response.WriteAsJsonAsync(new ErrorResponse
        {
            StatusCode = StatusCodes.Status429TooManyRequests,
            Message = "Too many attempts. Try again later."
        }, cancellationToken);
    };
});

// Repositories
builder.Services.AddScoped<IUserRepository, UserRepository>();
builder.Services.AddScoped<IGroupRepository, GroupRepository>();
builder.Services.AddScoped<IGroupMembershipRepository, GroupMembershipRepository>();
builder.Services.AddScoped<IExpenseRepository, ExpenseRepository>();
builder.Services.AddScoped<IBalanceRepository, BalanceRepository>();
builder.Services.AddScoped<IInviteRepository, InviteRepository>();
builder.Services.AddScoped<IOAuthAccountRepository, OAuthAccountRepository>();

// Services
builder.Services.AddScoped<IAuthService, AuthService>();
builder.Services.AddScoped<IGroupService, GroupService>();
builder.Services.AddScoped<IExpenseService, ExpenseService>();
builder.Services.AddScoped<IBalanceService, BalanceService>();
builder.Services.AddScoped<IInviteService, InviteService>();
builder.Services.AddScoped<IOAuthService, OAuthService>();

// Utils
builder.Services.AddScoped<IJwtTokenIssuer, JwtTokenIssuer>();
builder.Services.AddScoped<IGoogleTokenExchanger, GoogleTokenExchanger>();
builder.Services.AddHttpClient(nameof(GoogleTokenExchanger));

// Background
builder.Services.AddScoped<IBalanceRecomputeQueue, BalanceRecomputeQueue>();
builder.Services.AddSingleton<TransactionProcessedSignal>();
builder.Services.AddHostedService<TransactionBackgroundService>();

builder.Services.AddSingleton<Channel<TransactionRequest>>(
    _ => Channel.CreateUnbounded<TransactionRequest>(new UnboundedChannelOptions
    {
        SingleReader = true,
        AllowSynchronousContinuations = false
    })
    );

var app = builder.Build();

// Apply pending migrations on boot so a deploy against a fresh or lagging database
// self-heals; MigrateAsync is a no-op once the schema is current.
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
    await db.Database.MigrateAsync();
}

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
    app.MapScalarApiReference();
}

// Middleware
app.UseMiddleware<GlobalExceptionHandlingMiddleware>();
app.UseAuthentication();
app.UseAuthorization();
// Must run after UseAuthentication, otherwise the partition key claim is null.
app.UseRateLimiter();

// app.UseHttpsRedirection();

app.MapControllers();

// The seed command runs the host: the recomputation it requests is performed by a hosted
// service, so seeding and returning would queue work no worker is there to do.
if (args.Contains("seed"))
{
    return await SeedCommand.RunAsync(app);
}

app.Run();

return 0;

public partial class Program;