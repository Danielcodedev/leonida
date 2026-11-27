# R-7: single-wave Wave64 groups under `LEONIDA_WAVE64_GROUPS=1` (experimental, off by default)

`LEONIDA_WAVE64_GROUPS=1` stays off by default and keeps the legacy retry order: any usable
legacy result keeps its original bytes and binding contract. With the switch off nothing changes.

On a Wave32-only host (RTX 5060 Laptop), 8 compute pipelines were refused with `E_INVALIDARG`
because they still asked for `WaveSize(64)`. The independent-wave fallback refused all of them
silently. Logging each refusal reason showed:

| Shaders | Group | Why `admit` refused |
|---|---|---|
| `369cbe906ea72764` | 64x1x1, LDS | `ds_add_rtn_u32` |
| `2cc4c197ee29e291` | 64 threads | `buffer_atomic_add`, then `image_atomic_or` |
| `5dc3b25986622949`, `6f225b641c5b0708`, `926c46bab3b86bd6` | 8x8x1, LDS | `ds_min_u32`/`ds_max_u32`, then `s_setreg_imm32_b32 hwreg(MODE, 2, 2), 0` |
| `2da4beb386509b77`, `02384a60fda6f2d0`, `6b82bc7d22016cb5` | 256, 128 and 1024 threads with LDS | multi-wave LDS (out of scope) |

A 64-thread group is one original Wave64, replayed once (`wave_count() == 1`) on a `[64, 1, 1]`
physical group, so its dispatch shape and its LDS stay the original's:

- `IndependentWaves::new` accepts 64 to 1,024 threads in multiples of 64.
- For a single-wave group only, `eligibility` admits:
  - non-zero LDS, `s_barrier`, and non-GDS `ds_read*`/`ds_write*`;
  - integer LDS atomics (`ds_{add,sub,and,or,xor,min,max}` on 32-bit integers, `ds_wrxchg`,
    `ds_cmpst`, with or without `_rtn`). `Lower::ds` lowers them to group-shared
    `atomicrmw`/`cmpxchg`, which are atomic across the whole host group however it is split;
  - `buffer_atomic_*` and `image_atomic_*` (GLC allowed: it only selects the returned value);
  - `s_setreg_imm32_b32` writing 0 into MODE's FP_ROUND bits [3:0] (`ir::sets_nearest_rounding`).
    That is round to nearest even, the only rounding DXIL has, so the independent IR drops it.
    The ordinary path still refuses it; other MODE writes stay refused everywhere.
- Multi-wave groups still refuse LDS, `s_barrier` and every atomic. Float LDS atomics, GDS,
  `ds_append`/`ds_consume`, `ds_*_src2*` and `ds_*_addtid*` stay refused for all sizes.
- `independent_bound.hlsl` lowers its indirect snapshot floor from `128u` to `64u` so indirect
  dispatches of 64-thread contracts are not clamped to zero.

Tests: `independent_tests.rs` covers 64x1x1 and 8x8x1 admission with LDS, barrier and lane
operations, the allowed LDS forms including integer atomics, the refused forms, 128-thread
refusal, and which MODE writes are dropped.

Host measurement (RTX 5060 Laptop 8 GB, 3-minute session, first run after the change so every
shader is translated again; no fps comparison): 3 compute pipelines refused instead of 8 (the
three multi-wave groups above), no device loss, no crash report.

Then 9-minute sessions on the same build, Series X profile, the first gameplay room, median frame
time over the 50th to 99th frame-log samples (the means are skewed by streaming stalls of up to
4.5 s that come in runs with and without the switch):

| Run | Switch | Refused | Median frame time |
|---|---|---|---|
| 1 | off | 8 | 288 ms |
| 2 | off | 8 | 311 ms |
| 3 | on | 3 | 327 ms |
| 4 | on | 3 | 330 ms |
| 5 | on | 3 | 327 ms |

The five passes that now run cost about 15-40 ms a frame on this card, so this is a picture
change, not a speed-up. Skipping the three min/max shaders with `LEONIDA_SKIP_PIPELINES` gave
277 ms, and skipping the other two gave 292 ms, one run each.

Picture, judged by eye from frames at 5, 7 and 8.5 minutes: with the switch off, the character's
silhouette against the window has blocky stair-steps and the shaded side of the yard building has
jagged bright blotches; with it on, both are smooth and the room sits in shadow. In one of the
three runs with the switch on (and in none of the two runs with only some of the five shaders),
a ragged bright patch with sky colours replaced part of the far-left wall at 7 and 8.5 minutes,
with a bright slit under the window. It did not come back in the other runs, so its cause is
unknown. Other artefacts (missing window mesh, bright speckles, red blocks on the character)
appear with the switch off too and change from run to run with what has streamed in.
