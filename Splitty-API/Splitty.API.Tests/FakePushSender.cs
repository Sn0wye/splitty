using System.Collections.Concurrent;
using Splitty.Domain.Entities;
using Splitty.Service.Interfaces;

namespace Splitty.API.Tests;

/// Stands in for APNs. Records every push by device token; a token in
/// <see cref="Unregistered"/> answers the way Apple does for an uninstalled app.
public sealed class FakePushSender : IPushSender
{
    private readonly ConcurrentQueue<(string Token, Push Push)> _sent = new();

    public ConcurrentDictionary<string, bool> Unregistered { get; } = new();

    public Task<PushResult> SendAsync(PushDevice device, Push push, CancellationToken cancellationToken = default)
    {
        if (Unregistered.ContainsKey(device.Token))
        {
            return Task.FromResult(PushResult.Unregistered);
        }

        _sent.Enqueue((device.Token, push));
        return Task.FromResult(PushResult.Sent);
    }

    public List<Push> SentTo(string token) => _sent.Where(s => s.Token == token).Select(s => s.Push).ToList();
}
