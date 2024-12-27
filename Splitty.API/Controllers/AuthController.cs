using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Splitty.Domain.Entities;
using Splitty.Service.Interfaces;
using Splitty.DTO.Request;
using Splitty.DTO.Response;

namespace Splitty.API.Controllers;

[ApiController]
[Route("auth")]
public class AuthController(
    IAuthService authService
    ): ControllerBase
{
    [HttpPost("register")]
    public async Task<ActionResult> Register([FromBody] RegisterRequest request)
    {
        if (!ModelState.IsValid) return BadRequest(ModelState);

        var (user, token) = await authService.Register(request.Name, request.Email, request.Password);

        return Ok(new RegisterResponse
        {
            Token = token,
            User = user
        });
    }
    
    [HttpPost("login")]
    public async Task<ActionResult> Login([FromBody] LoginRequest request)
    {
        if (!ModelState.IsValid) return BadRequest(ModelState);

        var (user, token) = await authService.Login(request.Email, request.Password);

        return Ok(new LoginResponse
        {
            Token = token,
            User = user
        });
    }
    
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