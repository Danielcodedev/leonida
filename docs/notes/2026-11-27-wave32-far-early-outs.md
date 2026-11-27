# R-7: tiled cascade shadows on 32-lane hosts (LEONIDA_WAVE_MORE_SKIPS)

On a card whose waves have 32 lanes (NVIDIA), a console wave64 compute program runs as two host
waves, and its cross-lane code has to sit where every lane runs. The translator gets there by
leaving out the program's early-outs and skips (`ir::without_early_outs`, `ir::without_skips`).
Two shapes of the tiled cascade-shadow programs got past that:

- An early-out to an end too far for a branch's 16-bit offset: `s_cbranch_execnz` over a far
  jump (`s_getpc_b64`, an add, `s_setpc_b64`) to a block that only ends the program. It is now
  left out like the near `s_cbranch_execz` one. A far jump that does any other work, or whose
  target does, stays, and so does an `s_cbranch_execnz` that branches back: that is a loop's
  back edge, and leaving it out would take away the loop's only exit. (That check is not in
  4fd34fd; this tree adds it with a test.)
- In the deep skip form, a scalar phi whose arguments all come to one value (a join of branches
  that left a parked scalar alone) now counts as a copy of that value, as a plain move already
  did.

Both are from Belobug/VIctory-Belobug-AMD 4fd34fd by sawetco (their PR #82, merged as 0cb1372),
which adapted them from fxceless/victory-fork eaeb8f1 by Bruno Magalhães (victory-fork #1002).
Belobug's tests came along in `emit/wave64_tests.rs`, except one about parked pairs tracked by
lifetime: this tree pairs parked lanes over the whole program, which that commit did not change.

A limit this makes no worse in kind but reaches more often: a skipped region is left out only
when the join sees no scalar it changed, and nothing checks the region for writes that ignore
EXEC (`v_writelane_b32` to a VGPR that is not a parked lane, scalar stores and atomics,
`s_sendmsg`). The deep form already had that on `main`; the phi copies let it leave out more
regions. Nothing shows that any of the five programs below has such a write (a guess, not
checked).

**Switch:** `LEONIDA_WAVE_MORE_SKIPS=1`, off by default, read in `emit::emit` and part of the
shader cache key. It is a switch because it changes the output of programs that translate
without it (below).

## Measured

RTX 3080 12 GB, driver 621.24, Ryzen 7 7800X3D. `leonida translate --list` and
`translate --validate --list` (dxil.dll from Windows SDK 10.0.26100.0) with
`LEONIDA_HOST_MAX_WAVE=32`, this change against `main` at 016bf95a; emitted outputs compared
byte for byte through `LEONIDA_EMIT_DUMP`.

| | `main` | switch off | switch on |
|---|---|---|---|
| compute programs emitted, of 2734 | 2730 | 2730 | 2731 |
| compute programs validated | 2730 | 2730 | 2731 |
| outputs that differ from `main`, of 25754 | | 0 | 4 |

Vertex, pixel and mesh counts are the same in all three (14259 of 14259 emitted and validated;
8765 of 8765 mesh emitted, 8694 validated).

With the switch on:

- `cascadeshadows_rendering:CS_ShadowRenderTiledCascadesAlphaCBPPPC` (f133e35efed2a48a) translates
  and validates. On `main` it fails with "a lane mask exchanged where not every lane runs", and
  its dispatch is dropped in every run.
- Four programs that `main` translates through approximate local waves (each 32-lane half
  giving its own wave results) take the exact "without skips, scalars followed" form instead,
  and validate: `CS_ShadowRenderTiledCascadesPPPC` (ce79e9eba7ae0348),
  `CS_ShadowRenderTiledCascadesCBPPPC` (20b78ee12ecdb57d), `CS_ShadowRenderTiledMiscAlphaPPPC`
  (fa0bd10a35bfef3c) and `indirect_diffuse_lighting:CS_ResolveVBuffer_Voxels` (a893b565f10994b2).
  The exact form costs group barriers.

The check that the far branch goes forward changes no title output: with the switch on, all
25755 dumped outputs are the same bytes with and without it.

`cargo test -p leonida-shader`: 243 passed, 3 ignored; the far early-out test ran on the RTX 3080
and gave the console's count over both halves in every case.

### In game

Same PC, 2026-11-27: four runs of `scripts/measure-run.ps1` on the diagnostics build, off and
`LEONIDA_WAVE_MORE_SKIPS=1` taking turns, the shader cache warmed with the switch set.
Milliseconds a frame:

| run | median frame | card | preparing | end |
|---|---|---|---|---|
| off | 154.5 | 35.8 | 83.9 | ran its time |
| on | 2023 (9 frame lines) | 26.7 | 908.2 | lost the device |
| off | 155 | 36.5 | 81.7 | ran its time |
| on | 143 | 43.4 | 69.4 | ran its time |

`f133e35efed2a48a` translates in game and its dispatch is no longer dropped. One of the two runs
with the switch lost the device, and a run of the same day without any test switch
(`perf/thin-line` series) lost it too, so one run does not tell whether the switch is the cause.
The 143 against 155 ms is within what runs differ by here (about 5 ms, more in this series). All
runs stayed in the opening's cutscenes, so whether this changes the dark diamond patches on the
water outside the prison (the guess under test) is still unknown.
