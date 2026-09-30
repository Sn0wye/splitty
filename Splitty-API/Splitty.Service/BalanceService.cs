using Splitty.Domain.Entities;
using Splitty.DTO.Response;
using Splitty.Repository.Interfaces;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

/// <summary>
/// Owns the settlement writes and the simplified-debt read. A settlement write that succeeds
/// requests its own recomputation through the group ledger, the same as an expense write.
/// </summary>
public class BalanceService(
    IBalanceRepository balanceRepository,
    IExpenseRepository expenseRepository,
    IUserRepository userRepository,
    IGroupMembershipRepository groupMembershipRepository,
    IAvatarResolver avatarResolver,
    IGroupLedger groupLedger
) : IBalanceService
{
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

        var owed = await groupLedger.SettlementCapAsync(groupId, userId, peerId);

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
        await groupLedger.RequestRecomputationAsync(groupId);
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
        var owed = await groupLedger.SettlementCapAsync(
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
        await groupLedger.RequestRecomputationAsync(groupId);
    }

    public async Task DeleteSettlement(int groupId, int expenseId, int userId)
    {
        await EnsureMemberAsync(groupId, userId);

        await expenseRepository.DeleteAsync(await FindSettlementAsync(groupId, expenseId));
        await groupLedger.RequestRecomputationAsync(groupId);
    }

    /// <summary>
    /// A settlement is an <see cref="Expense"/> row, so this route can be handed an ordinary
    /// expense id. Refusing it here keeps one mutation path per row type, per
    /// docs/adr/0001-settlements-have-their-own-routes.md.
    /// </summary>
    private async Task<Expense> FindSettlementAsync(int groupId, int expenseId)
    {
        var expense = await expenseRepository.GetForUpdateAsync(expenseId);

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

    private async Task EnsureMemberAsync(int groupId, int userId)
    {
        var membership = await groupMembershipRepository.GetGroupMembershipByUserIdAndGroupId(userId, groupId);

        if (membership is null)
        {
            throw new UnauthorizedAccessException("User is not a member of the group");
        }
    }
}
