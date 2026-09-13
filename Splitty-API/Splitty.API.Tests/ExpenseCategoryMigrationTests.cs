using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.Extensions.Configuration;
using Splitty.Domain.Entities;
using Splitty.Infrastructure;
using Testcontainers.PostgreSql;

namespace Splitty.API.Tests;

/// <summary>
/// The category backfill, exercised on rows that predate the column. Its own database and
/// its own container: the shared ApiFactory migrates to head before any test runs, so there
/// is no way to observe the migration from inside it.
///
/// A settlement backfilled to <c>general</c> is the regression this guards. The client reads
/// glyph and tint from the category alone, so every historic settlement would render as an
/// uncategorized expense.
/// </summary>
public sealed class ExpenseCategoryMigrationTests : IAsyncLifetime
{
    /// The migration immediately before the category column.
    private const string BeforeCategory = "Add_User_Avatar_Key";

    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder()
        .WithImage("postgres:16-alpine")
        .Build();

    public Task InitializeAsync() => _postgres.StartAsync();

    public Task DisposeAsync() => _postgres.DisposeAsync().AsTask();

    [Fact]
    public async Task The_backfill_categorizes_expenses_as_general_and_settlements_as_payment()
    {
        await using var db = CreateContext();

        await db.GetService<IMigrator>().MigrateAsync(BeforeCategory);
        await InsertPreCategoryRowsAsync(db);

        await db.Database.MigrateAsync();

        var categories = await db.Expense
            .OrderBy(e => e.Id)
            .Select(e => new { e.Type, e.Category })
            .ToListAsync();

        Assert.Equal(
            [
                (ExpenseType.Expense, ExpenseCategory.General),
                (ExpenseType.Payment, ExpenseCategory.Payment)
            ],
            categories.Select(row => (row.Type, row.Category)));
    }

    /// <summary>
    /// Written as SQL rather than through the entity, which already carries the column this
    /// test needs absent.
    /// </summary>
    private static async Task InsertPreCategoryRowsAsync(ApplicationDbContext db)
    {
        await db.Database.ExecuteSqlRawAsync(
            """
            INSERT INTO "User" ("Id", "Name", "Email", "AvatarUrl", "CreatedAt", "UpdatedAt")
            VALUES (1, 'Payer', 'payer@example.com', '', now(), now()),
                   (2, 'Peer', 'peer@example.com', '', now(), now());

            INSERT INTO "Group" ("Id", "Name", "Description", "CreatedBy", "CreatedAt", "BalancesPending")
            VALUES (1, 'Trip', 'Before the category column', 1, now(), false);

            INSERT INTO "Expense" ("Id", "GroupId", "PaidBy", "Amount", "Description", "Type", "SplitMode", "CreatedAt", "UpdatedAt")
            VALUES (1, 1, 1, 20.00, 'Dinner', 0, 0, now(), now()),
                   (2, 1, 1, 5.00, 'Payment to Peer', 1, NULL, now(), now());
            """);
    }

    private ApplicationDbContext CreateContext()
    {
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ConnectionStrings:DefaultConnection"] = _postgres.GetConnectionString()
            })
            .Build();

        return new ApplicationDbContext(new DbContextOptions<ApplicationDbContext>(), configuration);
    }
}
