# startup-idle

Recorded 2026-10-29 through the Raspberry Pi 5 inline proxy (usb-proxy with `tools/pi/usb-proxy.patch`), on usbmon1. The adapter was device 1:2. Monitors on, GLM closed at the start, and no mic on the adapter.

| Time (EDT) | Seconds | What happened |
| --- | --- | --- |
| 21:03:43 | 0 | Capture started. |
| 21:03:47 | 4 | GLM 5 opened. |
| | 7.3 | GLM's first output report. |
| 21:06:01 | 138 | Capture stopped, with GLM still open. GLM was quit after the capture. |

GLM showed all six monitors online, with the usual setup and group, and no live SPL reading.

`startup-idle-mic` is the same scenario with the calibration mic plugged in. The traffic matches. Only the adapter's reply to `01 08` differs. With the mic in, that reply is longer and carries two changing values.

The `#` lines at 0 s are dumpcap's own descriptor reads, not GLM's.
