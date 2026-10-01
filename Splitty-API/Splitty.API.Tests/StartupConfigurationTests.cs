using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Options;
using Splitty.Service;

namespace Splitty.API.Tests;

[Collection(nameof(ApiCollection))]
public sealed class StartupConfigurationTests
{
    private readonly ApiFactory _factory;

    public StartupConfigurationTests(ApiFactory factory)
    {
        _factory = factory;
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("too-short-for-hmac-sha256")]
    public void Host_refuses_to_start_without_a_usable_signing_key(string secretKey)
    {
        using var host = WithSettings(new Dictionary<string, string?>
        {
            ["Jwt:SecretKey"] = secretKey
        });

        var error = Assert.Throws<OptionsValidationException>(() => host.CreateClient());

        Assert.Contains(nameof(JwtOptions.SecretKey), error.Message);
    }

    [Theory]
    [InlineData(nameof(GoogleOptions))]
    [InlineData(nameof(R2Options))]
    public void Host_outside_Development_refuses_to_start_without_external_credentials(string optionsType)
    {
        // Blanked explicitly: DotEnvFile would otherwise hand the host a developer's real .env.
        using var host = WithSettings(new Dictionary<string, string?>
        {
            ["Google:ClientId"] = "",
            ["Google:ClientSecret"] = "",
            ["R2:AccountId"] = "",
            ["R2:AccessKeyId"] = "",
            ["R2:SecretAccessKey"] = "",
            ["R2:BucketName"] = "",
            ["R2:PublicBaseUrl"] = ""
        }, environment: "Production");

        var error = Assert.ThrowsAny<Exception>(() => host.CreateClient());

        IEnumerable<Exception> failures = error is AggregateException aggregate ? aggregate.InnerExceptions : [error];
        Assert.Contains(failures, e => e is OptionsValidationException validation && validation.OptionsType.Name == optionsType);
    }

    [Fact]
    public void Development_host_starts_without_external_credentials()
    {
        using var host = WithSettings(new Dictionary<string, string?>
        {
            ["Google:ClientId"] = "",
            ["Google:ClientSecret"] = "",
            ["R2:AccountId"] = "",
            ["R2:PublicBaseUrl"] = ""
        });

        host.CreateClient();
    }

    private WebApplicationFactory<Program> WithSettings(
        Dictionary<string, string?> settings,
        string environment = "Development") =>
        _factory.WithWebHostBuilder(builder =>
        {
            builder.UseEnvironment(environment);
            builder.ConfigureAppConfiguration((_, config) => config.AddInMemoryCollection(settings));
        });
}
