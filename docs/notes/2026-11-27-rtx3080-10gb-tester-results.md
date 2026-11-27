# Cards measured: RTX 3080 10 GB

One tester's report (Luce) from the report form, as they gave it. Nothing here quotes game data.

RTX 3080 10 GB (10,051 MB), Core i5-12400F, 32 GB RAM, driver 621.40, Windows 11 Pro 26H2 build
26300. Build unknown (no git). `base` applied (the eight speed switches on), shader warm-up done.
The scene field says only "y"; asked afterwards, the tester said it was the prologue.

| Span | Frames | fps | Median frame | Longest frame |
|---|---|---|---|---|
| last minute before closing | 483 in 61.0 s | 7.9 | not given | not given |

- The report reached us cut off after the frame count, so the median and longest frame, the
  whole-run figures and whether a crash report was written are missing.
- 7.9 fps is about 126 ms a frame on average, in the prologue. The only other prologue figure is
  the RTX 3060 Ti 8 GB at 514 to 1,064 ms a frame ([../fork-notes.md](../fork-notes.md), "Cards
  measured: RTX 3060 Ti 8 GB"). The RTX 3080 12 GB figures in `gpu-profiles.json` (about 130 to
  170 ms) come from the first rooms, a different scene. An average is not a median, so both
  comparisons are rough.
- What the tester saw in the prologue: the heads of the player character and the other characters
  were not drawn, only parts of the hair, the eyeballs and the inside of the mouth. The RTX 4070
  Laptop 8 GB report in [the laptop note](2026-11-27-rtx-laptop-8gb-tester-reports.md) describes
  the same (hair, eyes, a held phone). Here the warm-up was done and the card has 10 GB, so neither
  a missing warm-up nor an 8 GB card explains it on its own.
- One run, switches on only, so nothing here says what any switch does on this card.
