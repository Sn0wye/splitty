using System.Net;
using Microsoft.EntityFrameworkCore;
using Splitty.Domain.Entities;

namespace Splitty.API.Tests;

/// <summary>
/// Either side records a payment: the payer saying "I paid", the payee saying "I was paid",
/// or any other member. The cap and the edit read the payer and payee off the payment, not
/// off whoever sent the request. See docs/adr/0010-any-member-records-a-payment-either-way.md.
/// </summary>
[Collection(nameof(ApiCollection))]
public sealed class SettlementDirectionTests(ApiFactory factory)
{
    /// <summary>The owner pays for both, so the guest owes the owner <paramref name="owed"/>.</summary>
    private async Task<GroupFixture> GroupWhereGuestOwesAsync(decimal owed)
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();

        await group.CreateExpenseAsync(amount: owed * 2, share: owed);
        await factory.WaitForProcessedAsync();

        return group;
    }

    private async Task<(SignedInUser User, ApiClient Client)> JoinThirdMemberAsync(GroupFixture group)
    {
        var third = await ApiClient.Create(factory).SignInAsync(name: "Third");
        var client = ApiClient.Create(factory, third.Token);
        (await client.AcceptInviteAsync(await group.Owner.CreateInviteAsync(group.Id))).EnsureSuccessStatusCode();
        return (third, client);
    }

    private Task<Expense> OnlyPaymentAsync(int groupId) =>
        factory.UseDbAsync(db => db.Expense
            .Include(e => e.Splits)
            .SingleAsync(e => e.GroupId == groupId && e.Type == ExpenseType.Payment));

    [Fact]
    public async Task The_payee_records_a_payment_they_received()
    {
        var group = await GroupWhereGuestOwesAsync(10m);

        var response = await group.Owner.SettleUpAsync(group.Id,
            new { fromUserId = group.GuestId, toUserId = group.OwnerId, amount = 4m });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        await factory.WaitForProcessedAsync();
        Assert.Equal(6m, (await group.Owner.ReadSummaryAsync(group.Id)).AmountOwedBy(group.OwnerId, group.GuestId));

        var payment = await OnlyPaymentAsync(group.Id);
        Assert.Equal(group.GuestId, payment.PaidBy);
        Assert.Equal(4m, payment.Splits.Single(s => s.UserId == group.GuestId).Amount);
        Assert.Equal(-4m, payment.Splits.Single(s => s.UserId == group.OwnerId).Amount);
    }

    [Fact]
    public async Task A_received_payment_is_capped_like_a_paid_one()
    {
        var group = await GroupWhereGuestOwesAsync(10m);

        var response = await group.Owner.SettleUpAsync(group.Id,
            new { fromUserId = group.GuestId, toUserId = group.OwnerId, amount = 10.01m });

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Recording_the_creditor_paying_the_debtor_is_capped_at_zero()
    {
        var group = await GroupWhereGuestOwesAsync(10m);

        var response = await group.Owner.SettleUpAsync(group.Id,
            new { fromUserId = group.OwnerId, toUserId = group.GuestId, amount = 1m });

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task A_member_who_is_neither_side_records_a_payment_between_two_others()
    {
        var group = await GroupWhereGuestOwesAsync(10m);
        var (_, third) = await JoinThirdMemberAsync(group);

        var response = await third.SettleUpAsync(group.Id,
            new { fromUserId = group.GuestId, toUserId = group.OwnerId, amount = 10m });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        await factory.WaitForProcessedAsync();
        Assert.Equal(0m, (await group.Owner.ReadSummaryAsync(group.Id)).AmountOwedBy(group.OwnerId, group.GuestId));
    }

    [Fact]
    public async Task A_creditor_records_a_payment_received_from_a_deleted_debtor_and_then_removes_them()
    {
        var group = await GroupWhereGuestOwesAsync(10m);

        (await group.Guest.DeleteAccountAsync()).EnsureSuccessStatusCode();

        var response = await group.Owner.SettleUpAsync(group.Id,
            new { fromUserId = group.GuestId, toUserId = group.OwnerId, amount = 10m });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        await factory.WaitForProcessedAsync();
        Assert.Equal(HttpStatusCode.NoContent,
            (await group.Owner.RemoveMemberAsync(group.Id, group.GuestId)).StatusCode);
    }

    [Fact]
    public async Task The_payer_edits_a_payment_the_payee_recorded()
    {
        var group = await GroupWhereGuestOwesAsync(10m);
        (await group.Owner.SettleUpAsync(group.Id,
            new { fromUserId = group.GuestId, toUserId = group.OwnerId, amount = 10m })).EnsureSuccessStatusCode();
        await factory.WaitForProcessedAsync();
        var payment = await OnlyPaymentAsync(group.Id);

        var response = await group.Guest.UpdateSettlementAsync(group.Id, payment.Id, new { amount = 7m });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        await factory.WaitForProcessedAsync();
        Assert.Equal(3m, (await group.Owner.ReadSummaryAsync(group.Id)).AmountOwedBy(group.OwnerId, group.GuestId));
    }

    [Fact]
    public async Task A_body_mixing_both_shapes_is_rejected()
    {
        var group = await GroupWhereGuestOwesAsync(10m);

        var response = await group.Guest.SettleUpAsync(group.Id,
            new { withUserId = group.OwnerId, fromUserId = group.GuestId, toUserId = group.OwnerId, amount = 5m });

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task A_body_naming_only_one_side_is_rejected()
    {
        var group = await GroupWhereGuestOwesAsync(10m);

        var onlyFrom = await group.Owner.SettleUpAsync(group.Id, new { fromUserId = group.GuestId, amount = 5m });
        var onlyTo = await group.Owner.SettleUpAsync(group.Id, new { toUserId = group.OwnerId, amount = 5m });
        var neither = await group.Owner.SettleUpAsync(group.Id, new { amount = 5m });

        await ErrorResponseAssertions.AssertErrorAsync(onlyFrom, HttpStatusCode.BadRequest);
        await ErrorResponseAssertions.AssertErrorAsync(onlyTo, HttpStatusCode.BadRequest);
        await ErrorResponseAssertions.AssertErrorAsync(neither, HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task A_payment_from_a_member_to_themselves_is_rejected()
    {
        var group = await GroupWhereGuestOwesAsync(10m);

        var response = await group.Owner.SettleUpAsync(group.Id,
            new { fromUserId = group.GuestId, toUserId = group.GuestId, amount = 5m });

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task A_payment_naming_someone_outside_the_group_is_forbidden()
    {
        var group = await GroupWhereGuestOwesAsync(10m);
        var stranger = await ApiClient.Create(factory).SignInAsync(name: "Stranger");

        var response = await group.Owner.SettleUpAsync(group.Id,
            new { fromUserId = stranger.Id, toUserId = group.OwnerId, amount = 5m });

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.Forbidden);
    }
}
