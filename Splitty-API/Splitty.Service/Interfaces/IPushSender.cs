using Splitty.Domain.Entities;

namespace Splitty.Service.Interfaces;

/// What a notification shows, plus what the app needs to open it.
public sealed record Push(string Title, string Body, int GroupId, int? ExpenseId);

public enum PushResult
{
    Sent,

    /// The token no longer reaches an installed app, so the device row should go.
    Unregistered,

    /// Anything else. Logged by the sender; notifications are best effort and not retried.
    Failed
}

/// The only component that talks to Apple, the way <see cref="IGoogleTokenExchanger"/> is
/// the only one that talks to Google.
public interface IPushSender
{
    Task<PushResult> SendAsync(PushDevice device, Push push, CancellationToken cancellationToken = default);
}
