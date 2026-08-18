using Splitty.Domain.Entities;

namespace Splitty.Repository.Interfaces;

public enum InviteRedemptionOutcome
{
    Success,
    Exhausted,
    AlreadyMember
}

public interface IInviteRepository
{
    /// Persists the invite. Returns null when its code collided with an existing one.
    Task<Invite?> TryCreateAsync(Invite invite);
    Task<Invite?> GetByCodeAsync(string code);

    /// Claims one use of the invite and creates the membership as a single unit:
    /// a failed membership insert leaves the use count untouched.
    Task<InviteRedemptionOutcome> TryRedeemAsync(int inviteId, GroupMembership membership);
}
