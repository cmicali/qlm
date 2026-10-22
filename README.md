# qlm

A native Mac controller for Genelec SAM monitors, through the GLM network adapter. It shows the system's status. It sets volume, mute, dim, and power. It switches groups. GLM stays installed for calibration.

**Nothing works yet.** The plan is [docs/plan.md](docs/plan.md).

## Building

You need Xcode and XcodeGen. `make setup` installs XcodeGen from the Brewfile.

```
make project   # fetch vibe-libs and generate qlm.xcodeproj
make build     # the menu bar app
make cli       # qlmctl
make test      # the unit tests
```

`vibe-libs/` is [vibe-libs](https://github.com/cmicali/vibe-libs), a git submodule. `make project` fetches it.

## Disclaimer

qlm is unofficial. It is not affiliated with or endorsed by Genelec. Genelec, GLM, and SAM are Genelec's trademarks. qlm drives your monitors with a reverse-engineered protocol. Use it at your own risk.

## License

Copyright 2026 Christopher Micali. qlm is licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).

The protocol was mapped by three GPL-3.0 projects, genlc, hlm, and espgensam. qlm ports no code from them. It is written from the protocol's facts and from its own captures.
