# iPad layout review

iPad remains enabled by `TARGETED_DEVICE_FAMILY = 1,2` in
`Splitty/Config/App.xcconfig`. The Info.plist permits all four iPad orientations.

Wide windows center group cards, the expense timeline, People content, and
Settings within 760 points. Tab controls use at most 600 points; login and
onboarding use at most 560. These are maximum widths, so narrower windows can
still use their available width. Backgrounds and the tab bar border fill the
window.

## Simulator check, October 4, 2026

Built with pinned Xcode 27.0 and reviewed on an iPad Pro 13-inch M5 simulator
running iOS 27.0. The existing `-SplittyPerformanceScenario` launch argument
provides 100 groups, a 500-expense timeline, and a 50-member split without a
backend.

- Groups and timeline: checked centered content and bottom navigation in
  portrait and landscape.
- Expense entry in landscape: entered an amount, advanced to details, opened
  split configuration and the graphical date picker. Keypad, Next, Save, Done,
  and date confirmation remained visible.
- Settings: checked the narrowed layout in portrait dark mode.
- Login and onboarding: checked dark portrait layout, continued from the
  walkthrough to the create/join choices.
- Simulator build, `git diff --check`, and string catalog formatting check passed.

This was a layout review with sample data. Live Google authentication, backend
writes, the full software keyboard, smaller iPads, resizable multitasking windows,
and accessibility text sizes were not verified. No unit or UI suites were run.

## Repeat the review

Build the Splitty scheme for an iPad simulator, install the app, and launch with
`-SplittyPerformanceScenario`. Open a group and use the central plus button to
review expense entry. Settings > Development > Review onboarding opens the
local first-run gallery. Launch without the argument to review the login screen.

For App Store captures, use a release build or otherwise exclude development
controls, and prepare representative screenshot content instead of the large
performance dataset. The simulator review captures are verification evidence,
not a finished store screenshot set.
