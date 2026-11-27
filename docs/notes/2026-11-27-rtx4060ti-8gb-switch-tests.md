# Cards measured: RTX 4060 Ti 8 GB, the speed switches one at a time

Eight reports from one tester (amineourabi0) from the report form, as they gave them, with their
own summary. Nothing here quotes game data.

RTX 4060 Ti 8 GB (7,949 MB), Core i5-14400F, 32 GB RAM, driver 621.40, Windows 11 Pro 26H2 build
26300. Build unknown (no git). Each run had `base` with one of its eight switches set to 0 and the
other seven on. **No shader warm-up** in any run. Hand-played, one run per switch, no crash report
(exit code 0 in all eight). Runs 1 to 7 were in the prison hallway after the secretary and into the
robbery; run 8 went on to the beach before the boat mission.

This follows the same tester's earlier pair in [../fork-notes.md](../fork-notes.md) ("Cards
measured: RTX 4070 Ti SUPER 16 GB, RTX 4060 Ti 8 GB"): all eight switches on, 2.7 fps in the last
minute; all off, 4.6 fps. That pair was in the first gameplay area after the opening cutscenes;
whether that is the same place as runs 1 to 7 is not known.

| Run | Switch off | Last minute | fps | Median frame | Longest frame | Whole run fps | Whole run median |
|---|---|---|---|---|---|---|---|
| 1 | `ASYNC_SUBMIT` | 169 in 64.1 s | 2.6 | 222 ms | 2,752 ms | 7.1 | 42 ms |
| 2 | `QUEUE2` | 265 in 61.5 s | 4.3 | 220 ms | 664 ms | 7.6 | 66 ms |
| 3 | `INDIRECT_WINDOW` | 75 in 61.4 s | 1.2 | 417 ms | 4,519 ms | 6.5 | 34 ms |
| 4 | `COPY_PLAIN` | 197 in 62.4 s | 3.2 | 213 ms | 2,778 ms | 7.0 | 111 ms |
| 5 | `JOIN_PARTS` | 248 in 62.1 s | 4.0 | 220 ms | 4,322 ms | 8.3 | 70 ms |
| 6 | `BACK_OWN_VIEW` | 227 in 62.2 s | 3.6 | 250 ms | 1,793 ms | 7.8 | 85 ms |
| 7 | `INDIRECT_GATHER` | 238 in 68.0 s | 3.5 | 181 ms | 6,686 ms | 9.6 | 34 ms |
| 8 | `CARD_REHASH_RUNS` | 510 in 61.2 s | 8.3 | 68 ms | 1,089 ms | 7.5 | 45 ms |

What it shows:

- `INDIRECT_WINDOW` off is the one clear result: 417 ms median against 181 to 250 ms for the other
  six in the same place, and the tester saw the prison stay below 4 fps. Keep it on for this card,
  as `base` has it.
- The other six land within 181 to 250 ms of each other, and the tester's own fps ranges for them
  overlap. With one hand-played run each, none of them can be called a cost or a gain here.
- None of the seven reaches the earlier all-off 4.6 fps; the nearest are `QUEUE2` off (4.3) and
  `JOIN_PARTS` off (4.0). So no single switch explains the earlier on/off gap. A guess: the gap
  was that pair's run-to-run spread, or it comes from more than one switch together.
- Run 8 was in a different place (beach and boat, where the tester saw a clearer picture than in
  the robbery), so it says nothing about `CARD_REHASH_RUNS`.
- No warm-up means shaders were translated during the runs, and the cache keeps them, so the
  earlier runs paid more of that than the later ones (runs went in the order of the table). The
  darkness and missing detail the tester saw read like the RTX 3060 Ti 8 GB without the warm-up
  (R-2, same fork-notes section); a guess until a run after the warm-up shows otherwise.

Not measured: any run with all eight on, in the same place on the same day; any run after the
warm-up; the `nvidia-8gb` profile.
