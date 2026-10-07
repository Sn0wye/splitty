using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;

namespace Splitty.API.Tests;

/// <summary>
/// A recurring expense's participants are fixed, and it ends when its payer or anyone in its
/// split leaves, is removed, or deletes their account. Catch-up copies the split without
/// checking membership, so this is what keeps it from billing someone outside the group.
/// </summary>
[Collection(nameof(ApiCollection))]
public sealed class RecurringExpenseMembershipTests : IDisposable
{
    private static readonly JsonSerializerOptions Json = new() { PropertyNameCaseInsensitive = true };

    private static readonly DateTimeOffset Now = new(2030, 1, 15, 12, 0, 0, TimeSpan.Zero);

    private readonly ApiFactory _factory;

    public RecurringExpenseMembershipTests(ApiFactory factory)
    {
        _factory = factory;
        _factory.Clock.Set(Now);
    }

    public void Dispose() => _factory.Clock.Reset();

    [Fact]
    public async Task Someone_who_joins_later_is_not_in_the_added_expenses()
    {
        var group = await GroupFixture.CreateAsync(_factory);
        await CreateWeeklyAsync(group, paidBy: group.OwnerId, group.OwnerId, group.GuestId);
        var third = await ApiClient.Create(_factory).SignInAsync(name: "Third");
        (await ApiClient.Create(_factory, third.Token).AcceptInviteAsync(await group.Owner.CreateInviteAsync(group.Id)))
            .EnsureSuccessStatusCode();

        _factory.Clock.Set(Now.AddDays(7));
        await OpenAsync(group);

        var expenses = await ExpensesAsync(group);
        Assert.Equal(2, expenses.Count);
        Assert.All(expenses, e => Assert.Equal(
            [group.OwnerId, group.GuestId],
            e.GetProperty("splits").EnumerateArray().Select(s => s.GetProperty("userId").GetInt32())));
    }

    [Fact]
    public async Task Leaving_catches_up_first_so_a_due_repeat_still_counts()
    {
        var group = await GroupFixture.CreateAsync(_factory);
        await _factory.DrainProcessedAsync();
        await CreateWeeklyAsync(group, paidBy: group.OwnerId, group.OwnerId, group.GuestId);
        await WorkerHarness.WaitForProcessedAsync(_factory);
        await group.SettleAsync(10m);
        await WorkerHarness.WaitForProcessedAsync(_factory);

        _factory.Clock.Set(Now.AddDays(7));
        var refused = await group.Guest.LeaveGroupAsync(group.Id);

        Assert.Equal(HttpStatusCode.Conflict, refused.StatusCode);
        Assert.Equal(2, (await ExpensesAsync(group)).Count);
    }

    [Fact]
    public async Task Leaving_is_refused_while_balances_are_pending_with_its_own_message()
    {
        var group = await GroupFixture.CreateAsync(_factory);
        using var gate = new RecomputeGate(group.Id);
        await using var gated = _factory.WithGate(gate);
        var owner = ApiClient.Create(gated, group.OwnerToken);
        var guest = ApiClient.Create(gated, group.GuestToken);

        // The owner pays for themselves alone, so the guest owes nothing either way.
        (await owner.CreateExpenseAsync(group.Id, new
        {
            paidBy = group.OwnerId,
            amount = 10m,
            description = "Own lunch",
            splitMode = "equal",
            splits = new[] { new { userId = group.OwnerId, amount = 10m } }
        })).EnsureSuccessStatusCode();
        await gate.WaitForEntryAsync();

        var refused = await guest.LeaveGroupAsync(group.Id);

        Assert.Equal(HttpStatusCode.Conflict, refused.StatusCode);
        // Not the outstanding-balance message: the guest owes nothing.
        Assert.Contains("recalculated", (await ErrorResponseAssertions.ReadErrorAsync(refused)).Message);

        gate.Release();
        await WorkerHarness.WaitForProcessedAsync(gated);

        Assert.Equal(HttpStatusCode.NoContent, (await guest.LeaveGroupAsync(group.Id)).StatusCode);
    }

    [Fact]
    public async Task Leaving_ends_the_recurring_expenses_the_member_shares_in()
    {
        var group = await GroupFixture.CreateAsync(_factory);
        await _factory.DrainProcessedAsync();
        await CreateWeeklyAsync(group, paidBy: group.OwnerId, group.OwnerId, group.GuestId);
        await WorkerHarness.WaitForProcessedAsync(_factory);
        await group.SettleAsync(10m);
        await WorkerHarness.WaitForProcessedAsync(_factory);

        Assert.Equal(HttpStatusCode.NoContent, (await group.Guest.LeaveGroupAsync(group.Id)).StatusCode);

        _factory.Clock.Set(Now.AddDays(21));
        await OpenAsync(group);

        var remaining = Assert.Single(await ExpensesAsync(group));
        Assert.Equal(JsonValueKind.Null, remaining.GetProperty("recurringExpenseId").ValueKind);
        Assert.False(await RecurringExpensesExistAsync(group.Id));
    }

    [Fact]
    public async Task Removing_a_member_ends_the_recurring_expenses_they_pay_for()
    {
        var group = await GroupFixture.CreateAsync(_factory);
        await _factory.DrainProcessedAsync();
        // The guest pays for themselves alone, so they never owe anyone.
        await CreateWeeklyAsync(group, paidBy: group.GuestId, group.GuestId);
        await WorkerHarness.WaitForProcessedAsync(_factory);

        Assert.Equal(HttpStatusCode.NoContent, (await group.Owner.RemoveMemberAsync(group.Id, group.GuestId)).StatusCode);

        _factory.Clock.Set(Now.AddDays(21));
        await OpenAsync(group);

        Assert.Single(await ExpensesAsync(group));
        Assert.False(await RecurringExpensesExistAsync(group.Id));
    }

    [Fact]
    public async Task Deleting_an_account_adds_the_due_repeat_first_then_ends_their_recurring_expenses()
    {
        var group = await GroupFixture.CreateAsync(_factory);
        await _factory.DrainProcessedAsync();
        await CreateWeeklyAsync(group, paidBy: group.OwnerId, group.OwnerId, group.GuestId);
        await CreateWeeklyAsync(group, paidBy: group.GuestId, group.GuestId);
        await WorkerHarness.WaitForProcessedAsync(_factory, count: 2);
        await group.SettleAsync(10m);
        await WorkerHarness.WaitForProcessedAsync(_factory);

        _factory.Clock.Set(Now.AddDays(7));
        Assert.Equal(HttpStatusCode.NoContent, (await group.Guest.DeleteAccountAsync()).StatusCode);
        await WorkerHarness.WaitForProcessedAsync(_factory);

        // Both due repeats were added, and the one the tombstone shares in left it owing,
        // so it keeps its membership to carry that.
        Assert.Equal(4, (await ExpensesAsync(group)).Count);
        Assert.False(await RecurringExpensesExistAsync(group.Id));
        Assert.Equal(10m, (await group.Owner.ReadSummaryAsync(group.Id)).AmountOwedBy(group.OwnerId, group.GuestId));

        _factory.Clock.Set(Now.AddDays(21));
        await OpenAsync(group);

        Assert.Equal(4, (await ExpensesAsync(group)).Count);
    }

    [Fact]
    public async Task Deactivating_leaves_recurring_expenses_running()
    {
        var group = await GroupFixture.CreateAsync(_factory);
        await CreateWeeklyAsync(group, paidBy: group.GuestId, group.OwnerId, group.GuestId);

        (await group.Guest.DeactivateAccountAsync()).EnsureSuccessStatusCode();
        _factory.Clock.Set(Now.AddDays(7));
        await OpenAsync(group);

        Assert.Equal(2, (await ExpensesAsync(group)).Count);
    }

    // Helpers.

    private static async Task CreateWeeklyAsync(GroupFixture group, int paidBy, params int[] participants)
    {
        var response = await group.Owner.CreateExpenseAsync(group.Id, new
        {
            paidBy,
            amount = 10m * participants.Length,
            description = "Rent",
            date = Now.UtcDateTime,
            splitMode = "equal",
            repeat = "weekly",
            timeZone = "UTC",
            splits = participants.Select(userId => new { userId, amount = 10m }).ToArray()
        });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    private static async Task OpenAsync(GroupFixture group) =>
        (await group.Owner.GetGroupAsync(group.Id)).EnsureSuccessStatusCode();

    private static async Task<List<JsonElement>> ExpensesAsync(GroupFixture group)
    {
        var response = await group.Owner.GetExpensesAsync(group.Id);
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<JsonElement>(Json)).EnumerateArray()
            .Where(e => e.GetProperty("type").GetString() == "expense")
            .ToList();
    }

    private Task<bool> RecurringExpensesExistAsync(int groupId) =>
        _factory.UseDbAsync(db => db.RecurringExpense.AnyAsync(r => r.GroupId == groupId));
}
