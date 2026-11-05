namespace Splitty.Service.Interfaces;

/// <summary>
/// Hands notices to the push worker. Called after a write succeeds, the same place the write
/// requests its recomputation. Returns at once: sending happens in the background and is
/// best effort, so a notice lost to a restart is not recovered.
/// </summary>
public interface INotifier
{
    void Notify(IEnumerable<Notice> notices);
}
