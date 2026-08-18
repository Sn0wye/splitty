using System.Security.Cryptography;
using Microsoft.EntityFrameworkCore;
using Splitty.Domain.Entities;
using Splitty.Repository.Interfaces;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

public class InviteService(
    IInviteRepository inviteRepository,
    IGroupRepository groupRepository,
    IGroupMembershipRepository groupMembershipRepository
) : IInviteService
{
    private const string CodeAlphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    private const int CodeLength = 6;
    private const int MaxCodeAttempts = 5;

    private static readonly TimeSpan DefaultLifetime = TimeSpan.FromDays(7);
    private static readonly TimeSpan MaxLifetime = TimeSpan.FromDays(30);

    public async Task<CreateInviteResult> CreateAsync(int groupId, int userId, int? maxUses, DateTime? expiresAt)
    {
        if (maxUses is <= 0) return new CreateInviteResult(CreateInviteStatus.InvalidMaxUses);

        var group = await groupRepository.GetGroupByIdAsync(groupId);

        if (group is null) return new CreateInviteResult(CreateInviteStatus.GroupNotFound);

        if (await groupMembershipRepository.GetGroupMembershipByUserIdAndGroupId(userId, groupId) is null)
        {
            return new CreateInviteResult(CreateInviteStatus.NotAMember);
        }

        var now = DateTime.UtcNow;
        var requested = expiresAt?.ToUniversalTime() ?? now.Add(DefaultLifetime);

        if (requested <= now) return new CreateInviteResult(CreateInviteStatus.InvalidExpiry);

        var capped = requested > now.Add(MaxLifetime) ? now.Add(MaxLifetime) : requested;

        for (var attempt = 0; attempt < MaxCodeAttempts; attempt++)
        {
            var invite = new Invite
            {
                GroupId = groupId,
                Code = GenerateCode(),
                CreatedBy = userId,
                CreatedAt = now,
                ExpiresAt = capped,
                MaxUses = maxUses
            };

            try
            {
                return new CreateInviteResult(CreateInviteStatus.Success, await inviteRepository.CreateAsync(invite));
            }
            catch (DbUpdateException) when (attempt < MaxCodeAttempts - 1)
            {
                // Code collided with an existing invite; draw another one.
            }
        }

        throw new InvalidOperationException("Could not allocate a unique invite code");
    }

    public async Task<RedeemInviteResult> RedeemAsync(string code, int userId)
    {
        var invite = await inviteRepository.GetByCodeAsync(code.Trim().ToUpperInvariant());

        if (invite is null) return new RedeemInviteResult(RedeemInviteStatus.NotFound);

        if (invite.ExpiresAt <= DateTime.UtcNow) return new RedeemInviteResult(RedeemInviteStatus.Expired);

        if (await groupMembershipRepository.GetGroupMembershipByUserIdAndGroupId(userId, invite.GroupId) is not null)
        {
            return new RedeemInviteResult(RedeemInviteStatus.AlreadyMember, invite.GroupId);
        }

        if (!await inviteRepository.TryConsumeAsync(invite.Id))
        {
            return new RedeemInviteResult(RedeemInviteStatus.Exhausted);
        }

        try
        {
            await groupMembershipRepository.CreateAsync(new GroupMembership
            {
                UserId = userId,
                GroupId = invite.GroupId
            });
        }
        catch (DbUpdateException)
        {
            // Lost a race against a concurrent redemption by the same user.
            return new RedeemInviteResult(RedeemInviteStatus.AlreadyMember, invite.GroupId);
        }

        return new RedeemInviteResult(RedeemInviteStatus.Success, invite.GroupId);
    }

    private static string GenerateCode() => RandomNumberGenerator.GetString(CodeAlphabet, CodeLength);
}
