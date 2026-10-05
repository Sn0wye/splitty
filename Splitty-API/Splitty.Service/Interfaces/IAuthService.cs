using Splitty.Domain.Entities;

namespace Splitty.Service.Interfaces;

public interface IAuthService
{
    /// Mints an access token and a refresh token for an existing user with no credential
    /// check. Only ever reachable through the Development-only endpoint; see
    /// `DevAuthController`.
    Task<(User user, string token, string refreshToken)> DevLogin(string email);
}
