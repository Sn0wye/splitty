using Splitty.DTO.Response;

namespace Splitty.API.Middleware;

public class GlobalExceptionHandlingMiddleware(RequestDelegate next, IWebHostEnvironment env)
{
    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await next(context);
        }
        catch (InvalidOperationException ex)
        {
            context.Response.StatusCode = 400;
            context.Response.ContentType = "application/json";
            var result = new ErrorResponse
            {
                StatusCode = 400,
                Message = ex.Message,
                Details = ex.StackTrace
            };
            await context.Response.WriteAsJsonAsync(result);
        }
        catch (Exception ex)
        {
            context.Response.StatusCode = 500;
            context.Response.ContentType = "application/json";
            var result = new ErrorResponse
            {
                StatusCode = 500,
                Message = "An error occurred while processing your request.",
                Details = ex.StackTrace
            };
            await context.Response.WriteAsJsonAsync(result);
        }
    }
}
