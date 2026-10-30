# unplug

Recorded 2026-10-29 through the Raspberry Pi 5 inline proxy (usb-proxy with all three hunks of `tools/pi/usb-proxy.patch`), on usbmon1. Monitors on, no mic, and the volume knob on the adapter. GLM was open, on Main 4x2.

The adapter was device 1:3 before the unplug and 1:4 after it. Convert with `--device 1:3 --device 1:4`.

The adapter was unplugged from the Pi's USB-A port, not the Pi from the Mac. The Mac lost the adapter because the proxy dropped its side. GLM recovered on its own.

| Time (EDT) | Seconds | What happened |
| --- | --- | --- |
| 21:29:36 | 0 | Capture started. |
| 21:30:37 | 60.4 | The adapter was unplugged. GLM's last report before it. |
| 21:30:38 | 62 | systemd restarted the proxy, which waited for the adapter. |
| 21:30:43 | 67 | The adapter was back in the same port, and the proxy relayed it again. |
| | 68.3 | GLM's first report after the replug. |
| 21:31:02 | 86.3 | Capture stopped, with GLM showing the adapter and all the monitors. |

The gap is the proxy's doing as much as GLM's: the Mac sees the adapter only once the proxy relays it again.
