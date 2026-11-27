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

The tester also sent screenshots from these runs, without saying which run each came from. They
are described here, not added. Frame figures are the title bar's:

- Prison, looking out of a window at the yard, 195.0 ms a frame, 5,030 draws: the yard, the
  buildings, a watchtower and the people in it are drawn in evening light and look whole. The
  room inside is almost black.
- Robbery, 263.3 ms, 4,447 draws: most of the picture is a white, washed-out blur. Characters
  show only as soft shapes, with scattered black and blue blotches and a few sharp fragments.
  This is the "severe corruption and blur" the tester describes. It reads like the washed-out
  prologue on the RTX 3060 Ti 8 GB (R-3, same fork-notes section). A guess: the shapes are there
  but smeared, so a full-screen pass going wrong fits better than missing textures.
- Boat, 201.7 ms, 4,621 draws: the sky, clouds, shore, a bridge, the boat and the people on it
  are drawn; the water is flat white with a few dark specks. That is the "poorly rendered
  water" the tester saw.

So how bad the picture is depends on the place: the prison yard looked whole and the robbery
did not, at similar draw counts.

## The `nvidia-8gb` pair, after the warm-up

Two more runs, same tester, same build, both during the boat mission, hand-played. The shader
warm-up ran before the first; the second used the cache it left. The tester's download is older
than the `nvidia-8gb` profile in the catalog, so they defined the same two switches as an opt-in
profile in `gpu-profiles.local.json`; the second report lists `ASYNC_PRESENT` and
`TEXTURE_STAGE_MB=512` on, with the eight `base` switches.

| Run | Last minute | fps | Median frame | Longest frame | Whole run fps | Whole run median |
|---|---|---|---|---|---|---|
| `base` | 373 in 61.7 s | 6.0 | 148 ms | 1,087 ms | 10.9 | 34 ms |
| `base` and `nvidia-8gb` | 350 in 61.8 s | 5.7 | 157 ms | 545 ms | 10.6 | 33 ms |

- No gain on this card: the median went 148 -> 157 ms. One hand-played pair, so the 9 ms is
  within what a rerun could move. The longest frame halved (1,087 -> 545 ms), but that is one
  frame in a minute, so one pair doesn't make it a result. No crash report in either run.
- On the RTX 3060 Ti 8 GB the same pair took the first room from 312-489 ms to 130 ms
  ([the 8 GB pair note](2026-11-27-nvidia-8gb-pair.md)). That card's baseline was two to three
  times slower, in another scene, with a Ryzen 5 5600 and 16 GB of RAM. A guess: there was more
  to gain there. Nothing here says which difference matters.
- So `nvidia-8gb` has helped on one of the two 8 GB cards measured, and stays opt-in.
- The picture was the same in both runs, and the same as before the warm-up: the water drawn but
  poorly, the boat slightly distorted, heavy stuttering. So at the boat the warm-up did not fix
  the picture. It didn't fix the robbery's either (next section).

## A new game to the robbery, after the warm-up

One more run, same tester, same build, `base` (the eight switches on), after the warm-up, started
as a new game and played through the prison into the robbery, hand-played.

| Span | Frames | fps | Median frame | Longest frame |
|---|---|---|---|---|
| last minute before closing | 183 in 61.8 s | 3.0 | 231 ms | 10,846 ms |
| whole run, menus and loading included | 7,263 in 983.4 s | 7.4 | 34 ms | 10,846 ms |

- It ended with a crash report and exit code -2005270523 (`0x887A0005`, the device removed), as
  the game moved from the robbery to the escape. The tester gives the reason as `0x887A0004`
  (unsupported), but in the device-removed line that code belongs to the missing breadcrumbs
  (DRED off), not to the removal: the RTX 5080 run that found the constant buffer view size
  carried it too, followed by `0x887A0001` (invalid call). So this may be the same cause, the
  view size ([its note](2026-11-27-cbv-64k-limit.md)); a guess until a run with that fix. The
  two RTX 3060 removals in [their note](2026-11-27-rtx3060-12gb-tester-results.md) don't
  show this cause: one gave no reason, the other points to memory. None of the eight earlier runs on
  this card, without the warm-up, lost the device.
- The robbery was still corrupted after the warm-up: the tester saw constant black-and-white
  flashing and about 1 to 4 fps. So the warm-up fixes neither the boat's water nor the
  robbery's picture.
- The tester felt this run was slower than the earlier ones: about 1 to 2 fps in the opening
  scene and 4 to 5 fps at best in the prison. Those are their readings, not report figures.
- Their screenshot, described and not added: in the robbery, 1,426.5 ms a frame and 14,074
  draws, about three times the 4,447 draws of the earlier robbery shot. Most of the picture is
  white glare with soft, washed-out shapes, black cut-out patches where characters stand, and
  bright edges with red and blue fringes on the walls. The same kind of picture as the earlier
  robbery shot, with far more draws.

Not measured: any run with all eight on in the prison, on the same day as runs 1 to 7; the
removal reason on the constant buffer view fix.
