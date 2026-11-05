# qlm-poll-meters

Two runs of `qlmctl poll --seconds 10` on all six monitors, on 2026-11-05. It is not a GLM scenario. No USB capture was made: the Pi proxy was not in line. So this folder holds no `capture.pcapng.xz` or `reports.txt`, only what `qlmctl` printed, saved as it ran:

- `poll-silent.txt`, with nothing playing.
- `poll-music.txt`, with music playing.

`qlmctl` was the one in `~/.local/bin`, installed at 17:28 EST, after `24b4732` (#91) merged on main. That `poll` starts a whole System. It leases every monitor, and polls them and the adapter, but sends no level and no `2B`. The installed app was quit, and GLM was not running. No mic was in, and the knob was on the adapter.

Each line is the seconds since `poll` started, then a monitor's session, its hardware ID in decimal, its model, its power state, its temperature, and its four meters as raw counts: `in` is `42`, `hf` is `43`, `lf` is `45`, and `sub` is `46`. `-1` is a meter the model doesn't send. The 8351B's `44` isn't printed.

| Time (EST) | File | What was playing | The knob | What the owner heard |
| --- | --- | --- | --- | --- |
| 17:29 | `poll-silent.txt` | Nothing | −57.3 dB | Nothing |
| 17:30 | `poll-music.txt` | Music, over the monitors' digital input | −42.7 dB | The music went quiet while the run ran |

The times are the files' own, to the minute.

## What the runs showed

- **With nothing playing, every output reads its floor, 128.** The first 8330A's HF reads 130 or 131. Every other output reads 128 in every frame.
- **With nothing playing, each input rests at its model's floor.** The 8330As read 157 to 160, the 8351Bs 158 to 161, the 7370A 147 to 149, and the 7350A 146 to 148.
- **With music, the outputs read 221 to 240.** The 8330As read 228 to 231 on HF and 235 to 240 on LF. The 8351Bs read 221 to 224 on HF and 225 to 229 on LF. The 7370A's LF read 228 to 230, and the 7350A's 231 to 236.
- **With music, every input read 252, in every frame, all 10 s.** It read 252 even once the outputs fell silent.
- **The outputs fell to their floor while the input still read the music.** The 8351Bs and the 7370A read 128 from the frame at 1.77 s. The 8330As and the 7350A read it from 2.38 s. Every output read 128 from then to the end.
- **The temperatures were steady.** The 8330As read 29 and 31 °C, and the rest 43 to 47 °C.

## What it means

`poll` silenced the monitors. It sent no level, and about 2 s in, every output fell to its floor while the input still carried the music. The owner heard it. [docs/protocol.md](../../docs/protocol.md#a-host-that-sends-no-level) sets this against the earlier runs, and says what is fact and what is a guess. Since then, `poll` sends the knob's level.

The input meter read 252 here, but 199 to 254 with music in the earlier runs. [docs/telemetry.md](../../docs/telemetry.md#the-meters) has the meters.

`QLMPollMetersTests` checks each number above.
