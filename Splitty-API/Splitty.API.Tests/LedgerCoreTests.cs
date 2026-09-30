using Splitty.DTO.Internal;
using Splitty.Service;

namespace Splitty.API.Tests;

/// <summary>
/// The ledger math, in process: no host, no database. Members are plain ints here, the way
/// the API keys them by user id.
/// </summary>
public sealed class LedgerCoreTests
{
    private static PairwisePosition<int> Paid(int payer, int participant, decimal amount) =>
        new(payer, participant, amount);

    private static IReadOnlyDictionary<int, decimal> NetsOf(params PairwisePosition<int>[] positions) =>
        LedgerCore.Nets(LedgerCore.Balances(positions));

    [Fact]
    public void Each_position_is_stored_from_both_sides_with_opposite_signs()
    {
        var balances = LedgerCore.Balances([Paid(1, 2, 10m)]);

        Assert.Equal(
            [new PairwiseBalance<int>(1, 2, 10m), new PairwiseBalance<int>(2, 1, -10m)],
            balances);
    }

    [Fact]
    public void Positions_for_the_same_pair_add_up_and_opposite_directions_offset()
    {
        var balances = LedgerCore.Balances([Paid(1, 2, 10m), Paid(1, 2, 5m), Paid(2, 1, 4m)]);

        Assert.Equal(
            [new PairwiseBalance<int>(1, 2, 11m), new PairwiseBalance<int>(2, 1, -11m)],
            balances);
    }

    [Fact]
    public void A_payer_splitting_with_themselves_owes_nothing_to_anyone()
    {
        Assert.Empty(LedgerCore.Balances([Paid(1, 1, 10m)]));
        Assert.Empty(LedgerCore.Simplify(NetsOf(Paid(1, 1, 10m))));
    }

    [Fact]
    public void Split_amounts_count_by_magnitude_so_a_settlement_row_pays_down_debt()
    {
        // A settlement from 2 to 1 stores the payee's split as a negative amount.
        var nets = NetsOf(Paid(1, 2, 10m), Paid(2, 1, -4m));

        Assert.Equal(6m, nets[1]);
        Assert.Equal(-6m, nets[2]);
    }

    [Fact]
    public void Nets_sum_to_zero()
    {
        var nets = NetsOf(Paid(1, 2, 7m), Paid(1, 3, 3.33m), Paid(3, 2, 12.5m), Paid(4, 1, 0.01m));

        Assert.Equal(0m, nets.Values.Sum());
    }

    [Fact]
    public void A_payer_who_is_not_a_participant_is_owed_every_split()
    {
        var nets = NetsOf(Paid(1, 2, 5m), Paid(1, 3, 5m));

        Assert.Equal(10m, nets[1]);
        Assert.Equal(
            [new SimplifiedPayment<int>(2, 1, 5m), new SimplifiedPayment<int>(3, 1, 5m)],
            LedgerCore.Simplify(nets));
    }

    [Fact]
    public void A_chain_collapses_into_one_payment()
    {
        // 2 owes 1, 1 owes 3: 1 nets to zero and drops out.
        var debts = LedgerCore.Simplify(NetsOf(Paid(1, 2, 10m), Paid(3, 1, 10m)));

        Assert.Equal([new SimplifiedPayment<int>(2, 3, 10m)], debts);
    }

    [Fact]
    public void Greedy_matching_reselects_the_largest_positions_after_each_payment()
    {
        // Ported from SimplifiedDebtTests: debts of 7, 7, 6 and credits of 12, 8.
        var debts = LedgerCore.Simplify(NetsOf(
            Paid(3, 1, 7m), Paid(3, 2, 5m), Paid(4, 2, 2m), Paid(4, 5, 6m)));

        Assert.Equal(
            [
                new SimplifiedPayment<int>(1, 3, 7m),
                new SimplifiedPayment<int>(2, 4, 7m),
                new SimplifiedPayment<int>(5, 3, 5m),
                new SimplifiedPayment<int>(5, 4, 1m)
            ],
            debts);
    }

    [Fact]
    public void Equal_positions_break_ties_by_member_id()
    {
        var debts = LedgerCore.Simplify(NetsOf(Paid(3, 1, 10m), Paid(4, 2, 10m)));

        Assert.Equal(
            [new SimplifiedPayment<int>(1, 3, 10m), new SimplifiedPayment<int>(2, 4, 10m)],
            debts);
    }

    [Fact]
    public void Simplification_needs_at_most_members_minus_one_payments()
    {
        var nets = NetsOf(
            Paid(1, 2, 3m), Paid(2, 3, 5m), Paid(3, 4, 7m), Paid(4, 5, 11m), Paid(5, 6, 13m), Paid(6, 1, 2m));

        var debts = LedgerCore.Simplify(nets);

        Assert.True(debts.Count <= nets.Count - 1);
        foreach (var (member, net) in nets)
        {
            var settled = debts.Where(d => d.To == member).Sum(d => d.Amount)
                          - debts.Where(d => d.From == member).Sum(d => d.Amount);
            Assert.Equal(net, settled);
        }
    }

    [Fact]
    public void A_settled_group_has_no_simplified_debts()
    {
        var nets = NetsOf(Paid(1, 2, 10m), Paid(2, 1, -10m));

        Assert.All(nets.Values, net => Assert.Equal(0m, net));
        Assert.Empty(LedgerCore.Simplify(nets));
        Assert.Empty(LedgerCore.Simplify(new Dictionary<int, decimal>()));
    }

    [Theory]
    [InlineData(4, 10, 4)]
    [InlineData(10, 4, 4)]
    [InlineData(10, 10, 10)]
    public void The_cap_is_the_smaller_of_the_payers_debt_and_the_payees_credit(
        decimal debt, decimal credit, decimal cap)
    {
        // Ported from SimplifiedDebtTests' chain: 2 owes 1 the debt, 1 owes 3 the credit.
        var nets = NetsOf(Paid(1, 2, debt), Paid(3, 1, credit));

        Assert.Equal(cap, LedgerCore.Cap(nets, payer: 2, payee: 3));
    }

    [Fact]
    public void The_cap_is_exactly_the_debt_and_settling_it_leaves_the_pair_at_zero()
    {
        // Ported from SettlementBoundsTests: the owner pays 20 split evenly, the guest owes 10.
        var owed = NetsOf(Paid(1, 2, 10m));
        Assert.Equal(10m, LedgerCore.Cap(owed, payer: 2, payee: 1));

        var settled = LedgerCore.Balances([Paid(1, 2, 10m), Paid(2, 1, -10m)]);
        Assert.All(settled, balance => Assert.Equal(0m, balance.Amount));
        Assert.Equal(0m, LedgerCore.Cap(LedgerCore.Nets(settled), payer: 2, payee: 1));
    }

    [Fact]
    public void A_group_with_no_positions_caps_every_settlement_at_zero()
    {
        // Ported from SettlementBoundsTests: no computed balances, nothing to settle.
        Assert.Equal(0m, LedgerCore.Cap(NetsOf(), payer: 2, payee: 1));
    }

    [Fact]
    public void The_cap_is_zero_when_the_payer_is_owed_or_the_payee_owes()
    {
        var nets = NetsOf(Paid(1, 2, 10m));

        Assert.Equal(0m, LedgerCore.Cap(nets, payer: 1, payee: 2));
        Assert.Equal(0m, LedgerCore.Cap(nets, payer: 2, payee: 3));
        Assert.Equal(0m, LedgerCore.Cap(nets, payer: 3, payee: 1));
    }

    [Fact]
    public void The_cap_excludes_an_edited_payments_own_contribution()
    {
        // 2 owed 10 and already paid 4 of it back.
        var nets = NetsOf(Paid(1, 2, 10m), Paid(2, 1, -4m));

        Assert.Equal(6m, LedgerCore.Cap(nets, payer: 2, payee: 1));
        Assert.Equal(10m, LedgerCore.Cap(nets, payer: 2, payee: 1, excluding: 4m));
    }

    [Fact]
    public void Members_can_be_keyed_by_any_identity()
    {
        var nets = LedgerCore.Nets(LedgerCore.Balances(
            [new PairwisePosition<string>("ann@x", "bob@x", 12m)]));

        Assert.Equal(12m, LedgerCore.Cap(nets, payer: "bob@x", payee: "ann@x"));
    }
}
