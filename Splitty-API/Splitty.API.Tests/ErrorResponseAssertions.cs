using System.Net;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Mvc;
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

    /// A body that fails model binding is rejected by the framework before any controller runs,
    /// so it comes back as a validation problem rather than an <see cref="ErrorResponse"/>.
    public static async Task AssertValidationProblemAsync(HttpResponseMessage response)
    {
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var problem = await response.Content.ReadFromJsonAsync<ValidationProblemDetails>();
        Assert.NotNull(problem);
        Assert.NotEmpty(problem!.Errors);
    }
}
