using System.Collections.Concurrent;
using System.Data.Common;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.DependencyInjection;
using Splitty.Infrastructure;

namespace Splitty.API.Tests;

/// <summary>
/// Sees every command the host sends, so a test can record what was written or run its own
/// statement in the gap between a request's read and its write.
///
/// A hook is armed for one matching command: it runs before that command reaches the
/// database, then disarms, so the statements it issues itself are never caught by it.
/// </summary>
public sealed class CommandInterceptor : DbCommandInterceptor
{
    private readonly ConcurrentQueue<string> _commands = new();
    private Hook? _hook;
    private readonly TaskCompletionSource _fired = new(TaskCreationOptions.RunContinuationsAsynchronously);

    public IReadOnlyCollection<string> Commands => _commands;

    public void Clear() => _commands.Clear();

    public void Before(Func<string, bool> matches, Func<Task> run) => _hook = new Hook(matches, run);

    /// Fails a test whose hook never ran, which would otherwise pass without testing anything.
    public Task Fired => _fired.Task.WaitAsync(TimeSpan.FromSeconds(15));

    public override async ValueTask<InterceptionResult<int>> NonQueryExecutingAsync(
        DbCommand command,
        CommandEventData eventData,
        InterceptionResult<int> result,
        CancellationToken cancellationToken = default)
    {
        await InterceptAsync(command);
        return result;
    }

    public override async ValueTask<InterceptionResult<DbDataReader>> ReaderExecutingAsync(
        DbCommand command,
        CommandEventData eventData,
        InterceptionResult<DbDataReader> result,
        CancellationToken cancellationToken = default)
    {
        await InterceptAsync(command);
        return result;
    }

    private async Task InterceptAsync(DbCommand command)
    {
        _commands.Enqueue(command.CommandText);

        var hook = _hook;
        if (hook is null || !hook.Matches(command.CommandText)) return;
        if (Interlocked.CompareExchange(ref _hook, null, hook) != hook) return;

        await hook.Run();
        _fired.TrySetResult();
    }

    private sealed record Hook(Func<string, bool> Matches, Func<Task> Run);
}

public static class CommandInterceptorExtensions
{
    public static WebApplicationFactory<Program> WithInterceptor(
        this WebApplicationFactory<Program> factory,
        CommandInterceptor interceptor) =>
        factory.WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
                services.ConfigureDbContext<ApplicationDbContext>(options =>
                    options.AddInterceptors(interceptor))));
}
