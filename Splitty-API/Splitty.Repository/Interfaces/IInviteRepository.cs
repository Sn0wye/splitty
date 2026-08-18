using Splitty.Domain.Entities;

namespace Splitty.Repository.Interfaces;

public interface IInviteRepository
{
    /// Persists the invite. Returns null when its code collided with an existing one.
    Task<Invite?> TryCreateAsync(Invite invite);
    Task<Invite?> GetByCodeAsync(string code);
    Task<bool> TryConsumeAsync(int inviteId);
}
