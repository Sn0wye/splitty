namespace Splitty.Domain.Entities;

/// <summary>
/// What an expense was for, from a closed server-defined list. Stored as the member name
/// rather than the ordinal, so the list stays editable without relabelling stored rows;
/// see docs/adr/0002-expense-categories-are-a-closed-text-list.md.
///
/// The headings a client groups these under (Food and drink, Transportation, …) are not
/// stored: a second column could only ever disagree with this one. Each heading carries
/// its own <c>*Other</c> leaf because the client takes its tint from the heading, and
/// <see cref="General"/> has none.
///
/// Values are append-only by name. Renaming a member is a data migration.
/// </summary>
public enum ExpenseCategory
{
    /// The value that means nobody chose.
    General,

    // Entertainment
    Games,
    Movies,
    Music,
    Sports,
    EntertainmentOther,

    // Food and drink
    DiningOut,
    Groceries,
    Liquor,
    FoodOther,

    // Home
    Electronics,
    Furniture,
    HouseholdSupplies,
    Maintenance,
    Mortgage,
    Pets,
    Rent,
    Services,
    HomeOther,

    // Life
    Childcare,
    Clothing,
    Education,
    Gifts,
    Insurance,
    Medical,
    Taxes,
    LifeOther,

    // Transportation
    Bicycle,
    BusTrain,
    Car,
    GasFuel,
    Hotel,
    Parking,
    Plane,
    Taxi,
    TransportationOther,

    // Utilities
    Cleaning,
    Electricity,
    HeatGas,
    Trash,
    TvPhoneInternet,
    Water,
    UtilitiesOther,

    /// <summary>
    /// The category every settlement carries. No expense may take it and the picker never
    /// offers it: the expense routes refuse it with a <c>400</c>, the settlement routes
    /// coerce whatever they are sent to it.
    /// </summary>
    Payment
}
