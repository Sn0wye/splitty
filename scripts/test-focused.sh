#!/usr/bin/env bash
# Runs a focused set of Splitty tests and judges the run by its result bundle, not by
# xcodebuild's exit code alone: a run that executed no tests fails, and every skipped
# test is listed with its reason.
#
#   scripts/test-focused.sh SplittyTests/InviteShareTextTests [SplittyTests/Suite/test()] ...
#
# Identifiers are what -only-testing takes. Unit tests run through the SplittyUnitTests
# scheme. Naming a SplittyUITests identifier switches to the Splitty scheme; UI tests
# still need the user's approval first (see AGENTS.md).
#
# SPLITTY_DESTINATION overrides the simulator. The result bundle and full build log are
# kept in a temporary directory whose path is printed at the end.

set -euo pipefail

usage() {
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' >&2
}

if [[ $# -eq 0 ]]; then
    usage
    exit 64
fi

cd "$(dirname "$0")/.."

scheme=SplittyUnitTests
only=()
for id in "$@"; do
    case "$id" in
        SplittyTests/?*) ;;
        SplittyUITests/?*) scheme=Splitty ;;
        *)
            echo "error: '$id' is not a SplittyTests/... or SplittyUITests/... identifier" >&2
            exit 64
            ;;
    esac
    only+=("-only-testing:$id")
done

destination="${SPLITTY_DESTINATION:-platform=iOS Simulator,name=iPhone 17}"
work="$(mktemp -d "${TMPDIR:-/tmp}/splitty-focused.XXXXXX")"
bundle="$work/Focused.xcresult"
log="$work/xcodebuild.log"

echo "Running ${#only[@]} identifier(s) with $scheme on '$destination'"

status=0
xcodebuild test \
    -project Splitty/Splitty.xcodeproj \
    -scheme "$scheme" \
    -destination "$destination" \
    -resultBundlePath "$bundle" \
    "${only[@]}" >"$log" 2>&1 || status=$?

if [[ ! -d "$bundle" ]]; then
    grep -E "error:|\*\* .* FAILED \*\*" "$log" | head -40 >&2 || tail -40 "$log" >&2
    echo "FAILED: xcodebuild exited $status without a result bundle. Log: $log" >&2
    exit 1
fi

summary="$(xcrun xcresulttool get test-results summary --path "$bundle" --compact)"
count() { jq -r ".$1 // 0" <<<"$summary"; }
passed="$(count passedTests)"
failed="$(count failedTests)"
skipped="$(count skippedTests)"
expected="$(count expectedFailures)"
executed=$((passed + failed + expected))

echo "$passed passed, $failed failed, $skipped skipped, $expected expected failures"

if ((skipped > 0)); then
    echo "Skipped:"
    xcrun xcresulttool get test-results tests --path "$bundle" --compact | jq -r '
        .. | objects
        | select(.nodeType == "Test Case" and .result == "Skipped")
        | "  \(.nodeIdentifier // .name): \(
            [.children[]? | select(.nodeType == "Skip Message") | .name] | first // "no reason given"
          )"'
fi

if ((failed > 0)); then
    echo "Failures:"
    jq -r '.testFailures[]? | "  \(.testIdentifierString): \(.failureText)"' <<<"$summary"
fi

echo "Result bundle: $bundle"
echo "Build log: $log"

if ((executed == 0)); then
    echo "FAILED: no test executed. Check the identifiers, and whether every selected test was skipped." >&2
    exit 1
fi
if ((failed > 0 || status != 0)); then
    echo "FAILED: xcodebuild exited $status." >&2
    exit 1
fi
echo "PASSED: $executed executed."
