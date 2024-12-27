using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Splitty.Domain.Entities;
using Splitty.DTO.Request;
using Splitty.Service;
using Splitty.Service.Interfaces;

namespace Splitty.API.Controllers;

[ApiController]
[Route("group")]
[Authorize]
public class GroupController(
    IGroupService groupService) : ControllerBase
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
}