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
and invalidated state, captured identity and padding, and skipped observations. A Windows
descriptor test exercises actual create/copy/raw-sync calls with two valid samplers and exact made
identities, including an API write queued before host-heap creation, in both existing scan modes. It
follows the existing explicit skip-if-no-device convention and submits no GPU work; it has not yet
been run. Exact made keys validate descriptor synchronization, not rendered sampler output. No game image improvement or performance result is claimed.
