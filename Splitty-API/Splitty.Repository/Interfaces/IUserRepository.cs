using Splitty.Domain.Entities;

namespace Splitty.Repository.Interfaces;

public interface IUserRepository
{
    Task CreateAsync(User user);
    Task<User?> GetByEmailAsync(string email);
    Task<User?> GetByIdAsync(int id);
    Task UpdateAsync(User user);
}