using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Splitty.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class Index_Balance_Group_User_Peer : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_Balance_GroupId",
                table: "Balance");

            migrationBuilder.CreateIndex(
                name: "IX_Balance_GroupId_UserId_PeerId",
                table: "Balance",
                columns: new[] { "GroupId", "UserId", "PeerId" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_Balance_GroupId_UserId_PeerId",
                table: "Balance");

            migrationBuilder.CreateIndex(
                name: "IX_Balance_GroupId",
                table: "Balance",
                column: "GroupId");
        }
    }
}
