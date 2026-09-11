# Agent instructions

## Swift verification policy

- Treat code-review tasks as static inspection. Do not run `xcodebuild`, execute tests, or launch a simulator during a review unless the user explicitly requests runtime verification.
- During implementation, run only the tests directly related to the changed feature.
- Do not run the complete `SplittyTests` suite or any `SplittyUITests` without explicit user approval.
- Reserve full unit and UI test-suite runs for CI, release validation, or an explicit user request.
- Report runtime concerns that cannot be verified statically instead of automatically expanding the test scope.
