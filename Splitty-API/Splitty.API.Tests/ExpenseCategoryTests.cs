using System.Net;
using Microsoft.EntityFrameworkCore;
using Splitty.Domain.Entities;

namespace Splitty.API.Tests;

/// <summary>
/// What an expense was for: one value from a closed list, stored non-null with
/// <c>general</c> meaning nobody chose. The asymmetry between the two route families is the
/// point — an expense filed as <c>payment</c> is a client confused about what it is writing
/// and is refused, while a category sent to a settlement route is merely noise and is
/// coerced. See docs/adr/0002-expense-categories-are-a-closed-text-list.md.
/// </summary>
[Collection(nameof(ApiCollection))]
public sealed class ExpenseCategoryTests(ApiFactory factory)
{
    [Fact]
    public async Task A_category_supplied_on_create_is_stored_and_returned()
    {
        var group = await GroupFixture.CreateAsync(factory);

        var expenseId = await CreateExpenseAsync(group, category: "groceries");

        Assert.Equal(ExpenseCategory.Groceries, await StoredCategoryAsync(expenseId));

        var body = await group.Owner.ReadJsonAsync(await group.Owner.GetExpenseAsync(group.Id, expenseId));
        Assert.Equal("groceries", body.GetProperty("category").GetString());
    }

    [Fact]
    public async Task A_create_omitting_the_category_stores_general()
    {
        var group = await GroupFixture.CreateAsync(factory);

        var expenseId = await group.CreateExpenseAsync(amount: 20m, share: 10m);

        Assert.Equal(ExpenseCategory.General, await StoredCategoryAsync(expenseId));
    }

    [Fact]
    public async Task Create_rejects_an_unknown_category()
    {
        var group = await GroupFixture.CreateAsync(factory);

        var response = await group.Owner.CreateExpenseAsync(group.Id, Expense(group, category: "spaceship"));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Create_refuses_the_payment_category()
    {
        var group = await GroupFixture.CreateAsync(factory);

        var response = await group.Owner.CreateExpenseAsync(group.Id, Expense(group, category: "payment"));

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task An_edit_may_change_the_category_alone()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var expenseId = await CreateExpenseAsync(group, category: "groceries");

        (await group.Owner.UpdateExpenseAsync(group.Id, expenseId, new { category = "dining_out" }))
            .EnsureSuccessStatusCode();

        Assert.Equal(ExpenseCategory.DiningOut, await StoredCategoryAsync(expenseId));
    }

    /// <summary>
    /// Patch semantics, like every other field on the update request: absent is unchanged,
    /// which is why clearing a category means sending <c>general</c> rather than <c>null</c>.
    /// </summary>
    [Fact]
    public async Task An_edit_omitting_the_category_leaves_it_unchanged()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var expenseId = await CreateExpenseAsync(group, category: "groceries");

        (await group.Owner.UpdateExpenseAsync(group.Id, expenseId, new { description = "Lunch" }))
            .EnsureSuccessStatusCode();

        Assert.Equal(ExpenseCategory.Groceries, await StoredCategoryAsync(expenseId));
    }

    [Fact]
    public async Task An_edit_clears_a_category_by_sending_general()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var expenseId = await CreateExpenseAsync(group, category: "groceries");

        (await group.Owner.UpdateExpenseAsync(group.Id, expenseId, new { category = "general" }))
            .EnsureSuccessStatusCode();

        Assert.Equal(ExpenseCategory.General, await StoredCategoryAsync(expenseId));
    }

    [Fact]
    public async Task Update_refuses_the_payment_category()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var expenseId = await CreateExpenseAsync(group, category: "groceries");

        var response = await group.Owner.UpdateExpenseAsync(group.Id, expenseId, new { category = "payment" });

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.BadRequest);
        Assert.Equal(ExpenseCategory.Groceries, await StoredCategoryAsync(expenseId));
    }

    [Fact]
    public async Task A_settlement_carries_the_payment_category()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();
        await group.CreateExpenseAsync(amount: 20m, share: 10m);
        await factory.WaitForProcessedAsync();

        var settlementId = await group.SettleAsync(5m);

        Assert.Equal(ExpenseCategory.Payment, await StoredCategoryAsync(settlementId));
    }

    [Fact]
    public async Task A_category_sent_to_the_settle_route_is_coerced_to_payment()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();
        await group.CreateExpenseAsync(amount: 20m, share: 10m);
        await factory.WaitForProcessedAsync();

        (await group.Guest.SettleUpAsync(group.Id, new
        {
            withUserId = group.OwnerId,
            amount = 5m,
            category = "groceries"
        })).EnsureSuccessStatusCode();

        var settlementId = await factory.UseDbAsync(db => db.Expense
            .Where(e => e.GroupId == group.Id && e.Type == ExpenseType.Payment)
            .OrderByDescending(e => e.Id)
            .Select(e => e.Id)
            .FirstAsync());

        Assert.Equal(ExpenseCategory.Payment, await StoredCategoryAsync(settlementId));
    }

    [Fact]
    public async Task A_category_sent_to_the_settlement_edit_is_coerced_to_payment()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();
        await group.CreateExpenseAsync(amount: 20m, share: 10m);
        await factory.WaitForProcessedAsync();

        var settlementId = await group.SettleAsync(5m);
        await factory.WaitForProcessedAsync();

        (await group.Guest.UpdateSettlementAsync(group.Id, settlementId, new
        {
            amount = 4m,
            category = "groceries"
        })).EnsureSuccessStatusCode();

        Assert.Equal(ExpenseCategory.Payment, await StoredCategoryAsync(settlementId));
    }

    /// <summary>
    /// Coercion, not refusal: the settlement requests carry no category field, so even a
    /// token the enum has never heard of is dropped rather than answered with a 400.
    /// </summary>
    [Fact]
    public async Task An_unknown_category_sent_to_the_settle_route_is_dropped()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();
        await group.CreateExpenseAsync(amount: 20m, share: 10m);
        await factory.WaitForProcessedAsync();

        var response = await group.Guest.SettleUpAsync(group.Id, new
        {
            withUserId = group.OwnerId,
            amount = 5m,
            category = "spaceship"
        });

        response.EnsureSuccessStatusCode();
    }

    /// <summary>
    /// The category guard runs once the row is resolved, like every other guard on the
    /// update path — otherwise a category nobody may send masks the missing expense.
    /// </summary>
    [Fact]
    public async Task An_edit_of_a_missing_expense_answers_404_even_with_the_payment_category()
    {
        var group = await GroupFixture.CreateAsync(factory);

        var response = await group.Owner.UpdateExpenseAsync(group.Id, 987654, new { category = "payment" });

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.NotFound);
    }

    private async Task<int> CreateExpenseAsync(GroupFixture group, string category)
    {
        var response = await group.Owner.CreateExpenseAsync(group.Id, Expense(group, category));
        response.EnsureSuccessStatusCode();

        return (await group.Owner.ReadJsonAsync(response)).GetProperty("id").GetInt32();
    }

    private static object Expense(GroupFixture group, string category) => new
    {
        paidBy = group.OwnerId,
        amount = 20m,
        description = "Dinner",
        splitMode = "equal",
        category,
        splits = new[]
        {
            new { userId = group.OwnerId, amount = 10m },
            new { userId = group.GuestId, amount = 10m }
        }
    };

    private Task<ExpenseCategory> StoredCategoryAsync(int expenseId) =>
        factory.UseDbAsync(db => db.Expense
            .Where(e => e.Id == expenseId)
            .Select(e => e.Category)
            .FirstAsync());
}
