using Splitty.Domain.Entities;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

/// <summary>
/// Resolves the one avatar URL a client is ever given: the image the user uploaded, else
/// the image the identity provider supplied, else a generated one.
///
/// The generated default is computed, never stored. A stored default is a stored default
/// forever — computing it means the rows that predate avatars fix themselves, and moving
/// off DiceBear later needs no backfill.
/// </summary>
public class AvatarResolver(IAvatarStorage storage) : IAvatarResolver
{
    /// <summary>
    /// The hosted DiceBear API routes on the major version only — `11.0` is a 404, so an
    /// exact minor is not addressable. Within a major, a style revision would shift every
    /// generated face; self-hosting the renderer is the escape hatch if that matters.
    /// </summary>
    private const string DiceBearVersion = "11.x";

    public string Resolve(User user)
    {
        if (!string.IsNullOrWhiteSpace(user.AvatarKey))
        {
            return storage.PublicUrl(user.AvatarKey);
        }

        if (!string.IsNullOrWhiteSpace(user.AvatarUrl))
        {
            return user.AvatarUrl;
        }

        return Generated(user.Id);
    }

    /// <summary>
    /// Seeded on the user id, never the email: the seed appears verbatim in a URL that
    /// every peer's client renders.
    /// </summary>
    private static string Generated(int userId) =>
        $"https://api.dicebear.com/{DiceBearVersion}/line-face/png?seed={userId}&size=256";
}
