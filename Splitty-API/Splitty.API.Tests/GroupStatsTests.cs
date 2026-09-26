using System.Net;
using System.Text.Json;

namespace Splitty.API.Tests;

/// <summary>
/// A group's spend for a range, by category, once at full expense amounts and once at the
/// caller's share. Read straight off the expense rows, so it owes nothing to the worker, and
/// filed by <c>Date ?? CreatedAt</c> against local midnights in the caller's time zone.
/// </summary>
[Collection(nameof(ApiCollection))]
public sealed class GroupStatsTests(ApiFactory factory)
{
    private const string AllTime = "tz=UTC";

    private static readonly DateTime August = new(2026, 8, 14, 12, 0, 0, DateTimeKind.Utc);

    [Fact]
    public async Task An_empty_group_has_zero_totals_and_no_categories()
    {
        var group = await GroupFixture.CreateAsync(factory);

        var stats = await StatsAsync(group.Owner, group.Id, AllTime);

        foreach (var half in new[] { stats.GetProperty("group"), stats.GetProperty("mine") })
        {
            Assert.Equal(0m, half.GetProperty("total").GetDecimal());
            Assert.Equal(0, half.GetProperty("expenseCount").GetInt32());
            Assert.Empty(half.GetProperty("categories").EnumerateArray());
        }
    }

    [Fact]
    public async Task An_empty_range_has_zero_totals_and_no_categories()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await CreateExpenseAsync(group, 20m, date: August);

        var stats = await StatsAsync(group.Owner, group.Id, "from=2026-01-01&to=2026-02-01&tz=UTC");

        Assert.Equal(0m, stats.GetProperty("group").GetProperty("total").GetDecimal());
        Assert.Empty(stats.GetProperty("group").GetProperty("categories").EnumerateArray());
        Assert.Empty(stats.GetProperty("mine").GetProperty("categories").EnumerateArray());
    }

    [Fact]
    public async Task Settlements_count_in_neither_half()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await factory.DrainProcessedAsync();
        await group.CreateExpenseAsync(amount: 20m, share: 10m, date: August);
        await factory.WaitForProcessedAsync();
        await group.SettleAsync(5m, August);
        await factory.WaitForProcessedAsync();

        var stats = await StatsAsync(group.Guest, group.Id, AllTime);

        Assert.Equal(20m, stats.GetProperty("group").GetProperty("total").GetDecimal());
        Assert.Equal(1, stats.GetProperty("group").GetProperty("expenseCount").GetInt32());
        Assert.Equal(10m, stats.GetProperty("mine").GetProperty("total").GetDecimal());
        Assert.Equal(1, stats.GetProperty("mine").GetProperty("expenseCount").GetInt32());
        Assert.DoesNotContain("payment", Tokens(stats.GetProperty("group")));
        Assert.DoesNotContain("payment", Tokens(stats.GetProperty("mine")));
    }

    [Fact]
    public async Task Group_counts_the_full_amount_and_mine_the_callers_share_of_an_expense_they_did_not_pay()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var expenseId = await CreateExpenseAsync(group, 30m, guestShare: 20m, date: August);

        var stats = await StatsAsync(group.Guest, group.Id, AllTime);

        var groupHalf = stats.GetProperty("group");
        Assert.Equal(30m, groupHalf.GetProperty("total").GetDecimal());
        Assert.Equal(30m, TopOf(groupHalf, "general")[0].GetProperty("amount").GetDecimal());

        var mine = stats.GetProperty("mine");
        Assert.Equal(20m, mine.GetProperty("total").GetDecimal());
        var top = TopOf(mine, "general");
        Assert.Equal(expenseId, top[0].GetProperty("expenseId").GetInt32());
        Assert.Equal(20m, top[0].GetProperty("amount").GetDecimal());
    }

    [Fact]
    public async Task An_expense_the_caller_has_no_split_in_is_absent_from_mine()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await CreateExpenseAsync(group, 25m, category: "taxi", guestShare: 0m, date: August);
        await CreateExpenseAsync(group, 10m, category: "groceries", date: August);

        var stats = await StatsAsync(group.Guest, group.Id, AllTime);

        Assert.Equal(35m, stats.GetProperty("group").GetProperty("total").GetDecimal());
        Assert.Contains("taxi", Tokens(stats.GetProperty("group")));

        var mine = stats.GetProperty("mine");
        Assert.Equal(5m, mine.GetProperty("total").GetDecimal());
        Assert.Equal(1, mine.GetProperty("expenseCount").GetInt32());
        Assert.Equal(new[] { "groceries" }, Tokens(mine));
    }

    [Fact]
    public async Task Categories_carry_totals_and_counts_and_sort_by_total_then_token()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await CreateExpenseAsync(group, 20m, category: "taxi", date: August);
        await CreateExpenseAsync(group, 10m, category: "taxi", date: August);
        await CreateExpenseAsync(group, 50m, category: "dining_out", date: August);
        await CreateExpenseAsync(group, 30m, category: "groceries", date: August);

        var stats = await StatsAsync(group.Owner, group.Id, AllTime);
        var groupHalf = stats.GetProperty("group");

        Assert.Equal(110m, groupHalf.GetProperty("total").GetDecimal());
        Assert.Equal(4, groupHalf.GetProperty("expenseCount").GetInt32());
        Assert.Equal(new[] { "dining_out", "groceries", "taxi" }, Tokens(groupHalf));

        var taxi = Category(groupHalf, "taxi");
        Assert.Equal(30m, taxi.GetProperty("total").GetDecimal());
        Assert.Equal(2, taxi.GetProperty("expenseCount").GetInt32());
    }

    [Fact]
    public async Task Top_ranks_by_amount_then_date_then_id_and_stops_at_five()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var earlier = August.AddDays(-1);
        var fifty = await CreateExpenseAsync(group, 50m, date: earlier);
        var fortyEarlier = await CreateExpenseAsync(group, 40m, date: earlier);
        var fortyLater = await CreateExpenseAsync(group, 40m, date: August);
        var thirtyFirst = await CreateExpenseAsync(group, 30m, date: August);
        var thirtySecond = await CreateExpenseAsync(group, 30m, date: August);
        await CreateExpenseAsync(group, 10m, date: August);

        var stats = await StatsAsync(group.Owner, group.Id, AllTime);
        var category = Category(stats.GetProperty("group"), "general");

        Assert.Equal(6, category.GetProperty("expenseCount").GetInt32());
        Assert.Equal(200m, category.GetProperty("total").GetDecimal());
        Assert.Equal(
            new[] { fifty, fortyLater, fortyEarlier, thirtySecond, thirtyFirst },
            TopOf(stats.GetProperty("group"), "general").Select(e => e.GetProperty("expenseId").GetInt32()));
    }

    [Fact]
    public async Task A_top_row_carries_the_description_and_effective_date()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await CreateExpenseAsync(group, 20m, description: "Sushi", date: August);

        var stats = await StatsAsync(group.Owner, group.Id, AllTime);
        var row = TopOf(stats.GetProperty("group"), "general")[0];

        Assert.Equal("Sushi", row.GetProperty("description").GetString());
        Assert.Equal("2026-08-14T12:00:00Z", row.GetProperty("date").GetString());
    }

    [Fact]
    public async Task Mine_ranks_by_the_callers_share_not_the_expense_total()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var bigTotal = await CreateExpenseAsync(group, 100m, guestShare: 10m, date: August);
        var bigShare = await CreateExpenseAsync(group, 50m, guestShare: 40m, date: August);

        var stats = await StatsAsync(group.Guest, group.Id, AllTime);

        Assert.Equal(
            new[] { bigTotal, bigShare },
            TopOf(stats.GetProperty("group"), "general").Select(e => e.GetProperty("expenseId").GetInt32()));
        Assert.Equal(
            new[] { bigShare, bigTotal },
            TopOf(stats.GetProperty("mine"), "general").Select(e => e.GetProperty("expenseId").GetInt32()));
    }

    /// <summary>
    /// São Paulo is UTC−3, so its local midnight on 1 September is 03:00Z. The range is
    /// <c>[from, to)</c> between those local midnights.
    /// </summary>
    [Fact]
    public async Task From_is_inclusive_and_to_exclusive_at_local_midnight()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await CreateExpenseAsync(group, 1m, date: new DateTime(2026, 9, 1, 2, 59, 59, DateTimeKind.Utc));
        await CreateExpenseAsync(group, 2m, date: new DateTime(2026, 9, 1, 3, 0, 0, DateTimeKind.Utc));
        await CreateExpenseAsync(group, 4m, date: new DateTime(2026, 10, 1, 2, 59, 59, DateTimeKind.Utc));
        await CreateExpenseAsync(group, 8m, date: new DateTime(2026, 10, 1, 3, 0, 0, DateTimeKind.Utc));

        var stats = await StatsAsync(group.Owner, group.Id, "from=2026-09-01&to=2026-10-01&tz=America/Sao_Paulo");

        Assert.Equal(6m, stats.GetProperty("group").GetProperty("total").GetDecimal());
    }

    [Fact]
    public async Task The_time_zone_decides_which_month_an_expense_falls_in()
    {
        var group = await GroupFixture.CreateAsync(factory);
        // 22:00 on 30 September in São Paulo.
        await CreateExpenseAsync(group, 20m, date: new DateTime(2026, 10, 1, 1, 0, 0, DateTimeKind.Utc));

        Assert.Equal(20m, await GroupTotalAsync(group, "from=2026-09-01&to=2026-10-01&tz=America/Sao_Paulo"));
        Assert.Equal(0m, await GroupTotalAsync(group, "from=2026-10-01&to=2026-11-01&tz=America/Sao_Paulo"));
        Assert.Equal(0m, await GroupTotalAsync(group, "from=2026-09-01&to=2026-10-01&tz=UTC"));
        Assert.Equal(20m, await GroupTotalAsync(group, "from=2026-10-01&to=2026-11-01&tz=UTC"));
    }

    /// <summary>
    /// São Paulo sprang forward at midnight on 4 November 2018, so that local midnight never
    /// happened; the day starts at 01:00−02, which is 03:00Z.
    /// </summary>
    [Fact]
    public async Task A_local_midnight_skipped_by_daylight_saving_resolves_to_the_first_instant_after_it()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await CreateExpenseAsync(group, 1m, date: new DateTime(2018, 11, 4, 2, 59, 59, DateTimeKind.Utc));
        await CreateExpenseAsync(group, 2m, date: new DateTime(2018, 11, 4, 3, 0, 0, DateTimeKind.Utc));

        Assert.Equal(2m, await GroupTotalAsync(group, "from=2018-11-04&tz=America/Sao_Paulo"));
        Assert.Equal(1m, await GroupTotalAsync(group, "to=2018-11-04&tz=America/Sao_Paulo"));
    }

    [Fact]
    public async Task A_future_dated_expense_counts_only_when_the_range_covers_it()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await CreateExpenseAsync(group, 20m, date: new DateTime(2099, 6, 15, 12, 0, 0, DateTimeKind.Utc));

        Assert.Equal(20m, await GroupTotalAsync(group, "from=2099-06-01&to=2099-07-01&tz=UTC"));
        Assert.Equal(0m, await GroupTotalAsync(group, "from=2099-07-01&to=2099-08-01&tz=UTC"));
        Assert.Equal(20m, await GroupTotalAsync(group, AllTime));
    }

    [Fact]
    public async Task An_undated_expense_is_filed_by_its_creation_time()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await CreateExpenseAsync(group, 20m, date: null);
        var today = DateOnly.FromDateTime(DateTime.UtcNow);

        Assert.Equal(20m, await GroupTotalAsync(group, $"from={today.AddDays(-1):yyyy-MM-dd}&to={today.AddDays(2):yyyy-MM-dd}&tz=UTC"));
        Assert.Equal(0m, await GroupTotalAsync(group, $"to={today.AddDays(-1):yyyy-MM-dd}&tz=UTC"));
    }

    [Fact]
    public async Task A_saved_expense_is_reflected_without_waiting_for_the_worker()
    {
        using var gate = new RecomputeGate();
        await using var gated = factory.WithGate(gate);
        var group = await GroupFixture.CreateAsync(gated);
        await gated.DrainProcessedAsync();

        await CreateExpenseAsync(group, 20m, date: August);
        await gate.WaitForEntryAsync();

        Assert.True((await group.Owner.ReadSummaryAsync(group.Id)).BalancesPending);
        Assert.Equal(20m, await GroupTotalAsync(group, AllTime));

        gate.Release();
        await gated.WaitForProcessedAsync();
    }

    [Theory]
    [InlineData("from=2026-10-01&to=2026-10-01&tz=UTC")]
    [InlineData("from=2026-10-02&to=2026-10-01&tz=UTC")]
    [InlineData("from=2026-13-01&tz=UTC")]
    [InlineData("from=01/10/2026&tz=UTC")]
    [InlineData("to=yesterday&tz=UTC")]
    [InlineData("from=2026-09-01")]
    [InlineData("from=2026-09-01&tz=")]
    [InlineData("from=2026-09-01&tz=Mars/Olympus_Mons")]
    public async Task A_bad_query_is_a_400(string query)
    {
        var group = await GroupFixture.CreateAsync(factory);

        var response = await group.Owner.GetStatsAsync(group.Id, query);

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task A_non_member_is_refused()
    {
        var group = await GroupFixture.CreateAsync(factory);
        await CreateExpenseAsync(group, 20m, date: August);
        var strangerUser = await ApiClient.Create(factory).SignInAsync();
        var stranger = ApiClient.Create(factory, strangerUser.Token);

        var response = await stranger.GetStatsAsync(group.Id, AllTime);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    /// <summary>
    /// Paid by the owner, who takes whatever the guest does not. The guest takes half unless
    /// told otherwise; a guest share of zero leaves the guest without a split row at all.
    /// </summary>
    private static async Task<int> CreateExpenseAsync(
        GroupFixture group,
        decimal amount,
        string category = "general",
        decimal? guestShare = null,
        string description = "Dinner",
        DateTime? date = null)
    {
        var guest = guestShare ?? amount / 2;
        var splits = new List<object> { new { userId = group.OwnerId, amount = amount - guest } };
        if (guest > 0) splits.Add(new { userId = group.GuestId, amount = guest });

        var response = await group.Owner.CreateExpenseAsync(group.Id, new
        {
            paidBy = group.OwnerId,
            amount,
            description,
            date,
            category,
            splitMode = "custom",
            splits
        });

        var body = await group.Owner.ReadJsonAsync(response);
        return body.GetProperty("id").GetInt32();
    }

    private static async Task<JsonElement> StatsAsync(ApiClient client, int groupId, string query) =>
        await client.ReadJsonAsync(await client.GetStatsAsync(groupId, query));

    private static async Task<decimal> GroupTotalAsync(GroupFixture group, string query) =>
        (await StatsAsync(group.Owner, group.Id, query)).GetProperty("group").GetProperty("total").GetDecimal();

    private static List<string> Tokens(JsonElement half) => half.GetProperty("categories")
        .EnumerateArray()
        .Select(c => c.GetProperty("category").GetString()!)
        .ToList();

    private static JsonElement Category(JsonElement half, string token) => half.GetProperty("categories")
        .EnumerateArray()
        .Single(c => c.GetProperty("category").GetString() == token);

    private static List<JsonElement> TopOf(JsonElement half, string token) =>
        Category(half, token).GetProperty("top").EnumerateArray().ToList();
}
