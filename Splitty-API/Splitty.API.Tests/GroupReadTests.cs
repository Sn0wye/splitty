using System.Net;
using System.Net.Http.Json;
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
        var user = await owner.RegisterAsync();
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
    public async Task Non_member_receives_404()
    {
        var owner = ApiClient.Create(_factory);
        var ownerUser = await owner.RegisterAsync();
        owner = ApiClient.Create(_factory, ownerUser.Token);
        var groupId = await owner.CreateGroupAsync();

        var stranger = ApiClient.Create(_factory);
        var strangerUser = await stranger.RegisterAsync();
        stranger = ApiClient.Create(_factory, strangerUser.Token);

        var response = await stranger.GetGroupAsync(groupId);

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Missing_group_receives_404()
    {
        var client = ApiClient.Create(_factory);
        var user = await client.RegisterAsync();
        client = ApiClient.Create(_factory, user.Token);

        var response = await client.GetGroupAsync(int.MaxValue);

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Missing_group_and_non_member_responses_are_indistinguishable()
    {
        var owner = ApiClient.Create(_factory);
        var ownerUser = await owner.RegisterAsync();
        owner = ApiClient.Create(_factory, ownerUser.Token);
        var groupId = await owner.CreateGroupAsync();

        var stranger = ApiClient.Create(_factory);
        var strangerUser = await stranger.RegisterAsync();
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
