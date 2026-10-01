# PR tests

Two independent workflows run on pull requests:

- `.github/workflows/api-tests.yml` runs `Splitty.API.Tests` on Ubuntu with
  .NET 9 when `Splitty-API/**` or backend build configuration changes.
  Testcontainers starts PostgreSQL. The test command receives the factory's
  public test-only JWT key so startup validation succeeds before the factory
  adds its configuration.
- `.github/workflows/ios-tests.yml` builds the app and runs `SplittyTests` on
  one iPhone simulator when `Splitty/**` or `.xcode-version` changes.
  The shared `SplittyUnitTests` scheme excludes `SplittyUITests` from both
  building and testing.

Each workflow also runs when its own workflow file changes. Markdown-only
changes trigger neither workflow; iOS UI-test-only changes skip the iOS
workflow. If both components change, both workflows run independently.
A new commit cancels older runs of the same workflow for that PR.

NuGet packages and Swift package sources are cached. Each job builds once.
There is no coverage collection, device matrix, UI testing, scheduled
execution, or automatic test retry.

API results are retained as TRX artifacts for seven days. Failed iOS runs
retain the `.xcresult` bundle and test log for seven days. Successful iOS
runs keep their console log in Actions.

GitHub leaves required checks pending when their workflow is skipped by a
path filter. Do not require both checks unconditionally in branch rules
unless you also change that trigger behavior. There is no aggregate check.

The iOS runner is `xcode-27`, currently a hosted preview image. The workflow
selects Xcode using `.xcode-version` and fails if that version is unavailable.
Update the runner label when changing the pinned major version. Package
cache keys include the installed Xcode build.
