# Cards measured: RTX 3060 12 GB

Two reports from one tester (axel_cf) from the report form, as they gave them. Nothing here quotes
game data. The tester attached a file to the first report; it is not added here (logs can quote
game data).

RTX 3060 12 GB (12,115 MB), Core i5-10400F, driver 621.01 (older than the 621.14 to 621.40 on the
other cards reported so far). RAM and Windows build not given. Build unknown (no git).

| Run | Span | Frames | fps | Median frame | Longest frame |
|---|---|---|---|---|---|
| 1 | last minute before closing | 508 in 60.8 s | 8.4 | 58 ms | 1,028 ms |
| 1 | whole run, menus and loading included | 2,863 in 696.3 s | 4.1 | 36 ms | 11,204 ms |
| 2 | last minute before closing | 200 in 64.9 s | 3.1 | 248 ms | 2,032 ms |
| 2 | whole run, menus and loading included | 6,558 in 1,206.3 s | 5.4 | 149 ms | 10,532 ms |

- Run 1: switches, warm-up and scene not given.
- Run 2: `base` applied (the eight speed switches on), shader warm-up done, first room and the
  flashback. No crash report (exit code 0). The tester saw textures missing and flashing, and a
  freeze.
- The two runs can't be compared with each other: run 1 gives no switches or scene, and its 58 ms
  last-minute median may not be world frames (the menus sit at about 33 ms). Run 2's 248 ms is
  slower than the RTX 3080 12 GB in the first rooms (about 130 to 170 ms usual frame, see
  `gpu-profiles.json`), on a slower CPU. A guess: the CPU and the older driver both play a part;
  nothing here separates them.
- Nothing here says what any switch does on this card: every run with known switches had the same
  ones. A run with the driver updated to 621.40 would show whether the driver matters.
