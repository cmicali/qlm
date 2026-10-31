# Frames GLM sends that qlm does not

GLM sends some frames that qlm refuses or leaves out. The allowlist refuses `05`, `22` and `51` to the adapter, and a broadcast `03`. `testEveryOutputReportRepacksByteForByte`, in `Tests/GLMProtocol/QLMGoldenTests.m`, pins that set. The allowlist accepts the rest. Broadcast `2D 00`, `3C`, `3E`, and `42` to a subwoofer, and `43` and `4B` to the 8351B, were refused too, and are now allowed with exactly GLM's payloads. System now sends them, broadcast `3D`, and `2B` to the adapter, as GLM does. It does not send the wake at startup. This doc says what each one does, and whether qlm needs it. [The group apply](#the-group-apply) says what System's apply sends against GLM's.

A time is seconds into that capture's `reports.txt`. "hlm §7" is section 7 of hlm's spec, `docs/Genelec GLM Protocol.13.md` in robcazzaro/hlm, revision 13, at commit `c08ced9`. Its facts are restated here in our own words. **Guess:** marks a guess. The code is as of this doc's last change.

## Short answers

| Frame | Where GLM sends it | qlm today | Does qlm need it? |
| --- | --- | --- | --- |
| `05 04 …` | Every monitor's DSP block, and a group switch's routing pass | Refused | No. AGENTS.md forbids `05`. |
| `3C`, `3E`, `42` | Each subwoofer's DSP block | Allowed, `00 00` to a session only. Sent in each subwoofer's block. | Phase 3, to match GLM's apply. Done. |
| `43 00 02`, `4B 00 00 00 01` | Each 8351B's DSP block | Allowed, these payloads to a session only. Built from the 8351B's node, and sent in its block. | Phase 3, to match GLM's apply. Done. The 8351B's refusal still stands. |
| `FF 2D 00` | With `FF 3D 00 00`: startup, wake, group switch, dim, and knob unplug | Allowed, as a broadcast only. Sent in dim, and at the end of each group apply. | Phase 2, for dim. Phase 3, for the apply. Done. |
| `FF 3D 00 00` | Right after every `FF 2D 00` | Accepted. Sent with `2D 00`. | As for `2D` |
| `01 22` | Once per connection | Refused | No |
| `01 51 82` | Once per connection | Refused | No |
| `01 2B 00`, `01 2B 01` | Mute all, unmute all, startup, each knob-driven level, and a group switch's tail | Accepted. Sent at mute all, unmute all, each knob-driven level, and a group switch's tail. | Phase 2, for mute all |
| The wake | Startup and wake | Accepted, not sent at connect | Phase 2, for power |
| `FF 03` | Once, before GLM leased every monitor again | Refused | No |

## The hand-back

Phase 2's open question is the level the adapter applies after the host goes quiet. GLM opens with `01 22` and `01 51 82`. qlm's first run sent neither. Could either set host mode, or the hand-back level?

**Nothing in the captures says so.**

1. **The adapter bridged qlm without them.** In `qlm-first-discover`, qlm sent the adapter only `01 08`, `01 39`, and `01 19 01` (24.940 to 24.947 s, and 56.413 to 56.420 s). The adapter passed every request through and answered each with one frame. Its `01 08` reply had GLM's shape. All six monitors answered, with GLM's session IDs.
2. **Both look like queries.** Each returns data, the same data in all five captures that hold them. A frame that sets state gets the bare `01 09`: `01 2B` got it all 346 times.
3. **Neither can track the level.** GLM sends each one once per connection, before its first volume, and never again. GLM's level changes all session, and GLM sends nothing at quit (`quit-glm`, 9.2 s). A frame sent once at open cannot carry the level at quit.

USB cannot show everything. The adapter speaks on the monitor bus, and USB does not carry that. While a host is present, the adapter broadcasts a defer frame, `F0 1F 00 00 00` (hlm §9). Whether `22` or `51 82` starts or stops that broadcast is not in any capture. The bus tap can show it.

### GLM's startup against qlm's

| Step | GLM, `startup-idle` | qlm, `qlm-first-discover` |
| --- | --- | --- |
| `01 08` | 7.293 s | 24.940 s |
| `01 22` | 7.295 s | not sent |
| `01 08` | 7.297 s | 24.942 s |
| `01 39` | 7.299 s | 24.944 s |
| `01 19 01` | 7.304 s | 24.947 s |
| The wake, three pairs | 7.332 to 7.739 s | not sent |
| `01 51 82` | 7.962 s | not sent |
| `FF 2D 00`, `FF 3D 00 00` | 7.971 s | not sent |
| The volume three times, `01 2B 00`, the volume | 7.986 to 7.991 s | not sent |
| The pair and the volume, three more times | 8.085, 8.195, and 8.306 s | not sent |
| Discovery | 8.419 s | 56.421 s |

GLM opens the same way after a replug (`unplug`, 68.34 to 69.04 s) and in `startup-idle-mic`, `knob-sweep`, and `unplug-proxy-hang`.

### What the first run hints about the level

The two 8330A, at sessions `02` and `04`, carried a little signal in `qlm-first-discover`. Their meters changed when GLM quit:

| Tag | While GLM ran (0 to 13.5 s, 14 polls each) | After GLM quit (56.4 s, and 79.7 to 89.4 s, 12 polls each) |
| --- | --- | --- |
| `42`, the input meter | `9D` to `9F` | `9D` to `9F` |
| `43`, the HF output meter | `81` to `84` | `80`, the floor, every time |

hlm §8.1 puts `42` before the volume stage, and `43` after the volume and the mute. The output meters read about 1 dB a count. So the output fell to the floor, 1 to 4 counts down, and the input did not change.

GLM's last level was `00 31 07`, −56.5 dB (14.009 s). The knob read −95.8 dB (24.941 s). A drop to the knob's level fits. So does a mute, or any drop of about 4 dB or more. Holding GLM's level does not fit.

**Guess:** with the host gone, the adapter applies the knob's position. The user reports the same with GLM closed. The open list has a test.

## Each frame

### `05 04 …`, the generator stop

**Where.** Always `05 04 00 00 00 FF FF EA 00 01 90 00 02 DA`, 154 times in the 15 captures `QLMDSPBlockGoldenTests` reads. That takes in the setup captures, whose changes to the Left 8351B's bands and shelves didn't move it. It opens each monitor's DSP block, right after `FF 04`. At startup every monitor gets one (`startup-idle`, 8.535 s for `02`). In a group switch it comes in the routing pass, after `3A 03 01` twice (`group-switch-main-2x2-main-4x2`, 10.412 s).

**What the captures show.** Of the first 85, the monitor answered `01 09` 76 times. The other 9 got `01 7E`, from monitors still waking in a group switch: `08` at 10.412 s, 23 ms after its second `3A 03 01`, in the same capture. No later reply can be tied to it alone, since the rest of the block goes out with it.

**hlm.** §7 lists `05` as the test-signal generator. Subcommand `04` runs the noise generator, and a mask of `00` stops it and restores the program. The mask also gates the tweeter and the woofer, for program audio too. §7 reads `FF FF EA` as a stopped generator's level, and `01 90` as 400 Hz. It also says the generator's state persists. §9 puts the stop in every monitor's enumeration and in the group apply.

**Need.** Neither phase. AGENTS.md forbids `05`, and the persisted state is one more reason. The stop matters only if GLM's test tools left a generator or a driver gate on. qlm never calibrates. Keep it refused.

### `3C`, `3E`, and `42`, to the subwoofers

**Where.** Only to the 7370A and the 7350A, in their DSP blocks, and always with the payload `00 00`. Each block sends `3C` and `3E` twice and `42` once. In `startup-idle`, after its level pair, the 7370A at `05` gets:

1. `40 00 02 00 03`, `40 01 02 00 00`
2. `3E 00 00` (8.910 s), `42 00 00` (8.912 s)
3. The two routing frames again, then `3B 00 3C`
4. `3C 00 00` (8.921 s), PEQ slot 0, `10 02`
5. `3C 00 00` (8.929 s), PEQ slot 0, `10 02`
6. The two routing frames, `3E 00 00` (8.941 s), then the 20 PEQ slots

Across 12 captures: `3C` 52 times, `3E` 52, and `42` 26.

**What the captures show.** The subwoofer answers `01 09`. The few `01 7E` came from a subwoofer still waking in a group switch (`group-switch-main-2x1-main-2x2`, 9.80 to 9.92 s, to `0A`). No later reply can be tied to them.

**The setup file.** In `Main.sam`, each subwoofer has `SubwooferGroupID`, `LFE_+10`, `LFE_Channel`, and `LFE_Level` at 0, in every group. Its `LFE_CrossoverFrequency(Hz)` is 120. **Guess:** the three opcodes carry zero-valued LFE fields. A field of 120 would not go out as `00 00` unless coded some other way.

**hlm.** §7 lists all three as unknown and subwoofer-only, seen on a 7350A as it enumerates, at about 20% confidence. §9 says a subwoofer's enumeration may add them. Appendix B leaves their payloads open (item 7) and the LFE fields unmapped (item 6). §6 lists the LFE fields as not yet seen on the wire.

**Need.** Phase 3. GLM sends them in every subwoofer block, so a dry run that matches GLM needs them. Phase 2 does not. They are not on AGENTS.md's never-send list. Allow exactly `3C 00 00`, `3E 00 00`, and `42 00 00`. The allowlist cannot see the model, so System sends them to subwoofers only, in GLM's order. Refuse a group whose subwoofer LFE fields are not zero until a capture maps them, as the plan's Risks table allows.

**Now.** The allowlist takes exactly these three payloads, and the encoder sends them only to a session. `QLMFrameTests` covers both. A subwoofer's DSP block is GLM's, frame for frame: `17 01`, slot 0, the delay, the level, `10 01 09`, the routing pair, `3E`, `42`, the routing pair, `3B`, then `3C`, slot 0, and the delay twice, the routing pair, `3E`, the twenty slots, `3D`, and the routing pair. `QLMDSPBlockGoldenTests` checks all 26 captured subwoofer passes against it in order. The routing pair is `40 00 02 00 03` and `40 01 02 00 00`. What the second routes is unknown. The block refuses a subwoofer whose `LFE_+10`, `LFE_Channel`, `LFE_Level`, or `SubwooferGroupID` is not 0, or whose `LFE_CrossoverFrequency(Hz)` is not 120, the values in every capture.

### `43 00 02` and `4B 00 00 00 01`, to the 8351B

**Where.** Only to the two 8351B. `43 00 02` follows the level pair `10 01 00` and `10 01 09`, before the PEQ slots. `4B 00 00 00 01` follows `3B`, before `3D`. In `startup-idle`: to `03` at 8.650 and 8.725 s, and to `06` at 9.048 and 9.116 s. Across the 15 captures `QLMDSPBlockGoldenTests` reads: `43` 47 times and `4B` 47, always with these payloads.

**What the captures show.** The 8351B answers `01 09`. One `01 7E` came from an 8351B still waking (`standby-wake`, 46.784 s, to `11`). No later reply can be tied to them. The payloads stay put when the group changes. Main 2x1 has a 60 Hz crossover and `RateFlatness` and `RateCorrelated` at −1 (`startup-idle`, `3B 00 3C` at 8.723 s). Main 4x2 has 85 Hz and both at 0 (`standby-wake`, `3B 00 55` at 46.775 s). Both send the same `43` and `4B`. So do the Left's blocks after its bands and shelves changed (`setup-b-peq-8351b`, 182.460 and 300.007 s).

**The setup file.** The 8351B nodes, class `ThreewayGen2`, carry fields the 8330A nodes lack. Two hold the same value in every group: `GroupDelayCompensation:2` and `BassExtensionXO(Hz):1`. No other node has either one, the subwoofers' included. **Guess:** `43 00 02` carries the first, and `4B 00 00 00 01` the second, which sits next to the crossover as `4B` follows `3B`. Against the first: each group has a `GroupDelayCompensation:2` of its own, and no other model gets a `43`. This doc once said the 7350A's node has the field. It doesn't, in `Main.sam` or in any setup in `captures/`. The group's field is the one every monitor shares.

**hlm.** §7 has neither opcode. §4 and Appendix B item 1 leave the 83x1 filter design rate open.

**Need.** Phase 3, so that qlm's apply is GLM's byte for byte. Neither is on the never-send list.

**Now.** qlm builds both. `QLMDSPBlock` takes `43 00 vv` from the node's `GroupDelayCompensation`, and `4B 00 00 00 vv` from its `BassExtensionXO(Hz)`, in GLM's places. It does so for any three-way, class `ThreewayGen2`, since it lays out the rest of the block by class too. The 8351B is the only three-way in the captures. The mapping is the guess above, matched only at 2 and 1. So the block refuses an 8351B whose fields hold anything else, or are missing, with `QLMDSPBlockErrorThreeWay`, as it refuses a subwoofer's LFE fields. The group's own `GroupDelayCompensation`, `Group_BE_Mode`, `Group_BE_XOMin`, and `Group_BE_XOMax` might drive the frames instead. They hold 2, 0, 150, and 250 in all 20 groups of the five setups in the repository, so the block requires those too, with the same refusal. The allowlist takes exactly `43 00 02` and `4B 00 00 00 01`, and the encoder sends them only to a session. `QLMFrameTests` covers both. `QLMDSPBlockGoldenTests` checks all 47 of the 8351B's captured passes against qlm's block, frame for frame, with nothing left out. They all match.

The 8351B's refusal is unchanged. System still refuses a group apply with an 8351B, since its design rate is unverified, except in `qlmctl apply-group`'s supervised test behind `--unverified-rate`. The app refuses always. That supervised test now sends `43` and `4B` as GLM does. `apply-group --dry-run` prints them, and still ends with REFUSED. What the frames set, and whether the guess holds at other values, needs Part G of [setup-captures.md](setup-captures.md).

### Broadcast `2D 00` and `3D 00 00`

**Where.** Always as a pair, `3D` within 1.1 ms of `2D`.

- **Dim on and off** (`mute-dim`, 51.323 and 54.846 s). Each time GLM sends the new volume twice, one `2B 04` round to all six, then the pair.
- **The knob's unplug** (`volume-sweep`, 25.719 s). GLM saw the knob go at 25.44 s and unlocked its own volume. Then it sent one `2B 04` round and the pair.
- **Startup.** Four times before discovery, each with the volume, and once after the last DSP block (`startup-idle`, 9.302 s).
- **Wake** (`standby-wake`, 46.836, 47.266, and 48.491 s).
- **Group switches.** One to three times in five of the six, after a `2B 04` round (`group-switch-main-2x2-main-4x2`, 12.199 and 12.318 s). `group-switch-main-2x2-main-2x1` has none.

Never with a mute, nor with a knob-driven level change. `mute-dim`'s 14 mute actions send none. `knob-sweep`'s 124 level changes send none.

The payloads never change. Dim on and dim off both send `2D 00`, so `2D` does not carry the dim state.

**What the captures show.** A broadcast gets no reply. After the pair, both subwoofers answer their next poll with the busy marker `07`. The two-way and three-way monitors do not.

| Capture | The pair | `05` | `0B` |
| --- | --- | --- | --- |
| `mute-dim`, dim on | 51.323 s | 51.658 s | 51.664 s |
| `mute-dim`, dim off | 54.846 s | 55.081 s | 55.089 s |
| `volume-sweep` | 25.719 s | 26.169 s | 26.176 s |

No other reply in `mute-dim` carries the marker, though its 14 mute actions send 170 `2B` frames. So the marker follows the pair, not the `2B` round.

**hlm.** §7 calls `2D` an input-select or configuration preamble that goes with `3D`, at about 50% confidence. It reports the same bare pair from the OEM hub about 0.27 s after a wake. §7 calls unicast `3D 00 00` the input-select sync, at about 60%. §8 links the busy marker to a settings write in progress, after `40`, `15`, or a generator change.

**Guess:** the pair makes the subwoofers re-apply their input setup. GLM sends it after it configures monitors, and when its volume mode changes: dim, or the knob gone.

**Need.** Phase 2 needs it only for dim to match GLM byte for byte. Dim itself is the volume frame: hlm §9 says there is no dim command. The pair carries no level. For Phase 3, GLM sends it after every round of DSP blocks. **Guess:** a subwoofer may need it to take its routing. `2D` is not on the never-send list. Allow exactly `2D 00`. System sends it only as a broadcast, only right before `FF 3D 00 00`, and only where GLM does. `FF 3D 00 00` is already allowed.

**Now.** The allowlist accepts exactly `2D 00`, and the encoder sends it only to `FF`. Every other `2D` payload and address is refused. `QLMFrameTests` covers both. System's dim sends GLM's whole sequence, `2D 00` included, and `QLMSystemGoldenTests` checks it against `mute-dim` byte for byte. In every capture, all 39 broadcast `3D 00 00` follow `2D 00`, and none of the 73 unicast ones does. System's group apply now sends the pair as GLM does: after the round that ends a switch, and after the blocks of an apply at launch or wake. [The group apply](#the-group-apply) has the detail.

### `01 22`

**Where.** Once per connection, between the two polls of GLM's first `01 08` pair (`startup-idle`, 7.295 s). Also `startup-idle-mic` at 7.314 s, `knob-sweep` at 6.486 s, `unplug` at 68.338 s after the replug, and `unplug-proxy-hang` at 106.239 s. Never again.

**What the captures show.** The reply is `01 09`, then the ASCII `GLM Adapter 0 0000 0104 06113`, a space, and a NUL. It is the same in all five. The adapter's `01 08` reply has the same shape before it (7.294 s) and after (7.298 s). The adapter's `39` reply carries `c-0` and `ver-1.4.0.6113` (7.300 s). **Guess:** `22` returns the same identity, space-separated: the class `0`, then `0000`, then the version `0104` and the build `06113`.

**hlm.** §7 has no opcode `22`. The spec covers the bus, and GLM sends `22` only to the adapter. §8 shows two forms of a monitor's system-info reply: one split by semicolons, and one by spaces, such as `7350A 1 0000 0106 3733`. The adapter's `22` reply has the space form. **Guess:** §8's space form is a monitor's reply to `22`. [adapter-status.md](adapter-status.md) cites genlc for calling `22` a hardware query.

**Need.** Neither phase. It reads an identity that `39` and `19 01` already give. qlm's first run worked without it. Keep it refused.

### `01 51 82`

**Where.** Once per connection, after the wake and before GLM's first volume (`startup-idle`, 7.962 s). Also `startup-idle-mic` at 7.983 s, `knob-sweep` at 7.170 s, `unplug` at 69.005 s, and `unplug-proxy-hang` at 106.904 s. Never again.

**What the captures show.** The reply is `01 09`, then the ASCII `219000`, with no NUL. It is the same in all five, with the mic out and with it in (`startup-idle-mic`, 7.985 s). The adapter's `01 08` reply does not change after it. What `82` selects is unknown.

**hlm.** §7 has no opcode `51`. [adapter-status.md](adapter-status.md) cites genlc for calling `51` the mic serial query. **Guess:** the adapter keeps the serial of its calibration mic, plugged in or not.

**Need.** Neither phase. The mic is for calibration, which qlm never does. qlm's first run worked without it. Keep it refused.

### `01 2B 00` and `01 2B 01`

**Where.** `01 2B 01` once, at mute all (`mute-dim`, 46.189 s). `01 2B 00` 345 times:

- at unmute all (`mute-dim`, 48.596 s)
- at startup, after the first volume (`startup-idle`, 7.989 s)
- with each knob-driven level change (`knob-sweep`, 169 times)
- in each group switch's tail (`group-switch-main-2x2-main-4x2`, 11.961 s)
- at wake (`standby-wake`, 18 times)
- with the knob's unplug transient (`volume-sweep`, 25.231, 25.341, and 25.450 s)

Mute all sends the volume once (46.188 s), then `01 2B 01`, then `2B 03` to each monitor, twice (46.192 to 46.215 s). Unmute all is the same with `01 2B 00` and `2B 04` (48.595 to 48.621 s).

**What the captures show.** The adapter answers `01 09`, all 346 times. Its `01 08` reply has no field that follows mute ([adapter-status.md](adapter-status.md)). Whatever the frame does happens inside the adapter or on the bus.

**hlm.** §7 defines `2B` for monitors: bit 0 mutes, and other bits drive the LED. It also says a volume re-broadcast comes before mute all. It says nothing of `2B` to the adapter.

**Guess:** the adapter keeps the system's mute state for when it runs alone.

**Need.** Phase 2, for mute all to match GLM byte for byte: `01 2B 01` at mute all, and `01 2B 00` at unmute all. The allowlist already accepts `2B`, and the plan's Next lists it for System. If qlm sends `01 2B 01`, it should also send `01 2B 00` at connect, as GLM does, so no stale mute lingers. Following the knob as GLM does would add `01 2B 00` and the `2B` rounds to each knob-driven change.

### The wake, at startup

**Where.** `FF 3A 03 7F` then `FF 3A 03 01`, three times, 0.2 s apart (`startup-idle`, 7.332, 7.538, and 7.739 s). The same at every connection, and at a wake from standby (`standby-wake`, 46.565 to 47.008 s).

**What the captures show.** A broadcast gets no reply. In `startup-idle` all six were already on, so nothing visible changed. In `qlm-first-discover`, all six answered with no wake. In `standby-wake`, the monitors came back after it, leased from 47.378 s.

**hlm.** §7 and §9 give the wake as three pairs of `3A 03 7F` and `3A 03 01`, with no `3A 03 02` after. §9 says the app sends it when it connects.

**Need.** Phase 2, for power on. The allowlist accepts `3A 03`. Sending it at connect is a setting in the plan's UI. Whether a monitor in standby answers without it is open (the plan's Next).

### Broadcast `03`

**Where.** Twice, 0.6 ms apart, in `setup-b-peq-8351b` at 22.461 s. No other capture holds it. The payload is the bare opcode.

**What the captures show.** A broadcast gets no reply. GLM polled no monitor after it. It asked the adapter for `39`, `19 01`, and `51 82`, sent the wake pairs, and at its next probe, 1.5 s after their last poll, all six monitors answered. GLM leased them `0B` to `10` and applied Main 4x2. A monitor that holds a lease ignores the probe, and the shortest lapse we've timed is 2.45 s. So something dropped the leases: the `03`, or the wake pairs after it. A wake drops a woken monitor's lease, but no capture shows a wake sent to monitors already on. GLM didn't relaunch: it kept counting sessions. The owner made no change then. Opening Main.sam in `setup-j-restore` re-read the adapter too, but sent no `03` and leased nothing.

**hlm.** §7 has no opcode `03`. `03` appears only as `3A 03`, power.

**Guess:** `03` tells every monitor to drop its lease, so GLM can set the system up again from the probe. The capture can't tell it from the wake.

**Need.** None. qlm takes leases back by serial, and never needs to drop them. Keep it refused.

## The allowlist, as recommended

| Frame | Change | When |
| --- | --- | --- |
| `2D 00` | Allowed: this payload only, as a broadcast only. System sends it right before `FF 3D 00 00`. | Done, in Phase 2 for dim's byte match |
| `3C 00 00`, `3E 00 00`, `42 00 00` | Allowed: these payloads only, to a session only. System sends them to subwoofers only. | Done, in Phase 3 |
| `43 00 02`, `4B 00 00 00 01` | Allowed: these payloads only, to a session only. System sends them to the 8351B only. | Done, in Phase 3 |
| `05 …` | Keep refused. | Never. AGENTS.md forbids it. |
| `01 22`, `01 51 82` | Keep refused. | Not needed |
| `FF 03` | Keep refused. | Not needed |
| `01 2B`, `FF 3D 00 00`, the wake | Already allowed. System sends them. | Phase 2 |

The allowlist accepts by opcode, with finer checks for `02`, `10`, and `3A`. `2D 00` is its first exact-payload entry, and the encoder's first rule by opcode and address. The golden test's refused set shrinks with each one.

## The group apply

GLM sends two kinds of apply. `QLMApplySequence` builds both, System sends them, and `qlmctl apply-group --dry-run` prints them. `QLMApplyGoldenTests` diffs each against all eight captured applies, once GLM's cycle and the generator stop are left out. "In device order" is the setup's device list. "On" means the monitor's last telemetry says on.

**At launch and wake** (`startup-idle`, 8.534 to 9.901 s). For each new monitor, in lease order: `FF 04`, a subwoofer's `3B`, `05 04`, `17 01`, a two-way's extra `FF 04`, the rest of its block, `39`, and `19 01`. Off nodes get their block too. Then a round to the other monitors that are on, and the pair. Each new monitor gets its state right after its next poll. System sends this as its first apply, and to any monitor leased while a group is active, once the probe finds no more.

**A group switch** (`group-switch-main-4x2-main-2x1`, 12.359 to 13.476 s):

1. `FF 1F 00 00 08`, then the duck, `FF 1F 00 00 02`.
2. `FF 3A 03 7F` twice.
3. The routing pass, in the group's node order. A node that is on gets `3A 03 01` twice, and one that is off `3A 03 02`. A subwoofer gets `3B`. Then `05 04`, the state if the monitor is on, the routing frames, and the state again.
4. A round, then the DSP pass in device order: `FF 04` for every node, and the block of each one that is on.
5. `01 2B 00`, two rounds, the volume three times, a round, and the pair.

A round restates the state of every monitor that is on, in device order. In the group it is `2B 04`, or `03` if muted. Outside it is `2B 05` then `07`, and `07` alone in the first of two rounds (`knob-sweep`, 19.135 s). Mute, dim, and the knob send the same rounds.

The tests match byte for byte for the apply at launch, the one after a wake, and the switch from 4x2 to 2x1. Each other switch differs only where GLM raced itself:

- **GLM's cycle runs beside its apply.** In `group-switch-main-4x2-main-2x2`, its polls found two monitors in standby mid-tail, so its later rounds left them out. System's cycle waits behind the apply, so its rounds keep them.
- **GLM sent `01 2B 00` twice** in two switches, mid-round. No capture says why.
- **GLM left out the last round and the pair** in `group-switch-main-2x2-main-2x1`, though it sent them in the other five.
- **A monitor woken into the group loses its lease.** GLM then applies its block at the new lease beside the switch's restore. System sends the restore, then the block.
- **GLM ran the switch twice** in `group-switch-main-2x1-main-2x2`, after the 7350A lost its lease. The test compares the first pass.
- **GLM cuts a pass short when it leases the monitor again.** In `setup-b-peq-8351b`, at 183.450 and 300.973 s, the 7350A took a new session mid-pass. GLM stopped its pass at the old one, and sent the whole block at the new one. The short pass is the block's start, frame for frame, and `compare-apply` checks it as that.

Any group with an 8351B is still refused for a real apply: every node's block must build at a verified rate, on or off. The dry run still prints such a group, `43` and `4B` included, and ends with REFUSED.

## Open

1. **The level the adapter applies when the host leaves.** The meters in `qlm-first-discover` point at the knob. A test with qlm alone can settle it:
   1. Play steady noise. Set the knob 10 dB below qlm's level, so the likely jump is down.
   2. Have qlm send its level, and read `42` and `43` for several polls.
   3. Turn qlm's level to the knob's position and read them again.
   4. Restore qlm's level, then send nothing for 5 s.
   5. Poll again without sending a volume. If `43` matches step 3, the adapter applied the knob.

   Pick levels where `43` reads well above `80` at both. Keep both low, as AGENTS.md asks. The bus tap reads the adapter's `F0 1F` level directly. A setup with no knob attached is a separate case.
2. **Whether `01 22` or `01 51 82` changes the adapter's bus behavior,** such as its defer broadcast. The bus tap, with qlm running without them, can show it.
3. **What the `2D` and `3D` pair does to the subwoofers,** and whether their busy marker means a write to flash.
4. **What `3C`, `3E`, `42`, `43`, and `4B` carry.** A capture of a setup change to the LFE fields, `GroupDelayCompensation`, or `BassExtensionXO` would map them. qlm builds `43` and `4B` from the 8351B's two fields, matched only at 2 and 1.
5. **What the adapter does with `01 2B 01`,** and whether a mute survives the hand-back.
6. **What `82` selects in `01 51 82`,** and what `219000` is.
7. **What a broadcast `03` does, and what made GLM send it** in `setup-b-peq-8351b`.

## Sources

- The captures in `captures/`, decoded from `reports.txt` with the CRC checked on every frame.
- hlm's spec, revision 13, at robcazzaro/hlm commit `c08ced9`: §4, §6, §7, §8, §8.1, §9, and Appendix B. Facts only. No text or code was copied.
- [adapter-status.md](adapter-status.md), for genlc's names of opcodes `22` and `51`.
- `Tests/Setups/Fixtures/Main.sam`, the redacted setup, for the fields of each model.
