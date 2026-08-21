using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Splitty.DTO.Request;
using Splitty.DTO.Response;
using Splitty.Service.Interfaces;

namespace Splitty.API.Controllers;

/// Hands out a token for a seeded user with no credential of any kind. Registered only
/// when the host is Development — `Program.cs` strips the whole controller otherwise, so
/// outside development the route does not exist rather than returning 401.
[ApiController]
[Route("auth")]
[AllowAnonymous]
public class DevAuthController(
    IAuthService authService
) : ControllerBase
{
    [HttpPost("dev-login")]
    public async Task<ActionResult> DevLogin([FromBody] DevLoginRequest request)
    {
        if (!ModelState.IsValid) return BadRequest(ModelState);

        var (user, token) = await authService.DevLogin(request.Email);

        return Ok(new LoginResponse
        {
            Token = token,
            User = user
        });
    }
}
