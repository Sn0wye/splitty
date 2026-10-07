using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Splitty.Service;
using Splitty.Service.Interfaces;

namespace Splitty.API.Tests;

/// <summary>
/// Program.cs requires Google and R2 credentials only outside Development, so a local API
/// with neither configured must still serve everything that does not reach those services.
/// </summary>
[Collection(nameof(ApiCollection))]
public sealed class DevelopmentHostTests(ApiFactory factory)
{
    // Every group and expense read resolves avatars, and resolving one never calls R2. The
    // real storage is put back so the host runs on the R2 wiring with no R2 settings.
    [Fact]
    public async Task Reads_that_resolve_avatars_work_without_r2_settings()
    {
        await using var host = factory.WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services => services.AddScoped<IAvatarStorage, R2AvatarStorage>()));
        var user = await ApiClient.Create(host).SignInAsync();
        var client = ApiClient.Create(host, user.Token);
        var groupId = await client.CreateGroupAsync();

        var group = await client.ReadJsonAsync(await client.GetGroupAsync(groupId));

        var member = Assert.Single(group.GetProperty("members").EnumerateArray());
        Assert.StartsWith("https://api.dicebear.com/", member.GetProperty("avatarUrl").GetString());
    }
}
