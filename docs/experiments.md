# Experiments for the open questions

[protocol.md](protocol.md#open-questions) lists the protocol's open questions in a table. This is the script for one supervised session that settles as many of them as a person at the desk can, safely. It follows the first control run's script in [plan.md](plan.md#the-first-control-run). You listen and approve each step. One session drives `qlmctl` and the Pi, and keeps the notes.

Each part names its question and says why qlm cares. Then it gives the setup, the steps, what to listen for, what to look for in the capture, what each result would mean, and when to stop. [What this session can't settle](#what-this-session-cant-settle) covers the questions no safe experiment reaches.

A question's number, such as Q3, is its row in protocol.md's table as this doc was written. Each part quotes its question too, in case the table changes.

## The run order

Parts A to F run through the Pi as one capture, `qlm-experiments`. Part G is GLM's, in a capture of its own. Part H runs with no capture, because the Pi can't show what it tests.

| Step | What runs | For | Time |
| --- | --- | --- | --- |
| Before | Build, REW, the copy of the setup, and the Pi | | 20 min, beforehand |
| A1 | GLM on Main 4x2, five monitors muted, the knob at −60 dB, music | Setup | 3 min |
| A2 | The Pi starts `qlm-experiments` | Setup | 1 min |
| A3 | GLM quits, then a minute's wait | Setup | 1.5 min |
| A4 | `info`, `discover`, and the variables | Setup | 2 min |
| A5 | `volume -50`: the hand-back at the knob | plan.md's Next | 2 min |
| A6 | `volume -70`: the louder case | plan.md's Next | 2 min |
| B1 | `poll`, with a turn of the knob | Q3 | 2 min |
| B2 | `volume -50 --adapter-poll 0` | Q3, Q5 | 1.5 min |
| B3 | `--adapter-poll 0.57`, only if B2 dipped | Q3 | 1 min |
| B4 | `--adapter-poll` from 2 to 3.2 s, only if B2 dipped | Q3 | 4 min |
| C1 | Calibrate the meter at two knob levels | Q4 | 4 min |
| C2 | Unplug the knob during `poll` | Q4 | 2 min |
| C3 | The staircase | Q4, Q17 | 3 min |
| C4 | `volume -50` with no knob, then the staircase again, only if C3 read −60 dB | Q4 | 4 min |
| C5 | Plug the knob back in during `poll` | Q4 | 3 min |
| D1 to D4 | Four lease gaps: 1, 4, 7, and 10 s | Q5 | 5 min |
| D5 | An unplug of the adapter, only if the leases outlast 4 s | Q5 | 4 min |
| E1 | `mute on` | Q10 | 2 min |
| E2 | `mute off --serial "$RIGHT"` | Q10 | 2 min |
| E3 | `mute off` | Q10 | 1.5 min |
| F1 | `mute on --serial "$LEFT"` | Q14 | 1 min |
| F2 | `sleep` | Q14 | 1 min |
| F3 | A lease gap in standby, optional | Q5 | 2 min |
| F4 | `wake --volume -50` | Q14 | 1.5 min |
| F5 | `mute off --serial "$LEFT"` | Q14 | 1 min |
| G1 to G4 | GLM switches to the analog group and back, captured | Q9 | 7 min |
| G5 | Changed fields, optional | Q8 | 3 min a field |
| G6, G7 | GLM back on Main.sam, and qlm's dry run of the copy | Q9 | 2 min |
| H1 to H3 | The adapter on the Mac, the reset, and the calibration | Q16 | 7 min |
| H4, H5 | The Mac sleeps and wakes, then the staircase | Q16 | 8 min |
| H6 | `poll` across a sleep, optional | Q16 | 3 min |
| H7 | The adapter back in place, and GLM relaunched | | 2 min |

The session takes about 70 minutes at the desk without the optional and conditional steps, and about 95 with all of them. The times include the 30 s between `qlmctl` runs.

## Rules for the whole session

These come from AGENTS.md's Safety rules and the two control runs.

- The levels stay low. The knob sits at −60 dB, and qlm's levels are −50 or −70 dB, under a −35 dB ceiling. So a take-over moves the level by 10 dB at most, and nothing in Parts A to F plays above −50 dB.
- One monitor plays first. Through Part D, the Right 8351B plays alone. The other five stay on, muted in GLM, and every `volume` names them with `--muted`. Part E unmutes all six on purpose, at the knob's −60 dB.
- GLM is quit before every `qlmctl` command. `qlmctl` refuses while GLM runs, with exit 69, and sends nothing. GLM runs only in step A1, in Part G, and at the end.
- Nothing qlm refuses goes out. `qlmctl` can't send it: GLMProtocol's allowlist refuses `05`, `15`, `3A 01`, `3A 02`, `3A 06`, `43`, `4B`, and `22` and `51` to the adapter. No step runs `apply-group` over USB. In Part G, GLM sends its own frames, `05 04` among them, as it does at every launch.
- The knob is at or below qlm's level before every exit, except in A6, which tests the other case on purpose. Then qlm sends the knob's level as it stops, and the adapter's take-over changes nothing (#32). Where a step has no knob in, the signal is off at the exit instead.
- Ctrl-C stops `qlmctl` without that hand-back. The adapter then takes over at the knob about 2.6 s later. That's one more reason the knob stays low.
- Leave 30 s between one `qlmctl`'s exit and the next, except in Part D, which shortens the gap on purpose. A monitor that still holds the last run's lease hides from the probe, and the next run may give its session to another monitor (protocol.md's TRAP). In both control runs, `dim off` started about 10 s after `dim on` stopped, and found every monitor, so 30 s leaves a margin. `info` leases nothing, so another command may follow it at once.
- If a command lists fewer monitors than you expect, stop. Wait a minute, and run it again.
- After each run, play the Tink, as the control runs did, so you can time the hand-back: `afplay /System/Library/Sounds/Tink.aiff`.
- To set a known level at any point, with the knob in, run the reset: `qlmctl volume -60 --ceiling -35 --muted "$OTHERS" --seconds 5`. Once it exits, the level is the knob's, whether qlm's stop sends it or the take-over does.

Stop at once on anything unexpected: a level above what the step says, a click or a thump, or a monitor that changes state on its own. Stop the signal, turn the knob down, or switch the monitor off at its power switch.

> **Warning:** a monitor switched back on plays at its own stored level until a host sends one. Keep the signal off until the reset, or GLM, has sent it a level.

## Before the session

Do these before you sit down. They take about 20 minutes.

1. Build `qlmctl` from main with `make cli`. Run `qlmctl help`, and fix any command here that differs.
2. Part B needs a flag `qlmctl` doesn't have yet, `--adapter-poll` ([The flag](#the-flag)). If `qlmctl help` doesn't list it, skip B2 to B4.
3. Open REW, with its signal generator set to pink noise. Parts B, C, and H use it. Any player of steady pink noise at a level set in dBFS will do.
4. For Part G, make the copy of the setup, as [Part G](#part-g-glms-analog-routing-frame) says.
5. On the Pi, check that `qlm-proxy` is running, and that `vcgencmd get_throttled` reads `0x0`.
6. Quit Spotify, and anything else that opens USB devices. In `qlm-standby-discover`, Spotify's USB client on the adapter made `qlmctl` refuse.
7. In the Terminal you'll use, go to your checkout of qlm, and set the setup file and its copy:

   ```bash
   SETUP="$HOME/Documents/Genelec/GLM5/Setup Files/Main.sam"
   ```

   ```bash
   COPY="$HOME/Documents/Genelec/GLM5/Setup Files/Main analog.sam"
   ```

Three things about `qlmctl` today matter here:

- `poll` and `discover` ignore an option they don't know, so a typo there runs with the defaults. The controls refuse one, and send nothing.
- The dry run of `mute off --serial` with `--muted` prints "would send nothing". The record `--muted` makes is published before the mute, and the dry run stops reading there. The script never uses that pair.
- `qlmctl help` says that `wake` without `--volume` sends no level. Since #29, it sends the knob's. The script always gives `--volume`.

## Part A: start, and the hand-back

Part A sets the session up. It also checks #32's hand-back on the monitors, since every later exit relies on it, and so far it has run only on the fake bus. That's item 2 of plan.md's Next.

1. A1, GLM. Open GLM on Main.sam, and switch to Main 4x2, so all six monitors are on. Mute every monitor but the Right 8351B. Turn the knob until GLM shows −60.0 dB. Play music quietly from the Mac. Only the Right plays.
2. A2, the capture. On the Pi, start it. It runs through Part F.

   ```bash
   sudo ./pi/capture.sh qlm-experiments
   ```

3. A3, GLM quits. Quit GLM. Listen: nothing should change, since the adapter takes over at the knob's −60 dB. Wait a minute for GLM's leases to lapse.
4. A4, the variables. Read the adapter and the monitors:

   ```bash
   qlmctl info
   ```

   ```bash
   qlmctl discover --setup "$SETUP"
   ```

   `info` reads the knob at about −60 dB. `discover` lists all six, on. Set these from its serials. Each piece must match one monitor.

   ```bash
   RIGHT="<Right 8351B>"
   LEFT="<Left 8351B>"
   OTHERS="<Left 8351B>,<Rear Left 8330A>,<Rear Right 8330A>,<7370A>,<7350A>"
   ```

5. A5, the hand-back at the knob. First the dry run, then the run:

   ```bash
   qlmctl volume -50 --ceiling -35 --muted "$OTHERS" --dry-run
   ```

   ```bash
   qlmctl volume -50 --ceiling -35 --muted "$OTHERS" --seconds 15; afplay /System/Library/Sounds/Tink.aiff
   ```

   The dry run prints one volume frame, `FF 1F 00 67 9F`, GLM's −50 dB, and says that qlm sends the knob's level as it stops. The run raises the Right 10 dB. At the exit, `qlmctl` prints that it sent the knob's −60 dB as it stopped. Listen: the level falls back with the Tink, and nothing changes 2 to 3 s later.
6. A6, the louder case:

   ```bash
   qlmctl volume -70 --ceiling -35 --muted "$OTHERS" --seconds 15; afplay /System/Library/Sounds/Tink.aiff
   ```

   The Right falls 10 dB. At the exit, `qlmctl` warns that the adapter takes over at the knob's −60 dB, louder than qlm's −70 dB, and says to turn the knob down. Leave it where it is. Listen: the level rises 2 to 3 s after the Tink, as in both control runs. That rise is what a take-over sounds like at these levels, and Part B listens for it.

In the capture, A5's last frame before its exit is a volume frame with the knob's word. For a reading of −60.0 dB, that's `00 20 C4`, GLM's −60 dB.

| At A5's exit you hear | It means |
| --- | --- |
| The drop with the Tink, then nothing | The hand-back works on the monitors. A stop with the knob at or below qlm's level changes nothing after it. |
| The drop 2 to 3 s after the Tink | qlm's last frame didn't go out, or didn't carry the knob's level. Read the capture's last `FF 1F` before the exit. Stop the session and fix it first, since every later part relies on it. |

Stop on the general rule.

## Part B: the adapter's host timeout

> Q3. What is the adapter's host timeout, and what resets it: any report, or only `01 08`? Does one poll a cycle hold it as well as GLM's pairs?

qlm polls the adapter as GLM does, with a pair of `01 08` every 107 ms. The poll is the knob's only path to the host. It's also likely how the adapter knows a host is there, but no one has tested that. Two things hang on the answer. If any frame holds the adapter, System could poll it less often, and halve that traffic with single polls. If only `01 08` holds it, any 2.6 s without one hands the bus to the adapter while qlm runs, at the knob's level, which qlm's ceiling doesn't bound. System's adapter polls wait in line behind an apply's frames, so the margin matters. GLM's longest gap between polls is 1.70 s, in a group switch.

B1 also settles an open item in adapter-status.md: whether the adapter acts on the knob while a host is present.

The setup is what Part A left, with one change. Swap the music for REW's pink noise at −30 dBFS, on the Right channel. A steady signal makes a short dip easy to hear. Part C keeps it.

### The flag

`qlmctl` can't vary its polling today. System has the setting, `adapterPollInterval`, but `qlmctl` doesn't expose it, and System always sends a pair, since `QLMAdapterPollsPerRound` is fixed at 2. B2 to B4 need one small flag:

- `--adapter-poll SECONDS`, on `volume` only. qlm polls the adapter with one `01 08` every SECONDS, in place of GLM's pair every 0.107 s. `0` polls it only at start. The rest of the cycle stays: the probe, the volume, and a poll to each monitor.
- It needs the polls per round as a setting, beside `adapterPollInterval`, and the option in `QLMControlOptions`.
- At start, `qlmctl` prints the cadence it runs, so the notes can't get it wrong.
- With a long interval, qlm reads the knob late, and with `0` only at start. Its hand-back then uses that old reading, so nobody touches the knob during these runs.

It goes on `volume` alone because `volume` refuses an option it doesn't know, and sends nothing. So a build without the flag fails safe: today's `qlmctl` answers `unknown argument '--adapter-poll'`, with exit 64. `poll` would ignore the flag, and run GLM's pairs while the notes said otherwise.

### The steps

1. B1, the knob while a host polls. It needs no flag.

   ```bash
   qlmctl poll --seconds 30; afplay /System/Library/Sounds/Tink.aiff
   ```

   About 10 s in, turn the knob down to about −70 dB. `poll` prints the new reading. Listen through the exit and for 10 s after. Then turn the knob back to −60 dB, and check it with `qlmctl info`.
2. B2, the cycle with no adapter polls:

   ```bash
   qlmctl volume -50 --ceiling -35 --muted "$OTHERS" --seconds 30 --adapter-poll 0; afplay /System/Library/Sounds/Tink.aiff
   ```

   The level rises to −50 dB at the start. Listen closely for the first 5 s, then to the end. A take-over would bring a dip toward the knob's −60 dB, once, or again and again as qlm's cycle sends −50 dB back. At the exit, qlm sends the knob's −60 dB.
3. B3, only if B2 dipped. One poll a cycle:

   ```bash
   qlmctl volume -50 --ceiling -35 --muted "$OTHERS" --seconds 20 --adapter-poll 0.57; afplay /System/Library/Sounds/Tink.aiff
   ```

4. B4, only if B2 dipped. The same command with `--adapter-poll 2`, then `2.4`, `2.8`, and `3.2`. Stop at the first interval that dips.

In B1, listen for whether the level follows the knob before the exit. In B2 to B4, listen for any dip below −50 dB during the hold.

In the capture:

- B1: the knob's `DF` in each `01 08` reply, which dates the turn.
- B2 to B4: the `01 08` cadence the flag set. Note any sync, `01 39` or `01 08` after a timeout, first. A sync is an adapter query too.
- After a dip, do the monitors' polls get `01 7E`, and does qlm lease them again? That tests protocol.md's guess that the take-over ends the leases, for Q5.
- The first `01 08` reply after each long gap: the same shape as the others, or not.

| Result | It means | For qlm |
| --- | --- | --- |
| B1: the level follows the turn | The adapter applies the knob while a host polls, at least one that sets no level | qlm can't assume the adapter stays quiet while it runs. Part C unplugs the knob with the signal off either way. |
| B1: the level moves only 2 to 3 s after the exit | The adapter defers to any host, even one that sends no level, as adapter-status.md guessed | Nothing changes |
| B2: steady at −50 dB | Some frame of the cycle holds the adapter: the probe, the volume, or the monitors' polls | System may poll the adapter less often. B3 and B4 aren't needed. |
| B2: a dip | Only the adapter's own polls hold it | System must never let `01 08` lapse for 2.6 s, in an apply or out of one |
| B3: steady | One poll a cycle holds it | System can send single polls, and halve the adapter's traffic |
| B4: the first dip at an interval T | The timeout lies between T and the interval before it | That's System's budget for its longest gap between polls |

Stop the noise and press Ctrl-C if the level rises above −50 dB, if it keeps changing after the exit, or if a monitor drops out and doesn't come back. The knob is at −60 dB, so a take-over can only make it quieter.

## Part C: the level with no knob in

> Q4. What level does the adapter apply with no knob in?

With the knob in, qlm's stop sends the knob's level, so the take-over changes nothing. With no knob, qlm can't know what the adapter will apply, so `qlmctl` and the app only warn (#30, which went in with #32). A user without the knob meets that at every quit and every sleep. If the adapter keeps the last level a host sent, qlm needs no warning. If it applies a stored level, qlm must say which, and the app should warn before a stop that would be louder.

The level is unknown, so the signal is off whenever the adapter takes over with no knob. Then a `poll` reads the Right's output meter while the noise comes back from far below, in 10 dB steps. `poll` sends no level, and while it runs the adapter keeps what it applied. The meter gives the level, and the noise never plays louder than in the calibration. The steps rest on [telemetry.md](telemetry.md#a-count-is-about-a-db): an output meter moves about a count a dB, and settles within about 2.3 s. `poll` prints the Right's HF output meter as `hf`, in decimal, with its floor at 128.

The setup: REW's pink noise on the Right channel. The knob at −60 dB. No `qlmctl` running, so the adapter applies the knob.

1. C1, the calibration. With the noise at −30 dBFS:

   ```bash
   qlmctl info
   ```

   ```bash
   qlmctl poll --seconds 10
   ```

   Note the knob's reading, K1, and the Right's `hf` on `poll`'s last lines, H1. Turn the knob down about 10 dB. The adapter follows at once. Run both commands again, and note K2 and H2. Turn the knob back to −60 dB. The meter's counts per dB are c = (H1 − H2) / (K1 − K2), which should be close to 1.
2. C2, the unplug. Stop the noise.

   ```bash
   qlmctl poll --seconds 40
   ```

   Once `poll` has printed the monitors, pull the knob's plug out of the adapter. `poll` prints `no knob`. Don't turn the knob while it's out. Let `poll` run out. About 2.6 s later, the adapter takes over with no knob. Wait 10 s.
3. C3, the staircase. Keep the noise off, then start it once `poll` runs.

   ```bash
   qlmctl poll --seconds 120
   ```

   Start the noise at −90 dBFS, and raise it 10 dB about every 15 s, toward −30 dBFS. At each step, note the noise level, S, and the Right's `hf`. Stop raising at once when `hf` comes within 5 of H1, or when anyone hears it louder than in C1. Stop the noise when `poll` ends. Take a step where `hf` reads at least 20 above the floor, and work out the level:

   ```text
   X = K1 + (hf − H1) / c − (S + 30)
   ```

   The first step is safe whatever X is. 0 dB is the highest level there is, and at −90 dBFS even 0 dB plays no louder than C1. The meter checks each step before the next.

   The steps also give the input meter's slope. `in` reads before the volume, so how far it moves at each 10 dB step is the slope telemetry.md left open, for Q17.
4. C4, only if X came out near −60 dB. That fits the knob's last reading, and also the last level a host sent, since every exit in Part B sent the knob's. So tell them apart. With the noise off:

   ```bash
   qlmctl volume -50 --ceiling -35 --muted "$OTHERS" --seconds 15; afplay /System/Library/Sounds/Tink.aiff
   ```

   `qlmctl` warns that the level after the take-over is unknown, since no knob is in. Wait 10 s after the exit, then run C3 again, for X′.
5. C5, the knob back in. Keep the noise off.

   ```bash
   qlmctl poll --seconds 30
   ```

   Plug the knob in. `poll` prints its reading. If it doesn't read about −60 dB, turn it there while `poll` runs. The noise is off, so it doesn't matter whether the adapter acts on the turn. About 2.6 s after `poll` ends, the adapter takes over at the knob. Check with `qlmctl info`, then play the noise or the music again.

In the capture:

- C2: the knob's readings as the plug comes out, then `30 36 DF` giving way to `31`, as in `volume-sweep` at 25.11 to 25.44 s.
- C3: the Right's `43` at each step against C1's, and its `42` against the noise level.
- C5: the readings as the plug goes in. No capture has that moment yet.

| Result | It means | For qlm |
| --- | --- | --- |
| X near −60 dB, then X′ near −50 dB | With no knob, the level stays where the last host left it | A stop with no knob changes nothing, so qlm can drop the warning |
| X and X′ both near −60 dB | The adapter keeps the knob's last reading | qlm can't read it once the knob is gone. Keep the warning, and give the level if qlm kept the last reading. |
| X at another level | The adapter applies a stored level. −56.5 dB would be Main.sam's startup level. | qlm warns with that level, and the app warns before any stop that would be louder |
| No signal at any step | It mutes, or goes to the bottom | A stop with no knob silences the system, and qlm says so |

The staircase is its own stop rule: no step plays louder than C1. If `hf` jumps past H1 at any step, stop the noise, and go to C5 with it off. With no knob, every exit comes back to X, so only the knob, back in, gets you out of a loud X.

## Part D: when the leases drop

> Q5. Why do monitors drop a quiet host's leases, and why within 9 s across an unplug?

A host finds only monitors without a lease. A host that starts too soon after another can give one monitor's session to a second, and then two monitors take one monitor's frames. Since #32, a System that starts again asks each monitor it knew for its serial at its old session, and takes the lease back. The app's System does that after a sleep. But each `qlmctl` command is a new System, which knows no monitor. So today's wait between hosts rests on wide bounds: a minute with every monitor on, and 4 with any in standby, from bounds of 23 to 210 s. protocol.md guesses that the take-over, about 2.6 s after the host goes quiet, ends the leases. The control runs hint at a bound under 10 s, as the rules above say.

The setup is what Part C left: all six on, five muted. The noise or the music may play, since `poll` and `discover` send no level and no mute.

> **Warning:** these trials break the wait between hosts on purpose. A trial's `discover` may lease a session that a monitor still holds. Only `poll` and `discover` run here, so a shared session costs garbled replies, not a level. Wait 30 s after each trial, and a minute after the last one before Part E.

1. D1 to D4, four gaps. Run each as one line, so the shell sets the gap:

   ```bash
   qlmctl poll --seconds 10; sleep 1; qlmctl discover --seconds 3
   ```

   ```bash
   qlmctl poll --seconds 10; sleep 4; qlmctl discover --seconds 3
   ```

   ```bash
   qlmctl poll --seconds 10; sleep 7; qlmctl discover --seconds 3
   ```

   ```bash
   qlmctl poll --seconds 10; sleep 10; qlmctl discover --seconds 3
   ```

   `discover` lists the monitors that answered its probe. Those had dropped `poll`'s lease. With none, it says that no monitor answered.
2. D5, only if the leases outlast 4 s. The unplug. Stop the signal first. The adapter boots alone, and hlm saw it ramp up at boot to a stored level we don't know.

   ```bash
   qlmctl poll --seconds 10
   ```

   As soon as it exits, unplug the adapter from the Pi, and plug it back into the same port 3 s later. Once `ioreg -p IOUSB -w0 | grep "Gnet Adapter"` shows it, run `qlmctl discover --seconds 3`. Compare it with the trial nearest that gap. Wait 30 s, and run the reset before any signal.

In the capture, read each trial's gap from `poll`'s last report to `discover`'s first probe, to the millisecond, and which hardware IDs answered. After D5, the capture holds two device numbers for the adapter. Convert it with `--device` for each, as for `unplug`.

| The first gap at which monitors answer | It means | For qlm |
| --- | --- | --- |
| Between 1 and 4 s | The take-over ends the leases, as protocol.md guessed. Across an unplug, the adapter's restart and take-over would end them too. | The wait between hosts can be a few seconds. Taking a lease back by serial helps only after a gap shorter than about 2.6 s. |
| Between 4 and 10 s | The monitors drop a quiet host's leases on their own clock, not at the take-over | Wait just past that bound |
| Earlier for some models | Each model has its own timeout | Wait for the slowest |
| None by 10 s | The leases last longer than the control runs suggest | Keep measurement.md's waits for the rest of the session, and run D5 |
| D5: answers where the trials found none | The adapter's restart ends the leases | That explains the 9 s across an unplug |

Nothing here sends a level, so stop if anyone hears the level change at all.

## Part E: mute all, and the hand-back

> Q10. What does the adapter do with `01 2B 01`, and does it keep a mute of its own through the hand-back?

qlm's mute all sends `01 2B 01`, as GLM's does (#27). GLM opens every connection with `01 2B 00`, and qlm doesn't. If the adapter keeps a mute of its own and applies it when it takes over, a user who mutes all and quits stays muted, and the next host must clear it. refused-frames.md suggests that qlm send `01 2B 00` at connect for that case. A monitor's own mute already outlasts qlm (`qlm-control-first`, 648.7 s). So the test has to tell the two apart: it unmutes the monitors, and leaves the adapter's mute set.

The setup: all six on, five muted, the knob at −60 dB, and quiet music. No volume is set in this part, so the monitors stay at the knob's level throughout.

1. E1, mute all:

   ```bash
   qlmctl mute on --dry-run
   ```

   ```bash
   qlmctl mute on --seconds 10; afplay /System/Library/Sounds/Tink.aiff
   ```

   The dry run prints `01 2B 01` to the adapter, then two rounds of `2B 03` to all six, and no level. The run silences the Right. Watch the adapter and the knob for any light that changes. Listen for 15 s after the Tink.
2. E2, unmute the monitors but not the adapter:

   ```bash
   qlmctl mute off --serial "$RIGHT" --dry-run
   ```

   ```bash
   qlmctl mute off --serial "$RIGHT" --seconds 10; afplay /System/Library/Sounds/Tink.aiff
   ```

   The dry run prints two rounds of `2B 04` to all six, and nothing to the adapter. All six play again, at the knob's −60 dB. That's on purpose. A round restates every monitor, and without `--muted` the dry run shows exactly what goes out. Listen for 15 s after the Tink.
3. E3, clear the adapter's mute:

   ```bash
   qlmctl mute off --seconds 5; afplay /System/Library/Sounds/Tink.aiff
   ```

   It sends `01 2B 00`, then two rounds of `2B 04`. Listen after the Tink.

In the capture, check the `01 09` ack to `01 2B 01`, and the adapter's `01 08` reply before and after it, which `mute-dim` says doesn't change. Check that E2 sent no `01 2B`.

| After E1's exit | After E2's exit | It means | For qlm |
| --- | --- | --- | --- |
| Silent | Plays on | The adapter's mute doesn't act at the take-over. What outlasts qlm is each monitor's own mute. | Nothing changes |
| Silent | Silent 2 to 3 s after the Tink | The adapter keeps a mute of its own, and applies it when it takes over | Send `01 2B 00` at connect, as GLM does. A stop while muted all leaves the system muted, and the app should say so. |
| Sound 2 to 3 s after the Tink | Not needed | The take-over unmutes the monitors | A mute all doesn't outlast qlm, and the app's mute record mustn't claim it does |

If E2 went silent, E3's exit should leave everything playing, which shows that `01 2B 00` clears it.

Stop if anything plays louder than the knob's −60 dB.

## Part F: a mute through standby and a wake

> Q14. Does a woken monitor stay muted until a host sends its state?

`qlm-control-all` answered half of it. After its second wake, with no `2B` sent, the unmuted monitors played again 3.4 to 4.0 s after the first wake pair. What's left is a monitor muted before the standby. System sends a muted monitor its state after its first poll that says on, 1.5 to 1.7 s after the first pair. If a wake clears a mute, that leaves about 2 s before the monitor plays, and System should send the state with the level, at the lease's ack. If the monitor keeps its mute, the state is only a restatement, and a monitor muted outside qlm's record stays muted after qlm's wake.

The setup: all six on and unmuted, as Part E left them, with music.

1. F1, the Left muted:

   ```bash
   qlmctl mute on --serial "$LEFT" --seconds 5; afplay /System/Library/Sounds/Tink.aiff
   ```

   The Left goes silent. The rounds restate the other five as unmuted, so they play.
2. F2, standby. Run `qlmctl sleep`. All six go to standby, and the music stops.
3. F3, optional, for Q5 in standby. One lease gap, at the first gap where Part D found answers. With 4 s, that's:

   ```bash
   qlmctl poll --seconds 10; sleep 4; qlmctl discover --seconds 3
   ```

   Monitors in standby answer without a wake. Wait a minute after it.
4. F4, the wake:

   ```bash
   qlmctl wake --volume -50 --ceiling -35 --dry-run
   ```

   ```bash
   qlmctl wake --volume -50 --ceiling -35 --seconds 30; afplay /System/Library/Sounds/Tink.aiff
   ```

   No `--muted`, so qlm's record is empty, and it sends no `2B` after the wake. Stand between the two 8351B, and note when each comes back, if it does. At the exit, the level falls 10 dB to the knob's.
5. F5, the Left back. Run `qlmctl mute off --serial "$LEFT" --seconds 5`, and every monitor plays.

In the capture, check that no `2B` went out between F4's first wake pair and its exit. Then read each monitor's first telemetry that says on, and the Left's output meters against the Right's after the wake.

| The Right | The Left | It means | For qlm |
| --- | --- | --- | --- |
| Back within about 4 s | Silent until F5 | A monitor keeps its mute through standby and a wake | System's state after a wake only restates it. A mute set in GLM outlasts qlm's wake, so `--muted` matters. |
| Back | Back | A wake clears a mute | System must send a muted monitor its state before it plays: with the level, at the ack |
| Silent | Silent, until F5's rounds | A woken monitor stays silent until a host sends `2B`, as telemetry.md guessed from `qlm-control-first` | That contradicts `qlm-control-all`. If the capture confirms no `2B` went out, every wake must send rounds. |

Stop on a level above −50 dB, a click as the monitors wake, or fewer than six monitors listed after the wake.

## Part G: GLM's analog routing frame

> Q9. What is the analog routing frame, for input 4?
>
> Q8, in part. What do `3C`, `3E`, `42`, `43`, `4B`, `40 01 02 00 00`, and `10 01 09` carry?

qlm builds the routing frame for input 4 from one observed variant, `40 00 01 02 00`, where the AES3 inputs send `40 00 02 00` and the channel. Its DSP block warns that the frame is unverified. No group in Main.sam uses input 4, so no capture shows GLM's. A capture of GLM routing a group to the analog input pins it, and a golden test can then check qlm's. For Q8, GLM sends the same payloads in every capture. Change a field one of them might carry, capture GLM's apply, and see which frame moves.

GLM sends every frame in this part, and qlm sends none. qlm's only part is a dry run that reads the copy.

Make the copy before the session. In GLM, save Main.sam under a new name, `Main analog.sam`, so Main.sam stays as it is. In the copy, change the setup's fourth group, `Group_4`, which isn't one of the three groups the captures switch between. Set the Right 8351B and the 7350A to the analog input, and leave the other four on AES3. Leave the 7370A alone: it feeds every monitor, as `qlm-control-first`'s notes say. The setup file stores a monitor's input per group, as each node's `Input`. Its header also holds `InputMode: 2`, which may be system-wide. If GLM changes it along with the group, note that. If GLM can't change a group's input without calibrating again, skip Part G: a calibration runs GLM's own sweeps, which have no place in this session.

Check the copy with `qlmctl setup "$COPY"`, which reads only the file. It should show Group_4's Right 8351B and 7350A at `input 4`, and every other node as before.

**Never commit the copy.** It's a raw setup file. If a test needs it, `tools/redact-setup.py` makes a fixture from it.

1. G1, the capture. On the Pi, stop `qlm-experiments` with Ctrl-C, and start GLM's:

   ```bash
   sudo ./pi/capture.sh group-switch-main-4x2-group-4-analog
   ```

2. G2, GLM on the copy. Open GLM with the copy. Its launch applies its active group, and opens at −56.5 dB, the setup's startup level. In GLM, switch to Main 4x2 if it isn't there.
3. G3, the analog group. Switch to Group_4, and wait 15 s. The Right and the 7350A now play the analog input, which is silent unless something is plugged into it. The other four play the music. If you have a quiet analog source, connect it to the Right's analog input at a low level before the switch, and listen for it.
4. G4, back to AES3. Switch back to Main 4x2. The music returns on all six.
5. G5, optional, for Q8. In GLM, change one field of Group_4, if GLM shows it: a subwoofer's LFE level, LFE channel, or LFE +10, or the group's bass extension or delay compensation. Keep each change small. Note the time and the field. Switch to Group_4 and back, so GLM applies it. Put the field back before the next one.
6. G6, Main.sam again. Open Main.sam in GLM, and switch to the group you use. Stop the capture.
7. G7, qlm's guess. Print qlm's frames for the same group, from the copy:

   ```bash
   qlmctl apply-group "$COPY" "Group_4" --dry-run
   ```

   It reads only the file. Its `40` frames for the Right and the 7350A are qlm's guess. It ends with REFUSED, for the 8351B's rate, as every group in this setup does.

In the capture, read the switch's routing pass and blocks: the Right's and the 7350A's `40` frames against the AES3 ones, and the 7350A's second routing frame. Note any frame no capture has shown. For G5, note which frame changes with each field.

| What GLM sends | It means |
| --- | --- |
| `40 00 01 02 00`, as qlm guesses | qlm's guess holds. A golden test pins it, and the warning goes. |
| Any other analog frame | qlm takes GLM's, and a golden test pins it |
| A change in the 7350A's `40 01 02 00 00` too | The second routing frame carries the input, which answers part of Q8 |
| G5: a field that moves `3C`, `3E`, `42`, `43`, `4B`, or `10 01 09` | That frame carries the field. The rest stay open. |

If GLM's level rises above −50 dB, turn the knob down.

## Part H: the adapter when the Mac sleeps

> Q16. What does the adapter do when the host's USB suspends?

The app stops System when the Mac sleeps, so the adapter takes over about 2.6 s later, as at any stop. What it does after that decides two things for the app. Does the knob still work while the Mac sleeps? And does the level jump when the Mac wakes? If the sleep cuts the adapter's power or resets it, the boot ramp hlm saw, up to a stored level we don't know, could run at every wake.

It can't be tested through the Pi. The proxy doesn't forward suspend, so the adapter sees only silence, as at a quit. Plugged into the Mac, the adapter does see the suspend, but nothing records it. So this part listens, reads the level with the staircase, and checks how the adapter came back. A full answer needs a USB analyzer that passes suspend through, such as a Cynthion, and the bus tap for what the adapter sends while the host sleeps.

The Mac is also the music's source, so the music stops when it sleeps. Only a source that plays through the monitors without the Mac lets you hear the knob during the sleep. A DarkWake tests nothing, since USB stays up: in `sleep-wake-darkwake`, GLM kept polling through one. Before H4, check `pmset -g assertions` for anything that holds the Mac awake.

1. H1, the move. Quit GLM, and stop the signal. Unplug the adapter from the Pi, and plug it into the Mac. Once `ioreg -p IOUSB -w0 | grep "Gnet Adapter"` shows it, note the `id` in that line. Wait a minute after GLM quit.
2. H2, the reset. Run `qlmctl info`, then the reset without `--muted`, since Part G may have changed GLM's mutes. No round goes out unless the knob turns.

   ```bash
   qlmctl volume -60 --ceiling -35 --seconds 5
   ```

   Optional: before the reset, run C3's staircase, to read the level the adapter came up at after it booted. hlm says a stored startup level.
3. H3, the calibration. With the noise at −30 dBFS on the Right channel, run `qlmctl poll --seconds 10`, and note the Right's `hf`. It replaces H1 from Part C, in case GLM's group changed the Right's trim. Stop the noise.
4. H4, the sleep. With no `qlmctl` running and the noise off, sleep the Mac with `pmset sleepnow`. Wait 60 s. If another source plays through the monitors without the Mac, play it now at the knob's level, turn the knob down 6 dB and back, and listen for whether the level follows. Wake the Mac with a key.
5. H5, the wake. Check what happened:

   ```bash
   pmset -g log | grep -e "Entering Sleep" -e "DarkWake" -e "Wake from" | tail -5
   ```

   ```bash
   ioreg -p IOUSB -w0 | grep "Gnet Adapter"
   ```

   The first says whether the Mac truly slept. The second shows the adapter's `id`: the same as in H1, or a new one, if it came back as a new device. Then run C3's staircase with `qlmctl poll --seconds 120`, against H3's reading.
6. H6, optional, `qlmctl` across a sleep. Run `qlmctl poll --seconds 300`. About 10 s in, sleep the Mac for 60 s, then wake it. Read `poll`'s lines after the wake: an adapter error, new sessions because the leases lapsed, or the same sessions. `poll` sends no level.
7. H7, the end. Put the adapter back where it lives. Relaunch GLM, which applies its group, and ends the session.

| What you find | It means | For qlm |
| --- | --- | --- |
| A true sleep, the same id, and H3's level | The adapter rides through the host's suspend, at the knob | Nothing changes. The app's stop at sleep is enough. |
| A new id, and H3's level | The adapter reset or lost power, and came back at the knob | The app must expect the adapter to vanish and return at every sleep |
| A new id, and another level | It came back at a startup level of its own | The level can jump at every wake. The app must set its level the moment the adapter returns, and warn. |
| The knob worked during the sleep | The adapter stays standalone, and alive, while the host sleeps | A Mac asleep doesn't take the knob away |
| Only a DarkWake | Nothing was tested | Find what holds the Mac awake, and try again |

The staircase's stop rule holds in H2 and H5: no step plays louder than the calibration.

## What this session can't settle

| Question | Why not here | What would settle it |
| --- | --- | --- |
| Q1, a `7D` or `7E` address | qlm never leases either, and refuses to send one. GLM's count reaches `7D` only after about twenty wakes in one launch. | A GLM capture that long. qlm gains nothing from it, since it skips both. |
| Q2, more than one request in flight | qlm keeps one in flight by design, and `qlmctl` can't send two | A debug flag that sends two adapter queries back to back, with replies of different shapes, such as `01 39` and `01 08`. Nothing qlm does depends on it. |
| Q6, `01 22` and `01 51 82` against the defer broadcast | qlm refuses both, and the broadcast is on the bus, which USB can't see | The bus tap, with GLM and then qlm as the host |
| Q7, the `2D 00` and `3D 00 00` pair | qlm sends it only in dim, at the end of a wake, and at the end of an apply. The level change, the wake, or the apply around it masks what it does. The busy marker means something inside the monitor. | The bus tap, or Genelec's documentation |
| Q8, the rest | Only GLM can change the fields, and only those it shows. G5 covers what it can. | More GLM captures, a field at a time |
| Q11, `82` and `219000` | qlm refuses `51`. Sending other payloads would be a guess at an unknown query to the adapter. | Nothing safe from qlm |
| Q12, the 8351B's design rate | It needs REW, a mic, and an hour and a half | [measurement.md](measurement.md), in its own session |
| Q13, GLM's lag and the burst from a new knob | Both are GLM's own behavior, which qlm doesn't copy. Under GLM, a knob plugged in is followed at once, wherever it reads. | A GLM capture of a knob plugged in, with the signal off, if it ever matters |
| Q15, `c-` in the system info | The field is fixed per model. Nothing at the desk changes it. | Genelec's documentation |
| Q17, the rest of the telemetry | `88` and `89` need an hour of standby, and `8A` 20 minutes from a wake. A power-on is already in `qlm-control-all`: the Rear Right was switched on at 214.8 s. It needs decoding, not a session. C3 gives `42`'s slope. | Long `poll` runs on their own |
| Q18, the bare `04` after `8A` | It came once, from two 8330As busy after GLM's apply as the knob turned. qlm can't provoke it. | Watch for it in Part G's capture |

Q8 and Q16 are only partly here, in G5 and Part H.

## Afterwards

1. Stop any capture still running, and convert each with the command `capture.sh` printed. If D5 ran, `qlm-experiments` needs `--device` for each number the adapter had.
2. Write each capture's `notes.md`, as the control runs did. Give each step's time and exact command, what you heard, each meter reading, and each staircase's steps.
3. Captures hold the monitors' serials ([captures/README.md](../captures/README.md)), so the session asks you before it commits one.
4. Each new fact goes into [protocol.md](protocol.md) with its source, in the PR that brings its capture, and a test pins any fact that code relies on, as AGENTS.md asks. Then the settled rows leave the open questions.
5. Record in [plan.md](plan.md) what follows for System and the app: the adapter's polling, the stop with no knob, `01 2B 00` at connect, and the state after a wake.
