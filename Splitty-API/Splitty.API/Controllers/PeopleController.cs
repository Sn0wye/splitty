using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Splitty.DTO.Response;
using Splitty.Service.Interfaces;

namespace Splitty.API.Controllers;

[ApiController]
[Route("people")]
[Authorize]
public class PeopleController(IPeopleService peopleService) : ControllerBase
{
    /// <summary>
    /// Membership is the access control here: the query only walks the caller's own
    /// groups, so no post-hoc filter is needed to keep other people's balances out.
    /// </summary>
    [HttpGet]
    public async Task<ActionResult<PeopleResponse>> GetPeople()
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);

        if (userId is null) return Unauthorized();

        return Ok(await peopleService.GetPeopleAsync(int.Parse(userId)));
    }
}
