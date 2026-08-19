namespace Splitty.Background;

public sealed class TransactionProcessedSignal
{
    private readonly SemaphoreSlim _processed = new(0);

    public void Notify() => _processed.Release();

    public Task WaitAsync(CancellationToken cancellationToken = default) =>
        _processed.WaitAsync(cancellationToken);
}
