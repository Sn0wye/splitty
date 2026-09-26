using System.Text.Json;
using Splitty.Domain.Entities;
using Splitty.DTO.Response;
using Splitty.Repository.Interfaces;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

/// <summary>
/// Aggregates straight off the expense rows rather than the balances, so an expense counts
/// the moment it is saved and nothing waits on the recomputation worker.
/// </summary>
public class GroupStatsService(IExpenseRepository expenseRepository) : IGroupStatsService
{
    private const int TopPerCategory = 5;

    public async Task<GroupStatsResponse> GetStatsAsync(int groupId, int userId, StatsRange range)
    {
        var expenses = await expenseRepository.FindExpensesInRangeAsync(groupId, range.Start, range.End);

        return new GroupStatsResponse
        {
            Group = Summarize(expenses.Select(e => new SpendRow(e, e.Amount))),
            Mine = Summarize(expenses
                .Select(e => new SpendRow(e, e.Splits.Where(s => s.UserId == userId).Sum(s => s.Amount)))
                // Every stored split is positive, so zero means the caller has no split.
                .Where(r => r.Amount != 0))
        };
    }

    private readonly record struct SpendRow(Expense Expense, decimal Amount)
    {
        public DateTime Date => Expense.Date ?? Expense.CreatedAt;
    }

    private static SpendStatsResponse Summarize(IEnumerable<SpendRow> rows)
    {
        var all = rows.ToList();

        var categories = all
            .GroupBy(r => r.Expense.Category)
            .Select(byCategory => new CategoryStatsResponse
            {
                Category = byCategory.Key,
                Total = byCategory.Sum(r => r.Amount),
                ExpenseCount = byCategory.Count(),
                Top = byCategory
                    .OrderByDescending(r => r.Amount)
                    .ThenByDescending(r => r.Date)
                    .ThenByDescending(r => r.Expense.Id)
                    .Take(TopPerCategory)
                    .Select(r => new TopExpenseResponse
                    {
                        ExpenseId = r.Expense.Id,
                        Description = r.Expense.Description,
                        Date = r.Date,
                        Amount = r.Amount
                    })
                    .ToList()
            })
            .Where(c => c.Total != 0)
            .OrderByDescending(c => c.Total)
            .ThenBy(c => Token(c.Category), StringComparer.Ordinal)
            .ToList();

        return new SpendStatsResponse
        {
            Total = all.Sum(r => r.Amount),
            ExpenseCount = all.Count,
            Categories = categories
        };
    }

    /// The category as it reaches the client, so ties sort the way the client reads them.
    private static string Token(ExpenseCategory category) =>
        JsonNamingPolicy.SnakeCaseLower.ConvertName(category.ToString());
}
