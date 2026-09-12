using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Splitty.DTO.Request;
using Splitty.DTO.Response;
using Splitty.Service.Interfaces;

namespace Splitty.API.Controllers;

/// <summary>
/// One resource for reading and editing a profile. There is no second route returning the
/// same user.
/// </summary>
[ApiController]
[Route("profile")]
[Authorize]
public class ProfileController(IProfileService profileService) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<ProfileResponse>> GetOwnProfile()
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);

        if (userId is null) return Unauthorized();

        return Ok(await profileService.GetAsync(int.Parse(userId)));
    }

    [HttpPatch]
    public async Task<ActionResult<ProfileResponse>> UpdateOwnProfile(
        [FromBody] UpdateProfileRequest request,
        CancellationToken cancellationToken)
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);

        if (userId is null) return Unauthorized();

        return Ok(await profileService.UpdateAsync(int.Parse(userId), request, cancellationToken));
    }

    /// <summary>
    /// A presigned slot the client PUTs the image to directly. The bytes never pass
    /// through the API, so there is no request-size configuration or streaming code here.
    /// </summary>
    [HttpPost("avatar/upload-url")]
    public async Task<ActionResult<AvatarUploadResponse>> CreateAvatarUpload(CancellationToken cancellationToken)
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);

        if (userId is null) return Unauthorized();

        return Ok(await profileService.CreateAvatarUploadAsync(int.Parse(userId), cancellationToken));
    }

    /// <summary>
    /// Gated on sharing a group with the caller: an authenticated account cannot walk the
    /// user table. A stranger is a 404, not a 403.
    /// </summary>
    [HttpGet("{userId:int}")]
    public async Task<ActionResult<ProfileResponse>> GetPeerProfile(int userId)
    {
        var callerId = User.FindFirstValue(ClaimTypes.NameIdentifier);

        if (callerId is null) return Unauthorized();

        return Ok(await profileService.GetPeerAsync(int.Parse(callerId), userId));
    }
}
