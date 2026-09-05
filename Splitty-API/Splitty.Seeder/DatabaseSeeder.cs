using Microsoft.EntityFrameworkCore;
using Splitty.Background;
using Splitty.Domain.Entities;
using Splitty.Infrastructure;

namespace Splitty.Seeder;

/// <summary>
/// Writes the development data set and asks for its balances.
///
/// It requests a recomputation per group through <see cref="IBalanceRecomputeQueue"/> and
/// never replays balances itself: invariant 4 says the replay has exactly one caller, the
/// background worker, and a test pins that caller list.
/// </summary>
public sealed class DatabaseSeeder(ApplicationDbContext context, IBalanceRecomputeQueue queue)
{
    /// <summary>The seeded addresses, in seed order. `POST /auth/dev-login` takes any of them.</summary>
    public static IReadOnlyList<string> UserEmails { get; } =
        SeedData.Users.Select(user => user.Email).ToList();

    /// <summary>
    /// The user a developer signs in as by default. The data set is arranged around them:
    /// they owe in one group and are owed in another.
    /// </summary>
    public static string PrimaryUserEmail => SeedData.John;

    /// <summary>
    /// Resets the tables the seeder owns, writes the data set, and enqueues one
    /// recomputation per group. Returns the seeded group ids, in seed order.
    /// </summary>
    public async Task<IReadOnlyList<int>> SeedAsync(CancellationToken cancellationToken = default)
    {
        await ResetAsync(cancellationToken);

        var users = SeedData.Users.ToDictionary(
            seeded => seeded.Email,
            seeded => new User { Name = seeded.Name, Email = seeded.Email });

        context.User.AddRange(users.Values);
        await context.SaveChangesAsync(cancellationToken);

        var groupIds = new List<int>();

        foreach (var seededGroup in SeedData.Groups)
        {
            var group = new Group
            {
                Name = seededGroup.Name,
                Description = seededGroup.Description,
                CreatedBy = users[seededGroup.CreatedBy].Id,
                Members = seededGroup.Members
                    .Select(email => new GroupMembership { UserId = users[email].Id })
                    .ToList()
            };

            context.Group.Add(group);
            await context.SaveChangesAsync(cancellationToken);

            foreach (var entry in seededGroup.Entries)
            {
                Validate(entry);

                context.Expense.Add(new Expense
                {
                    GroupId = group.Id,
                    Description = entry.Description,
                    Amount = entry.Amount,
                    PaidBy = users[entry.PaidBy].Id,
                    Type = entry.Type,
                    SplitMode = entry.Mode,
                    Date = DateTime.UtcNow.Date.AddDays(-entry.DaysAgo),
                    Splits = entry.Splits
                        .Select(split => new ExpenseSplit
                        {
                            UserId = users[split.Email].Id,
                            Amount = split.Amount,
                            Percentage = split.Percentage
                        })
                        .ToList()
                });
            }

            await context.SaveChangesAsync(cancellationToken);
            groupIds.Add(group.Id);
        }

        foreach (var groupId in groupIds)
        {
            await queue.EnqueueAsync(groupId, cancellationToken);
        }

        return groupIds;
    }

    /// <summary>
    /// Clearing first is what makes a second run safe. Appending a second "Game Night"
    /// would be worse than refusing, and refusing would mean dropping the database by hand
    /// to get back to a known state. Everything here is development-only data.
    /// </summary>
    private async Task ResetAsync(CancellationToken cancellationToken)
    {
        // Child rows first: nothing relies on a cascade being configured.
        await context.Balance.ExecuteDeleteAsync(cancellationToken);
        await context.ExpenseSplit.ExecuteDeleteAsync(cancellationToken);
        await context.Expense.ExecuteDeleteAsync(cancellationToken);
        await context.Invite.ExecuteDeleteAsync(cancellationToken);
        await context.GroupMembership.ExecuteDeleteAsync(cancellationToken);
        await context.Group.ExecuteDeleteAsync(cancellationToken);
        await context.OAuthAccount.ExecuteDeleteAsync(cancellationToken);
        await context.User.ExecuteDeleteAsync(cancellationToken);
    }

    /// <summary>
    /// The rules the API enforces on a client, checked against the data set so a seeded row
    /// is never one the API would have refused — a row the app cannot re-save is a trap for
    /// whoever edits it next. Deliberately duplicated rather than shared:
    /// <c>ExpenseSplitInvariants</c> is internal to Splitty.Service, and this checks static
    /// data at write time rather than a request. A stray percentage is refused here though
    /// the API would null it, because seeded data should say what it means.
    /// </summary>
    private static void Validate(SeedEntry entry)
    {
        if (entry.Type is ExpenseType.Payment)
        {
            if (entry.Mode is not null
                || entry.Splits.Count != 2
                || entry.Splits.Sum(split => split.Amount) != 0m
                || Math.Abs(entry.Splits[0].Amount) != entry.Amount)
            {
                throw new InvalidOperationException(
                    $"Seeded settlement '{entry.Description}' is not a valid payment.");
            }

            return;
        }

        if (entry.Mode is null)
        {
            throw new InvalidOperationException($"Seeded expense '{entry.Description}' has no split mode.");
        }

        if (entry.Amount <= 0m || entry.Splits.Count == 0)
        {
            throw new InvalidOperationException($"Seeded expense '{entry.Description}' has nothing to split.");
        }

        if (entry.Splits.Any(split => split.Amount <= 0m))
        {
            throw new InvalidOperationException(
                $"Seeded expense '{entry.Description}' has a split at or below zero. Omit the member instead.");
        }

        if (entry.Splits.Sum(split => split.Amount) != entry.Amount)
        {
            throw new InvalidOperationException(
                $"Seeded expense '{entry.Description}' has splits that do not sum to its amount.");
        }

        var percentages = entry.Splits.Where(split => split.Percentage is not null).ToList();

        if (entry.Mode is SplitMode.Percentage)
        {
            if (percentages.Count != entry.Splits.Count || percentages.Sum(split => split.Percentage!.Value) != 100m)
            {
                throw new InvalidOperationException(
                    $"Seeded expense '{entry.Description}' must carry percentages on every split, summing to 100.");
            }
        }
        else if (percentages.Count > 0)
        {
            throw new InvalidOperationException(
                $"Seeded expense '{entry.Description}' carries a percentage outside a percentage split.");
        }
    }
}
