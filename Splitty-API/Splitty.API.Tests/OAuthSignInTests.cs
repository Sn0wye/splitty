using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Splitty.Infrastructure;

namespace Splitty.API.Tests;

[Collection(nameof(ApiCollection))]
public sealed class OAuthSignInTests
{
    private static readonly JsonSerializerOptions Json = new() { PropertyNameCaseInsensitive = true };

    private readonly ApiFactory _factory;

    public OAuthSignInTests(ApiFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task Unknown_subject_creates_user_and_identity()
    {
        var email = Email();
        var client = ApiClient.Create(_factory);

        var response = await client.SignInResponseAsync(
            FakeGoogleTokenExchanger.Encode("sub-new", email, emailVerified: true, "Ada", "https://pic"));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(Json);
        var userId = body.GetProperty("user").GetProperty("id").GetInt32();

        Assert.Equal("Ada", body.GetProperty("user").GetProperty("name").GetString());
        Assert.Equal("https://pic", body.GetProperty("user").GetProperty("avatarUrl").GetString());
        Assert.False(string.IsNullOrWhiteSpace(body.GetProperty("token").GetString()));

        Assert.Equal(1, await CountAccountsAsync(userId));
    }

    [Fact]
    public async Task Known_subject_signs_in_without_creating_rows()
    {
        var email = Email();
        var code = FakeGoogleTokenExchanger.Encode("sub-returning", email, emailVerified: true, "Ada");
        var client = ApiClient.Create(_factory);

        var first = await client.SignInResponseAsync(code);
        first.EnsureSuccessStatusCode();
        var firstId = (await first.Content.ReadFromJsonAsync<JsonElement>(Json))
            .GetProperty("user").GetProperty("id").GetInt32();

        var second = await client.SignInResponseAsync(code);
        second.EnsureSuccessStatusCode();
        var secondId = (await second.Content.ReadFromJsonAsync<JsonElement>(Json))
            .GetProperty("user").GetProperty("id").GetInt32();

        Assert.Equal(firstId, secondId);
        Assert.Equal(1, await CountAccountsAsync(firstId));
        Assert.Equal(1, await CountUsersAsync(email));
    }

    [Fact]
    public async Task Verified_email_links_a_second_identity_to_one_user()
    {
        var email = Email();
        var client = ApiClient.Create(_factory);

        var first = await client.SignInResponseAsync(
            FakeGoogleTokenExchanger.Encode("sub-first", email, emailVerified: true, "Ada"));
        first.EnsureSuccessStatusCode();
        var userId = (await first.Content.ReadFromJsonAsync<JsonElement>(Json))
            .GetProperty("user").GetProperty("id").GetInt32();

        // Same person, same verified address, a subject the API has never seen.
        var second = await client.SignInResponseAsync(
            FakeGoogleTokenExchanger.Encode("sub-second", email, emailVerified: true, "Ada"));
        second.EnsureSuccessStatusCode();
        var linkedId = (await second.Content.ReadFromJsonAsync<JsonElement>(Json))
            .GetProperty("user").GetProperty("id").GetInt32();

        Assert.Equal(userId, linkedId);
        Assert.Equal(1, await CountUsersAsync(email));
        Assert.Equal(2, await CountAccountsAsync(userId));
    }

    /// The takeover case, and the reason the exchanger is a seam at all: an unverified
    /// address that happens to match an existing user must never reach that account.
    [Fact]
    public async Task Unverified_email_does_not_link_to_an_existing_user()
    {
        var email = Email();
        var client = ApiClient.Create(_factory);

        var first = await client.SignInResponseAsync(
            FakeGoogleTokenExchanger.Encode("sub-owner", email, emailVerified: true, "Ada"));
        first.EnsureSuccessStatusCode();
        var userId = (await first.Content.ReadFromJsonAsync<JsonElement>(Json))
            .GetProperty("user").GetProperty("id").GetInt32();

        var attacker = await client.SignInResponseAsync(
            FakeGoogleTokenExchanger.Encode("sub-attacker", email, emailVerified: false, "Mallory"));

        Assert.NotEqual(HttpStatusCode.OK, attacker.StatusCode);

        // The attacker's subject must not exist at all: not against the victim, and not
        // against any other user either. Asserting only "did not return 200" would pass
        // even if the row had been written.
        Assert.Equal(0, await CountBySubjectAsync("sub-attacker"));
        Assert.Equal(1, await CountAccountsAsync(userId));
        Assert.Equal(1, await CountUsersAsync(email));
    }

    [Fact]
    public async Task Rejected_code_is_401_not_500()
    {
        var response = await ApiClient.Create(_factory)
            .SignInResponseAsync(FakeGoogleTokenExchanger.RejectedCode);

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    private static string Email() => $"{Guid.NewGuid():N}@splitty.test";

    private async Task<int> CountAccountsAsync(int userId)
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();

        return await db.OAuthAccount.CountAsync(a => a.UserId == userId);
    }

    private async Task<int> CountBySubjectAsync(string subject)
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();

        return await db.OAuthAccount.CountAsync(a => a.Subject == subject);
    }

    private async Task<int> CountUsersAsync(string email)
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();

        return await db.User.CountAsync(u => u.Email == email);
    }
}
