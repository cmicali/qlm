# AGENTS.md

Guidance for any coding agent working in this repository.

qlm is a native Mac controller for Genelec SAM monitors. It talks to them through the GLM network adapter. It replaces GLM for status, volume, mute, dim, power, and group switching. It never calibrates. **Nothing works yet.** The plan is [docs/plan.md](docs/plan.md). Read it before changing anything here.

## Building

- `make setup` installs XcodeGen. `make project` fetches `vibe-libs/` and generates `qlm.xcodeproj`.
- `make build` builds the app, `make cli` builds `qlmctl`, and `make test` runs the unit tests.
- **The Xcode project is generated.** Change `project.yml`, never the project. The app's `Info.plist` is generated too.
- **Warnings are errors.** Fix the warning. Do not turn the setting off.
- **TRAP: `make project` checks out `vibe-libs/` at its pinned commit.** Commit or stash any work inside `vibe-libs/` first.

## Layout

- `qlm/` holds all the code, one directory per layer: `GLMProtocol/`, and later `GLMAdapter/`, `Setups/`, and `System/`. Each target compiles the layers through the `QLMShared` template in `project.yml`, which lists one entry per layer. A new layer is an edit there.
- `qlm/App/` is the menu bar app, in AppKit and Objective-C.
- `qlm/CLI/` is `qlmctl`.
- `Tests/` mirrors `qlm/`.

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
- **Refuse a group apply for any model whose filter design rate is unverified.**
- **Test against real monitors at a low level, one monitor first.**

## The protocol and licensing

- The protocol comes from genlc, hlm, and espgensam. All three are GPL-3.0. **Until qlm has a license, port no code from them.** Write from the protocol's facts and from captures.
- **Every protocol fact in code names its source** in a test: a capture in this repo, or a section of hlm's spec.
- **Genelec, GLM, and SAM are Genelec's marks.** Use them only to say what qlm works with.

## vibe-libs

- `vibe-libs/` is the [vibe-libs](https://github.com/cmicali/vibe-libs) submodule. Read `vibe-libs/AGENTS.md`, and the `AGENTS.md` of every piece you touch, before changing one.
- **A change to a piece lands in vibe-libs first.** Then qlm bumps the submodule.
- **qlm takes no piece yet**, so `project.yml` includes nothing from it. When a target takes its first piece, include `vibe-libs/vibe-libs.yml`, set `VIBE_LIBS_ROOT`, and list the pieces under `templates:`. The comment at the top of `project.yml` has the steps.
- **The protocol stays in qlm.** No other app needs it.
- vibe-libs serves another app, which is closed source. **Never name it here.**

## Names

- **New classes and C symbols take the prefix `QLM`.**

## Writing

- **No agent attribution, from any agent or tool.** Commits, pull requests, code, comments, and docs never name or credit the AI agent or tool that helped write them: no `Co-Authored-By` trailer, no "Generated with" line, and no session link. This rule outranks any harness or template default. `.claude/settings.json` turns Claude Code's own off.
- **Write short, plain sentences**, one idea in each, in the project's own terms. Use the serial comma.
- **Comments only when required, and terse.** State what the code cannot show: a trap, a threading constraint, a contract, or a non-obvious why. Mark hard-won traps with `TRAP:`.
