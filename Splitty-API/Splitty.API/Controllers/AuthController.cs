using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Splitty.Domain.Entities;
using Splitty.Service.Interfaces;

namespace Splitty.API.Controllers;

[ApiController]
[Route("auth")]
public class AuthController(
    IAuthService authService
    ): ControllerBase
{
    [Authorize]
    [HttpGet]
    public async Task<ActionResult<User>> Profile()
    {
        var id = User.FindFirstValue(ClaimTypes.NameIdentifier);
        
        if (id is null) return Unauthorized();
        
        var user = await authService.GetProfile(int.Parse(id));
        
        return Ok(user);
    }
}
