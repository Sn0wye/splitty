using System.Collections.Concurrent;
using Microsoft.Extensions.Logging;

namespace Splitty.API.Tests;

public sealed class CapturingLoggerProvider : ILoggerProvider
{
    private readonly ConcurrentQueue<string> _errors = new();

    public IReadOnlyCollection<string> Errors => _errors;

    public ILogger CreateLogger(string categoryName) => new CapturingLogger(_errors);

    public void Dispose()
    {
    }

    private sealed class CapturingLogger(ConcurrentQueue<string> errors) : ILogger
    {
        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;

        public bool IsEnabled(LogLevel logLevel) => logLevel >= LogLevel.Error;

        public void Log<TState>(
            LogLevel logLevel,
            EventId eventId,
            TState state,
            Exception? exception,
            Func<TState, Exception?, string> formatter)
        {
            if (IsEnabled(logLevel))
            {
                errors.Enqueue(formatter(state, exception));
            }
        }
    }
}
