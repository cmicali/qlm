# The adapter's status reply

GLM polls the adapter with `01 08`. This is what the reply carries, and what it answers for Phase 0 and Phase 2. Every fact comes from the Phase 0 captures. A time is seconds into that capture's `reports.txt`. **Guess:** marks a guess.

## Short answers

1. **The fields.** The reply is `01 09`, then tag-value fields, then the CRC. The fields say whether the knob and the mic are plugged in, and carry the knob's position and two mic readings. There is no status field.
2. **The knob.** The knob's position rides in tag `DF`, in tenths of a dB. GLM reads it on each poll and broadcasts the level itself as `FF 1F`. It rounds the knob to the nearest 0.5 dB.
3. **The host.** Nothing in the reply speaks of the host, and GLM sends no hello or goodbye. **Guess:** the adapter takes the host's steady polling as presence, and silence as its departure.
4. **Unplugging the knob.** The knob's fields give way to one byte, `31`. As the plug comes out, the knob's reading jumps first, and GLM follows it.

## The poll

- GLM sends `01 08` in pairs, 2.4 ms apart. A pair goes out about every 107 ms, or about 17 polls a second in every capture (`startup-idle`, from 10 s on).
- The second poll of a pair rarely brings news. `DF` differs between the two in 22 of the 14,096 pairs in the captures.
- The adapter answers each poll within about 1.5 ms. Every one of the 28,257 polls in the captures got a reply, and every reply passes its CRC.

## The reply's layout

`startup-idle`, 7.29 s:

```
01 09 33 30 36 DF FF FF FC 14 F5 ED 7E
```

- `01 09` opens every reply, as for a monitor. `F5 ED` is the CRC. `7E` ends the frame. The plan's [The adapter is a thin bridge](plan.md#the-adapter-is-a-thin-bridge) has the framing.
- The reply is escaped like any frame. A knob value of −643 is `FF FF FD 7D`, sent as `FF FF FD 7D 5D` (`sleep-wake-no-sleep`).
- After `09` come tag-value fields with no length byte. **The top two bits of a tag give its value's length:** `00` none, `01` one byte, `10` two bytes, and `11` four bytes. This is an inference, not a published fact. It fits all 38,038 `08` replies in the captures, both the adapter's and the monitors' telemetry. There, tags `41` to `49` carry one byte, `81` to `8A` two, and the busy markers `06` and `07` none.

| Tag | Value | Meaning |
| --- | --- | --- |
| `30` | none | The knob is plugged in. |
| `31` | none | No knob. |
| `32` | none | The mic is plugged in. |
| `33` | none | No mic. |
| `34` | none | Always follows `32`. **Guess:** it opens the mic's readings. |
| `DE` | 4 bytes | A mic reading that changes on every poll |
| `DD` | 4 bytes | A mic reading that changes about every 0.2 s |
| `36` | none | Always follows `30`. **Guess:** it opens the knob's reading. |
| `DF` | 4 bytes, signed | The knob's position, in tenths of a dB |

The captures show three shapes, always in this order:

| Shape | When | Where |
| --- | --- | --- |
| `33 30 36 DF` | No mic, knob in | `startup-idle` and most captures |
| `32 34 DE DD 30 36 DF` | Mic and knob in | `startup-idle-mic`, `knob-sweep` |
| `33 31` | No mic, no knob | `volume-sweep`, from 25.44 s |

The meanings of `30` to `33` come from when each shape appears. No capture has the mic in with the knob out.

Nothing else is in the reply. No field changes with standby, a group switch, mute, or GLM's state. The shape holds from GLM's first poll in every capture.

### The knob: `DF`

- A signed 32-bit integer, big-endian, in tenths of a dB. It reads `0` at the top stop (`knob-sweep`, 20.17, 39.47, and 71.41 s). It reads about `−1004` at the bottom stop (33.21, 45.91, and 73.04 s).
- It wanders by a tenth or two at rest.
- No capture records a knob press, and no field for one appears.

### The mic: `DE` and `DD`

These appear only with the calibration mic in. Normal use has no mic, so qlm can ignore them.

- `DE` changes on every poll. The first poll of each pair usually reads higher than the second: in 809 of 1,092 pairs in `startup-idle-mic`, and 483 of 677 in `knob-sweep`. The first `DE` after GLM opens in `startup-idle-mic` is `1B AB FB A0` (7.31 s), about 200 times its median. **Guess:** `DE` is the peak since the last read.
- `DD` changes about every 0.2 s, sometimes 0.1 s. It rarely changes between the two polls of a pair: in 16 of 618 changes in `startup-idle-mic`. **Guess:** an averaged level, updated on the adapter's own clock.
- Both stay positive, with medians near 2.3 million (`startup-idle-mic`).

## How knob turns reach GLM

GLM resends the level several times in every cycle, changed or not (`startup-idle`, from 7.99 s).

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

- **The level in dB is `DF` / 10, rounded to the nearest 0.5 dB.** For example, −123 gives −12.5 dB (`knob-sweep`, 24.74 s). `DF` is a whole number of tenths, so no value falls halfway between two steps.
- At −100 dB and below, GLM sends `00 00 08`. Both −1000 (`knob-sweep`, 32.99 s) and −999 (`standby-wake`, 2.38 s) give `00 00 08`. 0 dB is `7F FF FF`.
- **The level is `floor(10^(dB/20) × 0x7FFFFF)`, give or take one count.** The formula gives 196 of the 200 captured levels between 0 and −99.5 dB exactly, and the other four within one count. `× 2²³` misses ten.
- **The captures hold the level for every 0.5 dB step from 0 to −99.5 dB,** exactly one each. A table taken from them matches GLM byte for byte, with no arithmetic to pin down.

### What GLM does with the knob

- **GLM ignores the knob's position when it opens.** It opens at its own level, `00 31 07` (−56.5 dB): in `startup-idle` with `DF` at −1004 (7.99 s), and in `startup-idle-mic` with −775 (7.99 s).
- **At the knob's first move, GLM jumps to the knob's position.** In `knob-sweep` at 18.95 s, it went from −56.5 dB to −73.0 dB. In `startup-idle` at 38.48 s, it went from −56.5 dB to `00 00 08`. The jump can go up as far as 0 dB if the knob sits at the top. qlm's ceiling still clamps it.
- **GLM ignores small jitter at rest.** In `sleep-wake-no-sleep`, `DF` wanders from −647 to −637 for 130 s. The level stays at `00 13 84` (−64.5 dB), though −637 rounds to −63.5 dB.
- **But GLM follows a slow wander.** In `sleep-wake-darkwake`, `DF` ranges from −734 to −665 over 600 s, mostly a tenth at a time. GLM makes 37 level changes between −73.0 and −66.5 dB. The notes do not say whether anyone touched the knob. **Guess:** a larger move opens a window of a few seconds in which GLM follows every change. In `standby-wake`, GLM follows from 0.8 to 4.3 s and from 19.1 to 21.5 s, then ignores changes of the same size.
- **Each knob-driven change brings a burst of `2B` frames,** to every monitor and as `01 2B 00` to address `01`. In `knob-sweep`, 168 of the 169 `01 2B` frames come within 150 ms of a `DF` change. The other comes as GLM opens (7.20 s). **Guess:** GLM refreshes the mute and LED state on every knob move.
- **For qlm, a suggestion:** send a new level only when the rounded level changes, with a few tenths of hysteresis. Then jitter at rest sends no level and no `2B` burst.

## How the adapter knows a host is present

- When GLM opens, and again after a replug, it sends the same short sequence. This is in `startup-idle` at 7.29 to 7.99 s, `unplug` at 68.34 to 69.04 s, and `unplug-proxy-hang` at 106.24 to 106.94 s. None of it is plainly a "host is here" message.

  | Frame | Reply |
  | --- | --- |
  | `01 08` | The status reply |
  | `01 22` | `GLM Adapter 0 0000 0104 06113`. genlc calls opcode `22` a hardware query. |
  | `01 39` | The system info: `model-GLM Adapter`, `ver-1.4.0.6113`, `hw-0.0.202`, and a build date of 2025-05-19 |
  | `01 19 01` | The adapter's serial |
  | `FF 3A 03 7F`, `FF 3A 03 01`, three times | None. These wake the monitors. |
  | `01 51 82` | ASCII `219000`, even with no mic in. genlc calls opcode `51` the mic serial query. |
  | `01 2B 00` | `01 09` |

- **GLM sends nothing on quit.** Its last frame is an ordinary poll (`quit-glm`, 9.2 s). So the adapter can learn that the host left only from silence. The proxy does not forward USB suspend, so the captures cannot show whether a real Mac sleep is another signal.
- **While GLM runs, it never goes quiet for long.** The longest gap between any two reports from GLM is 0.22 s, when it opens (`startup-idle`, 7.74 s). The longest gap between `01 08` polls is 1.70 s, during a group switch (`group-switch-main-2x1-main-4x2`, 36.07 s). The next longest is 1.22 s, during a wake (`standby-wake`, 47.37 s).
- The plan's [The host is the bus master](plan.md#the-host-is-the-bus-master) has the adapter take over about 2.6 s after the host goes quiet. GLM's longest silences fit inside that.
- **For qlm:** poll `01 08` about every 107 ms, as GLM does, and never pause longer than 1.7 s. The poll is also the knob's only path to the host. GLM polls in pairs, but the second poll rarely brings news. Single polls would halve the traffic. Whether they hold the adapter as well is untested.

## Unplugging and plugging in the knob

### Unplugging (`volume-sweep`)

- From 25.11 to 25.44 s, `DF` moves: −1004, −999, −996, −992, −974, then −988. **Guess:** the jack's contacts slide as the plug comes out.
- At 25.44 s, `30 36 DF` gives way to `31`. The reply stays `33 31` to the end (71.76 s).
- GLM follows the jump. It moves the level from `00 31 07` (−56.5 dB) to `00 00 5E` (−99.0 dB) at 25.23 s, then to `00 00 6F` (−97.5 dB) at 25.34 s. It holds `00 00 6F` until the drag starts, at about 28.0 s.
- Once `31` appears, GLM unlocks its on-screen volume, as the notes say. It keeps broadcasting its own level as before.

### Plugging back in (`standby-wake`)

- The knob went back in before the capture started, so the moment of the plug is in no capture.
- The first poll, at 0.06 s, already shows `30 36 DF`, with `DF` at −1001.
- For the first 2.7 s, `DF` wanders from −1002 up to −982 and back. **Guess:** the jack settling, or a hand on the knob.
- GLM follows: −98.0 dB at 1.94 s, −99.5 dB at 2.05 s, then `00 00 08` at 2.38 s.

## Open

- The rule GLM uses to tell a knob turn from jitter.
- What `DE` and `DD` measure, and their scale. Nobody recorded GLM's displayed readings.
- The adapter's host timeout, and which frames reset it: any report, or only `01 08`. The takeover happens on the monitor bus, which USB cannot see. The bus tap can.
- Whether one poll per cycle holds the adapter as well as GLM's pairs.
- Whether the adapter acts on the knob itself while a host is present. **Guess:** it does not. When GLM opens at −56.5 dB with the knob at −77.5 dB, an adapter acting on the knob would send a conflicting level.

## Sources

- The captures in `captures/`, decoded from `reports.txt` with the CRC checked on every frame.
- hlm's spec, revision 13, through [plan.md](plan.md): the framing, the CRC, and the adapter's takeover.
- genlc's `const.py`, for the names of opcodes `22` and `51`. Facts only. No code was ported.
