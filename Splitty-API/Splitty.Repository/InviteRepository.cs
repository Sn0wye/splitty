using Microsoft.EntityFrameworkCore;
using Splitty.Domain.Entities;
using Splitty.Infrastructure;
using Splitty.Repository.Interfaces;

namespace Splitty.Repository;

public class InviteRepository(ApplicationDbContext context) : IInviteRepository
{
    /// Persists the invite. Returns null when its code collided with an existing one.
    public async Task<Invite?> TryCreateAsync(Invite invite)
    {
        var entry = await context.Invite.AddAsync(invite);

        try
        {
            await context.SaveChangesAsync();
        }
        catch (DbUpdateException ex) when (ex.IsUniqueViolation())
        {
            // Leaving the failed insert tracked would replay it on the next save.
            entry.State = EntityState.Detached;

            return null;
        }

        return invite;
    }

    public async Task<Invite?> GetByCodeAsync(string code)
    {
        return await context.Invite
            .AsNoTracking()
            .FirstOrDefaultAsync(i => i.Code == code);
    }

    /// Atomically claims one use of the invite. Returns false when it is exhausted.
    public async Task<bool> TryConsumeAsync(int inviteId)
    {
        var affected = await context.Database.ExecuteSqlInterpolatedAsync(
            $"""
             UPDATE "Invite" SET "UsedCount" = "UsedCount" + 1
             WHERE "Id" = {inviteId} AND ("MaxUses" IS NULL OR "UsedCount" < "MaxUses")
             """);

        return affected > 0;
    }
}
