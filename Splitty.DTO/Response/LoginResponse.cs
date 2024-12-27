using Splitty.Domain.Entities;

namespace Splitty.DTO.Response;

public class LoginResponse
{
    public string Token { get; set; }
    public User User { get; set; }
}