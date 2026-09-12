using System.Text.Json;
using System.Text.Json.Serialization;

namespace Splitty.DTO.Json;

/// <summary>
/// A field in a PATCH body that distinguishes "absent" from "explicitly null". Plain
/// nullable properties collapse the two, which makes a partial update unable to express
/// "clear this" without also making every omitted field a clear.
/// </summary>
[JsonConverter(typeof(PatchConverterFactory))]
public readonly struct Patch<T>
{
    private Patch(bool isSet, T? value)
    {
        IsSet = isSet;
        Value = value;
    }

    /// True when the property was present in the JSON body, null or not.
    public bool IsSet { get; }

    public T? Value { get; }

    public static Patch<T> Present(T? value) => new(true, value);
}

public sealed class PatchConverterFactory : JsonConverterFactory
{
    public override bool CanConvert(Type typeToConvert) =>
        typeToConvert.IsGenericType && typeToConvert.GetGenericTypeDefinition() == typeof(Patch<>);

    public override JsonConverter CreateConverter(Type typeToConvert, JsonSerializerOptions options) =>
        (JsonConverter)Activator.CreateInstance(
            typeof(PatchConverter<>).MakeGenericType(typeToConvert.GetGenericArguments()[0]))!;
}

internal sealed class PatchConverter<T> : JsonConverter<Patch<T>>
{
    // Without this, System.Text.Json short-circuits a null token to default(Patch<T>) and
    // an explicit null becomes indistinguishable from an absent property.
    public override bool HandleNull => true;

    public override Patch<T> Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
        reader.TokenType == JsonTokenType.Null
            ? Patch<T>.Present(default)
            : Patch<T>.Present(JsonSerializer.Deserialize<T>(ref reader, options));

    public override void Write(Utf8JsonWriter writer, Patch<T> value, JsonSerializerOptions options)
    {
        if (value.Value is null)
        {
            writer.WriteNullValue();
            return;
        }

        JsonSerializer.Serialize(writer, value.Value, options);
    }
}
