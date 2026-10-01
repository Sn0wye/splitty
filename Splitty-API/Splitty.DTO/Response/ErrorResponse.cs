namespace Splitty.DTO.Response;

public class ErrorResponse
{
    public int StatusCode { get; set; }
    public required string Message { get; set; }
    public string? Details { get; set; }
}