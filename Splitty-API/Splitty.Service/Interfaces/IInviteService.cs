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

public enum DescribeInviteStatus
{
    Success,
    NotFound,
    Expired,
    Exhausted
}

public record CreateInviteResult(CreateInviteStatus Status, Invite? Invite = null);

public record RedeemInviteResult(RedeemInviteStatus Status, int GroupId = 0);

public record InviteMetadata(string GroupName, int MemberCount, string CreatedByName, bool AlreadyMember);

public record DescribeInviteResult(DescribeInviteStatus Status, InviteMetadata? Metadata = null);

public interface IInviteService
{
    Task<CreateInviteResult> CreateAsync(int groupId, int userId, int? maxUses, DateTime? expiresAt);
    Task<RedeemInviteResult> RedeemAsync(string code, int userId);
    Task<DescribeInviteResult> DescribeAsync(string code, int userId);
}
