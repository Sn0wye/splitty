using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc.Testing;
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

    private GroupFixture(WebApplicationFactory<Program> factory, int id, ApiClient owner, int ownerId, int guestId)
    {
        _factory = factory;
        Id = id;
        Owner = owner;
        OwnerId = ownerId;
        GuestId = guestId;
    }

    public int Id { get; }
    public ApiClient Owner { get; }
    public int OwnerId { get; }
    public int GuestId { get; }

    public static async Task<GroupFixture> CreateAsync(WebApplicationFactory<Program> factory)
    {
        var ownerUser = await ApiClient.Create(factory).RegisterAsync(name: "Owner");
        var owner = ApiClient.Create(factory, ownerUser.Token);
        var groupId = await owner.CreateGroupAsync();
        var code = await owner.CreateInviteAsync(groupId);

        var guestUser = await ApiClient.Create(factory).RegisterAsync(name: "Guest");
        var guest = ApiClient.Create(factory, guestUser.Token);
        (await guest.AcceptInviteAsync(code)).EnsureSuccessStatusCode();

        return new GroupFixture(factory, groupId, owner, ownerUser.Id, guestUser.Id);
    }

    public async Task<int> CreateExpenseAsync(decimal amount, decimal share)
    {
        var response = await Owner.CreateExpenseAsync(Id, new
        {
            paidBy = OwnerId,
            amount,
            description = "Dinner",
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
            Splits =
            [
                new ExpenseSplit { UserId = OwnerId, Amount = share },
                new ExpenseSplit { UserId = GuestId, Amount = share }
            ]
        });

        await db.SaveChangesAsync();
    }
}
