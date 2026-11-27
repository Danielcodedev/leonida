//! Explicit execution metadata for independent original Wave64s. The ordinary shader path
//! has no such metadata and keeps its original dispatch shape and bindings.

use crate::gfx10::{Encoding, Fields, Operand};
use crate::native::{HwStage, NativeProgram, StageIo};
use crate::{ShaderError, ir};

/// Private `b0`: four root constants, with the original wave index in dword0.
pub const INDEPENDENT_WAVE_SPACE: u32 = 3;

/// One physical64-thread group per original Wave64. Construction validates all dimensions
/// so an invalid cache entry cannot ask the runtime to replay arbitrary numbers of groups.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct IndependentWaves {
    original_threads: [u32; 3],
}

impl IndependentWaves {
    pub fn new(original_threads: [u32; 3]) -> Option<Self> {
        let [x, y, z] = original_threads;
        if x == 0 || y == 0 || z == 0 || x > 1024 || y > 1024 || z > 64 {
            return None;
        }
        let count = x.checked_mul(y)?.checked_mul(z)?;
        (count > 64 && count <= 1024 && count.is_multiple_of(64))
            .then_some(Self { original_threads })
    }

    pub fn original_threads(self) -> [u32; 3] {
        self.original_threads
    }

    pub fn native_threads(self) -> [u32; 3] {
        [64, 1, 1]
    }

    pub fn wave_count(self) -> u32 {
        self.original_threads.iter().product::<u32>() / 64
    }
}

/// `LEONIDA_WAVE64_GROUPS=1`: allow the independent-wave fallback. Default off; its source
/// literal is included in the translator's generated switch list and cache fingerprint.
pub(super) fn enabled() -> bool {
    #[cfg(test)]
    if let Some(on) = TEST_ENABLED.get() {
        return on;
    }
    std::env::var_os("LEONIDA_WAVE64_GROUPS").is_some_and(|v| v == "1")
}

/// Eligibility is about original semantics, not a title hash or a captured resource layout.
/// This first mode excludes group communication, atomics and unmodelled cache/system scopes.
pub(super) fn admit(
    native: &NativeProgram,
    p: &ir::Program,
    res: &crate::resource::Resources,
) -> Option<IndependentWaves> {
    if !enabled() || super::lower::host_max_wave() != 32 || super::group_sync() == 0 {
        return None;
    }
    if !scalar_resources(p, res) {
        return None;
    }
    eligibility(native, p)
}

/// Resource tracking may look through a first-lane read when recovering an address or
/// descriptor. Such a reconstructed vector value is not a scalar just because the original
/// instruction was scalar. Refuse it here, including input and phi values; ordinary vector
/// memory accesses still keep their per-lane addresses.
pub(super) fn scalar_resources(p: &ir::Program, res: &crate::resource::Resources) -> bool {
    use crate::resource::{Address, Source};
    if !res.waterfall.reads.is_empty()
        || !res.waterfall.compares.is_empty()
        || !res.waterfall.loads.is_empty()
    {
        return false;
    }
    let scalar: std::collections::HashSet<_> = p
        .inputs
        .iter()
        .copied()
        .chain(
            p.blocks
                .iter()
                .flat_map(|b| b.phis.iter().map(|phi| (phi.reg, phi.value))),
        )
        .chain(
            p.blocks
                .iter()
                .flat_map(|b| b.insts.iter().flat_map(|i| i.writes.iter().copied())),
        )
        .filter_map(|(reg, value)| matches!(reg, ir::Reg::S(_)).then_some(value))
        .collect();
    let address = |a: &Address| a.dynamic.is_none_or(|v| scalar.contains(&v));
    fn source(s: &Source, address: &impl Fn(&Address) -> bool) -> bool {
        match s {
            Source::Built { address: a, .. } => address(a),
            Source::Phi { args, .. } | Source::Select { args, .. } => {
                args.iter().all(|s| source(s, address))
            }
            Source::Loaded { .. } | Source::Constant(_) => true,
            Source::Fetched { .. } | Source::Lanes { .. } | Source::LanePhi { .. } => false,
        }
    }
    let smem = |&(b, i): &crate::resource::Site| {
        matches!(p.blocks[b].insts[i].fields, Fields::Smem { .. })
    };
    res.scalar.iter().all(|(site, a)| !smem(site) || address(a))
        && res
            .descriptors
            .iter()
            .all(|d| !smem(&d.site) || source(&d.source, &address))
}

fn eligibility(native: &NativeProgram, p: &ir::Program) -> Option<IndependentWaves> {
    let StageIo::Cs(cs) = native.io else {
        return None;
    };
    if native.stage != HwStage::Cs || !native.wave64 || cs.lds_bytes() != 0 {
        return None;
    }
    let plan = IndependentWaves::new(cs.threads)?;
    if cs
        .system_sgprs()
        .1
        .is_some_and(|info| p.inputs.iter().any(|&(reg, _)| reg == ir::Reg::S(info)))
    {
        return None;
    }
    // Inspect the native instructions: normal IR has already discarded some waits and hints.
    let instructions = crate::gfx10::decode(&native.code).ok()?;
    for inst in &instructions {
        let name = inst.name()?;
        if name.contains("atomic") || matches!(name, "v_pipeflush" | "v_clrexcp") {
            return None;
        }
        let allowed = match inst.fields(native.wave64) {
            Fields::Sopp { .. } => {
                ir::wave_memory_wait(name)
                    || matches!(
                        name,
                        "s_endpgm"
                            | "s_branch"
                            | "s_cbranch_scc0"
                            | "s_cbranch_scc1"
                            | "s_cbranch_vccz"
                            | "s_cbranch_vccnz"
                            | "s_cbranch_execz"
                            | "s_cbranch_execnz"
                            | "s_nop"
                            | "s_inst_prefetch"
                            | "s_clause"
                    )
            }
            Fields::Sop { imm, src, .. } if name.starts_with("s_setreg") => {
                // Per-wave scratch-base setup, not MODE or a hardware/group identity register.
                name == "s_setreg_imm32_b32"
                    && imm.is_some_and(|v| matches!(v & 63, 20 | 21) && v & !63 == 0xf800)
                    && matches!(src.as_slice(), [Operand::Literal(_)])
            }
            Fields::Sop { src, .. } if ir::wave_memory_wait(name) => {
                // The non-null SOPK form adds a register contribution to its wait count.
                // This mode only implements the ordinary immediate/null form.
                matches!(
                    src.as_slice(),
                    [Operand::Scalar {
                        code: 125,
                        dwords: 1
                    }]
                )
            }
            Fields::Sop { .. } if name == "s_setpc_b64" => matches!(
                crate::gfx10::control(inst, native.code.len(), |at| {
                    instructions[..instructions.partition_point(|i| i.offset < at)].last()
                })
                .ok()?,
                crate::gfx10::Flow::Jump(_)
            ),
            Fields::Sop { .. } => match inst.encoding {
                Encoding::Sop2 | Encoding::Sopc => true, // arithmetic and comparisons
                Encoding::Sop1 => !matches!(
                    name,
                    "s_setpc_b64" | "s_swappc_b64" | "s_rfe_b64" | "s_mov_fed_b32"
                ),
                Encoding::Sopk => {
                    name.starts_with("s_cmpk_")
                        || matches!(
                            name,
                            "s_movk_i32" | "s_cmovk_i32" | "s_addk_i32" | "s_mulk_i32"
                        )
                }
                _ => false,
            },
            Fields::Smem { cache, .. } => {
                (name.contains("_load_") || name.contains("_store_"))
                    && !cache.glc
                    && !cache.slc
                    && !cache.dlc
            }
            Fields::Buffer { lds, cache, .. } => {
                !lds && (name.contains("load") || name.contains("store"))
                    && !cache.glc
                    && !cache.slc
                    && !cache.dlc
            }
            Fields::Flat { lds, cache, .. } => {
                !lds && (name.starts_with("global_load_") || name.starts_with("global_store_"))
                    && !cache.glc
                    && !cache.slc
                    && !cache.dlc
            }
            Fields::Image { cache, .. } => !cache.glc && !cache.slc && !cache.dlc,
            Fields::Ds { gds, .. } => {
                !gds && matches!(
                    name,
                    "ds_swizzle_b32" | "ds_permute_b32" | "ds_bpermute_b32"
                )
            }
            Fields::Valu(v) => !matches!(v.dpp,
                Some(crate::gfx10::Dpp::Row { row_mask, .. })
                    if row_mask & 3 != row_mask >> 2),
            _ => false,
        };
        if !allowed {
            return None;
        }
    }
    Some(plan)
}

pub(super) fn program(native: &NativeProgram) -> Result<ir::Program, ShaderError> {
    let mut p = ir::build_with_wave_waits(&native.code, native.wave64, native.vgprs)?;
    crate::spill::user_data(&mut p, native);
    Ok(p)
}

/// Every original control branch is a wave decision. Keep it that way throughout this
/// mode, not only around present exchange sites: a divergent early return or bounded loop
/// could otherwise leave a later rendezvous missing some participants.
pub(super) fn structure(p: &ir::Program) -> Result<crate::structure::Structured, ShaderError> {
    use crate::structure::{Atom, LaneExit};
    let mut wide = std::collections::HashSet::new();
    loop {
        let st = crate::structure::structure_wide(p, &wide)?;
        let before = wide.len();
        wide.extend(
            st.wave_any
                .iter()
                .enumerate()
                .filter_map(|(b, any)| any.map(|_| b)),
        );
        if wide.len() != before {
            continue;
        }
        let converged = st.exits.iter().enumerate().all(|(b, exit)| match *exit {
            LaneExit::Branch { when, .. } => {
                st.wide.contains(&b)
                    || st
                        .bools
                        .support(when)
                        .iter()
                        .all(|a| matches!(a, Atom::Uniform(_)))
            }
            LaneExit::Indirect => false,
            _ => true,
        });
        return if converged {
            Ok(st)
        } else {
            Err(ShaderError::Unsupported {
                offset: 0,
                what: "independent Wave64 control without a whole-wave decision",
            })
        };
    }
}

#[cfg(test)]
thread_local! {
    pub(super) static TEST_ENABLED: std::cell::Cell<Option<bool>> = const {
        std::cell::Cell::new(None)
    };
}
