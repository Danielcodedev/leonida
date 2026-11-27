# UP-3: keep raw descriptor observations consistent with API writes

A raw heap scan could observe record A, then an API call could replace the host descriptor with B.
Restoring A as raw bytes was then skipped: the raw-only fingerprint still said A, even though the
native slot held B. The same gap could leave a native descriptor active after a raw clear.

Host descriptor state and the last observed guest identity now share one lock. API writes, draw-time
mirroring and raw scans all publish into that state. Raw scans apply the exact first three words from
their kernel snapshot instead of fingerprinting a snapshot and rereading guest memory. The made and
observed identities remain distinct for deferred and invalidated resources; table grace, resource
retention and the existing page/scalar scan setting are preserved. This correctness fix is always on.

Adapted from [kelvaroq patch 0029 at commit 92606ea7](https://github.com/stellarr-studio/kelvaroq/blob/92606ea7f5da5bab74e4eee7f3045b060c7020a8/native/patches/0029-descriptor-record-sync.patch).
The patch's new batching option and page-straddling changes are outside this change.

The production-owned CPU state regression fails with the old raw-only observation publication and
passes with the fix. Six CPU tests cover A/B/A, null/restoration, first API write/raw clear, deferred
and invalidated state, captured identity and padding, and skipped observations. All six also pass in
the Windows test executable without graphics initialization.

Eight Windows regressions exercise actual create/copy/raw-sync calls with two valid samplers and
exact made identities, including an API write queued before host-heap creation, in both existing
scan modes. The identical tests fail all eight assertions on upstream `a3c5545` and pass all eight
with this fix on an NVIDIA RTX 5090 through vkd3d-proton. Neither run skips a test or submits shader
work; core and synchronization validation report only the runtime's deliberate initialization
canary. An initial test fixture had reversed LOD bounds; the recorded comparison uses the corrected
finite range 0..4 and valid sampler enums in both executables.

The tests use the normal explicit skip-if-no-device convention for CI. Native Windows CI passed
both strict workspace Clippy modes and the full workspace suite: 774 passed, none failed, and
19 explicitly ignored. The validation branch used identical production source and changed only the
workflow trigger. Local Windows cross-check and compilation of all 16 workspace test executables
also passed. Exact made keys validate descriptor synchronization, not rendered sampler output.

A bounded unattended game run with the fix completed. Rectangular corruption was still visible
before fog and through temporal processing. The baseline camera pan differed, so the captures do
not support a quantitative or severity comparison. No game image improvement, frame-rate benefit
or long-run stability result is claimed.
