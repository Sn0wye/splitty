using Splitty.Domain.Entities;

namespace Splitty.Service.Interfaces;

public interface IAvatarResolver
{
    /// The single absolute URL a client is given for this user's avatar.
    string Resolve(User user);
}
