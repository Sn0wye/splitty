using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Splitty.Background;
using Splitty.Domain.Entities;
using Splitty.DTO.Internal;
using Splitty.DTO.Request;
using Splitty.DTO.Response;
using Splitty.Service.Interfaces;

namespace Splitty.API.Controllers;

[ApiController]
[Route("group")]
[Authorize]
public class GroupController(
    IGroupService groupService,
    IExpenseService expenseService,
    IBalanceService balanceService,
    IInviteService inviteService,
    IBalanceRecomputeQueue balanceRecomputeQueue
) : ControllerBase
{
    [HttpPost]
    public async Task<ActionResult<Group>> CreateGroup([FromBody] CreateGroupRequest request)
    {
        if (!ModelState.IsValid)
        {
            Console.WriteLine(ModelState);
            return BadRequest(ModelState);
        }

        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);

        if (userId is null) return Unauthorized();

        var createdGroup = await groupService.CreateAsync(int.Parse(userId), request.Name, request.Description);

        return Ok(createdGroup);
    }

    [HttpGet]
    public async Task<ActionResult<List<GroupDTO>>> GetGroupsByUserId()
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);

        if (userId is null) return Unauthorized();

        var groups = await groupService.GetGroupsByUserId(int.Parse(userId));

        return Ok(groups);
    }

    [HttpGet("{groupId}")]
    public async Task<ActionResult<GroupDTO>> GetGroupById(int groupId)
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);

        if (userId is null) return Unauthorized();

        var group = await groupService.GetGroupAsync(groupId, int.Parse(userId));

        if (group is null) return NotFound(Error(404, "Group not found"));

        return Ok(group);
    }

    [HttpPut("{groupId}")]
    public async Task<ActionResult<Group>> UpdateGroup(int groupId, [FromBody] UpdateGroupRequest request)
    {
        if (request.Name is null && request.Description is null)
        {
            return BadRequest("At least one of the fields must be provided");
        }

        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);

        if (userId is null) return Unauthorized();

        var group = await groupService.UpdateAsync(groupId, int.Parse(userId), request.Name, request.Description);

        return Ok(group);
    }

    [HttpPost("{groupId}/invites")]
    public async Task<ActionResult<InviteResponse>> CreateInvite(int groupId, [FromBody] CreateInviteRequest? request)
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);

        if (userId is null) return Unauthorized();

        if (!await groupService.IsMemberAsync(groupId, int.Parse(userId))) return Forbid();

        var result = await inviteService.CreateAsync(
            groupId,
            int.Parse(userId),
            request?.MaxUses,
            request?.ExpiresAt);

        return result.Status switch
        {
            CreateInviteStatus.Success => Ok(new InviteResponse
            {
                Code = result.Invite!.Code,
                GroupId = result.Invite.GroupId,
                CreatedAt = result.Invite.CreatedAt,
                ExpiresAt = result.Invite.ExpiresAt,
                MaxUses = result.Invite.MaxUses,
                UsedCount = result.Invite.UsedCount
            }),
            CreateInviteStatus.GroupNotFound => NotFound(Error(404, "Group not found")),
            CreateInviteStatus.NotAMember => StatusCode(403, Error(403, "You are not a member of this group")),
            CreateInviteStatus.InvalidExpiry => BadRequest(Error(400, "Expiration must be in the future")),
            CreateInviteStatus.InvalidMaxUses => BadRequest(Error(400, "MaxUses must be greater than zero")),
            CreateInviteStatus.CodeUnavailable => StatusCode(500, Error(500, "Could not allocate an invite code")),
            _ => StatusCode(500)
        };
    }

    [HttpPost("{groupId}/leave")]
    public async Task<ActionResult> LeaveGroup(int groupId)
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);

        if (userId is null) return Unauthorized();

        if (!await groupService.IsMemberAsync(groupId, int.Parse(userId))) return Forbid();

        return MapRemoval(await groupService.LeaveAsync(groupId, int.Parse(userId)), self: true);
    }

    [HttpDelete("{groupId}/members/{memberUserId}")]
    public async Task<ActionResult> RemoveMember(int groupId, int memberUserId)
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);

        if (userId is null) return Unauthorized();

        if (!await groupService.IsMemberAsync(groupId, int.Parse(userId))) return Forbid();

        var result = await groupService.RemoveMemberAsync(groupId, int.Parse(userId), memberUserId);

        return MapRemoval(result, self: memberUserId == int.Parse(userId));
    }

    private ActionResult MapRemoval(MembershipRemovalStatus status, bool self) => status switch
    {
        MembershipRemovalStatus.Success => NoContent(),
        MembershipRemovalStatus.GroupNotFound => NotFound(Error(404, "Group not found")),
        MembershipRemovalStatus.NotAMember => StatusCode(403, Error(403, "You are not a member of this group")),
        MembershipRemovalStatus.TargetNotAMember => NotFound(Error(404, "User is not a member of this group")),
        MembershipRemovalStatus.OutstandingBalance => Conflict(Error(409, self
            ? "Settle your balance before leaving the group"
            : "This member has an outstanding balance")),
        _ => StatusCode(500)
    };

    private static ErrorResponse Error(int statusCode, string message) => new()
    {
        StatusCode = statusCode,
        Message = message
    };

    [HttpGet("{groupId}/expenses")]
    public async Task<ActionResult<List<Expense>>> GetExpensesByGroupId(int groupId)
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);

        if (userId is null) return Unauthorized();

        if (!await groupService.IsMemberAsync(groupId, int.Parse(userId))) return Forbid();

        var expenses = await expenseService.FindExpensesByGroupId(groupId, int.Parse(userId));

        return Ok(expenses);
    }

    [HttpPost("{groupId}/expenses")]
    public async Task<ActionResult<Expense>> CreateExpense(
        [FromBody] CreateExpenseRequest request,
        int groupId
    )
    {
        if (!ModelState.IsValid)
        {
            return BadRequest(ModelState);
        }

        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);

        if (userId is null) return Unauthorized();

        if (!await groupService.IsMemberAsync(groupId, int.Parse(userId))) return Forbid();

        var dto = new CreateExpenseDTO
        {
            Amount = request.Amount,
            Description = request.Description,
            GroupId = groupId,
            PaidBy = request.PaidBy,
            ExpenseSplits = request.Splits
        };

        var expense = await expenseService.CreateAsync(dto, int.Parse(userId));
        
        await balanceRecomputeQueue.EnqueueAsync(groupId);

        return Ok(expense);
    }

    [HttpPut("{groupId}/expenses/{expenseId}")]
    public async Task<ActionResult<Expense>> UpdateExpense(
        [FromBody] UpdateExpenseRequest request,
        int groupId,
        int expenseId
    )
    {
        
        if (!ModelState.IsValid)
        {
            return BadRequest(ModelState);
        }

        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);

        if (userId is null) return Unauthorized();

        if (!await groupService.IsMemberAsync(groupId, int.Parse(userId))) return Forbid();

        var dto = new UpdateExpenseDTO
        {
            Id = expenseId,
            GroupId = groupId,
            Amount = request.Amount,
            Description = request.Description,
            PaidBy = request.PaidBy,
            ExpenseSplits = request.Splits
        };

        var expense = await expenseService.UpdateAsync(dto, int.Parse(userId));
        
        await balanceRecomputeQueue.EnqueueAsync(groupId);
        
        return Ok(expense);
    }
    
    /// <summary>
    /// Requests a recomputation rather than performing one. Replaying inline would race the
    /// worker replaying the same group, and both would insert the pairwise row neither found.
    /// </summary>
    [HttpPost("{groupId}/expenses/summary")]
    public async Task<ActionResult> RequestExpenseSummaryRefresh(int groupId)
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);

        if (userId is null) return Unauthorized();

        if (!await groupService.IsMemberAsync(groupId, int.Parse(userId))) return Forbid();

        await balanceRecomputeQueue.EnqueueAsync(groupId);

        return Accepted();
    }
    
    [HttpGet("{groupId}/expenses/summary")]
    public async Task<ActionResult<GroupBalanceSummaryResponse>> GetExpenseSummary(int groupId)
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);

        if (userId is null) return Unauthorized();

        if (!await groupService.IsMemberAsync(groupId, int.Parse(userId))) return Forbid();

        // Read before the balances: a drain landing between the two reads then reports
        // fresh balances as pending, rather than stale balances as settled.
        var balancesPending = await groupService.AreBalancesPendingAsync(groupId);

        return Ok(new GroupBalanceSummaryResponse
        {
            Balances = await balanceService.GetGroupUserBalance(groupId, int.Parse(userId)),
            BalancesPending = balancesPending
        });
    }
    
    [HttpPost("{groupId}/settle")]
    public async Task<ActionResult> SettleUp(int groupId, [FromBody] SettleUpRequest request)
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);

        if (userId is null) return Unauthorized();
        
        if (!await groupService.IsMemberAsync(groupId, int.Parse(userId))) return Forbid();

        await balanceService.SettleUp(groupId, int.Parse(userId), request.WithUserId, request.Amount);

        await balanceRecomputeQueue.EnqueueAsync(groupId);

        return Ok();
    }
}