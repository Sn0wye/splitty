using System.Net;
using Microsoft.EntityFrameworkCore;
using Splitty.Domain.Entities;

namespace Splitty.API.Tests;

/// <summary>
/// Editing and deleting a settlement through its own routes. The edit re-applies the cap of
/// invariant 5 against a balance that already counts the row being edited, which is the one
/// thing this path can get wrong without any test noticing.
/// </summary>
[Collection(nameof(ApiCollection))]
public sealed class SettlementEditTests(ApiFactory factory)
{
    /// The owner pays 2x, so the guest owes x and settles part of it.
    private async Task<(GroupFixture Group, int SettlementId)> SettledAsync(decimal owed, decimal settled)
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();

        await group.CreateExpenseAsync(amount: owed * 2, share: owed);
        await factory.WaitForProcessedAsync();

        var settlementId = await group.SettleAsync(settled);
        await factory.WaitForProcessedAsync();

        return (group, settlementId);
    }

    [Fact]
    public async Task Lowering_a_settlement_puts_the_difference_back_on_the_debt()
    {
        var (group, settlementId) = await SettledAsync(owed: 10m, settled: 10m);

        var response = await group.Guest.UpdateSettlementAsync(group.Id, settlementId, new { amount = 4m });

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
        await factory.WaitForProcessedAsync();
        Assert.Equal(-6m, (await group.Guest.ReadSummaryAsync(group.Id)).AmountOwedBy(group.GuestId, group.OwnerId));
    }

    /// <summary>
    /// The regression the cap exists to avoid: a fully settled debt reads as zero, so an
    /// edit measured against the raw balance would reject even the amount already stored.
    /// </summary>
    [Fact]
    public async Task Re_saving_a_settlement_at_its_current_amount_is_accepted()
    {
        var (group, settlementId) = await SettledAsync(owed: 10m, settled: 10m);

        var response = await group.Guest.UpdateSettlementAsync(group.Id, settlementId, new { amount = 10m });

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
        await factory.WaitForProcessedAsync();
        Assert.Equal(0m, (await group.Guest.ReadSummaryAsync(group.Id)).AmountOwedBy(group.GuestId, group.OwnerId));
    }

    [Fact]
    public async Task Raising_a_settlement_past_the_debt_is_rejected()
    {
        var (group, settlementId) = await SettledAsync(owed: 10m, settled: 4m);

        var response = await group.Guest.UpdateSettlementAsync(group.Id, settlementId, new { amount = 10.01m });

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Raising_a_settlement_up_to_the_debt_is_accepted()
    {
        var (group, settlementId) = await SettledAsync(owed: 10m, settled: 4m);

        var response = await group.Guest.UpdateSettlementAsync(group.Id, settlementId, new { amount = 10m });

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
        await factory.WaitForProcessedAsync();
        Assert.Equal(0m, (await group.Guest.ReadSummaryAsync(group.Id)).AmountOwedBy(group.GuestId, group.OwnerId));
    }

    /// <summary>
    /// The replay reads splits and never reads <c>Amount</c>, so an edit that moved one and
    /// not the other would change the number users see and move no money.
    /// </summary>
    [Fact]
    public async Task An_edit_rebuilds_both_splits_from_the_new_amount()
    {
        var (group, settlementId) = await SettledAsync(owed: 10m, settled: 4m);

        (await group.Guest.UpdateSettlementAsync(group.Id, settlementId, new { amount = 7m }))
            .EnsureSuccessStatusCode();

        var splits = await factory.UseDbAsync(db => db.ExpenseSplit
            .Where(s => s.ExpenseId == settlementId)
            .Select(s => s.Amount)
            .ToListAsync());

        Assert.Equal(2, splits.Count);
        Assert.Equal(0m, splits.Sum());
        Assert.Equal(7m, splits.Max());
    }

    [Fact]
    public async Task Editing_a_settlement_to_zero_or_a_negative_amount_is_rejected()
    {
        var (group, settlementId) = await SettledAsync(owed: 10m, settled: 4m);

        var zero = await group.Guest.UpdateSettlementAsync(group.Id, settlementId, new { amount = 0m });
        var negative = await group.Guest.UpdateSettlementAsync(group.Id, settlementId, new { amount = -4m });

        await ErrorResponseAssertions.AssertErrorAsync(zero, HttpStatusCode.BadRequest);
        await ErrorResponseAssertions.AssertErrorAsync(negative, HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Deleting_a_settlement_restores_the_debt_it_paid_down()
    {
        var (group, settlementId) = await SettledAsync(owed: 10m, settled: 10m);

        var response = await group.Guest.DeleteSettlementAsync(group.Id, settlementId);

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
        await factory.WaitForProcessedAsync();
        Assert.Equal(-10m, (await group.Guest.ReadSummaryAsync(group.Id)).AmountOwedBy(group.GuestId, group.OwnerId));
    }

    /// <summary>
    /// The counterparty can undo it too: every member can correct anyone's rows
    /// (invariant 2).
    /// </summary>
    [Fact]
    public async Task The_payee_can_delete_a_settlement_recorded_against_them()
    {
        var (group, settlementId) = await SettledAsync(owed: 10m, settled: 10m);

        var response = await group.Owner.DeleteSettlementAsync(group.Id, settlementId);

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
    }

    [Fact]
    public async Task The_settlement_routes_refuse_an_ordinary_expense()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var expenseId = await group.CreateExpenseAsync(amount: 20m, share: 10m);

        await ErrorResponseAssertions.AssertErrorAsync(
            await group.Owner.UpdateSettlementAsync(group.Id, expenseId, new { amount = 5m }),
            HttpStatusCode.BadRequest);
        await ErrorResponseAssertions.AssertErrorAsync(
            await group.Owner.DeleteSettlementAsync(group.Id, expenseId),
            HttpStatusCode.BadRequest);

        Assert.NotNull(await factory.UseDbAsync(db => db.Expense.FirstOrDefaultAsync(e => e.Id == expenseId)));
    }

    [Fact]
    public async Task A_non_member_can_neither_edit_nor_delete_a_settlement()
    {
        var (group, settlementId) = await SettledAsync(owed: 10m, settled: 4m);
        var user = await ApiClient.Create(factory).SignInAsync(name: "Stranger");
        var stranger = ApiClient.Create(factory, user.Token);

        Assert.Equal(
            HttpStatusCode.Forbidden,
            (await stranger.UpdateSettlementAsync(group.Id, settlementId, new { amount = 1m })).StatusCode);
        Assert.Equal(
            HttpStatusCode.Forbidden,
            (await stranger.DeleteSettlementAsync(group.Id, settlementId)).StatusCode);
    }

    [Fact]
    public async Task A_settlement_of_another_group_is_not_found()
    {
        var (group, settlementId) = await SettledAsync(owed: 10m, settled: 4m);
        var other = await GroupFixture.CreateAsync(factory);

        var response = await other.Owner.DeleteSettlementAsync(other.Id, settlementId);

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task An_edit_can_move_the_settlement_date()
    {
        var (group, settlementId) = await SettledAsync(owed: 10m, settled: 4m);
        var date = new DateTime(2026, 3, 1, 12, 0, 0, DateTimeKind.Utc);

        (await group.Guest.UpdateSettlementAsync(group.Id, settlementId, new { amount = 4m, date }))
            .EnsureSuccessStatusCode();

        Assert.Equal(date, await factory.UseDbAsync(db => db.Expense
            .Where(e => e.Id == settlementId)
            .Select(e => e.Date)
            .FirstAsync()));
    }
}
