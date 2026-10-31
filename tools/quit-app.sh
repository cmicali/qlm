#!/bin/sh
# Asks the app running from a bundle path to quit, and waits until it has.
# It never kills the app. If the app still runs after the wait, as when it
# asks the user first and the user cancels, the script fails.
#
#   tools/quit-app.sh /Applications/qlm.app
#
# QUIT_WAIT sets the wait in seconds. It is 30 by default.

set -eu

app=${1:?usage: tools/quit-app.sh APP}
wait=${QUIT_WAIT:-30}

[ -d "$app" ] || exit 0

# The quit is the Apple Event the Dock sends. Only the copy running from
# this path is asked, so a build running from elsewhere keeps running.
pids=$(osascript -l JavaScript - "$app" <<'EOF'
ObjC.import("AppKit");
function run(argv) {
    const path = (url) => url.URLByResolvingSymlinksInPath.path.js;
    const target = path($.NSURL.fileURLWithPath(argv[0]));
    const asked = [];
    for (const app of $.NSWorkspace.sharedWorkspace.runningApplications.js) {
        if (!app.bundleURL.isNil() && path(app.bundleURL) === target && app.terminate) {
            asked.push(app.processIdentifier);
        }
    }
    return asked.join(" ");
}
EOF
)

[ -n "$pids" ] || exit 0

name=$(basename "$app" .app)
echo "Asked $name to quit. Waiting up to $wait s."
ticks=0
# ps -p succeeds while any pid in the list still runs.
while ps -p "$pids" >/dev/null 2>&1; do
    if [ "$ticks" -ge $((wait * 10)) ]; then
        echo "$name is still running. If it asks before it quits, answer it, or quit it from its menu. Then try again." >&2
        exit 1
    fi
    sleep 0.1
    ticks=$((ticks + 1))
done
echo "$name quit."
