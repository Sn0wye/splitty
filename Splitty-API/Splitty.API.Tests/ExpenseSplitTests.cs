using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;

namespace Splitty.API.Tests;

[Collection(nameof(ApiCollection))]
public sealed class ExpenseSplitTests
{
    private readonly ApiFactory _factory;

    public ExpenseSplitTests(ApiFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task Create_succeeds_when_splits_sum_to_the_total()
    {
        var (owner, groupId, payerId, peerId) = await SeedGroupWithTwoMembersAsync();

        var response = await owner.CreateExpenseAsync(groupId, Expense(payerId, 20m, Split(payerId, 10m), Split(peerId, 10m)));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(15));
        await _factory.WaitForProcessedAsync(cts.Token);
    }

    [Fact]
    public async Task Create_rejects_splits_that_do_not_sum_to_the_total()
    {
        var (owner, groupId, payerId, peerId) = await SeedGroupWithTwoMembersAsync();

        var response = await owner.CreateExpenseAsync(groupId, Expense(payerId, 100m, Split(payerId, 50m), Split(peerId, 40m)));

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Create_rejects_an_empty_split_collection()
    {
        var (owner, groupId, payerId, _) = await SeedGroupWithTwoMembersAsync();

        var response = await owner.CreateExpenseAsync(groupId, Expense(payerId, 10m));

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Create_rejects_a_request_that_omits_splits()
    {
        var (owner, groupId, payerId, _) = await SeedGroupWithTwoMembersAsync();

        var response = await owner.Http.PostAsync(
            $"/group/{groupId}/expenses",
            new StringContent(
                JsonSerializer.Serialize(new { paidBy = payerId, amount = 10m, description = "Dinner" }),
                Encoding.UTF8,
                "application/json"));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        await ErrorResponseAssertions.ReadErrorAsync(response);
    }

    [Fact]
    public async Task Create_rejects_a_zero_or_negative_split()
    {
        var (owner, groupId, payerId, peerId) = await SeedGroupWithTwoMembersAsync();

        var zero = await owner.CreateExpenseAsync(groupId, Expense(payerId, 10m, Split(payerId, 10m), Split(peerId, 0m)));
        var negative = await owner.CreateExpenseAsync(groupId, Expense(payerId, 10m, Split(payerId, 15m), Split(peerId, -5m)));

        await ErrorResponseAssertions.AssertErrorAsync(zero, HttpStatusCode.BadRequest);
        await ErrorResponseAssertions.AssertErrorAsync(negative, HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Create_rejects_a_zero_or_negative_total()
    {
        var (owner, groupId, payerId, peerId) = await SeedGroupWithTwoMembersAsync();

        var zero = await owner.CreateExpenseAsync(groupId, Expense(payerId, 0m, Split(payerId, 5m), Split(peerId, 5m)));
        var negative = await owner.CreateExpenseAsync(groupId, Expense(payerId, -10m, Split(payerId, 5m), Split(peerId, 5m)));

        await ErrorResponseAssertions.AssertErrorAsync(zero, HttpStatusCode.BadRequest);
        await ErrorResponseAssertions.AssertErrorAsync(negative, HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Edit_rejects_when_resulting_splits_no_longer_sum_to_the_total()
    {
        var (owner, groupId, payerId, peerId) = await SeedGroupWithTwoMembersAsync();
        var expenseId = await CreateValidExpenseAsync(owner, groupId, payerId, peerId);

        var response = await owner.UpdateExpenseAsync(groupId, expenseId, new
        {
            splits = new[] { Split(payerId, 8m), Split(peerId, 8m) }
        });

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Amount_only_edit_is_validated_against_existing_splits()
    {
        var (owner, groupId, payerId, peerId) = await SeedGroupWithTwoMembersAsync();
        var expenseId = await CreateValidExpenseAsync(owner, groupId, payerId, peerId);

        var response = await owner.UpdateExpenseAsync(groupId, expenseId, new { amount = 30m });

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.BadRequest);
    }

    private async Task<(ApiClient Owner, int GroupId, int PayerId, int PeerId)> SeedGroupWithTwoMembersAsync()
    {
        var owner = ApiClient.Create(_factory);
        var ownerUser = await owner.SignInAsync();
        owner = ApiClient.Create(_factory, ownerUser.Token);
        var groupId = await owner.CreateGroupAsync();
        var code = await owner.CreateInviteAsync(groupId);

        var guest = ApiClient.Create(_factory);
        var guestUser = await guest.SignInAsync();
        guest = ApiClient.Create(_factory, guestUser.Token);
        var accept = await guest.AcceptInviteAsync(code);
        accept.EnsureSuccessStatusCode();

        return (owner, groupId, ownerUser.Id, guestUser.Id);
    }

    private async Task<int> CreateValidExpenseAsync(ApiClient owner, int groupId, int payerId, int peerId)
    {
        var response = await owner.CreateExpenseAsync(groupId, Expense(payerId, 20m, Split(payerId, 10m), Split(peerId, 10m)));
        response.EnsureSuccessStatusCode();
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(15));
        await _factory.WaitForProcessedAsync(cts.Token);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>();
        return body.GetProperty("id").GetInt32();
    }

    private static object Expense(int paidBy, decimal amount, params object[] splits) => new
    {
        paidBy,
        amount,
        description = "Dinner",
        splits
    };

    private static object Split(int userId, decimal amount) => new { userId, amount };
}
