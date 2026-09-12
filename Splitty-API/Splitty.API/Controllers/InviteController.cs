using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Splitty.DTO.Internal;
using Splitty.DTO.Response;
using Splitty.Service.Interfaces;

namespace Splitty.API.Controllers;

[ApiController]
[Route("invite")]
[Authorize]
public class InviteController(
    IInviteService inviteService,
    IGroupService groupService
) : ControllerBase
{
    /// Read-only: describes the invite so the client can confirm before joining.
    /// Shares the redemption rate-limit partition, or it would be a free oracle for
    /// guessing the codes redemption is protected against.
    [HttpGet("{code}")]
    [EnableRateLimiting(RateLimitPolicies.InviteRedemption)]
    public async Task<ActionResult<InviteMetadataResponse>> GetInvite(string code)
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);

        if (userId is null) return Unauthorized();

        var result = await inviteService.DescribeAsync(code, int.Parse(userId));

        return result.Status switch
        {
            DescribeInviteStatus.Success => Ok(new InviteMetadataResponse
            {
                GroupName = result.Metadata!.GroupName,
                MemberCount = result.Metadata.MemberCount,
                CreatedByName = result.Metadata.CreatedByName,
                AlreadyMember = result.Metadata.AlreadyMember
            }),
            DescribeInviteStatus.NotFound => NotFound(new ErrorResponse { StatusCode = 404, Message = "Invite not found" }),
            DescribeInviteStatus.Expired => StatusCode(410, new ErrorResponse { StatusCode = 410, Message = "Invite has expired" }),
            DescribeInviteStatus.Exhausted => Conflict(new ErrorResponse { StatusCode = 409, Message = "Invite has no uses left" }),
            _ => StatusCode(500)
        };
    }

    [HttpPost("{code}/accept")]
    [EnableRateLimiting(RateLimitPolicies.InviteRedemption)]
    public async Task<ActionResult<GroupDTO>> AcceptInvite(string code)
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);

        if (userId is null) return Unauthorized();

        var result = await inviteService.RedeemAsync(code, int.Parse(userId));

        switch (result.Status)
        {
            case RedeemInviteStatus.Success:
            case RedeemInviteStatus.AlreadyMember:
            {
                var group = await groupService.GetGroupAsync(result.GroupId, int.Parse(userId));
                if (group is null)
                {
                    return NotFound(new ErrorResponse { StatusCode = 404, Message = "Group not found" });
                }

                return Ok(group);
            }
            case RedeemInviteStatus.NotFound:
                return NotFound(new ErrorResponse { StatusCode = 404, Message = "Invite not found" });
            case RedeemInviteStatus.Expired:
                return StatusCode(410, new ErrorResponse { StatusCode = 410, Message = "Invite has expired" });
            case RedeemInviteStatus.Exhausted:
                return Conflict(new ErrorResponse { StatusCode = 409, Message = "Invite has no uses left" });
            default:
                return StatusCode(500);
        }
    }
}
