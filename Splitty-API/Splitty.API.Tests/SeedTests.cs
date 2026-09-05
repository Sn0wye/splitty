using System.Net.Http.Json;
using System.Text.Json;
using Splitty.DTO.Internal;
using Splitty.Seeder;

namespace Splitty.API.Tests;

/// <summary>
/// Everything here reads what a signed-in client sees after `dotnet run seed`, never how
/// the seeder built it. A test that counted rows through the context would pin today's
/// data set and block the next edit to it.
/// </summary>
[Collection(nameof(ApiCollection))]
public sealed class SeedTests(ApiFactory factory)
{
    private static readonly JsonSerializerOptions Json = new() { PropertyNameCaseInsensitive = true };

    [Fact]
    public async Task A_seeded_group_has_more_than_three_members()
    {
        await SeedAsync();

        var groups = await GroupsOfAsync(DatabaseSeeder.PrimaryUserEmail);

        Assert.Contains(groups, group => group.Members.Count > 3);
    }

    [Fact]
    public async Task A_seeded_group_has_exactly_two_members()
    {
        await SeedAsync();

        var groups = await GroupsOfAsync(DatabaseSeeder.PrimaryUserEmail);

        Assert.Contains(groups, group => group.Members.Count == 2);
    }

    [Fact]
    public async Task A_seeded_user_reads_nonzero_balances_in_some_group()
    {
        await SeedAsync();

        var (client, groups) = await SignInAsync(DatabaseSeeder.PrimaryUserEmail);

        var summaries = new List<BalanceSummary>();
        foreach (var group in groups)
        {
            summaries.Add(await client.ReadSummaryAsync(group.Id));
        }

        Assert.Contains(summaries, summary => summary.Balances.Any(balance => balance.Amount != 0m));
    }

    [Fact]
    public async Task No_seeded_group_is_left_pending()
    {
        await SeedAsync();

        foreach (var email in DatabaseSeeder.UserEmails)
        {
            var (client, groups) = await SignInAsync(email);

            foreach (var group in groups)
            {
                var summary = await client.ReadSummaryAsync(group.Id);
                Assert.False(summary.BalancesPending, $"Group {group.Name} is still pending.");
            }
        }
    }

    [Fact]
    public async Task A_seeded_group_holds_a_pair_that_nets_to_zero()
    {
        await SeedAsync();

        var (client, groups) = await SignInAsync(DatabaseSeeder.PrimaryUserEmail);

        var balances = new List<BalanceEntry>();
        foreach (var group in groups)
        {
            balances.AddRange((await client.ReadSummaryAsync(group.Id)).Balances);
        }

        Assert.Contains(balances, balance => balance.Amount == 0m);
    }

    [Fact]
    public async Task The_first_seeded_user_is_a_debtor_in_one_group_and_a_creditor_in_another()
    {
        await SeedAsync();

        var groups = await GroupsOfAsync(DatabaseSeeder.PrimaryUserEmail);

        Assert.Contains(groups, group => group.NetBalance < 0m);
        Assert.Contains(groups, group => group.NetBalance > 0m);
    }

    [Fact]
    public async Task A_seeded_group_holds_a_settlement()
    {
        await SeedAsync();

        var types = new List<string>();
        foreach (var (_, expenses) in await SeededExpensesAsync())
        {
            types.AddRange(expenses.Select(expense => expense.GetProperty("type").GetString()!));
        }

        Assert.Contains("payment", types);
    }

    [Fact]
    public async Task Every_seeded_expense_has_splits_that_sum_to_its_amount_with_no_zero_split()
    {
        await SeedAsync();

        foreach (var (groupId, expenses) in await SeededExpensesAsync())
        {
            Assert.NotEmpty(expenses);

            foreach (var expense in expenses)
            {
                var amount = expense.GetProperty("amount").GetDecimal();
                var description = expense.GetProperty("description").GetString();
                var splits = expense.GetProperty("splits")
                    .EnumerateArray()
                    .Select(split => split.GetProperty("amount").GetDecimal())
                    .ToList();

                Assert.DoesNotContain(splits, split => split == 0m);

                if (expense.GetProperty("type").GetString() == "payment")
                {
                    // A settlement moves one amount between two people, so its splits
                    // cancel rather than summing to the total.
                    Assert.Equal(2, splits.Count);
                    Assert.Equal(0m, splits.Sum());
                    Assert.Equal(amount, Math.Abs(splits[0]));
                    continue;
                }

                Assert.Equal(amount, splits.Sum());
                Assert.NotEqual(JsonValueKind.Null, expense.GetProperty("splitMode").ValueKind);
                Assert.NotNull(description);
            }
        }
    }

    [Fact]
    public async Task Seeding_twice_does_not_duplicate_groups()
    {
        await SeedAsync();
        await SeedAsync();

        var names = (await GroupsOfAsync(DatabaseSeeder.PrimaryUserEmail))
            .Select(group => group.Name)
            .ToList();

        Assert.Equal(names.Distinct().Count(), names.Count);
    }

    private async Task SeedAsync()
    {
        await factory.DrainProcessedAsync();

        var outcome = await SeedCommand.SeedAndDrainAsync(factory.Services, TimeSpan.FromSeconds(30));

        Assert.True(outcome.Drained, "The seed command gave up before the worker drained.");
        Assert.NotEmpty(outcome.GroupIds);
    }

    private async Task<IReadOnlyList<(int GroupId, IReadOnlyList<JsonElement> Expenses)>> SeededExpensesAsync()
    {
        var seen = new Dictionary<int, IReadOnlyList<JsonElement>>();

        foreach (var email in DatabaseSeeder.UserEmails)
        {
            var (client, groups) = await SignInAsync(email);

            foreach (var group in groups.Where(group => !seen.ContainsKey(group.Id)))
            {
                var body = await client.ReadJsonAsync(await client.GetExpensesAsync(group.Id));
                seen[group.Id] = body.EnumerateArray().ToList();
            }
        }

        return seen.Select(entry => (entry.Key, entry.Value)).ToList();
    }

    private async Task<IReadOnlyList<GroupDTO>> GroupsOfAsync(string email) =>
        (await SignInAsync(email)).Groups;

    private async Task<(ApiClient Client, IReadOnlyList<GroupDTO> Groups)> SignInAsync(string email)
    {
        var response = await ApiClient.Create(factory).Http
            .PostAsJsonAsync("/auth/dev-login", new { email });
        response.EnsureSuccessStatusCode();

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(Json);
        var client = ApiClient.Create(factory, body.GetProperty("token").GetString());

        var groups = await client.Http.GetFromJsonAsync<List<GroupDTO>>("/group", Json);

        return (client, groups!);
    }
}
