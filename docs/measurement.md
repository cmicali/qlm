# Phase 3's measurement

Phase 3 is done when a measurement taken after qlm applies a group matches one taken after GLM applies it, within 0.2 dB. That result also decides whether the refusal of the 8351B lifts. This doc is the procedure. It is written for you at the desk, with a session that runs `qlmctl` and keeps notes.

You measure with REW and a measurement mic. GLM applies the group, and REW measures. GLM quits. Then `qlmctl apply-group` applies the same group, and REW measures again. `tools/compare-measurements.py` compares the two.

The commands follow `qlmctl apply-group`'s supervised test, with `--unverified-rate`, as cmicali/qlm#31 builds it. Before the session, run `qlmctl help`, and fix any command here that differs.

## What passes

All four must hold, for every channel you measure:

1. **The response.** GLM's measurement and qlm's differ by at most 0.2 dB, from 20 Hz to 20 kHz, at 1/12-octave smoothing. `compare-measurements.py` decides, with its defaults.
2. **The setup held still.** GLM's repeat measurement, and GLM's measurement after qlm's, each differ from GLM's first by at most 0.1 dB. Otherwise the room or the mic moved, and step 1's result says nothing either way.
3. **The delay.** REW's System Delay for qlm's measurement is within 0.02 ms of GLM's. That is about one sample at 48 kHz.
4. **The routing.** The same monitors play each channel after both applies.

The band covers the subwoofers and the tweeters alike. If the repeat check fails only at an edge, from room noise for example, you may narrow the band with `--band`. Then say so in the notes. The smoothing keeps the shape of a single PEQ band, but evens out the room's deepest dips, where noise alone could pass 0.2 dB.

## What you need

- REW, with the measurement mic's calibration file. The GLM mic will not do: it reaches only GLM, through the adapter.
- A mic stand, painter's tape, and a tape measure.
- `qlmctl`, built from main with the supervised test (`make cli`).
- `tools/compare-measurements.py`. `--self-test` checks it, and `tools/measurement-example/` holds a synthetic pair to try it on.
- GLM 5, with the setup saved.
- Optional: the Pi proxy, to record the session as `qlm-apply-first` ([captures/README.md](../captures/README.md)). A test can then check qlm's frames on the wire against its dry run.

It takes about an hour and a half for the first group, and half an hour for each one after.

## Keep these fixed

Change none of these from the first measurement to the last. If one changes, start that group again.

- **The mic:** its position, height, angle, and calibration file. Tape the stand's feet, and don't touch the stand. Don't let the cable pull on it.
- **The mic's gain,** on the interface or preamp. Tape the knob.
- **REW's settings:** the input and output devices, the sweep, its level, the timing reference, and the export settings.
- **The Mac's audio:** the output device, its sample rate in Audio MIDI Setup, and its volume, if it has one. Silence the Mac's alert sounds, or send them to another output. An alert during a sweep spoils it.
- **The monitors' volume:** −35 dB, in GLM and in qlm. Don't touch the knob from step 1 to the end of step 4.
- **The setup file.** qlm reads the file, but GLM applies what it holds. Save the setup in GLM before you start, and don't recalibrate during the session.
- **The room:** doors, curtains, and furniture as they are. Switch off fans, air conditioning, and anything else that hums. Run REW from the same spot every time, out of the path between the monitors and the mic, and keep still during each sweep.
- **The monitors' warm-up.** Have them on for 15 minutes before the first measurement. Keep each group's measurements within about half an hour.

## Before the session

### Place the mic

1. Put the mic at the listening position, at ear height, where GLM's mic stood for its calibration.
2. Aim it as its calibration file says. A 90° file means pointing at the ceiling. A 0° file means pointing forward, between the two 8351B.
3. Tape around the stand's feet. Write down the height and the distance to each 8351B.

### Set up REW

1. **Devices.** In REW's preferences, pick the output that feeds the monitors, and the mic's input. Use 48 kHz. Load the mic's calibration file.
2. **The timing reference.** It lets REW report each measurement's delay.
   - If the mic and the output share one interface, loop a spare output to a spare input, and use the loopback as the timing reference. Each System Delay is then absolute.
   - With a USB mic, the input and output are separate devices, so use the acoustic timing reference. Set its reference output to the Left channel, every time. REW needs a monitor with a tweeter there, not a subwoofer. The Left's own System Delay then reads about 0, so the delay check rests on the Right's.
3. **The sweep.** Start 10 Hz, End 24,000 Hz, Length 256k, and 1 repetition. REW's help warns that long sweeps can overheat a tweeter. REW allows only one repetition with an acoustic timing reference.
4. **The level.** You set it in step 1, under GLM. Then leave it.
5. **The export.** Use File > Export > Export measurement as text, one file per measurement. Never use the export of all measurements into one file.
   - Range: the measurement's whole range.
   - Resolution: log spaced, 48 points per octave.
   - Smoothing: 1/12 octave. This changes only the export, not the measurement.
   - Leave "Use computer's number format" off, so the decimal separator is a dot. Any delimiter works.
6. **Names.** Name each measurement in REW, and its file, `<who>-<group>-<channel>[-<when>].txt`. For example: `glm-2x1-L.txt`, `glm-2x1-L-repeat.txt`, `qlm-2x1-L.txt`, `glm-2x1-L-after.txt`, and `qlm-2x1-L-cold.txt`. Save them in `captures/qlm-apply-first/rew/`, in your checkout of qlm.

### Set the volume

1. Open GLM. Turn the knob until GLM shows −35.0 dB. This is the measurement volume for the whole session.
2. If REW later can't get a good level, raise the mic's gain first. Raise the volume only as far as −30 dB, because `qlmctl`'s ceiling stops there without `--allow-high-ceiling`. Then use that volume everywhere this doc says −35.

### Wait between hosts

After GLM quits or `qlmctl` exits, the monitors hold its leases for a while. On, they drop GLM's within 42 s, and qlm's within 23 s. In standby, they hold GLM's up to 210 s, and qlm's up to 88 s (`qlm-first-discover`, `qlm-standby-discover`). A run started sooner may lease a session that a monitor still holds. Then two monitors could take one monitor's frames.

So after a host stops, wait 1 minute when every monitor is on. Wait 4 minutes when any monitor is in standby. This doc says "wait between hosts" where it applies.

### Find the serials, and the setup file

1. In the Terminal you'll use for the session, go to your checkout of qlm. Set the setup file GLM uses. GLM 5 usually keeps it in `~/Documents/Genelec/GLM5/Setup Files/`.

   ```bash
   SETUP="$HOME/Documents/Genelec/GLM5/Setup Files/Main.sam"
   ```

   ```bash
   R=captures/qlm-apply-first/rew
   ```

2. Quit GLM, and wait between hosts.
3. Run `qlmctl discover --setup "$SETUP"`. Note each monitor's serial.
4. Set `OTHERS` to a piece of each serial but the Right 8351B's. Each piece must match one monitor.

   ```bash
   OTHERS="<Left 8351B>,<Rear Left 8330A>,<Rear Right 8330A>,<7370A>,<7350A>"
   ```

5. Run the dry run, and read it through:

   ```bash
   qlmctl apply-group "$SETUP" "Main 2x1" --volume -35 --ceiling -30 --dry-run
   ```

   It reads only the setup file and sends nothing. Its volume frames carry −35 dB. It shows every monitor unmuted. It ends by saying the apply runs only as the supervised test.
6. Relaunch GLM.

## The run, for Main 2x1

Main 2x1 comes first. It has the fewest monitors: the two 8351B and the 7370A. Stop REW's signal before every apply, every GLM launch, and every power switch. If anything sounds wrong, stop the signal, turn the knob down, or switch the monitor off at its power switch.

Start the Pi capture now, if you record.

### Step 1: GLM applies the group, and REW measures

1. In GLM, switch to Main 2x1. Check that no monitor is muted, that dim is off, and that GLM shows −35.0 dB.
2. **Set REW's level.** Start at −30 dBFS. Use the measure dialog's Check Levels, and raise the level in 6 dB steps until it reports a good level. Go no higher than −12 dBFS, REW's default, and no louder than you would listen. Write the level down.
3. **The routing check.** In REW's generator, play pink noise at −40 dBFS on the Left channel only. Walk to each monitor, and note which ones play. Do the same on the Right channel. Stop the noise.
4. Measure the Left channel: `glm-2x1-L`. Write down REW's System Delay, from its Info panel. Then measure the Right: `glm-2x1-R`, with its delay.
5. Measure both again, changing nothing: `glm-2x1-L-repeat` and `glm-2x1-R-repeat`. Export all four.
6. Check the setup is steady:

   ```bash
   python3 -I tools/compare-measurements.py --limit 0.1 "$R/glm-2x1-L.txt" "$R/glm-2x1-L-repeat.txt"
   ```

   ```bash
   python3 -I tools/compare-measurements.py --limit 0.1 "$R/glm-2x1-R.txt" "$R/glm-2x1-R-repeat.txt"
   ```

   Both must pass, and each repeat's System Delay should be within 0.01 ms. This also proves the tool reads your REW's export. If either fails, find the cause before you go on: noise, a draft, the cable, or someone moving.

### Step 2: GLM switches away, and quits

1. **In GLM, switch to Main 4x2.** It has a different crossover, other PEQ bands, and other monitors. So qlm's apply must change every setting back. Without this, an apply that left something out would still pass, on GLM's settings.
2. **One monitor first.** In GLM, mute every monitor but the Right 8351B.
3. Quit GLM. `qlmctl` refuses while GLM runs, with exit 69, and sends nothing. Listen: nothing should change. The adapter takes over at the knob's level.
4. Wait between hosts: 1 minute, since every monitor is on. Then run `qlmctl info`. The knob reads about −35 dB.

### Step 3: qlm applies the same group, and REW measures again

1. **One monitor first, at a low level.** With no signal playing, run:

   ```bash
   qlmctl apply-group "$SETUP" "Main 2x1" --volume -35 --ceiling -30 --unverified-rate --muted "$OTHERS" --seconds 120
   ```

   - `--muted` keeps muted what GLM muted. The Right 8351B plays alone. The Left and the 7370A stay muted. The 8330As and the 7350A leave the group, so they go to standby.
   - Once it prints `applied Main 2x1`, play pink noise at −50 dBFS on the Right channel. Then raise it to −40 dBFS.
   - Listen for a steady hiss, with no tone, distortion, or rattle. It should sound as it did in step 1's routing check.
   - Stop the noise. Let `qlmctl` run out, and read what it says at exit about the hand-back.
2. Wait between hosts: 4 minutes, since three monitors are in standby.
3. **The whole group.** With no signal playing, run the same apply with nothing muted, held for ten minutes:

   ```bash
   qlmctl apply-group "$SETUP" "Main 2x1" --volume -35 --ceiling -30 --unverified-rate --seconds 600
   ```

   Every monitor in the group now plays.
4. Repeat step 1's routing check. The same monitors must play each channel.
5. Measure the Left: `qlm-2x1-L`, and the Right: `qlm-2x1-R`. Write down each System Delay, and export both. If `qlmctl` exits during a sweep, discard that sweep, and start again from step 3.2.
6. Compare:

   ```bash
   python3 -I tools/compare-measurements.py "$R/glm-2x1-L.txt" "$R/qlm-2x1-L.txt"
   ```

   ```bash
   python3 -I tools/compare-measurements.py "$R/glm-2x1-R.txt" "$R/qlm-2x1-R.txt"
   ```

7. Let `qlmctl` run out.

### Step 4: GLM again, to check nothing moved

1. Wait for `qlmctl` to exit, then wait between hosts: 4 minutes. Relaunch GLM. It may open on Main 4x2, the group it used last, with your mutes.
2. Switch to Main 2x1. Unmute every monitor. Check that GLM shows −35.0 dB.
3. Measure the Left and the Right again: `glm-2x1-L-after` and `glm-2x1-R-after`, with each System Delay. Export both.
4. Compare each with GLM's first:

   ```bash
   python3 -I tools/compare-measurements.py --limit 0.1 "$R/glm-2x1-L.txt" "$R/glm-2x1-L-after.txt"
   ```

   ```bash
   python3 -I tools/compare-measurements.py --limit 0.1 "$R/glm-2x1-R.txt" "$R/glm-2x1-R-after.txt"
   ```

   If either fails, the setup moved during the session, and step 3's result is in doubt. Find out why, and run the group again.

### Step 5: qlm from a cold start

qlm leaves out two frames GLM sends to the 8351B: `43 00 02` and `4B 00 00 00 01` ([refused-frames.md](refused-frames.md)). GLM sends the same payloads in every group. So in step 3, the 8351B still held GLM's values, and the measurement could not tell whether they matter. A monitor switched on fresh holds whatever its flash has. This step measures qlm's apply on such monitors. It is also what the app will do: the apply at launch, on monitors just switched on.

1. Quit GLM. The power cycle next drops every lease, so there is no need to wait.
2. With no signal playing, switch every monitor off at its power switch. Wait 10 s. Switch them all on, and wait 60 s.
   - **TRAP: a monitor just switched on plays at its own stored level until a host sends one.** Play nothing until step 5.3's apply prints `applied`.
3. Run the apply at launch:

   ```bash
   qlmctl apply-group "$SETUP" "Main 2x1" --launch --volume -35 --ceiling -30 --unverified-rate --seconds 600
   ```

   If it refuses because a monitor is not leased yet, nothing was sent. Wait 30 s, and run it again.
4. Play pink noise at −50 dBFS on each channel in turn, and raise it to −40 dBFS, listening as in step 3.1. That is also the routing check.
   - The apply at launch changes no monitor's power. Those outside the group get their state as muted, as at GLM's launch, so they may stay lit. Expect that in the membership check.
5. Measure the Left and the Right: `qlm-2x1-L-cold` and `qlm-2x1-R-cold`, with each System Delay. Export both, and compare each with GLM's first:

   ```bash
   python3 -I tools/compare-measurements.py "$R/glm-2x1-L.txt" "$R/qlm-2x1-L-cold.txt"
   ```

   ```bash
   python3 -I tools/compare-measurements.py "$R/glm-2x1-R.txt" "$R/qlm-2x1-R-cold.txt"
   ```

6. Let `qlmctl` run out. Relaunch GLM.

A pass here, with step 3's, says that what qlm leaves out does not change the sound. A fail here, after step 3 passed, points at those two frames, or at other state the flash holds.

Stop the Pi capture, if you record.

## The other groups

Run steps 1 to 4 for every other group you use. In step 2, switch GLM to a group that differs from the one you measure:

| Measured | GLM switches to | Why |
| --- | --- | --- |
| Main 4x2 | Main 2x1 | Main 2x1 has a 60 Hz crossover, not 85 Hz, and three monitors fewer. |
| Main 2x2 | Main 2x1 | The crossover differs, and so does the 7350A's membership. |

In Main 4x2, each rear 8330A plays the same channel as the 8351B in front of it, so each channel's measurement holds both. The routing check shows which subwoofers play each channel.

Run step 3.1, one monitor first, for each group too. Leave the Right 8351B unmuted, and `$OTHERS` muted, as before. Wait between hosts each time: when GLM's last group was Main 2x1, three monitors are in standby.

## Besides the frames: the level, the delay, and the routing

The golden tests check qlm's apply against GLM's captured applies: the slots, level words, delays, and routing, and the coefficients within 1e-6. Three things decide the sound beyond those frames. Each needs a check on the monitors.

### The level

These must match:

- **The monitors' volume.** With the knob in, GLM's volume is the knob's position. qlm's is `--volume`. Both send the same word for the same dB (`volume-sweep`).
  - Check that GLM shows −35.0 dB before steps 1 and 4.
  - Check that `qlmctl info` reads the knob at about −35 dB in step 2.
  - Check that every `apply-group` has `--volume -35`.
- **Each monitor's level word,** from its `Level_Sensitivity` and `Group_Sensitivity` in the setup. The dry run matches GLM's, so this needs only the setup file unchanged.
- **Mute and dim.** No monitor is muted, and dim is off, in every measurement. Check GLM's window before steps 1 and 4.
- **The signal.** REW's level and output device, the Mac's output volume, and the interface's settings stay as they are.
- **The mic.** Its gain, and REW's input device, stay as they are.

A quick check before each measurement: play pink noise at −40 dBFS, and read REW's SPL meter, C-weighted and slow. It needs no calibration for this. The reading after qlm's apply should be within 0.1 dB of the one after GLM's.

A level mismatch shows in the tool's output as a large mean difference, with a small difference from the mean. If only one monitor's level differs, only its channel shows it. A subwoofer's shows near the crossover.

### The delay

Each monitor's delay goes out in its block as `10 02`, in 48 kHz samples. It comes from `Time-of-flight_Compensation` in the setup. A subwoofer's comes from its phase at the crossover.

A delay changes no single monitor's response. It changes how monitors sum: a main and a subwoofer near the crossover, at 60 Hz in Main 2x1 and 85 Hz in the others. In Main 4x2 it also changes how the front and rear monitors on one channel sum. So a delay error shows in the comparison near the crossover, or as ripple in Main 4x2. The magnitude alone cannot always tell it from a level error, so check the delay directly too:

- **System Delay.** REW reports it in the Info panel for each measurement with a timing reference. It comes from the impulse's peak. Compare each qlm measurement's with GLM's for the same channel. They must agree within 0.02 ms.
- **Which delay it checks.** With the loopback, each channel's delay is absolute. With the acoustic reference on the Left, the Right's System Delay is the Right's arrival less the Left's. So it checks both 8351B's delays against each other. The Left's reads about 0 either way.
- **The subwoofers.** REW times a subwoofer less precisely, from the start of its impulse. The comparison near the crossover covers them.

0.02 ms is 7 mm of sound. A mic moved that far moves every delay, so a fail here with step 4 also failing means the mic moved.

### The routing

Routing is which input and AES channel each monitor plays: its `40` frames, from `Input` and `Input1_AES_EBUChannel` in the setup. It also covers the group's membership: which monitors are on, and which are in standby (`3A 03`), and their mute state (`2B`).

- **Check it by ear.** Do the routing check after each apply, as in step 1.3: pink noise at −40 dBFS, on one channel at a time. Note which monitors play. The list after qlm's apply must equal the one after GLM's.
- **Check membership by sight.** Note which monitors are on and which are in standby, from their lights. Compare with GLM's. Step 5 may differ, as it says.
- **What a mistake looks like.** A routing mistake is gross. A monitor plays the wrong channel, or none, and the comparison differs by several dB. It is never a fraction of a dB.

## Reading a failure

| What the tool shows | Likely cause |
| --- | --- |
| The same offset everywhere: the mean difference is large, but the difference from the mean is small | The volume, or the signal. Check the knob, `--volume`, and REW's level. |
| An offset on one channel only | That channel's monitor: its level word, or its routing. |
| A difference only near the crossover | A subwoofer's block, a delay, or the crossover (`3B`). Check the System Delays. |
| A PEQ band's shape, at the wrong frequency | A band designed at the wrong rate. The dry run rules this out for the frames GLM sends, so look for a setup file that differs from GLM's. |
| Small differences scattered across the band, worst at the edges | Noise, or something moved. Steps 1.6 and 4.4 show which. |
| A pass in step 3, and a fail in step 5 | The frames qlm leaves out, or other state in the monitors' flash. |

`--table` prints every compared frequency, for a closer look. Look at the unsmoothed measurements in REW too.

## What the measurement cannot see

- **The phase.** The tool compares the magnitude only. The System Delay covers the timing.
- **Anything off the mic's position.** One position cannot see a change that cancels there. A PEQ band left out would show at any position, so one is enough for this test.
- **What qlm leaves out, when GLM's values persist.** Steps 3 and 4 run on monitors GLM configured. Only step 5 sees past that, and only against what the monitors' flash holds today.

## Afterwards

1. Relaunch GLM, if it is not running. It applies its group at launch.
2. Write `captures/qlm-apply-first/notes.md`, as the control run did:
   - each step's time, and the exact commands;
   - GLM's volume, the knob's reading, and REW's level;
   - each measurement's System Delay;
   - each routing check's list;
   - the tool's output for every pair;
   - anything you heard.
3. The REW text exports are already in `captures/qlm-apply-first/rew/`. Keep REW's own `.mdat` files out of the repository. A header may name the mic's serial: remove it.
4. If you recorded, convert the capture as [captures/README.md](../captures/README.md) says.
5. Record the result in [plan.md](plan.md): pass or fail, per group and channel, and what step 5 showed.
