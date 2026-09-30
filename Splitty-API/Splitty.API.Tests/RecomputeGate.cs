using Microsoft.AspNetCore.Mvc.Testing;

namespace Splitty.API.Tests;

/// <summary>
/// Holds a replay open so a test can observe the window in which balances are
/// pending, instead of guessing whether the worker has already drained.
///
/// Scoped to one group, it holds only that group's replays and lets every other group's
/// through, so a replay left behind by an earlier test cannot stall the worker. Its replays
/// are numbered in the order they enter, and each can be released on its own.
/// </summary>
public sealed class RecomputeGate(int? groupId = null) : IDisposable
{
    private static readonly TimeSpan EntryTimeout = TimeSpan.FromSeconds(15);

    private readonly List<Replay> _replays = [];
    private readonly TaskCompletionSource _releasedAll = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private int _entries;

    public Task WaitForEntryAsync(int replay = 1) => ReplayAt(replay).Entered.Task.WaitAsync(EntryTimeout);

    /// How many replays have entered so far. A request the ledger skips never enters.
    public int Entries => Volatile.Read(ref _entries);

    /// Releases every replay, held or still to come.
    public void Release() => _releasedAll.TrySetResult();

    public void Release(int replay) => ReplayAt(replay).Released.TrySetResult();

    // Releasing on dispose keeps a failed assertion from stranding the worker.
    public void Dispose() => Release();

    internal async Task EnterAsync(int replayedGroupId)
    {
        if (groupId is not null && groupId != replayedGroupId) return;

        var replay = ReplayAt(Interlocked.Increment(ref _entries));
        replay.Entered.TrySetResult();
        await Task.WhenAny(replay.Released.Task, _releasedAll.Task);
    }

    private Replay ReplayAt(int number)
    {
        lock (_replays)
        {
            while (_replays.Count < number) _replays.Add(new Replay());
            return _replays[number - 1];
        }
    }

    private sealed class Replay
    {
        public TaskCompletionSource Entered { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public TaskCompletionSource Released { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
    }
}

public static class RecomputeGateExtensions
{
    public static WebApplicationFactory<Program> WithGate(
        this WebApplicationFactory<Program> factory,
        RecomputeGate gate) =>
        factory.WithReplay(async (groupId, replay) =>
        {
            await gate.EnterAsync(groupId);
            await replay();
        });
}
