# Captures

The protocol facts in qlm come from two sources: hlm's spec, and the captures here. Phase 0 of [the plan](../docs/plan.md) records them. Each capture is a scenario GLM 5 ran with the adapter, saved as the USB traffic between them.

**These files hold your monitors' serial numbers and hardware IDs.** Keep that in mind before publishing the repository.

## Layout

```
captures/
├── inventory/                  what tools/inventory.sh records on the Mac
│   ├── usb.txt                 the adapter in the USB plane
│   ├── hid.txt                 every HID device, the adapter's report descriptor among them
│   ├── hidutil.txt             hidutil's list, for the adapter's usage page
│   └── setups/*.sam            a copy of every GLM setup file
└── <scenario>/
    ├── capture.pcapng          what usbmon or USBPcap recorded, untouched
    ├── reports.txt             tools/pcapng-to-reports.py's text form of it
    └── notes.md                what you did, when, and what you saw
```

`reports.txt` is what the tests read. One line per HID report: the time in seconds from the first packet, `out` or `in`, then the bytes in hex. Lines starting with `#` are comments.

## Recording

USB capture on a current Mac needs SIP off and reportedly fails on Apple silicon. So record off the Mac, one of two ways.

### A Raspberry Pi 5 inline

The Pi sits between the Mac and the adapter. GLM 5 runs on the Mac unchanged. The Pi relays every transfer with [usb-proxy](https://github.com/AristoChen/usb-proxy) over [raw-gadget](https://github.com/xairy/raw-gadget), and usbmon records it.

```
Mac USB port ── USB-C cable ── Pi 5 USB-C port   (the Pi as a USB device)
                               Pi 5 USB-A port ── GLM adapter
```

The Mac powers the Pi through that cable. Reach the Pi over SSH, on Wi-Fi or Ethernet.

Set it up once:

1. Enable SSH on the Pi, in Raspberry Pi Imager or with `sudo raspi-config`.
2. From the repository on the Mac, copy the kit over: `scp -r tools/pi <user>@<host>:`
3. On the Pi, run `sudo ./pi/setup.sh`. It installs the packages, builds usb-proxy with `tools/pi/usb-proxy.patch`, and enables the `qlm-proxy` service.
4. Reboot the Pi if setup says so.

Check that it works:

- On the Pi, `systemctl status qlm-proxy` shows it running. `journalctl -u qlm-proxy -f` follows its log. While GLM runs, it logs each report it relays.
- On the Mac, `ioreg -p IOUSB -w0 | grep "Gnet Adapter"` lists the adapter. System Information's USB section shows it too.
- On the Pi, `vcgencmd get_throttled` shows the supply. `0x0` is clean. `0x50000` means it sagged since boot, often at boot itself. A low bit set, as in `0x50005`, means it is sagging now.
- GLM sees the adapter as if it were plugged in directly, and finds the monitors.

Record each scenario:

1. With `qlm-proxy` running, on the Pi run `sudo ./pi/capture.sh <scenario>`. It prints the start time.
2. Run the scenario in GLM. Press Ctrl-C on the Pi when done.
3. Write `notes.md`: the time of each action and what GLM showed. Note that the capture went through the proxy.
4. On the Mac, run the `scp` and convert commands the script prints. The convert command names the adapter's device.

Pi route caveats:

- The Mac powers the Pi. A Mac port gives at most 15 W, so the Pi warns about its supply and caps its USB-A ports at 600 mA. That suffices for the adapter. If the Pi browns out, power it from the GPIO 5 V pins instead.
- The proxy does not forward USB suspend. So `sleep-wake` shows what GLM sends, but the adapter never sees the Mac suspend. Mark that capture as proxied in `notes.md`. Do not treat it as the answer to what the adapter does on host sleep.
- For `unplug`, unplug the adapter from the Pi, not the Pi from the Mac. That would power the Pi off. The adapter loses power and its host either way, and the proxy drops the Mac's side too. The adapter comes back at a new device number. The converter's warning lists it. Pass `--device` once for each number.
- The Pi shows the Mac a high-speed device, though the adapter is full speed. So the Mac polls every 125 µs, not every 1 ms. The reports and their order are unchanged, and usbmon records the adapter's side at its own speed.
- When a capture starts, dumpcap reads the descriptors of every device on the bus. Those reads are standard USB requests, not frames. They show up as `#` lines at the top of `reports.txt`.
- The Pi's own kernel may talk to the adapter before usb-proxy takes it over. Start each capture after `qlm-proxy` is running, and that traffic stays out.
- Keep the adapter in the same USB-A port. Its bus number, which the capture records, belongs to the port.
- The proxy only relays. It never sends a frame of its own, so AGENTS.md's bus rules hold.

### Windows, with USBPcap

1. Install GLM 5, Wireshark, and USBPcap on a Windows PC, or in a VM with the adapter passed through.
2. Plug in the adapter and open GLM once, so the driver and the setup file are in place.
3. In Wireshark, start a capture on the USBPcap interface that lists the adapter. The adapter is vendor `0x1781`, product `0x0E39`. Filter on `usb.idVendor == 0x1781` to check.
4. Run one scenario. Save the capture as pcapng into a directory named for it.
5. Write `notes.md` next to it: the time of each action and what GLM showed.

### Converting

The converter reads both routes' captures. `--device BUS:DEV` keeps the adapter's traffic and drops the hub's. `capture.sh` prints the adapter's number.

```
python3 -I tools/pcapng-to-reports.py --device 1:2 captures/<scenario>/capture.pcapng > captures/<scenario>/reports.txt
```

## Scenarios

Record each one on its own. Start every capture with the monitors on and GLM closed unless the scenario says otherwise. Unplug the calibration mic from the adapter first. Its live readings ride in the adapter's status replies, which normal use never has.

| Directory | What to do |
| --- | --- |
| `startup-idle` | Open GLM. Wait two minutes. |
| `volume-sweep` | Drag the volume in GLM's window from 0 dB down to the bottom and back, slowly. Unplug the volume knob first: while it is attached, GLM locks its own volume control. |
| `knob-sweep` | Turn the volume knob on the adapter down and up. Press it, if it has a press. |
| `group-switch-<a>-<b>` | Switch from group `a` to group `b`. One capture per ordered pair. |
| `mute-dim` | Mute and unmute each monitor, then all. Dim on, dim off. |
| `standby-wake` | Put the system in standby from GLM, wait ten seconds, wake it. |
| `quit-glm` | With GLM open and the volume at −20 dB, quit GLM. Wait ten seconds. |
| `unplug` | With GLM open, unplug the adapter. Wait ten seconds. Plug it back in. |
| `sleep-wake` | With GLM open, sleep the computer, wait a minute, wake it. Then check `pmset -g log` for an `Entering Sleep` line. A sleep that reaches only DarkWake leaves GLM running. |

## What Phase 0 must answer

The captures are done when they answer these three questions:

1. How the adapter knows a host is present.
2. How knob turns reach the host.
3. What level the adapter applies when the host leaves. Compare `quit-glm` and `unplug` against the volume GLM showed.

One group switch must also decode to the sequence espgensam documents, for your models.
