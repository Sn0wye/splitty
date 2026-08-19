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
        EnsureExpenseSplitInvariants(ExpenseType.Expense, dto.Amount, dto.ExpenseSplits.Select(s => s.Amount));

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
            Splits = splits.Select(s => new ExpenseSplit
            {
                Amount = s.Amount,
                UserId = s.UserId,
            }).ToList()
        };

        await expenseRepository.CreateAsync(expense);
        
        return (await expenseRepository.FindByIdAsync(expense.Id))!;
    }

    public async Task<Expense?> FindByIdAsync(int id)
    {
        return await expenseRepository.FindByIdAsync(id);
    }
    
    public async Task<List<Expense>> FindExpensesByGroupId(int groupId, int userId)
    {
        await EnsureMemberAsync(groupId, userId);

        return await expenseRepository.FindExpensesByGroupId(groupId);
    }
    
    public async Task<Expense> UpdateAsync(UpdateExpenseDTO dto, int userId)
    {
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

        // Validate the resulting state, not just the supplied fields: an
        // amount-only update must not leave a nonmember payer or split behind.
        await EnsureMemberAsync(expense.GroupId, dto.PaidBy ?? expense.PaidBy);
        await EnsureMembersAsync(
            expense.GroupId,
            dto.ExpenseSplits is not null
                ? dto.ExpenseSplits.Select(s => s.UserId)
                : expense.Splits.Select(s => s.UserId));

        var resultingAmount = dto.Amount ?? expense.Amount;
        IEnumerable<decimal> resultingSplits = dto.ExpenseSplits is not null
            ? dto.ExpenseSplits.Select(s => s.Amount)
            : expense.Splits.Select(s => s.Amount);

        EnsureExpenseSplitInvariants(expense.Type, resultingAmount, resultingSplits);

        expense.Amount = resultingAmount;
        expense.Description = dto.Description ?? expense.Description;
        expense.PaidBy = dto.PaidBy ?? expense.PaidBy;
        
        if (dto.ExpenseSplits is not null)
        {
            expense.Splits = dto.ExpenseSplits.Select(s => new ExpenseSplit
            {
                Id = s.Id,
                Amount = s.Amount,
                UserId = s.UserId,
            }).ToList();
        }
        
        await expenseRepository.UpdateAsync(expense);
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

    private static void EnsureExpenseSplitInvariants(ExpenseType type, decimal amount, IEnumerable<decimal>? splitAmounts)
    {
        if (type != ExpenseType.Expense) return;

        var splits = splitAmounts?.ToList();

        if (splits is null || splits.Count == 0)
        {
            throw new ArgumentException("An expense must have at least one split.");
        }

        if (amount <= 0)
        {
            throw new ArgumentException("Expense amount must be greater than zero.");
        }

        if (splits.Any(split => split <= 0))
        {
            throw new ArgumentException("Expense splits must be greater than zero.");
        }

        if (splits.Sum() != amount)
        {
            throw new ArgumentException("Expense splits must sum to the total.");
        }
    }
}
