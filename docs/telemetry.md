# The monitors' telemetry

Every monitor answers its `08` poll with a telemetry frame. hlm's spec lists most of its tags. The captures show five more: `49`, `82`, `88`, `89`, and `8A`. This is what each one carries, and what the meters can show. A time is seconds into that capture's `reports.txt`, at the poll. **Guess:** marks a guess.

## Short answers

| Tag | Sent by | What it is | Sure? |
| --- | --- | --- | --- |
| `49` | every model | Seconds since the monitor last woke, mod 256. One frame a second. | High |
| `8A` | every model | The seconds since the wake, over 256. With `49`, it makes one count of seconds. It rides one frame in 30 s. | High |
| `82` | the 8351B | A third reading of the kind `81` and `83` are. It equals the temperature at rest. What it measures is unknown. | Medium |
| `88` | the 8351B | A steady reading, different on each monitor, that standby does not change. | Unknown |
| `89` | the 8351B | A steady reading that falls 16 to 19 within a second of standby, and comes back at the wake. | Unknown |

- **The meters work as approximate meters.** On the output meters, a count is about a dB, and the floor is `80`. `42` reads before the volume. `44` is the 8351B's midrange.
- **A monitor sometimes splits a frame across two polls**, at a field. That explains the replies that lack the leading `41`: each is the second part of a split frame.
- `QLMReplyTelemetry` decodes `49` as `wakeSeconds`, `8A` as `wakeSteps`, and `82` as `sensor82`. It steps over `88` and `89`.

## Sources

- **The captures.** All 22 in `captures/`, each with its `notes.md`. GLM 5 ran the Phase 0 scenarios on 2026-10-29, from 20:57 to 21:47. qlm ran `qlm-first-discover`, `qlm-standby-discover`, `qlm-control-first`, `qlm-control-all`, and, through the app, `qlm-app-first` on 2026-10-30. Only those last three have music playing.
- **hlm's spec**, `docs/Genelec GLM Protocol.13.md` in [robcazzaro/hlm](https://github.com/robcazzaro/hlm), revision 13. It is GPL-3.0. This page states its facts in its own words, and takes no text or code from it.
  - Section 4: multi-byte values are big-endian.
  - Section 8: a busy byte, `06` or `07`, may follow the `09`. A reply of `09` and a busy byte alone carries no telemetry this round.
  - Section 8.1: the tags `42` to `47`, `81`, `83`, and `84`, and the VU mapping for the meters.
  - None of `49`, `82`, `88`, `89`, or `8A` appears in the spec.
- **The monitors.** Two 8351B (the Left and the Right), two 8330A, a 7370A, and a 7350A. The Right 8351B is the one `qlm-control-first` played.

The numbers here come from a script over every `reports.txt`. It parsed each reply to a monitor's `08` with the tag rule in [adapter-status.md](adapter-status.md): the top two bits of a tag give its value's length. `QLMTelemetryTests` checks the main claims in code.

## The frame

The captures hold 36,609 replies to a monitor's `08`. 21,046 are whole frames, and 15,418 are a bare `09`. 51 are a bare busy marker. 94 are the two parts of 47 split frames.

Each model sends its fields in a fixed order:

| Model | On | In standby |
| --- | --- | --- |
| 8351B | `81 82 83 42 43 45 44 47 49 88 89 84` | `47 49 88 89 84` |
| 8330A | `81 83 42 43 45 47 49 84` | `47 49 84` |
| 7370A, 7350A | `83 42 46 43 45 47 49 84` | `47 49 84` |

Any of them may end with `8A`. Every whole frame ends with `84`, or `84` and `8A`, as every example in section 8.1 does, but for two. In `qlm-control-all`, at 381.151 and 381.166 s, both 8330As, busy, ended a frame with a bare `04` after `8A`. Every frame reads with the tag rule. `04` is the only unknown tag, and it comes only after `84` (`QLMGoldenTests`). Both 8330As' counts had restarted minutes before, the Rear Right's at its power switch, and these were their first frames after GLM's apply ([protocol.md](protocol.md#telemetry)).

### One frame a second

- **A monitor makes a new frame about once a second.** GLM polls each monitor about every 0.57 s, so about every other poll finds nothing new. That poll gets the bare `09`.
- Every bare `09`, but one, comes less than a second after the last frame. Every frame comes at least 0.52 s after the last one. No frame repeats: `49` always differs (below).

### Split frames

**A monitor sometimes sends a frame in two parts, split at a field, across two polls.** The first part stops early, with no `84`. The next poll of that monitor, 0.57 s later, gets the rest, with no `41`. Together they make the model's whole frame, with one `49`. Each part passes its CRC.

`sleep-wake-darkwake`, the Left 8351B at `15`:

| Poll | Reply |
| --- | --- |
| 313.283 s | `09 41 2A` |
| 313.878 s | `09 81 00 2A 82 00 2A 83 00 2A 42 9F 43 80 45 80 44 80 47 01 49 73 88 00 4B 89 00 41 84 02 F1` |

- The captures have 47 split frames, from every model, in 15 scenarios. The split falls at any field: after `41` in 33, and after `81`, `83`, `46`, `42`, `47`, `49`, or `89` in the rest.
- Every first part is followed by its second part at the monitor's next poll. No second part comes alone.
- **Guess:** the poll reads the monitor's reply while the monitor is still writing that second's frame.

`QLMReplyTelemetry` reads a first part as `QLMTelemetryErrorPartial`, with its fields filled, and a second part as `QLMTelemetryErrorNotTelemetry`. System uses only `QLMTelemetryOK` and `QLMTelemetryErrorUnknownTag`, so it keeps the last whole frame.

## `49`: seconds since the wake

- **It counts up once a second.** In GLM's captures, 10,046 pairs of frames follow one another from the same monitor. Every pair advances, and none repeats. The advance matches the time between them within 0.82 s.
- **It counts with no host polling.** In `qlm-standby-discover`, no one polled the six in standby from 40 to 250 s. Each count rose 207 to 214 in 209.8 to 210.5 s. In `qlm-control-first`, the Left 8351B in standby rose 71 in 69.9 s, from 95.4 s.
- **It wraps at 256.** In `unplug`, all six read `FE` at 60.3 s, and `08` at 70.8 s, after the replug.
- **A lease, an unplug, a new host, standby, and a group apply do not reset it.** The Left 8351B's count ran on through all twelve GLM captures from `startup-idle-mic` (20:57) to `standby-wake` (21:21), with six wraps. It drifted 2.2 s against the captures' clock. In `standby-wake`, it counted on through standby at 34.9 s.
- **A wake resets it.** In `standby-wake`, GLM woke the six at 46.0 s. At 49.05 s, each read `01` or `02`. Monitors that join a group from standby read `02` too (`group-switch-main-2x1-main-4x2`, 38.2 s, and `group-switch-main-2x2-main-4x2`, 12.8 s). After qlm's wake, the 8351Bs and the 7370A read `01` (`qlm-control-first`, 829.4 s).
- **Monitors woken together count together.** The two 8330A woke in the same group switch at about 21:14:48. A minute later, in `mute-dim`, both read `35` at 0.19 s.
- **A power-on at the power switch resets it too.** In `qlm-control-all`, the Rear Right 8330A was switched on and answered the probe at 214.755 s. Its first frame, at 215.94 s, read `01`, and its `8A` read `00 00` (`testAPowerOnStartsTheWakeCount`). The other 8330A's count restarted at about 175 s too, though the notes don't say it was switched.

## `8A`: the seconds since the wake, over 256

`8A` and `49` are one count of seconds since the wake. `8A` is the count over 256, and `49` the count mod 256. So `8A` steps every 256 s.

- **It rides one frame in 30 s.** 447 frames carry it, about one in 24. After the first one a host reads, 213 of the 214 gaps between them in GLM's polling are 30 or 31 s. The other is 60 s, where the frame that carried it came split (`sleep-wake-darkwake`, 395.43 s).
- **A tick that no poll reads waits for the next poll.** GLM's first poll of each monitor carries `8A` (`startup-idle` and `startup-idle-mic`, 9.9 s, all six). So does the first poll after the replug in `unplug` (70.8 s) and `unplug-proxy-hang` (108.7 s). So does the first poll of every qlm run in `qlm-control-first`.
- **It is 0 after a wake.** In `standby-wake`, each of the six read `00 00` from 52.0 s. After qlm's wake, the 8351Bs read `00 00` at 833.4 s, and the 7370A at 839.1 s.
- **With `49`, it counts the seconds since the wake.** Take two frames in a row that carry `8A` from one session, with no lease of that session and no broadcast `3A 03 7F` or `3A 03 01` between. The captures hold 508 such pairs. In 505, the time less `8A` × 256 + `49` moves less than 1.5 s from one to the next, through every step. In `sleep-wake-darkwake`, it holds within a second (`testWakeStepsEveryThirtySeconds`). In `qlm-control-all`, all six read `00 1E` from 8400.45 to 8481.47 s, after their wake at 575.1 s: 30 steps of 256 s is 7,680 s.
- **In the other three, the earlier frame lags a step.** Each came 9 to 22 s after `49` wrapped, and carried the `8A` from before the wrap (`knob-sweep`, 9.185 s; `qlm-first-discover`, 79.695 and 79.753 s). **Guess:** a frame's `8A` is read when its 30 s slot falls due, a little before the frame.
- **A step looks like 240 s from the outside.** In `sleep-wake-darkwake`, the first frames to show `00 03` and `00 04` came 240 s apart. That's a multiple of the 30 s between frames that carry it, not the step. The count runs on across both steps without a jump. It counts in standby too: the Left went from `00 02` to `00 05` in 721 s (`qlm-control-first`).
- **The value is big-endian, by section 4.** Only the low byte moves in the captures. No capture shows a carry.
- **The values the captures show:**
  - `00 00` to `00 05` after the evening's wakes, and `00 1E` two hours after one (`qlm-control-all`).
  - `00 A7` to `00 C0` the next morning. That is 11.9 to 13.7 hours since the last wake, the night before.
  - `13 04` to `13 0D` (the 8351Bs and the subwoofers) and `2B DF` to `2B E3` (the 8330A) before that evening's first wake. That is 14.4 and 33.3 days. **Guess:** these monitors had not woken in that long.

## `81`, `82`, and `83`

Section 8.1 calls `81` and `83` slow readings that follow the temperature at rest, and part from it after a power change. `82` has their form, `00` and a value.

- **Only the 8351B sends `82`**, between `81` and `83`, in every frame while it is on.
- **At rest it equals the temperature.** So does `81` in every 8351B frame, outside the minute after a wake. `82` matches in 3,391 of 3,393, and `83` in 3,381.
- **After a wake, the three start apart and settle at their own rates.** The Left 8351B (`standby-wake`):

  | Time | `41` | `81` | `82` | `83` |
  | --- | --- | --- | --- | --- |
  | 49.05 s | 25 | 32 | 40 | 41 |
  | 59.38 s | 38 | 39 | 43 | 47 |
  | 78.23 s | 41 | 41 | 42 | 46 |

  The Right after qlm's wake reads 23, 33, 40, and 41 at 829.4 s, and 41, 41, 46, and 50 at 839.1 s (`qlm-control-first`). `83` overshoots and stays above the temperature for minutes.
- **Guess:** the 8330A sends `81` and `83`, the 8351B adds `82`, and the subwoofers send only `83`. That matches the meters: `43` the HF band, `44` the mid, and `45` the LF. So each may be a reading for one amplifier band: `81` HF, `82` mid, and `83` LF.

**The temperature itself restarts low at a wake.** The Left 8351B read 42 °C in standby and 25 °C in its first frame after the wake. It read 41 °C again about 20 s later (`standby-wake`). After hours in standby, it read 20 °C at the wake, and 26 °C ten seconds later (`qlm-control-first`, 829.4 s). No part cools that fast, so the reading is filtered from a low start. Treat a temperature in the first minute after a wake as unsettled.

## `88`

- **Only the 8351B sends it**, in every frame, on or in standby. Its first byte is always `00`.
- **It is steady on each monitor, and differs between them.** The Left reads 73 to 76, and the Right 78 to 82, in every capture on both days. The Right also runs 3 °C warmer.
- **In standby it holds, and stops jittering.** The Left reads 74 or 75, and the Right 79 or 80.
- **Volume, mute, dim, music, and group switches do not move it.**
- **After hours in standby, it starts low.** The Left read 70 to 72 for the 10 s after qlm's wake (`qlm-control-first`, 829.4 s). After a 15 s standby, it read 73 to 75 (`standby-wake`, 49 s).

**Guess:** a slow reading of a part that warms with use, or a supply that standby leaves on. The captures cannot tell. qlm does not decode it.

## `89`

- **Only the 8351B sends it**, in every frame. Its first byte is always `00`.
- **On, it is steady.** The Left reads 65, and the Right 67 or 68, in every capture on both days.
- **In standby, it falls 16 to 19, within one frame.** The Left reads 47, and the Right 51. Each first standby frame already has it (`standby-wake`, 35.68 s, and `qlm-standby-discover`, 31.92 s). After hours in standby, it reads 46 and 50 (`qlm-control-first`).
- **It comes back at the wake, within one frame.** The Left read 65 at 49.05 s (`standby-wake`). After hours in standby, it read 63 (`qlm-control-first`, 829.4 s).

No temperature moves 18 °C in a second. **Guess:** a supply voltage that the 8351B lowers in standby. qlm does not decode it.

## The meters

Section 8.1 lists the meters: `42` the input, `43` the HF output, `45` the LF output, and `46` the subwoofer's driver. It expects `44` on three-way models, and has never seen it (Appendix B, item 5). Its VU mapping puts the output meters' floor at `80`, gives them about a dB per count, and has `42` read before the volume.

### `44` is the 8351B's midrange

The 8351B is a three-way model. It sends `44` in every frame while it is on, and nothing else does. `44` moves with `43` and `45` at each change below, and its level sits between theirs.

### A count is about a dB

`qlm-control-first`, the Right 8351B, with music playing:

| Time | The level | `42` | `43` | `44` | `45` |
| --- | --- | --- | --- | --- | --- |
| 274.74 s | the knob's −40 dB | 231 | 201 | 204 | 211 |
| 279.29 s | qlm's −60 dB, from 274.76 s | 231 | 182 | 184 | 190 |
| 538.33 s | the knob's −43.3 dB | 229 | 195 | 198 | 204 |
| 541.18 s | dim, −63.5 dB, from 538.34 s | 229 | 173 | 180 | 184 |
| 639.27 s | unmuted | 229 | 193 | 200 | 204 |
| 640.37 s | muted at 638.71 s | 229 | 128 | 128 | 128 |

- **The output meters fall 18 to 22 counts for each 20 dB step.** As qlm followed the knob from −60 to −66 dB, `43` and `44` fell 6. `45` follows the music's bass, so it varies more.
- **A mute takes them to `80` within 1.7 s.**
- **They settle within about 2.3 s.** The frame at 275.88 s, 1.1 s after the level, is partway.
- **`42` does not move with the volume.** It held 229 to 231 from −40 to −67 dB.
- **`42` reads the same on two models.** The 7370A feeds the Right. At 638.7 s, both read 229.

### The floors

No music plays in GLM's captures. A few short sounds do: in seven of them, `42` reads 236 or 237 on every monitor in the same frame (`startup-idle`, 28.68 s, for one). At rest, each output meter reads `80`, and now and then a count or four above it. `42` rests at `9D` to `A0` on the 8330A and the 8351B, and at `91` to `95` on the subwoofers. The spec has `89` on an 8320A. So the input's floor is its noise, and differs by model and input.

### What the captures do not show

- **`42`'s slope.** No capture changes the input by a known amount.
- **The absolute scale.** **Guess:** each meter is a level in dB below full scale, as 255 less the count. That would put the outputs' floor at −127 dB, the inputs' floors near −97 and −109 dB, and the music near −25 dB. No capture pins it.
- **`46`.** It never leaves `80`, even while the 7370A plays with `45` at 206 to 208 (`qlm-control-first`, 638 to 665 s).

### Approximate meters

Show each output as its count less `80`, in dB, over a window of about 60 dB, as section 8.1 suggests. Show the input the same way, above its model's floor. Hold a reading for about a second, since the frame changes once a second.

### What the meters showed about the control run

- **The knob's burst unmuted the 7370A.** At 373.12 s, qlm followed the knob's first turn with `2B 04` to every monitor. The 7370A had been muted in GLM. Its `45` rose from `80` to 207 at 373.87 s. Its notes put the sub's start at 638.7 s, when the Right went silent. The meters say it played from 373.9 s.
- **After qlm's wake, every output read its floor.** From 829.4 to 839.1 s, the Right's `43`, `44`, and `45`, and the 7370A's `45`, read `80`. Their `42` read the music. qlm sent no `2B` after the wake. GLM's wake sends `2B 04` to every monitor (`standby-wake`, 49.05 s). The notes say the music came back, but not when. Later runs say why the outputs stayed down. A woken monitor waits for the level or the pair, not its mute state, and this wake sent neither ([protocol.md](protocol.md#monitors-keep-their-level-and-their-mute)).

## What qlm can use

- **`wakeSeconds`** tells a new frame from an old one, and shows how long ago a monitor woke, within 256 s.
- **`wakeSteps`** × 256 + `wakeSeconds` is how long a monitor has been up, in seconds. `wakeSteps` arrives once in 30 s, so keep the last one.
- **The meters** can drive the window's input and output bars.
- **The temperature** is unsettled for a minute after a wake.

## Open questions

These would settle them:

- **`88` and `89`.** Poll an 8351B through standby for an hour, then wake it. Watch both against the temperature.
- **`42`'s slope and the meters' scale.** Play a test tone at known levels, through one monitor.
- **The wake and the level.** Wake with qlm while music plays, and send the level alone, with no pair. Check whether the outputs leave their floor.
- **The bare `04`.** Switch a monitor on at its power switch, then apply the group with qlm. Check its first frame after.
