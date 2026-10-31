# setup-j-restore

Part J of [setup-captures.md](../../docs/setup-captures.md): GLM opening Main.sam again after the session, and switching to the group the owner uses. Recorded 2026-10-31 through the Raspberry Pi 5 inline proxy (usb-proxy with `tools/pi/usb-proxy.patch`), on usbmon1. The adapter was device 1:2. No mic, and the volume knob on the adapter.

GLM had run since `setup-b-peq-8351b`, with `qlm-g.sam` open on Main 4x2. The capture has no `setups/`: GLM applied Main.sam itself, and `Tests/Setups/Fixtures/Main.sam` is its redacted copy.

| Time (EDT) | Seconds | What happened |
| --- | --- | --- |
| 16:41:39 | 0 | Capture started. |
| 16:42:12 | 33.0 | The owner opened Main.sam in GLM. GLM asked the adapter for `39`, `19 01`, and `51 82` again, and kept every lease. |
| 16:42:12 | 33.1 | GLM applied Main 4x2: six passes, from 33.113 s, to sessions `0C`, `0E`, `0F`, `14`, `15`, and `16`. |
| 16:42:13 | 34.6 | GLM applied Main 4x2 again: six passes, from 34.551 s, to the same sessions, in the setup's device order. |
| 16:42:22 | 43.0 | The owner switched to Main 2x1, the group they use. Three passes, from 43.049 s. |
| | | Music played at a low level, and sounded as it did before the session. |
| 16:43:06 | | Capture stopped. |

The Pi logged under-voltage dips that day, eight in all, two of them during GLM's launch before `setup-a-baseline`. None broke a capture.

## What the capture showed

- **Main.sam is back.** Every pass matches the fixture's blocks: both Main 4x2 applies, and the Main 2x1 one. `QLMDSPBlockGoldenTests` has a row for each.
- **The generator stop didn't change.** All 18 stops are the known 14 bytes, 6 in each apply's window.
- **Opening a setup re-reads the adapter.** GLM sent `01 39`, `01 19 01`, and `01 51 82`, as it does at a connection, but no `01 22`, and leased nothing.

## Not explained

- GLM applied Main 4x2 twice, 1.4 s apart. The first went in session order, and the second in the setup's device order.
- In `setup-b-peq-8351b`, GLM also re-read the adapter, but broadcast `03` first and leased every monitor again. Here it did neither.
