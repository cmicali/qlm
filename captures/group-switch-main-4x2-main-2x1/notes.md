# group-switch-main-4x2-main-2x1

Recorded 2026-10-29 through the Raspberry Pi 5 inline proxy (usb-proxy with `tools/pi/usb-proxy.patch`), on usbmon1. The adapter was device 1:2. Monitors on, and no mic on the adapter.

**GLM was already open**, on Main 4x2. It was opened at 21:10:44, before the first switch capture, and stayed open for all six. So this capture has no startup traffic.

| Time (EDT) | Seconds | What happened |
| --- | --- | --- |
| 21:13:39 | 0 | Capture started, with GLM on Main 4x2. |
| | | Main 2x1 was picked in GLM's window. |
| 21:14:02 | 23 | GLM showed the switch finished. |
| 21:14:05 | 26 | Capture stopped. |

The `#` lines at 0 s are dumpcap's own descriptor reads, not GLM's.
