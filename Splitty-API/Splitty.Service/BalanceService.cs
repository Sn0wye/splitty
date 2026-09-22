using Splitty.Domain.Entities;
using Splitty.DTO.Response;
using Splitty.Repository.Interfaces;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

public class BalanceService(
    IBalanceRepository balanceRepository,
    IExpenseRepository expenseRepository,
    IUserRepository userRepository,
    IGroupMembershipRepository groupMembershipRepository,
    IAvatarResolver avatarResolver,
    IGroupRepository groupRepository
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

        var nets = balances.GroupBy(b => b.UserId)
            .ToDictionary(g => g.Key, g => g.Sum(b => b.Amount));
        var debts = new List<SimplifiedDebt>();
        while (true)
        {
            var debtor = nets.Where(n => n.Value < 0).OrderBy(n => n.Value).ThenBy(n => n.Key).FirstOrDefault();
            var creditor = nets.Where(n => n.Value > 0).OrderByDescending(n => n.Value).ThenBy(n => n.Key).FirstOrDefault();
            if (debtor.Value == 0 || creditor.Value == 0) break;

            var amount = Math.Min(-debtor.Value, creditor.Value);
            debts.Add(new SimplifiedDebt
            {
                GroupId = groupId, FromUserId = debtor.Key, ToUserId = creditor.Key, Amount = amount
            });
            nets[debtor.Key] += amount;
            nets[creditor.Key] -= amount;
        }
        await balanceRepository.ReplaceSimplifiedDebtsAsync(groupId, debts);
        
        return balances;
    }

    public async Task<List<SimplifiedDebtResponse>> GetGroupSimplifiedDebts(int groupId, int userId)
    {
        await EnsureMemberAsync(groupId, userId);

        var debts = await balanceRepository.GetSimplifiedDebtsAsync(groupId);
        return debts.Select(d => new SimplifiedDebtResponse
        {
            From = new DebtMemberResponse
            {
                Id = d.FromUserId, Name = d.FromUser.Name, AvatarUrl = avatarResolver.Resolve(d.FromUser)
            },
            To = new DebtMemberResponse
            {
                Id = d.ToUserId, Name = d.ToUser.Name, AvatarUrl = avatarResolver.Resolve(d.ToUser)
            },
            Amount = d.Amount
        }).ToList();
    }

    public async Task SettleUp(int groupId, int userId, int peerId, decimal amount, DateTime? date)
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
            // Not taken from the caller: a settlement always carries Payment, which is the
            // category no expense may hold and the picker never offers.
            Category = ExpenseCategory.Payment,
            Date = ExpenseDate.Normalize(date),
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
        // Coerced rather than preserved, so a row written before the column existed, or by an
        // earlier path, ends up saying what it is.
        settlement.Category = ExpenseCategory.Payment;
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

    // Read both net positions from stored bookkeeping. Excluding an existing payment
    // restores the payer's debt and the payee's credit before applying the same cap.
    private async Task<decimal> AmountOwedAsync(int groupId, int userId, int peerId, decimal excluding = 0m)
    {
        if (await groupRepository.GetBalancesPendingAsync(groupId)) return 0m;
        var balances = await balanceRepository.GetGroupBalancesAsync(groupId);
        var payerNet = balances.Where(b => b.UserId == userId).Sum(b => b.Amount) - excluding;
        var payeeNet = balances.Where(b => b.UserId == peerId).Sum(b => b.Amount) + excluding;
        return Math.Min(Math.Max(0m, -payerNet), Math.Max(0m, payeeNet));
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
