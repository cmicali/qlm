# startup-idle-mic

Recorded 2026-10-29, as startup-idle, through the Raspberry Pi 5 inline proxy (usb-proxy with `tools/pi/usb-proxy.patch`), on usbmon1. The adapter was device 1:2. Monitors on, GLM closed at the start.

| Time (EDT) | Seconds | What happened |
| --- | --- | --- |
| 20:57:37 | 0 | Capture started. |
| 20:57:41 | 4 | GLM 5 opened. |
| | 7.3 | GLM's first output report. |
| 20:59:50 | 133 | Capture stopped, with GLM still open. GLM was quit after the capture. |

GLM showed all six monitors online, with the usual setup and group, and nothing odd.

**The calibration mic was plugged into the adapter.** Normal use has no mic. `startup-idle` is the same scenario without it. Diff the two to find the mic's traffic.

The `#` lines at 0 s are dumpcap's own descriptor reads, not GLM's.
