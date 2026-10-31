# qlm

A native Mac controller for Genelec SAM monitors, through the GLM network adapter. It shows the system's status, sets volume, mute, dim, and power, and switches groups. GLM stays installed for calibration.

`qlmctl` and the app have both driven real monitors. `qlmctl`'s `info`, `discover`, `poll`, `volume`, `dim`, `sleep`, and `wake` have run on all six monitors of one system, and `mute` on one monitor. The app drives the adapter behind a setting that's off by default, and it has run on all six too, driven by hand under a −35 dB ceiling. **A group apply has run only on the fake bus.** [docs/plan.md](docs/plan.md#where-things-stand) says what's built and what waits. [docs/protocol.md](docs/protocol.md) has every protocol fact qlm relies on, with its source.

## Building

You need Xcode and XcodeGen. `make setup` installs XcodeGen from the Brewfile.

```
make project   # fetch vibe-libs and generate qlm.xcodeproj
make build     # the menu bar app
make cli       # qlmctl
make test      # the unit tests
```

`vibe-libs/` is [vibe-libs](https://github.com/cmicali/vibe-libs), a git submodule. `make project` fetches it.

A Debug build of the app, `make build CONFIG=Debug`, answers a debug channel. A script drives the running app with `qlm.app/Contents/MacOS/qlm --debug-cmd <verb>`, and an unknown verb's reply lists them all. Each of qlm's verbs is one of the app's own controls, so the ceiling and the GLM check hold. A Release build has none of it, and `make check-release` checks that.

## Installing

`make install` builds the app and `qlmctl` in Release, signs them, and installs them.

```
make install     # qlm.app in /Applications, and qlmctl in ~/.local/bin
make uninstall   # quit qlm, then remove both
```

- **Signing.** It signs with your Apple Development certificate if the keychain has a valid one, and ad hoc if not. `SIGN_IDENTITY=-` forces ad hoc. With a certificate, macOS keeps what you allowed qlm across installs. Ad hoc, it can ask again after each install.
- **A running qlm.** If qlm runs from `/Applications`, `make install` asks it to quit and waits. It never kills it. If qlm asks before it quits, answer it.
- **qlmctl** goes in `~/.local/bin`, so it needs no sudo. Put that folder on your `PATH`, or set `BINDIR`. `DESTDIR` stages the whole install in another folder.
- **Before you uninstall**, turn off "Open qlm at login" in Settings, since macOS keeps a login item after its app is gone. `make uninstall` leaves qlm's settings.

qlm is a menu bar item, with no Dock icon. At its first launch, macOS asks whether qlm may read your Documents folder, where GLM keeps its setup files. It asks about notifications the first time qlm has one, such as a monitor dropping off. Nothing else asks: the adapter needs no Input Monitoring, and Gatekeeper doesn't stop a build made on this Mac. "Open qlm at login" may need your approval under Login Items in System Settings, and Settings then shows a button that opens it.

## The app

The menu bar app runs on a fake bus until you turn on "Drive the real monitors through the GLM adapter" in Settings. It caps every volume at the ceiling set there. When GLM holds the adapter, it offers to quit GLM. On the real monitors, it asks before a quit, or turning the setting off, that may make them louder: the knob above qlm's level, or no knob read. It refuses any group with a model whose filter design rate is unverified, and has no way around that. Today that's any group with an 8351B. The app says so, and sends nothing, so while every group in your setup has an 8351B, the app switches no group.

### Driving the real monitors

The app is new to the real adapter, so turn the setting on at a low level, one monitor first:

1. In Settings, set the ceiling to −40 dB or lower. The field saves when you leave it, and when Settings closes. It refuses a level above 0 dB, so type the minus sign. The default is −30 dB. No volume goes out above the ceiling.
2. Turn the knob all the way down. The ceiling doesn't reach the knob, and when qlm quits or the Mac sleeps, the adapter takes over at the knob's level.
3. In GLM, put every monitor but one in standby. Then quit GLM, since qlm drives nothing while GLM runs. Leave "Wake the monitors" off.
4. Turn the setting on.

## qlmctl

`qlmctl` drives the system from the command line, and `qlmctl help` lists its commands and options. A command that drives the bus takes one of three: the GLM adapter over USB, by default; a fake bus of two monitors, with `--fake`; or a capture's `reports.txt`, with `--replay FILE`. `setup` and `compare-apply` only read files.

Over USB, `qlmctl` refuses the adapter while GLM runs, while another process holds it, or when it can't seize it. It then exits 69 and sends nothing.

Every command that drives the bus checks every argument before the bus opens. An unknown, repeated, or empty one is refused with exit 64, so a mistyped `--dry-run` can't send for real.

`info` and `poll` print the knob and the calibration mic. With the mic in, they add its two readings, `DE` and `DD`, as raw counts, like `mic in, DE 2301456, DD 2298770`. We don't know yet what the readings measure, so qlm shows no dB. `poll` prints the mic's line each time the readings change, which with the mic in is once a cycle, about every 0.57 s. [docs/adapter-status.md](docs/adapter-status.md#the-mic-de-and-dd) has what we've seen of them.

### The controls over USB

`volume`, `dim`, and `wake --volume` set a level, so each needs `--ceiling dB`, and GLMProtocol caps every volume frame at it. The ceiling may be at most −30 dB, or 0 dB with `--allow-high-ceiling`, and the volume may not be above it. qlm can't read the monitors' level, so `dim` also needs `--volume dB`, the level it dims from. Every wake ends with a level, as GLM's does: the `--volume` given, else the knob's position under the ceiling, else the bottom level, `00 00 08`. A bare `wake` needs no `--ceiling`, and caps the knob's level at −30 dB.

`--dry-run` discovers the monitors as `discover` does, then prints every frame the command would send, with the level each volume frame carries. The command runs on a fake bus that mirrors the monitors found, so nothing more is sent.

No reply reports a monitor's mute, so qlm keeps its own record, and each round of mute state restates it to every monitor. `mute on --serial TEXT` mutes the one monitor whose serial contains TEXT, and sends such a round. `dim` and a turn of the knob send one too. A fresh `qlmctl` takes every monitor as unmuted, so a monitor muted in GLM would play again. `--muted TEXT[,TEXT...]` names the ones already muted, and the rounds keep them muted.

`volume`, `dim`, `sleep`, and `wake` are broadcasts. To try one on a single monitor, put the others in standby in GLM, then quit GLM. `wake` wakes them all, so try it last. `--seconds N` keeps `qlmctl` the host for N seconds after the change, and the volume goes out again every cycle.

A first run, at a low level:

```
qlmctl volume -50 --ceiling -40 --dry-run
qlmctl volume -50 --ceiling -40 --seconds 5
```

qlm polls the adapter as GLM does, with a pair of `01 08` every 0.107 s. `volume --adapter-poll SECONDS` sends one `01 08` every SECONDS instead, at most 10, and `0` polls only at start. The rest of the cycle stays as it is. It's for Part B of [docs/experiments.md](docs/experiments.md#part-b-the-adapters-host-timeout), which looks for the adapter's host timeout. With fewer polls, the adapter may take over during the run, at the knob's level. So the flag needs the knob in, at or below the volume, or `qlmctl` refuses and sends nothing more. `volume` prints how it polls the adapter as it starts.

### The hand-back

When `qlmctl` exits, it stops sending, and about 2.6 s later the adapter takes over at the knob's position. If the knob is at or below qlm's level, `qlmctl` sends the knob's level as it stops, so nothing changes. If the knob is higher, the level rises at the take-over, and `qlmctl` warns, naming both levels. With no knob in, or no volume set, it warns that the level is unknown. **The ceiling holds only while qlm runs, so turn the knob down before you exit.** [docs/protocol.md](docs/protocol.md#the-hand-back) has what the runs heard.

### Leases between runs

Monitors keep a host's leases for a while after it goes quiet. In the runs so far, monitors that were on dropped them within 23 to 42 s, and monitors in standby within 68 to 210 s. A monitor that holds a lease ignores the probe. **A run started too soon may find fewer monitors, or lease a session a monitor still holds, and then two monitors take one monitor's frames.** So after GLM quits or `qlmctl` exits, wait 1 minute with every monitor on, and 4 minutes with any in standby.

Within a run, qlm takes leases back. At each start, it asks each monitor it knew for its serial at its old session, and a match means the lease still holds. So the app needn't wait after a short sleep of the Mac. Each `qlmctl` command starts afresh, though, so the wait applies between commands. And only one lease chain runs at a time, so a cycle can't lease a monitor twice. [docs/protocol.md](docs/protocol.md#addresses-and-leases) has the detail.

### apply-group over USB

`apply-group FILE.sam GROUP` prints or sends GLM's switch to a group, or with `--launch`, the apply GLM sends at launch and wake. Its dry run reads only the setup file, and opens no bus.

Over USB, it's a supervised test, run at a low level with one monitor first. It needs `--volume`, the level the apply restores, and `--ceiling`. `--muted` and `--seconds` work as they do for the controls. A group with a model whose filter design rate is unverified also needs `--unverified-rate`, on any bus. Only 48 kHz for a two-way and 12 kHz for a subwoofer are confirmed, and the 8351B's design rate is 96 kHz. Without the flag, `qlmctl` refuses before it opens the bus.

Captures decide whether the 8351B's refusal lifts. We record GLM applying setups made with varied settings, and qlm's apply must match GLM's byte for byte. [docs/measurement.md](docs/measurement.md) is an optional check after that: GLM applies a group and REW measures it, then `qlmctl` applies the same group and REW measures again.

### compare-apply

`compare-apply FILE.sam reports.txt --group NAME` checks a capture of GLM's apply of one group against qlm's blocks from a setup file. It reads the two files and opens no bus. It refuses any option of the bus, so a wrong flag can't drive the monitors.

It takes each DSP pass in the capture, from `17 01` through the `40` frames after `3D`. A pass with no `3D` was cut short: GLM sent the session's next `17 01` first, as it does when it leases a monitor again mid-pass. It's compared with the start of the block, as far as GLM got, and prints `cut short by GLM`. `--from S` and `--to S` keep only the passes in that window of the capture's seconds. Each apply gets its own run, with its group and its window.

It matches each pass to the node of the group whose block is closest to it. Only that group's nodes count, since another group may hold a near copy of a node. In Main.sam, Group_4 is nearly Main 4x2, so a search across groups could match a changed node's pass to the old copy, and hide the change. Two more rules narrow the match:

- Only nodes of the model in the session's `39` reply count. The reply is the one in the window, else the nearest in the capture. Phase 0's captures lease monitors again at new sessions, so a window whose replies give one session two models is refused. A raw setup file also names each node's hardware ID, so then only the node the session's lease names counts. A redacted one doesn't.
- A node is one monitor. So a second session that matches a node already matched fails, unless the capture leases that session, as when a monitor wakes into the group.

| It prints | As |
| --- | --- |
| A setting whose frame differs | `GLM`, then `qlm` |
| A frame only GLM sent | `GLM only` |
| A frame only qlm would send | `qlm only` |
| The 8351B's `43 00 02` and `4B 00 00 00 01`, which qlm leaves out | `left out` |
| One of those two that GLM didn't send | `not sent` |
| A DSP frame no pass holds, under the session's pass before it, or at the top when the window holds none | `GLM, outside a pass` |

It also checks every generator stop, `05 04`, in the window, to a monitor with a pass or not. A left-out frame or a stop with other bytes counts as one only GLM sent.

A frame outside a pass is one GLM sent a session before its first pass, or after a pass closed. A subwoofer's `3B` before its pass is one. So is a band GLM sends as you edit it, and the level, delay, and `10 01 09` it sends when you confirm the editor. For a band, `10 0E`, the output names the slot, and says whether it's the slot as the block sends it. Each slot's last live edit should be the slot in the next snapshot. These frames change no verdict by default. With `--strict-outside`, every one but such a band differs.

It exits 0 when every pass matches and every stop is the known one, and 1 when not. A wrong argument, or no `--group`, exits 64. A file it can't read, a group the setup lacks, no pass to compare, or a session with two models exits 65.

```bash
qlmctl compare-apply Tests/Setups/Fixtures/Main.sam captures/startup-idle/reports.txt --group "Main 2x1"
```

## Disclaimer

qlm is unofficial. It is not affiliated with or endorsed by Genelec. Genelec, GLM, and SAM are Genelec's trademarks. qlm drives your monitors with a reverse-engineered protocol. Use it at your own risk.

## License

Copyright 2026 Christopher Micali. qlm is licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).

The protocol was mapped by three GPL-3.0 projects, genlc, hlm, and espgensam. qlm ports no code from them. It is written from the protocol's facts and from its own captures.
