# PR tests

One workflow runs on pull requests:

- `.github/workflows/api-tests.yml` runs `Splitty.API.Tests` on Ubuntu with
  .NET 9 when `Splitty-API/**` or backend build configuration changes.
  Testcontainers starts PostgreSQL; `ApiFactory` supplies the test-only
  configuration, so the workflow sets no secrets.

It also runs when its own workflow file changes. Markdown-only changes do not
trigger it. A new commit cancels older runs for that PR.

CI does not build or test the iOS app. Run `SplittyTests` locally with the
pinned Xcode (see `xcode-metadata.md`) using the shared `SplittyUnitTests`
scheme, which excludes `SplittyUITests` from both building and testing.

NuGet packages are cached and the job builds once. There is no coverage
collection, scheduled execution, or automatic test retry.

API results are retained as TRX artifacts for seven days. The test step times
out before its job does, so a hung run still counts as a failure and uploads
its results.

GitHub leaves required checks pending when their workflow is skipped by a
path filter. Do not require the API check unconditionally in branch rules
unless you also change that trigger behavior.
