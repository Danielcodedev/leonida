# Cards measured: RTX 3060 12 GB

Reports from two testers from the report form, as they gave them. Nothing here quotes game data.
axel_cf attached a file to their first report; it is not added here (logs can quote game data).

- axel_cf: RTX 3060 12 GB (12,115 MB), Core i5-10400F, driver 621.01. RAM and Windows build not
  given. Build unknown (no git).
- Lepsy06: RTX 3060 12 GB (12,108 MB), Core i5-13600KF, 32 GB RAM, driver 621.01, Windows 11 Pro
  for Workstations 25H2 build 26200. Build unknown (no git). `base` applied (the eight speed
  switches on), shader warm-up done, prison hall.

Driver 621.01 is older than the 621.14 to 621.40 on the other cards reported so far.

| Tester | Run | Span | Frames | fps | Median frame | Longest frame |
|---|---|---|---|---|---|---|
| axel_cf | 1 | last minute before closing | 508 in 60.8 s | 8.4 | 58 ms | 1,028 ms |
| axel_cf | 1 | whole run, menus and loading included | 2,863 in 696.3 s | 4.1 | 36 ms | 11,204 ms |
| axel_cf | 2 | last minute before closing | 200 in 64.9 s | 3.1 | 248 ms | 2,032 ms |
| axel_cf | 2 | whole run, menus and loading included | 6,558 in 1,206.3 s | 5.4 | 149 ms | 10,532 ms |
| Lepsy06 | 1 | last minute before closing | 264 in 62.1 s | 4.3 | 238 ms | 754 ms |
| Lepsy06 | 1 | whole run, menus and loading included | 6,687 in 1,188.7 s | 5.6 | 33 ms | 23,369 ms |

- axel_cf run 1: switches, warm-up and scene not given. Its 58 ms last-minute median may not be
  world frames (the menus sit at about 33 ms), so it can't be compared with run 2.
- axel_cf run 2: `base` applied, shader warm-up done, first room and the flashback. No crash
  report (exit code 0). The tester saw textures missing and flashing, and a freeze.
- Lepsy06's run ended with a crash report and exit code -2005270523, which is `0x887A0005`, the
  device removed: the card dropped out of the run. It held about 4 fps before that, and the
  other characters' textures were still loading. The only other device removal in the notes is
  a laptop with `LEONIDA_TEXTURE_RANGE_LOCK=1` ([P-4 note](2026-11-27-p4-texture-range-lock.md)),
  a switch not on here. The cause is unknown.
- Lepsy06's 238 ms on an i5-13600KF is close to axel_cf's 248 ms on an i5-10400F, in different
  scenes. A much faster CPU gave about the same frame time, so the CPU looks less likely to be
  what holds this card back (a guess). Both testers run driver 621.01, so whether the driver
  matters is still not measured; a run on 621.40 would show it.
- Nothing here says what any switch does on this card: every run with known switches had the same
  ones.
