# UI review

Use this when implementing or reviewing a change to something the user sees or
touches. It is a judgement rule, not a test requirement: no UI suite is implied.

## Own the device

Give each verification session its own simulator. A device another session is
driving changes under you, and its taps and state end up in your evidence.

```sh
udid=$(xcrun simctl create "Splitty review <thread or branch>" "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-0)
xcrun simctl boot "$udid"
xcodebuild build -project Splitty/Splitty.xcodeproj -scheme Splitty \
    -destination "id=$udid" -derivedDataPath /tmp/splitty-review-dd
xcrun simctl install "$udid" /tmp/splitty-review-dd/Build/Products/Debug-iphonesimulator/Splitty.app
```

Delete it when the session is done: `xcrun simctl delete "$udid"`.

## Reach the state

Debug builds open the review gallery straight from a launch argument, without
signing in or a backend:

```sh
xcrun simctl launch "$udid" com.snowye.splitty -SplittyReview            # the gallery list
xcrun simctl launch "$udid" com.snowye.splitty -SplittyReview timeline   # one screen
```

Screen names are the raw values of `ReviewScreen` in
`Splitty/Splitty/Views/OnboardingReviewView.swift`:

| Screen | What it holds |
|---|---|
| `welcome`, `setup`, `create`, `join`, `invite` | First-run flow |
| `groupsEmpty`, `groupEmpty`, `peopleEmpty`, `balanceHint` | Empty states |
| `expenseForm` | The real expense sheet: amount digits, keypad, details step with the keyboard, split screens. Saving fails on purpose. |
| `timeline` | Real timeline rows on sample data: every row shape, date headers, swipe to delete, the last row's clearance above the add button. Reset restores deleted rows. |
| `charts` | The real Charts sheet; each range lands on different numbers after a short delay. |
| `chartsFailed` | The first load fails; Try again succeeds. |
| `chartsEmpty` | Charts for a group with no expenses. |

The same gallery opens from Settings > Development > Review onboarding.
`-SplittyPerformanceScenario` remains the way to load the real app with large
data sets (see `docs/ipad-review.md`).

When a change touches a state the gallery cannot reach, add it there. Use the
component's existing data-source seam (`GroupDataSource`, `ChartsDataSource`,
`ExpenseFormDataSource`) rather than a copy of the component.

## Record motion

For a changed animation, transition or gesture, record a short clip covering
the change and its return path: open and dismiss, swipe and snap back, switch a
range and switch back.

```sh
xcrun simctl io "$udid" recordVideo --codec=h264 --force /tmp/review.mov &
recorder=$!
# drive the interaction
kill -INT "$recorder"
```

A screenshot cannot show a regression in motion. The odometer revert of #103
and #104 is the example.

## Report

- Compare against the component as it was before the change, not only against
  the description of the change. Name anything that differs and was not asked
  for: styling, spacing, a transition that disappeared.
- List the states you saw running and the states you did not, such as below
  the fold, dark mode, Reduce Motion, larger text, iPad, or the keyboard up.
  Unseen states are open risks; say so rather than implying coverage.
- Check the recurring trouble spots when the change is near them: keyboard
  overlap, the add button covering the last row, sheet detents and sizing,
  empty states, swipe to delete.
