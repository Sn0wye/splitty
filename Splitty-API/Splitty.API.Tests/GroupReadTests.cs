using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Splitty.DTO.Internal;
using Splitty.DTO.Response;

namespace Splitty.API.Tests;

[Collection(nameof(ApiCollection))]
public sealed class GroupReadTests
{
    private readonly ApiFactory _factory;

    public GroupReadTests(ApiFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task Member_receives_the_group()
    {
        var owner = ApiClient.Create(_factory);
        var user = await owner.SignInAsync();
        owner = ApiClient.Create(_factory, user.Token);
        var groupId = await owner.CreateGroupAsync("Cabin");

        var response = await owner.GetGroupAsync(groupId);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var group = await response.Content.ReadFromJsonAsync<GroupDTO>();
        Assert.NotNull(group);
        Assert.Equal(groupId, group!.Id);
        Assert.Equal("Cabin", group.Name);
    }

    [Fact]
    public async Task Last_activity_is_the_newest_date_or_created_at_and_null_without_rows()
    {
        var group = await GroupFixture.CreateAsync(_factory);
        var empty = await group.Owner.ReadJsonAsync(await group.Owner.GetGroupAsync(group.Id));
        Assert.Equal(JsonValueKind.Null, empty.GetProperty("lastActivityAt").ValueKind);

        // A later-dated row wins over a newer write dated in the past.
        var april = new DateTime(2026, 4, 2, 12, 0, 0, DateTimeKind.Utc);
        await group.CreateExpenseAsync(amount: 20m, share: 10m, date: april);
        await group.CreateExpenseAsync(amount: 20m, share: 10m, date: april.AddMonths(-1));
        var list = await group.Owner.ReadJsonAsync(await group.Owner.Http.GetAsync("/group"));
        var read = Assert.Single(list.EnumerateArray());
        Assert.Equal(april, read.GetProperty("lastActivityAt").GetDateTime());

        // An undated row reads as its CreatedAt, which is now and so newer than April.
        await group.CreateExpenseAsync(amount: 20m, share: 10m);
        read = await group.Owner.ReadJsonAsync(await group.Owner.GetGroupAsync(group.Id));
        Assert.True(read.GetProperty("lastActivityAt").GetDateTime() > april);
    }

    [Fact]
    public async Task Non_member_receives_404()
    {
        var owner = ApiClient.Create(_factory);
        var ownerUser = await owner.SignInAsync();
        owner = ApiClient.Create(_factory, ownerUser.Token);
        var groupId = await owner.CreateGroupAsync();

        var stranger = ApiClient.Create(_factory);
        var strangerUser = await stranger.SignInAsync();
        stranger = ApiClient.Create(_factory, strangerUser.Token);

        var response = await stranger.GetGroupAsync(groupId);

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Missing_group_receives_404()
    {
        var client = ApiClient.Create(_factory);
        var user = await client.SignInAsync();
        client = ApiClient.Create(_factory, user.Token);

        var response = await client.GetGroupAsync(int.MaxValue);

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Missing_group_and_non_member_responses_are_indistinguishable()
    {
        var owner = ApiClient.Create(_factory);
        var ownerUser = await owner.SignInAsync();
        owner = ApiClient.Create(_factory, ownerUser.Token);
        var groupId = await owner.CreateGroupAsync();

        var stranger = ApiClient.Create(_factory);
        var strangerUser = await stranger.SignInAsync();
        stranger = ApiClient.Create(_factory, strangerUser.Token);

        var missing = await stranger.GetGroupAsync(int.MaxValue);
        var hidden = await stranger.GetGroupAsync(groupId);

        Assert.Equal(HttpStatusCode.NotFound, missing.StatusCode);
        Assert.Equal(missing.StatusCode, hidden.StatusCode);

        var missingError = await missing.Content.ReadFromJsonAsync<ErrorResponse>();
        var hiddenError = await hidden.Content.ReadFromJsonAsync<ErrorResponse>();
        Assert.NotNull(missingError);
        Assert.NotNull(hiddenError);
        Assert.Equal(missingError!.StatusCode, hiddenError!.StatusCode);
        Assert.Equal(missingError.Message, hiddenError.Message);
        Assert.Equal(missingError.Details, hiddenError.Details);
    }
}
