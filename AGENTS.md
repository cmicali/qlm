# AGENTS.md

Guidance for any coding agent working in this repository.

qlm is a native Mac controller for Genelec SAM monitors. It talks to them through the GLM network adapter. It replaces GLM for status, volume, mute, dim, power, and group switching. It never calibrates. **Only `qlmctl` has run on real hardware**, and its controls only on one monitor; the app and the group apply run over a fake bus. The plan is [docs/plan.md](docs/plan.md), and its "Where things stand" section says what is built and what waits. Read it before changing anything here.

## Building

- `make setup` installs XcodeGen. `make project` fetches `vibe-libs/` and generates `qlm.xcodeproj`.
- `make build` builds the app, `make cli` builds `qlmctl`, and `make test` runs the unit tests. `make check-release` fails if the Release app holds any of the debug channel.
- **The Xcode project is generated.** Change `project.yml`, never the project. The app's `Info.plist` is generated too.
- **Warnings are errors.** Fix the warning. Do not turn the setting off.
- **TRAP: `make project` checks out `vibe-libs/` at its pinned commit.** Commit or stash any work inside `vibe-libs/` first.

## Layout

- `qlm/` holds all the code, one directory per layer: `GLMProtocol/`, `GLMAdapter/`, `Setups/`, and `System/`. Each target compiles the layers through the `QLMShared` template in `project.yml`, which lists one entry per layer. A new layer is an edit there.
- `qlm/App/` is the menu bar app, in AppKit and Objective-C.
- `qlm/CLI/` is `qlmctl`.
- `Tests/` mirrors `qlm/`.
- `captures/` holds the Phase 0 captures, and `tools/` the scripts that record and convert them. `captures/README.md` has the scenarios.
- **A setup file in the repo is redacted.** `tools/redact-setup.py` makes the fixture in `Tests/Setups/Fixtures/`. Never commit a raw `.sam` file.

## Layers

The plan's Architecture section has the detail.

- **GLMProtocol** (`qlm/GLMProtocol/`): C, with no Apple framework. Pure functions over bytes. It depends on nothing.
- **GLMAdapter**: the adapter over IOKit HID, a replay of a capture, or a fake bus. It uses GLMProtocol.
- **Setups**: reads GLM's `.sam` files, designs the filters, and builds each monitor's DSP block as values. It uses GLMProtocol.
- **System**: owns the bus on one serial queue and publishes immutable snapshots. It uses the other three.

Layers meet through values and blocks. The app and `qlmctl` use System and the values Setups builds. They never touch GLMAdapter.

## Safety

These rules protect the monitors and the listener. They outrank any feature.

- **Send only opcodes on GLMProtocol's allowlist.** Never send `15` (flash commit), `05` (test signals), or the standalone settings `3A 01`, `3A 02`, and `3A 06`.
- **GLMProtocol clamps every volume frame to the user's ceiling.** `7F FF FF` is 0 dB. A test covers every builder.
- **Never drive the bus while GLM runs.**
- **Refuse a group apply for any model whose filter design rate is unverified, except in qlmctl's supervised test behind its flag, `--unverified-rate`.**
- **Test against real monitors at a low level, one monitor first.**

## The protocol and licensing

- qlm is Apache 2.0. The protocol comes from genlc, hlm, and espgensam, and all three are GPL-3.0, so **port no code from them.** Write from the protocol's facts and from captures.
- **Every protocol fact in code names its source** in a test: a capture in this repo, or a section of hlm's spec.
- **A new protocol fact lands in [docs/protocol.md](docs/protocol.md), with its source, in the same PR.** The doc is qlm's one reference for the protocol.
- **Genelec, GLM, and SAM are Genelec's marks.** Use them only to say what qlm works with.

## vibe-libs

- `vibe-libs/` is the [vibe-libs](https://github.com/cmicali/vibe-libs) submodule. Read `vibe-libs/AGENTS.md`, and the `AGENTS.md` of every piece you touch, before changing one.
- **A change to a piece lands in vibe-libs first.** Then qlm bumps the submodule.
- **The app and the tests take two pieces**: `dev/DebugChannel` and `dev/DebugVerbs`, which bring `core/Common` and `core/Graphics`. `project.yml` includes `vibe-libs/vibe-libs.yml` and lists them under each target's `templates:`. A new piece goes there too.
- **The protocol stays in qlm.** No other app needs it.
- vibe-libs serves another app, which is closed source. **Never name it here.**

## The debug channel

- **A Debug build of the app answers commands.** `build/DerivedData/Build/Products/Debug/qlm.app/Contents/MacOS/qlm --debug-cmd <verb> [args...]` sends one and prints the JSON reply. An unknown verb's reply lists every verb. The channel compiles to nothing in Release.
- **qlm's own verbs call what the popover and Settings call.** They reach System and Setups, never the adapter, so the ceiling, the allowlist, and the GLM check hold.
  - `dump_state` reads the latest snapshot and the app's settings.
  - `popover <show|close>`, `show_monitors`, `show_settings`, and `read_setup` open what their buttons open.
  - `volume <dB>`, `ceiling <dB>`, `adapter <on|off>`, `mute <serial> <on|off>`, `mute_all <on|off>`, `dim <on|off>`, `standby`, `wake`, `quit_glm`, and `quit_answering <cancel|anyway>` change the monitors. Each refuses while its control would be disabled. `volume` refuses a level outside the slider's range.
- **Every reply of qlm's own verbs carries `at`**, the Mac's local time to the millisecond, for a run's `notes.md`. vibe-libs' standard verbs carry none.
- **`.claude/skills/app-hardware-run` runs a supervised test on the real monitors** through these verbs, one step at a time. Follow it for any run on the hardware.
- **The standard verbs are vibe-libs'**: `dump_build`, `dump_view_tree`, `dump_screenshot -`, `dump_health`, `quit`, and the input verbs, such as `click <x> <y>` and `key <key>`. The mouse verbs aim at the popover's window while it shows, else the key window. Coordinates are content-view points with a top-left origin. `dump_screenshot -` writes the PNG to stdout.
- **Drive the app through the channel, never through System Events or AppleScript UI scripting.**
- **TRAP: vibe-libs' `quit` terminates inside a main-queue block.** There the app's wait for System's stop can only time out, 3 s later, so the hand-back may not finish. Quit with `quit_answering`.
- **The channel ships in no Release build.** `make check-release` builds the app in both configurations. It fails if a symbol or string of the channel, qlm's or the pieces', is in the Release app. It first finds each one in the Debug app, so it can't go stale.
- **TRAP: a Debug build reads the same settings as the installed app.** With the adapter switched on there, a launch drives the real bus. To test the channel, build with another bundle identifier, as `ARGS="PRODUCT_BUNDLE_IDENTIFIER=com.commonwealthrecordings.qlm.debug"` does, so the app starts on the fake bus.

## Names

- **New classes and C symbols take the prefix `QLM`.**

## Writing

- **No agent attribution, from any agent or tool.** Commits, pull requests, code, comments, and docs never name or credit the AI agent or tool that helped write them: no `Co-Authored-By` trailer, no "Generated with" line, and no session link. This rule outranks any harness or template default. `.claude/settings.json` turns Claude Code's own off.
- **Write short, plain sentences**, one idea in each, in the project's own terms. Use the serial comma.
- **Comments only when required, and terse.** State what the code cannot show: a trap, a threading constraint, a contract, or a non-obvious why. Mark hard-won traps with `TRAP:`.
