#!/bin/sh
# Records the adapter's USB traffic for one scenario, with usbmon.
# Run it on the Pi with sudo, after qlm-proxy is running: sudo ./capture.sh <scenario>
# Ctrl-C stops it.
set -eu

if [ $# -ne 1 ]; then
    echo "usage: sudo $0 <scenario>" >&2
    exit 2
fi
scenario=$1
case "$scenario" in
    *[!A-Za-z0-9._-]* | "" | .*)
        echo "A scenario name takes letters, digits, '.', '_', and '-'." >&2
        exit 2
        ;;
esac
if [ "$(id -u)" -ne 0 ]; then
    echo "Run this with sudo." >&2
    exit 1
fi

# TRAP: the bus number is the port's. Replug the adapter into the same port,
# or a running capture records the wrong bus.
bus=
for device in /sys/bus/usb/devices/*; do
    if [ "$(cat "$device/idVendor" 2> /dev/null)" = 1781 ] &&
        [ "$(cat "$device/idProduct" 2> /dev/null)" = 0e39 ]; then
        bus=$(cat "$device/busnum")
        devnum=$(cat "$device/devnum")
        break
    fi
done
if [ -z "$bus" ]; then
    echo "The adapter (1781:0e39) is not plugged into this Pi." >&2
    exit 1
fi
modprobe usbmon 2> /dev/null || true
if ! dumpcap -D 2> /dev/null | grep -q "usbmon$bus\$"; then
    echo "dumpcap cannot see usbmon$bus. Is usbmon in this kernel?" >&2
    exit 1
fi

user=${SUDO_USER:-root}
home=$(getent passwd "$user" | cut -d: -f6)
dir="$home/captures/$scenario"
file="$dir/capture.pcapng"
if [ -e "$file" ] || [ -e "$file.xz" ]; then
    echo "$dir already holds a capture. Move it away first." >&2
    exit 1
fi
mkdir -p "$dir"

echo "Recording usbmon$bus to $file. The adapter is device $bus:$devnum."
echo "Started at $(date '+%Y-%m-%d %H:%M:%S %Z'). Press Ctrl-C to stop."
# Ctrl-C stops dumpcap, which then exits 0. This trap keeps the script alive
# to compress the file and fix ownership.
# TRAP: dumpcap as root drops every capability but capture, so it cannot
# enter a 0700 home. This shell opens the file instead.
trap ':' INT
status=0
dumpcap -q -i "usbmon$bus" -w - > "$file" || status=$?
trap - INT
if [ "$status" -eq 0 ]; then
    # The repository stores captures xz-compressed.
    xz -9 "$file"
fi
chown -R "$user:" "$home/captures"
if [ "$status" -ne 0 ]; then
    echo "dumpcap failed with status $status. $file is incomplete." >&2
    exit 1
fi
echo "Stopped at $(date '+%Y-%m-%d %H:%M:%S %Z')."
echo "On the Mac, from the repository:"
echo "  scp -r $user@$(hostname).local:captures/$scenario captures/"
echo "  python3 -I tools/pcapng-to-reports.py --device $bus:$devnum captures/$scenario/capture.pcapng.xz > captures/$scenario/reports.txt"
