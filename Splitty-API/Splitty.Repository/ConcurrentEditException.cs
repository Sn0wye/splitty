namespace Splitty.Repository;

/// <summary>
/// An expense's <c>Version</c> moved between the read and the save: another edit won the
/// race. Nothing of this save is kept.
/// </summary>
public sealed class ConcurrentEditException(Exception inner)
    : Exception("The expense changed while this edit was being saved.", inner);
