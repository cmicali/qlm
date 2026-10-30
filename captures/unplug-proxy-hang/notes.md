# unplug-proxy-hang

Recorded 2026-10-29, as unplug, through the Raspberry Pi 5 inline proxy, on usbmon1. Monitors on, no mic, and the volume knob on the adapter. GLM was open, on Main 4x2, from 21:25:30.

**The proxy hung on the unplug, so the recovery here is not what a direct connection does.** usb-proxy stopped, but never exited, so systemd never restarted it. The third hunk of `tools/pi/usb-proxy.patch` fixes that. `unplug` is the same scenario, recorded after the fix. Use this capture only for the moment of the unplug.

The adapter was device 1:2 before the unplug and 1:3 after it. Convert with `--device 1:2 --device 1:3`.

| Time (EDT) | Seconds | What happened |
| --- | --- | --- |
| 21:25:36 | 0 | Capture started. |
| 21:25:54 | 18.0 | The adapter was unplugged from the Pi. GLM's last report. |
| | 72.9 | The adapter was plugged back into the same port. The Pi's kernel enumerated it as 1:3. GLM showed "adapter offline". |
| 21:27:21 | 105 | The proxy was restarted by hand. |
| | 106.2 | GLM's first report after the restart. GLM found the adapter and all the monitors. |
| 21:27:51 | 135.6 | Capture stopped. |
