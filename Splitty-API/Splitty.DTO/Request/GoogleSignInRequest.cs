using System.ComponentModel.DataAnnotations;

namespace Splitty.DTO.Request;

public class GoogleSignInRequest
{
    [Required(ErrorMessage = "Authorization code is required.")]
    public string AuthCode { get; set; }
}
