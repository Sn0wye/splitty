using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.Extensions.Configuration;
using Microsoft.IdentityModel.Tokens;
using Splitty.Domain.Entities;
using Splitty.Infrastructure.Interfaces;
using Splitty.Repository.Interfaces;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

public class AuthService(
    IConfiguration configuration,
    IUserRepository userRepository,
    IPasswordHasher passwordHasher
) : IAuthService
{
    public async Task<(User user, string token)> Register(string name, string email, string password, string avatarUrl)
    {
        var existingUser = await userRepository.GetByEmailAsync(email);

        if (existingUser  is not null)
        {
            throw new InvalidOperationException("User with this email already exists.");
        }
        
        var user = new User
        {
            Name = name,
            Email = email,
            AvatarUrl = avatarUrl
        };

        user.Password = passwordHasher.HashPassword(password);

        await userRepository.CreateAsync(user);

        var token = GenerateJwtToken(user);

        return (user, token);
    }


    public async Task<(User user, string token)> Login(string email, string password)
    {
        // Retrieve user by email
        var user = await userRepository.GetByEmailAsync(email);

        // If user is not found, return null or throw an exception
        if (user == null)
        {
            throw new InvalidOperationException("Invalid email or password.");
        }

        // Verify the password
        var result = passwordHasher.VerifyHashedPassword(user.Password, password);

        // If the password does not match, throw an exception
        if (result is false)
        {
            throw new InvalidOperationException("Invalid email or password.");
        }

        // Generate JWT Token
        var token = GenerateJwtToken(user);

        // Return the user and token
        return (user, token);
    }
    
    private string GenerateJwtToken(User user)
    {
        var secretKey = configuration["Jwt:SecretKey"];
        var issuer = configuration["Jwt:Issuer"];

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
            expires: DateTime.Now.AddDays(7),
            signingCredentials: credentials
        );

        return new JwtSecurityTokenHandler().WriteToken(token);
    }
    
    public async Task<User?> GetProfile(int userId)
    {
        return await userRepository.GetByIdAsync(userId);
    }
}