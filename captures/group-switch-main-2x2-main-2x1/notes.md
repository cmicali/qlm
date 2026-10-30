# group-switch-main-2x2-main-2x1

Recorded 2026-10-29 through the Raspberry Pi 5 inline proxy (usb-proxy with `tools/pi/usb-proxy.patch`), on usbmon1. The adapter was device 1:2. Monitors on, and no mic on the adapter.

**GLM was already open**, on Main 2x2. It was opened at 21:10:44, before the first switch capture, and stayed open for all six. So this capture has no startup traffic.

| Time (EDT) | Seconds | What happened |
| --- | --- | --- |
| 21:12:08 | 0 | Capture started, with GLM on Main 2x2. |
| | | Main 2x1 was picked in GLM's window. |
| 21:12:34 | 26 | GLM showed the switch finished. |
| 21:12:37 | 29 | Capture stopped. |

The `#` lines at 0 s are dumpcap's own descriptor reads, not GLM's.
