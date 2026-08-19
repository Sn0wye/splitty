using System.Net;
using System.Net.Http.Json;
using Splitty.DTO.Internal;

namespace Splitty.API.Tests;

[Collection(nameof(ApiCollection))]
public sealed class InviteAcceptanceTests
{
    private readonly ApiFactory _factory;

    public InviteAcceptanceTests(ApiFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task Accepting_an_invite_returns_the_joined_group()
    {
        var owner = ApiClient.Create(_factory);
        var ownerUser = await owner.RegisterAsync();
        owner = ApiClient.Create(_factory, ownerUser.Token);
        var groupId = await owner.CreateGroupAsync("Dinner");
        var code = await owner.CreateInviteAsync(groupId);

        var guest = ApiClient.Create(_factory);
        var guestUser = await guest.RegisterAsync();
        guest = ApiClient.Create(_factory, guestUser.Token);

        var response = await guest.AcceptInviteAsync(code);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var group = await response.Content.ReadFromJsonAsync<GroupDTO>();
        Assert.NotNull(group);
        Assert.Equal(groupId, group!.Id);
        Assert.Contains(group.Members, m => m.UserId == guestUser.Id);
    }
}
