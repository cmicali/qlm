# setup-a-baseline

Part A of [setup-captures.md](../../docs/setup-captures.md): GLM applying a fresh copy of Main.sam, with nothing changed. It checks the method before anything changes. Recorded 2026-10-31 through the Raspberry Pi 5 inline proxy (usb-proxy with `tools/pi/usb-proxy.patch`), on usbmon1. The adapter was device 1:2. No mic, and the volume knob on the adapter. No music played.

The setup:

- GLM 5.2.1 had `qlm-a.sam` open, a Save As of Main.sam, on Main 4x2. All six monitors were on.
- `setups/0.sam` is its redacted snapshot. Against a redacted Main.sam made the same day, it differs only in the `Modified` date and the file's `Volume` line, which went from −30 to −64.5, the knob's level as GLM saved it. Neither reaches a monitor.
- Against the repo's fixture, `Tests/Setups/Fixtures/Main.sam`, redacted on an earlier day, it also differs in `Active_Group`, 3 there and 1 here, and in the 7370A's `DBM_Filter`, 0 there and 1 here. Neither reaches a block: `setup-j-restore`'s applies of the fixture match.
- GLM had run since before the capture. Right after its launch it beachballed for about a minute, then recovered. The Pi's proxy log showed traffic flowing throughout.

| Time (EDT) | Seconds | What happened |
| --- | --- | --- |
| 16:29:30 | 0 | Capture started. GLM was open and idle, on Main 4x2. |
| 16:30:09 | 39.6 | The owner switched to Main 2x1. The routing pass starts at 39.627 s, and the DSP pass at 40.127 s: three passes, to the Left 8351B at `03`, the Right at `06`, and the 7370A at `05`. |
| 16:30:16 | 46.6 | The owner switched back to Main 4x2. Seven passes, from 46.580 s: the Left, the Right, and the 7370A at their sessions, the 7350A at its old session `07`, the Rear Right and Rear Left 8330A at new sessions `08` and `09`, and the 7350A again at `0A`. |
| 16:30:52 | | Capture stopped. |

The Pi logged under-voltage dips that day, eight in all, two of them during GLM's launch before this capture. None broke a capture.

## What the capture showed

- **The method works.** `qlmctl compare-apply` with snapshot `0` reports every pass matching, apart from what qlm leaves out: Main 2x1 from 0 to 45 s, and Main 4x2 from 45 s on. `QLMDSPBlockGoldenTests` has a row for each.
- **The generator stop didn't change.** All 15 stops are the known 14 bytes, 6 in the first window and 9 in the second.
- **A monitor woken into the group is leased again.** As in `group-switch-main-2x1-main-4x2`, GLM sent the 7350A its block at its old session, then again at its new one. The two 8330As took their new sessions before their passes.

## Not explained

GLM's minute-long beachball after launch. Its traffic flowed through it, so it was GLM's window, not the bus.
