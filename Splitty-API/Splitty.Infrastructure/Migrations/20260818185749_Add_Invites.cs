using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Splitty.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class Add_Invites : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "Invite",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    GroupId = table.Column<int>(type: "integer", nullable: false),
                    Code = table.Column<string>(type: "character varying(6)", maxLength: 6, nullable: false),
                    CreatedBy = table.Column<int>(type: "integer", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    ExpiresAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    MaxUses = table.Column<int>(type: "integer", nullable: true),
                    UsedCount = table.Column<int>(type: "integer", nullable: false, defaultValue: 0)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Invite", x => x.Id);
                    table.ForeignKey(
                        name: "FK_Invite_Group_GroupId",
                        column: x => x.GroupId,
                        principalTable: "Group",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_Invite_User_CreatedBy",
                        column: x => x.CreatedBy,
                        principalTable: "User",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            // Duplicate memberships were possible before the unique index existed;
            // keep the earliest row per (UserId, GroupId) so the index can be created.
            migrationBuilder.Sql("""
                                 DELETE FROM "GroupMembership" a
                                 USING "GroupMembership" b
                                 WHERE a."UserId" = b."UserId"
                                   AND a."GroupId" = b."GroupId"
                                   AND a."Id" > b."Id"
                                 """);

            migrationBuilder.CreateIndex(
                name: "IX_GroupMembership_UserId_GroupId",
                table: "GroupMembership",
                columns: new[] { "UserId", "GroupId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Invite_Code",
                table: "Invite",
                column: "Code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Invite_CreatedBy",
                table: "Invite",
                column: "CreatedBy");

            migrationBuilder.CreateIndex(
                name: "IX_Invite_GroupId",
                table: "Invite",
                column: "GroupId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "Invite");

            migrationBuilder.DropIndex(
                name: "IX_GroupMembership_UserId_GroupId",
                table: "GroupMembership");
        }
    }
}
