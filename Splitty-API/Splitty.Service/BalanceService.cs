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
            settleExpense.Amount,
            settleExpense.Splits.Select(s => s.Amount));

        await expenseRepository.CreateAsync(settleExpense);
    }

    /// <summary>
    /// What the caller may still settle with this peer, read from the stored pairwise row
    /// rather than recomputed. The replay credits the payer, so a negative amount on the
    /// caller's row is what the caller owes; anything else, including a group whose balances
    /// the worker has not written yet, leaves nothing to settle.
    /// </summary>
    private async Task<decimal> AmountOwedAsync(int groupId, int userId, int peerId)
    {
        var balance = await balanceRepository.GetPairwiseBalanceAsync(userId, peerId, groupId);

        return balance is { Amount: < 0 } ? -balance.Amount : 0;
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
