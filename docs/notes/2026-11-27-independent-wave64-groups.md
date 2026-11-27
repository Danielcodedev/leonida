# Independent Wave64 groups (experimental, off by default)

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

Validation so far: 204 native shader tests pass (two pre-existing ignored), the focused CPU
emission tests pass, and Microsoft DXIL validation accepts six authored examples, including
different wave loops, early returns, a guarded loop, and store/load ordering across halves.
The emitted half-swap example contains all four original memory waits as synchronization
with UAV and LDS fences. Device and gameplay validation are separate requirements; these
compiler checks establish no frame-rate or rendering improvement.

The original vector-store wait is `s_waitcnt_vscnt`; a vector-load wait alone does not stand
in for it. See AMD's [RDNA 2 ISA reference](https://www.amd.com/content/dam/amd/en/documents/radeon-tech-docs/instruction-set-architectures/rdna2-shader-instruction-set-architecture.pdf)
and Microsoft's [group synchronization contract](https://learn.microsoft.com/en-us/windows/win32/direct3dhlsl/groupmemorybarrierwithgroupsync).
