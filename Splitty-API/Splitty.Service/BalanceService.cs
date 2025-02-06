using Splitty.Domain.Entities;
using Splitty.Repository.Interfaces;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

public class BalanceService(
    IBalanceRepository balanceRepository,
    IExpenseRepository expenseRepository,
    IUserRepository userRepository
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
        return await balanceRepository.GetUserGroupBalances(userId, groupId);
    }

    public async Task SettleUp(int groupId, int userId, int peerId, decimal amount)
    {
        var payee = await userRepository.GetByIdAsync(peerId);

        if (payee is null)
        {
            throw new ArgumentException("User not found");
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

        await expenseRepository.CreateAsync(settleExpense);
    }
}