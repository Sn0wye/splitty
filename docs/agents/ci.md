# PR tests

`.github/workflows/pr-tests.yml` runs on pull requests only.

- API changes run `Splitty.API.Tests` on Ubuntu with .NET 9. Testcontainers
  starts PostgreSQL; the workflow does not start a second database service.
- iOS changes build the app and run `SplittyTests` on one installed iPhone
  simulator. The shared `SplittyUnitTests` scheme excludes `SplittyUITests`
  from both build and test actions.
- Changes to the workflow run both jobs. Markdown-only changes skip both;
  changes confined to `SplittyUITests` skip the iOS job.
- A new commit cancels the previous run for the same PR.

Configure **PR tests** as the required status check in the GitHub branch rules.
This final job verifies that each affected component passed and each unaffected
component was skipped. Keep the workflow trigger unfiltered so the required
check completes even when both test jobs are skipped.

NuGet packages and Swift package sources are cached. Each job builds once;
build outputs are not cached. There is no coverage collection, device matrix,
UI testing, scheduled execution, or automatic test retry.

API results are saved as TRX artifacts for seven days. Failed iOS runs save the
`.xcresult` bundle and build/test log for seven days; successful runs keep the
console log in Actions.

The iOS runner is `xcode-27`, which currently has preview status. The workflow
selects Xcode using `.xcode-version` and fails if that version is unavailable.
When changing the pinned major version, update the runner label too. Cache
keys include the installed Xcode build so different toolchains do not share
package caches.

Measure runner queue time, dependency restoration, build, and test execution
separately before adding build caches or splitting test jobs. iOS tests use
one runner without test parallelization because some existing tests mutate
process-wide language preferences.
