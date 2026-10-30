# mute-dim

Recorded 2026-10-29 through the Raspberry Pi 5 inline proxy (usb-proxy with `tools/pi/usb-proxy.patch`), on usbmon1. The adapter was device 1:2. Monitors on, and no mic on the adapter.

**GLM was already open**, on Main 4x2, after the six group-switch captures. So this capture has no startup traffic.

The monitors were muted and unmuted in this order: big sub, small sub, the two large speakers, the two small speakers. Then all, then dim on and off. The order within each pair is not known. The times and addresses below come from the capture.

| Seconds | Action | Bus address in this capture |
| --- | --- | --- |
| 0 | Capture started, 21:15:41 EDT. | |
| 19.2 / 22.7 | Big sub muted / unmuted. | `0B` |
| 24.7 / 26.1 | Small sub muted / unmuted. | `05` |
| 27.4 / 29.2 | A large speaker muted / unmuted. | `03` |
| 30.9 / 32.9 | The other large speaker muted / unmuted. | `06` |
| 34.8 / 36.7 | A small speaker muted / unmuted. | `0D` |
| 38.4 / 42.2 | The other small speaker muted / unmuted. | `0C` |
| 46.2 / 48.6 | All muted / unmuted. | all six, and `01` |
| 51.2 / 54.8 | Dim on / off. | broadcast |
| 99.9 | Capture stopped, 21:17:21 EDT. | |

Each mute action sends opcode `2B` to all six monitors, twice: `03` to a muted monitor and `04` to the others. Mute all also sends `2B 01` to address `01`, and unmute all sends `2B 00`.

Dim lowers the broadcast volume frame (`FF 1F`) from `00 31 07` to `00 04 E7`, and dim off restores it. Each dim action also sends broadcast `2D 00` and `3D 00 00`.

**The bus addresses are not the ones startup used.** At startup, GLM polled `02` to `07`. After the group switches, Main 4x2 sat at `03 05 06 0B 0C 0D`.
