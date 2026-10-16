using System.Security.Claims;
using Splitty.DTO.Response;

namespace Splitty.API.Middleware;

public class GlobalExceptionHandlingMiddleware(
    RequestDelegate next,
    IHostEnvironment environment,
    ILogger<GlobalExceptionHandlingMiddleware> logger)
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
            // The mapped exceptions above are refusals the service meant to make; only this one
            // is a fault, so only this one is logged.
            logger.LogError(ex, "Unhandled exception on {Method} {Path} for user {UserId} ({TraceId})",
                context.Request.Method,
                context.Request.Path.Value,
                context.User.FindFirstValue(ClaimTypes.NameIdentifier),
                context.TraceIdentifier);

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
            Details = environment.IsDevelopment() ? ex.StackTrace : null,
            TraceId = context.TraceIdentifier
        });
    }
}
