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
    ├── capture.pcapng          what USBPcap recorded, untouched
    ├── reports.txt             tools/pcapng-to-reports.py's text form of it
    └── notes.md                what you did, when, and what you saw
```

`reports.txt` is what the tests read. One line per HID report: the time in seconds from the first packet, `out` or `in`, then the bytes in hex. Lines starting with `#` are comments.

## Recording

USB capture on a current Mac needs SIP off and reportedly fails on Apple silicon, so record on Windows:

1. Install GLM 5, Wireshark, and USBPcap on a Windows PC, or in a VM with the adapter passed through.
2. Plug in the adapter and open GLM once, so the driver and the setup file are in place.
3. In Wireshark, start a capture on the USBPcap interface that lists the adapter. The adapter is vendor `0x1781`, product `0x0E39`. Filter on `usb.idVendor == 0x1781` to check.
4. Run one scenario. Save the capture as pcapng into a directory named for it.
5. Write `notes.md` next to it: the time of each action and what GLM showed.
6. Convert it:

```
python3 -I tools/pcapng-to-reports.py captures/<scenario>/capture.pcapng > captures/<scenario>/reports.txt
```

## Scenarios

Record each one on its own. Start every capture with the monitors on and GLM closed unless the scenario says otherwise.

| Directory | What to do |
| --- | --- |
| `startup-idle` | Open GLM. Wait two minutes. |
| `volume-sweep` | Drag the volume from 0 dB down to the bottom and back, slowly. |
| `knob-sweep` | Turn the 9310 knob down and up. Press it, if it has a press. |
| `group-switch-<a>-<b>` | Switch from group `a` to group `b`. One capture per ordered pair. |
| `mute-dim` | Mute and unmute each monitor, then all. Dim on, dim off. |
| `standby-wake` | Put the system in standby from GLM, wait ten seconds, wake it. |
| `quit-glm` | With GLM open and the volume at −20 dB, quit GLM. Wait ten seconds. |
| `unplug` | With GLM open, unplug the adapter. Wait ten seconds. Plug it back in. |
| `sleep-wake` | With GLM open, sleep the computer, wait a minute, wake it. |

## What Phase 0 must answer

The captures are done when they answer these three questions:

1. How the adapter knows a host is present.
2. How knob turns reach the host.
3. What level the adapter applies when the host leaves. Compare `quit-glm` and `unplug` against the volume GLM showed.

One group switch must also decode to the sequence espgensam documents, for your models.
