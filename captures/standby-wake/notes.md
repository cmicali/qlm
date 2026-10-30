# standby-wake

Recorded 2026-10-29 through the Raspberry Pi 5 inline proxy (usb-proxy with `tools/pi/usb-proxy.patch`), on usbmon1. The adapter was device 1:2. Monitors on, no mic, and the volume knob plugged back into the adapter just before.

**GLM was already open**, on Main 4x2, after `volume-sweep`. So this capture has no startup traffic.

The whole system was put in standby from GLM. After about ten seconds it was woken from GLM, and all the monitors came back. The times below come from the capture.

| Seconds | What happened |
| --- | --- |
| 0 | Capture started, 21:21:19 EDT. |
| 1.0 to 4.3, 19.6, 25.5 | Bursts of `2B` mute state to every monitor. The cause is not known. Perhaps GLM reacting to the knob. |
| 34.9 | Standby: broadcast `3A 03 02`, then `3A 03 00`. |
| 37.4, 40.2, 43.1, 46.0 | One lease every 3 s during standby. An 8351B, hardware ID `11 4B EA`, still answers the probe. GLM leases it `0E`, `0F`, `10`, then `11` (`F0 02 11 4B EA …`). An earlier reading took these for `02 11` probes. |
| 46.0 to 49.1 | Wake: a full re-init burst (`39`, `FF 04`, `3B`, `40`, `17`, and more). |
| 79.2 | Capture stopped, 21:22:38 EDT. |

Before standby, GLM polled the monitors at `03 05 06 0B 0C 0D`. After the wake, it polled them at `12` to `17`. GLM re-addresses the monitors on a wake, as on a group switch.
