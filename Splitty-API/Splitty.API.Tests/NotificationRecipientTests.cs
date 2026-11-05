using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Splitty.Service;

namespace Splitty.API.Tests;

/// <summary>
/// Who hears about a write, and what each person is told. The actor never hears about their
/// own action, and an edit is told only to someone whose money in the expense moved.
/// </summary>
[Collection(nameof(ApiCollection))]
public sealed class NotificationRecipientTests(ApiFactory factory)
{
    private CapturingNotifier Notifier => factory.Notifier;

    /// What the group's writes produced, without the invite notice every fixture starts with.
    private List<Notice> Notices(GroupFixture group) =>
        Notifier.InGroup(group.Id).Where(n => n.Message != NoticeMessage.InviteAccepted).ToList();

    private static async Task<int> IdOf(HttpResponseMessage response)
    {
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        return (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetInt32();
    }

    private static object Expense(int paidBy, decimal amount, params (int UserId, decimal Amount)[] splits) => new
    {
        paidBy,
        amount,
        description = "Dinner",
        splitMode = "custom",
        splits = splits.Select(s => new { userId = s.UserId, amount = s.Amount }).ToArray()
    };

    [Fact]
    public async Task A_new_expense_tells_each_participant_their_share_and_not_the_person_who_added_it()
    {
        var group = await GroupFixture.CreateAsync(factory);

        var expenseId = await IdOf(await group.Owner.CreateExpenseAsync(group.Id,
            Expense(group.OwnerId, 30m, (group.OwnerId, 10m), (group.GuestId, 20m))));

        var notice = Assert.Single(Notices(group));
        Assert.Equal(group.GuestId, notice.RecipientId);
        Assert.Equal(NoticeMessage.ExpenseAdded, notice.Message);
        Assert.Equal(group.OwnerId, notice.ActorId);
        Assert.Equal(20m, notice.Amount);
        Assert.Equal(expenseId, notice.ExpenseId);
        Assert.Equal("Dinner", notice.Description);
    }

    [Fact]
    public async Task A_payer_outside_the_split_is_told_what_they_paid()
    {
        var group = await GroupFixture.CreateAsync(factory);

        await IdOf(await group.Guest.CreateExpenseAsync(group.Id,
            Expense(group.OwnerId, 30m, (group.GuestId, 30m))));

        var notice = Assert.Single(Notices(group));
        Assert.Equal(group.OwnerId, notice.RecipientId);
        Assert.Equal(NoticeMessage.ExpenseAddedPaidByYou, notice.Message);
        Assert.Equal(30m, notice.Amount);
    }

    [Fact]
    public async Task Editing_only_the_description_tells_no_one()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var expenseId = await group.CreateExpenseAsync(amount: 20m, share: 10m);

        var response = await group.Owner.UpdateExpenseAsync(group.Id, expenseId, new { description = "Lunch" });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.DoesNotContain(Notices(group), n => n.Kind == Splitty.Domain.Entities.NotificationKind.ExpenseChanged);
    }

    [Fact]
    public async Task Changing_a_share_tells_that_person_the_amount_before_and_after()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var expenseId = await group.CreateExpenseAsync(amount: 20m, share: 10m);

        var response = await group.Owner.UpdateExpenseAsync(group.Id, expenseId,
            Expense(group.OwnerId, 30m, (group.OwnerId, 10m), (group.GuestId, 20m)));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var notice = Assert.Single(Notices(group), n => n.Message == NoticeMessage.ExpenseShareChanged);
        Assert.Equal(group.GuestId, notice.RecipientId);
        Assert.Equal(10m, notice.Before);
        Assert.Equal(20m, notice.Amount);
    }

    [Fact]
    public async Task Taking_someone_out_of_an_expense_or_back_in_tells_them()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var expenseId = await group.CreateExpenseAsync(amount: 20m, share: 10m);

        await group.Owner.UpdateExpenseAsync(group.Id, expenseId, Expense(group.OwnerId, 20m, (group.OwnerId, 20m)));
        await group.Owner.UpdateExpenseAsync(group.Id, expenseId,
            Expense(group.OwnerId, 20m, (group.OwnerId, 5m), (group.GuestId, 15m)));

        Assert.Equal(
            new (NoticeMessage, decimal?)[] { (NoticeMessage.ExpenseRemovedYou, null), (NoticeMessage.ExpenseIncludedYou, 15m) },
            Notices(group).Skip(1).Select(n => (n.Message, n.Amount)));
        Assert.All(Notices(group), n => Assert.Equal(group.GuestId, n.RecipientId));
    }

    [Fact]
    public async Task A_payer_outside_the_split_hears_when_the_total_changes()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var expenseId = await IdOf(await group.Guest.CreateExpenseAsync(group.Id,
            Expense(group.OwnerId, 30m, (group.GuestId, 30m))));

        await group.Guest.UpdateExpenseAsync(group.Id, expenseId, Expense(group.OwnerId, 45m, (group.GuestId, 45m)));

        var notice = Notices(group).Last();
        Assert.Equal((group.OwnerId, NoticeMessage.ExpensePaidTotalChanged, 30m, 45m),
            (notice.RecipientId, notice.Message, notice.Before!.Value, notice.Amount!.Value));
    }

    [Fact]
    public async Task Deleting_an_expense_tells_each_participant_the_share_they_had()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var expenseId = await group.CreateExpenseAsync(amount: 20m, share: 10m);

        await group.Owner.DeleteExpenseAsync(group.Id, expenseId);

        var notice = Assert.Single(Notices(group), n => n.Message == NoticeMessage.ExpenseDeleted);
        Assert.Equal(group.GuestId, notice.RecipientId);
        Assert.Equal(10m, notice.Amount);
    }

    [Fact]
    public async Task A_payment_is_told_to_the_person_paid_and_its_changes_to_the_other_side()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();
        await group.CreateExpenseAsync(amount: 40m, share: 20m);
        await factory.WaitForProcessedAsync();

        var settlementId = await group.SettleAsync(15m);
        await factory.WaitForProcessedAsync();

        var received = Assert.Single(Notices(group), n => n.Message == NoticeMessage.PaymentReceived);
        Assert.Equal(group.OwnerId, received.RecipientId);
        Assert.Equal(group.GuestId, received.ActorId);
        Assert.Equal(15m, received.Amount);

        (await group.Guest.UpdateSettlementAsync(group.Id, settlementId, new { amount = 10m })).EnsureSuccessStatusCode();
        await factory.WaitForProcessedAsync();
        var changed = Assert.Single(Notices(group), n => n.Kind == Splitty.Domain.Entities.NotificationKind.PaymentChanged);
        Assert.Equal((group.OwnerId, NoticeMessage.PaymentToYouChangedByPayer, 15m, 10m),
            (changed.RecipientId, changed.Message, changed.Before!.Value, changed.Amount!.Value));

        (await group.Owner.DeleteSettlementAsync(group.Id, settlementId)).EnsureSuccessStatusCode();
        var deleted = Assert.Single(Notices(group), n => n.Kind == Splitty.Domain.Entities.NotificationKind.PaymentDeleted);
        Assert.Equal((group.GuestId, NoticeMessage.YourPaymentDeletedByPayee, 10m),
            (deleted.RecipientId, deleted.Message, deleted.Amount!.Value));
    }

    [Fact]
    public async Task A_recurring_expense_is_told_once_and_its_repeats_never()
    {
        var now = new DateTimeOffset(2031, 3, 4, 12, 0, 0, TimeSpan.Zero);
        factory.Clock.Set(now);

        try
        {
            var group = await GroupFixture.CreateAsync(factory);
            await group.CreateRecurringAsync(repeat: "weekly", date: now.UtcDateTime);

            factory.Clock.Set(now.AddDays(21));
            await group.OpenAsync();

            Assert.Equal(4, (await group.ExpensesAsync()).Count);
            var notice = Assert.Single(Notices(group));
            Assert.Equal(NoticeMessage.RecurringExpenseAdded, notice.Message);
            Assert.Equal(Splitty.Domain.Entities.RepeatFrequency.Weekly, notice.Frequency);
            Assert.Equal(group.GuestId, notice.RecipientId);
        }
        finally
        {
            factory.Clock.Reset();
        }
    }

    [Fact]
    public async Task Joining_with_an_invite_tells_the_person_who_made_it()
    {
        var group = await GroupFixture.CreateAsync(factory);

        var notice = Assert.Single(Notifier.InGroup(group.Id));
        Assert.Equal((group.OwnerId, NoticeMessage.InviteAccepted, group.GuestId),
            (notice.RecipientId, notice.Message, notice.ActorId));
    }

    [Fact]
    public async Task Being_removed_is_told_to_the_member_removed_and_leaving_tells_no_one()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var third = await ApiClient.Create(factory).SignInAsync(name: "Third");
        var thirdClient = ApiClient.Create(factory, third.Token);
        (await thirdClient.AcceptInviteAsync(await group.Owner.CreateInviteAsync(group.Id))).EnsureSuccessStatusCode();

        Assert.Equal(HttpStatusCode.NoContent, (await group.Owner.RemoveMemberAsync(group.Id, group.GuestId)).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await thirdClient.LeaveGroupAsync(group.Id)).StatusCode);

        var removed = Assert.Single(Notices(group), n => n.Message == NoticeMessage.RemovedFromGroup);
        Assert.Equal((group.GuestId, group.OwnerId), (removed.RecipientId, removed.ActorId));
    }
}
