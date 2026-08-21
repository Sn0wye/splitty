using System.Net;
using System.Net.Http.Json;
using System.Text.Json;

namespace Splitty.API.Tests;

[Collection(nameof(ApiCollection))]
public sealed class DevLoginTests
{
    private static readonly JsonSerializerOptions Json = new() { PropertyNameCaseInsensitive = true };

    private readonly ApiFactory _factory;

    public DevLoginTests(ApiFactory factory)
    {
        _factory = factory;
    }

    // The host runs as Development; outside it the controller is never added to the
    // application model, so this route 404s rather than 401s.
    [Fact]
    public async Task Dev_login_mints_a_usable_token_for_an_existing_user()
    {
        var client = ApiClient.Create(_factory);
        var user = await client.SignInAsync(name: "Seeded");

        var response = await client.Http.PostAsJsonAsync("/auth/dev-login", new { email = user.Email });
        response.EnsureSuccessStatusCode();

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(Json);
        Assert.Equal(user.Id, body.GetProperty("user").GetProperty("id").GetInt32());

        var authed = ApiClient.Create(_factory, body.GetProperty("token").GetString());
        var profile = await authed.Http.GetAsync("/auth");

        Assert.Equal(HttpStatusCode.OK, profile.StatusCode);
    }

    [Fact]
    public async Task Dev_login_for_an_unknown_email_is_404()
    {
        var response = await ApiClient.Create(_factory).Http
            .PostAsJsonAsync("/auth/dev-login", new { email = "nobody@splitty.test" });

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }
}
