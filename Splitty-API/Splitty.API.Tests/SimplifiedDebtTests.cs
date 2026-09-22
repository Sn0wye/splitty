using System.Net;
using System.Net.Http.Json;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Splitty.Domain.Entities;
using Splitty.Service;
using Splitty.Service.Interfaces;

namespace Splitty.API.Tests;

[Collection(nameof(ApiCollection))]
public sealed class SimplifiedDebtTests(ApiFactory factory)
{
    [Fact]
    public async Task A_chain_is_one_debt_visible_to_every_member_without_pairwise_rows()
    {
        var (group, creditor, creditorId) = await ChainAsync();
        var body = await group.Owner.ReadJsonAsync(await group.Owner.GetSummaryAsync(group.Id));
        Assert.False(body.TryGetProperty("balances", out _));
        var debt = Assert.Single(body.GetProperty("simplifiedDebts").EnumerateArray());
        Assert.Equal(group.GuestId, debt.GetProperty("from").GetProperty("id").GetInt32());
        Assert.Equal(creditorId, debt.GetProperty("to").GetProperty("id").GetInt32());
        Assert.Equal("Guest", debt.GetProperty("from").GetProperty("name").GetString());
        Assert.True(debt.GetProperty("to").TryGetProperty("avatarUrl", out _));
        Assert.Equal(10m, debt.GetProperty("amount").GetDecimal());
        var other = await creditor.ReadJsonAsync(await creditor.GetSummaryAsync(group.Id));
        Assert.Equal(body.GetProperty("simplifiedDebts").GetRawText(), other.GetProperty("simplifiedDebts").GetRawText());
    }

    [Fact]
    public async Task A_chain_can_be_settled_directly_and_edited_down_without_losing_money()
    {
        var (group, creditor, creditorId) = await ChainAsync();
        (await group.Guest.SettleUpAsync(group.Id, new { withUserId = creditorId, amount = 10m }))
            .EnsureSuccessStatusCode();
        await factory.WaitForProcessedAsync();
        Assert.Empty((await group.Owner.ReadSummaryAsync(group.Id)).SimplifiedDebts);

        var expenses = await group.Owner.ReadJsonAsync(await group.Owner.GetExpensesAsync(group.Id));
        var payment = Assert.Single(expenses.EnumerateArray(), e => e.GetProperty("type").GetString() == "payment");
        var id = payment.GetProperty("id").GetInt32();
        (await group.Owner.UpdateSettlementAsync(group.Id, id, new { amount = 4m })).EnsureSuccessStatusCode();
        await factory.WaitForProcessedAsync();
        var debt = Assert.Single((await creditor.ReadSummaryAsync(group.Id)).SimplifiedDebts);
        Assert.Equal(new SimplifiedDebtEntry(group.GuestId, creditorId, 6m), debt);

        var nets = new List<decimal>();
        foreach (var client in new[] { group.Owner, group.Guest, creditor })
        {
            var body = await client.ReadJsonAsync(await client.GetGroupAsync(group.Id));
            nets.Add(body.GetProperty("netBalance").GetDecimal());
        }
        Assert.Equal(new[] { 0m, -6m, 6m }, nets);
        Assert.Equal(0m, nets.Sum());
        await ErrorResponseAssertions.AssertErrorAsync(
            await group.Guest.UpdateSettlementAsync(group.Id, id, new { amount = 10.01m }),
            HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task People_uses_the_same_simplified_pairs_in_both_directions()
    {
        var (group, creditor, creditorId) = await ChainAsync();
        foreach (var (client, peerId, amount) in new[]
                 { (group.Guest, creditorId, -10m), (creditor, group.GuestId, 10m) })
        {
            var people = await client.ReadJsonAsync(await client.GetPeopleAsync());
            var peers = people.GetProperty("peers").EnumerateArray().ToList();
            var peer = peers.Single(p => p.GetProperty("userId").GetInt32() == peerId);
            Assert.Equal(amount, peer.GetProperty("netAmount").GetDecimal());
            Assert.Equal(amount, Assert.Single(peer.GetProperty("groups").EnumerateArray()).GetProperty("amount").GetDecimal());
            Assert.Equal(0m, peers.Single(p => p.GetProperty("userId").GetInt32() == group.OwnerId)
                .GetProperty("netAmount").GetDecimal());
        }
    }

    [Theory]
    [InlineData(4, 10, 4.01)]
    [InlineData(10, 4, 4.01)]
    public async Task Settlement_is_bounded_by_both_net_positions(decimal debt, decimal credit, decimal amount)
    {
        var (group, _, creditorId) = await ChainAsync(debt, credit);
        await ErrorResponseAssertions.AssertErrorAsync(
            await group.Guest.SettleUpAsync(group.Id, new { withUserId = creditorId, amount }),
            HttpStatusCode.BadRequest);
        (await group.Guest.SettleUpAsync(group.Id, new { withUserId = creditorId, amount = 4m }))
            .EnsureSuccessStatusCode();
        await factory.WaitForProcessedAsync();
    }

    [Fact]
    public async Task Pending_balances_refuse_creation_and_edit_even_when_stored_debt_exists()
    {
        var (group, _, creditorId) = await ChainAsync();
        (await group.Guest.SettleUpAsync(group.Id, new { withUserId = creditorId, amount = 2m }))
            .EnsureSuccessStatusCode();
        await factory.WaitForProcessedAsync();
        var expenses = await group.Owner.ReadJsonAsync(await group.Owner.GetExpensesAsync(group.Id));
        var id = expenses.EnumerateArray().Single(e => e.GetProperty("type").GetString() == "payment")
            .GetProperty("id").GetInt32();
        using var gate = new RecomputeGate();
        await using var gated = factory.WithGate(gate);
        var guest = ApiClient.Create(gated, group.GuestToken);
        (await guest.RequestSummaryRefreshAsync(group.Id)).EnsureSuccessStatusCode();
        await gate.WaitForEntryAsync();
        Assert.True((await guest.ReadSummaryAsync(group.Id)).BalancesPending);
        await ErrorResponseAssertions.AssertErrorAsync(
            await guest.SettleUpAsync(group.Id, new { withUserId = creditorId, amount = 1m }), HttpStatusCode.BadRequest);
        await ErrorResponseAssertions.AssertErrorAsync(
            await guest.UpdateSettlementAsync(group.Id, id, new { amount = 1m }), HttpStatusCode.BadRequest);
        gate.Release();
        await gated.WaitForProcessedAsync();
    }

    [Fact]
    public async Task Greedy_matching_reselects_largest_positions_and_breaks_ties_by_user_id()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var third = await ApiClient.Create(factory).SignInAsync(name: "Third");
        var fourth = await ApiClient.Create(factory).SignInAsync(name: "Fourth");
        var fifth = await ApiClient.Create(factory).SignInAsync(name: "Fifth");
        foreach (var user in new[] { third, fourth, fifth })
            (await ApiClient.Create(factory, user.Token).AcceptInviteAsync(await group.Owner.CreateInviteAsync(group.Id)))
                .EnsureSuccessStatusCode();
        await factory.DrainProcessedAsync();
        // Debts of 7, 7, 6 and credits of 12, 8 force the largest creditor to change after each match.
        foreach (var (payer, debtor, amount) in new[]
                 { (third.Id, group.OwnerId, 7m), (third.Id, group.GuestId, 5m),
                     (fourth.Id, group.GuestId, 2m), (fourth.Id, fifth.Id, 6m) })
        {
            (await group.Owner.CreateExpenseAsync(group.Id, new
            {
                paidBy = payer, amount, description = "Match", splitMode = "custom",
                splits = new[] { new { userId = debtor, amount } }
            })).EnsureSuccessStatusCode();
            await factory.WaitForProcessedAsync();
        }
        var expected = new[]
        {
            new SimplifiedDebtEntry(group.OwnerId, third.Id, 7m),
            new SimplifiedDebtEntry(group.GuestId, fourth.Id, 7m),
            new SimplifiedDebtEntry(fifth.Id, third.Id, 5m),
            new SimplifiedDebtEntry(fifth.Id, fourth.Id, 1m)
        };
        Assert.Equal(expected, (await group.Owner.ReadSummaryAsync(group.Id)).SimplifiedDebts);
        (await group.Owner.RequestSummaryRefreshAsync(group.Id)).EnsureSuccessStatusCode();
        await factory.WaitForProcessedAsync();
        Assert.Equal(expected, (await group.Owner.ReadSummaryAsync(group.Id)).SimplifiedDebts);
    }

    [Fact]
    public async Task A_two_member_group_has_one_debt_and_a_settled_group_has_none()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();
        Assert.Empty((await group.Owner.ReadSummaryAsync(group.Id)).SimplifiedDebts);
        await group.CreateExpenseAsync(20m, 10m);
        await factory.WaitForProcessedAsync();
        Assert.Equal(new SimplifiedDebtEntry(group.GuestId, group.OwnerId, 10m),
            Assert.Single((await group.Owner.ReadSummaryAsync(group.Id)).SimplifiedDebts));
        await group.SettleAsync(10m);
        await factory.WaitForProcessedAsync();
        Assert.Empty((await group.Owner.ReadSummaryAsync(group.Id)).SimplifiedDebts);
    }

    [Fact]
    public async Task Updating_a_group_does_not_expose_internal_pairwise_balances()
    {
        var (group, _, _) = await ChainAsync();
        var body = await group.Owner.ReadJsonAsync(
            await group.Owner.Http.PutAsJsonAsync($"/group/{group.Id}", new { name = "Renamed" }));
        Assert.False(body.TryGetProperty("balances", out _));
    }

    [Fact]
    public async Task Startup_recovers_pending_groups_through_the_worker()
    {
        await factory.DrainProcessedAsync();
        GroupFixture group;
        await using (var failed = factory.WithWebHostBuilder(builder => builder.ConfigureTestServices(services =>
            services.AddScoped<IBalanceService>(provider => new FailedReplay(
                ActivatorUtilities.CreateInstance<BalanceService>(provider))))))
        {
            group = await GroupFixture.CreateAsync(failed);
            await group.CreateExpenseAsync(20m, 10m);
            await failed.WaitForProcessedAsync();
            Assert.True((await group.Guest.ReadSummaryAsync(group.Id)).BalancesPending);
        }
        await using var restarted = factory.WithWebHostBuilder(_ => { });
        var guest = ApiClient.Create(restarted, group.GuestToken);
        await restarted.WaitForProcessedAsync();
        var summary = await guest.ReadSummaryAsync(group.Id);
        Assert.False(summary.BalancesPending);
        Assert.Equal(new SimplifiedDebtEntry(group.GuestId, group.OwnerId, 10m), Assert.Single(summary.SimplifiedDebts));
    }

    [Fact]
    public async Task Equal_creditors_use_id_ties_but_settlements_need_not_follow_suggested_pairs()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var third = await ApiClient.Create(factory).SignInAsync(name: "Third");
        var fourth = await ApiClient.Create(factory).SignInAsync(name: "Fourth");
        foreach (var user in new[] { third, fourth })
            (await ApiClient.Create(factory, user.Token).AcceptInviteAsync(await group.Owner.CreateInviteAsync(group.Id)))
                .EnsureSuccessStatusCode();
        await factory.DrainProcessedAsync();
        foreach (var (payer, debtor) in new[] { (third.Id, group.OwnerId), (fourth.Id, group.GuestId) })
        {
            (await group.Owner.CreateExpenseAsync(group.Id, new
            {
                paidBy = payer, amount = 10m, description = "Ties", splitMode = "custom",
                splits = new[] { new { userId = debtor, amount = 10m } }
            })).EnsureSuccessStatusCode();
            await factory.WaitForProcessedAsync();
        }
        var expected = new[]
        {
            new SimplifiedDebtEntry(group.OwnerId, third.Id, 10m),
            new SimplifiedDebtEntry(group.GuestId, fourth.Id, 10m)
        };
        Assert.Equal(expected, (await group.Owner.ReadSummaryAsync(group.Id)).SimplifiedDebts);
        (await group.Owner.RequestSummaryRefreshAsync(group.Id)).EnsureSuccessStatusCode();
        await factory.WaitForProcessedAsync();
        Assert.Equal(expected, (await group.Owner.ReadSummaryAsync(group.Id)).SimplifiedDebts);
        (await group.Owner.SettleUpAsync(group.Id, new { withUserId = fourth.Id, amount = 10m }))
            .EnsureSuccessStatusCode();
        await factory.WaitForProcessedAsync();
        Assert.Equal(new SimplifiedDebtEntry(group.GuestId, third.Id, 10m),
            Assert.Single((await group.Owner.ReadSummaryAsync(group.Id)).SimplifiedDebts));
    }

    private sealed class FailedReplay(IBalanceService inner) : BalanceServiceDecorator(inner)
    {
        public override Task<List<Balance>> CalculateGroupBalances(int groupId) =>
            throw new InvalidOperationException("Leave work pending for restart");
    }

    private async Task<(GroupFixture Group, ApiClient Creditor, int CreditorId)> ChainAsync(decimal debt = 10m, decimal credit = 10m)
    {
        var group = await GroupFixture.CreateAsync(factory);
        var user = await ApiClient.Create(factory).SignInAsync(name: "Creditor");
        var creditor = ApiClient.Create(factory, user.Token);
        (await creditor.AcceptInviteAsync(await group.Owner.CreateInviteAsync(group.Id))).EnsureSuccessStatusCode();
        await factory.DrainProcessedAsync();
        await group.CreateExpenseAsync(debt * 2, debt);
        await factory.WaitForProcessedAsync();
        (await group.Owner.CreateExpenseAsync(group.Id, new
        {
            paidBy = user.Id, amount = credit, description = "Chain", splitMode = "custom",
            splits = new[] { new { userId = group.OwnerId, amount = credit } }
        })).EnsureSuccessStatusCode();
        await factory.WaitForProcessedAsync();
        return (group, creditor, user.Id);
    }
}
