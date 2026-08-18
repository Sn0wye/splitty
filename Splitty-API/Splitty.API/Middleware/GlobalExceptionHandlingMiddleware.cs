using Splitty.DTO.Response;

namespace Splitty.API.Middleware;

public class GlobalExceptionHandlingMiddleware(RequestDelegate next, IHostEnvironment environment)
{
    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await next(context);
        }
        catch (InvalidOperationException ex)
        {
            await WriteAsync(context, 400, ex.Message, ex);
        }
        catch (KeyNotFoundException ex)
        {
            await WriteAsync(context, 404, ex.Message, ex);
        }
        catch (ArgumentException ex)
        {
            await WriteAsync(context, 400, ex.Message, ex);
        }
        catch (UnauthorizedAccessException ex)
        {
            await WriteAsync(context, 403, ex.Message, ex);
        }
        catch (Exception ex)
        {
            await WriteAsync(context, 500, "An error occurred while processing your request.", ex);
        }
    }

    private async Task WriteAsync(HttpContext context, int statusCode, string message, Exception ex)
    {
        context.Response.StatusCode = statusCode;
        context.Response.ContentType = "application/json";

        await context.Response.WriteAsJsonAsync(new ErrorResponse
        {
            StatusCode = statusCode,
            Message = message,
            // Stack traces leak internals; development only.
            Details = environment.IsDevelopment() ? ex.StackTrace : null
        });
    }
}
