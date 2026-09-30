using System.Net;
using System.Net.Http.Json;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Splitty.DTO.Response;
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
        var ownerUser = await owner.SignInAsync();
        owner = ApiClient.Create(_factory, ownerUser.Token);
        var groupId = await owner.CreateGroupAsync("Dinner");
        var code = await owner.CreateInviteAsync(groupId);

        var guest = ApiClient.Create(_factory);
        var guestUser = await guest.SignInAsync();
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
        var ownerUser = await ApiClient.Create(_factory).SignInAsync();
        var owner = ApiClient.Create(_factory, ownerUser.Token);
        var groupId = await owner.CreateGroupAsync("Dinner");
        var code = await owner.CreateInviteAsync(groupId);

        await using var factory = _factory.WithWebHostBuilder(builder =>
        {
            builder.ConfigureTestServices(services =>
            {
                services.AddScoped<IGroupReadModel>(sp =>
                    new NullGroupReadModel(ActivatorUtilities.CreateInstance<GroupReadModel>(sp)));
            });
        });

        var guest = ApiClient.Create(factory);
        var guestUser = await guest.SignInAsync();
        guest = ApiClient.Create(factory, guestUser.Token);

        var response = await guest.AcceptInviteAsync(code);

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.NotFound);
    }

    private sealed class NullGroupReadModel(IGroupReadModel inner) : IGroupReadModel
    {
        public Task<GroupDTO?> GetGroupAsync(int groupId, int userId) =>
            Task.FromResult<GroupDTO?>(null);

        public Task<List<GroupDTO>> GetGroupsByUserId(int userId) => inner.GetGroupsByUserId(userId);
        public Task<List<ExpenseResponse>> GetExpensesAsync(int groupId, int userId) => inner.GetExpensesAsync(groupId, userId);
        public Task<ExpenseResponse> GetExpenseAsync(int groupId, int expenseId, int userId) => inner.GetExpenseAsync(groupId, expenseId, userId);
        public Task<bool> GroupExistsAsync(int groupId) => inner.GroupExistsAsync(groupId);
        public Task<bool> IsMemberAsync(int groupId, int userId) => inner.IsMemberAsync(groupId, userId);
        public Task<decimal> GetMemberNetAsync(int groupId, int userId) => inner.GetMemberNetAsync(groupId, userId);
    }
}
