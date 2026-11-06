using System.Net;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Splitty.Domain.Entities;

namespace Splitty.API.Tests;

/// <summary>
/// What a client that queues writes offline relies on: a resent create adds nothing, a stale
/// edit is refused with the row as it is now, a resent edit is not a conflict with itself,
/// and a write in a currency the group no longer has is refused. See
/// docs/adr/0008-offline-writes.md.
/// </summary>
[Collection(nameof(ApiCollection))]
public sealed class OfflineWriteTests(ApiFactory factory)
{
    private object ExpenseBody(GroupFixture group, Guid? clientId = null, string? currency = null) => new
    {
        clientId,
        currency,
        paidBy = group.OwnerId,
        amount = 20m,
        description = "Taxi",
        date = new DateTime(2026, 11, 1, 12, 0, 0, DateTimeKind.Utc),
        splitMode = "equal",
        splits = new[]
        {
            new { userId = group.OwnerId, amount = 10m },
            new { userId = group.GuestId, amount = 10m }
        }
    };

    private static async Task<JsonElement> JsonAsync(HttpResponseMessage response) =>
        JsonDocument.Parse(await response.Content.ReadAsStringAsync()).RootElement;

    private async Task<int> RowCountAsync(int groupId, ExpenseType type) =>
        await factory.UseDbAsync(db => db.Expense.CountAsync(e => e.GroupId == groupId && e.Type == type));

    [Fact]
    public async Task A_resent_create_answers_with_the_first_row_and_adds_nothing()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var clientId = Guid.NewGuid();

        var first = await group.Owner.ReadJsonAsync(
            await group.Owner.CreateExpenseAsync(group.Id, ExpenseBody(group, clientId)));
        var resent = await group.Owner.ReadJsonAsync(
            await group.Owner.CreateExpenseAsync(group.Id, ExpenseBody(group, clientId)));

        Assert.Equal(first.GetProperty("id").GetInt32(), resent.GetProperty("id").GetInt32());
        Assert.Equal(clientId, resent.GetProperty("clientId").GetGuid());
        Assert.Equal(1, await RowCountAsync(group.Id, ExpenseType.Expense));
    }

    [Fact]
    public async Task Creates_without_a_client_id_are_never_matched_to_each_other()
    {
        var group = await GroupFixture.CreateAsync(factory);

        (await group.Owner.CreateExpenseAsync(group.Id, ExpenseBody(group))).EnsureSuccessStatusCode();
        (await group.Owner.CreateExpenseAsync(group.Id, ExpenseBody(group))).EnsureSuccessStatusCode();

        Assert.Equal(2, await RowCountAsync(group.Id, ExpenseType.Expense));
    }

    [Fact]
    public async Task A_new_row_starts_at_version_one()
    {
        var group = await GroupFixture.CreateAsync(factory);

        var created = await group.Owner.ReadJsonAsync(
            await group.Owner.CreateExpenseAsync(group.Id, ExpenseBody(group, Guid.NewGuid())));

        Assert.Equal(1, created.GetProperty("version").GetInt32());
    }

    [Fact]
    public async Task A_settlement_answers_with_its_row_and_a_resend_does_not_pay_twice()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await group.CreateExpenseAsync(amount: 20m, share: 10m);
        var clientId = Guid.NewGuid();
        var body = new { withUserId = group.OwnerId, amount = 10m, clientId };

        var first = await group.Guest.ReadJsonAsync(await group.Guest.SettleUpAsync(group.Id, body));
        await factory.WaitForProcessedAsync();
        var resent = await group.Guest.ReadJsonAsync(await group.Guest.SettleUpAsync(group.Id, body));

        Assert.Equal("payment", first.GetProperty("type").GetString());
        Assert.Equal(clientId, first.GetProperty("clientId").GetGuid());
        Assert.Equal(first.GetProperty("id").GetInt32(), resent.GetProperty("id").GetInt32());
        Assert.Equal(1, await RowCountAsync(group.Id, ExpenseType.Payment));
    }

    [Fact]
    public async Task A_client_id_that_names_a_row_of_the_other_type_is_refused()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await group.CreateExpenseAsync(amount: 20m, share: 10m);
        var clientId = Guid.NewGuid();
        (await group.Owner.CreateExpenseAsync(group.Id, ExpenseBody(group, clientId))).EnsureSuccessStatusCode();

        var response = await group.Guest.SettleUpAsync(group.Id, new { withUserId = group.OwnerId, amount = 5m, clientId });

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.BadRequest);
        Assert.Equal(0, await RowCountAsync(group.Id, ExpenseType.Payment));
    }

    [Fact]
    public async Task An_edit_against_an_old_version_is_refused_with_the_row_as_it_is_now()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var expenseId = await group.CreateExpenseAsync(amount: 20m, share: 10m);

        var edited = await group.Guest.ReadJsonAsync(await group.Guest.UpdateExpenseAsync(group.Id, expenseId,
            new { description = "Guest's edit", baseVersion = 1 }));
        var stale = await group.Owner.UpdateExpenseAsync(group.Id, expenseId,
            new { description = "Owner's stale edit", baseVersion = 1 });

        Assert.Equal(2, edited.GetProperty("version").GetInt32());
        Assert.Equal(HttpStatusCode.Conflict, stale.StatusCode);
        var error = await JsonAsync(stale);
        Assert.Equal("version_conflict", error.GetProperty("code").GetString());
        Assert.Equal(2, error.GetProperty("expense").GetProperty("version").GetInt32());
        Assert.Equal("Guest's edit", error.GetProperty("expense").GetProperty("description").GetString());

        var stored = await group.Owner.ReadJsonAsync(await group.Owner.GetExpenseAsync(group.Id, expenseId));
        Assert.Equal("Guest's edit", stored.GetProperty("description").GetString());
    }

    [Fact]
    public async Task An_edit_without_a_base_version_applies_to_whatever_is_there()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var expenseId = await group.CreateExpenseAsync(amount: 20m, share: 10m);
        (await group.Guest.UpdateExpenseAsync(group.Id, expenseId, new { description = "First" })).EnsureSuccessStatusCode();

        var second = await group.Owner.ReadJsonAsync(
            await group.Owner.UpdateExpenseAsync(group.Id, expenseId, new { description = "Second" }));

        Assert.Equal("Second", second.GetProperty("description").GetString());
        Assert.Equal(3, second.GetProperty("version").GetInt32());
    }

    [Fact]
    public async Task A_resent_edit_answers_with_the_row_instead_of_a_conflict_with_itself()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var expenseId = await group.CreateExpenseAsync(amount: 20m, share: 10m);
        var body = new { description = "Once", baseVersion = 1, opId = Guid.NewGuid() };

        (await group.Owner.UpdateExpenseAsync(group.Id, expenseId, body)).EnsureSuccessStatusCode();
        var resent = await group.Owner.ReadJsonAsync(await group.Owner.UpdateExpenseAsync(group.Id, expenseId, body));

        Assert.Equal(2, resent.GetProperty("version").GetInt32());
        Assert.Equal("Once", resent.GetProperty("description").GetString());
    }

    [Fact]
    public async Task A_write_in_a_currency_the_group_no_longer_has_is_refused()
    {
        var group = await GroupFixture.CreateAsync(factory);
        (await group.Owner.UpdateGroupAsync(group.Id, new { currency = "EUR" })).EnsureSuccessStatusCode();

        var stale = await group.Owner.CreateExpenseAsync(group.Id, ExpenseBody(group, Guid.NewGuid(), currency: "USD"));
        var current = await group.Owner.CreateExpenseAsync(group.Id, ExpenseBody(group, Guid.NewGuid(), currency: "EUR"));

        Assert.Equal(HttpStatusCode.Conflict, stale.StatusCode);
        Assert.Equal("currency_changed", (await JsonAsync(stale)).GetProperty("code").GetString());
        Assert.Equal(HttpStatusCode.OK, current.StatusCode);
        Assert.Equal(1, await RowCountAsync(group.Id, ExpenseType.Expense));
    }

    [Fact]
    public async Task A_resent_create_is_answered_even_after_the_currency_changed()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var clientId = Guid.NewGuid();
        (await group.Owner.CreateExpenseAsync(group.Id, ExpenseBody(group, clientId, currency: "USD"))).EnsureSuccessStatusCode();
        (await group.Owner.UpdateGroupAsync(group.Id, new { currency = "EUR" })).EnsureSuccessStatusCode();

        var resent = await group.Owner.CreateExpenseAsync(group.Id, ExpenseBody(group, clientId, currency: "USD"));

        Assert.Equal(HttpStatusCode.OK, resent.StatusCode);
    }

    [Fact]
    public async Task An_over_cap_settlement_carries_its_code_and_the_cap()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await group.CreateExpenseAsync(amount: 20m, share: 10m);

        var response = await group.Guest.SettleUpAsync(group.Id, new { withUserId = group.OwnerId, amount = 12m });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var error = await JsonAsync(response);
        Assert.Equal("settlement_exceeds_cap", error.GetProperty("code").GetString());
        Assert.Equal(10m, error.GetProperty("cap").GetDecimal());
    }

    [Fact]
    public async Task A_settlement_edit_against_an_old_version_is_refused()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await group.CreateExpenseAsync(amount: 20m, share: 10m);
        var settlementId = await group.SettleAsync(4m);

        var edited = await group.Guest.ReadJsonAsync(
            await group.Guest.UpdateSettlementAsync(group.Id, settlementId, new { amount = 5m, baseVersion = 1 }));
        var stale = await group.Owner.UpdateSettlementAsync(group.Id, settlementId, new { amount = 6m, baseVersion = 1 });

        Assert.Equal(2, edited.GetProperty("version").GetInt32());
        Assert.Equal(HttpStatusCode.Conflict, stale.StatusCode);
        Assert.Equal("version_conflict", (await JsonAsync(stale)).GetProperty("code").GetString());
    }

    [Fact]
    public async Task A_delete_wins_over_an_edit_it_never_saw()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var expenseId = await group.CreateExpenseAsync(amount: 20m, share: 10m);
        (await group.Guest.UpdateExpenseAsync(group.Id, expenseId, new { description = "Edited" })).EnsureSuccessStatusCode();

        var deleted = await group.Owner.DeleteExpenseAsync(group.Id, expenseId);
        var editOfDeleted = await group.Guest.UpdateExpenseAsync(group.Id, expenseId,
            new { description = "Too late", baseVersion = 2 });

        Assert.Equal(HttpStatusCode.NoContent, deleted.StatusCode);
        await ErrorResponseAssertions.AssertErrorAsync(editOfDeleted, HttpStatusCode.NotFound);
    }
}
