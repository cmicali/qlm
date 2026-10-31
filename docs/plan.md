# qlm: the plan

**Status, 2026-10-30.** Phases 0 and 1 are done, and Phase 2's controls have run on one monitor, with every frame matching GLM's. Since then we've built the control run's safety fixes, the hand-back, the supervised 8351B apply, and the app's mode for the real adapter, but so far they've run only on the fake bus. Next we check them on the monitors: the fixes on all six, then the hand-back, then Phase 3's measurement.

## Where things stand

This section is a snapshot of main: what has run on the real adapter, what each layer holds, what we decided and learned on the way, and what comes next. [protocol.md](protocol.md) holds the protocol itself, with a source for every fact, so this section links to it rather than restate it.

Main passes 282 tests. Every protocol fact in them names its source: a capture in this repo, or a section of hlm's spec.

### What has run where

Most of qlm has run only on the fake bus. Only `qlmctl` has driven the real adapter, and its controls have reached one monitor.

| What | Where it has run |
| --- | --- |
| `qlmctl info`, `discover`, and `poll` | The adapter, with all six monitors, on and in standby (`qlm-first-discover`, `qlm-standby-discover`) |
| `qlmctl volume`, `mute`, `dim`, `sleep`, and `wake` | One monitor, before #27's fixes (`qlm-control-first`). A run on all six is under way (#39, open). |
| The hand-back at a stop | The fake bus |
| `qlmctl apply-group` | Its dry run, and the fake bus. It can go over USB now, behind `--unverified-rate`, but it hasn't. |
| The app | The fake bus. It has never run on the real adapter. |

### The layers

Each layer has grown since the first control run. Here's what each holds now, with the PR behind each newer part.

- GLMProtocol frames, escapes, and checks every message, and refuses any opcode off its allowlist. Its builders clamp every volume frame to the ceiling and use GLM's own 200 volume words, and its control builders match GLM's frames byte for byte. It parses every reply qlm reads, the adapter's status among them, and packs and reassembles the USB reports. Telemetry now decodes the tags hlm's spec lacks, and the first half of a frame split across two polls no longer reads as a whole one (#35).
- GLMAdapter holds the adapter over IOKit HID, the report link under it, a fake bus, a capture reader, and a replay adapter. The HID adapter refuses the adapter while GLM runs or another process holds it, and opens it only seized. The report link now syncs at every open, not only after a timeout, so a reply GLM left late can't answer qlm's first request (#33). The clock that every timer runs on lives here too (#38).
- System owns the bus on one serial queue. It runs discovery, the leases, the poll cycle, volume, mute, dim, power, and the group apply, and it follows the knob from its first turn, under the ceiling. The golden tests compare its group apply with all eight captured applies. Apart from the frames qlm skips, three match exactly, and the rest differ only where GLM raced itself. Since the control run, System:
  - sends the volume to each monitor the moment its lease is acked, and ends every wake with a level (#27, #29);
  - keeps the mute record across a stop, and starts from a record it's given (#29);
  - sends the knob's level at a stop when that is no louder, and says what the stop did (#32, which carries #30 and #31);
  - applies a group with an 8351B only for `qlmctl`'s supervised test (#32);
  - gives the app what it lacked: a ceiling that changes while System runs, a stop with a completion, leases taken back by serial after a short gap, a typed reason the bus is unavailable, and one rule for presence (#32);
  - runs every timer on an injectable clock, so the tests run on a virtual one. That work found a monitor leased twice, and a wait in `qlmctl` that could miss an action already done. #38, which carries #37, fixes both.
- Setups reads GLM 5 setup files strictly, designs the filters, and builds each monitor's DSP block, checked against every captured pass. It also watches the setup file, and calls back once a save settles (#28).
- `qlmctl` has `info`, `discover`, `poll`, and `setup`, and all of Phase 2's controls. The controls run behind gates: a ceiling the user states, at most −30 dB without `--allow-high-ceiling`, and a `--dry-run` that sends only discovery. Each also runs on the fake bus with `--fake`, or a capture with `--replay`. `dim` now sends GLM's whole sequence, `--muted` names the monitors already muted in GLM, and at exit `qlmctl` prints what the hand-back did (#27, #29, #32). `apply-group` prints GLM's whole apply. Over USB it's a supervised test, and it needs `--volume`, `--ceiling`, and, for a group with an 8351B, `--unverified-rate` (#32).
- The app has the menu bar popover, a monitors window, Settings, a banner for adapter errors, and a panel that plays the fake bus. A setting, off by default, drives the real adapter instead. The banner offers to quit GLM when GLM holds the adapter. The app stops System at sleep and starts it at wake, posts a notification when a monitor drops off or runs hot, and offers to read the setup again when GLM saves it (#28). It doesn't use System's new calls from #32 yet.

### The captures, the kits, and the docs

Besides the code, the repo holds the captures we learned from, the scripts that record and measure, and the docs that explain them.

`captures/` holds 20 captures: the 17 Phase 0 scenarios in [captures/README.md](../captures/README.md), and qlm's own three runs, `qlm-first-discover`, `qlm-standby-discover`, and `qlm-control-first`. Each has its `reports.txt` and `notes.md`, with the raw capture xz-compressed, and the golden tests read every report. `sleep-wake` never caught a true sleep. A fourth run of qlm's, `qlm-control-all`, is under way (#39, open).

The capture kit is `captures/README.md`, `tools/inventory.sh`, `tools/pcapng-to-reports.py`, and the Pi proxy in `tools/pi/`. The measurement kit is [measurement.md](measurement.md) and `tools/compare-measurements.py`, with a synthetic pair of exports in `tools/measurement-example/` (#34).

| Doc | What it covers |
| --- | --- |
| [protocol.md](protocol.md) | Every protocol fact qlm knows, with its source. AGENTS.md asks each PR that teaches us a new fact to add it there (#36). |
| [adapter-status.md](adapter-status.md) | The adapter's reply to `01 08`, and how the knob reaches the host |
| [refused-frames.md](refused-frames.md) | Each frame GLM sends that qlm doesn't, and GLM's group apply frame by frame |
| [telemetry.md](telemetry.md) | Each telemetry tag, and what the meters can show (#35) |
| [measurement.md](measurement.md) | Phase 3's measurement, step by step (#34) |

### Decided since Phase 1

We made these calls after the captures and the first control run. Each is built now.

- qlm matches GLM byte for byte. So the allowlist takes exactly `2D 00`, as a broadcast right before `FF 3D 00 00`, and dim sends it.
- qlm refuses the adapter only for GLM, or for a process that holds it the way GLM does. A process that only enumerates it does not count. Spotify puts a USB device client on every USB device, the adapter among them, and that made qlm refuse in `qlm-standby-discover`. GLM's client is an HID library client that has opened the HID device.
- The hand-back. When qlm stops, it compares the knob's position with its own volume. If the knob is at or below it, qlm sends the knob's level just before it lets go, so the adapter's take-over changes nothing. If the knob is above it, the take-over would make the level louder, so qlm warns instead.
- The 8351B in a supervised test. `qlmctl apply-group` may apply a group with an 8351B over USB only behind an explicit flag, at a low level, one monitor first. The app still refuses. A measurement after that apply decides whether the refusal lifts.
- qlm keeps the mute record. No reply reports a monitor's mute, so qlm's record is the truth, and its rounds stay GLM's. The record survives a stop, and System can start from one, so the app can keep it across launches.
- Every wake ends with a level. A woken monitor keeps its own level until a host sends one. So the wake sends the volume, else the knob's position under the ceiling, else the bottom level, `00 00 08`.

### Next

What's left, in the order we'll do it. Most of it needs the monitors and the user at the desk, at a low level, one monitor first.

1. The all-monitor check of #27's fixes, recorded as `qlm-control-all`. It's under way (#39, open). It checks that the volume reaches each new and woken monitor at once, that the wake ends with the level, and that `qlmctl dim` sends GLM's whole sequence.
2. The hand-back on hardware. A stop with the knob at or below qlm's level should change nothing we can hear. With the knob above it, `qlmctl` should warn before the level rises.
3. Phase 3's supervised apply and measurement, following [measurement.md](measurement.md). The result decides whether the 8351B's refusal lifts.
4. The app adopts System's calls from #32, which is under way: the live ceiling in place of a new System, the stop's completion before a sleep, the typed bus reason, and System's rule for presence. Then the app's first run on the real adapter, at a low level, one monitor first.
5. The knob's slow drift, in System, also under way. In `sleep-wake-darkwake`, GLM follows a 7 dB drift that qlm ignores until the knob's first turn.
6. The analog routing frame, still marked unverified in code. No group in the user's setup uses input 4, so no capture shows it.
7. The [open questions in protocol.md](protocol.md#open-questions), such as whether the adapter escapes an address byte, and what level it applies with no knob in. [experiments.md](experiments.md) is the script for a session that settles the ones a person at the desk can.
8. A bump of usb-proxy's pin in `tools/pi/setup.sh`, dropping `tools/pi/usb-proxy.patch`, once upstream [AristoChen/usb-proxy#37](https://github.com/AristoChen/usb-proxy/pull/37) merges. That PR carries the patch's three fixes, and it's still open.

### What the captures and runs showed

The captures and qlm's three runs taught us how the protocol behaves, and [protocol.md](protocol.md) has each fact with its source. Each run's `notes.md` has its timeline. These are the findings that shaped the plan:

- The adapter is a thin bridge. It passes each request to the bus and returns one reply, and while a host is connected, the host runs the bus ([The big picture](protocol.md#the-big-picture)).
- A monitor that holds a lease ignores the probe, and monitors drop a quiet host's leases within 23 to 210 s. So a new host waits, or takes the leases back ([When a monitor loses its lease](protocol.md#when-a-monitor-loses-its-lease)).
- About 2.6 s after the host goes quiet, the adapter takes over at the knob's position, and qlm's ceiling doesn't reach it ([The hand-back](protocol.md#the-hand-back)).
- A monitor just switched on plays at its own stored level until a host sends one. A mute outlasts the host, and no reply reports it ([What the adapter and the monitors do on their own](protocol.md#what-the-adapter-and-the-monitors-do-on-their-own)).
- Every frame qlm has sent on the adapter is one GLM sends (`QLMControlRunTests`). [refused-frames.md](refused-frames.md) covers the frames GLM sends that qlm doesn't.
- Phase 0's three questions are answered. GLM sends nothing when it quits, so the adapter senses a host by its traffic. Knob turns reach the host in the adapter's reply to `01 08`. When the host leaves, the adapter applies the knob's position.
- A 5 dB step is too small to hear in a quick test, so the control run tested the hand-back and the knob at −60 dB (`qlm-control-first`).

The user's system, from their setup file: two 8351B, two 8330A, a 7370A, and a 7350A. The file designs the 8351B bands at 96 kHz, the 8330A at 48 kHz, and the subwoofers at 12 kHz. On the wire, every 8351B band GLM sends matches qlm's 96 kHz design to the bit (`QLMDSPBlockGoldenTests`). No measurement confirms the rate yet. So the app refuses every group with an 8351B, which is every group in the setup, and only `qlmctl`'s supervised test may apply one.

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
- **Groups for unverified models are refused.** Status, volume, mute, and power still work on them. AGENTS.md's Safety rule makes one exception: `qlmctl`'s supervised test, behind `--unverified-rate`.

## Open, for you to decide

1. **The knob.** Decided: no 9310. The adapter has its own optional volume knob. While it is attached, GLM locks its on-screen volume. Its position rides the adapter's reply to `01 08` ([protocol.md](protocol.md#volume-and-the-knob)).
2. **Capture machine.** Decided: a Raspberry Pi 5 inline between the Mac and the adapter. [captures/README.md](../captures/README.md) has the steps.

## Architecture

Four layers. Each meets the next through values and blocks.

1. **GLMProtocol (C, pure).** Framing, escaping, CRC, report packing and reassembly, command builders, and reply parsers: ack, hardware ID, telemetry TLVs, and ASCII strings. No I/O. Golden tests: every captured frame decodes and re-encodes byte for byte.
2. **GLMAdapter.** An IOKit matching notification finds the adapter, and handles hot plug. `IOHIDDeviceSetDispatchQueue` delivers input reports to System's queue. A report link keeps one request in flight, with a timeout. Replies name no request, so after a timeout, and at every open, it syncs with a query whose reply has a shape the late one cannot, and drops replies until that one comes. One link serves each arrival of the adapter, across reopens, and one that loses track waits for a replug. The adapter is refused while GLM runs or another process holds it, and opened only seized, so a failed seize is a refusal too. Two stand-ins share its interface: a replay adapter that plays a capture, and a fake bus that simulates monitors, lease loss, and dropped replies.
3. **System.** One serial queue owns the bus. It runs the lease registry (hardware ID to session ID) and the cycle GLM runs: `FE`, the volume, and a `08` round, about every 0.57 s. Between rounds, it polls the adapter with `01 08` about every 110 ms, for the knob. It coalesces volume to at most one frame per 50 ms. It tracks mute in software. It runs a group apply as one transaction. It publishes an immutable snapshot of the monitors after each change.
4. **Setups.** It reads `.sam` files into groups. It designs the biquads at each device's rate and checks that each filter is stable. It builds each monitor's DSP block as values. It reports every field it cannot carry, never dropping one silently. It watches the file and offers a re-import when GLM saves.

The app reads snapshots on the main queue. Nothing in the UI touches GLMAdapter.

### The repository

```
qlm/
├── AGENTS.md  README.md  Makefile  Brewfile  project.yml
├── docs/           the plan, protocol.md, and the docs it links
├── qlm/            all the code, one directory per layer
│   ├── GLMProtocol/  C, no Apple dependency
│   ├── GLMAdapter/   the adapter protocol, HID, the fake bus, and the replay
│   ├── Setups/       the setup file reader, the filter design, and the DSP block
│   ├── System/       the engine and its snapshots
│   ├── App/          the menu bar app: AppKit, Objective-C
│   └── CLI/          qlmctl
├── Tests/          one XCTest bundle, hostless; mirrors qlm/
├── captures/       the captures, one directory per scenario
├── tools/          the capture, redaction, and measurement scripts, and the Pi proxy
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
| dev/DebugChannel | drive a running debug build from a script, for tests against the real monitors. Taken. |
| dev/DebugVerbs | the standard debug verbs: the build, the view tree, the screenshot, process health, and synthetic input. Taken. |
| audio/OutputDevices | later: switch groups when macOS changes output device, for example analog to AES |

Nothing else applies: no decoding, playback, tags, or waveforms.

**The app takes two pieces: dev/DebugChannel and dev/DebugVerbs.** They bring core/Common and core/Graphics with them. `project.yml` includes `vibe-libs/vibe-libs.yml`, sets `VIBE_LIBS_ROOT`, and lists them under the app's `templates:`. Each compiles to nothing in Release. The CLI and the tests take none. The rest of the table waits for its own work.

**The protocol stays in this app.** No other app needs it, so by vibe-libs's own rule it is not a candidate.

vibe-libs's `AGENTS.md` counts this app among its users.

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

Two of the three are met, and the third is built but not yet heard:

| Done when | Where it stands |
| --- | --- |
| Each action's frames match GLM's | Met. `QLMControlRunTests` checks each control frame qlm sent in `qlm-control-first` against GLM's. The run's dim sent only the dimmed level, so #27 made `qlmctl dim` send GLM's whole sequence, and a fake-bus test checks it frame by frame. |
| The knob moves the volume through System | Met in `qlm-control-first`. qlm jumped to the knob at its first turn, then followed it, and never sent more than −41.5 dB under a −35 dB ceiling. |
| Quitting hands the bus back without a jump | Built, on the fake bus. At a stop, System sends the knob's level when that is no louder than its own, and `qlmctl` says what the stop did. With the knob above qlm's level, it warns instead (#32). |

What's left is to hear the hand-back on the monitors. The all-monitor run, under way as `qlm-control-all` (#39, open), checks #27's fixes on hardware first.

#### The first control run

Done on 2026-10-30, as `qlm-control-first`. Its results are in [What the captures and runs showed](#what-the-captures-and-runs-showed) and the capture's `notes.md`. The script stays here for the next run.

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

Everything Phase 3 needs is built, and none of it has reached the monitors:

| Done when | Where it stands |
| --- | --- |
| The dry run matches GLM's for every group | Met. `QLMApplyGoldenTests` compares System's apply with all eight captured applies, and `QLMDSPBlockGoldenTests` checks every block against GLM's captured passes. Apart from the frames qlm skips, three applies match exactly, and the rest differ only where GLM raced itself. |
| The app applies each group, at a low level, one monitor first | Not yet. Every group in the user's setup has an 8351B, so the app refuses them all. `qlmctl apply-group --unverified-rate` can apply one over USB as a supervised test (#32). |
| A measurement after qlm's apply matches one after GLM's within 0.2 dB | Not yet. [measurement.md](measurement.md) is the procedure, and `tools/compare-measurements.py` compares REW's exports (#34). |

The measurement also decides whether the 8351B's refusal lifts. qlm leaves out the 8351B's `43 00 02` and `4B 00 00 00 01`, and only monitors just switched on can show whether that matters. So measurement.md's last step is [an apply from a cold start](measurement.md#step-5-qlm-from-a-cold-start).

### Phase 4: the Mac app

- The menu bar item and the window over System's snapshots.
- Settings, and detection of a running GLM.
- Sleep, wake, and hot plug.
- A notification when a monitor drops off or runs hot.

**Done when** a week of daily use without GLM brings no crash, and every dropped monitor recovers on its own. Volume must reach the bus within 50 ms of the slider. A group switch must finish within 2 s.

Each item is built, but the app has run only on the fake bus:

| Item | Where it stands |
| --- | --- |
| The menu bar item and the window | Built: the popover, the monitors window, and a panel that plays the fake bus |
| Settings, and detection of a running GLM | Built. A setting, off by default, drives the real adapter, and Settings explains the hand-back. When GLM holds the adapter, the banner offers to quit it (#28). |
| Sleep, wake, and hot plug | Built. System stops at sleep and starts again at wake, and the HID adapter follows hot plug (#28). |
| Notifications | Built: when a monitor drops off, or reaches 70 °C, at most one of each kind every 10 minutes per monitor (#28) |

The app also watches the setup file, and offers to read it again when GLM saves it. Before the week of daily use, it adopts System's calls from #32, which is under way. Then it runs on the real adapter for the first time, at a low level, one monitor first. Nothing in the Done when has been tried yet.

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
| The adapter's level when the app leaves | It is the knob's position (`qlm-control-first`); a stop sends the knob's level when that is no louder, and warns otherwise (#32) |
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
