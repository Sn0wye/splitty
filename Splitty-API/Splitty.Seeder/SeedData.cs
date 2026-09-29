using Splitty.Domain.Entities;
using static Splitty.Domain.Entities.ExpenseCategory;

namespace Splitty.Seeder;

/// <summary>
/// The development data set, written out rather than generated. It used to be random
/// members and random amounts, which is what hid the fact that nothing ever recomputed
/// balances: every run looked different, so "all zeros" read as one more random outcome.
/// The helpers below only do the cent arithmetic a client would; every description, amount,
/// payer and participant is still spelled out.
///
/// The shapes here are the cases a screen has to survive — a six-member group, two-member
/// and three-member groups, amounts from under a euro-fifty to four figures, groups where
/// John owes and groups where he is owed, a pair settled to exactly zero, percentage and
/// custom splits, a payer outside their own split, a future-dated row, monthly bills over
/// half a year for the Charts screen, and every category at least once — including
/// uncategorized rows, since general is a value the client renders.
/// </summary>
internal static class SeedData
{
    public const string John = "john@example.com";
    public const string Jane = "jane@example.com";
    public const string Bob = "bob@example.com";
    public const string Alice = "alice@example.com";
    public const string Charlie = "charlie@example.com";
    public const string Eva = "eva@example.com";
    public const string Mia = "mia@example.com";
    public const string Leo = "leo@example.com";

    /// <summary>
    /// The first six are kept as they were: `POST /auth/dev-login` and the docs name these
    /// addresses. Mia and Leo only share some groups with John, so People has peers he
    /// meets in one group and peers he meets in several.
    /// </summary>
    public static readonly IReadOnlyList<SeedUser> Users =
    [
        new("John Doe", John),
        new("Jane Smith", Jane),
        new("Bob Wilson", Bob),
        new("Alice Brown", Alice),
        new("Charlie Davis", Charlie),
        new("Eva Johnson", Eva),
        new("Mia Garcia", Mia),
        new("Leo Martins", Leo)
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
                Equal("Hotel", 1240.00m, John, Hotel, 47, John, Jane, Bob, Alice, Charlie, Eva),
                // Three of the six flew together; the rest are simply not on the row.
                Custom("Flights", Jane, Plane, 48, (John, 312.50m), (Jane, 312.50m), (Bob, 267.50m)),
                Equal("Taxi from the airport", 38.40m, Bob, Taxi, 47, Bob, Alice, Charlie, Eva),
                Equal("Breakfast groceries", 64.35m, Bob, Groceries, 46, John, Jane, Bob, Alice, Charlie, Eva),
                Percent("Dinner at Belcanto", 465.00m, Eva, DiningOut, 46, (Eva, 40m), (John, 30m), (Alice, 20m), (Charlie, 10m)),
                // Left uncategorized on purpose: general is a value the client has to
                // render, and a data set where every row is categorized never shows it.
                Equal("Pastéis de nata", 9.75m, Charlie, General, 45, Charlie, Jane, Eva),
                Equal("Train to Sintra", 27.60m, Alice, BusTrain, 45, John, Jane, Bob, Alice, Charlie, Eva),
                Equal("Pena Palace tickets", 120.00m, John, EntertainmentOther, 45, John, Jane, Bob, Alice, Charlie, Eva),
                Equal("Sunscreen and plasters", 14.90m, Alice, Medical, 45, Alice, John),
                Equal("Tram 28 day passes", 25.20m, Eva, BusTrain, 44, Eva, Alice, Charlie, Bob),
                Equal("Bike rental along the river", 45.00m, Eva, Bicycle, 44, Eva, Alice, Charlie),
                Equal("Surf lesson in Cascais", 180.00m, Bob, Sports, 44, Bob, Charlie, Eva),
                Equal("Fado night", 210.00m, Jane, Music, 44, Jane, John, Alice, Eva),
                Equal("Wine at Time Out Market", 48.00m, Charlie, Liquor, 44, Charlie, Bob, Eva),
                Equal("Postcards", 4.20m, Alice, Gifts, 44, Alice, John),
                Equal("Taxi back to the airport", 41.80m, John, Taxi, 43, John, Jane, Bob),
                Settle(Alice, John, 200.00m, 38)
            ]),

        // The smallest case, and the one where John owes: Jane carries the rent. Six months
        // of bills, so the Charts screen has a month-over-month shape to draw.
        new(
            Name: "Apartment 4B",
            Description: "Rent, bills and the occasional repair",
            CreatedBy: Jane,
            Members: [John, Jane],
            Entries:
            [
                ..Months(6).Select(month =>
                    Equal("Rent", 1850.00m, Jane, Rent, OnDay(month, 1), John, Jane)),
                ..new[] { 96.40m, 88.15m, 71.30m, 64.80m, 82.55m, 104.20m }.Select((amount, month) =>
                    Equal("Electricity", amount, Jane, Electricity, OnDay(month, 8), John, Jane)),
                ..Months(6).Select(month =>
                    Equal("Internet", 79.90m, John, TvPhoneInternet, OnDay(month, 12), John, Jane)),
                ..Months(6).Select(month =>
                    Equal("Cleaner", 60.00m, John, Cleaning, OnDay(month, 20), John, Jane)),
                Equal("Water", 58.70m, John, Water, OnDay(1, 15), John, Jane),
                Equal("Water", 61.25m, John, Water, OnDay(4, 15), John, Jane),
                Equal("Groceries", 142.37m, Jane, Groceries, 2, John, Jane),
                Equal("Takeaway Thai", 42.80m, Jane, DiningOut, 6, John, Jane),
                Equal("Farmers market", 36.80m, John, Groceries, 9, John, Jane),
                Equal("Dish soap, bin bags and paper towels", 27.45m, Jane, HouseholdSupplies, 15, John, Jane),
                // A bulk run John mostly eats from.
                Percent("Costco run", 213.45m, John, Groceries, 24, (John, 60m), (Jane, 40m)),
                Equal("Plant for the balcony", 24.50m, Jane, General, 30, John, Jane),
                Equal("Groceries", 97.12m, Jane, Groceries, 41, John, Jane),
                Equal("Groceries", 118.64m, John, Groceries, 66, John, Jane),
                Equal("Light bulbs", 18.99m, John, HouseholdSupplies, 70, John, Jane),
                Equal("New sofa", 899.00m, John, Furniture, 80, John, Jane),
                Equal("Groceries", 88.90m, Jane, Groceries, 95, John, Jane),
                Settle(John, Jane, 1850.00m, OnDay(2, 3)),
                Settle(John, Jane, 925.00m, 10)
            ]),

        // John repays Bob in full, so that pair sits at exactly zero — something for a
        // "hide settled pairs" rule to hide — and the timeline carries a payment row. Keep
        // it that way: no row here is paid by one of them with the other on it.
        new(
            Name: "Game Night",
            Description: "Weekly board games and takeaway",
            CreatedBy: Bob,
            Members: [John, Jane, Bob, Alice],
            Entries:
            [
                Equal("Pizza", 68.00m, Bob, DiningOut, 5, John, Jane, Bob, Alice),
                Equal("Board game rental", 24.00m, Alice, Games, 4, John, Jane, Alice),
                Settle(John, Bob, 17.00m, 3),
                Equal("Catan expansion", 45.00m, Jane, Games, 12, John, Jane, Bob, Alice),
                Equal("Sushi takeaway", 84.60m, Alice, DiningOut, 12, John, Jane, Bob, Alice),
                Equal("Beer and snacks", 32.40m, Bob, Liquor, 19, Bob, Jane, Alice),
                Equal("Escape room", 120.00m, Jane, EntertainmentOther, 26, John, Jane, Bob, Alice),
                Equal("Chips and dip", 11.80m, John, FoodOther, 26, John, Jane, Alice),
                Custom("Burgers", Alice, DiningOut, 33, (Jane, 18.40m), (Alice, 16.60m), (John, 22.20m)),
                Equal("Poker chip set", 39.99m, John, Games, 40, John, Jane, Alice),
                Equal("Movie night tickets", 52.00m, Bob, Movies, 47, Bob, Jane, Alice)
            ]),

        // Five people, one week, early in the year: Charlie books the chalet and ends up
        // owed by nearly everyone, and John is a debtor for once.
        new(
            Name: "Ski Trip Chamonix",
            Description: "Chalet, lift passes and too much raclette",
            CreatedBy: Charlie,
            Members: [John, Bob, Charlie, Eva, Mia],
            Entries:
            [
                Equal("Travel insurance", 145.00m, John, Insurance, 205, John, Bob, Charlie, Eva, Mia),
                Equal("Chalet", 2150.00m, Charlie, Hotel, 201, John, Bob, Charlie, Eva, Mia),
                Equal("Car rental", 386.40m, John, Car, 201, John, Bob, Mia),
                Equal("Diesel", 92.35m, Bob, GasFuel, 201, John, Bob, Mia),
                Equal("Motorway tolls", 23.60m, John, TransportationOther, 201, John, Bob, Mia),
                Equal("Airport shuttle", 180.00m, Eva, BusTrain, 201, Charlie, Eva),
                Equal("Lift passes", 1245.00m, Mia, Sports, 200, John, Bob, Charlie, Eva, Mia),
                Custom("Ski rental", Eva, Sports, 200, (Eva, 165.00m), (Charlie, 195.00m), (John, 180.00m)),
                Equal("Supermarket run", 187.45m, Eva, Groceries, 200, John, Bob, Charlie, Eva, Mia),
                Equal("Parking at Grands Montets", 36.00m, Mia, Parking, 199, John, Bob, Mia),
                Equal("Raclette dinner", 264.00m, Bob, DiningOut, 199, John, Bob, Charlie, Eva, Mia),
                Equal("Génépi and wine", 76.50m, Charlie, Liquor, 198, Charlie, Eva, Mia, Bob),
                // Charlie paid and is not on the row: the whole amount is Bob's.
                Custom("Pharmacy for Bob's knee", Charlie, Medical, 197, (Bob, 23.80m)),
                Settle(John, Charlie, 400.00m, 180),
                Settle(Bob, Mia, 200.00m, 176)
            ]),

        // A flatshare John is not in, so the other users have a busy group of their own.
        // Alice holds the lease and is owed by everyone.
        new(
            Name: "Maple Street House",
            Description: "Four flatmates and a cat called Miso",
            CreatedBy: Alice,
            Members: [Jane, Alice, Charlie, Leo],
            Entries:
            [
                ..Months(6).Select(month =>
                    Percent("Rent", 2400.00m, Alice, Rent, OnDay(month, 1), (Alice, 30m), (Jane, 25m), (Charlie, 25m), (Leo, 20m))),
                ..Months(6).Select(month =>
                    Equal("Fibre broadband", 49.99m, Jane, TvPhoneInternet, OnDay(month, 5), Jane, Alice, Charlie, Leo)),
                ..new[] { 38.20m, 31.75m, 29.40m, 44.10m, 86.30m, 132.55m }.Select((amount, month) =>
                    Equal("Gas", amount, Charlie, HeatGas, OnDay(month, 18), Jane, Alice, Charlie, Leo)),
                ..Months(6).Select(month =>
                    Equal("Cleaner", 80.00m, Leo, Cleaning, OnDay(month, 25), Jane, Alice, Charlie, Leo)),
                Equal("Shared pantry restock", 76.40m, Leo, Groceries, 4, Jane, Alice, Charlie, Leo),
                Equal("Toilet paper, sponges and detergent", 38.75m, Charlie, HouseholdSupplies, 8, Jane, Alice, Charlie, Leo),
                // Miso is Alice's and Leo's cat, so only they pay for her.
                Custom("Cat food and litter", Alice, Pets, 12, (Alice, 27.15m), (Leo, 27.15m)),
                Equal("Plumber for the kitchen sink", 145.00m, Charlie, Maintenance, 20, Jane, Alice, Charlie, Leo),
                Equal("Gardener", 90.00m, Jane, Services, 35, Jane, Alice, Charlie, Leo),
                Equal("Water", 142.60m, Leo, Water, 40, Jane, Alice, Charlie, Leo),
                Custom("Vet check-up for Miso", Leo, Pets, 52, (Alice, 42.50m), (Leo, 42.50m)),
                Equal("Bin collection", 45.00m, Charlie, Trash, 60, Jane, Alice, Charlie, Leo),
                Equal("Robot vacuum", 329.00m, Leo, Electronics, 75, Jane, Alice, Charlie, Leo),
                Equal("Gardener", 90.00m, Jane, Services, 95, Jane, Alice, Charlie, Leo),
                Percent("Council tax", 1236.00m, Jane, Taxes, 100, (Alice, 30m), (Jane, 25m), (Charlie, 25m), (Leo, 20m)),
                Equal("Dining table from the flea market", 180.00m, Alice, Furniture, 110, Jane, Alice, Charlie, Leo),
                Equal("Water", 138.90m, Leo, Water, 130, Jane, Alice, Charlie, Leo),
                Equal("Spare keys", 16.00m, Jane, HomeOther, 140, Jane, Alice, Charlie, Leo),
                Equal("Bin collection", 45.00m, Charlie, Trash, 150, Jane, Alice, Charlie, Leo),
                Equal("Housewarming drinks", 63.80m, Charlie, General, 165, Jane, Alice, Charlie, Leo),
                Settle(Leo, Alice, 480.00m, 58),
                Settle(Leo, Alice, 480.00m, 28),
                Settle(Charlie, Alice, 1200.00m, 45),
                Settle(Jane, Alice, 600.00m, 14)
            ]),

        // Small, frequent amounts between colleagues, and one row dated in the future:
        // concert tickets bought now for a show next month.
        new(
            Name: "Office Lunch Club",
            Description: "Lunches, coffee and the odd team outing",
            CreatedBy: Mia,
            Members: [John, Alice, Mia, Leo],
            Entries:
            [
                Equal("Concert tickets", 236.00m, John, Music, -21, John, Alice, Mia, Leo),
                Equal("Ramen Tuesday", 58.40m, John, DiningOut, 2, John, Alice, Mia, Leo),
                Equal("Tacos", 47.20m, Mia, DiningOut, 6, John, Mia, Leo),
                Equal("Coffee beans for the office", 32.00m, Leo, FoodOther, 9, John, Alice, Mia, Leo),
                Custom("Poke bowls", Alice, DiningOut, 13, (Alice, 14.95m), (John, 16.90m), (Mia, 15.10m), (Leo, 14.90m)),
                Equal("Birthday cake for Alice", 38.50m, John, Gifts, 16, John, Mia, Leo),
                Equal("Friday pub", 96.00m, Leo, Liquor, 20, John, Alice, Mia, Leo),
                Equal("SwiftUI workshop", 450.00m, Mia, Education, 27, John, Mia),
                Equal("Indian buffet", 72.00m, Alice, DiningOut, 34, John, Alice, Mia, Leo),
                Equal("Espresso machine descaler", 12.49m, Leo, HouseholdSupplies, 41, John, Alice, Mia, Leo),
                Equal("Burrito run", 44.80m, Mia, DiningOut, 48, John, Alice, Mia, Leo),
                Equal("Leaving gift for Sam", 80.00m, Alice, Gifts, 55, John, Alice, Mia, Leo),
                Equal("Lunch", 39.60m, Leo, General, 62, John, Alice, Leo),
                Settle(John, Mia, 80.00m, 7)
            ]),

        // Three co-owners and the big recurring bills: John pays the mortgage, so he is owed
        // the most here, and the others chip in with the annual costs.
        new(
            Name: "Cabin by the Lake",
            Description: "Mortgage and upkeep for the shared cabin",
            CreatedBy: John,
            Members: [John, Charlie, Leo],
            Entries:
            [
                ..Months(6).Select(month =>
                    Percent("Mortgage", 1860.00m, John, Mortgage, OnDay(month, 3), (John, 40m), (Charlie, 35m), (Leo, 25m))),
                Equal("Cleaning after the summer rental", 150.00m, Charlie, Cleaning, 14, John, Charlie, Leo),
                Equal("Electricity", 112.45m, John, Electricity, 25, John, Charlie, Leo),
                Equal("Trash pickup", 36.00m, Leo, Trash, 30, John, Charlie, Leo),
                Equal("Water", 67.30m, Charlie, Water, 45, John, Charlie, Leo),
                Equal("Propane refill", 318.60m, John, HeatGas, 60, John, Charlie, Leo),
                Equal("Porch chairs", 210.00m, Leo, Furniture, 65, John, Charlie, Leo),
                Equal("Roof repair", 1450.00m, John, Maintenance, 90, John, Charlie, Leo),
                Equal("Septic tank pump-out", 395.00m, Charlie, UtilitiesOther, 105, John, Charlie, Leo),
                Percent("Property tax", 2340.00m, Leo, Taxes, 120, (John, 40m), (Charlie, 35m), (Leo, 25m)),
                Percent("Home insurance", 1180.00m, Charlie, Insurance, 150, (John, 40m), (Charlie, 35m), (Leo, 25m)),
                Equal("Replacement keys and lockbox", 48.00m, John, HomeOther, 160, John, Charlie, Leo),
                Equal("Snow plowing contract", 300.00m, Charlie, Services, 170, John, Charlie, Leo),
                Equal("Firewood", 240.00m, Leo, HeatGas, 175, John, Charlie, Leo),
                Settle(Leo, John, 900.00m, 35),
                Settle(Charlie, John, 1300.00m, 40)
            ]),

        // Three parents sharing the school run. Uneven custom splits where one family has
        // two kids, and most of the Life categories.
        new(
            Name: "School Run Parents",
            Description: "Carpool, clubs and everything the school asks for",
            CreatedBy: Eva,
            Members: [John, Eva, Mia],
            Entries:
            [
                Equal("Bake sale supplies", 18.60m, Eva, General, 5, John, Eva, Mia),
                Equal("Class party snacks", 27.90m, Mia, FoodOther, 8, John, Eva, Mia),
                Equal("Carpool fuel", 64.20m, John, GasFuel, 10, John, Eva, Mia),
                Equal("Museum school trip", 45.00m, John, Education, 12, John, Eva, Mia),
                Equal("Babysitter for parents' evening", 72.00m, Mia, Childcare, 18, John, Eva, Mia),
                Equal("After-school club, autumn term", 540.00m, Eva, Childcare, 25, John, Eva, Mia),
                Equal("School photos", 39.00m, Eva, LifeOther, 28, John, Eva, Mia),
                Custom("School bus passes", Mia, BusTrain, 30, (Mia, 45.00m), (Eva, 90.00m)),
                Percent("Textbooks", 94.50m, Eva, Education, 33, (John, 40m), (Eva, 30m), (Mia, 30m)),
                Custom("School uniforms", John, Clothing, 35, (John, 62.10m), (Eva, 124.30m)),
                Equal("Carpool fuel", 58.75m, Eva, GasFuel, 40, John, Eva, Mia),
                Equal("Swimming lessons", 210.00m, John, Sports, 50, John, Eva, Mia),
                Equal("Carpool fuel", 61.30m, Mia, GasFuel, 70, John, Eva, Mia),
                Equal("Teacher's end-of-year gift", 60.00m, Mia, Gifts, 95, John, Eva, Mia),
                Settle(Mia, Eva, 100.00m, 20)
            ])
    ];

    /// <summary>
    /// An equal split with every share rounded to the cent and the last participant
    /// absorbing the remainder, the way a client does.
    /// </summary>
    private static SeedEntry Equal(
        string description,
        decimal amount,
        string paidBy,
        ExpenseCategory category,
        int daysAgo,
        params string[] among)
    {
        var share = Math.Round(amount / among.Length, 2, MidpointRounding.AwayFromZero);
        var splits = among
            .Select((email, index) => new SeedSplit(
                email,
                index == among.Length - 1 ? amount - share * (among.Length - 1) : share))
            .ToList();

        return new SeedEntry(description, amount, paidBy, SplitMode.Equal, daysAgo, splits, category);
    }

    /// <summary>A custom split: the amount is whatever the shares add up to.</summary>
    private static SeedEntry Custom(
        string description,
        string paidBy,
        ExpenseCategory category,
        int daysAgo,
        params (string Email, decimal Amount)[] shares) =>
        new(
            description,
            shares.Sum(share => share.Amount),
            paidBy,
            SplitMode.Custom,
            daysAgo,
            shares.Select(share => new SeedSplit(share.Email, share.Amount)).ToList(),
            category);

    /// <summary>
    /// A percentage split, each amount rounded to the cent and the last participant
    /// absorbing the remainder.
    /// </summary>
    private static SeedEntry Percent(
        string description,
        decimal amount,
        string paidBy,
        ExpenseCategory category,
        int daysAgo,
        params (string Email, decimal Percentage)[] shares)
    {
        var splits = shares
            .Select(share => new SeedSplit(
                share.Email,
                Math.Round(amount * share.Percentage / 100m, 2, MidpointRounding.AwayFromZero),
                share.Percentage))
            .ToList();
        splits[^1] = splits[^1] with { Amount = amount - splits.Take(splits.Count - 1).Sum(split => split.Amount) };

        return new SeedEntry(description, amount, paidBy, SplitMode.Percentage, daysAgo, splits, category);
    }

    /// <summary>A settlement described the way <c>BalanceService.SettleUp</c> describes one.</summary>
    private static SeedEntry Settle(string from, string to, decimal amount, int daysAgo) =>
        SeedEntry.Payment(
            description: $"Payment to {Users.Single(user => user.Email == to).Name}",
            amount: amount,
            paidBy: from,
            peer: to,
            daysAgo: daysAgo);

    /// <summary>This month and the ones before it, most recent first.</summary>
    private static IEnumerable<int> Months(int count) => Enumerable.Range(0, count);

    /// <summary>
    /// Days back to the given day of a past calendar month, so a monthly bill lands once in
    /// every month the Charts screen draws instead of drifting on a fixed 30-day step.
    /// Clamped to today when this month's day has not come yet.
    /// </summary>
    private static int OnDay(int monthsAgo, int day)
    {
        var today = DateTime.UtcNow.Date;
        var month = today.AddMonths(-monthsAgo);
        var date = new DateTime(month.Year, month.Month, Math.Min(day, DateTime.DaysInMonth(month.Year, month.Month)));

        return Math.Max(0, (today - date).Days);
    }
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
    ExpenseCategory Category = ExpenseCategory.General,
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
            Category: ExpenseCategory.Payment,
            Type: ExpenseType.Payment);
}
