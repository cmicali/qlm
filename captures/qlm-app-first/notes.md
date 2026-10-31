# qlm-app-first

The menu bar app's first run on the monitors, not a GLM scenario. Recorded 2026-10-30 through the Raspberry Pi 5 inline proxy (usb-proxy with `tools/pi/usb-proxy.patch`), on usbmon1. The adapter was device 1:4. No mic, and the volume knob on the adapter. Music played quietly, and the user listened at each step.

The app was built from `9af3c9b`, on main, and ran under a −35 dB ceiling. The user drove it by hand in its popover and Settings. The app has no way to be driven from a script yet. The steps came from the plan the session that ran it was given. The user also explored on their own between steps, and the table shows that too.

The setup:

- All six monitors were on, and none was muted in GLM. The 7370A feeds every monitor, so a run with one monitor would have kept it on too, and the app unmutes every monitor. The user chose all six, since `qlmctl` had already run the same System on all six.
- GLM's level was `01 47 AE`, −40.0 dB, and the knob read −39.9 dB.
- The Left 8351B is `8351BP21002711`, hardware ID `11 4B AB`. The Right is `8351BP21002717`, `11 4B EA`.

After each quit, the user listened for the hand-back, about 2.6 s after the app's last report.

| Time (EDT) | Seconds | What happened, and what the user saw and heard |
| --- | --- | --- |
| 17:38:56 | | GLM was launched. The user set it to −40 dB. |
| 17:40:15 | 0 | Capture started. GLM was open and idle. |
| 17:40:35 | | The app was launched with "Use the GLM adapter" off, on its fake bus. In Settings, the user set the slider to −45 dB and the ceiling to −35 dB. The ceiling saved only on a second try, with Return. |
| by 17:42:23 | | Step 1: the setting on, with GLM running. The banner said GLM holds the adapter, and offered Quit GLM. GLM was the only client holding the adapter, and the capture has no `01 39`, the app's first frame on an open. Heard: no change. |
| 17:43:17 | 182.8 | Step 2: Quit GLM, from the banner. GLM's last report, an ordinary poll, is at 182.770 s. GLM was gone by 17:43:18.6. No permission dialog. |
| 17:43:18 | 183.6 | The app opened 0.85 s later, at 183.622 s, with its sync, `01 39`. It sent its −45 dB level from 184.019 s. Its probes at 184.0, 184.5, and 185.1 s got `01 7E`, because the monitors still held GLM's leases. The probe at 185.719 s found the Rear Right 8330A, 3.06 s after GLM last polled a monitor. All six were leased by 185.842 s, each with the level right after its ack. Heard: the level dropped a little, then a brief dropout that recovered. |
| 17:43:21 | | Step 3: the popover's six dots and the monitors window matched the monitors, all on. The fake bus's three monitors stayed in the list, as offline. |
| 17:44:31 | 256.2 | The user explored the popover. The slider went down to −54 and up to −44 dB. Mute all and unmute all came at 258.830 and 259.333 s, and dim on and off at 259.831 and 260.446 s. |
| 17:44:57 | 282.6 | The user turned the knob to its top stop, 0.0 dB at 293.6 s, and to its bottom, then back to −40.2 dB by 296.5 s. The app never sent above −35 dB. At the bottom it sent the floor, `00 00 08`. |
| 17:45:46 | 331.7 | The user muted and unmuted each monitor in turn, about 0.4 s each, from session `02` to `07`. |
| 17:47:12 | 417.1 | Step 5, the knob: down from −39.9 to −50.3 dB, and back to −39.9 dB by 421.1 s. The app followed it, from −40 to −50.5 dB and back, with GLM's burst at each change. Heard: the level followed the knob. |
| 17:47:30 | 435.8 | Step 4, the slider: down to −51.5 dB, up to −44 dB, and back to −45 dB by 439.3 s. Heard: as expected, and nothing louder. |
| 17:50:21 | 606.1 | Step 6: the Left 8351B, at `03`, muted for 4.3 s. Then the Right, at `06`, from 612.719 s for 4.3 s. Heard: each went silent and came back. The user couldn't tell the two apart by serial. |
| 17:51:21 | 666.4 | Mute all for 4.1 s, then unmute all. Heard: everything went silent, then came back. |
| 17:51:49 | 694.0 | Step 7: dim on for 3.6 s, then off. Heard: a clear drop, and back to the same level. |
| 17:52:31 | 736.9 | Step 8a: the slider to −50 dB. Then quit. The app warned that quitting makes the monitors louder, naming both levels. The user chose Quit Anyway. Its last report, an ordinary poll, is at 754.247 s. Heard: the level rose to the knob's −40 dB a few seconds after. |
| 17:56:10 | 955.8 | Step 8b: the app relaunched, with the setting still on. It leased the six at once, each followed by its saved −50 dB. The user moved the slider up to −35 dB, by 1027.9 s. |
| 17:57:29 | 1034.6 | Quit, with no warning. The app's last report is the knob's level, `FF 1F 01 47 AE`, −40.0 dB. Heard: the drop came at once, and nothing changed after. |
| 17:58:27 | 1092.1 | Step 9: relaunched, at −35 dB. The user muted the Right at 1121.8 s and quit at 1125.9 s, with the knob's level last. The app kept the Right's hardware ID, `11 4B EA`. |
| 17:59:33 | 1158.1 | Relaunched. The Right's lease, its level, and then `06 2B 03` at 1158.195 s. No other monitor got a `2B`. Heard: the Right stayed silent, and the popover showed it muted. The user unmuted it at 1185.0 s. |
| 18:00:34 | 1219.4 | Step 10: standby, from the popover. Heard: the music stopped, and the dots showed standby. |
| 18:00:47 | 1232.6 | Wake. Three pairs, then 0.241 s after the last, the level and the pair. All six took new sessions, `08` to `0D`, each with the level right after its ack. Heard: all six came back, but sounded a little different. |
| 18:02:36 | 1341.9 | Step 11: the setting off. The app's last report is the knob's level, −40.0 dB. Heard: a small drop, then nothing. The user then quit the app. |
| 18:03:18 | | Capture stopped. |
| 18:04:59 | | GLM was relaunched, after the capture. Its launch applied the group. Heard: the sound was back to normal. |

## What the run showed

- **The app keeps off the bus while GLM runs, and takes it once GLM quits.** It opened 0.85 s after GLM's last report, before the adapter's own take-over.
- **The monitors let go of GLM's leases about 3 s after GLM stopped.** Its last poll to a monitor was at 182.660 s. Probes at 185.109 s still got `01 7E`, and the one at 185.719 s found a monitor. The app was already polling the adapter, so the adapter never took over.
- **Every lease gets the level first.** All 30 leases, at four launches and a wake, were followed by the level about 1 ms after the ack. The app sets its level at connect, so discovery sends it too.
- **Volume, the knob, mute, mute all, dim, standby, and wake are GLM's frames.** The knob's burst at 417.31 s is `knob-sweep`'s at 19.24 s, at the same level, −41.5 dB. Mute all, unmute all, and dim match `mute-dim`. Standby and the end of the wake match `standby-wake`. Each of the 56 levels is a report GLM sent in `volume-sweep`, and none passed −35 dB, even with the knob at its top stop.
- **The hand-back works both ways.** With the knob above the app's level, the app warned and sent nothing more, and the level rose about 2.6 s later. With the knob below it, the app sent the knob's level as its last report, and nothing changed after.
- **A mute outlasts a relaunch.** The app restated it with `06 2B 03`, right after the Right's lease and level.
- **`QLMAppFirstTests` checks all of it.**

## Surprises

- **A woken monitor plays without the group's settings.** The app's wake sends no group apply, which GLM sends after each wake. After the app's wake, both 8330As' LF output meters read 7 to 8 steps higher, at the same input, and the user heard a difference. GLM's launch applied the group, and the sound came back.
- **At the ceiling, each knob change still sends a burst.** In 13.7 s of turning, 102 bursts went out, 75 of them with the level frame held at −35 dB. System follows the knob to its own level, above the ceiling, and only the frame is capped.
- **The ceiling field saves only on Return.** The user's first −35 dB didn't save, and the ceiling stayed at −20 dB until a second try.
- **The fake bus's monitors stayed in the list.** After the setting went on, its three monitors showed as offline beside the six real ones.
- **The popover names monitors by serial.** The user couldn't tell the Left 8351B from the Right.
- **At launch, only a muted monitor gets a `2B`.** The others get none. A mute outlasts its host, so a monitor another host muted likely stays muted until the app's next round.

## Not explained

The user heard a brief dropout after the level dropped, at the take-over. No monitor was polled from 182.660 to 185.739 s, so telemetry can't show it. Before and after, the input meters held steady. It fell in the window when the monitors dropped GLM's leases and took the app's.
