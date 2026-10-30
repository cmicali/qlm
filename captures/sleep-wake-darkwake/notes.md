# sleep-wake-darkwake

Recorded 2026-10-29, as sleep-wake, through the Raspberry Pi 5 inline proxy (usb-proxy with all three hunks of `tools/pi/usb-proxy.patch`), on usbmon1, detached on the Pi so the Mac's sleep could not stop it. The adapter was device 1:4. Monitors on, no mic, and the volume knob on the adapter. GLM was open.

**The Mac never truly slept, so this capture does not show a sleep.** `pmset -g log` shows one sleep, at 21:40:55, that entered DarkWake only. A key press woke the Mac 11 s later. GLM kept polling, at about 60 reports a second, straight through. The proxy logged no USB suspend. The Pi stayed powered: its boot time did not change.

| Time (EDT) | Seconds | What happened |
| --- | --- | --- |
| 21:31:37 | 0 | Capture started. |
| 21:40:55 | 558 | Mac told to sleep. It entered DarkWake. The display went off. |
| 21:41:06 | 569 | Full wake, on a key press. |
| 21:41:39 | 602 | Capture stopped. GLM showed the adapter and all the monitors. |

Even a true sleep shows only GLM's side. The proxy does not forward USB suspend to the adapter.
