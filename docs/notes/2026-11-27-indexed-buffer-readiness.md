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

Seventeen CPU regressions exercise the production cache and recording policy: reordered
or abandoned recordings, two heaps in one recording, lifetime and identity
reuse, changed and unchanged snapshots, periodic copy replacement, concurrent
revision publication, and title-write invalidation. Device and gameplay
validation are still required. Windows GPU-crate Clippy passes for all targets
and features. The full Linux GPU-crate test command cannot compile on this
baseline: unguarded references to Windows-only texture, host and host_resource
code fail identically before and after this change. The focused production
cache/recording module tests run natively without those platform dependencies.

A local optimized Rust 1.98.1 metadata-only run resolved 96,485 authored views
once, then scheduled 230,469 spans across 51 recordings, each using the heap
four times. Discovery took 14.5 ms and scheduling 11.5 ms; 1,000 further changes
inside unchanged copy bounds took 27 microseconds and reused the snapshot.
This exercises the actual generic cache and recording gate plus equivalent
span metadata, without D3D calls, dirty-page queries, Shadow updates or copies.
It is not a frame-time measurement. No frame-rate improvement is claimed.

Implementation, tests and source review were AI-assisted.
