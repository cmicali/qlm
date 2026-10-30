# qlm-control-all

qlm's second control run on the monitors, and its first on all six. It is not a GLM scenario. Recorded 2026-10-30 through the Raspberry Pi 5 inline proxy (usb-proxy with `tools/pi/usb-proxy.patch`), on usbmon1. The adapter was device 1:4. No mic, and the volume knob on the adapter. Music played quietly, and the user listened at each step.

`qlmctl` was built from `535fcc5`, on main. That commit sends the level to a new or woken monitor, ends `wake --volume` as GLM does, and sends GLM's whole dim. The run checks each fix. Every run went over USB, with GLM quit, under a −35 dB ceiling.

The setup:

- All six monitors were on, and none was muted in GLM.
- GLM's level was `01 6F A9`, −39.0 dB, and the knob read −39.5 dB.
- The Rear Right 8330A is `8330AP21039626`, hardware ID `12 2F AB`.

After each qlm run, the Mac played its Tink sound, about 0.5 s after qlm's last report, so the user could time the hand-back.

| Time (EDT) | Seconds | What happened, and what the user heard |
| --- | --- | --- |
| 13:59:00 | 0 | Capture started. GLM was open and idle. |
| 13:59:17 | 17.4 | GLM was quit. Its last report, an ordinary adapter poll, is at 17.43 s. Heard: no change. |
| 13:59:26 | 26.2 | `info`, then `discover`: all six found and on, and the knob at −39.5 dB. Heard: no change. |
| 14:00:06 | 66.3 | `volume -50 --ceiling -35 --seconds 15`, to 81.4 s. Heard: all six dropped about 10 dB at once. They came back up 2 to 3 s after the Tink. |
| | | The user paused the music and switched the Rear Right 8330A off at its power switch. They also turned the knob down to −52.7 dB, meaning to turn down the Mac's output. |
| 14:02:11 | 191.9 | `volume -50 --ceiling -35 --seconds 90`, to 282.1 s. qlm found five monitors and held −50 dB. |
| 14:02:34 | 214.8 | The user switched the Rear Right on, with the music paused. It answered the probe at 214.755 s, and took session 07 at 214.774 s. Its ack came at 214.775 s, and qlm's level, `FF 1F 00 67 9F`, at 214.776 s, before the Rear Right's `39`. Heard, with the music playing again: the Rear Right a little louder than the rest. |
| 14:05:18 | 378.5 | The user opened GLM, to see the knob's level. GLM applied the group, sent its startup level, −56.5 dB, at 379.2 s, and then followed the knob. The user turned it to −40.0 dB, at 384.0 s. Heard: the Rear Right now matched the others. |
| 14:05:45 | 405.5 | GLM's last report, an ordinary adapter poll. At 14:06:04, GLM was quit, and was gone within 0.1 s. |
| 14:06:11 | 431.9 | `dim on --volume -50 --ceiling -35 --seconds 10`, to 442.0 s. Heard: a big drop, and the level back after the Tink. |
| 14:06:31 | 451.7 | `dim off --volume -50 --ceiling -35 --seconds 5`, to 456.8 s. Heard: about 10 dB under, and the level back after the Tink. |
| 14:08:02 | 542.2 | A dry run of `wake --volume -50`. It discovers, as `discover` does, and sent no control frame. |
| 14:08:23 | 563.4 | `sleep`, to 565.1 s. |
| 14:08:34 | 574.9 | `wake --volume -50 --ceiling -35 --seconds 10`, to 587.2 s. The user had to leave, so no one reported on the sleep or the wake. |
| 16:19:00 | 8400.4 | After the break, the user asked to run steps 4 and 5 again. `dim on --volume -50 --ceiling -35 --seconds 10`, to 8410.5 s. Heard: a big drop, and the level back 2 to 3 s after the Tink. |
| 16:19:20 | 8420.2 | `dim off --volume -50 --ceiling -35 --seconds 5`, to 8425.4 s. Heard: a smaller drop, and the level back 2 to 3 s after the Tink. |
| | | The knob was turned up, from −40.1 dB to −32.7 dB. |
| 16:20:10 | 8471.0 | `sleep`, to 8472.2 s. Heard: the music stopped. |
| 16:20:21 | 8481.3 | `wake --volume -50 --ceiling -35 --seconds 10`, to 8494.1 s. Heard: the music came back quietly, and rose after the Tink, louder than before step 4. |
| 16:22:24 | 8604.2 | The user turned the knob down. `info`: the knob at −35.9 dB. |
| 16:22:45 | 8625.3 | The user turned it down again. `info`: the knob at −41.4 dB. |
| 16:23:18 | 8658.6 | `volume -41.5 --ceiling -35 --seconds 5`, to 8663.8 s, the level step nearest the knob. Heard: no change at the start, and none after the Tink. |
| 16:26:01 | | Capture stopped. |

## What the run showed

- **A monitor switched on gets qlm's level first.** The Rear Right took its session during a hold at −50 dB, and the level went to it 1.1 ms after its ack, outside the volume cycle. It came before anything else qlm sent the monitor.
- **A woken monitor gets the level too.** A wake drops every monitor's session, as GLM's does in `standby-wake`. Each poll after the wake got `01 7E`, and the six took new sessions, `09` to `0E`. The level went to each about 1 ms after its ack.
- **The wake ends as GLM's does.** qlm sent the level, the three wake pairs, then 0.25 s later the level again, `2D 00`, and `3D 00 00`. GLM's wake in `standby-wake` ends with its last pair, its level 0.23 s later, `2D 00`, and `3D 00 00`.
- **Dim is GLM's whole sequence.** qlm sent the level it dims from, then the new level twice, one round of `2B 04` to all six, `2D 00`, and `3D 00 00`. After the first level, that is `mute-dim`'s dim at 51.24 s. In `qlm-control-first`, dim sent only the level.
- **The adapter hands back at the knob's level.** Each exit agreed with the first run. The level went back to the knob 2 to 3 s after the Tink, and step 6, which stopped at the knob's level, made no change.
- **Every control frame is on the allowlist, under the ceiling.** qlm sent 375: levels, `2B 04`, the input pair, and `3A 03` power steps. It sent three levels: −50 dB, −70 dB dimmed, and −41.5 dB. Each is a report GLM sent in `volume-sweep`. `QLMControlAllTests` checks all of it.

## Surprises

- **The ceiling holds only while qlm runs.** Between steps 4 and 5, the knob was turned up to −32.7 dB. After the wake, the adapter took over at the knob's level, above the run's −35 dB ceiling. No host bounds the knob.
- **A power-cycled monitor plays its own trims.** The Rear Right played a little louder than the rest at qlm's level, until GLM's launch applied the group. qlm sent it the level, but not the group's settings.
- **In each wake, one monitor in standby missed its lease.** At 575.00 s and 8481.29 s, a monitor in standby took no session, and answered `01 7E` for 40 ms. qlm probed again, and leased it 45 ms later.
- **Dim off sends the dimmed level first.** A new `qlmctl` takes the other dim state first, so dim off sends −70 dB, then −50 dB 1 ms later. No one heard it.
- **Step 6 ran at −41.5 dB, not −40 dB.** The knob ended at −41.4 dB after the user turned it back down.
- **Two telemetry replies end with a bare `04`, a tag no other capture shows.** At 381.15 and 381.17 s, both 8330As answered GLM's poll busy, 1.4 s after its group apply, as the user turned the knob. Each reply ends `8A 00 00 04`. In every other reply in every capture, `8A` is the last tag. The parser stops at `04`, and System keeps what came before it.

## Not explained

GLM's last report is at 14:05:45.5, 18 s before it was quit. As in `quit-glm`, it was an ordinary poll.
