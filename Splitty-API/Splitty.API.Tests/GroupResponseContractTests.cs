using System.Net.Http.Json;
using System.Text.Json;

namespace Splitty.API.Tests;

[Collection(nameof(ApiCollection))]
public sealed class GroupResponseContractTests(ApiFactory factory)
{
    [Fact]
    public async Task Group_reads_and_writes_keep_the_fields_the_client_decodes()
    {
        var user = await ApiClient.Create(factory).SignInAsync(name: "Ada");
        var client = ApiClient.Create(factory, user.Token);
        var created = await client.ReadJsonAsync(await client.Http.PostAsJsonAsync("/group",
            new { name = "Cabin", description = "Weekend" }));
        var id = created.GetProperty("id").GetInt32();
        AssertGroupIdentity(created, id, "Cabin", "Weekend");

        var single = await client.ReadJsonAsync(await client.GetGroupAsync(id));
        AssertGroupRead(single, user, id, "Cabin", "Weekend", 0m);
        var list = await client.ReadJsonAsync(await client.Http.GetAsync("/group"));
        AssertGroupRead(Assert.Single(list.EnumerateArray()), user, id, "Cabin", "Weekend", 0m);

        var renamed = await client.ReadJsonAsync(await client.UpdateGroupAsync(id,
            new { name = "Lake", description = "Summer" }));
        AssertGroupIdentity(renamed, id, "Lake", "Summer");
        Assert.Equal(single.GetProperty("createdAt").GetDateTime(), renamed.GetProperty("createdAt").GetDateTime());
    }

    [Fact]
    public async Task Expense_reads_and_writes_keep_scalars_users_and_percentage_splits()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var third = await ApiClient.Create(factory).SignInAsync(name: "Third");
        (await ApiClient.Create(factory, third.Token).AcceptInviteAsync(await group.Owner.CreateInviteAsync(group.Id)))
            .EnsureSuccessStatusCode();
        var date = new DateTime(2026, 3, 10, 12, 0, 0, DateTimeKind.Utc);
        // The payer is not a participant. Both participants' user objects must still arrive.
        var created = await group.Owner.ReadJsonAsync(await group.Owner.CreateExpenseAsync(group.Id, new
        {
            paidBy = group.OwnerId, amount = 40m, description = "Groceries", category = "groceries",
            splitMode = "percentage", date,
            splits = new[]
            {
                new { userId = group.GuestId, amount = 30m, percentage = 75m },
                new { userId = third.Id, amount = 10m, percentage = 25m }
            }
        }));
        var id = created.GetProperty("id").GetInt32();
        AssertExpense(created, id, group.Id, group.OwnerId, date, "Groceries");
        AssertSplits(created, group.GuestId, third.Id);

        var read = await group.Guest.ReadJsonAsync(await group.Guest.GetExpenseAsync(group.Id, id));
        AssertExpense(read, id, group.Id, group.OwnerId, date, "Groceries");
        AssertSplits(read, group.GuestId, third.Id);
        Assert.Equal(created.GetProperty("createdAt").GetDateTime(), read.GetProperty("createdAt").GetDateTime());
        var list = await group.Guest.ReadJsonAsync(await group.Guest.GetExpensesAsync(group.Id));
        var row = Assert.Single(list.EnumerateArray());
        AssertExpense(row, id, group.Id, group.OwnerId, date, "Groceries");
        AssertSplits(row, group.GuestId, third.Id);

        var updated = await group.Guest.ReadJsonAsync(await group.Guest.UpdateExpenseAsync(group.Id, id,
            new { description = "Weekly groceries" }));
        AssertExpense(updated, id, group.Id, group.OwnerId, date, "Weekly groceries");
        AssertSplits(updated, group.GuestId, third.Id);
        Assert.Equal(created.GetProperty("createdAt").GetDateTime(), updated.GetProperty("createdAt").GetDateTime());
    }

    private static void AssertGroupIdentity(JsonElement group, int id, string name, string description)
    {
        Assert.Equal(id, group.GetProperty("id").GetInt32());
        Assert.Equal(name, group.GetProperty("name").GetString());
        Assert.Equal(description, group.GetProperty("description").GetString());
        Assert.NotEqual(default, group.GetProperty("createdAt").GetDateTime());
    }

    private static void AssertGroupRead(JsonElement group, SignedInUser user, int id, string name, string description, decimal net)
    {
        AssertKeys(group, "id", "name", "description", "createdAt", "netBalance", "members");
        AssertGroupIdentity(group, id, name, description);
        Assert.Equal(net, group.GetProperty("netBalance").GetDecimal());
        var member = Assert.Single(group.GetProperty("members").EnumerateArray());
        AssertKeys(member, "id", "userId", "name", "email", "avatarUrl");
        Assert.True(member.GetProperty("id").GetInt32() > 0);
        Assert.Equal(user.Id, member.GetProperty("userId").GetInt32());
        Assert.Equal(user.Name, member.GetProperty("name").GetString());
        Assert.Equal(user.Email, member.GetProperty("email").GetString());
        Assert.Contains($"seed={user.Id}", member.GetProperty("avatarUrl").GetString()!);
    }

    private static void AssertExpense(JsonElement expense, int id, int groupId, int payerId, DateTime date, string description)
    {
        AssertKeys(expense, "id", "groupId", "paidBy", "amount", "description", "type", "splitMode",
            "category", "date", "createdAt", "updatedAt", "recurringExpenseId", "repeat", "paidByUser", "splits");
        Assert.Equal(id, expense.GetProperty("id").GetInt32());
        Assert.Equal(groupId, expense.GetProperty("groupId").GetInt32());
        Assert.Equal(payerId, expense.GetProperty("paidBy").GetInt32());
        Assert.Equal(40m, expense.GetProperty("amount").GetDecimal());
        Assert.Equal(description, expense.GetProperty("description").GetString());
        Assert.Equal("expense", expense.GetProperty("type").GetString());
        Assert.Equal("percentage", expense.GetProperty("splitMode").GetString());
        Assert.Equal("groceries", expense.GetProperty("category").GetString());
        Assert.Equal(date, expense.GetProperty("date").GetDateTime());
        Assert.NotEqual(default, expense.GetProperty("createdAt").GetDateTime());
        Assert.NotEqual(default, expense.GetProperty("updatedAt").GetDateTime());
        AssertUser(expense.GetProperty("paidByUser"), payerId, "Owner");
    }

    private static void AssertSplits(JsonElement expense, int guestId, int thirdId)
    {
        var splits = expense.GetProperty("splits").EnumerateArray().ToList();
        Assert.Equal(2, splits.Count);
        foreach (var split in splits)
        {
            AssertKeys(split, "id", "expenseId", "userId", "amount", "percentage", "user");
            Assert.True(split.GetProperty("id").GetInt32() > 0);
            Assert.Equal(expense.GetProperty("id").GetInt32(), split.GetProperty("expenseId").GetInt32());
            var userId = split.GetProperty("userId").GetInt32();
            Assert.Contains(userId, new[] { guestId, thirdId });
            Assert.Equal(userId == guestId ? 30m : 10m, split.GetProperty("amount").GetDecimal());
            Assert.Equal(userId == guestId ? 75m : 25m, split.GetProperty("percentage").GetDecimal());
            AssertUser(split.GetProperty("user"), userId, userId == guestId ? "Guest" : "Third");
        }
    }

    private static void AssertUser(JsonElement user, int id, string name)
    {
        AssertKeys(user, "id", "name", "email", "avatarUrl", "createdAt", "updatedAt");
        Assert.Equal(id, user.GetProperty("id").GetInt32());
        Assert.Equal(name, user.GetProperty("name").GetString());
        Assert.NotEmpty(user.GetProperty("email").GetString()!);
        Assert.NotEqual(default, user.GetProperty("createdAt").GetDateTime());
        Assert.NotEqual(default, user.GetProperty("updatedAt").GetDateTime());
    }

    internal static void AssertKeys(JsonElement value, params string[] keys) =>
        Assert.Equal(keys.Order(), value.EnumerateObject().Select(p => p.Name).Order());
}
