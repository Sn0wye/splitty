using Splitty.Domain.Entities;
using Splitty.DTO.Internal;
using Splitty.Repository.Interfaces;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

public class ExpenseService(
    IExpenseRepository expenseRepository,
    IGroupMembershipRepository groupMembershipRepository
    ): IExpenseService
{
    public async Task<Expense> CreateAsync(CreateExpenseDTO dto, int userId)
    {
        // Percentages are meaningless off a percentage expense, so they are dropped rather
        // than refused: a client that sends both a mode and leftover percentages is
        // describing an equal split, and the stored rows should say only that.
        var percentages = PercentagesFor(dto.SplitMode, dto.ExpenseSplits.Select(s => s.Percentage));

        ExpenseSplitInvariants.Ensure(
            ExpenseType.Expense,
            dto.SplitMode,
            dto.Amount,
            dto.ExpenseSplits.Zip(percentages, (s, p) => new SplitShape(s.Amount, p)));

        var splits = dto.ExpenseSplits;

        await EnsureMemberAsync(dto.GroupId, userId);
        await EnsureMemberAsync(dto.GroupId, dto.PaidBy);
        await EnsureMembersAsync(dto.GroupId, splits.Select(s => s.UserId));

        var expense = new Expense
        {
            Amount = dto.Amount,
            Description = dto.Description,
            GroupId = dto.GroupId,
            PaidBy = dto.PaidBy,
            Date = ExpenseDate.Normalize(dto.Date),
            SplitMode = dto.SplitMode,
            Splits = splits.Zip(percentages, (s, percentage) => new ExpenseSplit
            {
                Amount = s.Amount,
                UserId = s.UserId,
                Percentage = percentage,
            }).ToList()
        };

        await expenseRepository.CreateAsync(expense);
        
        return (await expenseRepository.FindByIdAsync(expense.Id))!;
    }

    public async Task<Expense?> FindByIdAsync(int id)
    {
        return await expenseRepository.FindByIdAsync(id);
    }

    public async Task<Expense> FindByIdAsync(int groupId, int expenseId, int userId)
    {
        await EnsureMemberAsync(groupId, userId);

        return await FindInGroupAsync(groupId, expenseId);
    }

    /// <summary>
    /// Refuses settlements: they are deleted through their own route, which re-reads the
    /// cap and keeps one delete path per row type. See
    /// docs/adr/0001-settlements-have-their-own-routes.md.
    /// </summary>
    public async Task DeleteAsync(int groupId, int expenseId, int userId)
    {
        await EnsureMemberAsync(groupId, userId);

        var expense = await FindInGroupAsync(groupId, expenseId);

        if (expense.Type == ExpenseType.Payment)
        {
            throw new InvalidOperationException(
                "This is a settlement. Delete it through /group/{groupId}/settlements/{expenseId}.");
        }

        await expenseRepository.DeleteAsync(expense);
    }
    
    public async Task<List<Expense>> FindExpensesByGroupId(int groupId, int userId)
    {
        await EnsureMemberAsync(groupId, userId);

        return await expenseRepository.FindExpensesByGroupId(groupId);
    }
    
    public async Task<Expense> UpdateAsync(UpdateExpenseDTO dto, int userId)
    {
        // The rows and the mode naming them are one fact. Accepting new splits without a
        // mode would leave the stored mode describing rows it has never seen.
        if (dto.ExpenseSplits is not null && dto.SplitMode is null)
        {
            throw new ArgumentException("An update that changes the splits must also send the split mode.");
        }

        var expense = await expenseRepository.FindByIdAsync(dto.Id);

        if (expense is null)
        {
            throw new KeyNotFoundException("Expense not found");
        }

        // The expense must belong to the group the request was made against,
        // otherwise a member of group A could edit an expense of group B.
        if (dto.GroupId is not null && dto.GroupId != expense.GroupId)
        {
            throw new UnauthorizedAccessException("Expense does not belong to the group");
        }

        await EnsureMemberAsync(expense.GroupId, userId);

        // Same reason the delete route refuses them: a settlement's amount is capped and its
        // splits are rebuilt rather than accepted, neither of which this path does.
        if (expense.Type == ExpenseType.Payment)
        {
            throw new InvalidOperationException(
                "This is a settlement. Edit it through /group/{groupId}/settlements/{expenseId}.");
        }

        // Validate the resulting state, not just the supplied fields: an
        // amount-only update must not leave a nonmember payer or split behind.
        await EnsureMemberAsync(expense.GroupId, dto.PaidBy ?? expense.PaidBy);
        await EnsureMembersAsync(
            expense.GroupId,
            dto.ExpenseSplits is not null
                ? dto.ExpenseSplits.Select(s => s.UserId)
                : expense.Splits.Select(s => s.UserId));

        var resultingAmount = dto.Amount ?? expense.Amount;
        var resultingMode = dto.SplitMode ?? expense.SplitMode;

        // Validate the mode against the rows it will actually name, which for a mode-only
        // edit are the rows already stored. Leaving percentage mode nulls them here too,
        // so an expense never carries percentages its mode does not claim.
        var resultingAmounts = dto.ExpenseSplits is not null
            ? dto.ExpenseSplits.Select(s => s.Amount).ToList()
            : expense.Splits.Select(s => s.Amount).ToList();
        var resultingPercentages = PercentagesFor(
            resultingMode,
            dto.ExpenseSplits is not null
                ? dto.ExpenseSplits.Select(s => s.Percentage)
                : expense.Splits.Select(s => s.Percentage));

        ExpenseSplitInvariants.Ensure(
            expense.Type,
            resultingMode,
            resultingAmount,
            resultingAmounts.Zip(resultingPercentages, (amount, percentage) => new SplitShape(amount, percentage)));

        expense.Amount = resultingAmount;
        expense.SplitMode = resultingMode;
        expense.Description = dto.Description ?? expense.Description;
        expense.PaidBy = dto.PaidBy ?? expense.PaidBy;
        expense.Date = ExpenseDate.Normalize(dto.Date) ?? expense.Date;
        expense.UpdatedAt = DateTime.UtcNow;
        
        if (dto.ExpenseSplits is not null)
        {
            expense.Splits = dto.ExpenseSplits.Zip(resultingPercentages, (s, percentage) => new ExpenseSplit
            {
                Id = s.Id,
                Amount = s.Amount,
                UserId = s.UserId,
                Percentage = percentage,
            }).ToList();
        }
        else
        {
            foreach (var (split, percentage) in expense.Splits.Zip(resultingPercentages))
            {
                split.Percentage = percentage;
            }
        }
        
        await expenseRepository.UpdateAsync(expense);
        return expense;
    }

    /// <summary>
    /// The percentage each split row should store under <paramref name="mode"/>: what was
    /// supplied when the mode is <see cref="SplitMode.Percentage"/>, and <c>null</c>
    /// otherwise. Nulling rather than rejecting is what lets a client switch an expense
    /// back to an equal split without first stripping the fields it no longer means.
    /// </summary>
    private static List<decimal?> PercentagesFor(SplitMode? mode, IEnumerable<decimal?> supplied) =>
        mode is SplitMode.Percentage
            ? supplied.ToList()
            : supplied.Select(_ => (decimal?)null).ToList();

    /// The expense must belong to the group the request was made against, otherwise a
    /// member of group A could read or delete an expense of group B.
    private async Task<Expense> FindInGroupAsync(int groupId, int expenseId)
    {
        var expense = await expenseRepository.FindByIdAsync(expenseId);

        if (expense is null || expense.GroupId != groupId)
        {
            throw new KeyNotFoundException("Expense not found");
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

    private async Task EnsureMembersAsync(int groupId, IEnumerable<int> userIds)
    {
        foreach (var userId in userIds.Distinct())
        {
            await EnsureMemberAsync(groupId, userId);
        }
    }
}
