# Agent instructions

## Swift verification policy

- Treat code-review tasks as static inspection. Do not run `xcodebuild`, execute tests, or launch a simulator during a review unless the user explicitly requests runtime verification.
- During implementation, run only the tests directly related to the changed feature, through `scripts/test-focused.sh <SplittyTests/Suite>...`. It fails a run that executed nothing and lists skipped tests; report both.
- Tests that assert copy or formatted dates pin the language with `@Suite(.appLanguage(.english))` or `AppLanguage.$pinned.withValue`. Never write the language to `UserDefaults.standard` in a test.
- Do not run the complete `SplittyTests` suite or any `SplittyUITests` without explicit user approval.
- Reserve full unit and UI test-suite runs for release validation or an explicit user request. CI does not build or test the iOS app.
- Report runtime concerns that cannot be verified statically instead of automatically expanding the test scope.

## Agent skills

### Issue tracker

Issues live as GitHub issues in `Sn0wye/splitty`, managed via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Canonical five-role vocabulary, label strings unchanged. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: root `CONTEXT.md` plus `docs/adr/`. See `docs/agents/domain.md`.

### UI review

For changes to what users see or touch, use your own simulator, the `-SplittyReview` gallery states, and motion recordings. See `docs/agents/ui-review.md`.

### Xcode metadata

Use the pinned Xcode version and canonicalize string catalogs before committing. See `docs/agents/xcode-metadata.md`.
