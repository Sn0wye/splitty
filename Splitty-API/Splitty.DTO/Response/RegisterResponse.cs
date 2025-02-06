using Splitty.Domain.Entities;

namespace Splitty.DTO.Response;

public class RegisterResponse
{
    public string Token { get; set; }
    public User User { get; set; }
}