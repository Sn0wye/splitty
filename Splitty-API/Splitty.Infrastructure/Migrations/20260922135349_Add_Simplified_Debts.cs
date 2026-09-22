using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Splitty.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class Add_Simplified_Debts : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "SimplifiedDebt",
                columns: table => new
                {
                    GroupId = table.Column<int>(type: "integer", nullable: false),
                    FromUserId = table.Column<int>(type: "integer", nullable: false),
                    ToUserId = table.Column<int>(type: "integer", nullable: false),
                    Amount = table.Column<decimal>(type: "numeric(18,2)", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_SimplifiedDebt", x => new { x.GroupId, x.FromUserId, x.ToUserId });
                    table.ForeignKey(
                        name: "FK_SimplifiedDebt_Group_GroupId",
                        column: x => x.GroupId,
                        principalTable: "Group",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_SimplifiedDebt_User_FromUserId",
                        column: x => x.FromUserId,
                        principalTable: "User",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_SimplifiedDebt_User_ToUserId",
                        column: x => x.ToUserId,
                        principalTable: "User",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_SimplifiedDebt_FromUserId",
                table: "SimplifiedDebt",
                column: "FromUserId");

            migrationBuilder.CreateIndex(
                name: "IX_SimplifiedDebt_ToUserId",
                table: "SimplifiedDebt",
                column: "ToUserId");
            // Existing groups need their first simplified projection before serving current debts.
            migrationBuilder.Sql("UPDATE \"Group\" SET \"BalancesPending\" = TRUE");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "SimplifiedDebt");
        }
    }
}
