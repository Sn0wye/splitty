# UI review

Use this when implementing or reviewing a change to something the user sees or
touches. It is a judgement rule, not a test requirement: no UI suite is implied.

## Own the device

Give each verification session its own simulator. A device another session is
driving changes under you, and its taps and state end up in your evidence.
Keep the host to two driven simulators: when `xcrun simctl list devices booted`
already shows two, wait for one to shut down before booting yours.

From the worktree root:

```sh
udid=$(xcrun simctl create "Splitty review <thread or branch>" "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-0)
printf '%s\n' "$udid" > .splitty-sim
xcrun simctl boot "$udid"
xcodebuild build -project Splitty/Splitty.xcodeproj -scheme Splitty \
    -destination "id=$udid" -derivedDataPath /tmp/splitty-review-dd
xcrun simctl install "$udid" /tmp/splitty-review-dd/Build/Products/Debug-iphonesimulator/Splitty.app
```

`.splitty-sim` (git-ignored) makes `scripts/test-focused.sh` test on this
simulator. A test run reinstalls the app there, so reinstall the build under
review and retake screenshots after one.

Then call `device_list`, and `device_open` with `hostId` `local` and the UDID as
`deviceId`. It returns an `agent-device` command bound to this simulator; `$AD`
below stands for that command. Every launch, tap, text entry, screenshot and
recording goes through `$AD`. `simctl` keeps create, boot, install, shutdown,
delete, builds and logs. When `$AD` says it is out of date, call `device_open`
again.

While the session waits on something long, such as a build or a PR review,
shut the simulator down with `xcrun simctl shutdown "$udid"`; the next
`$AD open` boots it again. At the end: `xcrun simctl delete "$udid" && rm .splitty-sim`.

## Reach the state

Debug builds open the review gallery straight from a launch argument, without
signing in or a backend. Pass each argument with its own `--launch-args`:

```sh
$AD open com.snowye.splitty --relaunch --launch-args -SplittyReview                         # the gallery list
$AD open com.snowye.splitty --relaunch --launch-args -SplittyReview --launch-args timeline  # one screen
```

Screen names are the raw values of `ReviewScreen` in
`Splitty/Splitty/Views/OnboardingReviewView.swift`:

| Screen | What it holds |
|---|---|
| `welcome`, `setup`, `create`, `join`, `invite` | First-run flow |
| `groupsEmpty`, `groupEmpty`, `balanceHint` | Empty states |
| `expenseForm` | The real expense sheet: amount digits, keypad, details step with the keyboard, split screens. Saving fails on purpose. |
| `expenseFormReais` | The same expense sheet in a BRL group: `R$` ahead of the amount and a `,` decimal key. |
| `timeline` | Real timeline rows on sample data: every row shape (an installment badge among them), date headers, swipe to delete, the last row's clearance above the tab bar. Reset restores deleted rows. |
| `timelineEuros` | The timeline in a EUR group: amounts written `42,50 €`. |
| `groupOpen` | The real Groups tab pushing the real group screen, over reads that take 1.2s. The first open shows the timeline loader under the seeded header; Back and opening it again shows the cached rows at once while the same read runs. The toolbar's search filters the timeline; its menu pushes Plans on sample installments. |
| `groupOffline` | The same Groups tab and group screen with every read failing, as with no network. The group opens on the copy saved two hours ago, with an expense added offline waiting to send and an edit that met another member's edit of the same field; the banner opens Unsent changes. |
| `charts` | The real Charts sheet; each range lands on different numbers after a short delay. |
| `chartsFailed` | The first load fails; Try again succeeds. |
| `chartsEmpty` | Charts for a group with no expenses. |
| `plans` | The Plans screen's Installments section on sample data: one with an end, one with none, a long name. Loads after a short delay; pull to refresh reloads. |
| `plansEmpty` | Plans for a group with no active recurring expense. |
| `settleUp` | The same sheet opened from the group's Settle up button: Who paid? then To whom?, a grid of faces with what each owes, before the amount. The summary above the amount goes back to Who paid?. |
| `settledUp` | The real Settle up sheet on a $165.00 debt to Ana. Recording it all plays the settled-up moment; a smaller amount dismisses as usual. Nothing is written. |
| `paidToYou` | The same sheet from the other side: Ana owes you $165.00 and the sheet opens on the amount, Ana paid You, with Full amount in place of Pay all. Recording it all plays the settled-up moment. Nothing is written. |
| `avatarCrop` | The real avatar crop screen on a generated landscape photo with a grid: pan, flick and pinch past the bounds. |
| `appearance` | The real Appearance setting. Picking a theme changes and stores the app's theme. |

The same gallery opens from Settings > Development > Review onboarding.
`-SplittyPerformanceScenario` remains the way to load the real app with large
data sets (see `docs/ipad-review.md`).

When a change touches a state the gallery cannot reach, add it there. Use the
component's existing data-source seam (`GroupDataSource`, `ChartsDataSource`,
`ExpenseFormDataSource`) rather than a copy of the component.

The gallery is not the real app: `isReview` turns off autofocus and fetches in
`JoinGroupSheet`, `GroupsView` and `GroupFormSheet`, so confirm a
focus or loading finding in the real app.

## Drive and capture

```sh
$AD snapshot -i                              # accessibility tree with @e refs
$AD press 'id="expense.repeat"' --settle     # or a ref: $AD press @e12 --settle
$AD fill @e5 "Dinner" --settle               # replaces the field's text
$AD gesture pan 380 650 -200 0 500           # drag: x y dx dy durationMs; a partial swipe
$AD swipe 380 650 40 650                     # quick fling from x1 y1 to x2 y2
$AD settings appearance dark                 # light, dark, toggle
$AD settings text-size accessibility-large   # then relaunch the app
$AD screenshot /tmp/review-after.png --pixel-density 3
```

Target controls by accessibility identifier (`id="..."`); find them with
`grep -rn accessibilityIdentifier Splitty/Splitty`, and add one to a control you
need that has none. Refs like `@e12` expire once the screen changes: take a
fresh `snapshot -i` before using one. `$AD screenshot` saves 1x points unless
given `--pixel-density`; `device_screenshot` shows you the screen.
`$AD help <command>` lists flags not shown here.

### Reduce Motion

agent-device has no Reduce Motion setting; flip it in the Settings app:

```sh
$AD open com.apple.Preferences --relaunch
$AD press 'label="Accessibility"' --settle
$AD press 'label="Motion"' --settle
$AD snapshot -i     # press the [switch] "Reduce Motion" until a snapshot shows it [checked]
$AD open com.snowye.splitty --relaunch --launch-args -SplittyReview --launch-args <screen>
```

In one session pressing the switch's ref left it unchecked and pressing its
coordinates checked it. The effect on Splitty is unverified for this route:
check it on a Splitty animation that reads `accessibilityReduceMotion`, since
the system navigation push still slides with Reduce Motion on (iOS 26.5).
Writing the default directly, plus a relaunch, is also unverified: one session
saw the Reduce Motion path after it, another saw no change.

```sh
xcrun simctl spawn "$udid" defaults write com.apple.Accessibility ReduceMotionEnabled -bool true
```

## Record motion

For a changed animation, transition or gesture, record a short clip covering
the change and its return path: open and dismiss, swipe and snap back, switch a
range and switch back.

```sh
$AD record start /tmp/review-after.mp4 --scope device
# drive the interaction
$AD record stop
$AD record contact-sheet /tmp/review-after.mp4 --out /tmp/review-after-sheet.png
```

The contact sheet is one PNG of the sampled frames where the screen changed,
each labelled with its time. A flash between two samples is not in it; watch
the clip for those.

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
  overlap, the tab bar covering the last row, sheet detents and sizing,
  empty states, swipe to delete.
- Attach the evidence to the pull request with `gh`, which uploads the files
  to GitHub and rewrites the references in the body:

  ```sh
  gh pr create --body-file body.md --attach './before.png#Before' --attach ./after.mp4
  gh pr edit <n> --attach './rested-dark.png#Rested row, dark'
  ```

  Write `![alt](./file.png)` in the body for a file passed with `--attach`.
  Do not push images to a `pr-assets/*` branch or a gist: those outlive the
  review and break when cleaned up.
