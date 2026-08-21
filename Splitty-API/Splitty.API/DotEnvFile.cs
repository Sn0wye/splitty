namespace Splitty.API;

/// Loads the repo-root `.env` into the process environment so that a plain `dotnet run`
/// or an IDE run configuration sees the same secrets `docker compose` gets from
/// `env_file`. Without this the API starts with an empty signing key and fails on the
/// first request instead of at startup.
public static class DotEnvFile
{
    /// Walks up from the content root looking for `<dir>/.env`. Values already present in
    /// the environment win, so an explicit export or a compose variable is never
    /// overwritten by the file.
    public static void Load(string startDirectory)
    {
        var directory = new DirectoryInfo(startDirectory);

        while (directory is not null)
        {
            var candidate = Path.Combine(directory.FullName, ".env");

            if (File.Exists(candidate))
            {
                Apply(candidate);
                return;
            }

            directory = directory.Parent;
        }
    }

    private static void Apply(string path)
    {
        foreach (var rawLine in File.ReadLines(path))
        {
            var line = rawLine.Trim();

            if (line.Length == 0 || line.StartsWith('#')) continue;

            var separator = line.IndexOf('=');

            if (separator <= 0) continue;

            var key = line[..separator].Trim();
            var value = line[(separator + 1)..].Trim();

            // Quoting is how a value keeps leading or trailing spaces; strip the quotes.
            if (value.Length >= 2 &&
                ((value[0] == '"' && value[^1] == '"') || (value[0] == '\'' && value[^1] == '\'')))
            {
                value = value[1..^1];
            }

            if (Environment.GetEnvironmentVariable(key) is not null) continue;

            Environment.SetEnvironmentVariable(key, value);
        }
    }
}
