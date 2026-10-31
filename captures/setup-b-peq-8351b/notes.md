# setup-b-peq-8351b

Part B of [setup-captures.md](../../docs/setup-captures.md): GLM applying a copy of Main.sam with the Left 8351B's bands and shelves changed. Recorded 2026-10-31 through the Raspberry Pi 5 inline proxy (usb-proxy with `tools/pi/usb-proxy.patch`), on usbmon1. The adapter was device 1:2. No mic, and the volume knob on the adapter. No music played.

The setup:

- GLM 5.2.1 had run since `setup-a-baseline`, on Main 4x2, with all six monitors on.
- The copy was `qlm-g.sam`, a Save As of Main.sam made for Part G. The owner then found that GLM shows no control for the 8351B's `GroupDelayCompensation` or `BassExtensionXO(Hz)` outside the group definition, which needs a recalibration. So Part G didn't run, and the copy served Part B.
- `setups/0.sam` is the copy before any change. It equals a redacted Main.sam apart from the `Modified` date and the `Volume` line, and it equals `setup-a-baseline`'s snapshot.
- Every change was to the Left 8351B's node in Main 4x2, in its Acoustic editor. Main 2x1's Left is a separate node, and stayed as it was.

| Time (EDT) | Seconds | What happened |
| --- | --- | --- |
| 16:35:22 | 0 | Capture started. The six held sessions `03`, `05`, `06`, `08`, `09`, and `0A`. |
| 16:35:44 | 22.5 | GLM broadcast a bare `03` twice, 0.6 ms apart, and polled no monitor after it. It asked the adapter for `39`, `19 01`, and `51 82`, sent the wake pairs, and from 23.760 s leased all six again, at `0B` to `10`. |
| 16:35:45 | 23.9 | GLM applied Main 4x2 on its own, before any change: six passes, from 23.863 s. |
| 16:36:12 | 50.0 | B1. The owner edited the Left's bands. GLM sent each change at once, as a lone `10 0E` to the Left's session `0C`, 13 frames to slots `04` to `09`, until 117.849 s. |
| 16:38:10 | 167.8 | The owner confirmed the editor. GLM sent the Left its level, now −0.2 dB, its delay, and `10 01 09`, and no block. The owner saved the copy, and kept `setups/1.sam`. |
| 16:38:19 | 177.3 | The owner switched to Main 2x1: three passes, from 177.333 s. |
| 16:38:24 | 182.5 | The owner switched back to Main 4x2: nine passes, from 182.460 s. The 8330As got theirs at `0D` and `0B`, then at new sessions `11` and `12`. GLM cut the 7350A's at `10` short after slot `09`, at 183.450 s, and sent it whole at `13`. |
| 16:39:12 | 230.5 | B2. The owner edited the Left's four shelves. GLM sent each to slots `00` to `03` as it changed, 8 frames, until 265.754 s. |
| 16:40:10 | 287.9 | The owner confirmed the editor. GLM sent the level, the delay, and `10 01 09` again. The owner saved the copy, and kept `setups/2.sam`. |
| 16:40:17 | 295.1 | The owner switched to Main 2x1: three passes, from 295.062 s. |
| 16:40:22 | 300.0 | The owner switched back to Main 4x2: nine passes, from 300.007 s. The 8330As got theirs at `12` and `11`, then at `14` and `15`. GLM cut the 7350A's at `13` short after slot `00`, at 300.973 s, and sent it whole at `16`. |
| 16:40:45 | | Capture stopped. |

The Pi logged under-voltage dips that day, eight in all, two of them during GLM's launch before `setup-a-baseline`. None broke a capture.

## B1, the bands

`setups/0.sam` to `setups/1.sam`. Notch 1+ is slot `04`, and Notch 6 is slot `09`.

| Band | Before | After | Why |
| --- | --- | --- | --- |
| Notch 1+ | 278.9 Hz, +4 dB, Q 1.12 | 1000 Hz, +6 dB, Q 0.1 | The lowest Q GLM allows, boosted |
| Notch 2+ | 73.46 Hz, −10.03 dB, Q 2.29 | 1000 Hz, −6 dB, Q 20 | The highest Q GLM allows |
| Notch 3+ | 123.17 Hz, −3.55 dB, Q 3.27 | 18000 Hz, −3 dB, Q 3.3 | Near the top |
| Notch 4+ | 183.64 Hz, −7.57 dB, Q 7.54 | 183.6 Hz, 0 dB, Q 7.5 | 0 dB, which goes out as the bypass |
| Notch 5 | 39.23 Hz, −8.18 dB, Q 8.54 | 25 Hz, −20 dB, Q 8.5 | Near the bottom, as deep as GLM allows |
| Notch 6 | 423.71 Hz, −2.95 dB, Q 13 | 423.7 Hz, 0 dB, Q 13 | 0 dB |

A plain notch, with no "+", refuses a boost. Only the "+" bands take one, so Notch 6 went to 0 dB in place of a boost.

The diff also holds three changes the owner didn't make:

- The Left's `Level_Sensitivity` went from −0.17 to −0.2, the rounded value the editor shows.
- Its `CalibrationStatusFlag` went from 3 to 4.
- Each band the owner touched lost its second decimal: frequency and Q now have one. So Notch 4+ moved from 183.64 Hz to 183.6 Hz, and its Q from 7.54 to 7.5, though the owner set only its gain. Notch 7 on, untouched, kept two.

`Volume` went from −64.5 to −56.5, the knob's level at the save.

## B2, the shelves

`setups/1.sam` to `setups/2.sam`. The shelves are slots `00` to `03`, and all four were at 0 dB before.

| Shelf | Before | After |
| --- | --- | --- |
| Low Shelf 1+ | 100 Hz, 0 dB | 60 Hz, +3 dB |
| Low Shelf 2 | 100 Hz, 0 dB | 150 Hz, −4 dB |
| High Shelf 1+ | 1000 Hz, 0 dB | 3000 Hz, +2 dB |
| High Shelf 2 | 1000 Hz, 0 dB | 8000 Hz, −5 dB |

GLM showed "Positive gain warning: Total sum of correction with positive gain exceeds +6db. Reduce filter gains." It took the values anyway. GLM moved nothing else.

## What the capture showed

- **The 8351B's peaking bands match across their range.** After B1, `compare-apply` with snapshot `1` matches every band to the bit: Q from 0.1 to 20, 18 kHz, a −20 dB cut, a +6 dB boost, and two bands at 0 dB sent as the bypass.
- **One shelf didn't match, until the fix.** After B2, High Shelf 2, 8000 Hz at −5 dB, came out of qlm's design a bit off in four of its five floats. GLM sent `66 95 27 3F F9 7A 0E BF D5 2F A2 3C 30 8E 84 3F 34 21 1D BE` to slot `03`, and qlm built `… FA 7A 0E BF D9 2F A2 3C 31 8E 84 3F 35 21 1D BE`. GLM rounds a shelf's w0 to float before its sine and cosine. With that, all four shelves match. The low shelves and High Shelf 1+ matched before it too.
- **Main 2x1's Left is its own node.** Its passes match snapshots `1` and `2` unchanged.
- **The generator stop didn't change.** All 36 stops are the known 14 bytes.
- **GLM sends a band as it's edited.** Each change in the editor went out at once, as one `10 0E` to the monitor's session, outside any block. Confirming the editor sent the level, the delay, and `10 01 09`, and no block. GLM applied each change in a block only at the next group switch.
- **GLM cuts a pass short to lease a monitor again.** Each switch to Main 4x2 woke the 8330As and the 7350A, which are off in Main 2x1. Twice GLM leased the 7350A again mid-pass, stopped that pass, and sent the whole block at the new session. Both short passes are the start of the block, frame for frame.

`QLMDSPBlockGoldenTests` has a row for each apply, against its snapshot: Main 4x2 to 170 s against `0`, Main 2x1 to 181 s and Main 4x2 to 290 s against `1`, then Main 2x1 to 299 s and Main 4x2 after against `2`. With the shelf fix, `compare-apply` exits 0 in each of those five windows, and says `cut short by GLM` for the two short passes.

## Surprises

- **GLM moves fields on its own when the editor saves.** The level rounded to what the editor shows, the calibration flag bumped, and each touched band rounded to one decimal.
- **A bare `03` broadcast, at 22.461 s.** No other capture holds it, and hlm's spec has no opcode `03`. All six answered GLM's next probe, 1.5 s after their last poll, sooner than any lapse we've timed. So the `03`, or the wake pairs after it, dropped their leases. qlm's allowlist refuses it.

## Not explained

- What made GLM send `03`, re-read the adapter, and apply Main 4x2 at 22.5 s. The owner made no change then. GLM kept counting sessions from `0B`, so it didn't relaunch. Opening Main.sam in `setup-j-restore` re-read the adapter, but sent no `03` and leased nothing.
- Why the 8330As got a second pass at a new session in both switches here, but not in `setup-a-baseline`, where they were leased before their first.
