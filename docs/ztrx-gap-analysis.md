# ztrx compared with Leonida: gap analysis

Status, 2026-11-25. Leonida side: branch `refactor/layers` at `abdaf16`. ztrx side: a local source snapshot
(folder name `ztrx-main`, no git history, so there is no commit to cite). The study was read-only: nothing was
built or run in either tree, nothing was written into the ztrx folder and no game file was opened.

Every statement about ztrx comes from reading its sources and its three documentation pages. Every statement
about Leonida names the file it was read in. Where a part was not read or not compared, the row says so.
No ztrx code is quoted on this page; file and function names are given so a reader can find the place.

## 1. Licence and origin

- ztrx is **GPL-3.0-or-later**: its `LICENSE` file is the plain GPLv3 text and its `Cargo.toml` declares
  `license = "GPL-3.0-or-later"`.
- Its README names its origin: based on VIctory (Marvisak) and victory-fork (fxceless).
- Leonida is GPL-3.0-or-later too, so the licences are compatible. Adapted code may be used with attribution
  and the licence notice, the case [related_projects.md](related_projects.md) describes for SCARAB.
- The house rule of that page still applies: facts first, write the implementation in Leonida's style, do not
  copy a whole component because the licence allows it.

Parts of ztrx carry terms of their own:

| Part of ztrx | Its terms | What that means here |
|---|---|---|
| `crates/victory-formats/src/texture.rs` | AMD, MIT notice in the file | usable, the notice stays with the code |
| `crates/victory-shader/src/gfx10/opcodes.rs` | Valve, MIT notice in the file | usable, the notice stays |
| `crates/victory-formats/src/xma.rs`, `xma/tables.rs` | follow FFmpeg (LGPL-2.1-or-later) | usable under GPLv3 |
| `crates/victory-loader/src/console_insn.rs` | says it is ported from XCL (GPL-2.0-only) | **do not copy** |

The last row matters. [related_projects.md](related_projects.md) records XCL as GPL-2.0-only and incompatible
with this repository. The file header in ztrx says the instruction decoder (`console_insn_decode.rs`) is XCL's,
unchanged. This page does not judge ztrx; for Leonida those two files are off limits whatever licence the
surrounding project declares. Leonida does not need them: `runtime/src/cpu_emulation.h` covers the same
instructions from the vendor manuals.

Result for reuse: ideas and measured facts from ztrx may be used, and code may be adapted with attribution,
except the two XCL-derived files. Nothing was copied for this page, and Leonida's tracked text does not mention
ztrx anywhere yet (searched: every Markdown file, `runtime`, `tools`, `scripts`).

## 2. How ztrx is laid out and built

A Rust workspace (edition 2024, minimum Rust 1.88) with 11 packages and about 107,000 lines. 135 Rust files
sit under its `crates` and `apps` folders.

| Package | Role, from its architecture page | Lines counted |
|---|---|---|
| `victory-core` | settings, the guard against writing game-derived data into the source tree, logging | not counted |
| `victory-pe` | read-only PE32+ and import-library analysis | not counted |
| `victory-loader` | prepare, map, bind and start the title image | 3,684 |
| `victory-hle` | console API implementations and the host pass-through policy | 18,120 |
| `victory-gpu` | console D3D12 objects, command lists and GPU memory on host D3D12 | 36,050 |
| `victory-shader` | console shader containers to host shaders | 41,237 |
| `victory-formats` | texture layouts, audio codecs | not counted |
| `victory-pipeline` | converter trait, content-addressed cache | not counted |
| `victory-game` | title-specific formats, build identities, hooks | not counted |
| `apps/victory` | command-line front end | not counted |
| `xtask` | asset-policy check, git hooks | not counted |

A stand-in title of its own code (the hle-probe fixture) serves its loader tests. A `diagnostics` feature and a
`diag` profile switch debug output and the D3D12 debug layer on. Its CI workflow and its play script were not
read.

## 3. How ztrx starts a title

Entry point: `apps/victory/src/main.rs`, which hands over to `run.rs`. The order read there:

1. Wait for a previous instance of the title to end (`lifecycle::wait_for_previous`).
2. Read the package's `MicrosoftGame.config`.
3. Mount two drives: `G:` for the package and `T:` for a temporary folder (`files::mount_at`).
4. Set the console model (Series X unless the user says otherwise).
5. Prepare and load the executable, load and bind the DLLs the title ships.
6. Install crash reporting and name a crash log file next to the temporary folder.
7. Load the title's remaining DLLs late, under a loader lock that may be entered again.
8. Start the title's main thread (`spawn_main`).

How the executable gets into the process (`crates/victory-loader/src/prepare.rs`, `windows.rs`):

- ztrx patches a **copy** of the executable in its cache folder: the copy is marked as a DLL, loses its entry
  point, has its import directory pointed at the terminator, loses its TLS callback pointer, and has the
  integrity flag and the checksum cleared.
- The Windows loader then maps that copy as an ordinary module. ztrx binds the imports itself.
- Import order, for every function: ztrx's own implementation, then the host's function when the pass-through
  policy allows that DLL, then a DLL the title ships, then a generated stub that names the import when called.
- An executable reads its thread-local block through TLS index 0. Mapped as a DLL it gets another index, so
  ztrx rewrites each such read into a call that yields the right slot (`tls.rs`).
- The prepared copy has no entry point and no TLS callbacks, so ztrx's own TLS callback passes thread start and
  end on to every attached image (`threads.rs`).

Leonida reaches the same point by another road: it maps the image itself (`runtime/src/pe_loader.cpp`) and takes
its TLS index from a small anchor DLL (`runtime/src/tls_host.cpp`). Both roads end in title code running
natively with every import bound, so the loader is not where the gap is.

## 4. The main frame in ztrx

"Main frame" on this page means the loop a title turns once per frame, whatever it draws: device creation,
queue and list and fence, the frame events (set an interval, schedule the origin event, wait for it and get a
token), and the present call that carries the token to a window.

- **Device** (`crates/victory-gpu/src/device.rs`): one static object laid out as the title's inlined code
  expects, with a table of 160 functions. One byte in the object is kept non-zero so the title's inlined fast
  paths call out of line, and the list limits are kept at zero so every command arrives as a call. It answers
  interface queries for device versions 1 to 8 and 11 itself. Feature queries are answered from a fixed table
  describing the console GPU. GPU addresses are CPU addresses; descriptor handles are plain addresses.
- **Queues and fences** (`queue.rs`, `fence.rs`): submitted lists run on the host GPU and are waited for, so a
  fence signal completes at once. Work given to a queue after a wait for a fence value not yet reached is kept
  in order and runs when the fence gets there.
- **Frame pacing** (`frame.rs`): one clock, started by the first interval the title sets, with absolute ticks.
  A wait for the origin event hands out consecutive frame tokens, also when the wait times out. The four calls
  sit at table offsets 0x270 to 0x288, which is slots 78 to 81: the slots Leonida uses.
- **Present** (`host.rs`): a window of its own and a DXGI flip-model swap chain with two buffers. The texture
  the title presents is copied into the back buffer in a swap chain format of the same family. A meter shows
  the frame rate in the window caption.
- **Host device** (`host.rs`): one D3D12 device at feature level 12_0 and one direct queue, created on first
  use. Without a host device ztrx logs a warning and goes on; command lists then do not run. Host objects that
  are let go are kept until the submissions that may still use them have finished.
- **DXGI** (`dxgi.rs`): one static adapter that reports the console GPU's vendor, one factory and one output
  with one display mode (3840x2160 at 60 Hz unless a variable says otherwise).

## 5. Finding: ztrx has no Vulkan path

The brief for this study asked how ztrx handles the GPU on Vulkan. It does not use Vulkan:

- A search of the whole snapshot for Vulkan, SPIR-V and the usual binding names finds one line, a comment in
  `crates/victory-shader/src/bvh.rs` about a public software model of an instruction.
- `victory-gpu` describes itself as the console's D3D12 on host D3D12. Shaders are translated to DXIL by an
  emitter of its own (`crates/victory-shader/src/emit`), which also computes the container hash D3D12 checks.
- So device selection, queue setup, swap chain and synchronisation in ztrx are all D3D12 and DXGI. What carries
  over to a Vulkan backend is the model (clock, tokens, present by copy, waits), not the calls.

There is no special handling for the GeForce 10 series either. The NVIDIA-specific places found are general:
a descriptor heap limit of 1,000,000 views, and a wave width of 32 lanes for compute programs written for 64.
A pipeline with a mesh shader is refused, with a message, when the host lacks mesh shaders or shader model 6.6
(`crates/victory-gpu/src/pipeline/host.rs`, `Host::mesh_shaders` in `host.rs`); there is no replacement path.

## 6. Gap table

Legend. Has it: yes, part, no, or ? when it was not established. Risk: low, med, high; it is the risk of the
missing piece or, when nothing is missing, of the assumption both projects share. Effort: none, S (under a
day), M (days), L (weeks), XL (months), ? when no comparison was made. Main frame: yes when the loop of
section 4 cannot turn without it, no when it is optional for that loop. File names in the table are short;
the notes under each table give the paths.

### 6.1 Loader and process

| ID | Capability in ztrx | Has it | Where in Leonida | What is missing | Risk | Effort | Main frame |
|---|---|---|---|---|---|---|---|
| L1 | Exe mapped in the process | yes | `pe_loader.cpp` | nothing known | low | none | yes |
| L2 | Imports bound in order | yes | `registry.cpp` | nothing known | low | none | yes |
| L3 | TLS for index-0 reads | yes | `pe_loader.cpp` | nothing known | med | none | yes |
| L4 | Thread notices to images | yes | `tls_host.cpp` | nothing known | med | none | yes |
| L5 | Stubs for unbound imports | yes | `registry.cpp` | nothing | low | none | yes |
| L6 | Zen 2 instructions emulated | yes | `cpu_emulation.h` | nothing | low | none | yes |
| L7 | Main thread started | yes | `process.cpp` | nothing known | low | none | yes |
| L8 | Console drives mounted | yes | `file_system.cpp` | nothing known | low | none | yes |
| L9 | Title DLLs loaded late | yes | `library_loader.cpp` | lock not compared | med | ? | yes |
| L10 | Crash report and crash log | part | `startup_trace.h` | always-on report | med | M | no |
| L11 | Wait for previous instance | no | none | whole feature | low | S | no |
| L12 | Package config read | no | none | reader | med | S | no |
| L13 | Console model choice | yes | `xgameruntime.cpp` | nothing | low | none | no |

Notes:

- **L1 to L4.** `runtime/src/pe_loader.h` states the contract: map, relocate, bind through the shim registry,
  register the unwind table, install static TLS. `runtime/src/pe_loader.cpp` rewrites an executable's index-0
  TLS reads and handles thread attach and detach through `runtime/src/tls_host.cpp`.
  `runtime/src/base_reservation.h` keeps the preferred base free for an image without relocations.
- **L5.** `runtime/shims/registry.cpp` has three policies (log, fail, stop) behind `LEONIDA_UNIMPLEMENTED`;
  ztrx has two (trap, return zero).
- **L7.** `rt::process::run_entry` in `runtime/shims/process.cpp` starts the entry point on a thread of its own
  with an 8 MiB stack reservation.
- **L8.** `runtime/shims/file_system.cpp` maps `GAME:`, `G:\` and `T:\`, with writes going to an overlay.
- **L9.** `runtime/shims/library_loader.cpp` returns pseudo handles for the DLLs the shims own, and the loader
  has a dynamic-load path. Whether a load from inside a module's start-up code is safe was not compared.
- **L10.** `runtime/shims/startup_trace.h` records an exception with a stack, but only under `--trace`. There
  is no unhandled-exception filter and no crash log by default. ztrx prints the faulting code first-chance for
  the fatal kinds, reports what nobody handles, and appends it to a crash log with the title's last debug
  output. Not needed to turn the loop, but it is what makes a later real run readable; it is step 4 of
  milestone 1 already.
- **L12.** Only `make_game.py` looks for the package config (to find the game folder); the runtime does not
  read it. What ztrx takes from it beyond the title's identity was not established.

### 6.2 Settings, logging, policy

| ID | Capability in ztrx | Has it | Where in Leonida | What is missing | Risk | Effort | Main frame |
|---|---|---|---|---|---|---|---|
| C1 | Settings: env, file, default | yes | `config.cpp` | nothing | low | none | no |
| C2 | Log levels, module filter | no | `[rt]` lines | levels and filter | low | M | no |
| C3 | Repo-write guard at run time | no | none | whole guard | low | S | no |
| C4 | Stand-in title for tests | yes | `tiny_game` | nothing | low | none | no |

Notes:

- **C1.** `runtime/core/config.h` and `runtime/core/config.cpp` hold one table for every setting, and
  `gta6rt config` prints each value with its source. ztrx has four values (game, cache and data folders, test
  titles) with the same lookup order.
- **C2.** ztrx filters by level and by module through one variable, and a plain release build is capped at
  info. Leonida prints `[rt] <module>: ...` lines to the error stream without levels; 249 such lines were
  counted before this study. Levels are the next step of the current work.
- **C3.** ztrx refuses to write game-derived data inside its source tree, found by a marker file at the root
  and by the path it was compiled from. In Leonida only `tools/progress_dashboard.py` refuses an output folder
  inside the repository; the runtime has no such check.

### 6.3 Console API implementations

| ID | Capability in ztrx | Has it | Where in Leonida | What is missing | Risk | Effort | Main frame |
|---|---|---|---|---|---|---|---|
| H1 | Table of served DLLs | yes | `registry.cpp` | not compared | med | ? | yes |
| H2 | Host pass-through policy | yes | `pe_loader.cpp` | not compared | med | ? | yes |
| H3 | Pseudo handle, console DLLs | yes | `library_loader.cpp` | nothing | low | none | yes |
| H4 | Offline answers, saves | yes | `xgameruntime.cpp` | not compared | med | ? | no |
| H5 | Audio, media, speech | part | `acphal.cpp` | not compared | med | ? | no |

Notes:

- **H1, H2.** ztrx groups its implementations in 26 modules (kernel, files, storage, xmem, xgameruntime and
  its user, save, store, package and system parts, gameinput, dstorage, display, the D3D12 entry points, audio
  and more). Leonida has 44 files under `runtime/shims`. The two sets were **not** compared function by
  function, so this page cannot say which imports only one of them serves. That comparison needs the title's
  import list, which `docs/runtime_imports.md` covers on Leonida's side.
- **H5.** Leonida has `runtime/shims/acphal.cpp` and `runtime/shims/xapu_chad.cpp`; ztrx has separate audio,
  DSP, media and speech modules. Not compared.

### 6.4 GPU and the frame

| ID | Capability in ztrx | Has it | Where in Leonida | What is missing | Risk | Effort | Main frame |
|---|---|---|---|---|---|---|---|
| G1 | Own device, console layout | part | `d3d12_xs_device.cpp` | PC-order proxy | high | L | yes |
| G2 | Device 1 to 8 and 11 answered | part | `d3d12_xs_device.cpp` | follows the host | high | M | yes |
| G3 | Feature answers as RDNA 2 | part | `d3d12_vulkan_device.cpp` | host answers kept | med | M | no |
| G4 | Virtual memory call answered | part | `d3d12_xs.cpp` | accepts, ignores | low | S | no |
| G5 | Queues, lists, fences | yes | `d3d12_xs_device.cpp` | layouts not compared | med | ? | yes |
| G6 | Wait before signal held | yes | `queue_holds.h` | nothing known | low | none | yes |
| G7 | Frame clock and tokens | part | `frame_pacer.h` | not wired to proxy | med | M | yes |
| G8 | Present call on the queue | part | `xbox_present.cpp` | slot not wired | high | M | yes |
| G9 | Window and swap chain | part | `vulkan_present.h` | host path has none | med | M | yes |
| G10 | Host device at level 12_0 | yes | `d3d12_xs.cpp` | nothing | low | none | yes |
| G11 | DXGI adapter and one output | part | `dxgi_com.cpp` | identity differs | med | S | no |
| G12 | Run without a host GPU | no | none | whole mode | low | S | no |
| G13 | Frame-rate meter | no | none | whole feature | low | S | no |
| G14 | Presented frames to files | yes | `vulkan_present.h` | Vulkan only | low | none | no |

Notes:

- **G1.** This is the deepest difference. ztrx gives the title an object of its own in the console's layout and
  takes every call itself. Leonida's host path wraps a PC device: `runtime/shims/d3d12_xs_device.h` says only
  the measured slots are overridden and the rest follow the PC table. Whether the title's inlined code reads
  device fields directly, and what the proxy shows at those offsets, was not checked for this page.
  [retail_boot_chain.md](retail_boot_chain.md) lists the stops measured so far. Leonida's Vulkan path is closer
  to ztrx in shape: `runtime/shims/d3d12_vulkan_device.cpp` implements the objects itself, behind the same
  proxy.
- **G2.** The proxy answers only the interfaces it models and otherwise depends on what the wrapped device
  offers. Measured on this PC at commit `6591ba9`, before runs with game files were ruled out: the host path
  stopped with the runtime's own line "D3D12XboxCreateDevice: proxy creation failed (hr=0x80004002)", which is
  the code for an interface that is not there. The host D3D12 of this PC (Windows 10, `d3d12.dll`
  10.0.19041.3636) ends at device version 8. Hypothesis, not proven: the title asks for a newer version. ztrx
  answers version 11 from its own object, whatever the host has.
- **G3.** On the Vulkan path Leonida derives its answers from the Vulkan device (the mesh shader tier, for
  example, follows the mesh shader extension). On the host path the query is presumed to reach the PC device;
  that was not read. Whether the title changes course on any answer is unknown without a run, hence optional.
- **G4.** `runtime/shims/d3d12_xs.cpp` accepts the call and ignores it; ztrx reports all of user space.
- **G5.** Device slots 48 and 73 (queue and list creation in the console's form) are handled and can be moved
  by settings. ztrx switches between two table layouts for lists and queues by runtime generation; Leonida's
  tables were not compared with them slot by slot.
- **G7.** `runtime/src/frame_pacer.h` models the clock, the origin event, the allowed latency and the tokens,
  and `runtime/shims/xbox_present.cpp` exposes the four frame calls on top of it; both are covered by tests.
  Neither is reached from the device proxy: `runtime/shims/d3d12_xs_device.cpp` answers slots 78 to 80 with a
  token counter of its own, and its wait returns at once. No file under `runtime/shims` or `runtime/src` other
  than `xbox_present.cpp` itself uses the presentation class. Wiring it is testable without the game.
- **G8.** The presentation class has the present call. The queue proxy refuses every slot past the public
  table and logs it. The two headers disagree on the slot: `runtime/shims/xbox_present.h` cites slot 30 (older
  runtime layout) or 32 (newer) from another project's measurement, while `runtime/shims/d3d12_xs_device.h`
  says the slot is not known and is not guessed. A wiring needs a setting for the slot, like the existing ones
  for the frame calls. A synthetic caller can prove the forwarding; that the slot is right for this title needs
  a real run.
- **G9.** `runtime/src/vulkan_present.h` puts a back buffer on screen (scaled copy, two frames in flight,
  swap chain rebuilt on resize, blank present, source rectangle), and `runtime/shims/dxgi_swapchain.h` serves
  the DXGI front end. On the host D3D12 path nothing was found that owns a window and a swap chain for the
  console's present call: the only windows created under `runtime/shims` are a probe in `dxgi_com.cpp` and the
  raw-mouse window in `gameinput.cpp`.
- **G11.** `runtime/shims/dxgi_com.cpp` reports the host GPU's vendor on the Vulkan path; ztrx reports the
  console GPU's. The mode lists were not compared.

### 6.5 Shaders and pipelines

| ID | Capability in ztrx | Has it | Where in Leonida | What is missing | Risk | Effort | Main frame |
|---|---|---|---|---|---|---|---|
| S1 | Translate at pipeline creation | no | `shader_library.h` | prebuilt lookup only | high | XL | no |
| S2 | DXIL emitter, container hash | no | none | whole emitter | high | XL | no |
| S3 | Shader cache on disk | part | `shader_library.h` | not needed yet | low | ? | no |
| S4 | Pipeline library, workers | part | `cached_pso.h` | not compared | med | ? | no |
| S5 | Mesh pipeline refused cleanly | yes | `d3d12_vulkan_device.cpp` | no replacement | high | XL | no |
| S6 | Wave64 on 32-lane hosts | ? | `subgroup_size.h` | not compared | med | ? | no |
| S7 | Ray tests in software | ? | `xdxr_build.h` | not compared | high | ? | no |

Notes:

- **Why "no" for the main frame.** The loop of section 4 turns and presents without a single title shader. A
  picture with content needs them, so every row here is needed for the step after the main frame.
- **S1, S3.** ztrx translates from the bytes the title passes when it creates a pipeline, and keeps the result
  on disk. Leonida translates ahead of time in `make_game.py`; `runtime/src/shader_library.h` finds the
  prebuilt SPIR-V by the hash of the native program. A shader that is not in the prebuilt set has no path.
- **S2.** Leonida's translator emits SPIR-V. A DXIL emitter is the direction chosen earlier for the host
  D3D12 backend; nothing of it exists on this branch.
- **S4.** `runtime/src/cached_pso.h` and the seeded pipeline cache in `runtime/shims/d3d12_vulkan_device.cpp`
  cover the cache blob and a warm start. ztrx also compiles pipelines on worker threads and starts the ones
  worth having early; Leonida's side of that was not read.
- **S5.** Both refuse a mesh pipeline when the host cannot run it, and both log why. Neither has a replacement
  for hosts without mesh shaders. `runtime/src/vulkan_mesh_limits.h` adds a limit check before creation.
- **S6, S7.** Established by name only: `runtime/src/subgroup_size.h`, `runtime/src/xdxr_build.h` and the
  wave64 and BVH test files under `tests/semantic` exist; none was read for this page. On ztrx's side the
  title's ray tracing is ordinary compute code plus one hardware instruction for the node test, which ztrx
  models in software; its own page says nothing is lit by ray tracing yet.

## 7. The eight failing `d3d12_*` tests

ztrx solves none of them, and cannot: they test Leonida's D3D12-on-Vulkan layer against the host's D3D12, and
ztrx has neither a Vulkan layer nor tests of that kind.

| Test | What fails on this PC | Counterpart in ztrx |
|---|---|---|
| `d3d12_vulkan_device` | a two-mip texture on a CPU-visible heap; a copy-count check | none |
| `d3d12_dxr_validation_khr` | the layer cannot allocate its synthetic buffers | none |
| `d3d12_r9g9b9e5_uav` | a committed resource on a custom heap | none |
| `d3d12_existing_heap` | no key line captured yet | none |
| `d3d12_close_parity` | three upload copies now match the reference; the table says otherwise | none |
| `d3d12_subresource_copy` | the copy steps differ from the host's | none |
| `d3d12_heap_properties` | 4 of 497 compared values differ | none |
| `d3d12_set_descriptor_heaps` | an empty shader blob | none |

The causes are not determined on this page; that is the next phase of the work, one test at a time. Two habits
of ztrx are worth keeping in mind there, as ideas and not as fixes: ask the host what it can do at run time and
refuse the one object with a clear message (S5), and go on with a warning when a whole device is missing (G12).

## 8. What this PC adds

| Fact | Source | Effect |
|---|---|---|
| Host D3D12 ends at device version 8, shader model 6.5, mesh shader tier 0 | measured on this PC earlier | see below |
| GTX 1070 Ti has no mesh shader, ray query or shading rate extension in Vulkan | the owner's report | unconfirmed |
| No 16-bit float shader arithmetic in Vulkan | the owner's report | unconfirmed |

- ztrx's README asks for shader model 6.6 and mesh shaders (an RTX 20 series card or newer). On this PC its
  mesh pipelines would be refused. What its other translated shaders need from the host was not established.
- The Vulkan facts are the owner's and count as hypotheses until a test queries them on the device.
- For Leonida this means: every item taken over for the main frame has to ask for such a feature at run time
  and fall back or report, never require it.

## 9. Candidates for the main frame, and one open decision

Needed for the main frame and not finished in Leonida:

| ID | Item | Testable without the game | Needs a real run for |
|---|---|---|---|
| G7 | Frame calls of the device proxy reach the frame pacer | yes, with a fake clock | the interval values |
| G8 | The present call of the queue proxy reaches the presentation class | yes, with a synthetic caller | the slot |
| G9 | A window and swap chain behind the present call on the chosen backend | yes, with a test window | scaling, HDR |
| G2 | The device answers the interface versions the title asks for | partly | which versions it asks for |
| G1 | The device shows the console's layout where the title reads it | no | everything |

Left out on purpose: everything marked "no" above, and G1 as a whole, because nothing about it can be checked
without the title.

The open decision is the backend. The brief asks for the main frame on Vulkan. ztrx, the reference, has it on
host D3D12 only. The direction chosen earlier for Leonida was host D3D12 with a DXIL emitter, with the Vulkan
layer frozen as the second backend, and the host D3D12 of this PC stops below what ztrx asks for. G7 and G8 are
the same work on either backend. G9 exists on Vulkan and is missing on host D3D12. The decision is the
maintainer's and is not made here.

## 10. Limits of this study

- Read in ztrx: the README, the manifest, the architecture and ray tracing pages, the front end's `main.rs`
  and `run.rs`, the loader's `lib.rs`, `prepare.rs` and `windows.rs`, the core crate, the HLE crate's `lib.rs`
  and `registry.rs`, and in the GPU crate `lib.rs`, `device.rs`, `dxgi.rs`, `frame.rs`, `queue.rs` and the
  parts of `host.rs` that create the device, present, and ask for mesh shaders.
- Read as file headers only: the loader's crash, thread, TLS and stub files, and the other GPU files.
- Not read: the HLE modules, the shader crate beyond its top file, the formats, pipeline and game crates, the
  asset-policy page, the CI workflow and the play script. How ztrx picks an adapter was not established.
- Nothing here was verified by running either program. Statements about what a title does at run time are
  what the two code bases say about it.
