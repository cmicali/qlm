#!/bin/sh
# Fails if the Release app holds any of the debug channel: qlm's own verbs, or
# vibe-libs' dev/DebugChannel and dev/DebugVerbs. Each name is first found in
# the Debug app, so a renamed one fails here instead of passing on anything.
#
#   tools/check-release.sh DEBUG_APP RELEASE_APP
#
# `make check-release` builds both apps and runs it.

set -euf

usage='usage: tools/check-release.sh DEBUG_APP RELEASE_APP'
debug=${1:?$usage}
release=${2:?$usage}

# Symbols: qlm's channel, then the pieces' functions and option classes.
# Strings: main.m's flag, the wire, qlm's client, qlm's verbs, and the
# standard verbs.
names='_QLMDebug _VibeDebug _VibeInstallDebug _VibeWriteDebug
       --debug-cmd .debug.command QLM_DEBUG_TIMEOUT quit_answering dump_view_tree'

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The symbols and strings of every Mach-O file in the bundle. A Debug build
# keeps its code in qlm.debug.dylib, beside a stub.
dump() {
    if [ ! -d "$1/Contents" ]; then
        echo "check-release: no app at $1" >&2
        exit 1
    fi
    find "$1/Contents" -type f | while IFS= read -r file; do
        if file -b "$file" | grep -q Mach-O; then
            nm -j "$file" 2>/dev/null || true
            strings -a "$file"
        fi
    done > "$work/$2"
}

dump "$debug" debug
dump "$release" release

failed=0
for name in $names; do
    if ! grep -qF -- "$name" "$work/debug"; then
        echo "check-release: the Debug app has no $name, so the check is stale" >&2
        exit 1
    fi
    found=$(grep -F -- "$name" "$work/release" | sort -u | head -5)
    if [ -n "$found" ]; then
        echo "check-release: the Release app has $name:" $found >&2
        failed=1
    fi
done
if [ "$failed" -ne 0 ]; then
    exit 1
fi
echo "check-release: the Release app has no debug channel"
