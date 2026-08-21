using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.Extensions.Configuration;
using Microsoft.IdentityModel.Tokens;
using Splitty.Domain.Entities;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

public class JwtTokenIssuer(IConfiguration configuration) : IJwtTokenIssuer
{
    private const int DefaultExpiryDays = 30;

    public string Issue(User user)
    {
        var secretKey = configuration["Jwt:SecretKey"];
        var issuer = configuration["Jwt:Issuer"];
        var expiryDays = configuration.GetValue<int?>("Jwt:ExpiryDays") ?? DefaultExpiryDays;

        var securityKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(secretKey));
        var credentials = new SigningCredentials(securityKey, SecurityAlgorithms.HmacSha256);

        var claims = new[]
        {
            new Claim(ClaimTypes.NameIdentifier, user.Id.ToString()),
            new Claim(ClaimTypes.Name, user.Name),
            new Claim(ClaimTypes.Email, user.Email),
            new Claim(JwtRegisteredClaimNames.Sub, user.Email),
        };

        var token = new JwtSecurityToken(
            issuer: issuer,
            claims: claims,
            // UtcNow, not Now: JwtSecurityToken reads `expires` as UTC, so a local
            // timestamp shifts the lifetime by the host's offset — west of UTC that
            // ships already-expired tokens.
            expires: DateTime.UtcNow.AddDays(expiryDays),
            signingCredentials: credentials
        );

        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}
