# qlm-standby-discover

qlm's discovery with all six monitors in standby, not a GLM scenario. Recorded 2026-10-30 through the Raspberry Pi 5 inline proxy (usb-proxy with `tools/pi/usb-proxy.patch`), on usbmon1. The adapter was device 1:4. No mic, and the volume knob on the adapter. The monitors and the knob were turned down low first.

`qlmctl` was built from `e55a0ba`, on main. It ran only `info`, `discover --setup Main.sam`, and `poll --seconds 10` over the adapter, with GLM quit. GLM put the monitors in standby first.

| Time (EDT) | Seconds | What happened |
| --- | --- | --- |
| 10:56:59 | | GLM 5 opened, before the capture. |
| 10:57:20 | 0 | Capture started. GLM was idle, with the monitors on and leased as `02` to `07`. |
| 10:57:50 | 30.4 | Standby from GLM: broadcast `3A 03 02` twice, then `3A 03 00` twice. |
| 10:58:00 | 40.7 | GLM was told to quit. Its last report, an ordinary adapter poll, is at 40.73 s. It exited within two seconds and left no HID client. |
| 10:58:56 | | `qlmctl info` refused with exit 69: Spotify held the adapter. Nothing was sent. |
| 11:00:12 | | Spotify was quit. No client was left on the adapter. |
| 11:00:15 | 175.4 | `qlmctl info`. |
| 11:01:30 | 250.3 | `qlmctl discover --setup Main.sam`. |
| 11:02:58 | 338.4 | `qlmctl poll --seconds 10`, to 348.4 s. |
| 11:04:16 | 416.1 | `qlmctl discover --setup Main.sam` again. |
| 11:04:21 | | Capture stopped. GLM was relaunched after it, and its wake brought the monitors back. |

Every command that ran exited 0 and printed `seized`. All six monitors stayed in standby throughout. No one heard a level change or a click, and no monitor woke. The knob read −93.6 dB. It drifts a little at rest, as it does under GLM.

## Spotify

Spotify held an `AppleUSBHostDeviceUserClient` on the adapter's USB device. qlm's host check refuses any other holder, so `info` refused and sent nothing. GLM ran alongside that client without trouble. Spotify had been opened at 10:29, after `qlm-first-discover`.

## Standby answers without a wake

All six answered everything qlm sent, the two 8351B and the other four alike: the probe, the lease, `39`, `19 01`, and `08`. qlm sent no wake. `discover` printed each as `standby`, with its temperature:

| Session | Model | Temperature |
| --- | --- | --- |
| `02` | 8330A | 29 C |
| `03` | 8351B | 42 C |
| `04` | 8330A | 32 C |
| `05` | 7370A | 46 C |
| `06` | 8351B | 46 C |
| `07` | 7350A | 47 C |

A reply in standby drops the meter tags (`42` to `46`) and the sensor tags (`81` to `83`). `47` reads `02`, not `01`, and `84`'s first byte reads `03`, not the class. So `discover` prints the class as `?`.

## What qlm sent

qlm sent only frames GLM sends, as in `qlm-first-discover`: the adapter's `01 08`, `01 39`, and `01 19 01`, the probe, the lease, and each monitor's `39`, `19 01`, and `08`. It sent no wake, no volume, and no sync query. Every request got a reply. Every `01 08` was one of a pair, and `01 39` went once per command.

In standby, a monitor sometimes misses a request, and the adapter answers `01 7E`. GLM's polls see the same: once in its 10 s of standby here, and eight times in `standby-wake`.

- **poll:** `04` missed one poll, and `07` missed two. Each answered its next one. `poll` printed these as `missed`.
- **The second discover:** `02` missed its first `08`. The 7370A, `05`, missed `39` and `19 01` right after its lease. qlm asked both again in the next cycle and got them.

| The cycle | qlm's `poll`, 338.9–348.4 s | GLM in standby, 30.6–40.8 s |
| --- | --- | --- |
| Probe spacing | 0.570 s | 0.571 s |
| Adapter `01 08` pairs | every 0.107 s | every 0.114 s |
| Volume `FF 1F` | none | one per cycle |
| Polls answered | full 58, bare `09` 41, `01 7E` 3 | full 59, bare `09` 47, `01 7E` 1 |

## Leases

GLM kept its leases through standby. No monitor answered its probe in the 10 s before it quit. That differs from `standby-wake`, where an 8351B answered the probe and GLM leased it again every 3 s.

210 s after GLM's last report, all six answered qlm's probe, so they had dropped GLM's leases. They had dropped `discover`'s by `poll`, 88 s later, and `poll`'s by the second `discover`, 68 s later. While `poll` ran, qlm kept all six leases, and every later probe got `01 7E`.
