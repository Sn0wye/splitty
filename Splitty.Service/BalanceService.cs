using Splitty.Domain.Entities;
using Splitty.Repository.Interfaces;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

public class BalanceService(
    IBalanceRepository balanceRepository,
    IExpenseRepository expenseRepository
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
                payer.Amount += split.Amount;

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
                payee.Amount -= split.Amount;

            }
        }

        await balanceRepository.UpdateBalancesAsync(balances);
        
        return balances;
    }

    public async Task<List<Balance>> GetGroupUserBalance(int groupId, int userId)
    {
        return await balanceRepository.GetUserGroupBalances(userId, groupId);
    }
}