using System.Globalization;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.RateLimiting;
using System.Threading.RateLimiting;
using Splitty.API;
using Splitty.API.Controllers;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.Options;
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
// Secrets arrive as Jwt__*, Google__* and R2__* from .env.
// Failing at startup beats minting tokens signed with "" or exchanging codes as an empty client.
//
// The signing key is validated in every environment, Development included: an empty key
// throws inside the JwtBearer handler, which runs per request, so skipping the check
// turns a config fault into a 400 on every route rather than a startup crash. It is bound
// rather than read here so that configuration added after this point (the test host's
// in-memory settings) is what gets validated and used.
builder.Services.AddOptions<JwtOptions>()
    .BindConfiguration(JwtOptions.SectionName)
    .ValidateDataAnnotations()
    .ValidateOnStart();

// Google and R2 credentials only matter to the real token exchanger and the real avatar
// storage, both of which the test suite replaces with fakes, so they are only required
// outside Development.
var googleOptions = builder.Services.AddOptions<GoogleOptions>()
    .BindConfiguration(GoogleOptions.SectionName);
var r2Options = builder.Services.AddOptions<R2Options>()
    .BindConfiguration(R2Options.SectionName);

if (!builder.Environment.IsDevelopment())
{
    googleOptions.ValidateDataAnnotations().ValidateOnStart();
    r2Options.ValidateDataAnnotations().ValidateOnStart();
}

// Resolved per context rather than read here, for the same reason as the options above.
builder.Services.AddDbContext<ApplicationDbContext>((services, options) =>
{
    var connectionString = services.GetRequiredService<IConfiguration>().GetConnectionString("DefaultConnection");

    if (string.IsNullOrWhiteSpace(connectionString))
    {
        throw new InvalidOperationException("Connection string 'DefaultConnection' is not configured.");
    }

    options.UseNpgsql(connectionString)
        .ConfigureWarnings(w => w.Ignore(RelationalEventId.PendingModelChangesWarning));
});

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(opts =>
    {
        opts.Events = new JwtBearerEvents
        {
            // A JWT is valid until it expires, so a closed account would otherwise keep
            // working on every device. One lookup per request is the revocation: failing
            // here sends the request to OnChallenge, the same JSON 401 as no token at all.
            OnTokenValidated = async context =>
            {
                var userId = context.Principal?.FindFirstValue(ClaimTypes.NameIdentifier);
                var version = context.Principal?.FindFirstValue(JwtTokenIssuer.TokenVersionClaim);
                var users = context.HttpContext.RequestServices.GetRequiredService<IUserRepository>();

                if (!int.TryParse(userId, out var id)
                    || !await users.AcceptsTokenAsync(id, int.TryParse(version, out var v) ? v : 0))
                {
                    context.Fail("This session has ended.");
                }
            },
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

// Configured from the bound options, not builder.Configuration, for the same reason as above.
builder.Services.AddOptions<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme)
    .Configure<IOptions<JwtOptions>>((opts, jwt) =>
    {
        opts.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = jwt.Value.Issuer,
            ValidateAudience = false,
            ValidateLifetime = true,
            ClockSkew = TimeSpan.FromMinutes(5),
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt.Value.SecretKey))
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
builder.Services.AddScoped<IGroupReadModel, GroupReadModel>();
builder.Services.AddScoped<IExpenseService, ExpenseService>();
builder.Services.AddScoped<IBalanceService, BalanceService>();
builder.Services.AddScoped<IInviteService, InviteService>();
builder.Services.AddScoped<IOAuthService, OAuthService>();
builder.Services.AddScoped<IPeopleService, PeopleService>();
builder.Services.AddScoped<IProfileService, ProfileService>();
builder.Services.AddScoped<IGroupStatsService, GroupStatsService>();

// Utils
builder.Services.AddScoped<IJwtTokenIssuer, JwtTokenIssuer>();
builder.Services.AddScoped<IGoogleTokenExchanger, GoogleTokenExchanger>();
builder.Services.AddHttpClient(nameof(GoogleTokenExchanger));
builder.Services.AddSingleton(services =>
    R2AvatarStorage.CreateClient(services.GetRequiredService<IOptions<R2Options>>().Value));
builder.Services.AddScoped<IAvatarStorage, R2AvatarStorage>();
builder.Services.AddScoped<IAvatarResolver, AvatarResolver>();

// Background
builder.Services.AddGroupLedger();
builder.Services.AddSingleton<TransactionProcessedSignal>();
builder.Services.AddHostedService<TransactionBackgroundService>();

var app = builder.Build();

// Apply pending migrations on boot so a deploy against a fresh or lagging database
// self-heals; MigrateAsync is a no-op once the schema is current.
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
    // Before the host starts, so the ledger's startup recovery sees backfilled pending flags.
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