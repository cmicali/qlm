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

Not chosen yet. Until one is, nothing here is licensed for reuse.
