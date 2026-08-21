using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc.Testing;

namespace Splitty.API.Tests;

public sealed class ApiClient
{
    private static readonly JsonSerializerOptions Json = new()
    {
        PropertyNameCaseInsensitive = true
    };

    private readonly HttpClient _http;

    public ApiClient(HttpClient http)
    {
        _http = http;
    }

    public static ApiClient Create(WebApplicationFactory<Program> factory, string? token = null)
    {
        var http = factory.CreateClient();
        if (token is not null)
        {
            http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        }

        return new ApiClient(http);
    }

    public HttpClient Http => _http;

    /// Signs in through the real `/oauth/google` route against the fake exchanger, so
    /// tests exercise the same path the app does.
    public async Task<SignedInUser> SignInAsync(string? email = null, string name = "Ada", string? subject = null)
    {
        email ??= $"{Guid.NewGuid():N}@splitty.test";
        subject ??= Guid.NewGuid().ToString("N");

        var response = await SignInResponseAsync(
            FakeGoogleTokenExchanger.Encode(subject, email, emailVerified: true, name));
        response.EnsureSuccessStatusCode();

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(Json);
        return new SignedInUser(
            body.GetProperty("user").GetProperty("id").GetInt32(),
            name,
            email,
            body.GetProperty("token").GetString()!);
    }

    public Task<HttpResponseMessage> SignInResponseAsync(string authCode) =>
        _http.PostAsJsonAsync("/oauth/google", new { authCode });

    public async Task<int> CreateGroupAsync(string name = "Trip")
    {
        var response = await _http.PostAsJsonAsync("/group", new { name, description = "test" });
        response.EnsureSuccessStatusCode();
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(Json);
        return body.GetProperty("id").GetInt32();
    }

    public async Task<string> CreateInviteAsync(int groupId)
    {
        var response = await _http.PostAsJsonAsync($"/group/{groupId}/invites", new { });
        response.EnsureSuccessStatusCode();
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(Json);
        return body.GetProperty("code").GetString()!;
    }

    public Task<HttpResponseMessage> GetGroupAsync(int groupId) =>
        _http.GetAsync($"/group/{groupId}");

    public Task<HttpResponseMessage> AcceptInviteAsync(string code) =>
        _http.PostAsync($"/invite/{code}/accept", null);

    public Task<HttpResponseMessage> CreateExpenseAsync(int groupId, object body) =>
        _http.PostAsJsonAsync($"/group/{groupId}/expenses", body);

    public Task<HttpResponseMessage> UpdateExpenseAsync(int groupId, int expenseId, object body) =>
        _http.PutAsJsonAsync($"/group/{groupId}/expenses/{expenseId}", body);

    public Task<HttpResponseMessage> RequestSummaryRefreshAsync(int groupId) =>
        _http.PostAsync($"/group/{groupId}/expenses/summary", null);

    public Task<HttpResponseMessage> GetSummaryAsync(int groupId) =>
        _http.GetAsync($"/group/{groupId}/expenses/summary");

    public Task<HttpResponseMessage> SettleUpAsync(int groupId, object body) =>
        _http.PostAsJsonAsync($"/group/{groupId}/settle", body);

    public async Task<BalanceSummary> ReadSummaryAsync(int groupId)
    {
        var response = await GetSummaryAsync(groupId);
        response.EnsureSuccessStatusCode();

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(Json);
        var balances = body.GetProperty("balances")
            .EnumerateArray()
            .Select(b => new BalanceEntry(
                b.GetProperty("userId").GetInt32(),
                b.GetProperty("peerId").GetInt32(),
                b.GetProperty("amount").GetDecimal()))
            .ToList();

        return new BalanceSummary(balances, body.GetProperty("balancesPending").GetBoolean());
    }
}

public readonly record struct SignedInUser(int Id, string Name, string Email, string Token);

public sealed record BalanceSummary(IReadOnlyList<BalanceEntry> Balances, bool BalancesPending)
{
    public decimal AmountOwedBy(int userId, int peerId) =>
        Balances.Single(b => b.UserId == userId && b.PeerId == peerId).Amount;
}

public readonly record struct BalanceEntry(int UserId, int PeerId, decimal Amount);
