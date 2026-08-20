namespace Splitty.API.Tests;

/// <summary>
/// Reads the solution's own source, for invariants that are about which code exists
/// rather than about what a request returns.
/// </summary>
public static class SolutionSource
{
    public static IEnumerable<string> FilesCalling(string identifier) =>
        Directory.EnumerateFiles(Root(), "*.cs", SearchOption.AllDirectories)
            .Where(path => !path.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}"))
            .Where(path => !path.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}"))
            .Where(path => File.ReadAllText(path).Contains(identifier, StringComparison.Ordinal));

    private static string Root()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);

        while (directory is not null && !File.Exists(Path.Combine(directory.FullName, "Splitty.sln")))
        {
            directory = directory.Parent;
        }

        return directory?.FullName
               ?? throw new InvalidOperationException("Could not locate Splitty.sln above the test assembly.");
    }
}
