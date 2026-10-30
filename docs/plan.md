# qlm: the plan

**Status: 2026-10-30. Phase 0's captures are in, and Phase 1 is done. In Phase 2, the controls ran on one monitor, and every frame matched GLM's. The adapter hands back at the knob's position. Phase 3's group apply matches GLM's in the dry run. The app's UI runs on the fake bus. Next come the control run's safety fixes, then the hand-back.**

## Where things stand

Built, with 234 tests, every protocol fact named by its section of hlm's spec or by its capture:

- **GLMProtocol:** framing, the allowlist, the builders with the volume clamp, the reply parsers, the adapter's status reply, and the USB report layer: packing an output report, assembling a reply across input reports, and which messages get a reply. The volume word comes from GLM's own 200 levels, and the DSP block's level word floors, as GLM's does. The control builders match GLM's frames byte for byte.
- **GLMAdapter:** the adapter protocol, the adapter over IOKit HID, the report link under it, a fake bus, a capture reader, and a replay adapter that answers as a capture did. The HID adapter refuses the adapter while GLM runs, or while another process holds its HID device or has opened its USB device. A process that only enumerates it does not count. It opens the adapter only seized, so a failed seize is a refusal. It has run on the adapter (`qlm-first-discover`, `qlm-standby-discover`).
- **System:** the adapter's identity and status poll, discovery, leases, the poll cycle, volume, mute, dim, power, the group apply, and snapshots. Dim, mute all, and the power steps go out as GLM sends them. The user's mutes are kept by hardware ID, so a monitor leased again comes back muted. System follows the knob: its first turn jumps the volume to the knob's position, under the ceiling, and the volume follows after. A gap in polling leads to new leases. On the adapter, System found all six monitors, on and in standby, and its cycle matched GLM's. The group apply is GLM's, both the apply at launch and a group switch, with the subwoofer frames and the group's membership. The golden tests compare it with all eight captured applies. Apart from the frames qlm skips, three match exactly, and the rest differ only where GLM raced itself. An apply to any group with an 8351B is still refused.
- **Setups:** a strict reader for GLM 5 setup files, the filter design, and the DSP block. Every DSP block is checked against GLM's captured passes.
- **`qlmctl`:** `info`, `discover`, and `poll` have run on the adapter. `volume`, `mute`, `dim`, `sleep`, and `wake` have run on one monitor (`qlm-control-first`). They run behind gates: a ceiling the user states, at most −30 dB without `--allow-high-ceiling`, a `--dry-run` that sends only discovery, and a warning about the hand-back at exit. Each also runs on the fake bus with `--fake`, or a capture with `--replay`. `qlmctl setup` and `apply-group --dry-run` run on a real setup file. `apply-group` prints GLM's whole apply, and never reaches USB.
- **The app:** the menu bar popover, a monitors window, Settings, a banner for adapter errors, and a panel that plays the fake bus. It runs on the fake bus only.
- **The capture kit:** `captures/README.md`, `tools/inventory.sh`, `tools/pcapng-to-reports.py`, and the Pi proxy in `tools/pi/`.
- **The captures:** every scenario in `captures/README.md`, 17 in all, and qlm's own runs: `qlm-first-discover`, `qlm-standby-discover`, and `qlm-control-first`. Each is xz-compressed, with `reports.txt` and `notes.md`. `sleep-wake` never caught a true sleep. The golden tests read every report in them.
- **The frames qlm does not send:** [refused-frames.md](refused-frames.md) says what each one does, and whether qlm needs it.
- **The protocol reference:** [protocol.md](protocol.md) holds every protocol fact qlm knows, with its source.

Decided since Phase 1:

- **qlm matches GLM byte for byte.** So the allowlist takes exactly `2D 00`, as a broadcast right before `FF 3D 00 00`, and dim sends it.
- **qlm refuses the adapter only for GLM, or for a process that holds it the way GLM does.** A process that only enumerates it does not count. Spotify puts a USB device client on every USB device, the adapter among them, and that made qlm refuse in `qlm-standby-discover`. GLM's client is an HID library client that has opened the HID device.
- **The hand-back.** When qlm stops, it compares the knob's position with its own volume. If the knob is at or below it, qlm sends the knob's level just before it lets go, so the adapter's take-over changes nothing. If the knob is above it, the take-over would make the level louder, so qlm warns instead.
- **The 8351B in a supervised test.** `qlmctl apply-group` may apply a group with an 8351B over USB only behind an explicit flag, at a low level, one monitor first. The app still refuses. A measurement after that apply decides whether the refusal lifts.

Next:

- The control run's safety fixes, from `qlm-control-first`:
  - Send the volume to each monitor the moment System leases it. A monitor that is switched on plays at its own stored level until a host sends one.
  - Send the volume on wake.
  - Make `qlmctl dim` send GLM's whole sequence. It sets dim before the volume, so it sends only the dimmed level.
  - `mute --serial` restates every other monitor as unmuted, as GLM does, so a monitor muted in GLM starts playing. Whether a monitor reports its mute state decides the fix.
- The hand-back, as decided above. The adapter takes over at the knob's position about 2.6 s after qlm stops, so qlm stops without a jump only when its volume equals the knob's.
- The app on the real adapter, behind a setting, with GLM's quit offered, sleep and wake, notifications, and the setup file watched.
- What System lacks for the app: a ceiling that changes while it runs, a kind of adapter error in the snapshot, and the group an apply is running.
- Phase 3 on the monitors. `apply-group` reaches only the fake bus, and every group in the user's setup has an 8351B. The supervised test, as decided above, opens it.
- The knob's slow drift. In `sleep-wake-darkwake`, GLM follows a 7 dB drift that qlm ignores until the knob's first turn.
- The analog routing frame, still marked unverified in code. No group in the user's setup uses input 4, so no capture shows it.
- Whether the address byte is escaped. The code sends it bare. No capture settles it, because GLM's session IDs never passed `19`. So the encoder refuses a `7D` or `7E` address, and System's leases skip both, and `F0`, the adapter's multicast. The question cannot arise.

### What the captures and runs showed

[protocol.md](protocol.md) holds every protocol fact qlm knows, each with its source. Each run's `notes.md` has its timeline. In short:

- **The adapter is a thin bridge.** It answers each probe and unicast with one frame: the monitor's reply, or its own `01 7E` when none answered. A broadcast gets none.
- **GLM's cycle:** about every 0.57 s, the probe, the volume, and one `08` to each monitor. Between cycles, it polls the adapter with a pair of `01 08` about every 107 ms. qlm's cycle matches it (`qlm-first-discover`).
- **The knob rides the adapter's reply to `01 08`.** The host turns its position into a volume frame ([adapter-status.md](adapter-status.md)).
- **Leases.** A monitor that holds a lease ignores the probe. A monitor that wakes from standby loses its lease. Monitors drop a quiet host's leases within 23 to 42 s, and within 68 to 210 s in standby (`qlm-first-discover`, `qlm-standby-discover`).
- **Monitors in standby answer qlm without a wake** (`qlm-standby-discover`).
- **The adapter hands back at the knob's position, about 2.6 s after the host stops** (`qlm-control-first`). With no host, the knob sets the level.
- **A monitor that is switched on plays at its own stored level until a host sends one** (`qlm-control-first`).
- **A mute outlasts the host, and no reply reports it** (`qlm-control-first`; #27).
- **Every frame qlm has sent on the adapter is one GLM sends** (`qlm-first-discover`, `qlm-standby-discover`, and `qlm-control-first`; `QLMControlRunTests`). [refused-frames.md](refused-frames.md) covers the frames GLM sends that qlm does not.
- **A 5 dB step is too small to hear** in a quick test, so the control run tested the hand-back and the knob at −60 dB (`qlm-control-first`).
- **Phase 0's three questions are answered.** GLM sends nothing when it quits, so the adapter senses a host by its traffic. Knob turns reach the host in the adapter's reply to `01 08`. When the host leaves, the adapter applies the knob's position.

The user's system, from their setup file: two 8351B, two 8330A, a 7370A, and a 7350A. The file designs the 8351B bands at 96 kHz, the 8330A at 48 kHz, and the subwoofers at 12 kHz. On the wire, every 8351B band GLM sends matches qlm's 96 kHz design to the bit (`QLMDSPBlockGoldenTests`). No measurement confirms the rate yet, so a group apply that includes an 8351B is still refused.

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

While a host is connected, the adapter passes each request to the monitor bus and returns one reply. [protocol.md](protocol.md#usb-and-hid) has the USB side, and its [Framing](protocol.md#framing) the bus frame.

### The host is the bus master

While a host is connected, it runs discovery, the leases, the polls, the volume, and the configuration. About 2.6 s after the host goes quiet, the adapter takes over at its knob's position ([protocol.md](protocol.md#what-the-adapter-and-the-monitors-do-on-their-own)). [protocol.md](protocol.md#sequences) has each feature on the wire, step by step, with GLM's two kinds of group apply.

### The setup file

GLM 5 saves setups as `.sam` files. espgensam's README shows them under `~/Documents/Genelec/GLM5/Setup Files/`. espgensam's importer documents the mapping:

- **PEQ:** 20 slots per device. A two-way monitor has two low shelves, two high shelves, and 16 peaking bands. A subwoofer has 20 peaking bands.
- **Design rate:** 48 kHz for two-way monitors and 12 kHz for subwoofers. The wrong rate moves every filter by 4×. The 8351B's bands match a 96 kHz design on the wire (#10), but no measurement confirms it yet.
- **Shelves:** RBJ formulas in Q form, with Q 0.3 for low shelves and 0.5 for high shelves. A three-way's high shelf is Q 0.3 (#10). The wire carries `b0 b1 b2 −a1 −a2`, normalized by `a0`, as little-endian floats. A band at exactly 0 dB goes out as `1, 0, 0, 0, 0`.
- **Level:** `Level_Sensitivity` plus `Group_Sensitivity`, sent as one word scaled by 2²³ − 1 and floored (#15).
- **Delay:** in 48 kHz samples on every device. A monitor's is its `Time-of-flight_Compensation` in milliseconds. On a subwoofer it is the AutoPhase angle turned into a delay, rounded (#8).
- **Crossover:** `1` means full band.
- **A node's `Serial`** is its monitor's hardware ID, in decimal (#8).
- **Not mapped yet:** `Optional_Gain`, `Video_Delay`, `SubwooferGroupID`, and the LFE crossover.

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

1. **The knob.** Decided: no 9310. The adapter has its own optional volume knob. While it is attached, GLM locks its on-screen volume. Its position rides the adapter's reply to `01 08` ([protocol.md](protocol.md#volume-and-the-knob)).
2. **Capture machine.** Decided: a Raspberry Pi 5 inline between the Mac and the adapter. [captures/README.md](../captures/README.md) has the steps.

## Architecture

Four layers. Each meets the next through values and blocks.

1. **GLMProtocol (C, pure).** Framing, escaping, CRC, report packing and reassembly, command builders, and reply parsers: ack, hardware ID, telemetry TLVs, and ASCII strings. No I/O. Golden tests: every captured frame decodes and re-encodes byte for byte.
2. **GLMAdapter.** An IOKit matching notification finds the adapter, and handles hot plug. `IOHIDDeviceSetDispatchQueue` delivers input reports to System's queue. A report link keeps one request in flight, with a timeout. Replies name no request, so after a timeout it syncs with a query whose reply has a shape the late one cannot, and drops replies until that one comes. One link serves each arrival of the adapter, across reopens, and one that loses track waits for a replug. The adapter is refused while GLM runs or another process holds it, and opened only seized, so a failed seize is a refusal too. Two stand-ins share its interface: a replay adapter that plays a capture, and a fake bus that simulates monitors, lease loss, and dropped replies.
3. **System.** One serial queue owns the bus. It runs the lease registry (hardware ID to session ID) and the cycle GLM runs: `FE`, the volume, and a `08` round, about every 0.57 s. Between rounds, it polls the adapter with `01 08` about every 110 ms, for the knob. It coalesces volume to at most one frame per 50 ms. It tracks mute in software. It runs a group apply as one transaction. It publishes an immutable snapshot of the monitors after each change.
4. **Setups.** It reads `.sam` files into groups. It designs the biquads at each device's rate and checks that each filter is stable. It builds each monitor's DSP block as values. It reports every field it cannot carry, never dropping one silently. It watches the file and offers a re-import when GLM saves.

The app reads snapshots on the main queue. Nothing in the UI touches GLMAdapter.

### The repository

```
qlm/
├── AGENTS.md  README.md  Makefile  Brewfile  project.yml
├── docs/plan.md  docs/adapter-status.md
├── qlm/            all the code, one directory per layer
│   ├── GLMProtocol/  C, no Apple dependency
│   ├── GLMAdapter/   the adapter protocol, HID, the fake bus, and the replay
│   ├── Setups/       the setup file reader, the filter design, and the DSP block
│   ├── System/       the engine and its snapshots
│   ├── App/          the menu bar app: AppKit, Objective-C
│   └── CLI/          qlmctl
├── Tests/          one XCTest bundle, hostless; mirrors qlm/
├── captures/       the captures, one directory per scenario
├── tools/          the inventory script and the capture converter
├── vibe-libs/      the shared toolbox, a git submodule
└── .github/        CI: tests and both builds on macOS
```

Every layer has its directory. `project.yml` compiles the layers into each target through one template, with one entry per layer, as Vibe lists its subsystems.

### Behavior System must copy from GLM

- **On every connect and wake, apply the active group in full**, as GLM does. Monitors may have rebooted to their flash settings, and leases are reassigned.
- **After any gap in polling, lease again.** Monitors drop their leases within 23 to 42 s of the host going quiet (`qlm-first-discover`), and within 68 to 210 s in standby (`qlm-standby-discover`).
- **Keep the user's mutes by hardware ID.** A monitor leased again comes back muted, if the user muted it.
- **Send the volume to each monitor the moment it is leased.** A monitor that is switched on plays at its own stored level until a host sends one (`qlm-control-first`).
- **A group apply ducks first and restores after.** Expect a short silence, as with GLM.
- **Every apply sends all twenty bands to each monitor**, changed or not, as GLM does ([protocol.md](protocol.md#payloads)).
- **Volume changes go out at once**, out of cadence. State changes are sent twice.
- **Poll the adapter with `01 08` about every 110 ms, and never pause longer than 1.7 s.** The reply is the knob's only path. GLM's polling is likely what tells the adapter a host is present.
- **At connect, keep the app's own level. At the knob's first move, jump to the knob's position**, under the ceiling. After that, follow the knob, but not its jitter at rest. [adapter-status.md](adapter-status.md) has what GLM does.
- **TRAP: when the app quits, sleeps, or loses USB, the adapter takes over with its own level about 2.6 s later.** That level is the knob's position (`qlm-control-first`), and the ceiling does not hold it. If it differs from the app's, the volume jumps.

### The UI

- **Menu bar popover:** volume in dB, in 0.5 dB steps; mute; dim; the group picker; power. One status dot per monitor: online, standby, or offline.
- **Window:** each monitor's model, serial, firmware, temperature, power state, approximate input and output meters, and last reply.
- **Settings:** the setup files, the volume range and ceiling, whether to wake the monitors at launch, and launch at login with `SMAppService`.
- **The knob drives the app's volume.** Its position rides the adapter's reply to `01 08`.

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
- The knob, read from the adapter's reply to `01 08`.

**Done when** each action's frames match GLM's captured frames byte for byte, apart from session IDs. The knob must move the volume through System in the CLI. Quitting the CLI must hand the bus back to the adapter without an unplanned level jump.

#### The first control run

Done on 2026-10-30, as `qlm-control-first`. "What the control run showed" has the results. The script stays here for the next run.

It runs from main, with the Pi recording it as `qlm-control-first`. The user approves each step and listens. The levels are chosen so that every expected change is a few dB, and nothing can pass −35 dB while qlm is the host.

Before the first step:

- Build `qlmctl` from main.
- Play music quietly through the monitors.
- Set the knob to −40 dB.
- Leave one monitor playing. Switch the others off, or put them in standby from GLM.

The steps:

1. With GLM open, check that its volume shows the knob's −40 dB. Quit GLM, and listen: the level should not change.
2. `qlmctl info`. The knob reads about −40 dB.
3. `qlmctl volume -45 --ceiling -35 --dry-run`. Beyond discovery, it prints only volume frames, each carrying GLM's word for −45 dB (`volume-sweep`).
4. `qlmctl volume -45 --ceiling -35 --seconds 15`. The level drops 5 dB. After the exit, listen for 10 s, and note when the level changes. A 5 dB rise about 2.6 s after the exit means the adapter hands back at the knob's position.
5. `qlmctl volume -45 --ceiling -35 --seconds 30`. During the hold, turn the knob down 2 dB, then back to −40 dB. At the first turn, the volume jumps to the knob, and then it follows. Never turn the knob above −35 dB: the adapter applies it after the exit, with no ceiling.
6. `qlmctl dim on --volume -45 --ceiling -35 --seconds 10`, then `qlmctl dim off --volume -45 --ceiling -35 --seconds 5`. Dim drops the level 20 dB.
7. `qlmctl mute on --serial <the playing monitor's> --seconds 10`, then `qlmctl mute off --serial <the same> --seconds 5`. After the first exit, listen: does the mute outlast qlm?
8. `qlmctl sleep`, then `qlmctl wake --seconds 10`, last. Wake wakes every monitor, and each comes back on its stored settings, at the knob's level.
9. Stop the capture, and relaunch GLM. Its launch applies the group again.

Stop at once on anything unexpected: a level above what the step says, a click, or a monitor that changes state on its own. Turn the knob down, or switch the monitor off.

Afterwards, `captures/qlm-control-first/notes.md` records each step's time and what the user heard. A test checks each control frame qlm sent against GLM's: the volume words against `volume-sweep`, dim and mute against `mute-dim`, and the power steps against `standby-wake`. The hand-back is the knob's position, so quitting without a jump means the volume must equal the knob's when qlm stops. That decides how the CLI and the app hand the bus back.

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
| The adapter's level when the app leaves | It is the knob's position (`qlm-control-first`); the app matches it before it exits |
| GLM and the app both drive the bus | Detection and refusal |
| A firmware update changes the protocol | A version check, a warning, and GLM kept installed |
| GLM changes the `.sam` format | A strict reader that reports unknown keys |

## Sources

- [protocol.md](protocol.md): every protocol fact qlm knows, with its source
- [genlc](https://github.com/markbergsma/genlc): `transport.py`, `gnet.py`, `const.py`, and `sam.py`
- [hlm](https://github.com/robcazzaro/hlm): `docs/Genelec GLM Protocol.13.md`
- [espgensam](https://github.com/markbergsma/espgensam): `README.md`, `docs/glm-group-apply.md`, and `components/gensam/sam_import.py`
- [Genelec GLM in the living room](https://jb1c.blog/2021/02/02/genelec-glm-in-the-living-room/): the adapter over usbip
- [Genelec 9310A listing](https://www.soundseasy.com.au/products/genelec-9310a-wired-volume-controller): the knob on the adapter's 3.5 mm jack
- [Genelec support: the 9320A without GLM](https://support.genelec.com/hc/en-us/articles/19924050319250-Can-I-use-the-9320A-without-GLM): group switching needs GLM
