using System.Buffers.Text;
using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Splitty.Domain.Entities;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

/// <summary>
/// Sends to APNs over HTTP/2 with token-based authentication: an ES256 JWT signed with the
/// .p8 key. Apple refuses a provider token older than an hour and one renewed more than
/// once in 20 minutes, so it is reused for 40.
/// </summary>
public sealed class ApnsPushSender(
    IHttpClientFactory httpClientFactory,
    IOptions<ApnsOptions> options,
    TimeProvider timeProvider,
    ILogger<ApnsPushSender> logger
) : IPushSender
{
    private static readonly TimeSpan ProviderTokenLifetime = TimeSpan.FromMinutes(40);

    private readonly Lock _lock = new();
    private (string Token, DateTimeOffset IssuedAt)? _providerToken;

    public async Task<PushResult> SendAsync(PushDevice device, Push push, CancellationToken cancellationToken = default)
    {
        var apns = options.Value;

        // Required outside Development, so only a local run without a key gets here.
        if (!apns.IsConfigured)
        {
            logger.LogInformation("APNs is not configured; dropped a push for device {DeviceId}.", device.Id);
            return PushResult.Failed;
        }

        var host = device.Environment == ApnsEnvironment.Sandbox
            ? "https://api.sandbox.push.apple.com"
            : "https://api.push.apple.com";

        using var request = new HttpRequestMessage(HttpMethod.Post, $"{host}/3/device/{device.Token}")
        {
            Version = HttpVersion.Version20,
            VersionPolicy = HttpVersionPolicy.RequestVersionExact,
            Content = new StringContent(Payload(push).ToJsonString(), Encoding.UTF8, "application/json")
        };
        request.Headers.TryAddWithoutValidation("authorization", $"bearer {ProviderToken(apns)}");
        request.Headers.Add("apns-topic", apns.BundleId);
        request.Headers.Add("apns-push-type", "alert");
        request.Headers.Add("apns-priority", "10");

        if (push.ExpenseId is { } expenseId)
        {
            // A later notice about the same expense replaces this one instead of stacking.
            request.Headers.Add("apns-collapse-id", $"expense-{expenseId}");
        }

        using var response = await httpClientFactory.CreateClient(nameof(ApnsPushSender))
            .SendAsync(request, cancellationToken);

        if (response.IsSuccessStatusCode)
        {
            return PushResult.Sent;
        }

        var reason = await ReasonAsync(response, cancellationToken);

        if (response.StatusCode == HttpStatusCode.Gone || reason is "BadDeviceToken" or "DeviceTokenNotForTopic")
        {
            return PushResult.Unregistered;
        }

        logger.LogWarning("APNs refused a push to device {DeviceId}: {Status} {Reason}",
            device.Id, (int)response.StatusCode, reason);

        return PushResult.Failed;
    }

    /// <summary>
    /// The title is the group and the body the sentence. <c>thread-id</c> groups a group's
    /// notifications together on the lock screen; <c>groupId</c> and <c>expenseId</c> are
    /// what the app opens on a tap.
    /// </summary>
    public static JsonObject Payload(Push push)
    {
        var payload = new JsonObject
        {
            ["aps"] = new JsonObject
            {
                ["alert"] = new JsonObject { ["title"] = push.Title, ["body"] = push.Body },
                ["sound"] = "default",
                ["thread-id"] = $"group-{push.GroupId}"
            },
            ["groupId"] = push.GroupId
        };

        if (push.ExpenseId is { } expenseId)
        {
            payload["expenseId"] = expenseId;
        }

        return payload;
    }

    private string ProviderToken(ApnsOptions apns)
    {
        lock (_lock)
        {
            var now = timeProvider.GetUtcNow();

            if (_providerToken is { } cached && now - cached.IssuedAt < ProviderTokenLifetime)
            {
                return cached.Token;
            }

            var token = SignProviderToken(apns, now);
            _providerToken = (token, now);

            return token;
        }
    }

    public static string SignProviderToken(ApnsOptions apns, DateTimeOffset issuedAt)
    {
        using var key = ECDsa.Create();

        if (apns.PrivateKey.Contains("-----BEGIN", StringComparison.Ordinal))
        {
            key.ImportFromPem(apns.PrivateKey);
        }
        else
        {
            key.ImportPkcs8PrivateKey(Convert.FromBase64String(apns.PrivateKey.Trim()), out _);
        }

        var header = Base64Url.EncodeToString(JsonSerializer.SerializeToUtf8Bytes(new { alg = "ES256", kid = apns.KeyId }));
        var claims = Base64Url.EncodeToString(JsonSerializer.SerializeToUtf8Bytes(
            new { iss = apns.TeamId, iat = issuedAt.ToUnixTimeSeconds() }));
        var signed = $"{header}.{claims}";

        // .NET's default ECDSA signature format is the IEEE P1363 r||s a JWS expects.
        var signature = key.SignData(Encoding.ASCII.GetBytes(signed), HashAlgorithmName.SHA256);

        return $"{signed}.{Base64Url.EncodeToString(signature)}";
    }

    private static async Task<string?> ReasonAsync(HttpResponseMessage response, CancellationToken cancellationToken)
    {
        try
        {
            var body = await response.Content.ReadFromJsonAsync<JsonObject>(cancellationToken);
            return body?["reason"]?.GetValue<string>();
        }
        catch (JsonException)
        {
            return null;
        }
    }
}
