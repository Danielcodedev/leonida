# P-4: range locks for texture refreshes during remaps (experimental, off by default)

In an opening scene run on `0a1a17b`, base profile, Ryzen 9 7900X and RTX 4070 Ti SUPER
(621.40), the median measured frame window was 1,706 ms. One window spent 1,038 ms per frame
waiting for the mapping lock across texture refresh threads. A refresh needs its own mapped
bytes to stay put, while the current lock also makes it wait for changes elsewhere in the
title's address space. A remap can temporarily unmap a whole view to replace one page, so any
narrower lock has to cover the full span of that view.

`LEONIDA_TEXTURE_RANGE_LOCK=1` enables range protection for texture refreshes. It keeps
overlapping views locked through the remap and its notifications. Reads of unrelated ranges can
continue, unless they share a lock in the fixed table. The switch is off by default and no
profile turns it on.

## RTX 4070 Ti SUPER 16 GB, opening scene (Ondra97)

Series X opening-scene runs on `e8aa615` and the range-lock patch used the same start state and
copies of the same warmed shader and pipeline caches. The hardware and driver were as above.
Each run took 330 seconds and added its listed switch to `base`. FPS and frame times are the
median of the script's windows after 170 seconds. Waits and deferred refreshes are medians for
windows with at least 500 draws per frame in that interval.

| Switch added to `base` | FPS | Frame (ms) | Mapping wait (ms/frame) | Deferred refreshes/frame |
|---|---:|---:|---:|---:|
| None | 0.2 | 4034.3 | 2995.4 | 0 |
| `LEONIDA_TEXTURE_NO_WAIT=1` | 2.2 | 449.4 | 0 | 16.2 |
| `LEONIDA_TEXTURE_RANGE_LOCK=1` | 3.2 | 307.8 | 3.8 | 0 |

The existing switch used kernel reads during contention and retried some refreshes on later
frames. Range locking kept the normal texture refresh path. All three runs reached the opening
scene and ended without a title crash or device loss. The runs reached different points in the
cutscene, so these numbers cover the sampled windows of each run. Three early range-lock samples
had near-black centers while hundreds of pipelines were pending. Shorter repeats in reverse
order used a more complete common pipeline cache and sampled from 100 to 190 seconds. The range
lock had visible output in all eight early samples. The existing switch had one near-black
sample. Median FPS in these shorter runs was 1.1 with range locking and 4.0 with the existing
switch. Equivalent gameplay views are still needed to compare picture quality and frame rate.

## RTX 5060 Laptop 8 GB, first gameplay area (sanchaton)

RTX 5060 Laptop GPU 8 GB, 16 GB RAM, Windows. Each run lasted 9 to 15 minutes, from the opening
cutscene into the first gameplay area with camera movement. The figures are averages of samples
50 to 99 (roughly minutes 4.5 to 9, after loading) from the per-frame `leonida_gpu::host` line.

| Run | fps (min to max) | ms/frame | preparing | copies | on the GPU | copying back | Stable |
|---|---|---|---|---|---|---|---|
| `main` (no P-4 patch) | 3.38 (2.7 to 3.8) | 297 | 83 | 48 | 181 | 52 | yes |
| `LEONIDA_TEXTURE_RANGE_LOCK=1` | 3.73 (0.8 to 5.4) | 313 | 113 | 65 | 114 | 62 | **no** |
| `LEONIDA_TEXTURE_NO_WAIT=1` | 3.03 (0.6 to 4.0) | 389 | 104 | 69 | 169 | 60 | yes |

- With the range lock the host device was removed after about 14 minutes, right after camera
  movement (`0x887A0005`, with `LEONIDA_RELAY=1` and no breadcrumbs). About 5 seconds before,
  one submission took much longer to prepare than usual. Until then the run held 4.0 to 4.3 fps.
- The `NO_WAIT` run on the same build survived the same camera movement, so the removal looks
  tied to the range lock. One earlier removal of the same kind on this laptop means that is not
  proven.
- `NO_WAIT` was slower than `main` on this card, and its frame times swung up to 1.6 s.

Keep both switches out of profiles for 8 GB cards until the device removal is understood. The
range lock cannot become a default before that. The cost of the page remaps themselves remains
part of P-4.