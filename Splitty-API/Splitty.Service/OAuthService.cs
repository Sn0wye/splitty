using Splitty.Domain.Entities;
using Splitty.Repository.Interfaces;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

public class OAuthService(
    IGoogleTokenExchanger tokenExchanger,
    IUserRepository userRepository,
    IOAuthAccountRepository oauthAccountRepository,
    IJwtTokenIssuer tokenIssuer
) : IOAuthService
{
    public async Task<(User user, string token)> SignInWithGoogleAsync(
        string authCode,
        CancellationToken cancellationToken = default)
    {
        var identity = await tokenExchanger.ExchangeAsync(authCode, cancellationToken);

        var user = await ResolveUserAsync(identity);

        return (user, tokenIssuer.Issue(user));
    }

    private async Task<User> ResolveUserAsync(GoogleIdentity identity)
    {
        // The subject is the identity, not the email. A returning user is found here
        // even if they changed their Google address since last time.
        var existingAccount = await oauthAccountRepository.GetByProviderSubjectAsync(
            OAuthProvider.Google, identity.Subject);

        if (existingAccount is not null)
        {
            return existingAccount.User;
        }

        var byEmail = await userRepository.GetByEmailAsync(identity.Email);

        if (byEmail is not null)
        {
            // Linking on email is only safe when the provider says the address is
            // verified. Without that check, anyone who can set an unverified address to
            // a known user's email takes over that account.
            if (!identity.EmailVerified)
            {
                throw new InvalidOperationException(
                    "This email is already registered and Google has not verified it for this account.");
            }

            await LinkAsync(byEmail.Id, identity);

            return byEmail;
        }

        var user = new User
        {
            Name = identity.Name,
            Email = identity.Email,
            // Set once, at creation. Never refreshed on later sign-ins, or an in-app
            // rename would silently revert to whatever Google holds.
            AvatarUrl = identity.Picture
        };

        await userRepository.CreateAsync(user);
        await LinkAsync(user.Id, identity);

        return user;
    }

    private Task LinkAsync(int userId, GoogleIdentity identity) =>
        oauthAccountRepository.CreateAsync(new OAuthAccount
        {
            UserId = userId,
            Provider = OAuthProvider.Google,
            Subject = identity.Subject,
            Email = identity.Email
        });
}
