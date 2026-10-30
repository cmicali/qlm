# quit-glm

Recorded 2026-10-29 through the Raspberry Pi 5 inline proxy (usb-proxy with `tools/pi/usb-proxy.patch`), on usbmon1. The adapter was device 1:2. Monitors on, no mic, and the volume knob on the adapter.

GLM was open on Main 4x2, after `standby-wake`. The knob set the volume to about 94 dB SPL on GLM's calibrated display, which is −20 dB.

| Time (EDT) | Seconds | What happened |
| --- | --- | --- |
| 21:24:07 | 0 | Capture started. |
| | 0.3 | GLM broadcasts the volume as `0C CC CC`. |
| 21:24:16.4 | 9.4 | GLM was told to quit. It exited within a second. |
| | 9.2 | GLM's last report: an ordinary poll. |
| 21:24:45 | 38 | Capture stopped. Nothing crossed USB after 9.2 s. |

GLM sends nothing special on quit. It stops polling.

`0C CC CC` is 0.1 × `7F FF FF`, so the level is linear amplitude, and −20 dB is a factor of 0.1.

This capture cannot show what level the adapter applies once GLM is gone. The adapter sends nothing over USB unless polled, so anything it does happens on the monitor bus only.
