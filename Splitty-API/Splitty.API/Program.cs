using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Channels;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using Splitty.API.Middleware;
using Splitty.Background;
using Splitty.DTO.Response;
using Splitty.Infrastructure;
using Splitty.Infrastructure.Interfaces;
using Splitty.Repository;
using Splitty.Repository.Interfaces;
using Splitty.Seeder;
using Splitty.Service;
using Splitty.Service.Interfaces;

var builder = WebApplication.CreateBuilder(args);
builder.Logging.AddConsole();

// Add services to the container.
// Learn more about configuring OpenAPI at https://aka.ms/aspnet/openapi
builder.Services.AddOpenApi();
builder.Services.AddControllers()
    .AddJsonOptions(options =>
    {
        options.JsonSerializerOptions.Converters.Add(
            new JsonStringEnumConverter(JsonNamingPolicy.SnakeCaseLower));
    });
builder.Services.AddDbContext<ApplicationDbContext>();

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
    

// Repositories
builder.Services.AddScoped<IUserRepository, UserRepository>();
builder.Services.AddScoped<IGroupRepository, GroupRepository>();
builder.Services.AddScoped<IGroupMembershipRepository, GroupMembershipRepository>();
builder.Services.AddScoped<IExpenseRepository, ExpenseRepository>();
builder.Services.AddScoped<IBalanceRepository, BalanceRepository>();

// Services
builder.Services.AddScoped<IAuthService, AuthService>();
builder.Services.AddScoped<IGroupService, GroupService>();
builder.Services.AddScoped<IExpenseService, ExpenseService>();
builder.Services.AddScoped<IBalanceService, BalanceService>();

// Utils
builder.Services.AddScoped<IPasswordHasher, PasswordHasher>();

// Background
builder.Services.AddHostedService<TransactionBackgroundService>();

builder.Services.AddSingleton<Channel<TransactionRequest>>(
    _ => Channel.CreateUnbounded<TransactionRequest>(new UnboundedChannelOptions
    {
        SingleReader = true,
        AllowSynchronousContinuations = false
    })
    );

var app = builder.Build();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

// Middleware
app.UseMiddleware<GlobalExceptionHandlingMiddleware>();
app.UseAuthentication();
app.UseAuthorization();

// app.UseHttpsRedirection();

app.MapControllers();

if (args.Contains("seed"))
{
    using var scope = app.Services.CreateScope();
    var dbContext = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
    DatabaseSeeder.Seed(dbContext);
    return;
}

app.Run();