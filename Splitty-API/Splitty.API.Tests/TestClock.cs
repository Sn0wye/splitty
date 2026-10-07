namespace Splitty.API.Tests;

/// <summary>
/// The test host's <see cref="TimeProvider"/>: real time until a test sets it, so a test can
/// move the clock past the days a recurring expense comes due. Shared by every test on the
/// host, so a test that sets it resets it when it ends.
/// </summary>
public sealed class TestClock : TimeProvider
{
    private DateTimeOffset? _now;

    public void Set(DateTimeOffset now) => _now = now;

    public void Reset() => _now = null;

    public override DateTimeOffset GetUtcNow() => _now ?? base.GetUtcNow();
}
