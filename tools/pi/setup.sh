#!/bin/sh
# Sets up this Raspberry Pi 5 as an inline USB proxy for the GLM adapter.
# Run it once with sudo. It is safe to re-run, and must be re-run after a
# kernel update.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
opt=/opt/qlm-proxy
raw_gadget_commit=8c6de5448ef2b8e4fc37021208c86c3f4dd579dc
usb_proxy_commit=a08301d21d6ba1036cddbcb1a4314578cbc4a274
overlay=dtoverlay=dwc2,dr_mode=peripheral
reboot=no

if [ "$(id -u)" -ne 0 ]; then
    echo "Run this with sudo." >&2
    exit 1
fi
model=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || true)
case "$model" in
    *"Raspberry Pi 5"*) ;;
    *)
        if [ "${QLM_PROXY_ANY_BOARD:-}" != 1 ]; then
            echo "This is not a Raspberry Pi 5: '$model'. Set QLM_PROXY_ANY_BOARD=1 to go on anyway." >&2
            exit 1
        fi
        ;;
esac

# Clones a repository into a directory, or updates it, at a pinned commit.
# Drops local changes, so a patch applies again on a re-run.
checkout() {
    if [ ! -d "$2/.git" ]; then
        git clone --quiet "$1" "$2"
    fi
    git -C "$2" fetch --quiet origin
    git -C "$2" checkout --quiet --force "$3"
}

echo "Packages"
export DEBIAN_FRONTEND=noninteractive
echo "wireshark-common wireshark-common/install-setuid boolean false" | debconf-set-selections
apt-get update -q
headers="linux-headers-$(uname -r)"
if ! apt-cache show "$headers" > /dev/null 2>&1; then
    headers=linux-headers-rpi-2712
fi
apt-get install -y -q git build-essential pkg-config libusb-1.0-0-dev libjsoncpp-dev "$headers" tshark

echo "Peripheral mode on the USB-C port"
config=/boot/firmware/config.txt
[ -d /boot/firmware ] || config=/boot/config.txt
if grep -qx "$overlay" "$config"; then
    echo "  $config already has $overlay"
else
    printf '\n[all]\n%s\n' "$overlay" >> "$config"
    echo "  added $overlay to $config"
    reboot=yes
fi
printf 'dwc2\nusbmon\nraw_gadget\n' > /etc/modules-load.d/qlm-proxy.conf

echo "raw_gadget"
if modprobe raw_gadget 2> /dev/null; then
    echo "  the kernel has it"
else
    # TRAP: this module is built for the running kernel. After a kernel
    # update, re-run this script, or the proxy cannot start.
    checkout https://github.com/xairy/raw-gadget "$opt/raw-gadget" "$raw_gadget_commit"
    make -C "$opt/raw-gadget/raw_gadget"
    mkdir -p "/lib/modules/$(uname -r)/updates"
    install -m 644 "$opt/raw-gadget/raw_gadget/raw_gadget.ko" "/lib/modules/$(uname -r)/updates/"
    depmod -a
    modprobe raw_gadget
    echo "  built and installed for $(uname -r)"
fi

echo "usb-proxy"
checkout https://github.com/AristoChen/usb-proxy "$opt/usb-proxy" "$usb_proxy_commit"
# The patch fixes two relay bugs. usb-proxy held back every output report of
# exactly 64 bytes, so GLM hung waiting for a reply. And it sent the host a
# zero-length input report on each idle read timeout, once a second.
git -C "$opt/usb-proxy" apply "$here/usb-proxy.patch"
make -C "$opt/usb-proxy"
install -m 755 "$opt/usb-proxy/usb-proxy" /usr/local/bin/usb-proxy

echo "The qlm-proxy service"
install -m 755 "$here/proxy.sh" /usr/local/bin/qlm-proxy
install -m 644 "$here/qlm-proxy.service" /etc/systemd/system/qlm-proxy.service
systemctl daemon-reload
systemctl enable qlm-proxy.service

if [ -z "$(ls /sys/class/udc 2> /dev/null)" ]; then
    reboot=yes
fi
if [ "$reboot" = yes ]; then
    echo "Done. Reboot now: sudo reboot. The service starts on its own after it."
else
    systemctl restart qlm-proxy.service
    echo "Done. No reboot needed. Check it: systemctl status qlm-proxy"
fi
