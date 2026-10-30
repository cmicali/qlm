# volume-sweep

Recorded 2026-10-29 through the Raspberry Pi 5 inline proxy (usb-proxy with `tools/pi/usb-proxy.patch`), on usbmon1. The adapter was device 1:2. Monitors on, and no mic on the adapter.

**GLM was already open**, on Main 4x2, after `mute-dim`. So this capture has no startup traffic.

**The volume knob was unplugged from the adapter during this capture.** With the knob attached, GLM does not let its on-screen volume be dragged. So the knob came out first, and then the volume was dragged in GLM's window only.

| Seconds | What happened |
| --- | --- |
| 0 | Capture started, 21:18:48 EDT. |
| 25.1 to 25.4 | The knob unplugged. Its reading in the adapter's reply to `01 08` jumps, then drops out. GLM follows the jump, from `00 31 07` to `00 00 6F`. [adapter-status.md](../../docs/adapter-status.md) has the detail. |
| 28.0 to 28.4 | Volume dragged from `00 00 6F` to the bottom (`00 00 08`). |
| 28.4 to 34.1 | Dragged to the top (`7F FF FF`). |
| 34.1 to 39.2 | Dragged back to the bottom. |
| 71.8 | Capture stopped, 21:20:00 EDT. The volume was left at the bottom. |

`knob-sweep` is the same sweep, done with the knob.
