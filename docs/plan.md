# qlm: the plan

**Status: 2026-10-25. Everything that needs no adapter is built and tested against a fake bus. Nothing has touched real hardware. Phase 0 is next.**

## Where things stand

Built, with 79 tests, every protocol fact named by its section of hlm's spec:

- **GLMProtocol:** framing, the allowlist, the builders with the volume clamp, and the reply parsers.
- **GLMAdapter:** the adapter protocol and a fake bus. **The adapter over HID is not written.** The spec does not cover the USB reports, so it waits for a capture.
- **System:** discovery, leases, the poll cycle, volume, mute, dim, power, the group apply, and snapshots.
- **Setups:** a strict reader for GLM 5 setup files, the filter design, and the DSP block.
- **The app and `qlmctl`:** both run over the fake bus. `qlmctl setup` and `apply-group --dry-run` run on a real setup file.
- **The capture kit:** `captures/README.md`, `tools/inventory.sh`, `tools/pcapng-to-reports.py`, and the Pi proxy in `tools/pi/`.

Waiting on the captures:

- The USB report layer: the host report prefix, and reassembly of a reply across reports. Then the HID adapter, the replay adapter, and golden tests over every captured frame.
- Three readings marked unverified in code: a monitor's delay taken from `Time-of-flight_Compensation` as milliseconds, the analog routing frame, and matching a setup node to a monitor by the bus serial's suffix.
- Whether the address byte is escaped. The code sends it bare.

The user's system, from their setup file: two 8351B, two 8330A, a 7370A, and a 7350A. The file designs the 8351B bands at 96 kHz, the 8330A at 48 kHz, and the subwoofers at 12 kHz. The 8351B rate is unverified on the wire, so a group apply that includes one is refused.

qlm is a native Mac controller for Genelec SAM monitors. It replaces GLM for daily use on the Mac. It shows the system's status. It sets volume, mute, dim, and power. It switches groups. GLM stays installed for calibration and setup. The app never measures, calibrates, or edits a setup.

"Scene" in this plan means one group of one GLM setup file. Switching to a group in the same setup is a delta. Switching to another setup is a full reconfiguration.

## What is already known

Most of the protocol is public. Three independent projects mapped it, and two of them now cross-check each other. **All three are GPL-3.0** (see Licensing).

| Project | What it gives us |
| --- | --- |
| [genlc](https://github.com/markbergsma/genlc) (2021, Python) | The USB side. It drives the GLM adapter over HID: discovery, addresses, wake, shutdown, volume, mute and LED, polls, and queries to the adapter itself. |
| [hlm](https://github.com/robcazzaro/hlm) (2026, STM32 firmware) | The bus side. A protocol spec, revision 13, with confidence levels per command. |
| [espgensam](https://github.com/markbergsma/espgensam) (2026, ESP32) | Group switching. It reads GLM 5 `.sam` files, designs the filters, and pushes them. PEQ, level, and crossover are acoustically verified on an 8330A. It also records GLM's group-switch sequence frame by frame. |

### The adapter is a thin bridge

- **USB:** a HID device. genlc matches VID `0x1781`, PID `0x0E39`, with 64-byte reports. Verify both against your adapter.
- **Host to adapter:** one output report of `0x80 + length`, then the escaped frame. genlc's leading `0x00` is hidapi's report-ID byte, not data.
- **Adapter to host:** 64-byte input reports, each starting with `63`. One reply spans up to three reports. After reassembly, the reply is a normal bus frame. genlc treats `0x7E` in the reply-code position as "no device answered". That is its guess.
- **Bus frame:** address, command, data, CRC-16/GSM (big-endian), then `0x7E`. HDLC escaping applies to `0x7E` and `0x7D` after the CRC is computed. The adapter adds the RS-485 ninth bit itself.
- **Size:** the largest frame the app sends, a PEQ band, is 28 bytes. Fully escaped, it still fits one report.

### The host is the bus master

While a host is connected, the adapter only bridges. The host runs discovery, address leases, the keep-alive, polls, volume, and configuration. The adapter broadcasts `F0 1F 00 00 00` about every 610 ms to say it defers. About 2.6 s after the host goes quiet, the adapter takes over as a standalone volume master with its own level.

### Each feature on the wire

| Feature | Mechanism | Confidence |
| --- | --- | --- |
| Find monitors | `FF FE` probe, `F0 02` lease, `09` ack; re-discover after 4 missed polls | High, both projects |
| Identify | `19 01` serial; `39` model, firmware, hardware | Medium to high |
| Status | `08` poll returns `41` TLVs: temperature, power state (`47`), device class (`84`), input and output meters | High for state and temperature; meter scale is approximate |
| Volume | `FF 1F` + 24-bit linear gain, `floor(10^(dB/20) × 2²³)`; fire and forget, sent at once on change | High |
| Dim | A plain volume frame 20 dB down; there is no dim command | High |
| Mute | `2B` bitfield per monitor; bit 0 is mute, other bits drive the LED | High. Telemetry does not show mute, so the app tracks it. |
| Power | `3A 03 02` ×2 then `3A 03 00` ×2 to sleep; `3A 03 7F` / `3A 03 01` ×3 to wake | High |
| Group switch | duck, wake, routing pass, DSP pass (`17 01`, `10 02` delay, `10 01 00` level, `10 01 09`, `10 0E` PEQ ×20, `3B` crossover, `3D`, `40` routing), tail, restore | High for two-way monitors; medium for subwoofers (from captures, not measured); unknown for 83x1 and three-way models |
| The knob, while a host owns the bus | **Unknown** | — |
| How the adapter decides a host is present | **Unknown** | — |

The 9310 knob plugs into the adapter's 3.5 mm jack. Standalone, the adapter reads it and broadcasts the volume itself. Nobody has published how its turns reach GLM when GLM is connected.

### The setup file

GLM 5 saves setups as `.sam` files. espgensam's README shows them under `~/Documents/Genelec/GLM5/Setup Files/`. espgensam's importer documents the mapping:

- **PEQ:** 20 slots per device. A two-way monitor has two low shelves, two high shelves, and 16 peaking bands. A subwoofer has 20 peaking bands.
- **Design rate:** 48 kHz for two-way monitors and 12 kHz for subwoofers. The wrong rate moves every filter by 4×. The rate for 83x1 models is unresolved.
- **Shelves:** RBJ formulas in Q form, with Q 0.3 for low shelves and 0.5 for high shelves. The wire carries `b0 b1 b2 −a1 −a2`, normalized by `a0`, as little-endian floats. A band at exactly 0 dB goes out as `1, 0, 0, 0, 0`.
- **Level:** `Level_Sensitivity` plus `Group_Sensitivity`, sent as one word scaled by 2²³ − 1.
- **Delay:** in 48 kHz samples on every device. On a subwoofer it is the AutoPhase angle turned into a delay.
- **Crossover:** `1` means full band.
- **Not mapped yet:** `Optional_Gain`, `Time-of-flight_Compensation`, `Video_Delay`, `SubwooferGroupID`, and the LFE crossover.

## Decided

- **The name is qlm, and the prefix for classes and C symbols is `QLM`.** The CLI is `qlmctl`.
- **A Mac app first:** a menu bar item, with a window for detail. iOS cannot reach a USB HID device without DriverKit, so a phone remote would go through the Mac later.
- **Objective-C and AppKit, as in Vibe**, so vibe-libs pieces compile in through their templates with no bridging. GLMProtocol is plain C with no Apple dependency, so a CLI and the tests share it.
- **A CLI, `qlmctl`, comes before the UI.** Every experiment and every acceptance test runs from it.
- **The app never writes to a monitor's flash.** It never sends `15` (commit), `05` (test signals), or the standalone settings in `3A 01`, `3A 02`, and `3A 06`. GLMProtocol sends only opcodes on an allowlist.
- **Volume is clamped in GLMProtocol, not the UI.** `7F FF FF` is 0 dB. A user ceiling caps every volume frame, and a test proves that no code path exceeds it.
- **GLM and the app never own the bus at once.** The app refuses the adapter while GLM runs, and it offers to quit GLM.
- **Groups for unverified models are refused.** Status, volume, mute, and power still work on them.

## Open, for you to decide

1. **The knob.** Is there a 9310 on the adapter? Its path to the host is unknown.
2. **Capture machine.** Decided: a Raspberry Pi 5 inline between the Mac and the adapter. [captures/README.md](../captures/README.md) has the steps.

## Architecture

Four layers. Each meets the next through values and blocks.

1. **GLMProtocol (C, pure).** Framing, escaping, CRC, report packing and reassembly, command builders, and reply parsers: ack, hardware ID, telemetry TLVs, and ASCII strings. No I/O. Golden tests: every captured frame decodes and re-encodes byte for byte.
2. **GLMAdapter.** `IOHIDManager` matches the adapter. `IOHIDDeviceSetDispatchQueue` delivers input reports to System's queue. It keeps one request in flight, with a timeout, and handles hot plug. Two stand-ins share its interface: a replay adapter that plays a capture, and a fake bus that simulates monitors, lease loss, and dropped replies.
3. **System.** One serial queue owns the bus. It runs the lease registry (hardware ID to session ID) and the cycle GLM runs: volume, `04`, a `08` round, and `FE`, every 1.2 to 1.8 s. It coalesces volume to at most one frame per 50 ms. It tracks mute in software. It runs a group apply as one transaction. It publishes an immutable snapshot of the monitors after each change.
4. **Setups.** It reads `.sam` files into groups. It designs the biquads at each device's rate and checks that each filter is stable. It builds each monitor's DSP block as values. It reports every field it cannot carry, never dropping one silently. It watches the file and offers a re-import when GLM saves.

The app reads snapshots on the main queue. Nothing in the UI touches GLMAdapter.

### The repository

```
qlm/
├── AGENTS.md  README.md  Makefile  Brewfile  project.yml
├── docs/plan.md
├── qlm/            all the code, one directory per layer
│   ├── GLMProtocol/  C, no Apple dependency
│   ├── GLMAdapter/   the adapter protocol and the fake bus; HID and replay to come
│   ├── Setups/       the setup file reader; filter design and the DSP block to come
│   ├── System/       the engine and its snapshots
│   ├── App/          the menu bar app: AppKit, Objective-C
│   └── CLI/          qlmctl
├── Tests/          one XCTest bundle, hostless; mirrors qlm/
├── captures/       the Phase 0 captures, one directory per scenario
├── tools/          the inventory script and the capture converter
├── vibe-libs/      the shared toolbox, a git submodule
└── .github/        CI: tests and both builds on macOS
```

Every layer has its directory. `project.yml` compiles the layers into each target through one template, with one entry per layer, as Vibe lists its subsystems.

### Behavior System must copy from GLM

- **On every connect and wake, apply the active group in full**, as GLM does. Monitors may have rebooted to their flash settings, and leases are reassigned.
- **A group apply ducks first and restores after.** Expect a short silence, as with GLM.
- **On a group switch, send only the bands that changed**, as GLM does. A full apply sends all of them.
- **Volume changes go out at once**, out of cadence. State changes are sent twice.
- **TRAP: when the app quits, sleeps, or loses USB, the adapter takes over with its own level about 2.6 s later.** If that level differs from the app's, the volume jumps. Phase 0 must find which level the adapter uses.

### The UI

- **Menu bar popover:** volume in dB, in 0.5 dB steps; mute; dim; the group picker; power. One status dot per monitor: online, standby, or offline.
- **Window:** each monitor's model, serial, firmware, temperature, power state, approximate input and output meters, and last reply.
- **Settings:** the setup files, the volume range and ceiling, whether to wake the monitors at launch, and launch at login with `SMAppService`.
- **The knob drives the app's volume**, if Phase 0 finds the path. Otherwise it works only while the app is closed.

## Where vibe-libs fits

| Piece | Use |
| --- | --- |
| core/Common | log and signpost macros, work lanes, the display-paced timer for meters, build provenance |
| ui/Controls | the mac sliders and buttons, and the detent slider for volume |
| system/Updates | Sparkle, for a direct-download build |
| dev/DebugChannel | drive a running debug build from a script, for tests against the real monitors |
| audio/OutputDevices | later: switch groups when macOS changes output device, for example analog to AES |

Nothing else applies: no decoding, playback, tags, or waveforms.

**The submodule is in place at `vibe-libs/`, but this app includes nothing from it yet.** When a target takes its first piece, `project.yml` adds `include: [vibe-libs/vibe-libs.yml]`, sets `VIBE_LIBS_ROOT`, and lists the pieces under `templates:`. The comment at the top of `project.yml` has the steps.

**Two pieces have moved so far**: `core/Common`, with only the realtime brackets, and `audio/DSP`, with Vibe's varispeed. Neither helps this app yet. The log and signpost macros move with the first piece that logs, in vibe-libs Phase 3. The mac controls, Updates, and DebugChannel wait for a second app in vibe-libs Phase 5. This app is that second app, so it triggers those moves. It must not wait for them. It starts on Apple's frameworks and adopts each piece as it lands.

**The protocol stays in this app.** No other app needs it, so by vibe-libs's own rule it is not a candidate.

vibe-libs's `AGENTS.md` says its users are Vibe and one other app. This would be a third, so that line needs an update when the app takes its first piece.

## Licensing

qlm is Apache 2.0, like vibe-libs. genlc, hlm, and espgensam are GPL-3.0, and the hlm spec is copyrighted text inside that distribution. The protocol's facts are not copyrightable. Their code and wording are.

So every line is written from the facts and from qlm's own captures. Port no code, including espgensam's `.sam` mapping and biquad code. Every protocol fact in code names its source in a test: a capture in this repo, or a section of hlm's spec.

Two other risks. GLM's license may forbid reverse engineering the software. Capturing USB and bus traffic avoids touching GLM's binary, so prefer it to disassembly. Firmware updates may change the protocol, so the app warns on any firmware version it has not seen.

This is not legal advice.

## The work, in order

### Phase 0: inventory and captures

**Record the system.**

- Each monitor's model, serial, and firmware, from GLM.
- The adapter's descriptors and HID report descriptor: `ioreg -p IOUSB -l -w0` and `hidutil list`. Confirm the VID, PID, report sizes, and usage page.
- A copy of every `.sam` file, and a screenshot of each group in GLM as ground truth.

**Capture USB traffic of GLM 5.** USB capture on a current Mac needs SIP disabled, and reports say it fails on Apple silicon. I have not tested this. Use one of these:

1. **Windows, with USBPcap and Wireshark**, on a PC or in a VM with the adapter passed through.
2. **A Raspberry Pi 5 inline proxy** (the route chosen). GLM stays on the Mac. The Pi relays the adapter with usb-proxy over raw-gadget, and `usbmon` on the Pi records it.
3. **Mac only:** Frida hooks on `IOHIDDeviceSetReport` and the input callback in a re-signed copy of GLM. It needs no extra hardware, but it does touch GLM's binary.

Capture each scenario:

- startup, then 2 minutes idle
- a volume sweep in GLM
- a knob sweep, and any knob press
- every pair of group switches
- mute and unmute per monitor, and dim
- standby and wake
- quitting GLM
- unplugging the adapter
- Mac sleep and wake

**Optionally, tap the bus.** espgensam's listen-only build on a Waveshare ESP32-S3-RS485-CAN decodes every frame. It is isolated and costs under $40. With the adapter attached, pull the board's terminator jumper. The tap later diffs the app's bus output against GLM's.

**Done when** the captures answer three questions:

- how the adapter knows a host is present
- how knob turns reach the host
- what level the adapter applies when the host leaves

One group switch must also decode to the sequence espgensam documents, for your models.

### Phase 1: GLMProtocol, GLMAdapter, and a read-only CLI

- The codec, with golden tests from the Phase 0 captures.
- The HID adapter, the replay adapter, and the fake bus.
- CLI commands `info`, `discover`, and `poll`.

**Done when** the CLI lists every monitor with model, serial, firmware, temperature, and power state, with GLM closed. Fake-bus tests must cover lease loss, rediscovery, and a lost reply.

### Phase 2: control from the CLI

- Volume with the ceiling, dim, mute per monitor and for all, sleep and wake.
- The knob, if Phase 0 found its path.

**Done when** each action's frames match GLM's captured frames byte for byte, apart from session IDs. The knob must move the volume through System in the CLI. Quitting the CLI must hand the bus back to the adapter without an unplanned level jump.

### Phase 3: groups

- The `.sam` reader, the filter design, and the DSP block.
- `apply-group --dry-run`, which prints the frames.

**Done when:**

- For every group in your setups, the dry run matches GLM's captured frames: the same slots, level words, delays, and routing, and coefficients within 1e-6.
- At a low level, one monitor first, the app applies each group.
- A measurement (REW and a measurement mic) after the app's apply matches one after GLM's apply within 0.2 dB.

### Phase 4: the Mac app

- The menu bar item and the window over System's snapshots.
- Settings, and detection of a running GLM.
- Sleep, wake, and hot plug.
- A notification when a monitor drops off or runs hot.

**Done when** a week of daily use without GLM brings no crash, and every dropped monitor recovers on its own. Volume must reach the bus within 50 ms of the slider. A group switch must finish within 2 s.

### Later

Each is optional:

- Shortcuts actions for group, volume, and mute.
- Global hotkeys.
- MIDI input with GLM's mapping, so existing MIDI controllers keep working.
- A calibration bypass toggle.
- Group switching by output device.
- A phone remote through the Mac app.
- The CLI on Homebrew.

## Risks

| Risk | Answer |
| --- | --- |
| A bug sends full volume | The clamp in GLMProtocol, the ceiling, and a test across every builder |
| Filters designed at the wrong rate | Rate from the model; groups refused for unverified models; a stability check on every biquad |
| Subwoofer LFE fields unmapped | Warn on, or refuse, a group that sets them until a capture maps them |
| The adapter's level when the app leaves | Found in Phase 0; the app matches it before it exits, if the protocol allows |
| GLM and the app both drive the bus | Detection and refusal |
| A firmware update changes the protocol | A version check, a warning, and GLM kept installed |
| GLM changes the `.sam` format | A strict reader that reports unknown keys |

## Sources

- [genlc](https://github.com/markbergsma/genlc): `transport.py`, `gnet.py`, `const.py`, and `sam.py`
- [hlm](https://github.com/robcazzaro/hlm): `docs/Genelec GLM Protocol.13.md`
- [espgensam](https://github.com/markbergsma/espgensam): `README.md`, `docs/glm-group-apply.md`, and `components/gensam/sam_import.py`
- [Genelec GLM in the living room](https://jb1c.blog/2021/02/02/genelec-glm-in-the-living-room/): the adapter over usbip
- [Genelec 9310A listing](https://www.soundseasy.com.au/products/genelec-9310a-wired-volume-controller): the knob on the adapter's 3.5 mm jack
- [Genelec support: the 9320A without GLM](https://support.genelec.com/hc/en-us/articles/19924050319250-Can-I-use-the-9320A-without-GLM): group switching needs GLM
