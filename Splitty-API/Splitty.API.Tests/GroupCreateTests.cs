using System.Net;
using System.Net.Http.Json;

namespace Splitty.API.Tests;

[Collection(nameof(ApiCollection))]
public sealed class GroupCreateTests
{
    private readonly ApiFactory _factory;

    public GroupCreateTests(ApiFactory factory)
    {
        _factory = factory;
    }

    public static TheoryData<object> NamelessBodies => new()
    {
        new { description = "no name" },
        new { name = (string?)null },
        new { name = "" },
        new { name = "   " },
    };

    [Theory]
    [MemberData(nameof(NamelessBodies))]
    public async Task Create_rejects_a_group_without_a_name(object body)
    {
        var client = ApiClient.Create(_factory);
        var user = await client.SignInAsync();
        client = ApiClient.Create(_factory, user.Token);

        var response = await client.Http.PostAsJsonAsync("/group", body);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }
}
