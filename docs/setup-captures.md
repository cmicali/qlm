# Setup captures

qlm builds each monitor's DSP block from GLM's setup file. The file doesn't hold filter coefficients. It holds each filter as settings: its type, frequency, gain, Q, and the sample rate to design it at.[^sr] qlm turns those into the coefficients GLM sends, and in every apply we've captured, its numbers match GLM's to the bit.[^bit-match] But every one of those applies came from one setup, Main.sam. And GLM sends three frames in its apply that qlm doesn't understand yet, so it leaves them out.

This is the script for a session that closes that gap. You make copies of Main.sam in GLM, each with known changes, and the Pi records GLM applying each one. qlm then has to produce GLM's frames byte for byte from each copy. Where it can't, the capture shows what GLM sends, and the copy shows which setting moved it.

If qlm's apply ends up matching GLM's everywhere, the 8351B's refusal can lift with no microphone, since a monitor can't tell who sent its frames. [measurement.md](measurement.md) then becomes an optional last check.

GLM drives the bus the whole time, and qlm sends nothing, so AGENTS.md's bus rules hold.

## What the captures answer

| # | Question | Parts |
| --- | --- | --- |
| S1 | Does qlm's PEQ design match GLM's for each filter type, across frequency, gain, and Q, at each design rate? That's 96 kHz for the 8351B, 48 kHz for the 8330A, and 12 kHz for the subwoofers. | B, C, D |
| S2 | Do levels and delays match across their range? | E |
| S3 | How does the crossover frequency reach `3B`, and what do `RateFlatness` and `RateCorrelated` change? | F |
| S4 | What do `43 00 02` and `4B 00 00 00 01` carry, to the 8351B? | G |
| S5 | What do a subwoofer's `3C`, `3E`, and `42` carry, once its LFE fields aren't zero? | H |
| S6 | What do the group's own settings change: its shelves, its room profile, and symmetrical EQ? | I |
| S7 | Does the generator stop, `05 04 …`, ever change? | All |

S7 decides what qlm does with opcode `05`. GLM sends the same 14 bytes at the top of every monitor's block, in every capture so far.[^stop] If no setting moves them, the frame is a fixed reset, and allowing exactly those bytes in an apply is the owner's call. If a setting does move them, the frame carries something, and we decode that first.

## What the first session settled

The owner ran the short form on 2026-10-31: Parts A, B, and J. Part G didn't run, as [its section](#part-g-the-8351bs-own-fields) says. Each capture's `notes.md` has its steps.[^first-session]

| # | After A, B, and J |
| --- | --- |
| S1 | Settled for the 8351B's peaking bands at 96 kHz. They match to the bit across frequency, from 25 Hz to 18 kHz, gain, from −20 dB to +6 dB, and Q, from 0.1 to 20.[^s1-bands] Its four shelves match too, now. One, 8000 Hz at −5 dB, missed by a bit in four of its five floats, until qlm took the shelf's w0 as a float.[^s1-shelf] That one shelf decides it. It matches a w0 rounded from double and one computed in float arithmetic, so the next capture needs the shelves under Part B. 48 kHz and 12 kHz wait for Parts C and D. |
| S2 to S6 | Open. Parts C to I haven't run. |
| S7 | Holds for 69 more stops, 154 in all, every one the known 14 bytes.[^s7] |

The captures also showed how GLM behaves while you edit:

- **It sends a band as you edit it.** Each change goes out at once, as one `10 0E` to the monitor's session, outside any block. Confirming the editor sends the monitor its level, its delay, and `10 01 09`, and no block. The block follows at the next group switch.[^live]
- **It moves fields of its own when the editor saves.** It rounds `Level_Sensitivity` to the value the editor shows, −0.17 to −0.2. It bumps `CalibrationStatusFlag`, 3 to 4. And each band you touch keeps one decimal of frequency and Q.[^own-fields]
- **Its editor has limits.** A plain notch, with no "+", is cut only. Q runs from 0.1 to 20, and the deepest cut is −20 dB. Above +6 dB of total boost, GLM warns, but takes the values.[^limits]
- **It cuts a pass short to lease a monitor again.** A monitor that wakes into the group mid-apply takes a new session. GLM stops that monitor's pass, and sends the whole block at the new one.[^cut]
- **Once, it broadcast a bare `03`, woke the system, and leased every monitor again.** The owner made no change then. [refused-frames.md](refused-frames.md#broadcast-03) has it.

## How a part runs

Each part is one capture of GLM, on a fresh copy of Main.sam. A step changes one thing, or one group of bands on one monitor, and has GLM apply it.

1. **A fresh copy.** In GLM, open Main.sam, and save it under the part's name, such as `qlm-b.sam`, in the same folder. Main.sam stays as it is, and GLM now has the copy open. Switch to Main 4x2, so all six monitors are on. Set `COPY` to the copy.
2. **The capture.** On the Pi, start it with the part's name:

   ```bash
   sudo ./pi/capture.sh setup-b-peq-8351b
   ```

3. **Each step:**
   1. Change the setting in GLM, in Main 4x2. Note the time, the setting, and its old and new values.
   2. Save the copy in GLM.
   3. Switch to Main 2x1, then back to Main 4x2, so GLM applies the group. Wait 15 s.
   4. Keep a redacted snapshot of the copy, and diff it against the step before:

      ```bash
      mkdir -p "captures/$PART/setups"
      python3 -I tools/redact-setup.py "$COPY" > "captures/$PART/setups/$STEP.sam"
      ```

      ```bash
      diff "captures/$PART/setups/$PREV.sam" "captures/$PART/setups/$STEP.sam"
      ```

      The diff goes in the notes. It says exactly what changed in the file. If it shows more than the change you made, note that too. GLM may move other fields along with a setting, and that's worth knowing.
4. **The end.** Stop the capture with Ctrl-C.

Each part's first snapshot, `0`, is taken right after the copy is made, before any change. So every step's diff is against the step before it, and the first step's is against Main.sam.

GLM may send a change as you make it, before the switch. The capture keeps that too, and the notes' times tell the two apart.

Play no music. The applies need no signal, and some of these settings would sound strange. Keep the knob at −60 dB or lower.

**Never commit a copy.** It's a raw setup file. Only the redacted snapshots go in the repo.

## Before the session

This takes about 15 minutes.

1. On the Pi, check that `qlm-proxy` is running, and that `vcgencmd get_throttled` reads `0x0`.
2. In GLM, open Main.sam, switch to Main 4x2, and stop any music. Turn the knob to −60 dB.
3. In the Terminal you'll use, go to your checkout of qlm, and set the setup folder:

   ```bash
   DIR="$HOME/Documents/Genelec/GLM5/Setup Files"
   ```

   Then, for each part, set `PART` to its capture's name and `COPY` to its copy, for example:

   ```bash
   PART=setup-b-peq-8351b COPY="$DIR/qlm-b.sam"
   ```

4. Build `qlmctl` with `make cli`. `qlmctl setup "$COPY"` reads a copy without opening the bus, and lists its groups and nodes. Use it to check each copy before you capture it. Part A uses `qlmctl compare-apply`, which also only reads files.

## The run order

| Part | Capture | What changes | For | Time |
| --- | --- | --- | --- | --- |
| A | `setup-a-baseline` | Nothing | The method | 5 min |
| B | `setup-b-peq-8351b` | The Left 8351B's bands and shelves | S1 at 96 kHz | 15 min |
| C | `setup-c-peq-8330a` | The Rear Left 8330A's bands and shelves | S1 at 48 kHz | 10 min |
| D | `setup-d-peq-subs` | The 7370A's and the 7350A's bands | S1 at 12 kHz | 10 min |
| E | `setup-e-level-delay` | Levels, distances, and a subwoofer's phase | S2 | 15 min |
| F | `setup-f-crossover` | The crossover frequency | S3 | 10 min |
| G | `setup-g-8351b-fields` | The 8351B's own fields | S4 | 15 min |
| H | `setup-h-lfe` | Each LFE field of a subwoofer | S5 | 15 min |
| I | `setup-i-group-eq` | The group's shelves, room profile, and symmetrical EQ | S6 | 15 min |
| J | `setup-j-restore` | Main.sam again | Back to normal | 5 min |

That's about two hours. If time is short, run A, B, G, and J. The 8351B's refusal hangs on those.

## Part A: the baseline

Part A checks the method before anything changes. Make the copy, `qlm-a.sam`, and take its snapshot `0`. Diff it against a redacted Main.sam. It should differ in nothing that a monitor gets, so note anything that shows.

Then switch to Main 2x1 and back, and wait 15 s. Stop the capture, then copy and convert it, as [captures/README.md](../captures/README.md) says. That's two applies, so check each against snapshot `0` with its own group. First run on the whole capture, with Main 2x1:

```bash
qlmctl compare-apply "captures/$PART/setups/0.sam" "captures/$PART/reports.txt" --group "Main 2x1"
```

`compare-apply` reads the two files and opens no bus.[^compare] It lists each of GLM's DSP passes with its time, in the capture's seconds, matched to the closest node of the group. It says `matches` for each one that's the same byte for byte. Main 2x1's passes come first, and should match. The passes after them are the switch back to Main 4x2, so they differ.

Set `T` between the two applies: after the last Main 2x1 pass, and a second or more before the first Main 4x2 pass. A switch's routing pass, with its generator stops, comes about a second before its DSP pass. Then check each apply in its own window:

```bash
qlmctl compare-apply "captures/$PART/setups/0.sam" "captures/$PART/reports.txt" --group "Main 2x1" --to $T
```

```bash
qlmctl compare-apply "captures/$PART/setups/0.sam" "captures/$PART/reports.txt" --group "Main 4x2" --from $T
```

Each 8351B's pass lists `43 00 02` and `4B 00 00 00 01` as left out. Each run also checks every generator stop in its window, the ones to monitors with no pass included. Both runs should end with every pass matching and every stop the known one, and exit 0, as Main.sam's captures do. If they don't, stop the session and work out why first. The `GLM` and `qlm` lines show each frame that differs.

## Part B: PEQ on the 8351B

Part B changes only the Left 8351B. The Right stays as it was, so the same capture holds an untouched 8351B beside it.

1. B1, the bands. Change these of the Left's peaking bands, all in one step:
   - one near the bottom, at 20 to 30 Hz, cut as deep as GLM allows;
   - one at about 1 kHz, with the narrowest Q GLM allows;
   - one at about 1 kHz, with the widest Q GLM allows;
   - one near the top, at 15 to 20 kHz;
   - one boosted, if GLM allows a boost;
   - one set to 0 dB, which should go out as `1, 0, 0, 0, 0`.
2. B2, the shelves. Move both low shelves and both high shelves to new frequencies and gains, one of each pair cut and one boosted.
3. In the next capture, B3, the high shelves at 5000, 10000, 11000, 13000, and 15000 Hz, each at −5 dB, one per step, at 96 kHz. A w0 rounded from double and one computed in float arithmetic give different coefficients at each. So these tell which GLM uses (protocol.md's open question 20).

Each band is checked on its own, so one step can change several. The one rule is that each band's settings are known from the snapshot.

## Part C: PEQ on the 8330A

As Part B, on the Rear Left 8330A. A two-way has two low shelves, two high shelves, and 16 peaking bands, at 48 kHz.

## Part D: PEQ on the subwoofers

As Part B's B1, on the 7370A and the 7350A. A subwoofer has 20 peaking bands and no shelves, at 12 kHz. Keep each band between 20 Hz and the group's crossover, 85 Hz in Main 4x2.

## Part E: levels and delays

Each step changes one setting on one monitor:

1. E1: the Left 8351B's level to the lowest GLM allows, and the Rear Left's to the highest. qlm sends a monitor's level as `Level_Sensitivity` plus `Group_Sensitivity`.[^level]
2. E2: the Right 8351B's distance to the largest GLM allows. A monitor's delay is its `Time-of-flight_Compensation`, in 48 kHz samples.[^delay]
3. E3: the 7370A's phase, `Phase(degrees)`, to two values in turn. A subwoofer's delay is its phase angle turned into a delay.[^delay]
4. E4: if GLM shows them, `Group_Sensitivity`, `Optional_Gain`, and `Video_Delay`, one step each. qlm reads the first. The capture shows whether GLM sends the other two at all.

## Part F: the crossover

Main 4x2 crosses over at 85 Hz, and GLM sends `3B 00 55`. Main 2x1 crosses over at 60 Hz, and GLM sends `3B 00 3C`.[^xo] Main 2x1 also has `RateFlatness` and `RateCorrelated` at −1, where Main 4x2 has them at 0.

1. F1: the lowest crossover GLM allows.
2. F2: one between, such as 100 Hz.
3. F3: the highest GLM allows.
4. F4 and F5: if GLM shows `RateFlatness` and `RateCorrelated` as their own controls, change each alone.

The diff after F1 to F3 shows whether GLM moves the two rates along with the crossover.

## Part G: the 8351B's own fields

> **Not run on 2026-10-31.** GLM 5.2.1 shows no control for `GroupDelayCompensation` or `BassExtensionXO(Hz)` outside the group definition. The group definition's "Extended Phase Linearity" switch is the likely owner of `GroupDelayCompensation`, and changing it needs a recalibration. So Part G needs [the file-edit route](#when-glm-doesnt-show-a-setting), or a session with a recalibration.

This part matters most. GLM sends two frames to the 8351Bs, always with the same bytes. `43 00 02` follows the level pair, before the PEQ slots. `4B 00 00 00 01` follows `3B`.[^43-4b] The 8351B's node has two fields no other node has, and both hold the same value in every group: `GroupDelayCompensation:2` and `BassExtensionXO(Hz):1`. Our guess is that `43` carries the first and `4B` the second. qlm now builds both frames from those fields, but only at 2 and 1. Against the guess, each group has a `GroupDelayCompensation:2` of its own, and no other model gets a `43`.

qlm refuses an 8351B whose fields hold any other value, or whose group's `GroupDelayCompensation`, `Group_BE_Mode`, `Group_BE_XOMin`, or `Group_BE_XOMax` differ from 2, 0, 150, and 250. So for any copy in Part G, `compare-apply` says `qlm builds no block` for that node, and exits 1. Its pass is then shown against the other 8351B, so a `43` or `4B` that GLM changed shows as GLM's frame against qlm's.

Each step changes one field to each other value GLM offers, one value per step:

1. G1: `GroupDelayCompensation`.
2. G2: `BassExtensionXO(Hz)`.
3. G3: the group's bass extension mode, `Group_BE_Mode`.
4. G4: its range, `Group_BE_XOMin` and `Group_BE_XOMax`, now 150 and 250.

After each step, read the capture for `43` and `4B`. A frame that moves with a field carries it.

## Part H: the LFE fields

Today GLM sends each subwoofer `3C 00 00`, `3E 00 00`, and `42 00 00`. qlm sends the same, and it refuses a subwoofer whose LFE fields aren't zero, or whose LFE crossover isn't 120 Hz, the values in every capture.[^lfe] One step each, on the 7370A:

1. H1: `LFE_+10` on.
2. H2: `LFE_Channel` to another channel.
3. H3: `LFE_Level` to a value other than 0.
4. H4: `LFE_CrossoverFrequency(Hz)` to another value.
5. H5: `SubwooferGroupID`, if GLM shows it.

Then repeat whichever step moved a frame on the 7350A, to check it lands the same way.

## Part I: the group's own EQ

The group has settings of its own, beside each monitor's: low and high shelves (`Group_LP_Shelve` at 100 Hz and `Group_HP_Shelve` at 1 kHz, both at 0 dB), a room profile (`Group_RoomProfile`, with `_MidRange` and `_Strength`, all 0), and `Group_SymmetricalEQ`, on. One step each:

1. I1: the group's low shelf, to a new gain.
2. I2: its high shelf, to a new gain.
3. I3: the room profile on, with its strength above 0.
4. I4: symmetrical EQ off.

These may change every monitor's bands or shelves at once. The capture shows how GLM folds them into each block.

## Part J: back to normal

Open Main.sam in GLM, as its own capture, `setup-j-restore`. Switch to the group you use. Then play music at a low level, and check it sounds as it did before the session. Stop the capture.

## When GLM doesn't show a setting

If GLM has no control for a field, you can edit a copy in a text editor and open it in GLM. Only ever edit a copy. Give the field only a value GLM itself writes for it somewhere, in another group or another monitor. The file uses CRLF line endings, so keep them. If GLM refuses the file, or rewrites the value when it opens it, note that and skip the step. GLM's own controls are better, since they show what GLM allows.

## After the session

For each capture:

1. Copy it from the Pi and convert it, as [captures/README.md](../captures/README.md) says.
2. Write its `notes.md`: each step, its time, and its diff.
3. Check that `setups/` holds only redacted snapshots.

Then check each step against its snapshot. Each step makes two applies, the switch to Main 2x1 and the one back to Main 4x2, and each gets its own run, with its group and its window. First run on the whole capture, once with each group. Each run lists every pass with its time, in the capture's seconds:

```bash
qlmctl compare-apply "captures/$PART/setups/$STEP.sam" "captures/$PART/reports.txt" --group "Main 2x1"
```

With the notes, those times give each apply's window, from a second or more before its first pass to the same before the next apply's. Windows that meet end to end check every generator stop once. Then check each apply alone:

```bash
qlmctl compare-apply "captures/$PART/setups/$STEP.sam" "captures/$PART/reports.txt" --group "$GROUP" --from $FROM --to $TO
```

Each run also lists, as `GLM, outside a pass`, the DSP frames no pass holds, and what explains each one. A switch's routing frames come before the pass they route. A step's live edits come after the edited monitor's pass before them, each band with its slot, and so does the level, delay, and `10 01 09` GLM sends when you confirm the editor. Each slot's last edit should be the slot as the block sends it, and the ones before it are values the editor passed through.

The edits come before the step's save, so check them against the step's own snapshot, not the one before. Run the window of the apply before the edits again, with the step's snapshot and `--check-outside`:

```bash
qlmctl compare-apply "captures/$PART/setups/$STEP.sam" "captures/$PART/reports.txt" --group "Main 4x2" --from $FROM --to $TO --check-outside
```

The summary should say `0 not explained`. The edited monitor's pass in that window is from the step before, so it differs, and the run exits 1. That pass is what names the monitor's node. A redacted snapshot holds no hardware IDs, and a window with no pass names a node only by model, so it can't tell the two 8351Bs apart.

`compare-apply` matches passes only within the group it's given. Main.sam's Group_4 is nearly a copy of Main 4x2, and these steps change only Main 4x2. So a match across groups could put a changed node's pass on Group_4's old copy, and hide the change.

Then one PR adds the captures, and it's mostly data. `QLMDSPBlockGoldenTests` checks its passes from a table of rows: a capture, the setup file GLM applied, the group, a window of the capture's seconds, and each pass's session and node. Each apply is a row, so a step is two. `compare-apply` uses the same code, so a step it passes adds rows and no new code. The rows pin GLM's frames byte for byte, and protocol.md gets what they decode to. Where qlm refuses a setting today, the test pins GLM's frames instead. The golden tests check S7 on every row: every generator stop GLM sent in the row's window is the known 14 bytes, pass or no pass, and each pass has at least one.

| Result | It means |
| --- | --- |
| qlm matches GLM in Parts B, C, and D | The PEQ design holds across its range at all three rates. S1 is settled. |
| A band qlm gets wrong | The capture has GLM's coefficients, and the test pins the fix |
| `43` or `4B` moves with a field in Part G | That frame carries it. qlm sends it from the field, and a golden test pins it. |
| Neither moves | They're fixed, as far as this setup can show. Allowing GLM's exact bytes is the owner's call, as for `05`. |
| `05 04` never changes | It's a fixed reset. The owner decides whether qlm sends it. |
| `05 04` changes | It carries a setting, and we decode that before anything else |

[^sr]: `Tests/Setups/Fixtures/Main.sam`. Every band of a `ThreewayGen2` node, the 8351B, has `SR:96000`. A `TwowayGen2`, the 8330A, has `SR:48000`, and a `SubwooferGen2` has `SR:12000`.
[^bit-match]: `QLMDSPBlockGoldenTests`, over every DSP pass in the captures; [protocol.md](protocol.md).
[^stop]: [refused-frames.md](refused-frames.md#05-04--the-generator-stop). It's `05 04 00 00 00 FF FF EA 00 01 90 00 02 DA`, 154 times in 15 captures.
[^level]: [plan.md](plan.md#the-setup-file).
[^delay]: [plan.md](plan.md#the-setup-file); #8.
[^xo]: `startup-idle`, `3B 00 3C` at 8.723 s; `standby-wake`, `3B 00 55` at 46.775 s; [refused-frames.md](refused-frames.md).
[^43-4b]: [refused-frames.md](refused-frames.md), on `43 00 02` and `4B 00 00 00 01`; `startup-idle`, from 8.650 s.
[^lfe]: [refused-frames.md](refused-frames.md), on `3C`, `3E`, and `42`; `QLMDSPBlock`.
[^first-session]: `captures/setup-a-baseline`, `setup-b-peq-8351b`, and `setup-j-restore`, and their notes.
[^s1-bands]: `setup-b-peq-8351b`, snapshot `1`, the Main 4x2 apply at 182.460 s; `QLMDSPBlockGoldenTests`.
[^s1-shelf]: `setup-b-peq-8351b`, slot `03` at 265.754 s, live from the editor, and at 300.029 s, in the pass; `testShelvesTakeAFloatW0`.
[^s7]: `testEveryGeneratorStopIsTheKnownOne`: 15 in `setup-a-baseline`, 36 in `setup-b-peq-8351b`, and 18 in `setup-j-restore`.
[^live]: `setup-b-peq-8351b`, 49.989 to 117.849 s and 230.501 to 265.754 s, and the confirms at 167.774 and 287.885 s.
[^own-fields]: `setup-b-peq-8351b`, `setups/0.sam` against `setups/1.sam`.
[^limits]: `setup-b-peq-8351b`'s notes.
[^cut]: `setup-b-peq-8351b`, the 7350A at 183.450 and 300.973 s.
[^compare]: The README's [compare-apply](../README.md#compare-apply) section, and `qlmctl help`, say how it matches a pass to a node, and what each exit code means.
