using System.Net;
using Microsoft.EntityFrameworkCore;
using Splitty.Domain.Entities;

namespace Splitty.API.Tests;

/// <summary>
/// Settling stays unilateral — one member, one request, no confirmation — but bounded by
/// what the caller actually owes the peer.
/// </summary>
[Collection(nameof(ApiCollection))]
public sealed class SettlementBoundsTests(ApiFactory factory)
{
    /// <summary>
    /// The owner pays for both, so the guest owes the owner half and is the only member
    /// with anything to settle.
    /// </summary>
    private async Task<GroupFixture> GroupWhereGuestOwesAsync(decimal owed)
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();

        await group.CreateExpenseAsync(amount: owed * 2, share: owed);
        await factory.WaitForProcessedAsync();

        return group;
    }

    [Fact]
    public async Task Settling_more_than_is_owed_is_rejected()
    {
        var group = await GroupWhereGuestOwesAsync(10m);

        var response = await group.Guest.SettleUpAsync(group.Id, new { withUserId = group.OwnerId, amount = 10.01m });

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Settling_less_than_is_owed_succeeds()
    {
        var group = await GroupWhereGuestOwesAsync(10m);

        var response = await group.Guest.SettleUpAsync(group.Id, new { withUserId = group.OwnerId, amount = 4m });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        await factory.WaitForProcessedAsync();
        Assert.Equal(-6m, (await group.Guest.ReadSummaryAsync(group.Id)).AmountOwedBy(group.GuestId, group.OwnerId));
    }

    [Fact]
    public async Task Settling_exactly_what_is_owed_leaves_the_pairwise_balance_at_zero()
    {
        var group = await GroupWhereGuestOwesAsync(10m);

        var response = await group.Guest.SettleUpAsync(group.Id, new { withUserId = group.OwnerId, amount = 10m });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        await factory.WaitForProcessedAsync();

        var summary = await group.Guest.ReadSummaryAsync(group.Id);
        Assert.Equal(0m, summary.AmountOwedBy(group.GuestId, group.OwnerId));
    }

    [Fact]
    public async Task A_settlement_takes_one_request_from_one_member_with_no_confirmation()
    {
        var group = await GroupWhereGuestOwesAsync(10m);

        (await group.Guest.SettleUpAsync(group.Id, new { withUserId = group.OwnerId, amount = 10m }))
            .EnsureSuccessStatusCode();
        await factory.WaitForProcessedAsync();

        // The owner is never asked to confirm, and the balance is already settled for them.
        Assert.Equal(0m, (await group.Owner.ReadSummaryAsync(group.Id)).AmountOwedBy(group.OwnerId, group.GuestId));
    }

    [Fact]
    public async Task Settling_zero_or_a_negative_amount_is_rejected()
    {
        var group = await GroupWhereGuestOwesAsync(10m);

        var zero = await group.Guest.SettleUpAsync(group.Id, new { withUserId = group.OwnerId, amount = 0m });
        var negative = await group.Guest.SettleUpAsync(group.Id, new { withUserId = group.OwnerId, amount = -5m });

        await ErrorResponseAssertions.AssertErrorAsync(zero, HttpStatusCode.BadRequest);
        await ErrorResponseAssertions.AssertErrorAsync(negative, HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Settling_with_oneself_is_rejected()
    {
        var group = await GroupWhereGuestOwesAsync(10m);

        var response = await group.Guest.SettleUpAsync(group.Id, new { withUserId = group.GuestId, amount = 5m });

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.BadRequest);
    }

    /// <summary>
    /// The cap reads the balance table, so a group the worker has not replayed yet caps at
    /// zero. Accepted: a retryable 400 rather than an unbounded settlement.
    /// </summary>
    [Fact]
    public async Task Settling_against_a_group_with_no_computed_balances_is_rejected()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();
        await group.InsertExpenseDirectlyAsync(amount: 20m, share: 10m);

        var response = await group.Guest.SettleUpAsync(group.Id, new { withUserId = group.OwnerId, amount = 10m });

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task An_over_cap_rejection_reads_differently_from_a_malformed_amount()
    {
        var group = await GroupWhereGuestOwesAsync(10m);

        var overCap = await ErrorResponseAssertions.ReadErrorAsync(
            await group.Guest.SettleUpAsync(group.Id, new { withUserId = group.OwnerId, amount = 50m }));
        var malformed = await ErrorResponseAssertions.ReadErrorAsync(
            await group.Guest.SettleUpAsync(group.Id, new { withUserId = group.OwnerId, amount = -1m }));

        Assert.NotEqual(overCap.Message, malformed.Message);
        Assert.Contains("exceeds", overCap.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task A_settlement_produces_two_splits_of_equal_magnitude_and_opposite_sign()
    {
        var group = await GroupWhereGuestOwesAsync(10m);

        (await group.Guest.SettleUpAsync(group.Id, new { withUserId = group.OwnerId, amount = 7m }))
            .EnsureSuccessStatusCode();
        await factory.WaitForProcessedAsync();

        var splits = await factory.UseDbAsync(db => db.Expense
            .Where(e => e.GroupId == group.Id && e.Type == ExpenseType.Payment)
            .SelectMany(e => e.Splits)
            .Select(s => s.Amount)
            .ToListAsync());

        Assert.Equal(2, splits.Count);
        Assert.Equal(0m, splits.Sum());
        Assert.Equal(7m, splits.Max());
    }
}
