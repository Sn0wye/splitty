using System.Net.Http.Json;
using Google.Apis.Auth;
using Microsoft.Extensions.Options;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

public class GoogleTokenExchanger(
    IHttpClientFactory httpClientFactory,
    IOptions<GoogleOptions> options
) : IGoogleTokenExchanger
{
    private const string TokenEndpoint = "https://oauth2.googleapis.com/token";

    public async Task<GoogleIdentity> ExchangeAsync(string authCode, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(authCode))
        {
            throw new ArgumentException("Authorization code cannot be null or empty.", nameof(authCode));
        }

        var google = options.Value;

        var http = httpClientFactory.CreateClient(nameof(GoogleTokenExchanger));

        var response = await http.PostAsync(TokenEndpoint, new FormUrlEncodedContent(
            new Dictionary<string, string>
            {
                ["code"] = authCode,
                ["client_id"] = google.ClientId,
                ["client_secret"] = google.ClientSecret,
                // The iOS SDK obtains the code without a redirect URI, so the exchange
                // must present an empty one or Google answers redirect_uri_mismatch.
                ["redirect_uri"] = string.Empty,
                ["grant_type"] = "authorization_code"
            }), cancellationToken);

        if (!response.IsSuccessStatusCode)
        {
            // The body carries Google's error code but also the code itself; not logged.
            throw new UnauthorizedAccessException("Google rejected the authorization code.");
        }

        var payload = await response.Content.ReadFromJsonAsync<TokenResponse>(cancellationToken: cancellationToken);

        if (payload?.IdToken is null)
        {
            throw new UnauthorizedAccessException("Google returned no id_token.");
        }

        GoogleJsonWebSignature.Payload identity;
        try
        {
            identity = await GoogleJsonWebSignature.ValidateAsync(payload.IdToken, new GoogleJsonWebSignature.ValidationSettings
            {
                // The token was minted for the web client that just performed the exchange.
                Audience = new[] { google.ClientId }
            });
        }
        catch (InvalidJwtException)
        {
            throw new UnauthorizedAccessException("Google returned an invalid id_token.");
        }

        return new GoogleIdentity(
            identity.Subject,
            identity.Email ?? string.Empty,
            identity.EmailVerified,
            identity.Name ?? string.Empty,
            identity.Picture ?? string.Empty);
    }

    private sealed class TokenResponse
    {
        [System.Text.Json.Serialization.JsonPropertyName("id_token")]
        public string? IdToken { get; set; }
    }
}
