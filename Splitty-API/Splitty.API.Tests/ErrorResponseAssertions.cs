using System.Net;
using System.Net.Http.Json;
using Splitty.DTO.Response;

namespace Splitty.API.Tests;

internal static class ErrorResponseAssertions
{
    public static async Task<ErrorResponse> ReadErrorAsync(HttpResponseMessage response)
    {
        var error = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        Assert.NotNull(error);
        return error!;
    }

    public static async Task AssertErrorAsync(HttpResponseMessage response, HttpStatusCode statusCode)
    {
        Assert.Equal(statusCode, response.StatusCode);
        var error = await ReadErrorAsync(response);
        Assert.Equal((int)statusCode, error.StatusCode);
        Assert.False(string.IsNullOrWhiteSpace(error.Message));
    }
}
