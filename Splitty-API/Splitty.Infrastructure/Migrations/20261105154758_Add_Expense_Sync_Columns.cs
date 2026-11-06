using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Splitty.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class Add_Expense_Sync_Columns : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_Expense_GroupId",
                table: "Expense");

            migrationBuilder.AddColumn<Guid>(
                name: "ClientId",
                table: "Expense",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "LastOpId",
                table: "Expense",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "Version",
                table: "Expense",
                type: "integer",
                nullable: false,
                defaultValue: 1);

            migrationBuilder.CreateIndex(
                name: "IX_Expense_GroupId_ClientId",
                table: "Expense",
                columns: new[] { "GroupId", "ClientId" },
                unique: true,
                filter: "\"ClientId\" IS NOT NULL");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_Expense_GroupId_ClientId",
                table: "Expense");

            migrationBuilder.DropColumn(
                name: "ClientId",
                table: "Expense");

            migrationBuilder.DropColumn(
                name: "LastOpId",
                table: "Expense");

            migrationBuilder.DropColumn(
                name: "Version",
                table: "Expense");

            migrationBuilder.CreateIndex(
                name: "IX_Expense_GroupId",
                table: "Expense",
                column: "GroupId");
        }
    }
}
