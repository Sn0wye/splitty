using System.ComponentModel.DataAnnotations;
using System.Runtime.InteropServices;

namespace Splitty.DTO.Request;

public class RegisterRequest
{
    [Required(ErrorMessage = "Name is required.")]
    public string Name { get; set; }
    
    [Required(ErrorMessage = "Email is required.")]
    [EmailAddress(ErrorMessage = "Invalid email format.")]
    public string Email { get; set; }
    
    [Required(ErrorMessage = "Password is required.")]
    [MinLength(6, ErrorMessage = "Password must be at least 6 characters.")]
    [MaxLength(20, ErrorMessage = "Password must be at most 20 characters.")]
    public string Password { get; set; }
    
    [MaxLength(255, ErrorMessage = "Avatar URL must be at most 255 characters.")]
    public string AvatarUrl { get; set; } = string.Empty;
}