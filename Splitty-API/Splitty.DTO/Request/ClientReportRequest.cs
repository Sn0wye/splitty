using System.ComponentModel.DataAnnotations;

namespace Splitty.DTO.Request;

/// <summary>
/// A crash, hang or non-fatal error the iOS app saw. The API logs it and stores nothing, so it
/// reaches Seq without a Seq key ever shipping in the app.
/// </summary>
public class ClientReportRequest
{
    public required ClientReportKind Kind { get; set; }

    [Required, MaxLength(32)]
    public required string AppVersion { get; set; }

    [Required, MaxLength(32)]
    public required string Build { get; set; }

    [Required, MaxLength(32)]
    public required string OsVersion { get; set; }

    [Required, MaxLength(64)]
    public required string DeviceModel { get; set; }

    /// <summary>One line for people: the exception type, or the failing request and status.</summary>
    [Required, MaxLength(512)]
    public required string Message { get; set; }

    /// <summary>The detail behind the message, such as a MetricKit diagnostic's JSON.</summary>
    [MaxLength(60_000)]
    public string? Payload { get; set; }
}

public enum ClientReportKind
{
    Crash,
    Hang,
    Error
}
