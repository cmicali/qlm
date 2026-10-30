# The GLM adapter protocol

A PR that learns a protocol fact adds it here, with its source.

This is what qlm knows about the protocol between a host, the GLM adapter, and the monitors: the USB side, the bus frames, the replies, the timing, and the sequences GLM and qlm send. Three docs hold more detail, and this one links to them rather than repeat them:

- [adapter-status.md](adapter-status.md) decodes the adapter's reply to `01 08`, and how the knob reaches the host.
- [refused-frames.md](refused-frames.md) covers each frame GLM sends that qlm does not, and GLM's group apply frame by frame.
- [telemetry.md](telemetry.md) covers each telemetry tag and the meters.

## How to read it

- **Every fact names its source**, in one of these forms:
  - A capture in `captures/`, with a time in seconds into its `reports.txt`. Each capture's `notes.md` says what happened when.
  - A test, by its name.
  - A pull request in cmicali/qlm, as #N. An open PR is marked "open". What it describes is not on main yet.
  - A section of hlm's spec, as hlm §N. That is `docs/Genelec GLM Protocol.13.md` in robcazzaro/hlm, revision 13, at commit `c08ced9`.
  - genlc's code, for a fact the plan took from it.
- **hlm, genlc, and espgensam are GPL-3.0.** This doc states their facts in its own words. It copies no text or code from them.
- **"In the captures"** means all 20 scenarios in `captures/`. A count comes from decoding every report in them, with each frame's CRC checked.
- **Guess:** marks a guess. Section 9 lists the open questions.
- Bytes are hex. A frame is written as its address and its payload, without the CRC and the flag. `FF 1F 00 31 07` is the volume broadcast at −56.5 dB.
- **The system in the captures:** two 8351B (the Left and the Right), two 8330A, a 7370A, and a 7350A ([telemetry.md](telemetry.md#sources)). Main 2x1 has the two 8351B and the 7370A. Main 2x2 adds the 7350A. Main 4x2 adds the two 8330A ([measurement.md](measurement.md#the-run-for-main-2x1), and its table in [The other groups](measurement.md#the-other-groups)).

## 1. USB and HID

### The device

- **The adapter is USB vendor `1781`, product `0E39`** (the device descriptor in every capture; `testTheAdapterDescriptorsMatchTheReportLayer`).
- **Its product string is `Gnet Adapter`** (the string descriptor in `unplug` and `unplug-proxy-hang`; [captures/README.md](../captures/README.md)).
- It is a full-speed USB 1.1 device ([captures/README.md](../captures/README.md); `bcdUSB` 1.10 in the device descriptor).
- It has one HID interface with two interrupt endpoints: IN `81` and OUT `03`. Each takes 64 bytes and polls every 1 ms (the configuration descriptor at the top of `startup-idle`'s `reports.txt`).
- **The HID report descriptor** has the vendor usage page `FFA0`, no report IDs, a 64-byte input report, a 64-byte output report, and a 1-byte feature report (`unplug` and `unplug-proxy-hang`; `testTheAdapterDescriptorsMatchTheReportLayer`).
- No capture shows the feature report in use. The only class request in them is the host's Set Idle (the control requests at the top of each `reports.txt`).
- On the Mac, the system's HID driver owns the adapter's interface. GLM opens the HID device through the HID library, without seizing it. qlm opens it only seized (#12, #21).

### Reports

- **Host to adapter, each output report is `80` plus the frame's length, then the frame, then zeros** to 64 bytes. Every output report in the captures has this form (`testEveryOutputReportRepacksByteForByte`; `testPacksTheAdapterPollAsCaptured`).
- genlc's leading `00` is hidapi's report-ID byte, not data (genlc's `transport.py`).
- **Adapter to host, each input report starts with `3F`**, whatever the frame's length. The frame follows. Zeros pad the report after the flag (`testEveryScenarioReads`; `testReadRejectsABadInputReport`).
- **A reply that does not fit runs on into the next report.** In the captures, only replies to `39` do: 207 of them, and none spans three reports. The adapter's own system info is a 74-byte frame across two reports (`startup-idle`, 7.300 and 7.301 s; `testReadsTheAdapterSystemInfoAcrossTwoReports`). A monitor's runs about 66 bytes (`QLMFrame.h`).
- qlm accepts a reply across three reports, as genlc does (`QLMReport.h`; `testReadStopsAfterThreeReportsWithNoFlag`).
- **One frame per report.** No report in the captures carries more than one (`testEveryOutputReportRepacksByteForByte`, `testEveryReplyReencodesByteForByte`).
- **The longest frame qlm sends, a PEQ band, fits one report** even with every byte escaped (`testRefusesAFrameLongerThanOneReport`).
- **The host keeps one request in flight.** Every reply in `startup-idle` and `qlm-first-discover` follows its own request (#33). qlm does the same (`QLMReportLink.h`).
- The Pi proxy does not forward USB suspend. So no capture shows what the adapter does when the host sleeps ([captures/README.md](../captures/README.md); `sleep-wake-darkwake`'s notes).

## 2. Framing

- **A frame is the address byte, the payload, the CRC, and the flag `7E`.** The payload's first byte is the opcode (hlm §1; `testEncodesTheKeepAliveFromSection7`).
- **The CRC is CRC-16/GSM**: polynomial `1021`, initial value 0, no reflection, and a final XOR of `FFFF` (hlm §2; `QLMCRC.h`; `testCheckValue`).
- It covers the unescaped address and payload, and goes out big-endian (hlm §2; `testBusFrames`).
- **Escaping:** in the payload and the CRC, `7E` goes out as `7D 5E`, and `7D` as `7D 5D`. The CRC is computed first (hlm §1, §2; `testEscapesThePayloadAndRoundTrips`, `testEscapesTheCRC`).
- The adapter escapes its own replies too. A knob reading of `FF FF FD 7D` comes as `FF FF FD 7D 5D` (`sleep-wake-no-sleep`; [adapter-status.md](adapter-status.md#the-replys-layout)).
- **Every frame in the captures passes its CRC:** 67,961 sent and 62,671 received (each decoded as `testEveryScenarioReads` reads it).
- Multi-byte integers are big-endian. PEQ coefficients are little-endian floats (hlm §4; `testWakeStepsAreBigEndian`).
- **On the bus**, frames travel on RS-485 as 9-bit characters, at about 288,000 baud. The ninth bit marks the address byte (hlm §1). No USB report carries a ninth bit, so the adapter adds it (every output report in the captures).
- **Unverified: whether the address byte is ever escaped.** qlm sends it bare. No capture has an address above `19`, so none shows a `7D` or `7E` address. qlm's encoder refuses both, and its leases skip them (`testLeasesNoAddressThatNeedsEscapingOrIsTheMulticast`; #9).

## 3. Addresses and leases

### The addresses

| Address | What it is | Source |
| --- | --- | --- |
| `FF` | A host's broadcast. GLM sends the probe, the keep-alive, the volume, `2D 00`, `3D 00 00`, and the power steps to it. | hlm §3; the captures |
| `F0` | The adapter's multicast. A host sends every lease to it. Standalone, the adapter sends its own volume and power steps on it. | hlm §3, §9; every lease in the captures |
| `01` | Every reply comes from `01`. A host also reaches the adapter itself at `01`. | hlm §3, §8; `startup-idle`, 7.293 s; `testEveryReplyReencodesByteForByte` |
| `02` to `FE` | Session IDs, leased to monitors. qlm leases none of `7D`, `7E`, and `F0`. | hlm §3; `QLMAddressIsLeasable` |

### Discovery and the lease

- **The probe `FF FE` is answered by one monitor that holds no lease**, with `09` and its 3-byte hardware ID. With none left, the adapter answers `01 7E` (hlm §7, §9; `startup-idle`, 8.419 to 8.492 s).
- **The lease is `F0 02`, the hardware ID, and the session.** The monitor answers `09` and the session (hlm §7, §8; `startup-idle`, 8.432 s; `testSessionAckAndHardwareID`).
- **A monitor that holds a lease does not answer the probe.** Once every monitor holds one, every probe gets `01 7E`: all 1,028 in `sleep-wake-darkwake`, for one. While qlm's `poll` held all six leases, every probe got `01 7E` (`qlm-standby-discover`'s notes).
- So a host finds only monitors without a lease. **TRAP:** a monitor still holding an earlier host's lease stays hidden. A host that leases from `02` again may give that session to a second monitor. Then two monitors take one monitor's frames (#17; [measurement.md](measurement.md#wait-between-hosts)).
- #32 (open) handles it: before its first probe, qlm asks each monitor it knew for its serial at its old session. The same serial means the monitor still holds that lease, and qlm takes it back.
- **The hardware ID maps one to one to the serial** in every capture, so qlm matches monitors by hardware ID (#9; #8).
- **A setup node's `Serial` is its monitor's hardware ID**, read big-endian, in decimal (`startup-idle`, the leases at 8.432 to 8.481 s; #8).
- The serial from `19 01` is a model prefix and eight digits. It never ends in the setup's `Serial` (#8). Serials are 14 or 15 characters (#9; `QLMReplies.h`).

### How GLM counts sessions

- **GLM counts up from `02` at each launch, one per lease**, in the order the monitors answer the probe. All three launches lease `02` to `07`, in the same order (`startup-idle`, 8.432 s; `startup-idle-mic`, 8.443 s; `knob-sweep`, 7.627 s).
- **The count runs on within a launch.** After a replug, GLM leased `08` to `0D` (`unplug-proxy-hang`, 107.137 s) and `14` to `19` (`unplug`, 69.241 s). After a wake, it leased `12` to `17` (`standby-wake`, 47.378 s).
- **qlm counts up from `02` at each start**, skipping `7D`, `7E`, and `F0` (#9; `QLMAddressIsLeasable`). Its first discovery found the six in GLM's order, and leased them GLM's sessions (`qlm-first-discover`, 56.427 to 56.536 s). Within a run it counts on: its wake re-leased three monitors at `06` to `08` (`qlm-control-first`, 828.326 to 828.371 s).

### When a monitor loses its lease

- **A monitor that wakes from standby loses its lease** and answers the next probe:
  - At a wake, all six. GLM leased them `12` to `17`, 0.81 s after its first wake pair (`standby-wake`, 46.565 and 47.378 s).
  - At qlm's wake, all three in the run. Polls to their old sessions got `01 7E` (`qlm-control-first`, 828.29 to 828.37 s).
  - In a group switch, each monitor that joins the group from standby: the 7350A in 2x1 to 2x2, both 8330A and the 7350A in 2x1 to 4x2, and both 8330A in 2x2 to 4x2 (the leases in `group-switch-main-2x1-main-2x2`, 10.418 s; `group-switch-main-2x1-main-4x2`, 36.254 to 36.457 s; and `group-switch-main-2x2-main-4x2`, 11.562 and 11.575 s).
- **A monitor that stays on keeps its session.** The switches from 4x2 to 2x1, 4x2 to 2x2, and 2x2 to 2x1 lease nothing (each `group-switch-*` capture).
- **Frames sent to a lost session get `01 7E`.** GLM's block to a monitor that has just woken gets it from the old session (`group-switch-main-2x1-main-4x2`, 35.84 to 36.38 s; `standby-wake`, from 46.631 s).
- **A monitor in standby may drop its lease over and over.** In `standby-wake`, the Right 8351B answered the probe every 3 s in standby, and GLM leased it `0E`, `0F`, `10`, and `11` (37.365 to 45.959 s). In `qlm-standby-discover`, no monitor did in GLM's 10 s of standby.
- **A monitor that misses four polls in a row is dropped.** GLM polls again at once after a miss, about 9 ms apart. After the fourth miss it stops polling that session, and the probe finds the monitor again (`standby-wake`, 35.077 to 35.105 s, then 37.365 s; hlm §3). Most retries get their answer on the second poll (`standby-wake`, 45.973 s).
- qlm drops a monitor after four missed cycles and a burst of four more polls (`QLMSystem.h`).
- **Monitors drop a host's leases once the host goes quiet.** USB cannot show why.

  | Monitors | After GLM | After qlm | Source |
  | --- | --- | --- | --- |
  | On | within 42 s | within 23 s | `qlm-first-discover` |
  | In standby | within 210 s | within 88 s and 68 s | `qlm-standby-discover` |
  | On, across an unplug of the adapter | within 9 s | | `unplug`, 60.4 to 69.2 s |

  **Guess:** the adapter's take-over, about 2.6 s after the host goes quiet, ends them. Across the unplug, the adapter lost power, and its restart may have.
- **A wait between hosts avoids the TRAP above:** 1 minute with every monitor on, and 4 minutes with any in standby ([measurement.md](measurement.md#wait-between-hosts)).

## 4. Opcodes

Every opcode in the captures, and the ones qlm never sends. "Sends" means qlm's allowlist accepts it and System sends it. The allowlist accepts by opcode, with finer checks on `02`, `10`, `2D`, `3A`, `3C`, `3E`, and `42` (`QLMFrameAllows`; `testTheAllowlistAcceptsWhatQLMSends`). The golden test pins the refused set: `05`, `43`, `4B`, and `22` and `51` to the adapter (`testEveryOutputReportRepacksByteForByte`). [refused-frames.md](refused-frames.md) has the detail on each refused frame.

Every frame qlm sent in its three runs on the adapter is one GLM sends (`qlm-first-discover`, `qlm-standby-discover`, and `qlm-control-first`, their notes; `QLMControlRunTests`).

| Frame | To | Reply | Who sends it, and when | qlm | Source |
| --- | --- | --- | --- | --- | --- |
| `FE` | `FF` | A hardware ID, or `01 7E` | GLM, each cycle, and back to back at discovery | Sends | hlm §7; `startup-idle`, 8.419 s |
| `02` ID ID ID session | `F0` | `09` session | GLM, after each probe answer | Sends, only a leasable session | hlm §7; `testLeasesNoAddressThatNeedsEscapingOrIsTheMulticast` |
| `04` | `FF` | None | GLM, only in a DSP pass | Sends, in an apply | `startup-idle`, 8.534 s; #12 |
| `05 04 00 00 00 FF FF EA 00 01 90 00 02 DA` | Session | `09` | GLM, in every block at launch, and in a switch's routing pass | Refused, never-send | hlm §7; [refused-frames.md](refused-frames.md#05-04--the-generator-stop) |
| `08` | Session | Telemetry, a bare `09`, a busy marker, or `01 7E` | GLM, each cycle | Sends | hlm §7; [telemetry.md](telemetry.md) |
| `08` | `01` | The adapter's status | GLM, in pairs, about every 107 ms | Sends | [adapter-status.md](adapter-status.md) |
| `10 01 00` word | Session | `09` | GLM, in each block | Sends | hlm §6; #15 |
| `10 01 05` word | | | Never in the captures. hlm's store sequence sends it. | Refused | hlm §9; `testTheAllowlistRefusesWhatQLMNeverSends` |
| `10 01 09 00 00 00` | Session | `09` | GLM, in each block | Sends | hlm §6; the captures |
| `10 02` samples | Session | `09` | GLM, in each block | Sends | hlm §6; #8 |
| `10 0E` slot, five floats, `00` | Session | `09` | GLM, twenty or more in each block | Sends | hlm §5; #10 |
| `15` | | | Never in the captures | Refused, never-send | hlm §7; AGENTS.md |
| `17 01` | Session | `09` | GLM, first in each block | Sends | hlm §7; `startup-idle`, 8.538 s |
| `19 01` | Session or `01` | The serial, in ASCII | GLM, at discovery, after each block, and to the adapter at open | Sends | hlm §7, §8; `startup-idle`, 7.304 s |
| `1F` word | `FF` | None | GLM, each cycle and at once on a change. The adapter, standalone, on `F0`. | Sends, under the ceiling | hlm §7, §9; `volume-sweep` |
| `22` | `01` | The adapter's identity, in ASCII | GLM, once per connection | Refused | [refused-frames.md](refused-frames.md#01-22) |
| `2B` value | Session | `09` | GLM, in rounds of mute state | Sends | hlm §7; `mute-dim` |
| `2B 00` or `2B 01` | `01` | `09` | GLM: mute all, unmute all, startup, the knob, a switch's tail, and a wake | Sends | [refused-frames.md](refused-frames.md#01-2b-00-and-01-2b-01) |
| `2D 00` | `FF` | None | GLM, right before `FF 3D 00 00`, each time | Sends, only this, only as a broadcast | [refused-frames.md](refused-frames.md#broadcast-2d-00-and-3d-00-00); #20 |
| `39` | Session or `01` | System info, in ASCII | GLM, at discovery, after each block, and to the adapter at open | Sends | hlm §7, §8; `startup-idle`, 7.299 s |
| `3A 01`, `3A 02`, `3A 06` | | | Never in the captures | Refused, never-send | hlm §7; AGENTS.md |
| `3A 03` step | `FF` | None | GLM: standby, wake, and a switch. The adapter, standalone, on `F0`. | Sends | hlm §7, §9; `standby-wake` |
| `3A 03` step | Session | `09` | GLM, only in a switch's routing pass | Sends | the six `group-switch-*` captures |
| `3B` value | Session | `09` | GLM, in each block, and a subwoofer's routing pass | Sends | hlm §7; the captures |
| `3C 00 00`, `3E 00 00`, `42 00 00` | Session | `09` | GLM, only to the subwoofers, in their blocks | Sends, only these, only to a session | [refused-frames.md](refused-frames.md#3c-3e-and-42-to-the-subwoofers); #24 |
| `3D 00 00` | Session | `09` | GLM, in each block | Sends | hlm §7; #20 |
| `3D 00 00` | `FF` | None | GLM, right after `FF 2D 00` | Sends | #20 |
| `40` routing | Session | `09` | GLM, in each block and the routing pass | Sends | hlm §7; #8 |
| `43 00 02`, `4B 00 00 00 01` | Session | `09` | GLM, only to the 8351B, in its blocks | Refused, until the 8351B's rate is verified | [refused-frames.md](refused-frames.md#43-00-02-and-4b-00-00-00-01-to-the-8351b) |
| `51 82` | `01` | ASCII `219000` | GLM, once per connection | Refused | [refused-frames.md](refused-frames.md#01-51-82) |

### Payloads

- **`1F`, the volume:** a 24-bit linear gain, with `7F FF FF` at 0 dB (hlm §4; `quit-glm`, 0.3 s: `0C CC CC` is −20 dB).
  - GLM's volume runs from 0 to −99.5 dB in 0.5 dB steps, 200 levels. The captures hold each one, and qlm takes its words from a table of them (`testEveryStepIsTheLevelGLMSent`; #11).
  - No formula gives all 200. `floor(10^(dB/20) × 7FFFFF)` misses four by one count, and a scale of 2²³ misses ten (`QLMCommands.c`; #11; [adapter-status.md](adapter-status.md#the-mapping)).
  - The bottom stop, −100 dB, sends `00 00 08` (`volume-sweep`, 28.36 s; `testTheBottomStopIsGLMs`).
  - `00 00 02` is the duck under an apply. It is not a level of the volume (hlm §4; `group-switch-main-4x2-main-2x1`, 12.359 s; `testEveryVolumeFrameGLMSentIsAStep`).
  - GLMProtocol caps every volume frame at the user's ceiling (`testEveryVolumeBuilderHonorsTheCeiling`, `testNoVolumeFramePassesTheCeiling`).
- **`2B`, mute and the LED:** bit 0 mutes, and bits 1 and 2 pick the LED's color (hlm §7).
  - GLM sends four values to monitors: `03` muted, `04` unmuted, and `05` then `07` to a monitor outside the active group (`mute-dim`; `knob-sweep`, 19.135 s; `QLMCommands.h`).
  - To the adapter, `2B 01` at mute all, and `2B 00` otherwise (`mute-dim`, 46.189 and 48.596 s).
- **`3A 03`, power:** `02` prepares for standby, `00` powers off, and `7F` then `01` wake (hlm §7). The power steps in [Sleep and wake](#sleep-and-wake) have the order.
- **`10 02`, the delay:** a 4-byte count of samples at 48 kHz, on every model (hlm §6).
  - A monitor's is its `Time-of-flight_Compensation` in milliseconds, times 48. 6 ms is `00 00 01 20`, 288 samples. 1.23 ms is `00 00 00 3B`, 59 (`group-switch-main-2x1-main-4x2`; #8).
  - A subwoofer's is its phase at the crossover, as a delay, rounded (hlm §6; #8). 180° at 60 Hz is 400 samples (`startup-idle`). At 85 Hz, 150° is 235, and 105° is 165, rounded from 164.7, so GLM rounds and does not floor. 90° is 141, and 165° is 259 (the subwoofers' `10 02` frames in the group switches, against `Phase(degrees)` in `Main.sam`; `QLMDSPBlockGoldenTests`).
- **`10 01 00`, the level:** a linear gain at 2²³ − 1, floored. It carries `Level_Sensitivity` plus `Group_Sensitivity` from the setup (hlm §6; #15; `testGLMFloorsTheLevelWord`).
- **`10 01 09 00 00 00`:** always these zeros, in all 73 blocks in the captures. What it sets is unknown (hlm §6).
- **`10 0E`, a PEQ band:** the slot, then `b0`, `b1`, `b2`, `−a1`, and `−a2`, normalized by `a0`, as little-endian floats, then `00` (hlm §5).
  - A flat band goes out as `1, 0, 0, 0, 0` (hlm §5; `startup-idle`, 8.553 s).
  - GLM designs in double precision, rounds the six raw coefficients to float, and normalizes in float (#10).
  - The design rate is 48 kHz for the 8330A and 12 kHz for the subwoofers (hlm §4). The 8351B's bands match a 96 kHz design to the bit, and no 48 kHz design (#10; `QLMDSPBlockGoldenTests`). No measurement confirms that rate yet.
  - GLM sends all twenty slots in every block, not only the changed ones. A subwoofer's block sends 23 PEQ frames, with slot 0 four times (#9; `QLMDSPBlockGoldenTests`).
- **`3B`, the crossover:** a big-endian 16-bit value. The captures hold `00 3C`, 60 Hz in Main 2x1, and `00 55`, 85 Hz in Main 2x2 and Main 4x2 ([refused-frames.md](refused-frames.md#43-00-02-and-4b-00-00-00-01-to-the-8351b)). hlm reads a small value such as `00 01` as full band (hlm §7).
- **`40`, the routing:** the input index, the source, a pair selector, and the AES3 channel (hlm §7).
  - Inputs 1 to 3 route as AES3: `40 00 02 00` and the channel, `01` for A, `02` for B, and `03` for both (`group-switch-main-2x1-main-4x2`; #8).
  - Each subwoofer also gets `40 01 02 00 00`. What it routes is unknown ([refused-frames.md](refused-frames.md#3c-3e-and-42-to-the-subwoofers)).
  - No group in the setup uses input 4, the analog input, so no capture shows its frame. qlm marks it unverified (#8).

## 5. Replies

### What a reply says

- **Every reply comes from `01`, and a monitor's starts with `09`** (hlm §8; `testEveryReplyReencodesByteForByte`).
- **The adapter answers every probe and unicast with exactly one frame:** the monitor's reply, or its own `01 7E` when no monitor answered. A broadcast gets none (`testEveryReplyAnswersItsRequest`; `testWhichMessagesExpectAReply`).
- **A reply names no request.** The adapter's status reply carries nothing of the `01 08` it answers, and an ack is a bare `01 09` (`startup-idle`, 7.294 s; [adapter-status.md](adapter-status.md#the-replys-layout)). Only the request just sent says what a reply answers.
- **TRAP:** `09 06` is a busy marker, and also the lease ack for session `06`. Only the request tells them apart (`QLMReplies.h`).

### The shapes

| Reply | Shape | Answers | Source |
| --- | --- | --- | --- |
| Ack | `09` | Every block frame, `2B`, `3A 03` to a session, `05 04`, and `01 2B` | hlm §8; the captures |
| Lease ack | `09` session | `02` | hlm §8; `testSessionAckAndHardwareID` |
| Hardware ID | `09` and three bytes | `FE` | hlm §8; `startup-idle`, 8.424 s |
| Telemetry | `09`, maybe `06` or `07`, `41`, the temperature, then tag-value fields | `08` | hlm §8.1; [telemetry.md](telemetry.md) |
| No new telemetry | `09` alone, or `09 06` or `09 07` | `08` | hlm §8; [telemetry.md](telemetry.md#the-frame) |
| Serial | `09` and 14 or 15 ASCII characters, with no NUL | `19 01` | hlm §8; `testTextReplies` |
| System info | `09` and NUL-terminated ASCII | `39` | hlm §8; `testSystemInfoParse` |
| The adapter's status | `09`, then `33` or `32 34 DE … DD …`, then `31` or `30 36 DF …` | `01 08` | [adapter-status.md](adapter-status.md) |
| The adapter's identity | `09`, space-separated ASCII, a space, and a NUL | `01 22` | [refused-frames.md](refused-frames.md#01-22) |
| No answer | A payload of one byte, `7E`, sent escaped: `01 7D 5E 53 97 7E` on USB | Any probe or unicast no monitor answered | `startup-idle`, 20.146 s; `testReadsTheNoAnswerFrame` |

- **qlm tells two shapes apart for its syncs.** In every capture, a reply has the adapter status's exact shape only when it answers `01 08`, and reads as system info with a `model-` field only when it answers `39` (`testOnlyStatusPollsAndSystemInfoQueriesGetTheirShapes`).
- **Why:** a reply that comes after its timeout would answer the next request. So after a timeout, the report link sends a sync whose shape the late reply cannot have, and drops replies until the sync's comes. Each open syncs too: first `01 39`, then `01 08`, since GLM's last request before it quits is `01 08` (#12, #33; `QLMReportLink.h`; `testGLMsLastRequestBeforeItQuitsIsAStatusPoll`).
- **TRAP:** the status walk reads a serial, and most other replies, as a status. Only the exact shape check tells a status apart (`QLMReplies.h`; `testOnlyTheStatusShapesAreAStatus`).

### System info

- **It has fields split by semicolons:** `c-`, `model-`, `ver-`, `hw-`, and `build-` (`startup-idle`, 7.300 s and 8.493 to 8.533 s). hlm also saw a space-separated form (hlm §8).
- **`c-` reads `0` for the adapter, `1` for the subwoofers, `2` for the 8330A, and `3` for the 8351B** (the same replies). **Guess:** it is the model's class. Telemetry's `84` reads `02` for the 8351B, though, as for the 8330A (`qlm-control-first`, 829.397 s).
- The adapter's reads `model-GLM Adapter`, `ver-1.4.0.6113`, and `hw-0.0.202`, built 2025-05-19 (`startup-idle`, 7.300 s; [adapter-status.md](adapter-status.md#how-the-adapter-knows-a-host-is-present)).

### The adapter's status

[adapter-status.md](adapter-status.md) decodes it. In short:

- A tag's top two bits give its value's length: none, one, two, or four bytes. This is an inference, and it fits every `08` reply in the captures, the monitors' included ([adapter-status.md](adapter-status.md#the-replys-layout)).
- `30` or `31` says whether the knob is in, and `32` or `33` the mic. `DF` holds the knob's position, a signed count of tenths of a dB. `DE` and `DD` hold two mic readings ([adapter-status.md](adapter-status.md#the-replys-layout)).
- `DF` reads about −1004 at the knob's bottom stop and 0 at its top (`knob-sweep`, 33.21 and 20.17 s; [adapter-status.md](adapter-status.md#the-knob-df)).
- No field speaks of the host, mute, standby, or a group. The shape holds from GLM's first poll in every Phase 0 capture ([adapter-status.md](adapter-status.md#the-replys-layout)).
- The adapter answers each poll within about 1.5 ms ([adapter-status.md](adapter-status.md#the-poll)). Every one of the 32,073 polls in the captures got a reply.

### Telemetry

[telemetry.md](telemetry.md) decodes it. In short:

- `47` is the power state: `01` on, `02` in standby (hlm §8.1; `qlm-standby-discover`, `standby-wake`). hlm saw `03` in standby when its own firmware drove the monitors (hlm §8.1, Appendix B item 9). No capture here shows it.
- `84`'s first byte reads `01` for a subwoofer and `02` for the two-way and three-way models while on (hlm §8.1; `qlm-control-first`, 829.397 s). In standby it reads `03`, after the first frame or two (`qlm-standby-discover`; `standby-wake`, 35.685 and 36.242 s).
- A standby reply drops the meters and the `81` to `83` readings (`qlm-standby-discover`).
- A monitor makes a new frame about once a second. A poll before it gets a bare `09` ([telemetry.md](telemetry.md#one-frame-a-second)). A frame sometimes comes split across two polls ([telemetry.md](telemetry.md#split-frames)).
- **No reply reports a monitor's mute.** Not the telemetry, the `2B` ack, `19 01`, `39`, or the adapter's status. A muted monitor's output meters read their floor, `80`, but so does silence (#27; `mute-dim`).

### `01 7E`

- **The adapter sends it when no monitor answered** (#9; `testTheNoAnswerFrameIsNoReply`).
- **It comes 8.1 to 11.1 ms after the request**, 8.6 ms at the median, across its 3,545 instances in the captures. The slowest is in `group-switch-main-2x1-main-4x2`, at 36.053 s. A monitor's reply comes within 6.6 ms, 1.6 ms at the median. **Guess:** the adapter waits about 8 ms for a monitor.
- It answers the probe once every monitor holds a lease ([Discovery and the lease](#discovery-and-the-lease)).
- It answers a frame to a session that just lost its lease ([When a monitor loses its lease](#when-a-monitor-loses-its-lease)).
- **A monitor in standby misses a request at times,** and answers the next try. qlm's polls in standby got `01 7E` three times in 10 s, and GLM's once (`qlm-standby-discover`). GLM's got it eight times in `standby-wake`.

## 6. Timing

### GLM's idle cycle

- **About every 0.57 s, GLM sends the probe, then the volume, then one `08` to each monitor** (`startup-idle`, from 10 s; 20.137 and 20.705 s, for two). The notes of `qlm-first-discover` and `qlm-standby-discover` measure GLM's cycle at 0.564 to 0.571 s.
- **It sends no `04` keep-alive while idle.** `04` comes only in a DSP pass: the apply at launch, the one after a wake, and a group switch (`startup-idle`, from 10 s; #12). hlm reports `04` once a cycle, every 1.2 to 1.8 s, in its bus captures (hlm §7). GLM 5 sends none while idle.
- qlm runs the same cycle: a probe every 0.569 s in `qlm-first-discover`, and 0.570 s in `qlm-standby-discover` (their notes; `QLMSystem.h`).

### The adapter's polls

- **GLM polls the adapter with `01 08` in pairs, 2.4 ms apart, a pair about every 107 ms.** That is about 17 polls a second ([adapter-status.md](adapter-status.md#the-poll)). Five pairs fall between two cycles (`startup-idle`, 20.137 to 20.705 s).
- The second poll of a pair rarely brings news. The knob differs between the two in 22 of 14,096 pairs ([adapter-status.md](adapter-status.md#the-poll)).
- **While GLM runs, it never goes quiet for long.** The longest gap between two of its reports is 0.22 s. The longest between two `01 08` polls is 1.70 s, in a group switch ([adapter-status.md](adapter-status.md#how-the-adapter-knows-a-host-is-present)).
- qlm polls a pair every 107 ms (`qlm-first-discover`; `QLMSystem.h`).

### Replies

- The adapter's status comes within about 1.5 ms ([adapter-status.md](adapter-status.md#the-poll)).
- A monitor's reply comes within 6.6 ms. The slowest is a `39`, whose reply spans two reports (`qlm-control-first`, 180.096 s).
- **The slowest reply in the captures is the adapter's `01 7E`, 11.1 ms** after a PEQ band to a monitor that had just lost its lease (`group-switch-main-2x1-main-4x2`, 36.053 s).
- qlm times a request out after 0.1 s (`QLMReportLink.h`).

### Volume

- **GLM sends a new level at once, out of the cycle** (hlm §7). A knob-driven level follows the poll that read the knob by 1.7 to 42 ms, 2.2 ms at the median ([adapter-status.md](adapter-status.md#how-knob-turns-reach-glm)).
- qlm coalesces the volume to at most one frame every 50 ms (`QLMSystem.h`).

### The power steps

- **Standby:** `3A 03 02` twice, then `3A 03 00` twice, 21.6 to 22.0 ms apart (`standby-wake`, 34.856 s; `testSleepIsGLMs`; hlm §7).
- **Wake:** `3A 03 7F` and `3A 03 01` back to back, three pairs 0.20 to 0.21 s apart (`startup-idle`, 7.332 s; `testWakeIsGLMs`).
- After a wake, the level follows the last pair by 0.235 s (`standby-wake`, 47.243 s; `testWakeIsGLMs`).
- **The monitors answer the first probe after the pairs:** 0.81 s after the first pair in `standby-wake` (47.373 s), and 0.50 s in `qlm-control-first` (828.290 s).
- **The first telemetry after the wake says on.** It came 1.6 s after the first pair in `qlm-control-first` (829.397 s). In `standby-wake` it came 2.5 s after, near the end of GLM's apply at wake (49.05 s). hlm saw 1.55 to 1.66 s on two 8320A (hlm §7).

### Applies

- GLM's apply at launch runs 1.4 s for six monitors (`startup-idle`, 8.534 to 9.901 s).
- A group switch runs 1.1 s when no monitor wakes (`group-switch-main-4x2-main-2x1`, 12.359 to 13.476 s).

### The hand-back

- **The adapter takes over at the knob's position about 2.6 s after the host goes quiet.** After `volume -60`, the level rose back to the knob's −40 dB 2 to 3 s after the Mac's sound, which played 0.2 s after qlm's last report (`qlm-control-first`, 289.7 s).
- hlm gives the timeout as about 2.6 s (hlm §9).
- GLM's longest silences, 0.22 s between reports and 1.70 s between polls, fit inside it ([adapter-status.md](adapter-status.md#how-the-adapter-knows-a-host-is-present)).

## 7. Sequences

### Each feature, at a glance

| Feature | On the wire | Section |
| --- | --- | --- |
| Find monitors | The probe and the lease until `01 7E`, then `39`. A monitor that misses four polls is found again. | [Discovery](#discovery) |
| Identify | `19 01`, the serial, and `39`, the system info | [System info](#system-info) |
| Status | `08`, answered with telemetry about once a second. `47` is the power state. | [Telemetry](#telemetry) |
| Volume | `FF 1F` with one of GLM's 200 levels, from a table, each cycle and at once on a change | [Volume and the knob](#volume-and-the-knob) |
| The knob | Its position rides the adapter's reply to `01 08`. The host sends the level. | [Volume and the knob](#volume-and-the-knob) |
| Dim | GLM's sequence: the level 20 dB down twice, a round of `2B`, then `FF 2D 00` and `FF 3D 00 00` | [Dim](#dim) |
| Mute | Two rounds of `2B` to every monitor that is on. Mute all also sends `01 2B 01`. No reply reports mute. | [Mute and mute all](#mute-and-mute-all) |
| Power | Standby: `3A 03 02` twice, then `3A 03 00` twice. Wake: three pairs of `3A 03 7F` and `3A 03 01`, then the level and the pair. | [Sleep and wake](#sleep-and-wake) |
| Group | Two kinds: the apply at launch and wake, and a group switch | [The group apply](#the-group-apply) |
| The host leaving | Nothing is sent. The adapter takes over at the knob's position about 2.6 s later. | [Section 8](#8-what-the-adapter-and-the-monitors-do-on-their-own) |

### GLM's startup

GLM opens the same way at launch and after a replug (`startup-idle`, 7.29 to 9.90 s; `unplug`, 68.34 to 69.04 s; [refused-frames.md](refused-frames.md#glms-startup-against-qlms) has each time):

1. `01 08`, `01 22`, `01 08`, `01 39`, and `01 19 01`, the adapter's identity (7.293 to 7.304 s).
2. The wake: `FF 3A 03 7F` and `FF 3A 03 01`, three times (7.332 to 7.739 s).
3. `01 51 82` (7.962 s).
4. `FF 2D 00` and `FF 3D 00 00`, the volume three times, `01 2B 00`, and the volume (7.971 to 7.991 s).
5. The pair and the volume, three more times, about 0.11 s apart (8.085 to 8.313 s).
6. Discovery (8.419 s). [Discovery](#discovery) has it.
7. The apply at launch (8.534 to 9.901 s). [The group apply](#the-group-apply) has it.
8. The idle cycle, with the adapter's polls between.

- **GLM opens at its own level, not the knob's:** `00 31 07`, −56.5 dB ([adapter-status.md](adapter-status.md#what-glm-does-with-the-knob)). That is the startup level in `Main.sam` (`qlm-control-first`'s notes, after the capture).

### qlm's startup

1. **The open's sync:** `01 39`, then `01 08`. Their replies answer no request (#33; `testAnOpenSyncsBeforeTheFirstRequest`).
2. **System's opening:** `01 08` twice, `01 39`, and `01 19 01` (`qlm-first-discover`, 24.940 to 24.947 s, before #33 added the sync).
3. With #32 (open): `19 01` to each monitor's old session, before the first probe.
4. Discovery, then the cycle.

- qlm leaves out `01 22`, `01 51 82`, the wake, the pair, and `01 2B 00` at connect. It sends no volume until one is set. The adapter bridged qlm without them (`qlm-first-discover`; [refused-frames.md](refused-frames.md#the-hand-back)).

### Discovery

- **GLM probes and leases back to back** until the probe gets `01 7E`. Then it sends the volume, then `39` to each new monitor (`startup-idle`, 8.419 to 8.533 s).
- **qlm probes, leases, and asks the new monitor's `39`, `19 01`, and `08`,** then probes again, until `01 7E` (`qlm-first-discover`, 56.42 s).
- **Once a volume is set, qlm sends it the moment a lease is acked**, ahead of everything queued (#27). A monitor that is switched on plays at its stored level until a host sends one ([Section 8](#8-what-the-adapter-and-the-monitors-do-on-their-own)).
- **Monitors in standby answer discovery without a wake**: the probe, the lease, `39`, `19 01`, and `08`. They stay in standby (`qlm-standby-discover`, 250.3 s).
- A monitor that drops out is found again by the probe, at the next session ([When a monitor loses its lease](#when-a-monitor-loses-its-lease)).

### Volume and the knob

- **GLM restates the volume once a cycle,** and sends a new level at once (`startup-idle`, from 10 s; hlm §7).
- **The knob's position rides the adapter's reply to `01 08`.** GLM turns each change into a level: the reading in tenths of a dB, rounded to the nearest 0.5 dB ([adapter-status.md](adapter-status.md#the-mapping); `testTheKnobNamesTheSteps`).
- **GLM ignores the knob until its first move, then jumps to it.** After that it follows each step, ignores jitter at rest, and sometimes follows a slow wander ([adapter-status.md](adapter-status.md#what-glm-does-with-the-knob)).
- **Each knob-driven level is a burst:** the level three times, `01 2B 00`, two rounds of `2B`, then the level again (`standby-wake`, 0.99 s; `testAKnobTurnIsGLMs`; `knob-sweep`, 19.24 s).
- GLM sends the burst on every change in the reading, even when its level stays (#18).
- With the knob in, GLM locks its on-screen volume. With the knob out, the reply carries `31`, and GLM unlocks it (`volume-sweep`, 25.44 s; its notes).
- **qlm's rule** (`QLMKnob`; #18; `QLMKnobTests`):
  - The first reading is where the knob rests. The volume stays qlm's own.
  - A turn is a move of a whole dB within half a second. It sets the knob's nearest step, under the ceiling.
  - For 2 s after a turn, the volume follows every step the knob passes.
  - Once the volume is the knob's, a slow wander of a whole dB moves it. Less moves nothing.
  - With no volume set, the knob sets none.
  - qlm sends the burst only when its volume changes.
- In `qlm-control-first`, qlm jumped to the knob at its first real turn, then followed it. The highest level it sent was −41.5 dB, under a −35 dB ceiling (373.12 s; `testEveryLevelIsGLMsAndUnderTheCeiling`).

### Dim

- **There is no dim opcode.** Dim is a volume frame 20 dB down (hlm §9; `mute-dim`, 51.24 s: `00 31 07` to `00 04 E7`).
- **GLM's dim:** the dimmed level twice, one round of `2B`, then `FF 2D 00` and `FF 3D 00 00`. Dim off sends the restored level the same way (`mute-dim`, 51.24 s on and 54.77 s off; `testDimIsGLMs`).
- `2D 00` is the same for on and off, so it does not carry the dim state ([refused-frames.md](refused-frames.md#broadcast-2d-00-and-3d-00-00)).
- After the pair, both subwoofers answer their next poll with the busy marker `07` (`mute-dim`, 51.658 and 51.664 s).
- qlm's dim floors at `00 00 08`. A volume above the ceiling dims from the ceiling (`QLMCommands.h`; `testDimFloorsAtTheSlider`). With no volume set, dim sends nothing (`QLMSystem.h`).
- `qlmctl dim` sends GLM's whole dim. It sets the volume first, then dim (#27). Before #27 it sent only the dimmed level (`qlm-control-first`, 538.3 s).

### Mute and mute all

- **One monitor:** two rounds of `2B` to every monitor that is on, in the setup's device order. The muted one gets `03`, and the others in the group `04`. A monitor outside the group gets `05` then `07`, or `07` alone in the first of two rounds. No volume goes out, and nothing to `01` (`mute-dim`, 19.19 s; `knob-sweep`, 19.135 s; `testMutingOneMonitorIsGLMs`).
- **Mute all:** the level once, `01 2B 01`, then two rounds of `2B 03` (`mute-dim`, 46.19 s; `testMutingAllIsGLMs`).
- **Unmute all:** the level, `01 2B 00`, then two rounds of `2B 04` (`mute-dim`, 48.60 s).
- Every answered `2B`, to a monitor or the adapter, got a bare `09`: 5,569 in the captures (#27).
- **Every round restates every monitor that is on.** So a round from any host unmutes a monitor muted elsewhere. In `qlm-control-first`, the knob's burst unmuted the 7370A, which GLM had muted (373.12 s; [telemetry.md](telemetry.md#what-the-meters-showed-about-the-control-run)).
- qlm keeps the user's mutes by hardware ID, across a lapsed lease (#20). #29 (open) keeps them across a stop too.
- In `mute-dim`, session `05` is the 7370A and `0B` the 7350A. That comes from the lease of `0B` in `group-switch-main-2x1-main-2x2` (10.418 s), against the leases and `39` replies in `startup-idle` (8.432 to 8.533 s). The notes of `mute-dim` call `0B` the big sub, so their sub labels look swapped.

### Sleep and wake

- **Standby:** `FF 3A 03 02` twice, then `FF 3A 03 00` twice (`standby-wake`, 34.856 s; `testStandbyIsGLMs`).
- hlm says that sending `3A 03 00` twice keeps a monitor from waking by itself when a signal returns (hlm §9).
- **In standby, GLM keeps polling and sending the volume.** The monitors answer with `47 02` and no meters (`standby-wake`, from 35.68 s).
- **Wake:** three pairs of `FF 3A 03 7F` and `FF 3A 03 01`. Then the level, `FF 2D 00`, and `FF 3D 00 00` (`standby-wake`, 46.565 to 47.266 s; `testWakeIsGLMs`).
- **Every monitor that wakes loses its lease** and answers the next probe ([When a monitor loses its lease](#when-a-monitor-loses-its-lease)). GLM then sends its apply at wake to each, and each gets its state after its first poll (`standby-wake`, 47.70 to 49.09 s; `testWakeApply`).
- **qlm's wake** sends the three pairs. Once a volume is set, it ends with the level and the pair, as GLM's does (#27; `testWakeIsGLMs`). With #29 (open), every wake ends with a level: the volume, else the knob's position under the ceiling, else `00 00 08`.
- **GLM sends `3A 03` to one monitor only in a group switch.** Its own standby is a broadcast (the six `group-switch-*` captures). A single `3A 03 02` puts a monitor outside the new group in standby (`group-switch-main-4x2-main-2x2`, 14.249 s; `testSwitchFrom4x2To2x2`).

### The group apply

GLM sends two kinds of apply. [refused-frames.md](refused-frames.md#the-group-apply) has both, frame by frame, and how System's match GLM's. `QLMApplyGoldenTests` diffs System's against all eight captured applies.

**At launch and wake** (`startup-idle`, 8.534 to 9.901 s; `testStartupApply`, `testWakeApply`):

1. For each new monitor, in lease order: `FF 04`, a subwoofer's `3B`, `05 04` (refused), and its block.
2. Then `39` and `19 01` to that monitor.
3. Off nodes get their block too.
4. Then a round to the other monitors that are on, and the pair.
5. Each new monitor gets its state right after its next poll.

**A group switch** (`group-switch-main-4x2-main-2x1`, 12.359 to 13.476 s; `testSwitchFrom4x2To2x1`):

1. `FF 1F 00 00 08`, then the duck, `FF 1F 00 00 02`.
2. `FF 3A 03 7F` twice.
3. The routing pass, in the group's node order. A node that is on gets `3A 03 01` twice, and one that is off `3A 03 02` once. A subwoofer gets `3B`. Then `05 04` (refused), the state if the monitor is on, the routing frames, and the state again.
4. A round. Then the DSP pass, in the setup's device order: `FF 04` for every node, and the block of each one that is on.
5. `01 2B 00`, two rounds, the volume three times, a round, and the pair.

**The block** (`QLMDSPBlockGoldenTests`, all 73 captured passes):

| Model | Frames, in order | Source |
| --- | --- | --- |
| 8330A | `17 01`, `FF 04`, `10 02`, `10 01 00`, `10 01 09`, twenty `10 0E`, `3B`, `3D 00 00`, `40` | `startup-idle`, 8.538 s |
| 8351B | `17 01`, `10 02`, `10 01 00`, `10 01 09`, `43 00 02`, twenty `10 0E`, `3B`, `4B 00 00 00 01`, `3D 00 00`, `40` | `standby-wake`, 46.581 to 46.807 s |
| 7370A, 7350A | `17 01`, slot 0, `10 02`, the level pair, the routing pair, `3E`, `42`, the routing pair, `3B`, then `3C`, slot 0, and `10 02` twice, the routing pair, `3E`, the twenty slots, `3D`, and the routing pair | [refused-frames.md](refused-frames.md#3c-3e-and-42-to-the-subwoofers) |

- Only the 8330A gets the extra `FF 04` after `17 01` (`startup-idle`, 8.540 s; `group-switch-main-2x2-main-4x2`, 10.947 s; `QLMApplySequence.m`).
- **A monitor woken into the group loses its lease mid-switch.** GLM's frames to its old session get `01 7E`, and GLM applies its block at the new lease beside the switch's tail (`group-switch-main-2x1-main-4x2`, 35.84 to 36.46 s; `testSwitchFrom2x1To4x2`).
- **GLM's cycle runs beside its apply,** so its rounds drop monitors its polls find in standby mid-switch (`testSwitchFrom4x2To2x2`).
- **The switches decode to the group switch espgensam documents,** with this system's differences: the per-monitor wake, all twenty slots, the 8351B's two extra frames, the subwoofers' repeats, and the tail (#9; espgensam's `docs/glm-group-apply.md`).
- qlm leaves out `05 04`, and the 8351B's `43` and `4B`. Any real apply with an 8351B is refused until its rate is verified. #31 (open) allows one behind a flag, as a supervised test, still without `43` and `4B` ([measurement.md](measurement.md)).
- No apply by qlm has run on the monitors or been measured yet. [measurement.md](measurement.md) is the procedure.

## 8. What the adapter and the monitors do on their own

- **With no host, the adapter applies the knob.**
  - About 2.6 s after the host goes quiet, it takes over at the knob's position ([The hand-back](#the-hand-back)).
  - When qlm stopped at the knob's level, no one heard a change. With qlm stopped, turning the knob moved the level (`qlm-control-first`, 393.7 s, and its notes).
  - qlm's ceiling does not reach it. A knob above qlm's level makes the take-over louder (#28; #30, open).
  - With no knob in, the level it applies is unknown (#30, open).
  - While a host is connected, the adapter broadcasts `F0 1F 00 00 00` about every 610 ms, a level the monitors ignore. Standalone, it sends its own level on `F0` (hlm §9). USB shows none of this.
  - hlm saw the adapter ramp up to its stored startup level at boot, in steps about 610 ms apart (hlm §9). No capture here shows it.
- **Nothing tells the adapter the host left.** GLM's last frame is an ordinary poll (`quit-glm`, 9.2 s). At that quit, the knob read −19.8 dB and GLM's level was −20 dB, so the capture cannot tell the two apart (`quit-glm`, 0.3 and 9.215 s). **Guess:** the adapter takes steady polling as a host's presence ([adapter-status.md](adapter-status.md#how-the-adapter-knows-a-host-is-present)).
- **A monitor that is switched on plays at its own stored level until a host sends one.** When GLM relaunched, two 8330A just switched on played very loud for about a second, until GLM's −56.5 dB reached them (`qlm-control-first`'s notes, after the capture).
- **A woken monitor keeps the level it had** until a host sends one (`qlm-control-first`, 827.8 s, and its notes). **Guess:** it also stays muted until a host sends its state. After qlm's wake, every output meter read its floor for 10 s, and qlm sent no `2B` ([telemetry.md](telemetry.md#what-the-meters-showed-about-the-control-run)).
- **A mute outlasts the host, and no reply reports it.** The Right 8351B stayed muted after qlm's exit, until `mute off` (`qlm-control-first`, 648.7 to 660.5 s; [Telemetry](#telemetry)).
- **Monitors in standby answer.** They answer discovery and polls without a wake, and stay in standby (`qlm-standby-discover`). They miss a request at times ([`01 7E`](#01-7e)).
- **Monitors drop a quiet host's leases**, within 23 s to 210 s ([When a monitor loses its lease](#when-a-monitor-loses-its-lease)).
- **The telemetry clocks count with no host polling.** `49` counts seconds since the wake through standby, leases, and unplugs ([telemetry.md](telemetry.md#49-seconds-since-the-wake)).

## 9. Open questions

1. **Whether the adapter escapes a `7D` or `7E` address.** No capture has an address above `19`. qlm never leases either ([Framing](#2-framing)).
2. **Whether the adapter answers in order with more than one request in flight.** GLM and qlm keep one in flight, so no capture shows it. qlm's sync assumes it (`QLMReportLink.h`).
3. **The adapter's host timeout, and what resets it:** any report, or only `01 08`. Whether one poll a cycle holds it as well as GLM's pairs ([adapter-status.md](adapter-status.md#open)).
4. **What level the adapter applies with no knob in** (#30, open).
5. **Why monitors drop a quiet host's leases, and why within 9 s across an unplug** (`unplug`).
6. **Whether `01 22` or `01 51 82` changes what the adapter does on the bus,** such as its defer broadcast ([refused-frames.md](refused-frames.md#open)).
7. **What the `2D 00` and `3D 00 00` pair does to the subwoofers,** and what their busy marker after it means ([refused-frames.md](refused-frames.md#open)).
8. **What `3C`, `3E`, `42`, `43`, `4B`, `40 01 02 00 00`, and `10 01 09` carry.** A capture of a change to the LFE fields, `GroupDelayCompensation`, or `BassExtensionXO` could map some ([refused-frames.md](refused-frames.md#open)).
9. **The analog routing frame,** for input 4. No group in the setup uses it (#8).
10. **What the adapter does with `01 2B 01`,** and whether it keeps a mute of its own through the hand-back ([refused-frames.md](refused-frames.md#open)).
11. **What `82` selects in `01 51 82`,** and what `219000` is ([refused-frames.md](refused-frames.md#open)).
12. **The 8351B's design rate.** Its bands match 96 kHz on the wire, and a measurement must confirm it ([measurement.md](measurement.md)).
13. **GLM's rule for following the knob's slow wander** ([adapter-status.md](adapter-status.md#open)).
14. **Whether a woken monitor stays muted until a host sends its state** ([telemetry.md](telemetry.md#open-questions)).
15. **What `c-` means in the system info**, given that `84` reads `02` for the 8351B ([System info](#system-info)).
16. **What the adapter does when the host's USB suspends.** The proxy does not forward suspend, and no capture caught a true sleep ([captures/README.md](../captures/README.md)).
17. **The telemetry tags and meters still open** ([telemetry.md](telemetry.md#open-questions)).

## Sources

- The 20 captures in `captures/`, each with its `notes.md`. GLM 5 ran the Phase 0 scenarios on 2026-10-29. qlm ran `qlm-first-discover`, `qlm-standby-discover`, and `qlm-control-first` on 2026-10-30.
- The tests in `Tests/`, which check these facts against the captures, and the headers in `qlm/GLMProtocol/`.
- hlm's spec, revision 13, at robcazzaro/hlm commit `c08ced9`: §1 to §9, and Appendix B. Facts only. No text was copied.
- genlc's `transport.py`, for the report-ID byte. Facts only. No code was ported.
- Pull requests #8 to #35 in cmicali/qlm. #29 to #32 are open.
- [adapter-status.md](adapter-status.md), [refused-frames.md](refused-frames.md), [telemetry.md](telemetry.md), and [measurement.md](measurement.md).
