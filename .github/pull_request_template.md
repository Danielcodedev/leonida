<!--
Title: the TODO ID first (`P-3: ...`), or a Conventional Commit for work with no ID.
Never attach logs, screenshots, frame shots or captures: they can quote game data. Post figures and words.
-->

## What changed

<!-- One or two sentences. The TODO row it closes, or the upstream hash it brings in. -->

## How it was tested

Pick one, and delete the others:

- [ ] **Played:** I ran the game with this change and played it (fill in Playtest below).
- [ ] **Unattended runs:** `scripts\measure-run.ps1` before and after (fill in Playtest below).
- [ ] **Not run in game:** tests only. Why: <!-- e.g. tooling, docs, a code path the game does not reach yet -->

Checks run on this branch:

- [ ] `cargo test --workspace --locked`: no new failure compared with `main`
- [ ] `cargo clippy --workspace --all-targets --locked -- -D warnings`
- [ ] `cargo clippy --workspace --all-targets --all-features --locked -- -D warnings`
- [ ] `cargo xtask policy`

## Playtest

<!-- Skip this section only for "Not run in game". -->

| | |
|---|---|
| GPU and driver | |
| CPU, RAM | |
| Windows or Wine/Proton version | |
| Console profile | Series X / Series S |
| Where in the game | |
| How long | |
| Frame rate or frame time before (`main`) | |
| Frame rate or frame time after (this branch) | |

- [ ] Before and after were measured in the same place, and not on the first run after a shader change
- [ ] No crash report was written and the device was not lost
- [ ] The picture looks the same or better (say what changed, in words):

<!-- Anything that went wrong, even if it also happens on main. -->

## AI

- [ ] AI-assisted (say which parts)
