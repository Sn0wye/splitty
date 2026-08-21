using System.ComponentModel.DataAnnotations;

namespace Splitty.DTO.Request;

public class DevLoginRequest
{
    [Required(ErrorMessage = "Email is required.")]
    [EmailAddress(ErrorMessage = "Invalid email format.")]
    public string Email { get; set; }
}
