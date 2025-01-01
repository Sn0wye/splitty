using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Splitty.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class Add_ExpenseType : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "Type",
                table: "Expense",
                type: "integer",
                nullable: false,
                defaultValue: 0);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "Type",
                table: "Expense");
        }
    }
}
