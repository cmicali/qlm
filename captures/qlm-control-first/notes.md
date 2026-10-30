# qlm-control-first

qlm's first control run on the monitors, not a GLM scenario. Recorded 2026-10-30 through the Raspberry Pi 5 inline proxy (usb-proxy with `tools/pi/usb-proxy.patch`), on usbmon1. The adapter was device 1:4. No mic, and the volume knob on the adapter. Music played quietly through the whole run, and the user listened at each step.

`qlmctl` was built from `ba67c6d`, on main. It ran `info`, dry runs, `volume`, `dim`, `mute`, `sleep`, and `wake` over USB, with GLM quit, under a −35 dB ceiling. An earlier attempt the same day was discarded: no music played, and the other monitors were not out of the way.

The setup:

- The Right 8351B, `8351BP21002717`, played.
- The 7370A feeds every monitor, so it stayed on, muted in GLM.
- The Left 8351B was in standby.
- The two 8330A and the 7350A were switched off at their power switches.
- GLM's level and the knob were at −40 dB. GLM's last level frame was `01 47 AE`, −40.0 dB, and the knob read −40.1 dB.

After each qlm run, the Mac played its Tink sound, about 0.2 s after qlm's last report, so the user could time the hand-back.

| Time (EDT) | Seconds | What happened, and what the user heard |
| --- | --- | --- |
| 12:28:24 | 0 | Capture started. GLM was open and idle. |
| 12:28:41 | 17.5 | GLM was quit. Its last report, an ordinary adapter poll, is at 17.45 s. Heard: no change, and the sub stayed muted. |
| 12:29:59 | 95.3 | `info`: the knob at −40.1 dB. Then a dry run of `volume -61.5`. |
| 12:31:09 | 165.2 | `volume -45 --ceiling -35 --dry-run`: `FF 1F 00 B8 44`, GLM's −45 dB frame. |
| 12:31:24 | 180.2 | `volume -45 --ceiling -35 --seconds 15`, to 195.1 s. Heard: a 5 dB change was too small to tell, at the start or after. |
| 12:32:48 | 264.0 | A dry run of `volume -60`: `FF 1F 00 20 C4`, GLM's −60 dB frame. |
| 12:32:59 | 274.8 | `volume -60 --ceiling -35 --seconds 15`, to 289.7 s. Heard: a clear drop at the start. After the Tink, the level came back up about 2 to 3 s later. |
| 12:34:27 | 363.7 | `volume -60 --ceiling -35 --seconds 30`, to 393.7 s, while the user turned the knob down. At 373.12 s, with the knob at −41.7 dB, qlm jumped to −41.5 dB. It then followed the knob down to −67 dB, and back to −66 dB. The knob ended at −65.7 dB. Heard: the jump up at the first notch, then the level following the knob. No jump after the Tink. |
| | | With qlm stopped, the user turned the knob back up to the starting level. Heard: the music followed the knob. |
| 12:36:32 | 488.0 | `info`: the knob at −43.3 dB. |
| 12:36:43 | 499.7 | Dry runs of `dim on` and `dim off`. |
| 12:37:22 | 538.3 | `dim on --volume -43.5 --ceiling -35 --seconds 10`, to 548.3 s. Heard: a 20 dB drop, and the level back about 2 to 3 s after the Tink. |
| 12:37:42 | 558.0 | `dim off --volume -43.5 --ceiling -35 --seconds 5`, to 563.0 s. Heard: no change, during or after. |
| 12:38:45 | 620.7 | Dry runs of `mute on` and `mute off`. |
| 12:39:03 | 638.7 | `mute on --serial 8351BP21002717 --seconds 10`, to 648.7 s. Heard: the Right went silent, and the sub started playing. After the Tink, the Right stayed silent. |
| 12:39:24 | 660.5 | `mute off --serial 8351BP21002717 --seconds 5`, to 665.4 s. Heard: the Right played again, and stayed on. |
| 12:40:21 | 717.2 | Dry runs of `sleep` and `wake`. |
| 12:42:01 | 816.9 | `sleep`. Heard: the music stopped, and nothing came back on its own. |
| 12:42:12 | 827.8 | `wake --seconds 10`, to 840.0 s. Heard: everything came back at the same level, with no change after the Tink. |
| 12:43:16 | | Capture stopped. |

## What the run showed

- **The adapter hands back at the knob's position, about 2.6 s after qlm's last report.** At 289.7 s, the level rose from qlm's −60 dB back to the knob's −40 dB, 2 to 3 s after the Tink. At 393.7 s, qlm stopped at −66.0 dB with the knob at −65.7 dB, and no one heard a change. With no host, the knob sets the level.
- **qlm follows the knob.** It ignored the knob's first 0.7 dB. At its first real turn, it jumped to the knob's position, and then followed it to the nearest 0.5 dB step. It ignored the last 0.3 dB. The highest level qlm sent was −41.5 dB, so the −35 dB ceiling was never reached.
- **A mute outlasts qlm.** The Right stayed muted after qlm's exit, until `mute off`.
- **qlm's mute unmutes the others.** As GLM does, `mute --serial` sends `2B 04` to every other monitor, so the sub, muted in GLM, started playing.
- **`qlmctl dim` sends only the dimmed level.** It sets dim before the volume, so System skips the rest of GLM's dim: the level twice, a round of `2B`, then `2D 00` and `3D 00 00`. The level itself is GLM's, 20 dB under.
- **A monitor woken from standby keeps its level.** qlm's wake sends no volume, and the monitors came back at the level they had.
- **Every control frame qlm sent is one GLM sends.** The levels are reports in `volume-sweep`, byte for byte. The mute payloads are `mute-dim`'s. The knob's burst has `knob-sweep`'s shape. The power steps are `standby-wake`'s. `QLMControlRunTests` checks each one.
- **No request timed out, and no sync went out.** Every `01 08` was one of a pair, and `01 39` went once per command. Six polls got `01 7E`, all to monitors in standby or waking.

## After the capture

At 12:43:48, GLM was relaunched. The user had switched the two 8330A back on just before. They played very loud for about a second, and then everything went to −56.5 dB, the startup level in `Main.sam`. A monitor that is switched on plays at its own stored level until a host sends one. So qlm must send the volume to every monitor it finds, at once. The capture does not show this.

## Not explained

In the discarded attempt, GLM showed −40 dB while its level frames were `00 31 07`, −56.5 dB, and the knob read −93.6 dB. In this run, GLM's display, its level, and the knob agreed.
