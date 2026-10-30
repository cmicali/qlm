# Frames GLM sends that qlm does not

GLM sends some frames that qlm refuses or leaves out. The allowlist refuses `05`, `3C`, `3E`, `42`, `43`, `4B`, and `22` and `51` to the adapter. `testEveryOutputReportRepacksByteForByte`, in `Tests/GLMProtocol/QLMGoldenTests.m`, pins that set. The allowlist accepts the rest. Broadcast `2D 00` was refused too, and is now allowed. System now sends it, broadcast `3D`, and `2B` to the adapter, as GLM does. It does not send the wake at startup. This doc says what each one does, and whether qlm needs it.

A time is seconds into that capture's `reports.txt`. "hlm §7" is section 7 of hlm's spec, `docs/Genelec GLM Protocol.13.md` in robcazzaro/hlm, revision 13, at commit `c08ced9`. Its facts are restated here in our own words. **Guess:** marks a guess. The code is as of `e55a0ba`.

## Short answers

| Frame | Where GLM sends it | qlm today | Does qlm need it? |
| --- | --- | --- | --- |
| `05 04 …` | Every monitor's DSP block, and a group switch's routing pass | Refused | No. AGENTS.md forbids `05`. |
| `3C`, `3E`, `42` | Each subwoofer's DSP block | Refused | Phase 3, to match GLM's apply |
| `43 00 02`, `4B 00 00 00 01` | Each 8351B's DSP block | Refused | Phase 3, once the 8351B's rate is verified |
| `FF 2D 00` | With `FF 3D 00 00`: startup, wake, group switch, dim, and knob unplug | Allowed, as a broadcast only. Sent in dim. | Phase 2, only for dim to match GLM byte for byte |
| `FF 3D 00 00` | Right after every `FF 2D 00` | Accepted. Sent in dim. | As for `2D` |
| `01 22` | Once per connection | Refused | No |
| `01 51 82` | Once per connection | Refused | No |
| `01 2B 00`, `01 2B 01` | Mute all, unmute all, startup, each knob-driven level, and a group switch's tail | Accepted. Sent at mute all, unmute all, and each knob-driven level. | Phase 2, for mute all |
| The wake | Startup and wake | Accepted, not sent at connect | Phase 2, for power |

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

**Where.** Always `05 04 00 00 00 FF FF EA 00 01 90 00 02 DA`, 85 times in 12 captures. It opens each monitor's DSP block, right after `FF 04`. At startup every monitor gets one (`startup-idle`, 8.535 s for `02`). In a group switch it comes in the routing pass, after `3A 03 01` twice (`group-switch-main-2x2-main-4x2`, 10.412 s).

**What the captures show.** The monitor answers `01 09`, 76 times. The other 9 got `01 7E`, from monitors still waking in a group switch: `08` at 10.412 s, 23 ms after its second `3A 03 01`, in the same capture. No later reply can be tied to it alone, since the rest of the block goes out with it.

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

### `43 00 02` and `4B 00 00 00 01`, to the 8351B

**Where.** Only to the two 8351B. `43 00 02` follows the level pair `10 01 00` and `10 01 09`, before the PEQ slots. `4B 00 00 00 01` follows `3B`, before `3D`. In `startup-idle`: to `03` at 8.650 and 8.725 s, and to `06` at 9.048 and 9.116 s. Across 12 captures: `43` 27 times and `4B` 27, always with these payloads.

**What the captures show.** The 8351B answers `01 09`. One `01 7E` came from an 8351B still waking (`standby-wake`, 46.784 s, to `11`). No later reply can be tied to them. The payloads stay put when the group changes. Main 2x1 has a 60 Hz crossover and `RateFlatness` and `RateCorrelated` at −1 (`startup-idle`, `3B 00 3C` at 8.723 s). Main 4x2 has 85 Hz and both at 0 (`standby-wake`, `3B 00 55` at 46.775 s). Both send the same `43` and `4B`.

**The setup file.** The 8351B nodes, class `ThreewayGen2`, carry fields the 8330A nodes lack. Two hold the same value in every group: `GroupDelayCompensation:2` and `BassExtensionXO(Hz):1`. **Guess:** `43 00 02` carries the first, and `4B 00 00 00 01` the second, which sits next to the crossover as `4B` follows `3B`. Against the first: the 7350A also has `GroupDelayCompensation:2`, and gets no `43`.

**hlm.** §7 has neither opcode. §4 and Appendix B item 1 leave the 83x1 filter design rate open.

**Need.** Phase 3, but only after the 8351B's rate is verified. Until then AGENTS.md refuses any group apply with an 8351B, so qlm never needs them. Then allow exactly `43 00 02` and `4B 00 00 00 01`, to the 8351B only, where GLM sends them. Neither is on the never-send list.

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

**Now.** The allowlist accepts exactly `2D 00`, and the encoder sends it only to `FF`. Every other `2D` payload and address is refused. `QLMFrameTests` covers both. System's dim sends GLM's whole sequence, `2D 00` included, and `QLMSystemGoldenTests` checks it against `mute-dim` byte for byte. Dim is the only place System sends broadcast `3D 00 00`. The group apply sends `3D 00 00` only to one monitor at a time, and GLM never puts `2D 00` before that: in every capture, all 39 broadcast `3D 00 00` follow `2D 00`, and none of the 73 unicast ones does. GLM also sends the pair after a round of `2B` in a group switch. System's apply does not yet, which is Phase 3's to match.

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

## The allowlist, as recommended

| Frame | Change | When |
| --- | --- | --- |
| `2D 00` | Allowed: this payload only, as a broadcast only. System sends it right before `FF 3D 00 00`. | Done, in Phase 2 for dim's byte match |
| `3C 00 00`, `3E 00 00`, `42 00 00` | Allow these payloads only. System sends them to subwoofers only. | Phase 3 |
| `43 00 02`, `4B 00 00 00 01` | Allow these payloads only. System sends them to the 8351B only. | Once the 8351B's rate is verified |
| `05 …` | Keep refused. | Never. AGENTS.md forbids it. |
| `01 22`, `01 51 82` | Keep refused. | Not needed |
| `01 2B`, `FF 3D 00 00`, the wake | Already allowed. System sends them. | Phase 2 |

The allowlist accepts by opcode, with finer checks for `02`, `10`, and `3A`. `2D 00` is its first exact-payload entry, and the encoder's first rule by opcode and address. The golden test's refused set shrinks with each one.

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
4. **What `3C`, `3E`, `42`, `43`, and `4B` carry.** A capture of a setup change to the LFE fields, `GroupDelayCompensation`, or `BassExtensionXO` would map them.
5. **What the adapter does with `01 2B 01`,** and whether a mute survives the hand-back.
6. **What `82` selects in `01 51 82`,** and what `219000` is.

## Sources

- The captures in `captures/`, decoded from `reports.txt` with the CRC checked on every frame.
- hlm's spec, revision 13, at robcazzaro/hlm commit `c08ced9`: §4, §6, §7, §8, §8.1, §9, and Appendix B. Facts only. No text or code was copied.
- [adapter-status.md](adapter-status.md), for genlc's names of opcodes `22` and `51`.
- `Tests/Setups/Fixtures/Main.sam`, the redacted setup, for the fields of each model.
