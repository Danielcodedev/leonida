# Notes

What the fork measured and changed, one file per change. Older notes, up to 2026-11-27, are in
[../fork-notes.md](../fork-notes.md).

## Adding a note

Add a new file here in the pull request that makes the change:

- **Name:** `YYYY-MM-DD-short-name.md`: the day you open the pull request and a few lowercase words joined
  by hyphens, for example `2026-11-27-null-cbv.md`. The names sort by date, so the newest notes are last.
- **Title:** the first line is `# ` and what changed, with the TODO ID when there is one, for example
  `# R-7: an unread input takes the mode read in its register`.
- **Body:** what changed and why; the switch that turns it on, if there is one, and whether it is off by
  default; and what was measured: card, CPU, driver, scene, and the figures before and after. Say plainly
  what was not measured.
- **Figures and words only.** No logs, screenshots or anything quoted from the game
  ([asset policy](../asset-policy.md)).

Tester results for a card go in a note of their own too. To correct an old note, edit that note. Don't keep a
list of notes in another file: a list every pull request adds to is what made them all conflict before.