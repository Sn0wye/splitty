using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Splitty.Infrastructure;

namespace Splitty.API.Tests;

[Collection(nameof(ApiCollection))]
public sealed class RefreshTokenTests
{
    private static readonly JsonSerializerOptions Json = new() { PropertyNameCaseInsensitive = true };

    private readonly ApiFactory _factory;

    public RefreshTokenTests(ApiFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task Sign_in_returns_an_access_token_and_a_refresh_token()
    {
        var response = await ApiClient.Create(_factory).SignInResponseAsync(
            FakeGoogleTokenExchanger.Encode(Guid.NewGuid().ToString("N"), Email(), emailVerified: true, "Ada"));

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(Json);

        Assert.False(string.IsNullOrWhiteSpace(body.GetProperty("token").GetString()));
        Assert.False(string.IsNullOrWhiteSpace(body.GetProperty("refreshToken").GetString()));
    }

    [Fact]
    public async Task Refresh_returns_a_new_pair_whose_access_token_works()
    {
        var client = ApiClient.Create(_factory);
        var user = await client.SignInAsync();

        var pair = await RefreshPairAsync(client, user.RefreshToken);

        Assert.NotEqual(user.RefreshToken, pair.RefreshToken);

        var profile = await ApiClient.Create(_factory, pair.Token).GetProfileAsync();
        Assert.Equal(HttpStatusCode.OK, profile.StatusCode);
    }

    [Fact]
    public async Task Rotated_refresh_token_is_rejected()
    {
        var client = ApiClient.Create(_factory);
        var user = await client.SignInAsync();

        await RefreshPairAsync(client, user.RefreshToken);

        await ErrorResponseAssertions.AssertErrorAsync(
            await client.RefreshAsync(user.RefreshToken), HttpStatusCode.Unauthorized);
    }

    /// The stolen-token case: whoever presents the old token second, the attacker or the
    /// user, the newest token in the family stops working too.
    [Fact]
    public async Task Reusing_a_rotated_token_revokes_the_newest_token_in_its_family()
    {
        var client = ApiClient.Create(_factory);
        var user = await client.SignInAsync();

        var second = await RefreshPairAsync(client, user.RefreshToken);
        var third = await RefreshPairAsync(client, second.RefreshToken);

        Assert.Equal(HttpStatusCode.Unauthorized, (await client.RefreshAsync(user.RefreshToken)).StatusCode);

        await ErrorResponseAssertions.AssertErrorAsync(
            await client.RefreshAsync(third.RefreshToken), HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task Expired_refresh_token_is_rejected()
    {
        var client = ApiClient.Create(_factory);
        var user = await client.SignInAsync();

        await WithDbAsync(db => db.RefreshToken
            .Where(t => t.UserId == user.Id)
            .ExecuteUpdateAsync(s => s.SetProperty(t => t.ExpiresAt, DateTime.UtcNow.AddMinutes(-1))));

        await ErrorResponseAssertions.AssertErrorAsync(
            await client.RefreshAsync(user.RefreshToken), HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task Unknown_refresh_token_is_rejected()
    {
        await ErrorResponseAssertions.AssertErrorAsync(
            await ApiClient.Create(_factory).RefreshAsync("not-a-token-we-issued"), HttpStatusCode.Unauthorized);
    }

    /// Unknown, expired and revoked must be indistinguishable, or the answer tells an
    /// attacker which tokens once existed.
    [Fact]
    public async Task Every_rejection_carries_the_same_message()
    {
        var client = ApiClient.Create(_factory);

        var rotated = await client.SignInAsync();
        await RefreshPairAsync(client, rotated.RefreshToken);

        var expired = await client.SignInAsync();
        await WithDbAsync(db => db.RefreshToken
            .Where(t => t.UserId == expired.Id)
            .ExecuteUpdateAsync(s => s.SetProperty(t => t.ExpiresAt, DateTime.UtcNow.AddMinutes(-1))));

        var messages = new HashSet<string>();
        foreach (var token in new[] { "not-a-token-we-issued", rotated.RefreshToken, expired.RefreshToken })
        {
            var response = await client.RefreshAsync(token);
            messages.Add((await ErrorResponseAssertions.ReadErrorAsync(response)).Message);
        }

        Assert.Single(messages);
    }

    [Fact]
    public async Task Refresh_without_a_token_is_400()
    {
        var response = await ApiClient.Create(_factory).Http.PostAsJsonAsync("/auth/refresh", new { });

        await ErrorResponseAssertions.AssertValidationProblemAsync(response);
    }

    [Fact]
    public async Task Logout_revokes_the_refresh_token()
    {
        var client = ApiClient.Create(_factory);
        var user = await client.SignInAsync();

        var logout = await client.LogoutAsync(user.RefreshToken);
        Assert.Equal(HttpStatusCode.NoContent, logout.StatusCode);

        await ErrorResponseAssertions.AssertErrorAsync(
            await client.RefreshAsync(user.RefreshToken), HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task Logout_with_an_unknown_token_is_still_204()
    {
        var response = await ApiClient.Create(_factory).LogoutAsync("not-a-token-we-issued");

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
    }

    /// Signing out never shows an error, even from a client that has already lost its token.
    [Fact]
    public async Task Logout_without_a_token_is_still_204()
    {
        var http = ApiClient.Create(_factory).Http;

        var emptyObject = await http.PostAsJsonAsync("/auth/logout", new { });
        var noBody = await http.PostAsync("/auth/logout", null);

        Assert.Equal(HttpStatusCode.NoContent, emptyObject.StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, noBody.StatusCode);
    }

    [Fact]
    public async Task Logout_ends_one_sign_in_and_leaves_another_working()
    {
        var client = ApiClient.Create(_factory);
        var email = Email();
        var phone = await client.SignInAsync(email, subject: "sub-two-devices-" + email);
        var tablet = await client.SignInAsync(email, subject: "sub-two-devices-" + email);

        Assert.Equal(phone.Id, tablet.Id);

        await client.LogoutAsync(phone.RefreshToken);

        Assert.Equal(HttpStatusCode.Unauthorized, (await client.RefreshAsync(phone.RefreshToken)).StatusCode);
        await RefreshPairAsync(client, tablet.RefreshToken);
    }

    [Fact]
    public async Task Deleting_a_user_deletes_their_refresh_tokens()
    {
        var client = ApiClient.Create(_factory);
        var user = await client.SignInAsync();
        // A rotated chain, so the cascade has to get past rows that point at each other.
        await RefreshPairAsync(client, user.RefreshToken);
        await client.SignInAsync(user.Email);

        Assert.Equal(3, await WithDbAsync(db => db.RefreshToken.CountAsync(t => t.UserId == user.Id)));

        await WithDbAsync(db => db.User.Where(u => u.Id == user.Id).ExecuteDeleteAsync());

        Assert.Equal(0, await WithDbAsync(db => db.RefreshToken.CountAsync(t => t.UserId == user.Id)));
    }

    /// Deactivation bumps the token version so reactivating does not revive old access
    /// tokens. Refresh tokens need the same guarantee, or a lost phone would mint fresh
    /// access tokens as soon as the user signed in again elsewhere.
    [Fact]
    public async Task Deactivating_ends_every_refresh_token_even_after_reactivating()
    {
        var client = ApiClient.Create(_factory);
        var email = Email();
        var subject = "sub-deactivate-" + email;
        var phone = await client.SignInAsync(email, subject: subject);
        var tablet = await client.SignInAsync(email, subject: subject);

        (await ApiClient.Create(_factory, tablet.Token).DeactivateAccountAsync()).EnsureSuccessStatusCode();

        Assert.Equal(HttpStatusCode.Unauthorized, (await client.RefreshAsync(phone.RefreshToken)).StatusCode);

        var reactivated = await client.SignInAsync(email, subject: subject);

        Assert.Equal(HttpStatusCode.Unauthorized, (await client.RefreshAsync(tablet.RefreshToken)).StatusCode);
        await RefreshPairAsync(client, reactivated.RefreshToken);
    }

    /// Deleting an account keeps the user row as a tombstone, so the cascade never fires.
    [Fact]
    public async Task Deleting_the_account_deletes_its_refresh_tokens()
    {
        var client = ApiClient.Create(_factory);
        var user = await client.SignInAsync();

        (await ApiClient.Create(_factory, user.Token).DeleteAccountAsync()).EnsureSuccessStatusCode();

        Assert.Equal(HttpStatusCode.Unauthorized, (await client.RefreshAsync(user.RefreshToken)).StatusCode);
        Assert.Equal(0, await WithDbAsync(db => db.RefreshToken.CountAsync(t => t.UserId == user.Id)));
    }

    [Fact]
    public async Task Only_a_hash_of_the_refresh_token_is_stored()
    {
        var user = await ApiClient.Create(_factory).SignInAsync();

        var hashes = await WithDbAsync(db => db.RefreshToken
            .Where(t => t.UserId == user.Id)
            .Select(t => t.TokenHash)
            .ToListAsync());

        var hash = Assert.Single(hashes);
        Assert.False(string.IsNullOrWhiteSpace(hash));
        Assert.DoesNotContain(user.RefreshToken, hash);
    }

    private static string Email() => $"{Guid.NewGuid():N}@splitty.test";

    private static async Task<(string Token, string RefreshToken)> RefreshPairAsync(ApiClient client, string refreshToken)
    {
        var body = await client.ReadJsonAsync(await client.RefreshAsync(refreshToken));

        return (body.GetProperty("token").GetString()!, body.GetProperty("refreshToken").GetString()!);
    }

    private async Task<T> WithDbAsync<T>(Func<ApplicationDbContext, Task<T>> query)
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();

        return await query(db);
    }
}
