# qlm-first-discover

qlm's first run on the adapter, not a GLM scenario. Recorded 2026-10-30 through the Raspberry Pi 5 inline proxy (usb-proxy with `tools/pi/usb-proxy.patch`), on usbmon1. The adapter was device 1:4. Monitors on, no mic, and the volume knob on the adapter. The monitors and the knob were turned down low first.

`qlmctl` was built from `fce5531`, PR #12's head. It ran `info`, `discover --setup Main.sam`, and `poll --seconds 10` over the adapter, with GLM quit. An earlier run on `c1204ed` was discarded.

| Time (EDT) | Seconds | What happened |
| --- | --- | --- |
| 09:18:41 | | GLM 5 opened, before the capture. |
| 09:18:51 | | `qlmctl info` with GLM open. It refused with exit 69 and sent nothing. |
| 09:18:54 | 0 | Capture started. GLM was idle, with the monitors leased as `02` to `07`. |
| 09:19:09 | 14.5 | GLM was told to quit. Its last report, an ordinary adapter poll, is at 14.45 s. It exited within a second and left no HID client. |
| 09:19:19 | 24.9 | `qlmctl info`. |
| 09:19:51 | 56.4 | `qlmctl discover --setup Main.sam`. |
| 09:20:14 | 79.6 | `qlmctl poll --seconds 10`, to 89.6 s. |
| 09:20:28 | | Capture stopped. GLM was relaunched after it. |

Every command exited 0 and printed `seized`, so IOKit let qlm seize the adapter. No one heard a level jump or a click, and no monitor changed state.

## What qlm sent

qlm sent only frames GLM sends: the adapter's `01 08`, `01 39`, and `01 19 01`, the probe `FF FE`, the lease `F0 02`, and each monitor's `39`, `19 01`, and `08`. It sent no wake, no volume, and no sync query. Every request got its reply.

- **info** (24.9 s): `01 08` twice, `01 39`, and `01 19 01`. GLM opens with the same, plus `01 22` (`startup-idle`, 7.29 s). The replies match `startup-idle` byte for byte, but for the knob position: −95.8 dB here, and −100.4 dB there.
- **discover** (56.4 s): the same opening, then a probe, a lease, and the monitor's `39`, `19 01`, and `08`, once per monitor, until the probe got `01 7E`. All six answered without a wake. They came in `startup-idle`'s order and got its IDs, `02` to `07`. qlm matched each to `Main.sam` by hardware ID.
- **GLM's discovery differs in order.** It leases all six first, then sends each `39`, then `39` and `19 01` again (`startup-idle`, 8.42 s). Before it, GLM also sends the wake (`FF 3A 03 7F`, `FF 3A 03 01`), `01 51 82`, `FF 2D 00`, `FF 3D 00`, its volume (`FF 1F`), and `01 2B 00`. qlm sends none of them.
- **poll** (79.6 s): the same opening and discovery, then the cycle.

| The cycle | qlm's `poll`, 80.2–89.7 s | GLM here, 0–14.4 s | GLM in `startup-idle`, 20–30 s |
| --- | --- | --- | --- |
| Probe spacing | 0.569 s | 0.564 s | 0.569 s |
| Adapter `01 08` pairs | every 0.107 s | every 0.113 s | every 0.114 s |
| Volume `FF 1F` | none | one per cycle | one per cycle |
| Polls answered with a bare `09` | 42 of 102 | 65 of 150 | 46 of 108 |
| Unanswered requests | 0 | 0 | 0 |

No sync went out. Every `01 08` was one of a pair, and `01 39` went once per command. So no request timed out, and no reply was unreadable.

## Leases

GLM held `02` to `07` when it quit. 42 s after its last report, all six answered qlm's probe, so they had dropped GLM's leases. By `poll`, 23 s after `discover`, they had dropped qlm's too. USB cannot show why. The adapter's takeover, about 2.6 s after the host goes quiet, is a likely cause.

## Not covered

Every monitor was on. Whether a monitor in standby answers without GLM's wake is still open.
