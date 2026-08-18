using Splitty.Domain.Entities;

namespace Splitty.Repository.Interfaces;

public interface IInviteRepository
{
    Task<Invite> CreateAsync(Invite invite);
    Task<Invite?> GetByCodeAsync(string code);
    Task<bool> TryConsumeAsync(int inviteId);
}
