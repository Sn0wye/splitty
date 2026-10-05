using Microsoft.EntityFrameworkCore;
using Splitty.Domain.Entities;
using Splitty.Infrastructure;
using Splitty.Repository.Interfaces;

namespace Splitty.Repository;

public class RefreshTokenRepository(ApplicationDbContext context) : IRefreshTokenRepository
{
    public async Task CreateAsync(RefreshToken token)
    {
        await context.RefreshToken.AddAsync(token);
        await context.SaveChangesAsync();
    }

    public async Task<RefreshToken?> GetByHashAsync(string tokenHash)
    {
        return await context.RefreshToken
            .Include(t => t.User)
            .AsNoTracking()
            .FirstOrDefaultAsync(t => t.TokenHash == tokenHash);
    }

    public async Task<bool> TryRotateAsync(Guid currentId, RefreshToken replacement)
    {
        await using var transaction = await context.Database.BeginTransactionAsync();

        // The replacement goes in first so the current row can point at it.
        var entry = await context.RefreshToken.AddAsync(replacement);
        await context.SaveChangesAsync();

        // Conditional on RevokedAt so that of two requests presenting the same token, only
        // one claims it: the second blocks on the row lock, then matches nothing.
        var claimed = await context.RefreshToken
            .Where(t => t.Id == currentId && t.RevokedAt == null)
            .ExecuteUpdateAsync(setters => setters
                .SetProperty(t => t.RevokedAt, DateTime.UtcNow)
                .SetProperty(t => t.ReplacedById, replacement.Id));

        if (claimed == 0)
        {
            // The rolled-back insert is still tracked as saved; stop the context believing it exists.
            entry.State = EntityState.Detached;

            await transaction.RollbackAsync();

            return false;
        }

        await transaction.CommitAsync();

        return true;
    }

    public async Task RevokeFamilyAsync(Guid familyId)
    {
        await context.RefreshToken
            .Where(t => t.FamilyId == familyId && t.RevokedAt == null)
            .ExecuteUpdateAsync(setters => setters.SetProperty(t => t.RevokedAt, DateTime.UtcNow));
    }

    public async Task RevokeAllForUserAsync(int userId)
    {
        await context.RefreshToken
            .Where(t => t.UserId == userId && t.RevokedAt == null)
            .ExecuteUpdateAsync(setters => setters.SetProperty(t => t.RevokedAt, DateTime.UtcNow));
    }
}
