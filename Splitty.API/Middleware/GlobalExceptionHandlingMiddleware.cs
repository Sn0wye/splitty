using Splitty.DTO.Response;

namespace Splitty.API.Middleware;

public class GlobalExceptionHandlingMiddleware(RequestDelegate next)
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
        catch (ArgumentException ex)
        {
            context.Response.StatusCode = 400;
            context.Response.ContentType = "application/json";
            var result = new ErrorResponse
            {
                StatusCode = 404,
                Message = ex.Message,
                Details = ex.StackTrace
            };
            await context.Response.WriteAsJsonAsync(result);
        }
        catch (UnauthorizedAccessException ex)
        {
            context.Response.StatusCode = 403;
            context.Response.ContentType = "application/json";
            var result = new ErrorResponse
            {
                StatusCode = 403,
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
