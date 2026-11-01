using System.Text.Json.Serialization;

namespace Splitty.Domain.Entities;

/// <summary>
/// The currency every amount in a group is in, from a closed list of currencies with two
/// decimal places. Stored as the member name; sent as the uppercase ISO 4217 code, which the
/// member names are. See docs/adr/0007-a-group-has-one-currency.md.
///
/// Values are append-only by name. Renaming a member is a data migration.
///
/// The converter is on the type as well as in the API's options, so any serializer reads the
/// code as a string, not only the API's.
/// </summary>
[JsonConverter(typeof(JsonStringEnumConverter<Currency>))]
public enum Currency
{
    [JsonStringEnumMemberName("USD")] USD,
    [JsonStringEnumMemberName("CAD")] CAD,
    [JsonStringEnumMemberName("AUD")] AUD,
    [JsonStringEnumMemberName("MXN")] MXN,
    [JsonStringEnumMemberName("GBP")] GBP,
    [JsonStringEnumMemberName("BRL")] BRL,
    [JsonStringEnumMemberName("EUR")] EUR,
    [JsonStringEnumMemberName("CHF")] CHF,
}
