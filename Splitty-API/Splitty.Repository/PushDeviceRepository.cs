using Microsoft.EntityFrameworkCore;
using Splitty.Domain.Entities;
using Splitty.Infrastructure;
using Splitty.Repository.Interfaces;

namespace Splitty.Repository;

public class PushDeviceRepository(ApplicationDbContext context) : IPushDeviceRepository
{
    public async Task UpsertAsync(PushDevice device)
    {
        await using var transaction = await context.Database.BeginTransactionAsync();

        // One statement, so two registrations of the same token cannot both insert.
        await context.Database.ExecuteSqlInterpolatedAsync($"""
            INSERT INTO "PushDevice" ("Token", "UserId", "FamilyId", "Environment", "Language", "UpdatedAt")
            VALUES ({device.Token}, {device.UserId}, {device.FamilyId}, {device.Environment.ToString()},
                    {device.Language}, {device.UpdatedAt})
            ON CONFLICT ("Token") DO UPDATE SET
                "UserId" = EXCLUDED."UserId",
                "FamilyId" = EXCLUDED."FamilyId",
                "Environment" = EXCLUDED."Environment",
                "Language" = EXCLUDED."Language",
                "UpdatedAt" = EXCLUDED."UpdatedAt"
            """);

        // A sign-in is one device, so a token it registered before is that device's old token.
        await context.PushDevice
            .Where(d => d.FamilyId == device.FamilyId && d.Token != device.Token)
            .ExecuteDeleteAsync();

        await transaction.CommitAsync();
    }

    public Task<List<PushDevice>> GetSignedInAsync(int userId)
    {
        var now = DateTime.UtcNow;

        return context.PushDevice.AsNoTracking()
            .Where(d => d.UserId == userId
                && context.RefreshToken.Any(t => t.FamilyId == d.FamilyId
                    && t.UserId == userId
                    && t.RevokedAt == null
                    && t.ExpiresAt > now))
            .ToListAsync();
    }

    public Task DeleteAsync(int id) =>
        context.PushDevice.Where(d => d.Id == id).ExecuteDeleteAsync();
}
