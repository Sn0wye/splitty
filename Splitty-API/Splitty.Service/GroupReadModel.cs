using Microsoft.EntityFrameworkCore;
using Splitty.Domain.Entities;
using Splitty.DTO.Internal;
using Splitty.DTO.Response;
using Splitty.Infrastructure;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

/// <summary>
/// Group and expense wire contracts are projections, never entity graphs. Collections are
/// read separately, so members and pairwise balances cannot multiply each other's rows.
/// Avatar inputs stay inside this module; only the resolved URL reaches a response.
/// </summary>
public class GroupReadModel(ApplicationDbContext context, IAvatarResolver avatarResolver) : IGroupReadModel
{
    public Task<List<GroupDTO>> GetGroupsByUserId(int userId) =>
        ReadGroupsAsync(context.Group.Where(g => g.Members.Any(m => m.UserId == userId)), userId);

    public async Task<GroupDTO?> GetGroupAsync(int groupId, int userId) =>
        (await ReadGroupsAsync(context.Group.Where(g => g.Id == groupId &&
            g.Members.Any(m => m.UserId == userId)), userId)).SingleOrDefault();

    private async Task<List<GroupDTO>> ReadGroupsAsync(IQueryable<Group> query, int userId)
    {
        var groups = await query.AsNoTracking()
            .Select(g => new GroupDTO
            {
                Id = g.Id,
                Name = g.Name,
                Description = g.Description,
                CreatedAt = g.CreatedAt,
                NetBalance = g.Balances.Where(b => b.UserId == userId).Sum(b => (decimal?)b.Amount) ?? 0m
            }).ToListAsync();

        if (groups.Count == 0) return groups;

        var groupIds = groups.Select(g => g.Id).ToArray();
        var members = await context.GroupMembership.AsNoTracking()
            .Where(m => groupIds.Contains(m.GroupId))
            .OrderBy(m => m.Id)
            .Select(m => new
            {
                m.GroupId,
                m.Id,
                m.UserId,
                m.User.Name,
                m.User.Email,
                m.User.AvatarKey,
                ProviderUrl = m.User.AvatarUrl
            }).ToListAsync();

        var byGroup = members.ToLookup(m => m.GroupId, m => new MemberDTO
        {
            Id = m.Id,
            UserId = m.UserId,
            Name = m.Name,
            Email = m.Email,
            AvatarUrl = avatarResolver.Resolve(m.UserId, m.AvatarKey, m.ProviderUrl)
        });
        foreach (var group in groups) group.Members = byGroup[group.Id].ToList();
        return groups;
    }

    public async Task<List<ExpenseResponse>> GetExpensesAsync(int groupId, int userId)
    {
        await EnsureMemberAsync(groupId, userId);
        return await ReadExpensesAsync(context.Expense.Where(e => e.GroupId == groupId));
    }

    public async Task<ExpenseResponse> GetExpenseAsync(int groupId, int expenseId, int userId)
    {
        await EnsureMemberAsync(groupId, userId);
        return (await ReadExpensesAsync(context.Expense.Where(e => e.GroupId == groupId && e.Id == expenseId)))
            .SingleOrDefault() ?? throw new KeyNotFoundException("Expense not found");
    }

    /// <summary>
    /// One statement, so the expenses and their splits come from one snapshot. A split query
    /// reads them in two, and an expense written in between, such as a repeat the parallel
    /// group read adds (ADR 0006), leaves EF matching splits against rows it never read:
    /// the expenses after it come back with none. Splits are the only collection, so the
    /// join repeats each expense once per split and nothing multiplies.
    /// </summary>
    private async Task<List<ExpenseResponse>> ReadExpensesAsync(IQueryable<Expense> query)
    {
        var expenses = await query.AsNoTracking().AsSingleQuery()
            .OrderByDescending(e => e.Date ?? e.CreatedAt)
            .ThenByDescending(e => e.Id)
            .Select(e => new ExpenseResponse
            {
                Id = e.Id,
                GroupId = e.GroupId,
                PaidBy = e.PaidBy,
                Amount = e.Amount,
                Description = e.Description,
                Type = e.Type,
                SplitMode = e.SplitMode,
                Category = e.Category,
                Date = e.Date,
                CreatedAt = e.CreatedAt,
                UpdatedAt = e.UpdatedAt,
                RecurringExpenseId = e.RecurringExpenseId,
                Repeat = e.RecurringExpense == null ? null : e.RecurringExpense.Frequency,
                Splits = e.Splits.OrderBy(s => s.Id).Select(s => new ExpenseSplitResponse
                {
                    Id = s.Id,
                    ExpenseId = s.ExpenseId,
                    UserId = s.UserId,
                    Amount = s.Amount,
                    Percentage = s.Percentage
                }).ToList()
            }).ToListAsync();

        if (expenses.Count == 0) return expenses;

        // Include payers even when they are not participants, and departed members whose
        // historical expenses remain. User rows are projected once for the whole response.
        var userIds = expenses.SelectMany(e => e.Splits.Select(s => s.UserId).Append(e.PaidBy))
            .Distinct().ToArray();
        var users = await context.User.AsNoTracking()
            .Where(u => userIds.Contains(u.Id))
            .Select(u => new
            {
                u.Id, u.Name, u.Email, u.AvatarKey, ProviderUrl = u.AvatarUrl, u.CreatedAt, u.UpdatedAt
            }).ToListAsync();
        var byId = users.ToDictionary(u => u.Id, u => new ExpenseUserResponse
        {
            Id = u.Id,
            Name = u.Name,
            Email = u.Email,
            AvatarUrl = avatarResolver.Resolve(u.Id, u.AvatarKey, u.ProviderUrl),
            CreatedAt = u.CreatedAt,
            UpdatedAt = u.UpdatedAt
        });
        foreach (var expense in expenses)
        {
            expense.PaidByUser = byId[expense.PaidBy];
            foreach (var split in expense.Splits) split.User = byId[split.UserId];
        }
        return expenses;
    }

    public Task<bool> GroupExistsAsync(int groupId) =>
        context.Group.AnyAsync(g => g.Id == groupId);

    /// A tombstone keeps its membership row only to carry its balance, so it is not a
    /// member here. The settle path reads the row directly, which is what lets a debtor
    /// still pay a deleted creditor.
    public Task<bool> IsMemberAsync(int groupId, int userId) =>
        context.GroupMembership.AnyAsync(m => m.GroupId == groupId && m.UserId == userId
            && m.User.DeletedAt == null);

    public async Task<decimal> GetMemberNetAsync(int groupId, int userId) =>
        await context.Balance.Where(b => b.GroupId == groupId && b.UserId == userId)
            .SumAsync(b => (decimal?)b.Amount) ?? 0m;

    private async Task EnsureMemberAsync(int groupId, int userId)
    {
        if (!await IsMemberAsync(groupId, userId))
            throw new UnauthorizedAccessException("User is not a member of the group");
    }
}
