using Splitty.Domain.Entities;
using Splitty.DTO.Response;
using Splitty.Repository;
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
    IGroupLedger groupLedger,
    IGroupReadModel readModel
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

    /// <summary>
    /// Records <paramref name="payerId"/> paying <paramref name="payeeId"/>. Any member may
    /// record a payment between any two members — the payer saying "I paid", the payee
    /// saying "I was paid", or anyone else — because membership is the only authorization
    /// boundary (invariant 2). Both sides are checked by membership row, not liveness, so a
    /// tombstone can be either one. See docs/adr/0010-any-member-records-a-payment-either-way.md.
    /// </summary>
    public async Task<ExpenseResponse> SettleUp(
        int groupId,
        int callerId,
        int payerId,
        int payeeId,
        decimal amount,
        DateTime? date,
        Guid? clientId = null,
        Currency? currency = null)
    {
        // A resent settlement answers with what its first send recorded. Checked before the
        // cap, which that first send already paid down.
        if (await ClientWrites.ExistingAsync(readModel, groupId, clientId, ExpenseType.Payment) is { } existing)
        {
            return await readModel.GetExpenseAsync(groupId, existing, callerId);
        }

        if (payerId == payeeId)
        {
            throw new ArgumentException("A settlement must be recorded between two different members.");
        }

        if (amount <= 0)
        {
            throw new ArgumentException("Settlement amount must be greater than zero.");
        }

        await EnsureMemberAsync(groupId, callerId);
        await EnsureMemberAsync(groupId, payerId);
        await EnsureMemberAsync(groupId, payeeId);

        var payee = await userRepository.GetByIdAsync(payeeId);

        if (payee is null)
        {
            throw new KeyNotFoundException("User not found");
        }

        await ClientWrites.EnsureCurrencyAsync(readModel, groupId, currency);

        var owed = await groupLedger.SettlementCapAsync(groupId, payerId, payeeId);

        if (amount > owed) throw ExceedsCap(owed, payee);

        var settleExpense = new Expense
        {
            ClientId = clientId,
            GroupId = groupId,
            Description = $"Payment to {payee.Name}",
            Amount = amount,
            PaidBy = payerId,
            Type = ExpenseType.Payment,
            // Not taken from the caller: a settlement always carries Payment, which is the
            // category no expense may hold and the picker never offers.
            Category = ExpenseCategory.Payment,
            Date = ExpenseDate.Normalize(date),
            Splits = new List<ExpenseSplit>
            {
                new()
                {
                    UserId = payerId,
                    Amount = amount
                },
                new()
                {
                    UserId = payeeId,
                    Amount = -amount
                }
            }
        };

        ExpenseSplitInvariants.Ensure(
            settleExpense.Type,
            settleExpense.SplitMode,
            settleExpense.Amount,
            settleExpense.Splits.Select(s => new SplitShape(s.Amount, s.Percentage)));

        if (!await expenseRepository.CreateOnceAsync(settleExpense))
        {
            var first = await ClientWrites.ExistingAsync(readModel, groupId, clientId, ExpenseType.Payment);
            return await readModel.GetExpenseAsync(groupId, first!.Value, callerId);
        }

        await groupLedger.RequestRecomputationAsync(groupId);

        return await readModel.GetExpenseAsync(groupId, settleExpense.Id, callerId);
    }

    private static RefusalException ExceedsCap(decimal owed, User payee) =>
        new(400, ErrorCode.SettlementExceedsCap, $"Settlement amount exceeds the {owed} owed to {payee.Name}.")
        {
            Cap = owed
        };

    /// <summary>
    /// Edits an existing settlement, re-applying the cap of invariant 5 against the debt
    /// the settlement itself does not account for. Splits are rebuilt from the new amount
    /// rather than accepted, the same way <see cref="SettleUp"/> constructs them.
    /// </summary>
    public async Task<ExpenseResponse> UpdateSettlement(
        int groupId,
        int expenseId,
        int userId,
        decimal amount,
        DateTime? date,
        int? baseVersion = null,
        Guid? opId = null,
        Currency? currency = null)
    {
        if (amount <= 0)
        {
            throw new ArgumentException("Settlement amount must be greater than zero.");
        }

        await EnsureMemberAsync(groupId, userId);

        var settlement = await FindSettlementAsync(groupId, expenseId);

        if (opId is { } op && settlement.LastOpId == op)
        {
            return await readModel.GetExpenseAsync(groupId, expenseId, userId);
        }

        if (baseVersion is { } version && version != settlement.Version)
        {
            throw RefusalException.VersionConflict(await readModel.GetExpenseAsync(groupId, expenseId, userId));
        }

        await ClientWrites.EnsureCurrencyAsync(readModel, groupId, currency);

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

        if (amount > owed) throw ExceedsCap(owed, payee);

        settlement.Amount = amount;
        // Coerced rather than preserved, so a row written before the column existed, or by an
        // earlier path, ends up saying what it is.
        settlement.Category = ExpenseCategory.Payment;
        settlement.Date = ExpenseDate.Normalize(date) ?? settlement.Date;
        settlement.UpdatedAt = DateTime.UtcNow;
        settlement.Version++;
        settlement.LastOpId = opId;

        foreach (var split in settlement.Splits)
        {
            split.Amount = split.UserId == payerId ? amount : -amount;
        }

        ExpenseSplitInvariants.Ensure(
            settlement.Type,
            settlement.SplitMode,
            settlement.Amount,
            settlement.Splits.Select(s => new SplitShape(s.Amount, s.Percentage)));

        try
        {
            await expenseRepository.UpdateAsync(settlement);
        }
        catch (ConcurrentEditException)
        {
            throw RefusalException.VersionConflict(await readModel.GetExpenseAsync(groupId, expenseId, userId));
        }

        await groupLedger.RequestRecomputationAsync(groupId);

        return await readModel.GetExpenseAsync(groupId, expenseId, userId);
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
