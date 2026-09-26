using Splitty.Domain.Entities;

namespace Splitty.DTO.Response;

/// <summary>
/// A group's spend over a range, once as the group spent it and once as it cost the caller,
/// so toggling between the two needs no second request. Settlements count in neither.
/// </summary>
public class GroupStatsResponse
{
    /// <summary>Every expense at its full amount.</summary>
    public SpendStatsResponse Group { get; init; } = new();

    /// <summary>
    /// Every expense the caller has a split in, at the split amount. Expenses without one
    /// are absent rather than counted at zero.
    /// </summary>
    public SpendStatsResponse Mine { get; init; } = new();
}

public class SpendStatsResponse
{
    public decimal Total { get; init; }
    public int ExpenseCount { get; init; }

    /// <summary>
    /// Only categories with a non-zero total, largest first, ties by category token.
    /// Per category rather than per heading, so regrouping categories stays client-side.
    /// </summary>
    public List<CategoryStatsResponse> Categories { get; init; } = [];
}

public class CategoryStatsResponse
{
    public ExpenseCategory Category { get; init; }
    public decimal Total { get; init; }
    public int ExpenseCount { get; init; }

    /// <summary>
    /// The largest expenses in the category, capped at <c>5</c>: enough for the client to
    /// derive the exact top five overall or under any heading, since each of those is in
    /// its own category's top five. Ranked by amount, then date, then id, all descending.
    /// </summary>
    public List<TopExpenseResponse> Top { get; init; } = [];
}

public class TopExpenseResponse
{
    public int ExpenseId { get; init; }
    public string Description { get; init; } = string.Empty;

    /// <summary>The effective date, <c>Date ?? CreatedAt</c>.</summary>
    public DateTime Date { get; init; }

    /// <summary>The expense total under <c>group</c>, the caller's split under <c>mine</c>.</summary>
    public decimal Amount { get; init; }
}
