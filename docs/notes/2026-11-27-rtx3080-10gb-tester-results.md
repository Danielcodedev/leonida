# Cards measured: RTX 3080 10 GB

Two reports from one tester (Luce) from the report form, as they gave them. Nothing here quotes
game data.

RTX 3080 10 GB (10,051 MB), Core i5-12400F, 32 GB RAM, driver 621.40, Windows 11 Pro 26H2 build
26300. Build unknown (no git). `base` applied (the eight speed switches on), shader warm-up done,
both runs. Run 1's scene field says only "y"; asked afterwards, the tester said it was the
prologue. Run 2 was in the prologue's first room.

| Run | Span | Frames | fps | Median frame | Longest frame |
|---|---|---|---|---|---|
| 1 | last minute before closing | 483 in 61.0 s | 7.9 | not given | not given |
| 2 | last minute before closing | 398 in 61.1 s | 6.5 | 150 ms | 703 ms |
| 2 | whole run, menus and loading included | 3,531 in 560.3 s | 6.3 | 107 ms | 9,086 ms |

- Run 1 reached us cut off after the frame count, so its median and longest frame, whole-run
  figures and crash line are missing. Run 2 is a new run (other frame counts), not a resend.
- Run 2: no crash report (exit code 0). The tester saw shadows completely black.
- What the tester saw in run 1: the heads of the player character and the other characters were
  not drawn, only parts of the hair, the eyeballs and the inside of the mouth. The RTX 4070
  Laptop 8 GB report in [the laptop note](2026-11-27-rtx-laptop-8gb-tester-reports.md) describes
  the same (hair, eyes, a held phone). Here the warm-up was done and the card has 10 GB, so neither
  a missing warm-up nor an 8 GB card explains it on its own.
- Run 2's 150 ms median in the prologue is far shorter than the RTX 3060 Ti 8 GB's 514 to 1,064 ms
  there ([../fork-notes.md](../fork-notes.md), "Cards measured: RTX 3060 Ti 8 GB"), but those are
  title-bar readings on another build, so the comparison is rough. It is close to the RTX 3080
  12 GB in the first rooms (about 130 to 170 ms, see `gpu-profiles.json`), a different scene.
- Both runs had the same switches, so nothing here says what any switch does on this card.
