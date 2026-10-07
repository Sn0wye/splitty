using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Splitty.DTO.Response;

namespace Splitty.API.Tests;

[Collection(nameof(ApiCollection))]
public sealed class GroupProjectionTests(ApiFactory factory)
{
    [Theory]
    [InlineData("uploaded")]
    [InlineData("provider")]
    [InlineData("generated")]
    public async Task Every_expense_response_resolves_payer_and_participant_avatars(string source)
    {
        var providerUrl = source == "generated" ? "" : "https://provider.test/old.jpg";
        var user = await ApiClient.Create(factory).SignInAsync(name: "Payer", picture: providerUrl);
        var client = ApiClient.Create(factory, user.Token);
        var groupId = await client.CreateGroupAsync();
        string expected;
        if (source == "uploaded")
        {
            var upload = await client.ReadJsonAsync(await client.CreateAvatarUploadAsync());
            var key = upload.GetProperty("key").GetString()!;
            factory.AvatarStorage.PutObject(key);
            (await client.UpdateProfileAsync(new { avatarKey = key })).EnsureSuccessStatusCode();
            expected = $"{FakeAvatarStorage.PublicBase}/{key}";
        }
        else
        {
            expected = source == "provider" ? providerUrl
                : $"https://api.dicebear.com/11.x/line-face/png?seed={user.Id}&size=256";
        }

        var created = await client.ReadJsonAsync(await client.CreateExpenseAsync(groupId, new
        {
            paidBy = user.Id, amount = 10m, description = "Lunch", splitMode = "equal",
            splits = new[] { new { userId = user.Id, amount = 10m } }
        }));
        var id = created.GetProperty("id").GetInt32();
        var updated = await client.ReadJsonAsync(await client.UpdateExpenseAsync(groupId, id, new { description = "Dinner" }));
        var single = await client.ReadJsonAsync(await client.GetExpenseAsync(groupId, id));
        var list = await client.ReadJsonAsync(await client.GetExpensesAsync(groupId));
        foreach (var expense in new[] { created, updated, single, Assert.Single(list.EnumerateArray()) })
        {
            AssertPublicResponse(expense);
            foreach (var responseUser in new[]
                     { expense.GetProperty("paidByUser"), Assert.Single(expense.GetProperty("splits").EnumerateArray()).GetProperty("user") })
            {
                GroupResponseContractTests.AssertKeys(responseUser, "id", "name", "email", "avatarUrl", "createdAt", "updatedAt");
                Assert.Equal(expected, responseUser.GetProperty("avatarUrl").GetString());
            }
            if (source == "uploaded") Assert.DoesNotContain(providerUrl, expense.GetRawText());
        }
    }

    [Fact]
    public async Task Group_writes_return_the_read_shape_without_bookkeeping_or_user_entities()
    {
        const string providerUrl = "https://provider.test/old-group-picture.jpg";
        var user = await ApiClient.Create(factory).SignInAsync(picture: providerUrl);
        var client = ApiClient.Create(factory, user.Token);
        var upload = await client.ReadJsonAsync(await client.CreateAvatarUploadAsync());
        var key = upload.GetProperty("key").GetString()!;
        factory.AvatarStorage.PutObject(key);
        (await client.UpdateProfileAsync(new { avatarKey = key })).EnsureSuccessStatusCode();
        var created = await client.ReadJsonAsync(await client.Http.PostAsJsonAsync("/group", new { name = "Trip" }));
        var id = created.GetProperty("id").GetInt32();
        var renamed = await client.ReadJsonAsync(await client.UpdateGroupAsync(id, new { name = "Cabin" }));
        var single = await client.ReadJsonAsync(await client.GetGroupAsync(id));
        var list = await client.ReadJsonAsync(await client.Http.GetAsync("/group"));
        foreach (var group in new[] { created, renamed, single, Assert.Single(list.EnumerateArray()) })
        {
            GroupResponseContractTests.AssertKeys(group, "id", "name", "description", "createdAt", "netBalance", "members");
            AssertPublicResponse(group);
            Assert.Equal(0m, group.GetProperty("netBalance").GetDecimal());
            Assert.Equal(JsonValueKind.Null, group.GetProperty("description").ValueKind);
            var member = Assert.Single(group.GetProperty("members").EnumerateArray());
            GroupResponseContractTests.AssertKeys(member, "id", "userId", "name", "email", "avatarUrl");
            Assert.Equal(user.Id, member.GetProperty("userId").GetInt32());
            Assert.Equal($"{FakeAvatarStorage.PublicBase}/{key}", member.GetProperty("avatarUrl").GetString());
            Assert.DoesNotContain(providerUrl, group.GetRawText());
        }
    }

    [Fact]
    public async Task Group_nets_sum_only_the_callers_rows_in_that_group_and_settle_to_zero()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();
        await group.CreateExpenseAsync(20m, 10m);
        await factory.WaitForProcessedAsync();
        var third = await ApiClient.Create(factory).SignInAsync();
        var thirdClient = ApiClient.Create(factory, third.Token);
        (await thirdClient.AcceptInviteAsync(await group.Owner.CreateInviteAsync(group.Id))).EnsureSuccessStatusCode();
        (await group.Owner.CreateExpenseAsync(group.Id, new
        {
            paidBy = group.OwnerId, amount = 8m, description = "Another peer", splitMode = "equal",
            splits = new[] { new { userId = group.OwnerId, amount = 4m }, new { userId = third.Id, amount = 4m } }
        })).EnsureSuccessStatusCode();
        await factory.WaitForProcessedAsync();
        // The same members in another group with the debt pointing the other way.
        var otherId = await group.Owner.CreateGroupAsync();
        (await group.Guest.AcceptInviteAsync(await group.Owner.CreateInviteAsync(otherId))).EnsureSuccessStatusCode();
        (await group.Guest.CreateExpenseAsync(otherId, new
        {
            paidBy = group.GuestId, amount = 14m, description = "Other group", splitMode = "equal",
            splits = new[] { new { userId = group.OwnerId, amount = 7m }, new { userId = group.GuestId, amount = 7m } }
        })).EnsureSuccessStatusCode();
        await factory.WaitForProcessedAsync();

        await AssertNetAsync(group.Owner, group.Id, 14m);
        await AssertNetAsync(group.Guest, group.Id, -10m);
        await AssertNetAsync(thirdClient, group.Id, -4m);
        await AssertNetAsync(group.Owner, otherId, -7m);
        await AssertNetAsync(group.Guest, otherId, 7m);
        await group.SettleAsync(10m);
        await factory.WaitForProcessedAsync();
        await AssertNetAsync(group.Owner, group.Id, 4m);
        (await thirdClient.SettleUpAsync(group.Id, new { withUserId = group.OwnerId, amount = 4m })).EnsureSuccessStatusCode();
        await factory.WaitForProcessedAsync();
        await AssertNetAsync(group.Owner, group.Id, 0m);
        await AssertNetAsync(group.Guest, group.Id, 0m);
    }

    [Fact]
    public async Task Changing_the_payer_returns_the_new_payer_user()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var id = await group.CreateExpenseAsync(20m, 10m);
        var updated = await group.Owner.ReadJsonAsync(await group.Owner.UpdateExpenseAsync(group.Id, id,
            new { paidBy = group.GuestId }));

        Assert.Equal(group.GuestId, updated.GetProperty("paidBy").GetInt32());
        var payer = updated.GetProperty("paidByUser");
        Assert.Equal(group.GuestId, payer.GetProperty("id").GetInt32());
        Assert.Equal("Guest", payer.GetProperty("name").GetString());
        Assert.Contains($"seed={group.GuestId}", payer.GetProperty("avatarUrl").GetString()!);
    }

    [Fact]
    public async Task Settlement_reads_keep_the_payment_shape_after_an_edit_and_a_member_leaves()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();
        await group.CreateExpenseAsync(20m, 10m);
        await factory.WaitForProcessedAsync();
        var id = await group.SettleAsync(6m);
        await factory.WaitForProcessedAsync();
        var date = new DateTime(2026, 3, 15, 12, 0, 0, DateTimeKind.Utc);
        Assert.Equal(HttpStatusCode.NoContent,
            (await group.Owner.UpdateSettlementAsync(group.Id, id, new { amount = 10m, date })).StatusCode);
        await factory.WaitForProcessedAsync();
        (await group.Guest.LeaveGroupAsync(group.Id)).EnsureSuccessStatusCode();

        var single = await group.Owner.ReadJsonAsync(await group.Owner.GetExpenseAsync(group.Id, id));
        var list = await group.Owner.ReadJsonAsync(await group.Owner.GetExpensesAsync(group.Id));
        foreach (var payment in new[] { single, list.EnumerateArray().Single(e => e.GetProperty("id").GetInt32() == id) })
        {
            AssertPublicResponse(payment);
            Assert.Equal("payment", payment.GetProperty("type").GetString());
            Assert.Equal("payment", payment.GetProperty("category").GetString());
            Assert.Equal(JsonValueKind.Null, payment.GetProperty("splitMode").ValueKind);
            Assert.Equal(10m, payment.GetProperty("amount").GetDecimal());
            Assert.Equal(date, payment.GetProperty("date").GetDateTime());
            Assert.Equal(group.GuestId, payment.GetProperty("paidByUser").GetProperty("id").GetInt32());
            var splits = payment.GetProperty("splits").EnumerateArray().ToList();
            Assert.Equal(2, splits.Count);
            Assert.Equal(10m, splits.Single(s => s.GetProperty("userId").GetInt32() == group.GuestId).GetProperty("amount").GetDecimal());
            Assert.Equal(-10m, splits.Single(s => s.GetProperty("userId").GetInt32() == group.OwnerId).GetProperty("amount").GetDecimal());
            foreach (var split in splits)
            {
                Assert.Equal(JsonValueKind.Null, split.GetProperty("percentage").ValueKind);
                GroupResponseContractTests.AssertKeys(split.GetProperty("user"), "id", "name", "email", "avatarUrl", "createdAt", "updatedAt");
            }
        }
    }

    [Fact]
    public async Task Removing_or_leaving_still_requires_a_zero_net_and_the_last_member_deletes_the_group()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();
        await group.CreateExpenseAsync(20m, 10m);
        await factory.WaitForProcessedAsync();
        var removal = await group.Owner.Http.DeleteAsync($"/group/{group.Id}/members/{group.GuestId}");
        Assert.Equal(HttpStatusCode.Conflict, removal.StatusCode);
        Assert.Equal(ErrorCode.OutstandingBalance, (await ErrorResponseAssertions.ReadErrorAsync(removal)).Code);
        Assert.Equal(HttpStatusCode.Conflict, (await group.Guest.LeaveGroupAsync(group.Id)).StatusCode);
        await group.SettleAsync(10m);
        await factory.WaitForProcessedAsync();
        Assert.Equal(HttpStatusCode.NoContent,
            (await group.Owner.Http.DeleteAsync($"/group/{group.Id}/members/{group.GuestId}")).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await group.Owner.LeaveGroupAsync(group.Id)).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await group.Owner.GetGroupAsync(group.Id)).StatusCode);
    }

    private static async Task AssertNetAsync(ApiClient client, int groupId, decimal expected)
    {
        var single = await client.ReadJsonAsync(await client.GetGroupAsync(groupId));
        Assert.Equal(expected, single.GetProperty("netBalance").GetDecimal());
        var list = await client.ReadJsonAsync(await client.Http.GetAsync("/group"));
        var group = list.EnumerateArray().Single(g => g.GetProperty("id").GetInt32() == groupId);
        Assert.Equal(expected, group.GetProperty("netBalance").GetDecimal());
    }

    internal static void AssertPublicResponse(JsonElement value)
    {
        if (value.ValueKind == JsonValueKind.Object)
        {
            foreach (var property in value.EnumerateObject())
            {
                Assert.DoesNotContain(property.Name, new[] { "balancesPending", "balancesPendingGeneration", "avatarKey", "providerUrl" });
                AssertPublicResponse(property.Value);
            }
        }
        else if (value.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in value.EnumerateArray()) AssertPublicResponse(item);
        }
    }
}
