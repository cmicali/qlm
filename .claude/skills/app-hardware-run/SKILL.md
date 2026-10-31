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
| `ceiling <dB>` | Settings' ceiling, on a step at or below the value | the level is above 0 dB, as Settings' field refuses it |
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

## The second run's plan: `qlm-app-second`

The app's second run on all six monitors. It checks the fixes made since `qlm-app-first` that have run only on the fake bus: #49, #52, and #53. It sets out to check nothing else. It keeps the first run's −35 dB ceiling and −50 dB level. Agree on it with the user, as with any plan.

### Before this run

"Before the run" applies as it is. At its step 3, this run checks two more facts:

- **The Debug build shares the installed app's defaults.** The per-bus check reads them.

  ```bash
  plutil -extract CFBundleIdentifier raw build/DerivedData/Build/Products/Debug/qlm.app/Contents/Info.plist
  ```

  It must give `com.commonwealthrecordings.qlm`. A build made with the `.debug` identifier keeps its own domain, so `defaults read com.commonwealthrecordings.qlm` would miss what it writes. Rebuild without it.
- **`QLMUsesAdapter` reads 0.** Then the app starts on the fake bus, and steps 1 to 3 touch no monitor.

  ```bash
  defaults read com.commonwealthrecordings.qlm QLMUsesAdapter
  ```

  A key that doesn't exist reads as 0 too. If it reads 1, don't launch. Ask the user to turn it off, and run `defaults write com.commonwealthrecordings.qlm QLMUsesAdapter -bool false` only on their word.

The calibration mic stays out of the adapter for the whole run. `qlm-mic-discovery`, below, comes after it.

Keep the whole `defaults read` from step 3 in the log. It is the per-bus check's "before". If `QLMVolumeDecibels` isn't −50, ask whether to write −50, so the monitors come on at the run's level.

### The steps

The knob decides each stop's hand-back. It goes above the ceiling once, for steps 7 to 10, and those steps stop nothing. It sits below the level for both stops, steps 16 and 20, so neither makes the monitors louder and no step needs `anyway`. Mute all spans the one restart, so a single gap checks both the leases and the lifted mute.

| Step | Verb, or what the user does | Fix | Heard | What proves it |
| --- | --- | --- | --- | --- |
| 1 | `dump_state` | | Nothing | `usesAdapter` false. `snapshot.monitors` holds the fake bus's three. |
| 2 | `ceiling -35` | | Nothing | `sliderRange.ceilingDecibels` −35 |
| 3 | `volume -55`. Then `defaults read com.commonwealthrecordings.qlm`. | #52, each bus keeps its own level[^per-bus] | Nothing | `snapshot.volumeDecibels` −55. In the defaults, `QLMFakeVolumeDecibels` is −55, and `QLMVolumeDecibels` is as it was before launch. |
| 4 | The user quits GLM. | | The adapter takes over at the knob. | |
| 5 | `adapter on`. Then `dump_state` until `busProblem` is `none` and six monitors read `on`. | #52, each bus keeps its own level[^per-bus]. #53, the old bus's monitors go.[^list] | The level drops to −50 dB. | `snapshot.volumeDecibels` −50, not the fake bus's −55. `monitors` holds six, and none is `offline`. |
| 6 | `popover show`, `dump_view_tree`, and `dump_screenshot - > captures/qlm-app-second/names.png`. Then `popover close`. | #53, monitors named as the setup names them[^names] | Nothing | The popover's rows, not `dump_state`. Each row shows its setup name. `114bab` is Left, and `114bea` is Right.[^ids] The serial is the row's tip. |
| 7 | The user turns the knob slowly up to about −30 dB, a few dB above the ceiling. Not to its top stop. | #52, the volume held at the ceiling[^hold] | The level rises to −35 dB, and no further. | `volumeDecibels` −35 while `handBack.knobDecibels` reads about −30. `handBack.kind` is `louder`, and `quitAsksFirst` is true. |
| 8 | `adapter off` | #52, a stop that may be louder asks first[^asks] | Nothing | An error reply: it refuses. `usesAdapter` stays true. |
| 9 | `adapter_off_answering cancel` | #52, as step 8[^asks] | Nothing | The reply's `asksFirst` is true and `restarted` false. `usesAdapter` stays true. |
| 10 | `quit_answering cancel` | #52, as step 8[^asks] | Nothing | The reply's `asksFirst` is true and `quitting` false. `pgrep -x qlm` still finds it. |
| 11 | The user turns the knob down to about −55 dB. | | The level follows the knob down. | `volumeDecibels` about −55. `handBack.kind` is `knobLevel`. |
| 12 | `volume -50` | | A little louder | `volumeDecibels` −50. `handBack.kind` is `knobLevel`, and `quitAsksFirst` is false. |
| 13 | `mute_all on` | | Silence | `mutingAll` and `allMuted` true |
| 14 | `mute 8351BP21002711 off`, the Left 8351B | #49, a lift of one mute under mute all holds[^lift] | Only the Left plays. | The Left's `muted` is false and `lifted` true. The other five read `muted`. `mutingAll` stays true. |
| 15 | `defaults read com.commonwealthrecordings.qlm` | #52, the record and the leases kept[^per-bus] | | The defaults, not `dump_state`. `QLMMutingAll` is 1, and `QLMLiftedHardwareIDs` holds `114bab`. `QLMKnownLeases` lists six sessions. Note each one. |
| 16 | `adapter off` and `adapter on`, back to back, as one step. See below. Then `dump_state` until `busProblem` is `none` and six read `on`. | #49, after a gap qlm trusts no old session until its serial answers[^gap]. #49, the lift holds.[^lift] | The Left may dip to the knob's −55 dB for a moment. The other five stay silent. | Each monitor's `session`, against step 15's. The same one means its serial answered and qlm took it back. A new one means its lease lapsed and the probe found it. The Left is still `lifted` and unmuted, and the other five muted. |
| 17 | `mute_all off` | | All six play at −50 dB. | `mutingAll` false, and no monitor `muted` or `lifted` |
| 18 | `standby`. Then `dump_state` until all six read `standby`. | | The music stops. | Each `status` is `standby`, and `anyOn` is false. |
| 19 | `wake`. Then `dump_state` until all six read `on`. Then `popover show` and `dump_view_tree`. | #53, a wake with no group active says so[^wake] | All six come back. They may sound a little different, as in the first run. | `wokeWithoutGroup` true, and `activeGroupName` null. The popover's banner reads "The monitors play without their group's settings". |
| 20 | `quit_answering cancel` | #52, the stop's rule[^asks] | The level drops to the knob's −55 dB at once. Nothing changes 2.6 s later. | The reply's `asksFirst` is false and `quitting` true. `pgrep -x qlm` finds nothing. |
| 21 | `defaults read com.commonwealthrecordings.qlm` | #52, each bus keeps its own settings[^per-bus] | | `QLMVolumeDecibels` −50 and `QLMFakeVolumeDecibels` −55. `QLMKnownLeases` holds the sessions from the wake. `QLMMutingAll` is 0, and `QLMLiftedHardwareIDs` is empty. |

**Step 16 is the one step that runs two verbs.** Agree on it as one step before the run. Run it as one command line:

```bash
"$Q" --debug-cmd adapter off && "$Q" --debug-cmd adapter on
```

`&&` stops at a refusal. Back to back, the gap stays under the 3 s or so a monitor holds a quiet host's lease, so qlm can take back the leases still held.[^lapse] As two steps, the gap passes that. Every old session then answers `01 7E`, and the probe leases all six anew. That still shows qlm used no old session unchecked, but takes nothing back. Either way, the capture shows the check: a `19 01` to each session in step 15, before the first probe.

After step 20, the user relaunches GLM once the capture stops. Its launch applies the group, so the monitors play with their group's settings again.

### What this run can't reach

These fixes need a fault or a race that no verb or hand can make safely. Each has its test on the fake bus.

| Fix | Why the run can't reach it | What would | Test |
| --- | --- | --- | --- |
| #49: a ceiling lowered while a volume frame waits, in System's queue or behind the link's syncs | The window is milliseconds wide. | A proxy that holds the adapter's replies, which opens the window | `testALoweredCeilingCapsTheVolumeFramesAlreadyQueued`, `testALoweredCeilingCapsAVolumeFrameTheLinkHolds` |
| #49: a lost sync reply. #52: the banner when the adapter stops answering. | Nothing on the channel silences the adapter. An unplug shows "No adapter", which is another path. Pausing the Pi proxy might work, but after 2.6 s the adapter takes the bus at the knob's level, and how the patched usb-proxy recovers is untested. A lost capture or a replug mid-run costs more than the step shows. | A proxy mode that drops the adapter's replies on command, tried on the bench first | `testALostSyncReplyIsSyncedAgain`, `testASilentAdapterShowsAsItsOwnProblemWithTheKnobKept`, `testALinkThatLostTrackShowsAsItsOwnProblem`, `testTheBannerShowsTheAdaptersProblem` |
| #49: a report IOKit didn't take, and a mute whose `2B` never went out | It needs IOKit to time out on a report. | A proxy that stalls one report from the Mac | `testAPollIOKitDidNotTakeIsNoMissedPoll`, `testAMuteWhose2BDidNotGoOutIsStatedAfterTheNextPoll` |
| #49: a reply from before a stop | It needs a reply still in flight across a restart. The adapter answers in milliseconds, and the restart waits for System's stop. | A proxy that holds one reply past the restart | `testAReplyFromBeforeAStopEndsNothingAfterTheStart` |
| #49: the check after another host | Step 16's gap has no other host. GLM would have to lease the monitors, in its own order, between qlm's runs. Its launch applies its group, and ends step 19's flag. | A later run: quit qlm, run GLM, quit it, and relaunch qlm | `testABusThatComesBackChecksEveryLeaseBeforeUsingIt` |
| #49: a `2B` round's mutes as it goes out | It needs two mute changes inside one round. By hand that's luck. | None safe. The fuzz covers it. | `testARoundSaysTheMutesAsTheyAreWhenItGoesOut` |
| #52: the stop decides from a snapshot of now | Steps 8 to 10 and 20 use it. A snapshot that lags needs a level not yet published, within milliseconds. | None safe | `testASnapshotOfNowSeesALevelNotYetPublished` |
| #52: the ceiling field saves as editing ends, and the −30 dB default | The `ceiling` verb sets the preference, not the field. The domain holds a ceiling, so the default never shows. | Typing in Settings, as #55's check did | None for the field. `testTheDefaultCeilingIsQlmctlsHighest` |
| #53: a wake applies the active group | The app refuses every group in the setup, since each holds an 8351B. | `qlmctl`'s supervised apply, behind `--unverified-rate` | `testAWakeAppliesTheActiveGroupToEachMonitorLeasedAgain` |

[^per-bus]: #52, fixes 4 and 5. `testEachBusKeepsItsOwnLevel`, `testASnapshotsLevelStaysWithItsBus`, `testTheRealMonitorsKeepTheirKeys`, `testTheRecordAndTheLeasesOutlastALaunch`, and `testOnlyARunningSystemsRecordIsKept`, in `Tests/App/QLMPreferencesTests.m`. The real monitors keep the first run's keys, such as `QLMVolumeDecibels`. The fake bus's start with `QLMFake`.
[^list]: #53, fix 2. `testAnotherBusForgetsTheMonitorsSeen`, in `Tests/App/QLMMonitorListTests.m`. In `qlm-app-first`, the fake bus's three stayed in the list, as offline.
[^names]: #53, fix 3. `testAMonitorIsNamedAsTheSetupNamesIt`, in `Tests/App/QLMFormatTests.m`, with the redacted fixture. Its names are Left, Right, Rear Left 8330A, Rear Right 8330A, Sub, and Center 7350A. The setup's names for the user's own hardware IDs need the real monitors.
[^ids]: `captures/qlm-app-first/notes.md`: the Left 8351B is `8351BP21002711`, hardware ID `11 4B AB`, and the Right is `8351BP21002717`, `11 4B EA`. No capture yet ties the two 8330As to their hardware IDs, so the user confirms those names.
[^hold]: #52, fix 7. `testTheKnobAboveTheCeilingHoldsTheVolumeAtIt`, in `Tests/System/QLMSystemTests.m`. In `qlm-app-first`, 75 knob bursts went out with the level held at −35 dB. A capture should now show no burst once the level reaches the ceiling.
[^asks]: #52, fix 3, and its merge with main. `testAStopMayRaiseTheLevelWhenTheTakeOverIsLouderOrUnknown` and `testAStopWithoutTheBusRaisesNothing`, in `Tests/App/QLMFormatTests.m`. `testTurningTheAdapterOffAnswersTheLouderAlert`, in `Tests/App/QLMDebugChannelTests.m`.
[^lift]: #49, fix 6. `testLiftingOneMuteUnderMuteAllHolds`, in `Tests/System/QLMSystemTests.m`: before it, the Left came back muted at its next lease. #52 keeps the lifted mutes across a restart, under `QLMLiftedHardwareIDs`.
[^gap]: #49, fixes 2 and 3. `testANewSystemChecksTheLeasesItIsGivenBeforeLeasing` and `testARestartTakesBackLeasesStillHeld`, in `Tests/System/QLMSystemTests.m`. #52 gives the new System the leases saved under `QLMKnownLeases`.
[^lapse]: `docs/protocol.md`, "When the host goes quiet". In `qlm-app-first`, the monitors dropped GLM's leases within 3.1 s.
[^wake]: #53, fix 1. `testAWakeWithNoGroupActiveSaysSo` and `testAGroupAppliedAfterAWakeEndsIt`, in `Tests/System/QLMSystemTests.m`. In `qlm-app-first`, the woken monitors sounded a little different until GLM's launch applied the group.

## The mic's discovery: `qlm-mic-discovery`

A capture of its own, run after `qlm-app-second`, to decode what the adapter reports with the calibration mic in. qlm parses the mic's fields already, but nobody knows their scale.[^mic-known] This capture is the first one made to find out. It drives no app. `qlmctl poll` is the host, and the user makes every change by hand: the mic, the room's sound, and the knob. The mic stays out for every other run, so this one comes last, with the app quit.

The rules above still hold, with `qlmctl` in place of the verbs:

- **GLM stays closed, and so does the app.** One host at a time: `pgrep -lx qlm` finds nothing, and no other `qlmctl` runs.
- **`poll` sends nothing new.** It sends the adapter's status poll and identity queries, the probe, the leases, and the monitors' polls. It sends no level, so the monitors keep the one the app's last stop left: the knob's, about −55 dB after `qlm-app-second`.[^poll-level] The ceiling stays −35 dB, and the level stays at −50 dB or lower.
- **Never send `51`, the mic serial query.** genlc names it, and GLM sends `01 51 82` as it opens. GLMProtocol's allowlist refuses `51` to the adapter. Only a capture of GLM can show more of it.
- **The signal is off whenever the knob is out.** With no knob, the level the adapter applies at a take-over is unknown.[^no-knob]

### Before the capture

1. Build `qlmctl` with `make cli`. Use this path:

   ```bash
   C=build/DerivedData/Build/Products/Release/qlmctl
   ```

2. Check that the app quit, with `pgrep -lx qlm`, and that GLM is closed.
3. With the mic out, read the adapter:

   ```bash
   "$C" info
   ```

   `mic` must read `none`, and the knob −50 dB or lower. If the knob reads higher, ask the user to turn it down first. The adapter applies it at once, since no host runs.
4. Set up REW's generator: pink noise on the Right channel only, off, at −40 dBFS. One monitor keeps the distance step simple.
5. Put the mic on a stand, on the Right 8351B's axis, 0.5 m from it. Mark the spot, and the spot at 1 m.
6. Ask the user to start `sudo ./pi/capture.sh qlm-mic-discovery` on the Pi, and to tell you the time it printed. That is the run's zero.

### The steps

Steps 1 to 5 run under one `poll`. Start it in the background, with its output in the capture's folder:

```bash
"$C" poll --seconds 600 > captures/qlm-mic-discovery/poll-1.txt
```

`poll` prints the knob and each monitor's telemetry, not the mic. So log each hand action's time when the user says it's done, with `date +%T`. `reports.txt` gives the exact poll later. If `poll` exits early, the adapter takes over at the knob, which changes nothing. Ask before starting it again.

| Step | What the user does | Seconds | What it settles |
| --- | --- | --- | --- |
| 1 | The mic out. Then plug it in. Then pull it out again. | 10 out, 20 in, 10 out | How the adapter reports a hot-plug: the shape goes from `33 30 36 DF` to `32 34 DE DD 30 36 DF` and back. How many polls the change takes, and whether `34` ever appears alone. |
| 2 | Plug the mic in at the 0.5 m spot. The room silent, and the noise off. | 30 | The floor of `DE` and `DD` |
| 3 | The noise on, at −40, −30, and −20 dBFS in turn | 30 each | Whether `DD` steps by a fixed ratio per 10 dB, and which: linear in pressure or in power, or already in dB. Whether `DE` takes the same steps. |
| 4 | The noise off. Three sharp claps or finger snaps near the mic, 10 s apart. | 40 | Whether `DE` spikes and `DD` barely moves, which would confirm peak against average |
| 5 | The noise on at −30 dBFS. The mic at 0.5 m, then moved to 1 m. Then the noise off. | 30 each | The change against the 6 dB a doubled distance gives in free space. A room gives less. |

Step 6 runs under its own `poll`, with the noise off throughout:

```bash
"$C" poll --seconds 60 > captures/qlm-mic-discovery/poll-2.txt
```

| Step | What the user does | Seconds | What it settles |
| --- | --- | --- | --- |
| 6 | The mic in, the noise off. Pull the knob out, wait, and plug it back in before `poll` ends. Leave the knob where it was. | 20 out | The one shape no capture has: mic in, knob out. `poll` prints `no knob` while it's out. |

If REW's top step leaves `DD` at its floor, stop. Don't raise the monitors' level. A louder test is the user's call, at −50 dB or lower.

After step 6, ask the user to stop the capture, then to unplug the mic.

### After the capture

Convert the capture, with the adapter's number that `capture.sh` printed, as `captures/README.md` says. Then pull `DE`, `DD`, and the shape from each status reply in a window of seconds. `DE` and `DD` read as unsigned and big-endian, and `DF` as signed.

```bash
python3 -I - captures/qlm-mic-discovery/reports.txt 100 130 <<'EOF'
import sys
path, start, end = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
sizes = {0: 0, 1: 1, 2: 2, 3: 4}
known = {'30', '31', '32', '33', '34', '36', 'DD', 'DE', 'DF'}
for line in open(path):
    if line.startswith('#'):
        continue
    time, way, *hexes = line.split()
    if way != 'in' or not start <= float(time) <= end:
        continue
    raw = bytes.fromhex(''.join(hexes))[1:]
    if 0x7E not in raw:
        continue
    raw = raw[:raw.index(0x7E)]
    frame, i = bytearray(), 0
    while i < len(raw):
        if raw[i] == 0x7D:
            i += 1
            frame.append(raw[i] ^ 0x20)
        else:
            frame.append(raw[i])
        i += 1
    if frame[:2] != b'\x01\x09' or frame[2] not in (0x30, 0x31, 0x32, 0x33):
        continue
    fields, i = [], 2
    while i < len(frame) - 2:
        tag, size = frame[i], sizes[frame[i] >> 6]
        value = int.from_bytes(frame[i + 1:i + 1 + size], 'big', signed=tag == 0xDF) if size else None
        fields.append(f'{tag:02X}' if value is None else f'{tag:02X}={value}')
        i += 1 + size
    if all(f[:2] in known for f in fields):
        print(time, ' '.join(fields))
EOF
```

It walks the tags by their top two bits, as [adapter-status.md](../../../docs/adapter-status.md) infers. It prints only replies made of the known tags. So `01 51 82`'s ASCII reply, which also starts with `32`, drops out, and so would a status reply with a new tag. Count the replies it drops in each window, and look at any that aren't the serial query's.

What each result would mean, against the guesses in adapter-status.md:

| Step | If | Then |
| --- | --- | --- |
| 1 | The shape changes within a poll or two of the plug, both ways | The adapter reports the mic live, and qlm can show a hot-plug. |
| 1 | `34` shows without `32`, or `32` without `34` | `34` isn't tied to `32`. The guess that it opens the readings falls. |
| 2 | `DD` holds steady and `DE` wanders above it | The floor of each. Every later reading is read against it. |
| 3 | `DD`'s median rises about 3.16 times per 10 dB | `DD` is linear in pressure. |
| 3 | About 10 times per 10 dB | `DD` is linear in power. |
| 3 | By a fixed amount per 10 dB | `DD` is already in dB, or another log scale. |
| 3 | `DE` takes the same steps as `DD` | Both share one scale, and the first poll of each pair still reading higher keeps the peak guess. |
| 4 | `DE` spikes in the poll after each clap, and `DD` barely moves | `DE` is a peak since the last read, and `DD` an average. How long `DD` takes to settle gives its window. |
| 5 | The readings drop by about 6 dB, in step 3's scale | The mic reads the sound field as expected. A smaller drop is the room. |
| 6 | The shape is `32 34 DE DD 31` | The mic and knob fields are independent. Any other shape goes into the shape table as found. |

A decoded fact lands in `docs/adapter-status.md` and `docs/protocol.md`, with this capture and its seconds as its source, in the capture's PR. Add the scenario to `captures/README.md`'s list there too. The mic serial query stays off limits, whatever this capture shows.

[^mic-known]: `docs/adapter-status.md`, "The mic: `DE` and `DD`". `qlm/GLMProtocol/QLMReplies.c` parses `mic`, `micDE`, and `micDD`. `QLMSnapshot` has `micPresent`. `qlmctl info` prints `mic in` or `mic none`, and no command prints the readings yet. The captures with the mic in are `startup-idle-mic` and `knob-sweep`.
[^poll-level]: `qlmctl`'s usage, for what `poll` sends. `docs/experiments.md`, Part C: `poll` sends no level, and while it runs, the adapter keeps what it applied.
[^no-knob]: `docs/experiments.md`, Part C, Q4. Its steps keep the signal off at every take-over with no knob, for the same reason.

## After the run

- Check that qlm quit: `pgrep -x qlm`.
- Tell the user what the log holds and what to fill in once `reports.txt` exists.
- If the run turned up a new protocol fact, it goes into `docs/protocol.md`, with this capture as its source, in the same PR as the capture.
