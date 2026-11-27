# DPP row masks across a split Wave64

A Wave64 compute program can run in two 32-lane host waves even when its DPP shuffles
stay inside each half. The row mask still names four original 16-lane rows. Testing it
against the physical lane index reused bits 0 and 1 in the upper half: an authored
`row_mask=0x3` case incorrectly changed thread 32, while `row_mask=0xc` missed it.
Use the existing original thread mapping only for the row-mask index. Shuffle source
indices and the repeating bank mask remain local to the host wave; native Wave32,
native Wave64, and graphics-stage mapping are unchanged.

Validation: the public emitter accepts the authored fixture, and a CPU evaluator follows
its emitted integer expressions for 6,912 lane results across 64/128-thread groups, six
row masks, two bank masks, native Wave32/Wave64 and the split Wave64 path. The baseline
fails and the corrected lowering passes. The native shader suite passes 191 tests with
two ignored; strict native and Windows Clippy and asset policy pass. The evaluator
models the entry allocator's logical wave base; separate hardware validation covers
the actual emitted shaders.

Twelve authored baseline/fixed programs pass Microsoft DXIL validation. On an RTX 5090 (driver 580.173.02)
with an i9-14900KS, through Proton 11.0 and official vkd3d-proton ec207, three asymmetric-mask cases
each return 32 wrong lanes before the fix; the symmetric-mask and native Wave32 controls
pass. All six cases pass after the fix, with all twelve submission fences completed.
Vulkan core/synchronization validation reports the same runtime initialization warning
in both runs and no further errors. A private census finds no eligible asymmetric
Wave64 compute DPP row-mask sites among 26,148 native programs, so this is a translator
correctness fix without a demonstrated current-title rendering or performance gain.
