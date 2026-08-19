using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Splitty.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class Unique_User_Email : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AlterColumn<string>(
                name: "AvatarUrl",
                table: "User",
                type: "character varying(255)",
                maxLength: 255,
                nullable: false,
                oldClrType: typeof(string),
                oldType: "text");

            // Duplicate emails were possible before the unique index existed;
            // keep the earliest user per email so the index can be created.
            migrationBuilder.Sql("""
                CREATE TEMP TABLE user_email_extras AS
                SELECT u."Id" AS extra_id, k.keeper_id
                FROM "User" u
                JOIN (
                    SELECT "Email", MIN("Id") AS keeper_id
                    FROM "User"
                    GROUP BY "Email"
                ) k ON k."Email" = u."Email"
                WHERE u."Id" <> k.keeper_id;

                UPDATE "Group" g
                SET "CreatedBy" = e.keeper_id
                FROM user_email_extras e
                WHERE g."CreatedBy" = e.extra_id;

                UPDATE "Invite" i
                SET "CreatedBy" = e.keeper_id
                FROM user_email_extras e
                WHERE i."CreatedBy" = e.extra_id;

                UPDATE "Expense" x
                SET "PaidBy" = e.keeper_id
                FROM user_email_extras e
                WHERE x."PaidBy" = e.extra_id;

                UPDATE "ExpenseSplit" s
                SET "UserId" = e.keeper_id
                FROM user_email_extras e
                WHERE s."UserId" = e.extra_id;

                UPDATE "Balance" b
                SET "UserId" = e.keeper_id
                FROM user_email_extras e
                WHERE b."UserId" = e.extra_id;

                UPDATE "Balance" b
                SET "PeerId" = e.keeper_id
                FROM user_email_extras e
                WHERE b."PeerId" = e.extra_id;

                DELETE FROM "GroupMembership" m
                USING user_email_extras e
                WHERE m."UserId" = e.extra_id
                  AND EXISTS (
                      SELECT 1
                      FROM "GroupMembership" k
                      WHERE k."UserId" = e.keeper_id
                        AND k."GroupId" = m."GroupId"
                  );

                UPDATE "GroupMembership" m
                SET "UserId" = e.keeper_id
                FROM user_email_extras e
                WHERE m."UserId" = e.extra_id;

                DELETE FROM "User" u
                USING user_email_extras e
                WHERE u."Id" = e.extra_id;
                """);

            migrationBuilder.CreateIndex(
                name: "IX_User_Email",
                table: "User",
                column: "Email",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_User_Email",
                table: "User");

            migrationBuilder.AlterColumn<string>(
                name: "AvatarUrl",
                table: "User",
                type: "text",
                nullable: false,
                oldClrType: typeof(string),
                oldType: "character varying(255)",
                oldMaxLength: 255);
        }
    }
}
