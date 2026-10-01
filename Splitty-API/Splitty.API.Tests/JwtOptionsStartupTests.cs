using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Options;
using Splitty.Service;

namespace Splitty.API.Tests;

[Collection(nameof(ApiCollection))]
public sealed class JwtOptionsStartupTests
{
    private readonly ApiFactory _factory;

    public JwtOptionsStartupTests(ApiFactory factory)
    {
        _factory = factory;
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("too-short-for-hmac-sha256")]
    public void Host_refuses_to_start_without_a_usable_signing_key(string secretKey)
    {
        using var host = _factory.WithWebHostBuilder(builder =>
            builder.ConfigureAppConfiguration((_, config) =>
                config.AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["Jwt:SecretKey"] = secretKey
                })));

        var error = Assert.Throws<OptionsValidationException>(() => host.CreateClient());

        Assert.Contains(nameof(JwtOptions.SecretKey), error.Message);
    }
}
