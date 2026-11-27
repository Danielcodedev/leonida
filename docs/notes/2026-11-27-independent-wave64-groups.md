# R-7: independent Wave64 groups (experimental, off by default)

`LEONIDA_WAVE64_GROUPS=1` enables an additional compute translation attempt on hosts with
32-lane waves. An eligible original group of 128 through 1,024 threads is replayed once per
original Wave64, using physical groups of 64 threads. The compiler reconstructs the original
local IDs; group IDs and dispatch dimensions stay unchanged. Explicit execution metadata,
including the original dimensions, is cached with the shader. The switch is part of the
shader cache key. The complete legacy retry chain runs first, including jump threading.
Any usable legacy result keeps its original bytes and binding contract; independent replay
is attempted only after that chain still refuses the shader or requires native Wave64.
The ordinary path and default settings are unchanged.

Admission excludes original LDS/GDS, group barriers, atomics, unmodelled cache/system scopes,
group-info inputs, per-lane scalar resource reconstruction, descriptor waterfalls, and DPP
row masks that differ between the two halves. All control decisions must remain whole-wave
decisions. The two physical halves exchange through atomic scratch writes and rendezvous;
recognized memory waits retain a whole-group UAV/LDS fence. Non-null register wait counts
are not admitted. Partial waits are strengthened, within the admitted memory/scope contract.
The existing bounded-loop approximation remains, with guard exits shared by all 64 threads.
This mode cannot be combined with `LEONIDA_GROUP_SYNC=0`.

The runtime binds once and replays the complete command. Direct dispatch keeps the original
grid. Indirect dispatch currently accepts one dispatch-only record without a count buffer;
it snapshots that record once, admits the full original workload against the list budget,
and reuses the snapshot for every wave. Unsupported forms are refused before replay. This
inherits the existing readable-source state contract of the indirect path; refreshing a CPU
shadow is not proof of a native resource-state transition.

Validation so far: 206 native shader tests pass (two pre-existing ignored), the focused CPU
emission tests pass, and Microsoft DXIL validation accepts six authored examples, including
different wave loops, early returns, a guarded loop, and store/load ordering across halves.
The emitted half-swap example contains all four original memory waits as synchronization
with UAV and LDS fences.

On an RTX 5090, Core i9-14900KS, NVIDIA 580.173.02 and Proton 11.0, all six authored shader
execution cases passed: reductions requiring either original wave's upper half, cross-half
load/store ordering, original two-dimensional IDs, early returns with initialized untouched
outputs, and a bounded loop before a later wait. All 13 authored runtime cases also passed,
covering replay, argument snapshots and the full original workload budget. These used
vkd3d-proton ec207 with the separately reviewed custom-heap allocator correction. Vulkan
core/synchronization validation reported only the deliberate initialization canary; all five
distinct emitted SPIR-V programs passed offline validation. No title dispatch, scene,
frame-rate or rendering improvement is established by these authored tests.

The original vector-store wait is `s_waitcnt_vscnt`; a vector-load wait alone does not stand
in for it. See AMD's [RDNA 2 ISA reference](https://www.amd.com/content/dam/amd/en/documents/radeon-tech-docs/instruction-set-architectures/rdna2-shader-instruction-set-architecture.pdf)
and Microsoft's [group synchronization contract](https://learn.microsoft.com/en-us/windows/win32/direct3dhlsl/groupmemorybarrierwithgroupsync).

The pinned full-corpus feature comparison reconciled 26,148 program identities. With the
switch off, all 25,754 emitted outputs were byte-identical and the same 394 programs were
refused. With it on, every existing output remained identical, one additional program
emitted and passed Microsoft DXIL validation, and no new refusal appeared. The integrated
Windows workspace passed both default and all-features Clippy with all targets and warnings
denied after integrating current main.

A bounded opening-cutscene run created the new native pipeline, and its emitted bytes
matched the SDK-validated corpus output exactly. A private observation at the second world
frame offset confirmed one replay submission completed and its recording retired, but the
sampled post-budget indirect arguments requested zero work. It therefore does not prove a
nonzero live shader dispatch. The captured yard was populated, with rectangular character
and clothing artifacts still visible; neither a visual improvement nor a frame-rate gain
is claimed. Existing WSI and buffer-alignment validation categories remained. The observer
is a private diagnostic and is not part of the feature.

Native Windows behavior and a matched before/after performance run were not tested.
