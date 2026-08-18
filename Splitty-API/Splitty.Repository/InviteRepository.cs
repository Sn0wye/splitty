using Microsoft.EntityFrameworkCore;
using Splitty.Domain.Entities;
using Splitty.Infrastructure;
using Splitty.Repository.Interfaces;

namespace Splitty.Repository;

public class InviteRepository(ApplicationDbContext context) : IInviteRepository
{
    public async Task<Invite> CreateAsync(Invite invite)
    {
        await context.Invite.AddAsync(invite);
        await context.SaveChangesAsync();

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
