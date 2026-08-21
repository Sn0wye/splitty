using Microsoft.EntityFrameworkCore;
using Splitty.Domain.Entities;
using Splitty.Infrastructure;
using Splitty.Repository.Interfaces;

namespace Splitty.Repository;

public class OAuthAccountRepository(ApplicationDbContext context) : IOAuthAccountRepository
{
    public async Task<OAuthAccount?> GetByProviderSubjectAsync(OAuthProvider provider, string subject)
    {
        if (string.IsNullOrWhiteSpace(subject))
        {
            throw new ArgumentException("Subject cannot be null or empty.", nameof(subject));
        }

        return await context.OAuthAccount
            .Include(a => a.User)
            .AsNoTracking()
            .FirstOrDefaultAsync(a => a.Provider == provider && a.Subject == subject);
    }

    public async Task CreateAsync(OAuthAccount account)
    {
        var entry = await context.OAuthAccount.AddAsync(account);

        try
        {
            await context.SaveChangesAsync();
        }
        catch (DbUpdateException ex) when (ex.IsUniqueViolation())
        {
            // Leaving the failed insert tracked would replay it on the next save.
            entry.State = EntityState.Detached;

            throw new InvalidOperationException("This provider account is already linked.");
        }
    }
}
