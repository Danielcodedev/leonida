# Cards measured: RX 9070 XT 16 GB

One tester's report (FallingLizard) from the report form, as they gave it. It was filed as a crash
report, but no crash report was written. Nothing here quotes game data.

Radeon RX 9070 XT 16 GB (16,191 MB), Ryzen 7 9700X, 31 GB RAM, Adrenalin 26.11.2, Windows 11 Home
26H2 build 26300. Build `8bfde9e` "with local changes": that commit is not in this repository's
history or in any fork fetched here, so the build can't be identified. `base` applied (the eight
speed switches on), shader warm-up done, first room.

| Span | Frames | fps | Median frame | Longest frame |
|---|---|---|---|---|
| last minute before closing | 27 in 61.0 s | 0.4 | 1,993 ms | 8,343 ms |
| whole run, menus and loading included | 2,147 in 484.1 s | 4.4 | 33 ms | 18,670 ms |

- No crash report (exit code 0). The tester saw black textures, and at the end only sound with the
  picture at about 0.1 fps.
- 1,993 ms is by far the slowest first-room median reported: the NVIDIA cards in the notes sit
  between 130 and 250 ms there. With 27 frames in the last minute the game was close to stalled,
  not just slow (a guess).
- This is the first AMD card with frame figures in the notes. [../fork-notes.md](../fork-notes.md)
  records AMD's shader compiler crashing on pipeline workers on an RX 9070 XT; that crash is now
  caught and the pipeline's draws are dropped, which could leave surfaces black. A guess: nothing
  in this report shows it.
- The unknown build and the local changes mean this can't be put on the card yet. A run on a
  fresh download of `main`, after the warm-up, in the first room, would tell.
- One run, switches on only, so nothing here says what any switch does on this card.
