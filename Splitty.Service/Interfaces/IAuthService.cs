using Splitty.Domain.Entities;

namespace Splitty.Service.Interfaces;

public interface IAuthService
{
    Task<(User user, string token)> Register(string name, string email, string password);
    Task<(User user, string token)> Login(string email, string password);
    Task<User?> GetProfile(int userId);
}