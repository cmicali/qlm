#!/bin/sh
# Relays the GLM adapter from this Pi's USB-A port to its USB-C port.
# Installed as /usr/local/bin/qlm-proxy. systemd runs it, and restarts it
# when usb-proxy exits on an unplug.
set -eu

modprobe dwc2
modprobe raw_gadget

udc=$(ls /sys/class/udc 2> /dev/null | head -n 1)
if [ -z "$udc" ]; then
    echo "No USB device controller in /sys/class/udc. The dwc2 overlay is missing, or a reboot is pending." >&2
    exit 1
fi

# The adapter: vendor 0x1781, product 0x0E39.
present() {
    for device in /sys/bus/usb/devices/*; do
        if [ "$(cat "$device/idVendor" 2> /dev/null)" = 1781 ] &&
            [ "$(cat "$device/idProduct" 2> /dev/null)" = 0e39 ]; then
            return 0
        fi
    done
    return 1
}

if ! present; then
    echo "Waiting for the adapter on the USB-A port"
    while ! present; do
        sleep 1
    done
fi
echo "Relaying the adapter through $udc"
exec /usr/local/bin/usb-proxy --device="$udc" --driver="$udc" --vendor_id=1781 --product_id=0e39
