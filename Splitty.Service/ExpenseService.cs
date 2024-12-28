using Splitty.Domain.Entities;
using Splitty.DTO.Internal;
using Splitty.Repository.Interfaces;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

public class ExpenseService(
    IExpenseRepository expenseRepository
    ): IExpenseService
{
    public async Task<Expense> CreateAsync(CreateExpenseDTO dto)
    {
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
        return await expenseRepository.FindExpensesByGroupId(groupId);
    }
    
    public async Task<Expense> UpdateAsync(UpdateExpenseDTO dto)
    {
        var expense = await expenseRepository.FindByIdAsync(dto.Id);

        if (expense is null)
        {
            Console.WriteLine("Expense not found");
            throw new ArgumentException("Expense not found");
        }
        
        // if (expense.Group.Members.All(m => m.UserId != dto.PaidBy))
        // {
        //     Console.WriteLine("User is not a member of the group");
        //     throw new UnauthorizedAccessException("User is not a member of the group");
        // }
        
        expense.Amount = dto.Amount ?? expense.Amount;
        expense.Description = dto.Description ?? expense.Description;
        expense.GroupId = dto.GroupId ?? expense.GroupId;
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
}