using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Splitty.DTO.Request;

namespace Splitty.API.Controllers;

/// <summary>
/// Anonymous on purpose: a crash before sign-in, or one that signed the user out, is still worth
/// hearing about. A token, when sent, only attributes the report.
/// </summary>
[ApiController]
[Route("client-reports")]
[EnableRateLimiting(RateLimitPolicies.ClientReports)]
public class ClientReportController(ILogger<ClientReportController> logger) : ControllerBase
{
    [HttpPost]
    [RequestSizeLimit(64 * 1024)]
    public IActionResult Report(ClientReportRequest request)
    {
        var level = request.Kind == ClientReportKind.Error ? LogLevel.Warning : LogLevel.Error;

        logger.Log(level,
            "Client {Kind} on {AppVersion} ({Build}): {ClientMessage} [iOS {OsVersion}, {DeviceModel}, user {UserId}] {Payload}",
            request.Kind,
            request.AppVersion,
            request.Build,
            request.Message,
            request.OsVersion,
            request.DeviceModel,
            User.FindFirstValue(ClaimTypes.NameIdentifier),
            request.Payload);

        return Accepted();
    }
}
