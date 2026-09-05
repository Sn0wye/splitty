using Splitty.Domain.Entities;

namespace Splitty.Seeder;

/// <summary>
/// The development data set, written out rather than generated. It used to be random
/// members and random amounts, which is what hid the fact that nothing ever recomputed
/// balances: every run looked different, so "all zeros" read as one more random outcome.
///
/// The shapes here are the cases a screen has to survive — a six-member group, a
/// two-member group, amounts from a few euros to four figures, one debtor group, one
/// creditor group, a pair settled to exactly zero, and a percentage split.
/// </summary>
internal static class SeedData
{
    public const string John = "john@example.com";
    public const string Jane = "jane@example.com";
    public const string Bob = "bob@example.com";
    public const string Alice = "alice@example.com";
    public const string Charlie = "charlie@example.com";
    public const string Eva = "eva@example.com";

    /// <summary>
    /// Kept as they were: `POST /auth/dev-login` and the docs name these addresses.
    /// </summary>
    public static readonly IReadOnlyList<SeedUser> Users =
    [
        new("John Doe", John),
        new("Jane Smith", Jane),
        new("Bob Wilson", Bob),
        new("Alice Brown", Alice),
        new("Charlie Davis", Charlie),
        new("Eva Johnson", Eva)
    ];

    public static readonly IReadOnlyList<SeedGroup> Groups =
    [
        // Six members and a spread of two and a half orders of magnitude, so a
        // proportional layout meets real extremes. John pays the hotel, so he is the
        // creditor here.
        new(
            Name: "Weekend in Lisbon",
            Description: "Flights, hotel and everything after",
            CreatedBy: John,
            Members: [John, Jane, Bob, Alice, Charlie, Eva],
            Entries:
            [
                new SeedEntry(
                    Description: "Hotel",
                    Amount: 1240.00m,
                    PaidBy: John,
                    Mode: SplitMode.Equal,
                    DaysAgo: 12,
                    Splits:
                    [
                        new SeedSplit(John, 206.67m),
                        new SeedSplit(Jane, 206.67m),
                        new SeedSplit(Bob, 206.67m),
                        new SeedSplit(Alice, 206.67m),
                        new SeedSplit(Charlie, 206.67m),
                        // Absorbs the remainder cent, the way a client does.
                        new SeedSplit(Eva, 206.65m)
                    ]),
                new SeedEntry(
                    Description: "Flights",
                    Amount: 892.50m,
                    PaidBy: Jane,
                    Mode: SplitMode.Custom,
                    DaysAgo: 11,
                    // Three of the six flew together; the rest are simply not on the row.
                    Splits:
                    [
                        new SeedSplit(John, 312.50m),
                        new SeedSplit(Jane, 312.50m),
                        new SeedSplit(Bob, 267.50m)
                    ]),
                new SeedEntry(
                    Description: "Dinner at Belcanto",
                    Amount: 465.00m,
                    PaidBy: Eva,
                    Mode: SplitMode.Percentage,
                    DaysAgo: 9,
                    Splits:
                    [
                        new SeedSplit(Eva, 186.00m, 40m),
                        new SeedSplit(John, 139.50m, 30m),
                        new SeedSplit(Alice, 93.00m, 20m),
                        new SeedSplit(Charlie, 46.50m, 10m)
                    ]),
                new SeedEntry(
                    Description: "Taxi from the airport",
                    Amount: 38.40m,
                    PaidBy: Bob,
                    Mode: SplitMode.Equal,
                    DaysAgo: 12,
                    Splits:
                    [
                        new SeedSplit(Bob, 9.60m),
                        new SeedSplit(Alice, 9.60m),
                        new SeedSplit(Charlie, 9.60m),
                        new SeedSplit(Eva, 9.60m)
                    ]),
                new SeedEntry(
                    Description: "Pastéis de nata",
                    Amount: 9.75m,
                    PaidBy: Charlie,
                    Mode: SplitMode.Equal,
                    DaysAgo: 8,
                    Splits:
                    [
                        new SeedSplit(Charlie, 3.25m),
                        new SeedSplit(Jane, 3.25m),
                        new SeedSplit(Eva, 3.25m)
                    ]),
                new SeedEntry(
                    Description: "Postcards",
                    Amount: 4.20m,
                    PaidBy: Alice,
                    Mode: SplitMode.Equal,
                    DaysAgo: 7,
                    Splits:
                    [
                        new SeedSplit(Alice, 2.10m),
                        new SeedSplit(John, 2.10m)
                    ])
            ]),

        // The smallest case, and the one where John owes: Jane carries the rent.
        new(
            Name: "Apartment 4B",
            Description: "Rent, bills and the occasional repair",
            CreatedBy: Jane,
            Members: [John, Jane],
            Entries:
            [
                new SeedEntry(
                    Description: "Rent",
                    Amount: 1850.00m,
                    PaidBy: Jane,
                    Mode: SplitMode.Equal,
                    DaysAgo: 20,
                    Splits: [new SeedSplit(John, 925.00m), new SeedSplit(Jane, 925.00m)]),
                new SeedEntry(
                    Description: "Electricity",
                    Amount: 96.40m,
                    PaidBy: Jane,
                    Mode: SplitMode.Equal,
                    DaysAgo: 18,
                    Splits: [new SeedSplit(John, 48.20m), new SeedSplit(Jane, 48.20m)]),
                new SeedEntry(
                    Description: "Internet",
                    Amount: 79.90m,
                    PaidBy: John,
                    Mode: SplitMode.Equal,
                    DaysAgo: 17,
                    Splits: [new SeedSplit(John, 39.95m), new SeedSplit(Jane, 39.95m)])
            ]),

        // John repays Bob in full, so that pair sits at exactly zero — something for a
        // "hide settled pairs" rule to hide — and the timeline carries a payment row.
        new(
            Name: "Game Night",
            Description: "Weekly board games and takeaway",
            CreatedBy: Bob,
            Members: [John, Jane, Bob, Alice],
            Entries:
            [
                new SeedEntry(
                    Description: "Pizza",
                    Amount: 68.00m,
                    PaidBy: Bob,
                    Mode: SplitMode.Equal,
                    DaysAgo: 5,
                    Splits:
                    [
                        new SeedSplit(John, 17.00m),
                        new SeedSplit(Jane, 17.00m),
                        new SeedSplit(Bob, 17.00m),
                        new SeedSplit(Alice, 17.00m)
                    ]),
                new SeedEntry(
                    Description: "Board game rental",
                    Amount: 24.00m,
                    PaidBy: Alice,
                    Mode: SplitMode.Equal,
                    DaysAgo: 4,
                    Splits:
                    [
                        new SeedSplit(John, 8.00m),
                        new SeedSplit(Jane, 8.00m),
                        new SeedSplit(Alice, 8.00m)
                    ]),
                SeedEntry.Payment(
                    description: "Payment to Bob Wilson",
                    amount: 17.00m,
                    paidBy: John,
                    peer: Bob,
                    daysAgo: 3)
            ])
    ];
}

internal sealed record SeedUser(string Name, string Email);

internal sealed record SeedGroup(
    string Name,
    string Description,
    string CreatedBy,
    IReadOnlyList<string> Members,
    IReadOnlyList<SeedEntry> Entries);

internal sealed record SeedSplit(string Email, decimal Amount, decimal? Percentage = null);

internal sealed record SeedEntry(
    string Description,
    decimal Amount,
    string PaidBy,
    SplitMode? Mode,
    int DaysAgo,
    IReadOnlyList<SeedSplit> Splits,
    ExpenseType Type = ExpenseType.Expense)
{
    /// <summary>
    /// A settlement, built the way <c>BalanceService.SettleUp</c> builds one: no split
    /// mode, and two splits that cancel.
    /// </summary>
    public static SeedEntry Payment(
        string description,
        decimal amount,
        string paidBy,
        string peer,
        int daysAgo) =>
        new(
            description,
            amount,
            paidBy,
            Mode: null,
            daysAgo,
            Splits: [new SeedSplit(paidBy, amount), new SeedSplit(peer, -amount)],
            Type: ExpenseType.Payment);
}
