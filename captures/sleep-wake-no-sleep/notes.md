# sleep-wake-no-sleep

Recorded 2026-10-29, as a retry of sleep-wake, through the Raspberry Pi 5 inline proxy, on usbmon1, detached on the Pi. The adapter was device 1:4. GLM was open.

**The Mac did not sleep.** Apple menu → Sleep was chosen, and the Mac was left untouched for a minute. But `pmset -g log` shows no sleep or wake from 21:44:50 on, and GLM's traffic has no gap.

| Time (EDT) | Seconds | What happened |
| --- | --- | --- |
| 21:44:55 | 0 | Capture started. |
| 21:47:06 | 130 | Capture stopped. GLM showed all the monitors. |
