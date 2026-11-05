using System.Net;
using Splitty.Service;

namespace Splitty.API.Tests;

/// A creditor asks a member who owes them to pay, with the amount from the simplified debts.
[Collection(nameof(ApiCollection))]
public sealed class ReminderTests(ApiFactory factory)
{
    /// The owner paid 30 split evenly, so the guest owes the owner 15.
    private async Task<GroupFixture> OwedAsync()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();
        await group.CreateExpenseAsync(amount: 30m, share: 15m);
        await factory.WaitForProcessedAsync();

        return group;
    }

    [Fact]
    public async Task A_reminder_asks_the_debtor_for_what_they_owe_once_a_day()
    {
        var group = await OwedAsync();

        Assert.Equal(HttpStatusCode.NoContent, (await group.Owner.SendReminderAsync(group.Id, group.GuestId)).StatusCode);
        Assert.Equal(HttpStatusCode.TooManyRequests, (await group.Owner.SendReminderAsync(group.Id, group.GuestId)).StatusCode);

        var notice = Assert.Single(factory.Notifier.InGroup(group.Id), n => n.Message == NoticeMessage.PaymentReminder);
        Assert.Equal((group.GuestId, group.OwnerId, 15m), (notice.RecipientId, notice.ActorId, notice.Amount!.Value));
    }

    [Fact]
    public async Task Someone_who_owes_you_nothing_cannot_be_reminded()
    {
        var group = await OwedAsync();

        await ErrorResponseAssertions.AssertErrorAsync(
            await group.Guest.SendReminderAsync(group.Id, group.OwnerId), HttpStatusCode.BadRequest);
        await ErrorResponseAssertions.AssertErrorAsync(
            await group.Owner.SendReminderAsync(group.Id, group.OwnerId), HttpStatusCode.BadRequest);
        Assert.DoesNotContain(factory.Notifier.InGroup(group.Id), n => n.Message == NoticeMessage.PaymentReminder);
    }

    [Fact]
    public async Task A_reminder_waits_for_pending_balances()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();

        using var gate = new RecomputeGate(group.Id);
        await using var host = factory.WithGate(gate);
        await host.DrainProcessedAsync();
        var owner = ApiClient.Create(host, group.OwnerToken);

        (await owner.CreateExpenseAsync(group.Id, new
        {
            paidBy = group.OwnerId,
            amount = 30m,
            description = "Dinner",
            splitMode = "equal",
            splits = new[] { new { userId = group.OwnerId, amount = 15m }, new { userId = group.GuestId, amount = 15m } }
        })).EnsureSuccessStatusCode();
        await gate.WaitForEntryAsync();

        var response = await owner.SendReminderAsync(group.Id, group.GuestId);

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.Conflict);
        gate.Release();
    }

    [Fact]
    public async Task A_reminder_needs_a_member_on_both_ends()
    {
        var group = await OwedAsync();
        var stranger = await ApiClient.Create(factory).SignInAsync();

        await ErrorResponseAssertions.AssertErrorAsync(
            await group.Owner.SendReminderAsync(group.Id, stranger.Id), HttpStatusCode.NotFound);
        Assert.Equal(HttpStatusCode.Forbidden,
            (await ApiClient.Create(factory, stranger.Token).SendReminderAsync(group.Id, group.GuestId)).StatusCode);
    }
}
