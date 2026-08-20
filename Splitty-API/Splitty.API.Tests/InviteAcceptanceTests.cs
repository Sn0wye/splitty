using System.Net;
using System.Net.Http.Json;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Splitty.Domain.Entities;
using Splitty.DTO.Internal;
using Splitty.Service;
using Splitty.Service.Interfaces;

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

    [Fact]
    public async Task Accepting_an_invite_returns_404_when_the_joined_group_cannot_be_read()
    {
        await using var factory = _factory.WithWebHostBuilder(builder =>
        {
            builder.ConfigureTestServices(services =>
            {
                services.AddScoped<IGroupService>(sp =>
                    new NullGroupReadService(ActivatorUtilities.CreateInstance<GroupService>(sp)));
            });
        });

        var owner = ApiClient.Create(factory);
        var ownerUser = await owner.RegisterAsync();
        owner = ApiClient.Create(factory, ownerUser.Token);
        var groupId = await owner.CreateGroupAsync("Dinner");
        var code = await owner.CreateInviteAsync(groupId);

        var guest = ApiClient.Create(factory);
        var guestUser = await guest.RegisterAsync();
        guest = ApiClient.Create(factory, guestUser.Token);

        var response = await guest.AcceptInviteAsync(code);

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.NotFound);
    }

    private sealed class NullGroupReadService(IGroupService inner) : IGroupService
    {
        public Task<Group> CreateAsync(int userId, string name, string? description) =>
            inner.CreateAsync(userId, name, description);

        public Task<GroupDTO?> GetGroupAsync(int groupId, int userId) =>
            Task.FromResult<GroupDTO?>(null);

        public Task<List<GroupDTO>> GetGroupsByUserId(int userId) =>
            inner.GetGroupsByUserId(userId);

        public Task<Group> UpdateAsync(int groupId, int userId, string name, string? description) =>
            inner.UpdateAsync(groupId, userId, name, description);

        public Task<MembershipRemovalStatus> LeaveAsync(int groupId, int userId) =>
            inner.LeaveAsync(groupId, userId);

        public Task<MembershipRemovalStatus> RemoveMemberAsync(int groupId, int actorId, int targetUserId) =>
            inner.RemoveMemberAsync(groupId, actorId, targetUserId);

        public Task<bool> AreBalancesPendingAsync(int groupId) =>
            inner.AreBalancesPendingAsync(groupId);

        public Task<bool> IsMemberAsync(int groupId, int userId) =>
            inner.IsMemberAsync(groupId, userId);
    }
}
