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
        await EnsureMemberAsync(dto.GroupId, userId);
        await EnsureMemberAsync(dto.GroupId, dto.PaidBy);
        await EnsureMembersAsync(dto.GroupId, dto.ExpenseSplits.Select(s => s.UserId));

        var expense = new Expense
        {
            Amount = dto.Amount,
            Description = dto.Description,
            GroupId = dto.GroupId,
            PaidBy = dto.PaidBy,
            Splits = dto.ExpenseSplits.Select(s => new ExpenseSplit
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
            throw new ArgumentException("Expense not found");
        }

        // The expense must belong to the group the request was made against,
        // otherwise a member of group A could edit an expense of group B.
        if (dto.GroupId is not null && dto.GroupId != expense.GroupId)
        {
            throw new UnauthorizedAccessException("Expense does not belong to the group");
        }

        await EnsureMemberAsync(expense.GroupId, userId);

        if (dto.PaidBy is not null)
        {
            await EnsureMemberAsync(expense.GroupId, dto.PaidBy.Value);
        }

        if (dto.ExpenseSplits is not null)
        {
            await EnsureMembersAsync(expense.GroupId, dto.ExpenseSplits.Select(s => s.UserId));
        }

        expense.Amount = dto.Amount ?? expense.Amount;
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
}
