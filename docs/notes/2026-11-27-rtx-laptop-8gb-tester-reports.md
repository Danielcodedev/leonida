# Cards measured: RTX 5070 Laptop 8 GB, RTX 4070 Laptop 8 GB

Two testers' reports from the report form, as they gave them. Nothing here quotes game data.

RTX 5070 Laptop GPU 8 GB (7,891 MB), Core Ultra 9 275HX, 31 GB RAM, driver 621.14, Windows 11
Home 26H2 build 26300, tester vladisthelad. Build unknown (no git). `base` applied (the eight
speed switches on), shader warm-up done; the scene was not given.

| Span | Frames | fps | Median frame | Longest frame |
|---|---|---|---|---|
| last minute before closing | 847 in 61.2 s | 13.8 | 66 ms | 642 ms |
| whole run, menus and loading included | 5,563 in 883.5 s | 6.3 | 33 ms | 11,180 ms |

- No crash report (exit code 0). One run, switches on only, so nothing here says what the
  switches do on this card.
- 66 ms is the shortest last-minute median reported so far, but with no scene given it may not
  be world frames (the menus sit at 33 ms). A rerun in the first gameplay area would tell.

RTX 4070 Laptop GPU 8 GB (7,948 MB), Core i7-13700H, driver 621.24, tester rushbcykab. Crash
report, "just launch the game"; profiles, warm-up and build not given:

- The picture was white at the start of the opening cutscene. After it most surfaces were black
  and only a few small parts of a character (hair, eyes, a held phone) were drawn, at about
  2 fps, and then the game crashed.
- This reads like the RTX 3060 Ti 8 GB section of [../fork-notes.md](../fork-notes.md) ("Cards
  measured: RTX 3060 Ti 8 GB"): without the warm-up the first room was black (R-2), and on 8 GB
  the title asks for more texture data than the card holds. A guess until the tester confirms
  whether the warm-up ran; the crash itself needs the `crashes.log` lines (addresses only) to say
  more.
