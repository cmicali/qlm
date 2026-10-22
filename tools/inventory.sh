#!/bin/sh
# Records the adapter and the setup files on this Mac into captures/inventory.
# Run it with the adapter plugged in. It changes nothing on the system.
set -eu

cd "$(dirname "$0")/.."
out=captures/inventory
mkdir -p "$out"

# The adapter: vendor 0x1781 (6017), product 0x0E39 (3641).
vendor=6017

echo "USB plane"
ioreg -p IOUSB -l -w0 > "$out/usb.txt"
if grep -q "\"idVendor\" = $vendor" "$out/usb.txt"; then
    echo "  adapter found"
else
    echo "  adapter not found: is it plugged in?" >&2
fi

echo "HID devices"
ioreg -r -c IOHIDDevice -l -w0 > "$out/hid.txt"
if grep -q "\"VendorID\" = $vendor" "$out/hid.txt"; then
    echo "  adapter's HID device found"
else
    echo "  adapter's HID device not found" >&2
fi
hidutil list > "$out/hidutil.txt"

echo "Setup files"
setups="$HOME/Documents/Genelec/GLM5/Setup Files"
if [ -d "$setups" ]; then
    mkdir -p "$out/setups"
    find "$setups" -name '*.sam' -exec cp {} "$out/setups/" \;
    echo "  $(ls "$out/setups" | wc -l | tr -d ' ') copied from $setups"
else
    echo "  $setups not found: copy your .sam files into $out/setups by hand" >&2
fi

echo "Done. Add each monitor's model, serial, and firmware from GLM to $out/notes.md."
