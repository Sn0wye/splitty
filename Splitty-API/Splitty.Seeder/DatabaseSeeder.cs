using Splitty.Domain.Entities;
using Splitty.Infrastructure;

namespace Splitty.Seeder;

public class DatabaseSeeder
{
    private static readonly Random _random = new Random();
    
    public static void Seed(ApplicationDbContext context)
    {
        var users = new List<User>
        {
            new() { Name = "John Doe", Email = "john@example.com", CreatedAt = DateTime.UtcNow, UpdatedAt = DateTime.UtcNow },
            new() { Name = "Jane Smith", Email = "jane@example.com", CreatedAt = DateTime.UtcNow, UpdatedAt = DateTime.UtcNow },
            new() { Name = "Bob Wilson", Email = "bob@example.com", CreatedAt = DateTime.UtcNow, UpdatedAt = DateTime.UtcNow },
            new() { Name = "Alice Brown", Email = "alice@example.com", CreatedAt = DateTime.UtcNow, UpdatedAt = DateTime.UtcNow },
            new() { Name = "Charlie Davis", Email = "charlie@example.com", CreatedAt = DateTime.UtcNow, UpdatedAt = DateTime.UtcNow },
            new() { Name = "Eva Johnson", Email = "eva@example.com", CreatedAt = DateTime.UtcNow, UpdatedAt = DateTime.UtcNow }
        };
        context.User.AddRange(users);
        context.SaveChanges();

        var groups = new List<Group>
        {
            new() { Name = "Vacation Trip", Description = "Summer vacation expenses", CreatedBy = users[0].Id, CreatedAt = DateTime.UtcNow, CreatedByUser = users[0] },
            new() { Name = "Shared Apartment", Description = "Monthly apartment expenses", CreatedBy = users[1].Id, CreatedAt = DateTime.UtcNow, CreatedByUser = users[1] },
            new() { Name = "Game Night", Description = "Weekly game night expenses", CreatedBy = users[2].Id, CreatedAt = DateTime.UtcNow, CreatedByUser = users[2] }
        };
        context.Group.AddRange(groups);
        context.SaveChanges();

        var memberships = new List<GroupMembership>();
        foreach (var group in groups)
        {
            // Get 3 random users for each group
            var groupUsers = users.OrderBy(x => _random.Next()).Take(3).ToList();
            foreach (var user in groupUsers)
            {
                memberships.Add(new GroupMembership
                {
                    GroupId = group.Id,
                    UserId = user.Id,
                    JoinedAt = DateTime.UtcNow,
                    User = user,
                    Group = group
                });
            }
        }
        context.GroupMembership.AddRange(memberships);
        context.SaveChanges();

        foreach (var group in groups)
        {
            var groupMemberships = memberships.Where(m => m.GroupId == group.Id).ToList();
            
            // Create 10 expenses per group
            for (int i = 0; i < 10; i++)
            {
                // Random amount between 10 and 200
                var amount = Math.Round((decimal)(_random.NextDouble() * 190 + 10), 2);
                
                // Random payer from group members
                var payer = groupMemberships[_random.Next(groupMemberships.Count)].User;

                // One percentage expense per group, so a client opening the seed data has
                // a real percentage split to read rather than only equal ones.
                var mode = i == 0 ? SplitMode.Percentage : SplitMode.Equal;

                var expense = new Expense
                {
                    GroupId = group.Id,
                    PaidBy = payer.Id,
                    Amount = amount,
                    Description = GetRandomExpenseDescription(),
                    Type = ExpenseType.Expense,
                    SplitMode = mode,
                    CreatedAt = DateTime.UtcNow,
                    UpdatedAt = DateTime.UtcNow,
                    Group = group,
                    PaidByUser = payer
                };
                context.Expense.Add(expense);
                context.SaveChanges();

                var splitAmount = Math.Round(amount / groupMemberships.Count, 2);

                // Amounts stay evenly divided either way: the mode describes how the split
                // was chosen, it is never what the amounts are computed from. The last
                // member absorbs the percentage remainder for the same reason.
                var evenPercentage = Math.Round(100m / groupMemberships.Count, 2);
                var splits = groupMemberships.Select((m, index) => new ExpenseSplit
                {
                    ExpenseId = expense.Id,
                    UserId = m.UserId,
                    Amount = splitAmount,
                    Percentage = mode == SplitMode.Percentage
                        ? index == groupMemberships.Count - 1
                            ? 100m - evenPercentage * (groupMemberships.Count - 1)
                            : evenPercentage
                        : null,
                    Expense = expense,
                    User = m.User
                }).ToList();
                
                context.ExpenseSplit.AddRange(splits);
                context.SaveChanges();
            }
        }
    }

    private static string GetRandomExpenseDescription()
    {
        var descriptions = new[]
        {
            "Groceries",
            "Restaurant bill",
            "Movie tickets",
            "Utilities",
            "Pizza night",
            "Transportation",
            "Coffee run",
            "Office supplies",
            "Snacks",
            "Party supplies",
            "Cleaning supplies",
            "Take out food",
            "Entertainment",
            "Group activity"
        };
        
        return descriptions[_random.Next(descriptions.Length)];
    }
}