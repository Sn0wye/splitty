using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace Splitty.Repository;

internal static class DbUpdateExceptionExtensions
{
    private const string UniqueViolation = "23505";

    /// True when the save failed on a unique index or constraint, not on something else.
    public static bool IsUniqueViolation(this DbUpdateException exception)
    {
        return exception.InnerException is PostgresException { SqlState: UniqueViolation };
    }
}
