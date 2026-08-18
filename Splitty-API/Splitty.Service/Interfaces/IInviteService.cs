using Splitty.Domain.Entities;

namespace Splitty.Service.Interfaces;

public enum CreateInviteStatus
{
    Success,
    GroupNotFound,
    NotAMember,
    InvalidExpiry,
    InvalidMaxUses,
    CodeUnavailable
}

public enum RedeemInviteStatus
{
    Success,
    NotFound,
    Expired,
    Exhausted,
    AlreadyMember
}

public record CreateInviteResult(CreateInviteStatus Status, Invite? Invite = null);

public record RedeemInviteResult(RedeemInviteStatus Status, int GroupId = 0);

public interface IInviteService
{
    Task<CreateInviteResult> CreateAsync(int groupId, int userId, int? maxUses, DateTime? expiresAt);
    Task<RedeemInviteResult> RedeemAsync(string code, int userId);
}
