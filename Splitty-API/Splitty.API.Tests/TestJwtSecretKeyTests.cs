using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;

namespace Splitty.API.Tests;

public sealed class TestJwtSecretKeyTests
{
    [Theory]
    [InlineData("Development")]
    [InlineData("Staging")]
    [InlineData("Production")]
    public void Host_refuses_the_test_signing_key_outside_Testing(string environment)
    {
        using var factory = new KeyedFactory(environment, HostEnvironments.TestJwtSecretKey);

        var error = Assert.Throws<InvalidOperationException>(() => factory.CreateClient());

        Assert.Contains("test suite's key", error.Message);
    }

    // Startup throws before any other configuration or the database is touched, so this
    // factory needs nothing beyond the environment and the key.
    private sealed class KeyedFactory(string environment, string secretKey) : WebApplicationFactory<Program>
    {
        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            builder.UseEnvironment(environment);
            builder.UseSetting("Jwt:SecretKey", secretKey);
        }
    }
}
