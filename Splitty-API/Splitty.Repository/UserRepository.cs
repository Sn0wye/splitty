using Microsoft.EntityFrameworkCore;
using Splitty.Domain.Entities;
using Splitty.Infrastructure;
using Splitty.Repository.Interfaces;

namespace Splitty.Repository;

public class UserRepository(ApplicationDbContext context): IUserRepository
{
    public async Task CreateAsync(User user)
    {
        var entry = await context.User.AddAsync(user);

        try
        {
            await context.SaveChangesAsync();
        }
        catch (DbUpdateException ex) when (ex.IsUniqueViolation())
        {
            // Leaving the failed insert tracked would replay it on the next save.
            entry.State = EntityState.Detached;

            throw new InvalidOperationException("User with this email already exists.");
        }
    }

    public async Task<User?> GetByEmailAsync(string email)
    {
        if (string.IsNullOrWhiteSpace(email))
        {
            throw new ArgumentException("Email cannot be null or empty.", nameof(email));
        }

        // Tombstones store an empty email, but the unique index only covers live rows.
        return await context.User.FirstOrDefaultAsync(u => u.Email == email && u.DeletedAt == null);
    }

    public async Task<User?> GetByIdAsync(int id)
    {
        return await context.User
            .FirstOrDefaultAsync(u => u.Id == id);
    }

    public async Task UpdateAsync(User user)
    {
        if (user == null)
        {
            throw new ArgumentNullException(nameof(user));
        }
        
        context.User.Update(user);
        await context.SaveChangesAsync();
    }

    /// The per-request revocation check: one primary-key lookup.
    public Task<bool> AcceptsTokenAsync(int id, int tokenVersion) =>
        context.User.AnyAsync(u => u.Id == id
            && u.DeletedAt == null
            && u.DeactivatedAt == null
            && u.TokenVersion == tokenVersion);

    /// <summary>
    /// Rewrites the user as a `[removed]` tombstone in one transaction, so a failure
    /// partway leaves the account as it was. A membership is dropped only when it carries
    /// no money: a nonzero net stays on the tombstone so the group still sums to zero, and
    /// a pending group's stored net may be stale, so it is kept too. Every group left with
    /// no live member is then deleted, which cascades its expenses, balances and invites.
    /// </summary>
    public async Task TombstoneAsync(int id)
    {
        await using var transaction = await context.Database.BeginTransactionAsync();

        var now = DateTime.UtcNow;

        await context.User
            .Where(u => u.Id == id)
            .ExecuteUpdateAsync(setters => setters
                .SetProperty(u => u.Name, User.TombstoneName)
                .SetProperty(u => u.Email, string.Empty)
                .SetProperty(u => u.AvatarUrl, string.Empty)
                .SetProperty(u => u.AvatarKey, (string?)null)
                .SetProperty(u => u.DeletedAt, now)
                .SetProperty(u => u.UpdatedAt, now));

        await context.OAuthAccount.Where(a => a.UserId == id).ExecuteDeleteAsync();

        var groupIds = await context.GroupMembership
            .Where(m => m.UserId == id)
            .Select(m => m.GroupId)
            .ToListAsync();

        // The replay reads splits, not memberships, so dropping a zero-net one changes no money.
        await context.GroupMembership
            .Where(m => m.UserId == id
                && !m.Group.BalancesPending
                && (context.Balance
                    .Where(b => b.GroupId == m.GroupId && b.UserId == id)
                    .Sum(b => (decimal?)b.Amount) ?? 0m) == 0m)
            .ExecuteDeleteAsync();

        await context.Group
            .Where(g => groupIds.Contains(g.Id) && !g.Members.Any(m => m.User.DeletedAt == null))
            .ExecuteDeleteAsync();

        await transaction.CommitAsync();
    }
}
