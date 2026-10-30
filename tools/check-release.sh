#!/bin/sh
# Fails if the Release app holds the debug channel. Run it after `make test`
# and `make build`. It first finds each name in the Debug test bundle, so a
# renamed symbol cannot leave a check that passes on anything.
set -eu

cd "$(dirname "$0")/.."
products=build/DerivedData/Build/Products
debug=$products/Debug/QLMTests.xctest/Contents/MacOS/QLMTests
release=$products/Release/qlm.app/Contents/MacOS

symbols='_QLMInstallDebugChannel _QLMDebugRun _QLMDebugClientMain _VibeInstallDebugCommandChannel _VibeDebugCmd'
strings_='.debug.command quit-glm'

if [ ! -f "$debug" ] || [ ! -f "$release/qlm" ]; then
    echo "check-release: run make test and make build first" >&2
    exit 1
fi

failed=0
for symbol in $symbols; do
    if ! nm "$debug" | grep -q " $symbol\$"; then
        echo "check-release: the Debug tests have no $symbol, so the check is stale" >&2
        exit 1
    fi
    for file in "$release"/*; do
        if nm "$file" 2>/dev/null | grep -q " $symbol\$"; then
            echo "check-release: the Release app's $(basename "$file") has $symbol" >&2
            failed=1
        fi
    done
done
for text in $strings_; do
    if ! strings -a "$debug" | grep -qF -- "$text"; then
        echo "check-release: the Debug tests have no \"$text\", so the check is stale" >&2
        exit 1
    fi
    for file in "$release"/*; do
        if strings -a "$file" | grep -qF -- "$text"; then
            echo "check-release: the Release app's $(basename "$file") has \"$text\"" >&2
            failed=1
        fi
    done
done
if [ "$failed" -ne 0 ]; then
    exit 1
fi
echo "check-release: the Release app has no debug channel"
