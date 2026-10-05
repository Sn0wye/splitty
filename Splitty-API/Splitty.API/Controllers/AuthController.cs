using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Splitty.DTO.Request;
using Splitty.DTO.Response;
using Splitty.Service.Interfaces;

namespace Splitty.API.Controllers;

/// Renews and ends a sign-in. Anonymous: the refresh token in the body is the credential,
/// and the access token may well have expired by the time either route is called.
[ApiController]
[Route("auth")]
[AllowAnonymous]
public class AuthController(
    IRefreshTokenService refreshTokenService
) : ControllerBase
{
    [HttpPost("refresh")]
    public async Task<ActionResult> Refresh([FromBody] RefreshTokenRequest request)
    {
        if (!ModelState.IsValid) return BadRequest(ModelState);

        var pair = await refreshTokenService.RotateAsync(request.RefreshToken);

        if (pair is null)
        {
            // One answer for unknown, expired, revoked and reused, so the response never
            // says whether a token once existed.
            return Unauthorized(new ErrorResponse
            {
                StatusCode = StatusCodes.Status401Unauthorized,
                Message = "The refresh token is invalid or has expired. Sign in again."
            });
        }

        return Ok(new RefreshResponse
        {
            Token = pair.Token,
            RefreshToken = pair.RefreshToken
        });
    }

    /// Always 204, for the same reason refresh has one 401: a different answer for an
    /// unknown token would confirm which ones are real. Signing out never shows an error.
    [HttpPost("logout")]
    public async Task<ActionResult> Logout([FromBody] RefreshTokenRequest request)
    {
        if (!ModelState.IsValid) return BadRequest(ModelState);

        await refreshTokenService.RevokeFamilyAsync(request.RefreshToken);

        return NoContent();
    }
}
