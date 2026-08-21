using Splitty.Domain.Entities;

namespace Splitty.Service.Interfaces;

public interface IOAuthService
{
    Task<(User user, string token)> SignInWithGoogleAsync(string authCode, CancellationToken cancellationToken = default);
}
