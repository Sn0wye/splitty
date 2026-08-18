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
                return Ok(await groupService.GetGroupAsync(result.GroupId, int.Parse(userId)));
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
