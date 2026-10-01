namespace Splitty.API;

/// The test suite runs the host as `Testing` so it can be told apart from a developer's
/// `Development` run. Anything Development unlocks (the dev login, OpenAPI, stack traces,
/// skipping the Google and R2 credential checks) applies to Testing too.
public static class HostEnvironments
{
    public const string Testing = "Testing";

    /// Signs the test suite's tokens. Public by necessity, so the host refuses it in every
    /// environment except Testing: a deployment that copied it would mint forgeable tokens.
    public const string TestJwtSecretKey = "SplittyTestSigningKeyLongEnoughForHmacSha256";

    public static bool IsTesting(this IHostEnvironment environment) =>
        environment.IsEnvironment(Testing);

    public static bool IsDevelopmentOrTesting(this IHostEnvironment environment) =>
        environment.IsDevelopment() || environment.IsTesting();
}
