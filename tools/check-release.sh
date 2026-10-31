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

# The start of every symbol the channel defines: qlm's, then the pieces'
# functions, and their option classes.
prefixes='_QLMDebug _VibeDebug _VibeInstallDebug _VibeWriteDebug _OBJC_CLASS_$_VibeDebug'
# A string from each part: main.m's flag, the wire, qlm's client, qlm's
# verbs, and the standard verbs.
texts='--debug-cmd .debug.command QLM_DEBUG_TIMEOUT quit_answering dump_view_tree'

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Every Mach-O file in the bundle. A Debug build keeps its code in
# qlm.debug.dylib, beside a stub.
dump() {
    : > "$work/$2.symbols"
    : > "$work/$2.strings"
    find "$1/Contents" -type f | while IFS= read -r file; do
        if file -b "$file" | grep -q Mach-O; then
            nm -j "$file" >> "$work/$2.symbols" 2>/dev/null || true
            strings -a "$file" >> "$work/$2.strings"
        fi
    done
}

# The symbols in a dump that start with a prefix.
starting() {
    awk -v prefix="$2" 'index($0, prefix) == 1' "$work/$1.symbols"
}

for app in "$debug" "$release"; do
    if [ ! -d "$app/Contents" ]; then
        echo "check-release: no app at $app" >&2
        exit 1
    fi
done
dump "$debug" debug
dump "$release" release

failed=0
for prefix in $prefixes; do
    if [ -z "$(starting debug "$prefix")" ]; then
        echo "check-release: the Debug app has no symbol starting $prefix, so the check is stale" >&2
        exit 1
    fi
    found=$(starting release "$prefix" | sort -u | head -5)
    if [ -n "$found" ]; then
        echo "check-release: the Release app has symbols starting $prefix:" $found >&2
        failed=1
    fi
done
for text in $texts; do
    if ! grep -qF -- "$text" "$work/debug.strings"; then
        echo "check-release: the Debug app has no \"$text\", so the check is stale" >&2
        exit 1
    fi
    if grep -qF -- "$text" "$work/release.strings"; then
        echo "check-release: the Release app has \"$text\"" >&2
        failed=1
    fi
done
if [ "$failed" -ne 0 ]; then
    exit 1
fi
echo "check-release: the Release app has no debug channel"
