using System.Net;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Splitty.DTO.Response;

namespace Splitty.API.Tests;

/// <summary>
/// A recurring expense's participants are fixed, and it ends when its payer or anyone in its
/// split leaves, is removed, or deletes their account. Catch-up copies the split without
/// checking membership, so this is what keeps it from billing someone outside the group.
/// </summary>
[Collection(nameof(ApiCollection))]
public sealed class RecurringExpenseMembershipTests : IDisposable
{
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
        await group.CreateRecurringAsync("weekly", Now.UtcDateTime, paidBy: group.OwnerId, participants: [group.OwnerId, group.GuestId]);
        var third = await ApiClient.Create(_factory).SignInAsync(name: "Third");
        (await ApiClient.Create(_factory, third.Token).AcceptInviteAsync(await group.Owner.CreateInviteAsync(group.Id)))
            .EnsureSuccessStatusCode();

        _factory.Clock.Set(Now.AddDays(7));
        await group.OpenAsync();

        var expenses = await group.ExpensesAsync();
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
        await group.CreateRecurringAsync("weekly", Now.UtcDateTime, paidBy: group.OwnerId, participants: [group.OwnerId, group.GuestId]);
        await WorkerHarness.WaitForProcessedAsync(_factory);
        await group.SettleAsync(10m);
        await WorkerHarness.WaitForProcessedAsync(_factory);

        _factory.Clock.Set(Now.AddDays(7));
        var refused = await group.Guest.LeaveGroupAsync(group.Id);

        Assert.Equal(HttpStatusCode.Conflict, refused.StatusCode);
        Assert.Equal(2, (await group.ExpensesAsync()).Count);
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
        // Not the outstanding-balance refusal: the guest owes nothing. The code is what lets
        // a client tell the two 409s apart without reading English.
        var error = await ErrorResponseAssertions.ReadErrorAsync(refused);
        Assert.Equal(ErrorCode.BalancesPending, error.Code);
        Assert.Contains("recalculated", error.Message);

        gate.Release();
        await WorkerHarness.WaitForProcessedAsync(gated);

        Assert.Equal(HttpStatusCode.NoContent, (await guest.LeaveGroupAsync(group.Id)).StatusCode);
    }

    [Fact]
    public async Task Leaving_ends_the_recurring_expenses_the_member_shares_in()
    {
        var group = await GroupFixture.CreateAsync(_factory);
        await _factory.DrainProcessedAsync();
        await group.CreateRecurringAsync("weekly", Now.UtcDateTime, paidBy: group.OwnerId, participants: [group.OwnerId, group.GuestId]);
        await WorkerHarness.WaitForProcessedAsync(_factory);
        await group.SettleAsync(10m);
        await WorkerHarness.WaitForProcessedAsync(_factory);

        Assert.Equal(HttpStatusCode.NoContent, (await group.Guest.LeaveGroupAsync(group.Id)).StatusCode);

        _factory.Clock.Set(Now.AddDays(21));
        await group.OpenAsync();

        var remaining = Assert.Single(await group.ExpensesAsync());
        Assert.Equal(JsonValueKind.Null, remaining.GetProperty("recurringExpenseId").ValueKind);
        Assert.False(await RecurringExpensesExistAsync(group.Id));
    }

    [Fact]
    public async Task Removing_a_member_ends_the_recurring_expenses_they_pay_for()
    {
        var group = await GroupFixture.CreateAsync(_factory);
        await _factory.DrainProcessedAsync();
        // The guest pays for themselves alone, so they never owe anyone.
        await group.CreateRecurringAsync("weekly", Now.UtcDateTime, paidBy: group.GuestId, participants: [group.GuestId]);
        await WorkerHarness.WaitForProcessedAsync(_factory);

        Assert.Equal(HttpStatusCode.NoContent, (await group.Owner.RemoveMemberAsync(group.Id, group.GuestId)).StatusCode);

        _factory.Clock.Set(Now.AddDays(21));
        await group.OpenAsync();

        Assert.Single(await group.ExpensesAsync());
        Assert.False(await RecurringExpensesExistAsync(group.Id));
    }

    [Fact]
    public async Task Deleting_an_account_adds_the_due_repeat_first_then_ends_their_recurring_expenses()
    {
        var group = await GroupFixture.CreateAsync(_factory);
        await _factory.DrainProcessedAsync();
        await group.CreateRecurringAsync("weekly", Now.UtcDateTime, paidBy: group.OwnerId, participants: [group.OwnerId, group.GuestId]);
        await group.CreateRecurringAsync("weekly", Now.UtcDateTime, paidBy: group.GuestId, participants: [group.GuestId]);
        await WorkerHarness.WaitForProcessedAsync(_factory, count: 2);
        await group.SettleAsync(10m);
        await WorkerHarness.WaitForProcessedAsync(_factory);

        _factory.Clock.Set(Now.AddDays(7));
        Assert.Equal(HttpStatusCode.NoContent, (await group.Guest.DeleteAccountAsync()).StatusCode);
        await WorkerHarness.WaitForProcessedAsync(_factory);

        // Both due repeats were added, and the one the tombstone shares in left it owing,
        // so it keeps its membership to carry that.
        Assert.Equal(4, (await group.ExpensesAsync()).Count);
        Assert.False(await RecurringExpensesExistAsync(group.Id));
        Assert.Equal(10m, (await group.Owner.ReadSummaryAsync(group.Id)).AmountOwedBy(group.OwnerId, group.GuestId));

        _factory.Clock.Set(Now.AddDays(21));
        await group.OpenAsync();

        Assert.Equal(4, (await group.ExpensesAsync()).Count);
    }

    [Fact]
    public async Task Deactivating_leaves_recurring_expenses_running()
    {
        var group = await GroupFixture.CreateAsync(_factory);
        await group.CreateRecurringAsync("weekly", Now.UtcDateTime, paidBy: group.GuestId, participants: [group.OwnerId, group.GuestId]);

        (await group.Guest.DeactivateAccountAsync()).EnsureSuccessStatusCode();
        _factory.Clock.Set(Now.AddDays(7));
        await group.OpenAsync();

        Assert.Equal(2, (await group.ExpensesAsync()).Count);
    }

    // Helpers.

    private Task<bool> RecurringExpensesExistAsync(int groupId) =>
        _factory.UseDbAsync(db => db.RecurringExpense.AnyAsync(r => r.GroupId == groupId));
}
