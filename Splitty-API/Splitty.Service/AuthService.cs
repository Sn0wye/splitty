using Splitty.Domain.Entities;
using Splitty.Repository.Interfaces;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

public class AuthService(
    IUserRepository userRepository,
    IJwtTokenIssuer tokenIssuer,
    IRefreshTokenService refreshTokenService
) : IAuthService
{
    public async Task<(User user, string token, string refreshToken)> DevLogin(string email)
    {
        var user = await userRepository.GetByEmailAsync(email);

        if (user is null)
        {
            throw new KeyNotFoundException("No user with this email.");
        }

        return (user, tokenIssuer.Issue(user), await refreshTokenService.IssueAsync(user));
    }
}
