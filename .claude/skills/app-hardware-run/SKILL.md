---
name: app-hardware-run
description: Run a supervised test of qlm's menu bar app on the real monitors, one step at a time, through a Debug build's debug channel, and log each step's time for the capture's notes.md. Use when the user wants to test the app on the hardware, script an app run during a capture, or drive the running app from the terminal.
---

# A supervised hardware run of the app

This drives a running Debug build of the app through its debug channel, one verb per step. The user listens at the desk. You ask before every step, run that one step, and log its time and what the user heard. The log becomes the capture's `notes.md`.

Each of qlm's verbs is the app's own action: the slider, Settings, a mute button, the power button, the banner's Quit GLM, or Quit. Each refuses while that control would be disabled. So the ceiling, the allowlist, and the GLM check hold, as they do for a click. No verb sends a frame of its own.

## Rules

These come from `AGENTS.md`'s Safety section. They outrank the user's plan and this skill's.

- **One step at a time, and ask before each.** Run exactly the verb the user agreed to. Never chain two steps, retry with other arguments, or work around an error without asking.
- **Low level, one monitor first.** Agree on the ceiling and the level before the adapter goes on. Earlier runs used a −35 dB ceiling and −50 dB. **Never raise the ceiling above the one agreed.**
- **Never drive the bus while GLM runs.** The app refuses the adapter while GLM holds it. **Run `quit_glm` only on the user's word.**
- **One host at a time.** Never run `qlmctl` against the adapter while the app runs, and never run a second qlm, the installed one included.
- **A louder hand-back needs the user's own yes.** When `dump_state` gives `quitAsksFirst` as true, the adapter may raise the level about 2.6 s after qlm quits or the adapter goes off. That's a `snapshot.handBack.kind` of `louder`, or `unknown` with no knob read. Run `quit_answering anyway` or `adapter_off_answering anyway` only after the user says so. Otherwise suggest they turn the knob down first.
- **If anything sounds wrong, run `mute_all on` at once**, then ask. It needs no permission. Tell the user it ran.
- **Quit with `quit_answering`, never vibe-libs' `quit`.** The standard `quit` terminates inside a main-queue block. There the app's wait for System's stop can only time out, 3 s later, and a louder hand-back puts up the alert while the channel waits.

## The client

The channel lives only in a Debug build. A Release build has none of it, and `make check-release` checks that.

```bash
make build CONFIG=Debug
```

The app's own binary is the client. Use this path for every command:

```bash
Q=build/DerivedData/Build/Products/Debug/qlm.app/Contents/MacOS/qlm
"$Q" --debug-cmd dump_state
```

`"$Q" --debug-cmd <verb> [args...]` prints the reply, one JSON object. It exits 0 for a reply, 2 for an error reply (`{"error": …}`), 1 when no reply came in 5 s, and 64 for a usage error. With no reply, no Debug build of qlm is running, or it hung. An unknown verb's reply lists every verb.

**Every reply from qlm's own verbs carries `at`**: the Mac's local time when the verb ran, to the millisecond, such as `2026-10-31T14:06:11.123-04:00`. That is the step's time. An error reply carries it too. vibe-libs' standard verbs carry none.

| Verb | The app's action | Refused when |
| --- | --- | --- |
| `dump_state` | Reads the snapshot the popover shows, and the app's settings: below | never |
| `volume <dB>` | The slider, on GLM's 0.5 dB steps | System is stopped, or the level is outside the slider's range (`sliderRange`) |
| `ceiling <dB>` | Settings' ceiling. The preferences bound it: at most 0 dB, on a step at or below the value | never |
| `adapter <on\|off>` | Settings' "Drive the real monitors through the GLM adapter". A change starts a new System | `off` while the louder alert would show (`quitAsksFirst`) |
| `adapter_off_answering <cancel\|anyway>` | Turning the setting off. The argument answers the louder alert, if it would show | never |
| `mute <serial> <on\|off>` | One monitor's mute button | System tracks no monitor with that serial |
| `mute_all <on\|off>` | Mute | System is stopped, or tracks no monitor |
| `dim <on\|off>` | Dim | System is stopped |
| `standby` | Power, while it reads Standby | System is stopped or tracks no monitor, or no monitor is on |
| `wake` | Power, while it reads Wake | System is stopped or tracks no monitor, or a monitor is on |
| `quit_glm` | The banner's Quit GLM. GLM may ask to save | the banner offers no Quit GLM, or GLM was asked already |
| `quit_answering <cancel\|anyway>` | Quit. The argument answers the louder hand-back alert, if it would show | never |

`dump_state` gives:

- `usesAdapter`, `sliderRange` (`lowestDecibels` and `ceilingDecibels`), `quitGLMButton` (its title, or null while hidden), `quitAsksFirst`, `popoverShown`, and `windows`.
- `snapshot`, or null before System's first one:
  - `running`, `idle`, `busProblem` (`none`, `noAdapter`, `glm`, or `otherHost`), `adapterProblem`, and `adapterError`.
  - `adapter`: the device, model, and serial, and the knob: `knobPresent` and `knobTenths`.
  - `volumeDecibels` as set, before dim. `ceilingDecibels`, the one System caps at. `dimmed`, `allMuted`, `mutingAll`, `anyOn`, `applying`, `activeGroupName`, and `wokeWithoutGroup`: a wake went out with no group active, so the woken monitors play without their group's settings.
  - `handBack`: `kind` (`knobLevel`, `louder`, or `unknown`), `knobDecibels`, `volumeDecibels` (the level sent, dimmed and under the ceiling), and the app's `line` about it.
  - `monitors`: each one's serial, model, class, hardware ID, session, status, mute, and offline state, with its missed polls and temperature.

After `ceiling` or `adapter`, an open Settings window shows the old value until it opens again. `dump_state` reads the new one.

`quit_answering` replies before the app quits. Check it went with `pgrep -x qlm`. `quitting` is false only when the alert would show and the answer was `cancel`.

## Before the run

1. Read `AGENTS.md`'s Safety section and the last capture's `notes.md`, for what the monitors did then.
2. Check that no qlm runs: `pgrep -lx qlm`. If one does, the installed app included, ask the user to quit it.
3. Read the settings the app starts from. The Debug build shares them with the installed qlm.

   ```bash
   defaults read com.commonwealthrecordings.qlm
   ```

   `QLMUsesAdapter` set to 1 means the app drives the real monitors at launch, at `QLMVolumeDecibels`, under `QLMCeilingDecibels`. `QLMWakesAtLaunch` set to 1 wakes them too. Tell the user what you found. If the adapter setting is on, ask before you launch.
4. Agree on the plan with the user: the scenario's name, the ceiling, the level, and the steps, in order. Write the steps down before the first one runs. The template below is a start.
5. Ask the user to start the capture, if there is one, and to tell you the time `capture.sh` printed. That is the run's zero.
6. Launch the app: `open build/DerivedData/Build/Products/Debug/qlm.app`. Then run `dump_state` until it replies.

   **TRAP: a new build's first launch waits on macOS.** It asks whether qlm may open the Documents folder, where GLM keeps its setup files. Until the user answers, the app's main thread waits, and the channel never installs. Every verb gets no reply. Ask the user to answer the prompt. Granting it is theirs to do.

## Each step

1. **Say the step.** Give the command, what it should do to the monitors, and what to listen for. Name the capture that showed it, if one did.
2. **Ask** with AskUserQuestion: run it, skip it, or stop the run. Wait for the answer.
3. **Run the one command.** Read the reply. On an error reply, log it, show it, and ask what next.
4. **Log it** at once, from the reply's `at`.
5. **Ask what the user heard.** Offer "No change", "Quieter", "Louder", and "Silence". They can type more. Log their words.
6. **Run `dump_state`**, and log one line: the level sent, dim, mute, power, the knob, and the hand-back.

Things the user does by hand are steps too: a knob turn, a power switch, a cable. Ask them to say when it's done, then run `dump_state` and log its `at`.

## The log

Keep it in `captures/<scenario>/notes.md` as the run goes, in the table every capture's notes use:

```markdown
| Time (EDT) | Seconds | What happened, and what the user heard |
| --- | --- | --- |
| 14:59:00 | 0 | Capture started. |
| 15:00:06 | 66.3 | `volume -50`: the app took −50 dB. Heard: all six dropped about 10 dB at once. |
```

- **Time** is `at`, as `HH:MM:SS`. Keep the milliseconds in your own working notes.
- **Seconds** is from the run's zero, by the Mac's clock. Mark these as the Mac's until `reports.txt` exists. Then correct each to the first report the step sent, as earlier captures did.
- Write what was run, what the reply said, and the user's own words for what they heard.
- Above the table, say what the run is, the date, the route, the build's commit, the ceiling, and the level. Below it, once the run is done, add what the run showed, surprises, and what is not explained. `captures/qlm-control-all/notes.md` is the model.

## A template plan

For the app's run on all six monitors. Change it with the user before you start.

1. `dump_state`, on the fake bus. The app answers.
2. `ceiling -35`, then `volume -50`, still on the fake bus.
3. The user quits GLM, or says to run `quit_glm` if `quitGLMButton` offers it.
4. `adapter on`. Then `dump_state` until `busProblem` is `none` and every monitor reads `on`. Heard: the level the app keeps.
5. `mute <serial> on`, then `off`, for one monitor.
6. `mute_all on`, then `off`.
7. `dim on`, then `off`.
8. `standby`. Wait for every monitor to read `standby`. Then `wake`.
9. The user turns the knob a little. `dump_state` reads it.
10. `quit_answering cancel`, or `quit_answering anyway` as the hand-back allows and the user says. Heard: the hand-back, about 2.6 s after the quit.

## After the run

- Check that qlm quit: `pgrep -x qlm`.
- Tell the user what the log holds and what to fill in once `reports.txt` exists.
- If the run turned up a new protocol fact, it goes into `docs/protocol.md`, with this capture as its source, in the same PR as the capture.
