using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Splitty.DTO.Request;
using Splitty.DTO.Response;
using Splitty.Service.Interfaces;

namespace Splitty.API.Controllers;

/// Mints Splitty tokens from provider identities. `AuthController` renews and ends a
/// sign-in from a refresh token this controller already issued; the two never share a route.
[ApiController]
[Route("oauth")]
[AllowAnonymous]
public class OAuthController(
    IOAuthService oauthService
) : ControllerBase
{
    [HttpPost("google")]
    public async Task<ActionResult> Google([FromBody] GoogleSignInRequest request, CancellationToken cancellationToken)
    {
        if (!ModelState.IsValid) return BadRequest(ModelState);

        try
        {
            var (user, token, refreshToken) = await oauthService.SignInWithGoogleAsync(request.AuthCode, cancellationToken);

            return Ok(new LoginResponse
            {
                Token = token,
                RefreshToken = refreshToken,
                User = user
            });
        }
        catch (UnauthorizedAccessException)
        {
            // A code Google refused is a rejected credential, not a server fault.
            return Unauthorized(new ErrorResponse
            {
                StatusCode = StatusCodes.Status401Unauthorized,
                Message = "Google sign-in failed."
            });
        }
    }
}
