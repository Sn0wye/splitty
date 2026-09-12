using System.Net;
using System.Net.Http.Json;
using System.Text.Json;

namespace Splitty.API.Tests;

[Collection(nameof(ApiCollection))]
public sealed class PeopleTests(ApiFactory factory)
{
    private static readonly JsonSerializerOptions Json = new() { PropertyNameCaseInsensitive = true };

    [Fact]
    public async Task A_peer_shared_across_two_groups_nets_across_both_with_a_per_group_breakdown()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();

        var secondGroupId = await group.Owner.CreateGroupAsync("Second");
        var code = await group.Owner.CreateInviteAsync(secondGroupId);
        (await group.Guest.AcceptInviteAsync(code)).EnsureSuccessStatusCode();

        // Owner fronts 20 in the first group, the guest fronts 30 in the second, so the
        // net only comes out right if both directions survive the aggregation.
        await group.CreateExpenseAsync(amount: 20m, share: 10m);
        await factory.WaitForProcessedAsync();

        (await group.Owner.CreateExpenseAsync(secondGroupId, new
        {
            paidBy = group.GuestId,
            amount = 30m,
            description = "Groceries",
            splitMode = "equal",
            splits = new[]
            {
                new { userId = group.OwnerId, amount = 15m },
                new { userId = group.GuestId, amount = 15m }
            }
        })).EnsureSuccessStatusCode();
        await factory.WaitForProcessedAsync();

        var people = await ReadPeopleAsync(group.Owner);

        var peer = Assert.Single(people.Peers);
        Assert.Equal(group.GuestId, peer.UserId);
        Assert.Equal("Guest", peer.Name);
        Assert.Equal(-5m, peer.NetAmount);
        Assert.Equal(2, peer.Groups.Count);
        Assert.Equal(10m, peer.Groups.Single(g => g.GroupId == group.Id).Amount);
        Assert.Equal(-15m, peer.Groups.Single(g => g.GroupId == secondGroupId).Amount);
    }

    [Fact]
    public async Task A_peer_settled_to_exactly_zero_still_appears()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();

        await group.CreateExpenseAsync(amount: 20m, share: 10m);
        await factory.WaitForProcessedAsync();

        await group.SettleAsync(10m);
        await factory.WaitForProcessedAsync();

        var people = await ReadPeopleAsync(group.Owner);

        var peer = Assert.Single(people.Peers);
        Assert.Equal(group.GuestId, peer.UserId);
        Assert.Equal(0m, peer.NetAmount);
        Assert.Equal(0m, Assert.Single(peer.Groups).Amount);
    }

    [Fact]
    public async Task A_peer_in_a_group_with_no_expenses_appears_with_a_zero_net()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();

        var people = await ReadPeopleAsync(group.Owner);

        var peer = Assert.Single(people.Peers);
        Assert.Equal(group.GuestId, peer.UserId);
        Assert.Equal(0m, peer.NetAmount);
        var breakdown = Assert.Single(peer.Groups);
        Assert.Equal(group.Id, breakdown.GroupId);
        Assert.Equal(0m, breakdown.Amount);
    }

    [Fact]
    public async Task A_stranger_sharing_a_group_with_the_peer_but_not_the_caller_does_not_appear()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();

        // The guest joins a stranger's group. Neither the stranger nor that group is the
        // caller's business.
        var strangerUser = await ApiClient.Create(factory).SignInAsync(name: "Stranger");
        var stranger = ApiClient.Create(factory, strangerUser.Token);
        var strangerGroupId = await stranger.CreateGroupAsync("Elsewhere");
        var code = await stranger.CreateInviteAsync(strangerGroupId);
        (await group.Guest.AcceptInviteAsync(code)).EnsureSuccessStatusCode();

        var people = await ReadPeopleAsync(group.Owner);

        var peer = Assert.Single(people.Peers);
        Assert.Equal(group.GuestId, peer.UserId);
        Assert.Equal(group.Id, Assert.Single(peer.Groups).GroupId);
    }

    [Fact]
    public async Task Leaving_a_group_drops_its_rows_from_the_breakdown()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();

        var secondGroupId = await group.Owner.CreateGroupAsync("Second");
        var code = await group.Owner.CreateInviteAsync(secondGroupId);
        (await group.Guest.AcceptInviteAsync(code)).EnsureSuccessStatusCode();

        await group.CreateExpenseAsync(amount: 20m, share: 10m);
        await factory.WaitForProcessedAsync();

        var before = await ReadPeopleAsync(group.Owner);
        Assert.Equal(2, Assert.Single(before.Peers).Groups.Count);

        (await group.Guest.Http.PostAsync($"/group/{secondGroupId}/leave", null)).EnsureSuccessStatusCode();

        var after = await ReadPeopleAsync(group.Owner);

        var peer = Assert.Single(after.Peers);
        Assert.Equal(group.Id, Assert.Single(peer.Groups).GroupId);
        Assert.Equal(10m, peer.NetAmount);
    }

    [Fact]
    public async Task A_peer_from_a_group_the_caller_left_disappears()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();

        Assert.Single((await ReadPeopleAsync(group.Owner)).Peers);

        (await group.Owner.Http.PostAsync($"/group/{group.Id}/leave", null)).EnsureSuccessStatusCode();

        Assert.Empty((await ReadPeopleAsync(group.Owner)).Peers);
    }

    [Fact]
    public async Task Balances_pending_is_true_while_a_contributing_group_recomputes()
    {
        using var gate = new RecomputeGate();
        await using var gated = factory.WithGate(gate);

        var group = await GroupFixture.CreateAsync(gated);
        await gated.DrainProcessedAsync();

        await group.CreateExpenseAsync(amount: 20m, share: 10m);

        await gate.WaitForEntryAsync();
        Assert.True((await ReadPeopleAsync(group.Owner)).BalancesPending);

        gate.Release();
        await gated.WaitForProcessedAsync();

        Assert.False((await ReadPeopleAsync(group.Owner)).BalancesPending);
    }

    [Fact]
    public async Task Unauthenticated_request_receives_401()
    {
        var response = await ApiClient.Create(factory).GetPeopleAsync();

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    private static async Task<PeopleSnapshot> ReadPeopleAsync(ApiClient client)
    {
        var response = await client.GetPeopleAsync();
        response.EnsureSuccessStatusCode();

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(Json);
        var peers = body.GetProperty("peers")
            .EnumerateArray()
            .Select(p => new PeerSnapshot(
                p.GetProperty("userId").GetInt32(),
                p.GetProperty("name").GetString()!,
                p.GetProperty("avatarUrl").GetString()!,
                p.GetProperty("netAmount").GetDecimal(),
                p.GetProperty("groups")
                    .EnumerateArray()
                    .Select(g => new PeerGroupSnapshot(
                        g.GetProperty("groupId").GetInt32(),
                        g.GetProperty("groupName").GetString()!,
                        g.GetProperty("amount").GetDecimal()))
                    .ToList()))
            .ToList();

        return new PeopleSnapshot(peers, body.GetProperty("balancesPending").GetBoolean());
    }

    private sealed record PeopleSnapshot(IReadOnlyList<PeerSnapshot> Peers, bool BalancesPending);

    private sealed record PeerSnapshot(
        int UserId,
        string Name,
        string AvatarUrl,
        decimal NetAmount,
        IReadOnlyList<PeerGroupSnapshot> Groups);

    private sealed record PeerGroupSnapshot(int GroupId, string GroupName, decimal Amount);
}
