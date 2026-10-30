# qlm

A native Mac controller for Genelec SAM monitors, through the GLM network adapter. It shows the system's status. It sets volume, mute, dim, and power. It switches groups. GLM stays installed for calibration.

**Only `qlmctl info`, `discover`, and `poll` have run on real hardware.** They drive the adapter over USB. Everything else runs over a fake bus. The plan is [docs/plan.md](docs/plan.md).

## Building

You need Xcode and XcodeGen. `make setup` installs XcodeGen from the Brewfile.

```
make project   # fetch vibe-libs and generate qlm.xcodeproj
make build     # the menu bar app
make cli       # qlmctl
make test      # the unit tests
```

`vibe-libs/` is [vibe-libs](https://github.com/cmicali/vibe-libs), a git submodule. `make project` fetches it.

## qlmctl

`qlmctl` drives the system from the command line, and `qlmctl help` lists its commands. A command that drives the bus takes one of three: the GLM adapter over USB, by default; a fake bus, with `--fake`; or a capture, with `--replay FILE`.

Over USB, `qlmctl` refuses the adapter while GLM runs, while another process holds it, or when it cannot seize it. It then exits 69 and sends nothing.

### The controls over USB

`volume`, `mute`, `dim`, `sleep`, and `wake` drive the monitors over USB behind these gates:

- **A ceiling you state.** `volume` and `dim` need `--ceiling dB`. GLMProtocol caps every volume frame at it. It may be at most −30 dB. A higher one takes `--allow-high-ceiling`, and none may be above 0 dB. The volume may not be above the ceiling.
- **A level to dim from.** qlm cannot read the level, so `dim` needs `--volume dB`. Its frame is 20 dB under that level.
- **A dry run.** `--dry-run` discovers the monitors as `discover` does, then prints every frame the command would send, with the level each volume frame carries. It sends nothing more: the command runs on a fake bus that mirrors the monitors found.
- **Strict arguments.** An unknown, repeated, or empty argument is refused before any bus opens, so a mistyped `--dry-run` cannot send for real.
- **One monitor first.** `mute on --serial TEXT` mutes the one monitor whose serial contains TEXT. As GLM does, it also sends every other monitor found its mute state. Telemetry does not show mute, so qlm takes them as unmuted. `volume`, `dim`, `sleep`, and `wake` are broadcasts, and every monitor obeys them. To try one on a single monitor, open GLM, put every other monitor in standby, and quit GLM. Then only that monitor plays. `wake` wakes every monitor, so try it last.
- **The hand-back.** On exit, `qlmctl` stops sending, as `poll` does. About 2.6 s later, the adapter takes over with its own level, likely the knob's position. That level is not yet measured, so `qlmctl` warns of it. Turn the knob all the way down first. `--seconds N` keeps qlm the host for N seconds after the change, and the volume goes out again every cycle.

Monitors drop a host's leases a while after it stops: GLM's within 42 s, and qlm's within 23 s, in the first run. A run started sooner may find fewer monitors, or lease a session a monitor still holds. So wait that long after quitting GLM, and between runs.

A first run, at a low level:

```
qlmctl volume -50 --ceiling -40 --dry-run
qlmctl volume -50 --ceiling -40 --seconds 5
```

## Disclaimer

qlm is unofficial. It is not affiliated with or endorsed by Genelec. Genelec, GLM, and SAM are Genelec's trademarks. qlm drives your monitors with a reverse-engineered protocol. Use it at your own risk.

## License

Copyright 2026 Christopher Micali. qlm is licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).

The protocol was mapped by three GPL-3.0 projects, genlc, hlm, and espgensam. qlm ports no code from them. It is written from the protocol's facts and from its own captures.
