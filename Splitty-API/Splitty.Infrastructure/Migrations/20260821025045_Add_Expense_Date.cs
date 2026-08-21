using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Splitty.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class Add_Expense_Date : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTime>(
                name: "Date",
                table: "Expense",
                type: "timestamp with time zone",
                nullable: true);

            // Backfilled so existing rows sort and group by the same instant they always
            // showed. The column stays nullable: a row written before this migration has no
            // user-supplied date, and readers fall back to CreatedAt anyway.
            migrationBuilder.Sql(@"UPDATE ""Expense"" SET ""Date"" = ""CreatedAt"";");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "Date",
                table: "Expense");
        }
    }
}
