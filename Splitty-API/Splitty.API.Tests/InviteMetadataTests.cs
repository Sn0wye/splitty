using System.Net;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Splitty.Infrastructure;

namespace Splitty.API.Tests;

[Collection(nameof(ApiCollection))]
public sealed class InviteMetadataTests
{
    private readonly ApiFactory _factory;

    public InviteMetadataTests(ApiFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task Checking_a_valid_code_describes_the_group_and_the_inviter()
    {
        var owner = await SignInAsync(name: "Grace Hopper");
        var groupId = await owner.Client.CreateGroupAsync("Beach Trip");
        var code = await owner.Client.CreateInviteAsync(groupId);

        var guest = await SignInAsync();

        var response = await guest.Client.GetInviteAsync(code);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await guest.Client.ReadJsonAsync(response);
        Assert.Equal("Beach Trip", body.GetProperty("groupName").GetString());
        Assert.Equal(1, body.GetProperty("memberCount").GetInt32());
        Assert.Equal("Grace Hopper", body.GetProperty("createdByName").GetString());
        Assert.False(body.GetProperty("alreadyMember").GetBoolean());
    }

    [Fact]
    public async Task Checking_a_code_does_not_consume_a_use()
    {
        var owner = await SignInAsync();
        var groupId = await owner.Client.CreateGroupAsync();
        var code = await owner.Client.CreateInviteAsync(groupId, maxUses: 1);

        var guest = await SignInAsync();

        var check = await guest.Client.GetInviteAsync(code);
        Assert.Equal(HttpStatusCode.OK, check.StatusCode);

        var accept = await guest.Client.AcceptInviteAsync(code);
        Assert.Equal(HttpStatusCode.OK, accept.StatusCode);
    }

    [Fact]
    public async Task Checking_an_expired_code_returns_410()
    {
        var owner = await SignInAsync();
        var groupId = await owner.Client.CreateGroupAsync();
        var code = await owner.Client.CreateInviteAsync(groupId);
        await ExpireInviteAsync(code);

        var guest = await SignInAsync();

        var response = await guest.Client.GetInviteAsync(code);

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.Gone);
    }

    [Fact]
    public async Task Checking_an_exhausted_code_returns_409()
    {
        var owner = await SignInAsync();
        var groupId = await owner.Client.CreateGroupAsync();
        var code = await owner.Client.CreateInviteAsync(groupId, maxUses: 1);

        var first = await SignInAsync();
        var joined = await first.Client.AcceptInviteAsync(code);
        Assert.Equal(HttpStatusCode.OK, joined.StatusCode);

        var second = await SignInAsync();
        var response = await second.Client.GetInviteAsync(code);

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task A_member_checking_an_exhausted_code_gets_the_flag_not_an_error()
    {
        var owner = await SignInAsync();
        var groupId = await owner.Client.CreateGroupAsync();
        var code = await owner.Client.CreateInviteAsync(groupId, maxUses: 1);

        var joiner = await SignInAsync();
        var joined = await joiner.Client.AcceptInviteAsync(code);
        Assert.Equal(HttpStatusCode.OK, joined.StatusCode);

        // Accepting an exhausted code as a member answers 200, so checking one must too.
        var response = await joiner.Client.GetInviteAsync(code);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await joiner.Client.ReadJsonAsync(response);
        Assert.True(body.GetProperty("alreadyMember").GetBoolean());
    }

    [Fact]
    public async Task Checking_an_unknown_code_returns_404()
    {
        var guest = await SignInAsync();

        var response = await guest.Client.GetInviteAsync("ZZZZZ1");

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Checking_a_code_for_a_group_the_caller_is_in_sets_the_already_member_flag()
    {
        var owner = await SignInAsync();
        var groupId = await owner.Client.CreateGroupAsync();
        var code = await owner.Client.CreateInviteAsync(groupId);

        var response = await owner.Client.GetInviteAsync(code);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await owner.Client.ReadJsonAsync(response);
        Assert.True(body.GetProperty("alreadyMember").GetBoolean());
    }

    [Fact]
    public async Task Checking_a_code_requires_authentication()
    {
        var anonymous = ApiClient.Create(_factory);

        var response = await anonymous.GetInviteAsync("ZZZZZ1");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Member_count_reflects_a_member_who_has_since_left()
    {
        var owner = await SignInAsync();
        var groupId = await owner.Client.CreateGroupAsync();
        var code = await owner.Client.CreateInviteAsync(groupId);

        var joiner = await SignInAsync();
        var joined = await joiner.Client.AcceptInviteAsync(code);
        Assert.Equal(HttpStatusCode.OK, joined.StatusCode);
        var left = await joiner.Client.LeaveGroupAsync(groupId);
        Assert.Equal(HttpStatusCode.NoContent, left.StatusCode);

        var guest = await SignInAsync();
        var response = await guest.Client.GetInviteAsync(code);

        var body = await guest.Client.ReadJsonAsync(response);
        Assert.Equal(1, body.GetProperty("memberCount").GetInt32());
    }

    [Fact]
    public async Task Checking_a_code_counts_against_the_redemption_rate_limit()
    {
        var owner = await SignInAsync();
        var groupId = await owner.Client.CreateGroupAsync();
        var code = await owner.Client.CreateInviteAsync(groupId);

        var guest = await SignInAsync();

        // The redemption policy allows 10 requests per window; spending the whole
        // budget on metadata checks must leave none for an accept.
        for (var i = 0; i < 10; i++)
        {
            var check = await guest.Client.GetInviteAsync(code);
            Assert.Equal(HttpStatusCode.OK, check.StatusCode);
        }

        var accept = await guest.Client.AcceptInviteAsync(code);

        Assert.Equal(HttpStatusCode.TooManyRequests, accept.StatusCode);
    }

    private async Task<(ApiClient Client, SignedInUser User)> SignInAsync(string name = "Ada")
    {
        var client = ApiClient.Create(_factory);
        var user = await client.SignInAsync(name: name);
        return (ApiClient.Create(_factory, user.Token), user);
    }

    /// Backdates the invite in the database; the API refuses to create one already expired.
    private async Task ExpireInviteAsync(string code)
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        await db.Invite
            .Where(i => i.Code == code)
            .ExecuteUpdateAsync(s => s.SetProperty(i => i.ExpiresAt, DateTime.UtcNow.AddMinutes(-1)));
    }
}
