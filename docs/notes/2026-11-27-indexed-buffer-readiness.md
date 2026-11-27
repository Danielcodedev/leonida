# R-9: retain indexed-buffer readiness per command recording

Shaders that compute their descriptor indices need the buffer views of their
bound heap made ready. The old path schedules their deferred refreshes only
in the first recording of a frame. Another recording can be submitted first,
or the first can be abandoned, leaving the consumer without those refreshes.
A single per-list key also skips retention of a second heap's stride table.

`LEONIDA_HEAP_READINESS=1` opts into per-recording readiness. It is off by
default. Each heap owns a cache of the exact host copies its descriptors show,
with a durable identity and a generation that changes when the resolved copies
or ranges change. Unchanged descriptors reuse the cached span allocation;
changed slots are resolved incrementally, with the existing periodic full
check for invalidations that do not rewrite a descriptor. Every consuming
recording retains its stride table and schedules the cached ranges through
ordinary deferred refreshes. Known and unknown title-writing steps invalidate
that recording's readiness. The normal batch merging, dirty-page tracking,
readback ordering and outstanding-writer checks therefore see these accesses.

This can increase refresh work, particularly for memory without write watching.
The opt-in does not perform a full descriptor scan for every list. It does not
change the legacy path when disabled or multiply the texture-upload passes.

Limits remain: descriptors rewritten after their final recorded bind may still
need different submission-time handling. Deferred CPU work is prepared before
native GPU lists run, so this does not establish a CPU/GPU boundary between two
draws in one native list. It does not repair all resource-state tracking,
declare writes through dynamically indexed UAVs, or prove that a particular
game artifact or device fault was caused by missing readiness.

Seventeen CPU regressions exercise the production cache and recording policy:
reordered or abandoned recordings, two heaps in one recording, lifetime and identity
reuse, changed and unchanged snapshots, periodic copy replacement, concurrent
revision publication, and title-write invalidation. An independent full-table
oracle also matched 10,000 deterministic update batches across 512 slots and
32 copies, including old snapshot ownership and generation reuse. Strict Windows
workspace Clippy passes for all targets, with default and all features.
The full Linux GPU-crate test command cannot compile on this
baseline: unguarded references to Windows-only texture, host and host_resource
code fail identically before and after this change. The focused production
cache/recording module tests run natively without those platform dependencies.

Five authored device regressions exercise actual title heaps, mirrored SRVs,
`State::heap_buffers`, deferred refreshes and synchronous or late submission.
Each data case first completes a GPU read of 13, advances the production frame,
writes 37 into title memory, then records A and B in the same frame. With the
switch off, submitting only B synchronously or through late submission, or
abandoning A before submitting B, reads stale 13. With it on, all three read 37.
Submitting A first reads 37 in both modes. The two-heap case fails safely before
submission with the switch off because the second stride table is not retained;
with it on, both tables remain readable as 4 and 12 after the title heaps drop.

All ten cases used the same executable in separate processes on an RTX 5090,
NVIDIA 580.173.02, Pop!_OS, Proton 11.0 and vkd3d-proton ec207 with the allocator
correction from vkd3d-proton #3532. Every readback followed an actual completed
native fence. Core and synchronization validation reported only the known
initialization canary; no new errors occurred. Device tests require explicit
test and adapter opt-ins and otherwise return before creating a device. These
cases prove the tested readiness and ownership behavior.

Two bounded game runs used the same diagnostics executable, existing saves,
runtime and validation settings, changing only this switch. Both reached the
first dense world frame plus six captured frames with the same existing
validation-error categories and no sampled prolonged native wait or driver
fault. The courtyard still showed rectangular patches on foreground characters
and other surfaces in both runs. This does not establish sustained stability,
correct rendering or 30 fps.

The enabled path also adds substantial refresh work. The recorded early-world
windows contained these per-frame figures:

| Diagnostic counter | Off, three-frame window | On, four-frame window |
|---|---:|---:|
| Deferred refresh requests | 14,548 | 167,433 |
| Logical requested ranges, MB | 14,363.1 | 89,226.5 |
| Bytes checked, MB | 5,763.5 | 29,436.1 |
| Copy preparation, ms | 184.3 | 641.1 |

These windows differ in scene timing and workload; the range sizes are not
uploaded bytes, and these are not steady-state or causal frame-rate figures.
The switch remains off by default. Existing batch coalescing remains in use;
`LEONIDA_REFRESH_ONCE` is not enabled implicitly, since broader reuse needs a
freshness proof across pending writers, asynchronous copy-back and aliases.
Device and game runs used the readiness core before the later PR #34 texture
range-lock change. Source review found no specific integration conflict; the
combined upstream tree was not used for these game measurements.

A local optimized Rust 1.98.1 metadata-only run resolved 96,485 authored views
once, then scheduled 230,469 spans across 51 recordings, each using the heap
four times. Discovery took 14.5 ms and scheduling 11.5 ms; 1,000 further changes
inside unchanged copy bounds took 27 microseconds and reused the snapshot.
This exercises the actual generic cache and recording gate plus equivalent
span metadata, without D3D calls, dirty-page queries, Shadow updates or copies.
It is not a frame-time measurement. No frame-rate improvement is claimed.

Implementation, tests and source review were AI-assisted.
