using Splitty.Domain.Entities;

namespace Splitty.DTO.Response;

public class LoginResponse
{
    public string Token { get; set; } = string.Empty;
    public User User { get; set; } = null!;
}