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

    /// Claims one use of the invite and creates the membership as a single unit:
    /// a failed membership insert leaves the use count untouched.
    public async Task<InviteRedemptionOutcome> TryRedeemAsync(int inviteId, GroupMembership membership)
    {
        await using var transaction = await context.Database.BeginTransactionAsync();

        var claimed = await context.Database.ExecuteSqlInterpolatedAsync(
            $"""
             UPDATE "Invite" SET "UsedCount" = "UsedCount" + 1
             WHERE "Id" = {inviteId} AND ("MaxUses" IS NULL OR "UsedCount" < "MaxUses")
             """);

        if (claimed == 0)
        {
            await transaction.RollbackAsync();

            return InviteRedemptionOutcome.Exhausted;
        }

        var entry = await context.GroupMembership.AddAsync(membership);

        try
        {
            await context.SaveChangesAsync();
        }
        catch (DbUpdateException ex) when (ex.IsUniqueViolation())
        {
            // Leaving the failed insert tracked would replay it on the next save.
            entry.State = EntityState.Detached;

            await transaction.RollbackAsync();

            return InviteRedemptionOutcome.AlreadyMember;
        }

        await transaction.CommitAsync();

        return InviteRedemptionOutcome.Success;
    }
}
