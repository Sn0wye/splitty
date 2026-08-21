using Splitty.Domain.Entities;

namespace Splitty.Service.Interfaces;

public interface IJwtTokenIssuer
{
    string Issue(User user);
}
