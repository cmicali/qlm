# qlm: the plan

**Status, 2026-10-31.** Phases 0 and 1 are done. Phase 2's controls have run on all six monitors, with every frame matching GLM's, and the app has run on all six too. The group apply has run only on the fake bus. Next we capture GLM applying setups with varied settings, until qlm's apply matches GLM's byte for byte. Then comes the week of daily use.

## Where things stand

This section is a snapshot of main: what has run on the real adapter, what each layer holds, what we decided and learned on the way, and what comes next. [protocol.md](protocol.md) holds the protocol itself, with a source for every fact, so this section links to it rather than restate it.

Main passes 416 tests. Every protocol fact in them names its source: a capture in this repo, or a section of hlm's spec.

### What has run where

`qlmctl` and the app have both driven all six monitors now, each in a supervised run. What hasn't reached the monitors is the group apply, and every fix made since the app's run.

| What | Where it has run | Source |
| --- | --- | --- |
| `qlmctl info`, `discover`, and `poll` | The adapter, with all six monitors, on and in standby | `qlm-first-discover`, `qlm-standby-discover` |
| `qlmctl volume`, `dim`, `sleep`, and `wake` | All six monitors, with #27's fixes, under a −35 dB ceiling | `qlm-control-all`, #39 |
| `qlmctl mute` | One monitor, before #27's fixes | `qlm-control-first` |
| The app | All six monitors, once, driven by hand under a −35 dB ceiling. It ran volume, the knob, mute, mute all, dim, standby, and wake, across four launches. | `qlm-app-first`, #43 |
| The hand-back at a stop | All six, through the app, both ways. Both of `qlmctl`'s control runs were built before #32, so `qlmctl` hasn't run it. | `qlm-app-first` |
| The fixes since the app's run: System's, GLMAdapter's, and the app's | The fake bus | #49, #52, #53 |
| The debug channel | The fake bus | #50, #51 |
| The group apply | Its dry run, and the fake bus. `qlmctl apply-group` can send it over USB behind `--unverified-rate`, but it hasn't. | #32 |
| Phase 3's measurement | Not yet. It's an optional final check now. | [measurement.md](measurement.md) |

### The layers

Each layer has grown since the first control run. Here's what each holds now, with the PR behind each newer part.

- GLMProtocol frames, escapes, and checks every message, and refuses any opcode off its allowlist. Its builders clamp every volume frame to the ceiling and use GLM's own 200 volume words, and its control builders match GLM's frames byte for byte. It parses every reply qlm reads, the adapter's status among them, and packs and reassembles the USB reports. Telemetry now decodes the tags hlm's spec lacks, and the first half of a frame split across two polls no longer reads as a whole one (#35).
- GLMAdapter holds the adapter over IOKit HID, the report link under it, a fake bus, a capture reader, and a replay adapter. The HID adapter refuses the adapter while GLM runs or another process holds it, and opens it only seized. The report link now syncs at every open, not only after a timeout, so a reply GLM left late can't answer qlm's first request (#33). The clock that every timer runs on lives here too (#38). Since the safety review, the link caps a volume frame at the ceiling as it writes it, so a frame held behind its syncs can't pass a ceiling lowered meanwhile. A lost sync reply no longer stalls the link for good. It syncs up to three more times, and its errors say whether the adapter stopped answering or the link lost track. A report IOKit didn't take counts as not sent (#49).
- System owns the bus on one serial queue. It runs discovery, the leases, the poll cycle, volume, mute, dim, power, and the group apply, and it follows the knob from its first turn, under the ceiling. The golden tests compare its group apply with all eight captured applies. Apart from the frames qlm skips, three match exactly, and the rest differ only where GLM raced itself. Since the control run, System:
  - sends the volume to each monitor the moment its lease is acked, and ends every wake with a level (#27, #29);
  - keeps the mute record across a stop, and starts from a record it's given (#29);
  - sends the knob's level at a stop when that is no louder, and says what the stop did (#32, which carries #30 and #31);
  - applies a group with an 8351B only for `qlmctl`'s supervised test (#32);
  - gives the app what it lacked: a ceiling that changes while System runs, a stop with a completion, leases taken back by serial after a short gap, a typed reason the bus is unavailable, and one rule for presence (#32);
  - runs every timer on an injectable clock, so the tests run on a virtual one. That work found a monitor leased twice, and a wait in `qlmctl` that could miss an action already done. #38, which carries #37, fixes both.
  - follows the knob by GLM's own rule, slow drift and all. A move of more than a whole dB moves the level, and then every change does for about 2.5 s. A replay of seven captures matches GLM's level at every rest point but GLM's five lags (#42).
  - has the fixes from a safety review and a fuzz (#49). It caps every volume frame at the ceiling as it goes out. After a gap, it trusts none of its old sessions until each one's own serial answers. It also starts from the leases it's given, states a mute whose `2B` never went out, holds a lift of one mute under mute all, and drops a reply from before a stop.
  - holds its volume at or under the ceiling, so a turn of the knob above it sends nothing, and gives a snapshot of itself now, for a stop's warning (#52);
  - says when a wake went out with no group active, so the woken monitors play without their group's settings (#53).
  - numbers each call to a command, and stamps each snapshot with the last call that ran on its queue before it. So a wait in `qlmctl` takes only a snapshot from after its own action, whatever else publishes meanwhile (#60).
- Setups reads GLM 5 setup files strictly, designs the filters, and builds each monitor's DSP block, checked against every captured pass. It also watches the setup file, and calls back once a save settles (#28).
- `qlmctl` has `info`, `discover`, `poll`, and `setup`, and all of Phase 2's controls. The controls run behind gates: a ceiling the user states, at most −30 dB without `--allow-high-ceiling`, and a `--dry-run` that sends only discovery. Each also runs on the fake bus with `--fake`, or a capture with `--replay`. `dim` now sends GLM's whole sequence, `--muted` names the monitors already muted in GLM, and at exit `qlmctl` prints what the hand-back did (#27, #29, #32). `info` and `poll` print the calibration mic's two readings as raw counts. After a missed poll, the knob and mic lines say they are stale. `apply-group` prints GLM's whole apply. Over USB it's a supervised test, and it needs `--volume`, `--ceiling`, and, for a group with an 8351B, `--unverified-rate` (#32). `compare-apply` reads a setup file and a capture, opens no bus, and checks each of GLM's DSP passes against qlm's block, for the setup captures. A pass GLM cut short is checked against the block's start.
- The app has the menu bar popover, a monitors window, Settings, a banner for adapter errors, and a panel that plays the fake bus. A setting, off by default, drives the real adapter instead. The banner offers to quit GLM when GLM holds the adapter. The app stops System at sleep and starts it at wake, posts a notification when a monitor drops off or runs hot, and offers to read the setup again when GLM saves it (#28). A Debug build answers a debug channel, whose verbs are the app's own controls, so a script can run a supervised test on the monitors one step at a time (#50, #51). `make check-release` fails if a Release build holds any of it (#51). `make install` puts the app in `/Applications`, and `qlmctl` in `~/.local/bin`, for daily use (#46). Since its first run (#43):
  - It asks before any stop that may make the monitors louder: a quit, or turning the setting off. That's the knob above qlm's level, or no knob read. It decides from System's snapshot now (#52).
  - Each bus keeps its own level, mute record, and known leases across launches, so nothing set on the fake bus reaches the real monitors (#52).
  - The banner says when the adapter stops answering, or qlm loses track of it, and what the take-over does then (#52).
  - The default ceiling is −30 dB, qlmctl's highest without `--allow-high-ceiling`, and the field saves as it ends editing (#52).
  - After a wake with no group active, it says the monitors play without their group's settings until GLM applies the group. System's snapshot carries that. With a group active, System already sends GLM's apply at wake to each monitor leased again (#53).
  - It names each monitor as the setup file does, and forgets the fake bus's monitors when the setting changes (#53).

### The captures, the kits, and the docs

Besides the code, the repo holds the captures we learned from, the scripts that record and measure, and the docs that explain them.

`captures/` holds 25 captures: the 17 Phase 0 scenarios in [captures/README.md](../captures/README.md), qlm's own five runs, and three setup captures. Four ran `qlmctl`: `qlm-first-discover`, `qlm-standby-discover`, `qlm-control-first`, and `qlm-control-all`. The fifth, `qlm-app-first`, ran the app. The setup captures, `setup-a-baseline`, `setup-b-peq-8351b`, and `setup-j-restore`, are GLM applying copies of the setup, with redacted snapshots of each copy in `setups/`. Each has its `reports.txt` and `notes.md`, with the raw capture xz-compressed, and the golden tests read every report. `sleep-wake` never caught a true sleep.

The capture kit is `captures/README.md`, `tools/inventory.sh`, `tools/pcapng-to-reports.py`, and the Pi proxy in `tools/pi/`. The measurement kit is [measurement.md](measurement.md) and `tools/compare-measurements.py`, with a synthetic pair of exports in `tools/measurement-example/` (#34). For a run of the app on the monitors, `.claude/skills/app-hardware-run` drives the debug channel one step at a time (#51). The rest of `tools/` is small. `tools/redact-setup.py` makes the redacted setup fixture, and two scripts serve the Makefile: `tools/check-release.sh` for `make check-release` (#51), and `tools/quit-app.sh`, which asks a running qlm to quit before `make install` or `make uninstall` replaces it (#46).

| Doc | What it covers |
| --- | --- |
| [protocol.md](protocol.md) | Every protocol fact qlm knows, with its source. AGENTS.md asks each PR that teaches us a new fact to add it there (#36). |
| [adapter-status.md](adapter-status.md) | The adapter's reply to `01 08`, and how the knob reaches the host |
| [refused-frames.md](refused-frames.md) | Each frame GLM sends that qlm doesn't, and GLM's group apply frame by frame |
| [telemetry.md](telemetry.md) | Each telemetry tag, and what the meters can show (#35) |
| [measurement.md](measurement.md) | Phase 3's measurement, step by step (#34) |
| [experiments.md](experiments.md) | The script for a session that settles the open questions a person at the desk can (#47) |
| [setup-captures.md](setup-captures.md) | The script for capturing GLM's applies of setups made with known changes, to decode the rest of the group apply |

### Decided since Phase 1

We made these calls after the captures and the runs on the monitors. Each is built now.

- qlm matches GLM byte for byte. So the allowlist takes exactly `2D 00`, as a broadcast right before `FF 3D 00 00`, and dim sends it.
- qlm refuses the adapter only for GLM, or for a process that holds it the way GLM does. A process that only enumerates it does not count. Spotify puts a USB device client on every USB device, the adapter among them, and that made qlm refuse in `qlm-standby-discover`. GLM's client is an HID library client that has opened the HID device.
- The hand-back. When qlm stops, it compares the knob's position with its own volume. If the knob is at or below it, qlm sends the knob's level just before it lets go, so the adapter's take-over changes nothing. If the knob is above it, the take-over would make the level louder, so qlm warns instead.
- The 8351B in a supervised test. `qlmctl apply-group` may apply a group with an 8351B over USB only behind an explicit flag, at a low level, one monitor first. The app still refuses. Lifting that is the owner's call, once qlm's apply matches GLM's byte for byte across captures of setups with varied settings. A measurement after the apply is an optional final check, not the gate.
- qlm keeps the mute record. No reply reports a monitor's mute, so qlm's record is the truth, and its rounds stay GLM's. The record survives a stop, and System can start from one, so the app can keep it across launches.
- Every wake ends with a level. A woken monitor keeps its own level until a host sends one. So the wake sends the volume, else the knob's position under the ceiling, else the bottom level, `00 00 08`.
- After a gap, qlm trusts none of its old sessions. Another host may have leased them in its own order, so qlm checks each one's serial before it sends anything there (#49).
- System holds its volume at the ceiling, not only its frames. So at the ceiling, a turn of the knob that changes nothing sends nothing (#52).
- The 8351B's refusal stands at a wake. The app applies no group with an unverified rate, so after a wake it says the monitors play without their group's settings (#53).

### Next

What's left, in the order we'll do it. Most of it needs the monitors and the user at the desk, at a low level, one monitor first.

1. The rest of the group apply, decoded from GLM's captures. The owner makes setups in GLM with known, varied settings: PEQ bands of each type, frequency, gain, and Q on each model; crossover points; levels and delays; and the 8351B's own fields, `GroupDelayCompensation` and the bass extension crossover, `BassExtensionXO(Hz)`. We capture GLM applying each setup through the Pi proxy. qlm's design from each setup must then match GLM's frames byte for byte, which decodes `43 00 02` and `4B 00 00 00 01`. [setup-captures.md](setup-captures.md) is the script. The captures also show whether GLM's generator stop, `05 04 …`, ever changes, and the owner decides about `05` after them.
   - Done, on 2026-10-31: Parts A, B, and J. The 8351B's peaking bands and shelves match GLM's to the bit across their range, once qlm takes a shelf's w0 as a float. One shelf decides that, and it can't yet tell a w0 rounded from double from one computed in float. The generator stop held in 69 more stops. [What the first session settled](setup-captures.md#what-the-first-session-settled) has the rest.
   - Open: Parts C to I. Part G, the 8351B's own fields, needs the file-edit route or a recalibration, since GLM 5.2.1 shows no control for either field outside the group definition.
2. Lifting the 8351B's refusal. Once qlm's apply matches GLM's byte for byte across those captures, that's the owner's call. Then the app can apply the active group at a wake, as GLM does, and switch groups. Today a wake leaves the monitors on their stored settings, until GLM applies the group (#53). The REW measurement in [measurement.md](measurement.md) becomes an optional final check, not the gate.
3. The week of daily use without GLM, Phase 4's Done when. `make install` installs the app (#46). The fixes from its first run (#52, #53), and System's (#49), have run only on the fake bus, so the week is their first test on the monitors. The debug channel can check them one step at a time first, following `.claude/skills/app-hardware-run`.
4. The experiments session. [experiments.md](experiments.md) is the script, and it settles the [open questions in protocol.md](protocol.md#open-questions) that a person at the desk can, such as what level the adapter applies with no knob in. Its Part A also hears `qlmctl`'s own hand-back, which neither control run had. Part B needs `qlmctl volume --adapter-poll`, which isn't built yet.
5. The analog routing frame, still marked unverified in code. No group in the user's setup uses input 4, so no capture shows it. Part G of the experiments captures GLM switching to a copy of the setup with an analog group.
6. A bump of usb-proxy's pin in `tools/pi/setup.sh`, dropping `tools/pi/usb-proxy.patch`, once upstream [AristoChen/usb-proxy#37](https://github.com/AristoChen/usb-proxy/pull/37) merges. That PR carries the patch's three fixes, and it's still open.

### What the captures and runs showed

The captures and qlm's five runs taught us how the protocol behaves, and [protocol.md](protocol.md) has each fact with its source. Each run's `notes.md` has its timeline. These are the findings that shaped the plan:

- The adapter is a thin bridge. It passes each request to the bus and returns one reply, and while a host is connected, the host runs the bus ([The big picture](protocol.md#the-big-picture)).
- A monitor that holds a lease ignores the probe, and monitors drop a quiet host's leases on their own. The bounds we've timed run from 3.1 s, with the next host already polling the adapter, to 210 s in standby. Between two of `qlmctl`'s runs, every monitor answered the probe within 9.7 s. So a new host waits, or takes the leases back ([When a monitor loses its lease](protocol.md#when-a-monitor-loses-its-lease)).
- About 2.6 s after the host goes quiet, the adapter takes over at the knob's position. qlm's ceiling doesn't reach it, and once we heard the take-over pass the ceiling ([The hand-back](protocol.md#the-hand-back)).
- A monitor just switched on plays at its own stored level until a host sends one. So qlm sends its level within 2 ms of each lease's ack. On all six, it reached every monitor switched on or woken. The monitor still plays without its group's settings until a group applies. A mute outlasts the host, and no reply reports it ([What the adapter and the monitors do on their own](protocol.md#what-the-adapter-and-the-monitors-do-on-their-own)).
- Every frame qlm has sent on the adapter is one GLM sends. `QLMControlRunTests`, `QLMControlAllTests`, and `QLMAppFirstTests` check each run's. [refused-frames.md](refused-frames.md) covers the frames GLM sends that qlm doesn't.
- Phase 0's three questions are answered. GLM sends nothing when it quits, so the adapter senses a host by its traffic. Knob turns reach the host in the adapter's reply to `01 08`. When the host leaves, the adapter applies the knob's position.
- A 5 dB step is too small to hear in a quick test, so the control run tested the hand-back and the knob at −60 dB (`qlm-control-first`).

The user's system, from their setup file: two 8351B, two 8330A, a 7370A, and a 7350A. The file designs the 8351B bands at 96 kHz, the 8330A at 48 kHz, and the subwoofers at 12 kHz. On the wire, every 8351B band GLM sends matches qlm's 96 kHz design to the bit (`QLMDSPBlockGoldenTests`). `setup-b-peq-8351b` varied the Left 8351B's bands and shelves across their range, and they match too. But qlm leaves out two of the 8351B's frames, `43 00 02` and `4B 00 00 00 01`. So the app refuses every group with an 8351B, which is every group in the setup, and only `qlmctl`'s supervised test may apply one.

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
- **Shelves:** RBJ formulas in Q form, with Q 0.3 for low shelves and 0.5 for high shelves. A three-way's high shelf is Q 0.3 (#10). A shelf's w0 is a float: one captured shelf decides it, and qlm rounds it from double (`setup-b-peq-8351b`; [protocol.md](protocol.md#10-0e-a-peq-band)). The wire carries `b0 b1 b2 −a1 −a2`, normalized by `a0`, as little-endian floats. A band at exactly 0 dB goes out as `1, 0, 0, 0, 0`.
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
├── captures/       the captures, one directory per scenario or run
├── tools/          the capture, redaction, measurement, and build scripts, and the Pi proxy
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

**The app takes two pieces: dev/DebugChannel and dev/DebugVerbs.** They bring core/Common and core/Graphics with them. `project.yml` includes `vibe-libs/vibe-libs.yml`, sets `VIBE_LIBS_ROOT`, and lists them under the app's `templates:`. Each compiles to nothing in Release, and `make check-release` checks that. The tests take them too, to run the app's debug verbs on the fake bus. The CLI takes none. The rest of the table waits for its own work.

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

Two of the three are met in `qlmctl`, and the third has been heard through the app:

| Done when | Where it stands |
| --- | --- |
| Each action's frames match GLM's | Met. `QLMControlRunTests` checks each control frame qlm sent in `qlm-control-first` against GLM's. That run's dim sent only the dimmed level, so #27 made `qlmctl dim` send GLM's whole sequence. `QLMControlAllTests` checks it on all six, in `qlm-control-all`. |
| The knob moves the volume through System | Met in `qlm-control-first`. qlm jumped to the knob at its first turn, then followed it, and never sent more than −41.5 dB under a −35 dB ceiling. |
| Quitting hands the bus back without a jump | Heard through the app, in `qlm-app-first`. With the knob below the app's level, the app's last report was the knob's level, and nothing changed after. With the knob above it, the app warned first. `qlmctl` stops through the same System, but both its control runs were built before #32 added the hand-back. |

What's left is to hear `qlmctl`'s own hand-back. Part A of [experiments.md](experiments.md) runs it.

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

The 8351B's refusal no longer waits on the measurement. qlm leaves out the 8351B's `43 00 02` and `4B 00 00 00 01`, and captures of GLM applying setups with varied settings should decode them ([Next](#next)). Once qlm's apply matches GLM's byte for byte across those captures, lifting the refusal is the owner's call. The measurement becomes an optional final check. Only monitors just switched on can show whether the frames qlm leaves out matter, so its last step is [an apply from a cold start](measurement.md#step-5-qlm-from-a-cold-start).

### Phase 4: the Mac app

- The menu bar item and the window over System's snapshots.
- Settings, and detection of a running GLM.
- Sleep, wake, and hot plug.
- A notification when a monitor drops off or runs hot.

**Done when** a week of daily use without GLM brings no crash, and every dropped monitor recovers on its own. Volume must reach the bus within 50 ms of the slider. A group switch must finish within 2 s.

Each item is built, and the app has run once on the real adapter, on all six monitors (`qlm-app-first`, #43):

| Item | Where it stands |
| --- | --- |
| The menu bar item and the window | Built: the popover, the monitors window, and a panel that plays the fake bus |
| Settings, and detection of a running GLM | Built. A setting, off by default, drives the real adapter, and Settings explains the hand-back. When GLM holds the adapter, the banner offers to quit it (#28). Turning the setting off asks first when the take-over may be louder (#52). |
| Sleep, wake, and hot plug | Built. System stops at sleep and starts again at wake, and the HID adapter follows hot plug (#28). |
| Notifications | Built: when a monitor drops off, or reaches 70 °C, at most one of each kind every 10 minutes per monitor (#28) |

The app also watches the setup file, and offers to read it again when GLM saves it. Its first run on the real adapter found the bugs #52 and #53 fix. Nothing in the Done when has been tried yet.

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
