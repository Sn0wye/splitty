using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Splitty.Background;
using Splitty.Infrastructure;
using Splitty.Service.Interfaces;
using Testcontainers.PostgreSql;

namespace Splitty.API.Tests;

public sealed class ApiFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder()
        .WithImage("postgres:16-alpine")
        .Build();

    public async Task InitializeAsync()
    {
        await _postgres.StartAsync();

        using var scope = Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        await db.Database.MigrateAsync();
    }

    async Task IAsyncLifetime.DisposeAsync()
    {
        await DisposeAsync();
        await _postgres.DisposeAsync();
    }

    public async Task WaitForProcessedAsync(CancellationToken cancellationToken = default)
    {
        await Services.GetRequiredService<TransactionProcessedSignal>().WaitAsync(cancellationToken);
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        // DevAuthController and the startup secret checks both key off this.
        builder.UseEnvironment("Development");
        builder.ConfigureAppConfiguration((_, config) =>
        {
            config.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ConnectionStrings:DefaultConnection"] = _postgres.GetConnectionString(),
                ["Jwt:SecretKey"] = "SplittyTestSigningKeyLongEnoughForHmacSha256",
                ["Jwt:Issuer"] = "Splitty"
            });
        });

        // Nothing in the test suite reaches Google.
        builder.ConfigureTestServices(services =>
        {
            services.AddScoped<IGoogleTokenExchanger, FakeGoogleTokenExchanger>();
        });
    }
}

[CollectionDefinition(nameof(ApiCollection))]
public sealed class ApiCollection : ICollectionFixture<ApiFactory>;
