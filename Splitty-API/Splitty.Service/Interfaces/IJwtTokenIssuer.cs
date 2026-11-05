using Splitty.Domain.Entities;

namespace Splitty.Service.Interfaces;

public interface IJwtTokenIssuer
{
    /// <param name="familyId">The refresh token family the access token was issued with, so a
    /// request can name the sign-in it comes from.</param>
    string Issue(User user, Guid familyId);
}
