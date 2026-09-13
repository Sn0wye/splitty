using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Splitty.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class Add_Expense_Category : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "Category",
                table: "Expense",
                type: "text",
                nullable: false,
                defaultValue: "General");

            // Expense rows take the default: nobody chose a category before the column
            // existed. Settlements must not, because the client reads its glyph and tint from
            // the category alone — backfilling them to General renders every historic
            // settlement as an uncategorized expense. 1 is ExpenseType.Payment.
            migrationBuilder.Sql(@"UPDATE ""Expense"" SET ""Category"" = 'Payment' WHERE ""Type"" = 1;");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "Category",
                table: "Expense");
        }
    }
}
