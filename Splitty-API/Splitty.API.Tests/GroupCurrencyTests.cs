using System.Net;
using System.Net.Http.Json;

namespace Splitty.API.Tests;

/// <summary>
/// A group's currency is a label on its amounts (ADR 0007). Changing it converts nothing.
/// </summary>
[Collection(nameof(ApiCollection))]
public sealed class GroupCurrencyTests(ApiFactory factory)
{
    private async Task<ApiClient> SignedInAsync()
    {
        var user = await ApiClient.Create(factory).SignInAsync();
        return ApiClient.Create(factory, user.Token);
    }

    [Fact]
    public async Task A_group_created_without_a_currency_is_in_dollars()
    {
        var client = await SignedInAsync();

        var created = await client.ReadJsonAsync(await client.Http.PostAsJsonAsync("/group", new { name = "Trip" }));

        Assert.Equal("USD", created.GetProperty("currency").GetString());
    }

    [Fact]
    public async Task Reads_return_the_currency_the_group_was_created_with()
    {
        var client = await SignedInAsync();
        var created = await client.ReadJsonAsync(await client.Http.PostAsJsonAsync("/group",
            new { name = "Viagem", currency = "BRL" }));
        var id = created.GetProperty("id").GetInt32();

        var single = await client.ReadJsonAsync(await client.GetGroupAsync(id));
        var list = await client.ReadJsonAsync(await client.Http.GetAsync("/group"));

        Assert.Equal("BRL", created.GetProperty("currency").GetString());
        Assert.Equal("BRL", single.GetProperty("currency").GetString());
        Assert.Equal("BRL", Assert.Single(list.EnumerateArray()).GetProperty("currency").GetString());
    }

    [Fact]
    public async Task Changing_the_currency_relabels_amounts_without_converting_them()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await group.CreateExpenseAsync(amount: 20m, share: 10m);
        await factory.WaitForProcessedAsync();

        var updated = await group.Owner.ReadJsonAsync(
            await group.Owner.UpdateGroupAsync(group.Id, new { currency = "EUR" }));

        Assert.Equal("EUR", updated.GetProperty("currency").GetString());
        Assert.Equal("Trip", updated.GetProperty("name").GetString());
        var expense = Assert.Single(await group.ExpensesAsync());
        Assert.Equal(20m, expense.GetProperty("amount").GetDecimal());
        Assert.Equal(10m, (await group.Owner.ReadSummaryAsync(group.Id)).AmountOwedBy(group.OwnerId, group.GuestId));
    }

    [Fact]
    public async Task A_rename_keeps_the_currency()
    {
        var client = await SignedInAsync();
        var created = await client.ReadJsonAsync(await client.Http.PostAsJsonAsync("/group",
            new { name = "Trip", currency = "GBP" }));

        var renamed = await client.ReadJsonAsync(
            await client.UpdateGroupAsync(created.GetProperty("id").GetInt32(), new { name = "Holiday" }));

        Assert.Equal("GBP", renamed.GetProperty("currency").GetString());
    }

    public static TheoryData<object> UnlistedCurrencies => new()
    {
        "JPY",
        "usd dollars",
        99,
    };

    [Theory]
    [MemberData(nameof(UnlistedCurrencies))]
    public async Task Create_rejects_a_currency_outside_the_list(object currency)
    {
        var client = await SignedInAsync();

        var response = await client.Http.PostAsJsonAsync("/group", new { name = "Trip", currency });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Theory]
    [MemberData(nameof(UnlistedCurrencies))]
    public async Task Update_rejects_a_currency_outside_the_list(object currency)
    {
        var client = await SignedInAsync();
        var id = await client.CreateGroupAsync();

        var response = await client.UpdateGroupAsync(id, new { currency });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var group = await client.ReadJsonAsync(await client.GetGroupAsync(id));
        Assert.Equal("USD", group.GetProperty("currency").GetString());
    }
}
