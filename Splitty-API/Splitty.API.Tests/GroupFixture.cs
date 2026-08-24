using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Splitty.Domain.Entities;
using Splitty.Infrastructure;

namespace Splitty.API.Tests;

/// <summary>
/// A group with two members and an authenticated client for each, the shape every
/// balance assertion needs before it can say anything.
/// </summary>
public sealed class GroupFixture
{
    private static readonly JsonSerializerOptions Json = new() { PropertyNameCaseInsensitive = true };

    private readonly WebApplicationFactory<Program> _factory;

    private GroupFixture(
        WebApplicationFactory<Program> factory,
        int id,
        ApiClient owner,
        int ownerId,
        ApiClient guest,
        int guestId,
        string guestToken)
    {
        _factory = factory;
        Id = id;
        Owner = owner;
        OwnerId = ownerId;
        Guest = guest;
        GuestId = guestId;
        GuestToken = guestToken;
    }

    public int Id { get; }
    public ApiClient Owner { get; }
    public int OwnerId { get; }
    public ApiClient Guest { get; }
    public int GuestId { get; }

    /// <summary>
    /// Lets a test reach the same guest through a differently configured host, which is how
    /// an assertion about the gated worker still acts as a real member.
    /// </summary>
    public string GuestToken { get; }

    public static async Task<GroupFixture> CreateAsync(WebApplicationFactory<Program> factory)
    {
        var ownerUser = await ApiClient.Create(factory).SignInAsync(name: "Owner");
        var owner = ApiClient.Create(factory, ownerUser.Token);
        var groupId = await owner.CreateGroupAsync();
        var code = await owner.CreateInviteAsync(groupId);

        var guestUser = await ApiClient.Create(factory).SignInAsync(name: "Guest");
        var guest = ApiClient.Create(factory, guestUser.Token);
        (await guest.AcceptInviteAsync(code)).EnsureSuccessStatusCode();

        return new GroupFixture(factory, groupId, owner, ownerUser.Id, guest, guestUser.Id, guestUser.Token);
    }

    public async Task<int> CreateExpenseAsync(
        decimal amount,
        decimal share,
        DateTime? date = null,
        string splitMode = "equal")
    {
        var response = await Owner.CreateExpenseAsync(Id, new
        {
            paidBy = OwnerId,
            amount,
            description = "Dinner",
            date,
            splitMode,
            splits = new[]
            {
                new { userId = OwnerId, amount = share },
                new { userId = GuestId, amount = share }
            }
        });
        response.EnsureSuccessStatusCode();

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(Json);
        return body.GetProperty("id").GetInt32();
    }

    /// <summary>
    /// The id of the settlement the guest just recorded — the settle route answers with no
    /// body, and every settlement assertion needs a row to point at.
    /// </summary>
    public async Task<int> SettleAsync(decimal amount)
    {
        (await Guest.SettleUpAsync(Id, new { withUserId = OwnerId, amount })).EnsureSuccessStatusCode();

        return await _factory.UseDbAsync(db => db.Expense
            .Where(e => e.GroupId == Id && e.Type == ExpenseType.Payment)
            .OrderByDescending(e => e.Id)
            .Select(e => e.Id)
            .FirstAsync());
    }

    /// <summary>
    /// Bypasses the endpoint so no recomputation is enqueued, leaving an expense that only
    /// an explicitly requested replay can turn into a balance.
    /// </summary>
    public async Task InsertExpenseDirectlyAsync(decimal amount, decimal share)
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();

        db.Expense.Add(new Expense
        {
            GroupId = Id,
            Description = "Unreplayed",
            Amount = amount,
            PaidBy = OwnerId,
            Type = ExpenseType.Expense,
            SplitMode = SplitMode.Equal,
            Splits =
            [
                new ExpenseSplit { UserId = OwnerId, Amount = share },
                new ExpenseSplit { UserId = GuestId, Amount = share }
            ]
        });

        await db.SaveChangesAsync();
    }
}
