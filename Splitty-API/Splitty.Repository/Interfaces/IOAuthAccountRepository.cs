using Splitty.Domain.Entities;

namespace Splitty.Repository.Interfaces;

public interface IOAuthAccountRepository
{
    Task<OAuthAccount?> GetByProviderSubjectAsync(OAuthProvider provider, string subject);
    Task CreateAsync(OAuthAccount account);
}
