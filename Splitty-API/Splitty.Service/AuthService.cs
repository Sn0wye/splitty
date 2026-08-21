using Splitty.Domain.Entities;
using Splitty.Repository.Interfaces;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

public class AuthService(
    IUserRepository userRepository,
    IJwtTokenIssuer tokenIssuer
) : IAuthService
{
    public async Task<User?> GetProfile(int userId)
    {
        return await userRepository.GetByIdAsync(userId);
    }

    public async Task<(User user, string token)> DevLogin(string email)
    {
        var user = await userRepository.GetByEmailAsync(email);

        if (user is null)
        {
            throw new KeyNotFoundException("No user with this email.");
        }

        return (user, tokenIssuer.Issue(user));
    }
}
