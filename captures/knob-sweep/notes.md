# knob-sweep

Recorded 2026-10-29, as volume-sweep, through the Raspberry Pi 5 inline proxy (usb-proxy with `tools/pi/usb-proxy.patch`), on usbmon1. The adapter was device 1:2. Monitors on, GLM closed at the start.

**The calibration mic was plugged into the adapter**, and GLM showed its live reading. Normal use has no mic.

| Time (EDT) | Seconds | What happened |
| --- | --- | --- |
| 21:00:29 | 0 | Capture started. |
| 21:00:32 | 3 | GLM 5 opened. |
| | 6.5 | GLM's first output report. |
| | | The adapter's volume knob was turned slowly up, down, up, and down, across the whole range. GLM's window was not touched. |
| 21:01:55 | 86 | Capture stopped, with GLM still open. GLM was quit after the capture. |

GLM showed the volume in dB SPL, from 14 to 114, because the system is calibrated. Everything worked.

GLM follows each knob turn with volume frames. They are broadcast opcode `1F` (address `FF`) with a 3-byte level. They run from `7F FF FF` at the top to `00 00 08` at the bottom.
