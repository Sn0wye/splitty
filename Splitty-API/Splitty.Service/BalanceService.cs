using Splitty.Domain.Entities;
using Splitty.Repository.Interfaces;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

public class BalanceService(
    IBalanceRepository balanceRepository,
    IExpenseRepository expenseRepository,
    IUserRepository userRepository,
    IGroupMembershipRepository groupMembershipRepository
) : IBalanceService
{
    public async Task<List<Balance>> CalculateGroupBalances(int groupId)
    {
        var balances = await balanceRepository.GetGroupBalancesAsync(groupId);
        var expenses = await expenseRepository.FindExpensesByGroupId(groupId);
        
        foreach (var balance in balances)
        {
            balance.Amount = 0;
        }

        foreach (var expense in expenses)
        {
            foreach (var split in expense.Splits)
            {
                if (split.UserId == expense.PaidBy)
                    continue;
                    
                var payer = balances.Find(b => b.UserId == expense.PaidBy && b.PeerId == split.UserId);
                if (payer == null)
                {
                    payer = new Balance
                    {
                        UserId = expense.PaidBy,
                        GroupId = groupId,
                        PeerId = split.UserId,
                        Amount = 0
                    };
                    balances.Add(payer);
                }
                payer.Amount += Math.Abs(split.Amount);

                var payee = balances.Find(b => b.UserId == split.UserId && b.PeerId == expense.PaidBy);
                if (payee == null)
                {
                    payee = new Balance
                    {
                        UserId = split.UserId,
                        GroupId = groupId,
                        PeerId = expense.PaidBy,
                        Amount = 0
                    };
                    balances.Add(payee);
                }
                payee.Amount -= Math.Abs(split.Amount);

            }
        }

        await balanceRepository.UpdateBalancesAsync(balances);
        
        return balances;
    }

    public async Task<List<Balance>> GetGroupUserBalance(int groupId, int userId)
    {
        await EnsureMemberAsync(groupId, userId);

        return await balanceRepository.GetUserGroupBalances(userId, groupId);
    }

    public async Task SettleUp(int groupId, int userId, int peerId, decimal amount)
    {
        if (userId == peerId)
        {
            throw new ArgumentException("A settlement must be recorded against another member.");
        }

        if (amount <= 0)
        {
            throw new ArgumentException("Settlement amount must be greater than zero.");
        }

        await EnsureMemberAsync(groupId, userId);
        await EnsureMemberAsync(groupId, peerId);

        var payee = await userRepository.GetByIdAsync(peerId);

        if (payee is null)
        {
            throw new KeyNotFoundException("User not found");
        }

        var owed = await AmountOwedAsync(groupId, userId, peerId);

        if (amount > owed)
        {
            throw new ArgumentException(
                $"Settlement amount exceeds the {owed} owed to {payee.Name}.");
        }

        var settleExpense = new Expense
        {
            GroupId = groupId,
            Description = $"Payment to {payee.Name}",
            Amount = amount,
            PaidBy = userId,
            Type = ExpenseType.Payment,
            Splits = new List<ExpenseSplit>
            {
                new()
                {
                    UserId = userId,
                    Amount = amount
                },
                new()
                {
                    UserId = peerId,
                    Amount = -amount
                }
            }
        };

        ExpenseSplitInvariants.Ensure(
            settleExpense.Type,
            settleExpense.SplitMode,
            settleExpense.Amount,
            settleExpense.Splits.Select(s => new SplitShape(s.Amount, s.Percentage)));

        await expenseRepository.CreateAsync(settleExpense);
    }

    /// <summary>
    /// Edits an existing settlement, re-applying the cap of invariant 5 against the debt
    /// the settlement itself does not account for. Splits are rebuilt from the new amount
    /// rather than accepted, the same way <see cref="SettleUp"/> constructs them.
    /// </summary>
    public async Task UpdateSettlement(int groupId, int expenseId, int userId, decimal amount, DateTime? date)
    {
        if (amount <= 0)
        {
            throw new ArgumentException("Settlement amount must be greater than zero.");
        }

        await EnsureMemberAsync(groupId, userId);

        var settlement = await FindSettlementAsync(groupId, expenseId);

        var payerId = settlement.PaidBy;
        var peerSplit = settlement.Splits.FirstOrDefault(s => s.UserId != payerId);

        if (peerSplit is null)
        {
            throw new InvalidOperationException("This settlement has no counterparty.");
        }

        var payee = await userRepository.GetByIdAsync(peerSplit.UserId);

        if (payee is null)
        {
            throw new KeyNotFoundException("User not found");
        }

        // The stored balance already counts this settlement, so the cap has to be read with
        // that contribution removed — otherwise every edit is measured against a debt the
        // row being edited has already paid down, and even a decrease is rejected. The
        // contribution is read off the split, since that is what the replay sums.
        var owed = await AmountOwedAsync(
            groupId, payerId, peerSplit.UserId, excluding: Math.Abs(peerSplit.Amount));

        if (amount > owed)
        {
            throw new ArgumentException(
                $"Settlement amount exceeds the {owed} owed to {payee.Name}.");
        }

        settlement.Amount = amount;
        settlement.Date = ExpenseDate.Normalize(date) ?? settlement.Date;
        settlement.UpdatedAt = DateTime.UtcNow;

        foreach (var split in settlement.Splits)
        {
            split.Amount = split.UserId == payerId ? amount : -amount;
        }

        ExpenseSplitInvariants.Ensure(
            settlement.Type,
            settlement.SplitMode,
            settlement.Amount,
            settlement.Splits.Select(s => new SplitShape(s.Amount, s.Percentage)));

        await expenseRepository.UpdateAsync(settlement);
    }

    public async Task DeleteSettlement(int groupId, int expenseId, int userId)
    {
        await EnsureMemberAsync(groupId, userId);

        await expenseRepository.DeleteAsync(await FindSettlementAsync(groupId, expenseId));
    }

    /// <summary>
    /// A settlement is an <see cref="Expense"/> row, so this route can be handed an ordinary
    /// expense id. Refusing it here keeps one mutation path per row type, per
    /// docs/adr/0001-settlements-have-their-own-routes.md.
    /// </summary>
    private async Task<Expense> FindSettlementAsync(int groupId, int expenseId)
    {
        var expense = await expenseRepository.FindByIdAsync(expenseId);

        if (expense is null || expense.GroupId != groupId)
        {
            throw new KeyNotFoundException("Settlement not found");
        }

        if (expense.Type != ExpenseType.Payment)
        {
            throw new InvalidOperationException(
                "This is an expense, not a settlement. Use /group/{groupId}/expenses/{expenseId}.");
        }

        return expense;
    }

    /// <summary>
    /// What the caller may still settle with this peer, read from the stored pairwise row
    /// rather than recomputed. The replay credits the payer, so a negative amount on the
    /// caller's row is what the caller owes; anything else, including a group whose balances
    /// the worker has not written yet, leaves nothing to settle.
    /// </summary>
    /// <param name="excluding">
    /// A contribution already counted in the stored row that should not bound the caller —
    /// the settlement being edited.
    /// </param>
    private async Task<decimal> AmountOwedAsync(int groupId, int userId, int peerId, decimal excluding = 0m)
    {
        var balance = await balanceRepository.GetPairwiseBalanceAsync(userId, peerId, groupId);
        var amount = (balance?.Amount ?? 0m) - excluding;

        return amount < 0 ? -amount : 0m;
    }

    private async Task EnsureMemberAsync(int groupId, int userId)
    {
        var membership = await groupMembershipRepository.GetGroupMembershipByUserIdAndGroupId(userId, groupId);

        if (membership is null)
        {
            throw new UnauthorizedAccessException("User is not a member of the group");
        }
    }
}
