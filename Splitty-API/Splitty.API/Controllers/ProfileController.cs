using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Splitty.DTO.Request;
using Splitty.DTO.Response;
using Splitty.Service;
using Splitty.Service.Interfaces;

namespace Splitty.API.Controllers;

/// <summary>
/// One resource for reading and editing a profile. There is no second route returning the
/// same user.
/// </summary>
[ApiController]
[Route("profile")]
[Authorize]
public class ProfileController(
    IProfileService profileService,
    INotificationService notificationService
) : ControllerBase
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
    /// Switches the account off and ends every session. Signing in again reactivates it.
    /// </summary>
    [HttpPost("deactivate")]
    public async Task<ActionResult> Deactivate()
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);

        if (userId is null) return Unauthorized();

        await profileService.DeactivateAsync(int.Parse(userId));

        return NoContent();
    }

    /// <summary>
    /// Deletes the account permanently and immediately. Shared history stays with the
    /// other members under a `[removed]` tombstone. See docs/adr/0004-account-closure.md.
    /// </summary>
    [HttpDelete]
    public async Task<ActionResult> DeleteOwnAccount(CancellationToken cancellationToken)
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);

        if (userId is null) return Unauthorized();

        await profileService.DeleteAsync(int.Parse(userId), cancellationToken);

        return NoContent();
    }

    /// <summary>
    /// Registers this device for push notifications, against the sign-in the access token
    /// came from. Sent again whenever the token or the app language changes. Signing out
    /// forgets the device.
    /// </summary>
    [HttpPut("push-device")]
    public async Task<ActionResult> RegisterPushDevice([FromBody] RegisterPushDeviceRequest request)
    {
        if (!ModelState.IsValid) return BadRequest(ModelState);

        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);

        // A token from before the claim existed: the 401 makes the app refresh and retry
        // with one that has it.
        if (userId is null || !Guid.TryParse(User.FindFirstValue(JwtTokenIssuer.FamilyClaim), out var familyId))
        {
            return Unauthorized();
        }

        await notificationService.RegisterDeviceAsync(int.Parse(userId), familyId, request);

        return NoContent();
    }

    [HttpGet("notifications")]
    public async Task<ActionResult<NotificationSettingsResponse>> GetNotificationSettings()
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);

        if (userId is null) return Unauthorized();

        return Ok(await notificationService.GetSettingsAsync(int.Parse(userId)));
    }

    [HttpPut("notifications")]
    public async Task<ActionResult<NotificationSettingsResponse>> UpdateNotificationSettings(
        [FromBody] NotificationSettingsRequest request)
    {
        if (!ModelState.IsValid) return BadRequest(ModelState);

        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);

        if (userId is null) return Unauthorized();

        return Ok(await notificationService.UpdateSettingsAsync(int.Parse(userId), request));
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
