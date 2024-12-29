using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Splitty.Domain.Entities;
using Splitty.DTO.Internal;
using Splitty.DTO.Request;
using Splitty.Service.Interfaces;

namespace Splitty.API.Controllers;

[ApiController]
[Route("group")]
[Authorize]
public class GroupController(
    IGroupService groupService,
    IExpenseService expenseService,
    IBalanceService balanceService
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
    public async Task<ActionResult<List<Group>>> GetGroupsByUserId()
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);

        if (userId is null) return Unauthorized();

        var groups = await groupService.GetGroupsByUserId(int.Parse(userId));

        return Ok(groups);
    }

    [HttpGet("{groupId}")]
    public async Task<ActionResult<Group>> GetGroupById(int groupId)
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);

        var group = await groupService.GetGroupAsync(groupId, int.Parse(userId));

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

    [HttpPost("{groupId}/join")]
    public async Task<ActionResult<Group>> JoinGroup(int groupId)
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);

        if (userId is null) return Unauthorized();

        var group = await groupService.JoinGroupAsync(groupId, int.Parse(userId));

        return Ok(group);
    }

    [HttpGet("{groupId}/expenses")]
    public async Task<ActionResult<List<Expense>>> GetExpensesByGroupId(int groupId)
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);

        if (userId is null) return Unauthorized();

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

        var dto = new CreateExpenseDTO
        {
            Amount = request.Amount,
            Description = request.Description,
            GroupId = groupId,
            PaidBy = request.PaidBy,
            ExpenseSplits = request.Splits
        };

        var expense = await expenseService.CreateAsync(dto);

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

        var dto = new UpdateExpenseDTO
        {
            Id = expenseId,
            GroupId = groupId,
            Amount = request.Amount,
            Description = request.Description,
            PaidBy = request.PaidBy,
            ExpenseSplits = request.Splits
        };

        var expense = await expenseService.UpdateAsync(dto);

        return Ok(expense);
    }
    
    [HttpPost("{groupId}/expenses/summary")]
    public async Task<ActionResult<List<Balance>>> CalculateExpenseSummary(int groupId)
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);

        if (userId is null) return Unauthorized();

        var balances = await balanceService.CalculateGroupBalances(groupId);

        return Ok(balances);
    }
    
    [HttpGet("{groupId}/expenses/summary")]
    public async Task<ActionResult<List<Balance>>> GetExpenseSummary(int groupId)
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);

        if (userId is null) return Unauthorized();

        var balances = await balanceService.GetGroupUserBalance(groupId, int.Parse(userId));

        return Ok(balances);
    }
}