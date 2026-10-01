using Splitty.Domain.Entities;

namespace Splitty.DTO.Response;

public class LoginResponse
{
    public required string Token { get; set; }
    public required User User { get; set; }
}