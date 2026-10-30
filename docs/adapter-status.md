# The adapter's status reply

GLM polls the adapter with `01 08`. This is what the reply carries, and what it answers for Phase 0 and Phase 2. Every fact comes from the Phase 0 captures. A time is seconds into that capture's `reports.txt`. **Guess:** marks a guess.

## Short answers

1. **The fields.** The reply is `01 09`, then tag-value fields, then the CRC. The fields say whether the knob and the mic are plugged in, and carry the knob's position and two mic readings. There is no status field.
2. **The knob.** The knob's position rides in tag `DF`, in tenths of a dB. GLM reads it on each poll and broadcasts the level itself as `FF 1F`. It rounds the knob to the nearest 0.5 dB.
3. **The host.** Nothing in the reply speaks of the host, and GLM sends no hello or goodbye. **Guess:** the adapter takes the host's steady polling as presence, and silence as its departure.
4. **Unplugging the knob.** The knob's fields give way to one byte, `31`. As the plug comes out, the knob's reading jumps first, and GLM follows it.

## The poll

- GLM sends `01 08` in pairs, 2.4 ms apart. A pair goes out about every 107 ms, or about 17 polls a second in every capture (`startup-idle`, from 10 s on).
- The adapter answers each poll within about 1.5 ms. Every one of the 28,257 polls in the captures got a reply, and every reply passes its CRC.

## The reply's layout

`startup-idle`, 7.29 s:

```
01 09 33 30 36 DF FF FF FC 14 F5 ED 7E
```

- `01 09` opens every reply, as for a monitor. `F5 ED` is the CRC-16/GSM of everything before it, big-endian. `7E` ends the frame. hlm's spec gives this framing.
- The reply is escaped like any frame. In `startup-idle-mic` at 8.10 s, `DE 00 2B 7D 5D F6` on the wire is `DE 00 2B 7D F6`. The knob's field is escaped too. −643 is `FF FF FD 7D`, sent as `FF FF FD 7D 5D` (`sleep-wake-no-sleep`).
- After `09` come tag-value fields with no length byte. **The top two bits of a tag give its value's length:** `00` none, `01` one byte, `10` two bytes, and `11` four bytes. This is an inference, not a published fact. It fits all 38,038 `08` replies in the captures, both the adapter's and the monitors' telemetry. There, tags `41` to `49` carry one byte, `81` to `8A` two, and the busy markers `06` and `07` none.

| Tag | Value | Meaning | Evidence |
| --- | --- | --- | --- |
| `30` | none | The knob is plugged in. | Every capture with the knob in |
| `31` | none | No knob. | `volume-sweep`, from 25.44 s |
| `32` | none | The mic is plugged in. | `startup-idle-mic`, `knob-sweep` |
| `33` | none | No mic. | Every other capture |
| `34` | none | Always follows `32`. **Guess:** it opens the mic's readings. | |
| `DE` | 4 bytes | A mic reading that changes on every poll | |
| `DD` | 4 bytes | A mic reading that changes about every 0.2 s | |
| `36` | none | Always follows `30`. **Guess:** it opens the knob's reading. | |
| `DF` | 4 bytes, signed | The knob's position, in tenths of a dB | `knob-sweep` |

The captures show three shapes, always in this order:

| Shape | When | Where |
| --- | --- | --- |
| `33 30 36 DF` | No mic, knob in | `startup-idle` and most captures |
| `32 34 DE DD 30 36 DF` | Mic and knob in | `startup-idle-mic`, `knob-sweep` |
| `33 31` | No mic, no knob | `volume-sweep`, from 25.44 s |

The bytes are facts. The meanings are read from when each shape appears. **Guess:** in each pair, the odd tag means "absent". No capture has the mic in with the knob out.

Nothing else is in the reply. No field changes with standby, a group switch, mute, or GLM's state. The shape holds from GLM's first poll in every capture.

### The knob: `DF`

- A signed 32-bit integer, big-endian, in tenths of a dB. It reads `0` at the top stop (`knob-sweep`, 20.17, 39.47, and 71.41 s). It reads about `−1004` at the bottom stop (33.21, 45.91, and 73.04 s).
- It is noisy at rest. In `sleep-wake-no-sleep`, it wanders from −647 to −637 over 130 s. In `sleep-wake-darkwake`, it ranges from −734 to −665 over 600 s, mostly moving a tenth at a time. That capture's notes do not say whether anyone touched the knob.
- No capture records a knob press, and no field for one appears.

### The mic: `DE` and `DD`

These appear only with the calibration mic in. Normal use has no mic, so qlm can ignore them.

- `DE` changes on every poll. The first poll of a pair comes about 105 ms after the last one, and the second only 2.4 ms after. The first usually reads higher: in 809 of 1,092 pairs in `startup-idle-mic`, and 483 of 677 in `knob-sweep`. The first `DE` after GLM opens in `startup-idle-mic` is `1B AB FB A0` (7.31 s), about 200 times its median. **Guess:** `DE` is the peak since the last read.
- `DD` changes about every 0.2 s, sometimes 0.1 s. It rarely changes between the two polls of a pair: in 16 of 618 changes in `startup-idle-mic`. **Guess:** an averaged level, updated on the adapter's own clock.
- Both stay positive, with medians near 2.3 million (`startup-idle-mic`). Their scale is unknown. Nobody recorded GLM's displayed readings.

## How knob turns reach GLM

The adapter speaks only when polled. GLM reads `DF` on each poll and broadcasts the level itself as `FF 1F`. GLM resends the level several times in every cycle, changed or not (`startup-idle`, from 7.99 s).

**The knob leads every level change.** `knob-sweep` has 124 level changes. 109 follow a new `DF` read in the same pair of polls, 1.7 to 42 ms after the reply (median 2.2 ms). 14 come a cycle late and use the value from the pair before. The last one is GLM's own level when it opens (7.19 s). No level change comes before the `DF` change that explains it.

`knob-sweep`, a turn to the top:

| Reply | `DF` | Level sent | dB |
| --- | --- | --- | --- |
| 19.237 s | −417 | 19.241 s, `01 13 B5` | −41.5 |
| 19.570 s | −287 | 19.585 s, `04 CF 8B` | −28.5 |
| 19.728 s | −137 | 19.737 s, `1B 0D 7A` | −13.5 |
| 19.839 s | −36 | 19.844 s, `55 8C 4A` | −3.5 |
| 20.055 s | −11 | 20.066 s, `72 14 81` | −1.0 |
| 20.165 s | 0 | 20.181 s, `7F FF FF` | 0.0 |

### The mapping

- **The level in dB is `DF` / 10, rounded to the nearest 0.5 dB.** For example, −123 gives −12.5 dB (24.74 s), −113 gives −11.5 dB (24.41 s), and −29 gives −3.0 dB (23.07 s). `DF` is a whole number of tenths, so no value falls halfway between two steps.
- At −100 dB and below, GLM sends `00 00 08`. `DF` −1000 gives `00 00 08` (`knob-sweep`, 32.99 s), and so does −999, rounded to −100 dB (`standby-wake`, 2.38 s). −995 gives −99.5 dB, `00 00 58` (`standby-wake`, 25.50 s).
- 0 dB is `7F FF FF`.
- **The level is `floor(10^(dB/20) × 0x7FFFFF)`, give or take one count.** The captures hold 200 distinct levels besides `7F FF FF` and `00 00 08`. The formula gives 195 of them exactly, and the other five within one count. The plan's `× 2²³` misses eleven. The exact arithmetic is unknown. **Guess:** GLM works in single precision. Phase 2 must match GLM byte for byte, so this needs pinning down.

### What GLM does with the knob

- **GLM ignores the knob's position when it opens.** It opens at its own level, `00 31 07` (−56.5 dB): in `startup-idle` with `DF` at −1004 (7.99 s), in `startup-idle-mic` with −775 (7.99 s), and in `knob-sweep` with −775 (7.19 s).
- **At the knob's first move, GLM jumps to the knob's position.** In `knob-sweep` at 18.95 s, it went from −56.5 dB to −73.0 dB. In `startup-idle` at 38.48 s, it went from −56.5 dB to `00 00 08`. That capture's notes do not mention the knob. The jump can go up as far as 0 dB if the knob sits at the top. qlm's ceiling still clamps it.
- **GLM ignores small jitter at rest.** In `sleep-wake-no-sleep`, `DF` wanders from −647 to −637 for 130 s, and the level stays at `00 13 84` (−64.5 dB), though −637 rounds to −63.5 dB. Yet in `sleep-wake-darkwake` GLM follows the slow wander, with 37 level changes between −73.0 and −66.5 dB. The rule that tells a turn from jitter is not known. **Guess:** a larger move opens a window of a few seconds in which GLM follows every change. In `standby-wake`, GLM follows from 0.8 to 4.3 s and from 19.1 to 21.5 s, then stops following changes of the same size.
- **Each knob-driven change brings a burst of `2B` frames,** to every monitor and as `01 2B 00` to address `01`. In `knob-sweep`, 168 of the 169 `01 2B` frames come within 150 ms of a `DF` change. The other comes as GLM opens (7.20 s). This explains the `2B` bursts in `standby-wake` at 1.0 to 4.3, 19.6, and 25.5 s: each follows a `DF` change. In `mute-dim`, `01 2B` carries mute all: `01` at 46.19 s, then `00` at 48.60 s. **Guess:** GLM refreshes the mute and LED state on every knob move.

## How the adapter knows a host is present

**Nothing in this reply tells it. Nothing in the captures is an explicit hello or goodbye.** **Guess:** the adapter infers a host from the host's steady traffic, and infers its departure from silence.

- The reply carries only the mic and the knob. No field tracks the host.
- When GLM opens, and again after a replug, it sends the same short sequence: `01 08`, `01 22`, `01 39`, and `01 19 01`. Then come broadcast wakes, `FF 3A 03 7F` and `FF 3A 03 01`, three times. Then come `01 51 82` and `01 2B 00`. This is in `startup-idle` at 7.29 to 7.99 s, `unplug` at 68.34 to 69.04 s, and `unplug-proxy-hang` at 106.24 to 106.94 s.
  - `01 22` returns `GLM Adapter 0 0000 0104 06113`. genlc calls opcode `22` a hardware query.
  - `01 39` returns the system info: `model-GLM Adapter`, `ver-1.4.0.6113`, `hw-0.0.202`, and a build date of 2025-05-19.
  - `01 19 01` returns the adapter's serial.
  - `01 51 82` returns the ASCII text `219000`, even with no mic in (`startup-idle`, 7.96 s). genlc calls opcode `51` the mic serial query.
  - None of these is plainly a "host is here" message. **Guess:** the adapter may treat one of them as the start of a session. Nothing in the captures shows that.
- **GLM sends nothing on quit.** Its last frame is an ordinary poll (`quit-glm`, 9.2 s). So the adapter can learn that the host left only from silence. Closing GLM's HID handle sends nothing on USB. The proxy does not forward USB suspend, so the captures cannot show whether a real Mac sleep is another signal.
- **While GLM runs, it never goes quiet for long.** The longest gap between any two reports from GLM is 0.22 s, when it opens (`startup-idle`, 7.74 s). The longest gap between `01 08` polls is 1.70 s, during a group switch (`group-switch-main-2x1-main-4x2`, 36.07 s). The next longest is 1.22 s, during a wake (`standby-wake`, 47.37 s).
- hlm's spec, as the plan sums it up: the adapter broadcasts `F0 1F 00 00 00` about every 610 ms while it defers to a host. It takes over about 2.6 s after the host goes quiet. GLM's longest silences fit inside that.
- **What the captures cannot show:** which frames reset the adapter's timer, any report or only `01 08`. They cannot show the timeout either. The takeover happens on the monitor bus, which USB cannot see. The bus tap can.
- **For qlm:** poll `01 08` as GLM does, in pairs about every 107 ms. Never pause longer than GLM does, 1.7 s. The poll is also the knob's only path to the host.

## Unplugging and plugging in the knob

### Unplugging (`volume-sweep`)

- From 25.11 to 25.44 s, `DF` moves: −1004, −999, −996, −992, −974, then −988. **Guess:** the jack's contacts slide as the plug comes out.
- At 25.44 s, `30 36 DF` gives way to `31`. The reply stays `33 31` to the end (71.76 s).
- GLM follows the transient. It moves the level from `00 31 07` (−56.5 dB) to `00 00 5E` (−99.0 dB) at 25.23 s, then to `00 00 6F` (−97.5 dB) at 25.34 s. It sends three `01 2B 00` frames between 25.23 and 25.45 s, then no more.
- GLM holds `00 00 6F` until the drag starts, at about 28.0 s. **This corrects `volume-sweep`'s notes,** which have the drag starting at 25.2 s, from `00 31 07`.
- Once `31` appears, GLM unlocks its on-screen volume, as the notes say. It keeps broadcasting its own level as before.

### Plugging back in (`standby-wake`)

- The knob went back in before the capture started, so the moment of the plug is in no capture.
- The first poll, at 0.06 s, already shows `30 36 DF`, with `DF` at −1001.
- For the first 2.7 s, `DF` wanders from −1002 up to −982 and back. **Guess:** the jack settling, or a hand on the knob.
- GLM follows: −98.0 dB at 1.94 s, −99.5 dB at 2.05 s, then `00 00 08` at 2.38 s. `2B` bursts come from 0.77 to 4.28 s.

## Open

- The rule GLM uses to tell a knob turn from jitter.
- What `DE` and `DD` measure, and their scale.
- The adapter's host timeout, and which frames reset it. This needs the bus tap.
- The exact arithmetic behind the level.
- Whether the adapter acts on the knob itself while a host is present. **Guess:** it does not. When GLM opens at −56.5 dB with the knob at −77.5 dB, an adapter acting on the knob would send a conflicting level. USB cannot show the bus.

## Sources

- The captures in `captures/`, decoded from `reports.txt` with the CRC checked on every frame.
- hlm's spec, revision 13, for the framing, the CRC, and the adapter's `F0 1F` and 2.6 s takeover, as summed up in [plan.md](plan.md).
- genlc's `const.py`, for the names of opcodes `22` and `51`. Facts only. No code was ported.
