//! Authored programs at the ordinary native-program-to-DXIL boundary. No device is created.

use super::{HostShader, independent, lower};
use crate::native::{
    ComputeIo, HwStage, NativeProgram, ResourceType, RootParam, RootType, StageIo, UsedResource,
};
use crate::{Container, ShaderError, io, ir, resource, structure};

pub(super) fn looping_mask() -> NativeProgram {
    // Root constants s0/s1 bound the active thread IDs and iteration count. The two original
    // Wave64s may run different loop regions. Each stores its exact count's SCC result.
    let words: [u32; 22] = [
        0xBE85_0380, // s_mov_b32 s5, 0
        0xF408_0202,
        0xFA00_0000, // s_load_dwordx4 s[8:11], s[4:5], 0
        0x7E04_0280, // v_mov_b32 v2, 0
        0xBE87_0380, // s_mov_b32 s7, 0
        0x7D88_0000, // v_cmp_gt_u32 vcc, s0, v0
        0xBE8C_246A, // s_and_saveexec_b64 s[12:13], vcc
        0xBF88_0008, // s_cbranch_execz restore
        0x7D84_0102, // loop: v_cmp_eq_u32 vcc, v2, v0
        0x878E_7E6A, // s_and_b64 s[14:15], vcc, exec
        0xBE86_100E, // s_bcnt1_i32_b64 s6, s[14:15]
        0x8507_8081, // s_cselect_b32 s7, 1, 0
        0x4A04_0481, // v_add_nc_u32 v2, 1, v2
        0x7D88_0401, // v_cmp_gt_u32 vcc, s1, v2
        0x87FE_6A7E, // s_and_b64 exec, exec, vcc
        0xBF89_FFF8, // s_cbranch_execnz loop
        0xBEFE_040C, // restore: s_mov_b64 exec, s[12:13]
        0x7E02_0207, // v_mov_b32 v1, s7
        0x3406_0082, // v_lshlrev_b32 v3, 2, v0
        0xE070_1000,
        0x8002_0103, // buffer_store_dword v1, v3, s[8:11], 0 offen
        0xBF81_0000, // s_endpgm
    ];
    NativeProgram {
        stage: HwStage::Cs,
        wave64: true,
        vgprs: 4,
        layout: vec![
            RootParam {
                root: RootType::Constants,
                table_offset_dwords: 0,
                sgprs: 4,
                base_register: 0,
                user_data: 0,
                slot: 0,
            },
            RootParam {
                root: RootType::Table,
                table_offset_dwords: 0,
                sgprs: 1,
                base_register: 0,
                user_data: 4,
                slot: 1,
            },
        ],
        used: vec![UsedResource {
            kind: ResourceType::Uav,
            root: RootType::Table,
            table_offset_dwords: 0,
            lower_bound: 0,
            stride: 0,
            dwords: 4,
            user_data: 4,
            slot: 1,
        }],
        io: StageIo::Cs(ComputeIo {
            rsrc2: 5 << 1,
            threads: [128, 1, 1],
        }),
        code: words.iter().flat_map(|w| w.to_le_bytes()).collect(),
    }
}

fn half_swap() -> NativeProgram {
    let mut native = looping_mask();
    // After restoring EXEC, initialize each original thread's own word, then exchange
    // words with the other 32-lane half. Both waits are original Wave64 boundaries.
    let tail: [u32; 14] = [
        0xBBFD_0000, // finish the loop's observable vector store
        0x3406_0082, // v_lshlrev_b32 v3, 2, v0
        0xE070_1000,
        0x8002_0003, // buffer_store_dword v0, v3, s[8:11], 0 offen
        0xBBFD_0000, // s_waitcnt_vscnt null, 0: initialization stores complete
        0xE030_1000,
        0x8002_0103, // buffer_load_dword v1, v3, s[8:11], 0 offen
        0xBF8C_0000, // s_waitcnt vmcnt(0) expcnt(0) lgkmcnt(0)
        0x3A04_00A0, // v_xor_b32 v2, 32, v0
        0x3406_0482, // v_lshlrev_b32 v3, 2, v2
        0xE070_1000,
        0x8002_0103, // buffer_store_dword v1, v3, s[8:11], 0 offen
        0xBBFD_0000, // s_waitcnt_vscnt null, 0
        0xBF81_0000, // s_endpgm
    ];
    // Retain the loop's observable store too; dropping it would make its mask reduction
    // dead and let the ordinary path finish before the new fallback is needed.
    native.code.truncate(21 * 4);
    native
        .code
        .extend(tail.into_iter().flat_map(u32::to_le_bytes));
    native
}

fn emit(native: &NativeProgram, enabled: bool) -> Result<HostShader, ShaderError> {
    let p = ir::build(&native.patched_code(), native.wave64, native.vgprs)?;
    let st = structure::structure(&p)?;
    let res = resource::track(&p, &native.layout, native.stage, Some(&st))?;
    let io = io::raise(&p, native)?;
    let bytes = crate::dxbc::build(&[]);
    let c = Container::parse(&bytes)?;
    let old = lower::TEST_HOST_WAVE.replace(Some(32));
    let previous = independent::TEST_ENABLED.replace(Some(enabled));
    let strict = super::TEST_STRICT_LOCAL.replace(Some(true));
    let result = super::emit(&c, native, &p, &st, &io, &res);
    independent::TEST_ENABLED.set(previous);
    super::TEST_STRICT_LOCAL.set(strict);
    lower::TEST_HOST_WAVE.set(old);
    result
}

fn check(shader: &HostShader, original: [u32; 3]) {
    let plan = shader.independent_waves.expect("explicit replay contract");
    assert_eq!(plan.original_threads(), original);
    assert_eq!(plan.native_threads(), [64, 1, 1]);
    let container = Container::parse(&shader.dxil).unwrap();
    let psv = container
        .parts
        .iter()
        .find(|p| p.fourcc == crate::dxbc::FourCC(*b"PSV0"))
        .unwrap()
        .data;
    let word = |at| u32::from_le_bytes(psv[at..at + 4].try_into().unwrap());
    assert_eq!([word(20), word(24)], [32, 32], "native Wave32");
    assert_eq!([word(40), word(44), word(48)], [64, 1, 1]);
    let bindings = word(52) as usize;
    assert_eq!(word(56), 24);
    assert!(
        (0..bindings).any(|i| {
            let at = 60 + 24 * i;
            word(at) == 2
                && word(at + 4) == independent::INDEPENDENT_WAVE_SPACE
                && word(at + 8) == 0
                && word(at + 12) == 0
        }),
        "private b0 binding"
    );
    #[cfg(windows)]
    if let Ok(mut validator) =
        super::validator::Validator::load(super::validator::Validator::default_path().as_deref())
    {
        validator.validate(&mut shader.dxil.clone()).unwrap();
        eprintln!("validated independent Wave64 synthetic DXIL");
    } else {
        assert!(
            std::env::var_os("LEONIDA_DXIL").is_none(),
            "requested SDK validator must load"
        );
    }
}

#[test]
fn authored_reduction_defines_both_words_of_its_wave64_mask() {
    let native = looping_mask();
    let decoded = crate::gfx10::decode(&native.code).unwrap();
    let mask = decoded.iter().find(|inst| inst.offset == 0x24).unwrap();
    assert_eq!(mask.text(true), "s_and_b64 s[14:15], vcc, exec");
    let p = ir::build(&native.code, true, native.vgprs).unwrap();
    let instructions: Vec<_> = p.blocks.iter().flat_map(|block| &block.insts).collect();
    let producer = instructions
        .iter()
        .find(|inst| inst.machine.offset == 0x24)
        .unwrap();
    let count = instructions
        .iter()
        .find(|inst| inst.machine.offset == 0x28)
        .unwrap();
    for reg in [ir::Reg::S(14), ir::Reg::S(15)] {
        let value = producer.write(reg).expect("both ballot words are defined");
        assert_eq!(count.read(reg), Some(value));
    }
}

#[test]
fn independent_wave64s_can_reduce_inside_different_loop_regions() {
    let shader = emit(&looping_mask(), true).unwrap();
    check(&shader, [128, 1, 1]);
    assert_eq!(shader.independent_waves.unwrap().wave_count(), 2);
}

#[test]
fn disabled_mode_never_adds_a_replay_contract() {
    if let Ok(shader) = emit(&looping_mask(), false) {
        assert!(shader.independent_waves.is_none());
    }
}

#[test]
fn memory_waits_survive_public_emission_in_the_independent_mode() {
    let native = half_swap();
    let waits = |p: &ir::Program| {
        p.blocks
            .iter()
            .flat_map(|b| &b.insts)
            .filter(|i| ir::wave_memory_wait(i.name()))
            .count()
    };
    assert_eq!(
        waits(&ir::build(&native.code, true, native.vgprs).unwrap()),
        0
    );
    assert_eq!(waits(&independent::program(&native).unwrap()), 4);
    check(&emit(&native, true).unwrap(), [128, 1, 1]);
}

fn early_return() -> NativeProgram {
    let mut native = looping_mask();
    // Every lane first writes a sentinel. A wave returning below must leave it intact;
    // DEFAULT-heap UAV contents are otherwise undefined before the first shader store.
    let initialize: [u32; 8] = [
        0xBE85_0380, // s_mov_b32 s5, 0
        0xF408_0202,
        0xFA00_0000, // s_load_dwordx4 s[8:11], s[4:5], 0
        0x7E02_0293, // v_mov_b32 v1, 19
        0x3406_0082, // v_lshlrev_b32 v3, 2, v0
        0xE070_1000,
        0x8002_0103, // buffer_store_dword v1, v3, s[8:11], 0 offen
        0xBBFD_0000, // s_waitcnt_vscnt null, 0
    ];
    let prefix: [u32; 4] = [
        0x7D88_0002, // v_cmp_gt_u32 vcc, s2, v0
        0xBE92_246A, // s_and_saveexec_b64 s[18:19], vcc
        0xBF88_0016, // s_cbranch_execz final s_endpgm
        0xBEFE_0412, // s_mov_b64 exec, s[18:19]
    ];
    let mut code: Vec<u8> = initialize
        .into_iter()
        .chain(prefix)
        .flat_map(u32::to_le_bytes)
        .collect();
    code.append(&mut native.code);
    native.code = code;
    native
}

#[test]
fn independent_waves_keep_early_returns_and_loop_decisions_wave_wide() {
    check(&emit(&early_return(), true).unwrap(), [128, 1, 1]);
}

fn multidimensional() -> NativeProgram {
    let mut native = half_swap();
    native.io = StageIo::Cs(ComputeIo {
        rsrc2: 5 << 1 | 1 << 11,
        threads: [8, 16, 1],
    });
    let prefix: [u32; 2] = [
        0x3406_0283, // v_lshlrev_b32 v3, 3, v1
        0x4A00_0103, // v_add_nc_u32 v0, v3, v0
    ];
    let mut code: Vec<u8> = prefix.into_iter().flat_map(u32::to_le_bytes).collect();
    code.append(&mut native.code);
    native.code = code;
    native
}

#[test]
fn independent_waves_preserve_original_multidimensional_thread_ids() {
    check(&emit(&multidimensional(), true).unwrap(), [8, 16, 1]);
}

#[test]
fn independent_mode_accepts_only_resolved_far_jumps() {
    let mut native = looping_mask();
    let prefix: [u32; 5] = [
        0xBE94_1F00, // s_getpc_b64 s[20:21]
        0x8014_FF14,
        16,          // s_add_u32 s20, s20, 16
        0x8215_8015, // s_addc_u32 s21, s21, 0
        0xBE80_2014, // s_setpc_b64 s[20:21]: resolved to the following code
    ];
    let mut code: Vec<u8> = prefix.into_iter().flat_map(u32::to_le_bytes).collect();
    code.append(&mut native.code);
    native.code = code;
    check(&emit(&native, true).unwrap(), [128, 1, 1]);
    native.code[..4].copy_from_slice(&0xBE80_2000u32.to_le_bytes());
    if let Ok(shader) = emit(&native, true) {
        assert!(shader.independent_waves.is_none());
    }
}

#[test]
fn independent_mode_rejects_group_communication_and_unmodelled_system_effects() {
    for words in [
        vec![0xBF8A_0000],              // s_barrier
        vec![0xBFA2_0000],              // s_wait_idle
        vec![0xBF90_0000],              // s_sendmsg
        vec![0xBB80_0000],              // s_waitcnt_vscnt s0, 0: non-null counter operand
        vec![0xE0C8_1000, 0x8002_0000], // buffer_atomic_add
        vec![0xE031_1000, 0x8002_0000], // buffer_load_dword, GLC scope
        vec![0x7E04_02FA, 0xCF00_E400], // DPP row mask 0xC selects only original lanes32..63
    ] {
        let mut native = looping_mask();
        let mut prefix: Vec<u8> = words.into_iter().flat_map(u32::to_le_bytes).collect();
        prefix.append(&mut native.code);
        native.code = prefix;
        if let Ok(shader) = emit(&native, true) {
            assert!(
                shader.independent_waves.is_none(),
                "{:?}",
                crate::gfx10::decode(&native.code)
            );
        }
    }
    for (threads, lds) in [([64, 1, 1], 0), ([129, 1, 1], 0), ([128, 1, 1], 1)] {
        let mut native = looping_mask();
        native.io = StageIo::Cs(ComputeIo {
            rsrc2: 5 << 1 | lds << 15,
            threads,
        });
        if let Ok(shader) = emit(&native, true) {
            assert!(shader.independent_waves.is_none());
        }
    }
}

#[test]
fn replay_metadata_rejects_invalid_original_dimensions() {
    for dims in [
        [0, 1, 1],
        [64, 1, 1],
        [65, 1, 1],
        [128, 0, 1],
        [1, 1, 128],
        [1025, 1, 1],
        [u32::MAX, u32::MAX, 2],
        [1024, 2, 1],
    ] {
        assert!(super::IndependentWaves::new(dims).is_none());
    }
    for (dims, waves) in [([8, 16, 1], 2), ([4, 4, 16], 4), ([1024, 1, 1], 16)] {
        let plan = super::IndependentWaves::new(dims).unwrap();
        assert_eq!(plan.wave_count(), waves);
        assert_eq!(plan.original_threads(), dims);
    }
}

#[test]
fn descriptor_waterfalls_cannot_claim_an_independent_wave_contract() {
    let table = |user_data| RootParam {
        root: RootType::Table,
        table_offset_dwords: 0,
        sgprs: 1,
        base_register: 0,
        user_data,
        slot: user_data,
    };
    let range = |kind, offset, dwords, user_data| UsedResource {
        kind,
        root: RootType::Table,
        table_offset_dwords: offset,
        lower_bound: 0,
        stride: 0,
        dwords,
        user_data,
        slot: user_data,
    };
    let native = NativeProgram {
        stage: HwStage::Cs,
        wave64: true,
        vgprs: 48,
        layout: vec![table(0), table(1)],
        used: vec![
            range(ResourceType::Srv, 0, 8, 0),
            range(ResourceType::Uav, 16, 4, 0),
            range(ResourceType::Sampler, 0, 4, 1),
        ],
        io: StageIo::Cs(ComputeIo {
            rsrc2: 2 << 1,
            threads: [128, 1, 1],
        }),
        code: crate::resource::tests::cmpx_waterfall(true, false)
            .into_iter()
            .flat_map(u32::to_le_bytes)
            .collect(),
    };
    let p = independent::program(&native).unwrap();
    let st = structure::structure(&p).unwrap();
    let resources = resource::track(&p, &native.layout, native.stage, Some(&st)).unwrap();
    assert!(
        !resources.waterfall.reads.is_empty(),
        "exercise the actual tracked waterfall"
    );
    if let Ok(shader) = emit(&native, true) {
        assert!(shader.independent_waves.is_none());
    }
}

#[test]
fn scalar_code_addresses_cannot_reuse_a_vector_input_as_uniform() {
    let mut native = looping_mask();
    let tail: [u32; 12] = [
        0xBE94_1F00, // s_getpc_b64 s[20:21]
        0xD70F_1604,
        0x0000_2900, // v_add_co_u32 v4, s22, v0, s20
        0xD528_1605,
        0x0058_2A80, // v_add_co_ci_u32 v5, s22, 0, s21, s22
        0x7E30_0504, // v_readfirstlane_b32 s24, v4
        0x7E32_0505, // v_readfirstlane_b32 s25, v5
        0xF400_068C,
        0xFA00_0000, // s_load_dword s26, s[24:25], 0
        0x7E02_021A, // v_mov_b32 v1, s26
        0xE070_1000,
        0x8002_0103, // buffer_store_dword v1, v3, s[8:11], 0 offen
    ];
    native.code.truncate(21 * 4);
    native.code.extend(
        tail.into_iter()
            .chain([0xBF81_0000])
            .flat_map(u32::to_le_bytes),
    );
    native.vgprs = 6;
    let p = independent::program(&native).unwrap();
    let st = structure::structure(&p).unwrap();
    let resources = resource::track(&p, &native.layout, native.stage, Some(&st)).unwrap();
    let v0 = p
        .inputs
        .iter()
        .find(|(reg, _)| *reg == ir::Reg::V(0))
        .unwrap()
        .1;
    assert!(
        resources
            .scalar
            .iter()
            .any(|(_, a)| a.param == resource::CODE && a.dynamic == Some(v0))
    );
    if let Ok(shader) = emit(&native, true) {
        assert!(shader.independent_waves.is_none());
    }
}

fn guarded_loop() -> NativeProgram {
    let mut native = looping_mask();
    let tail: [u32; 7] = [
        0x7D88_0002, // v_cmp_gt_u32 vcc, s2, v0
        0xBE92_246A, // s_and_saveexec_b64 s[18:19], vcc
        0xBF84_0001, // s_cbranch_scc0 restore (SCC from saveexec's new EXEC)
        0xBF82_FFFF, // self-loop, stopped by the existing iteration guard
        0xBEFE_0412, // restore: s_mov_b64 exec, s[18:19]
        0xBF8C_0000, // s_waitcnt
        0xBF81_0000,
    ];
    native.code.truncate(21 * 4);
    native
        .code
        .extend(tail.into_iter().flat_map(u32::to_le_bytes));
    native
}

#[test]
fn an_inactive_half_cannot_leave_before_a_later_wait_at_the_loop_limit() {
    check(&emit(&guarded_loop(), true).unwrap(), [128, 1, 1]);
}

#[test]
fn authored_execution_cases_need_the_independent_contract_under_strict_policy() {
    for native in [
        looping_mask(),
        half_swap(),
        multidimensional(),
        early_return(),
        guarded_loop(),
    ] {
        match emit(&native, false) {
            Err(ShaderError::Unsupported { .. }) => {}
            Ok(shader) => {
                let container = Container::parse(&shader.dxil).unwrap();
                let psv = container.part(crate::dxbc::FourCC::PSV0).unwrap().data;
                assert_eq!(u32::from_le_bytes(psv[20..24].try_into().unwrap()), 64);
            }
            Err(error) => panic!("unexpected fixture error: {error}"),
        }
        assert!(emit(&native, true).unwrap().independent_waves.is_some());
    }
}

/// This is deliberately separate from the CPU/SDK tests. It opens no device unless the
/// hardware-test opt-in is explicit; an unavailable device is a failure, not a skipped pass.
#[cfg(windows)]
#[test]
fn independent_wave64_authored_execution_on_hardware() {
    if std::env::var("LEONIDA_TEST_INDEPENDENT_WAVES").as_deref() != Ok("1") {
        return;
    }
    assert_ne!(std::env::var("LEONIDA_WARP").as_deref(), Ok("1"));
    use super::host::{Dispatch, Host, Root, View};
    let host = Host::new(false).expect("requested SM6.6 hardware device");
    let first: Vec<u32> = (0..128).map(|t| u32::from(t < 64)).collect();
    let second: Vec<u32> = (0..128).map(|t| u32::from(t >= 64)).collect();
    let swap: Vec<u32> = (0..128).map(|t| t ^ 32).collect();
    for (name, native, constants, expected) in [
        (
            "upper-half reduction",
            looping_mask(),
            [128, 64, 0, 0],
            first.clone(),
        ),
        (
            "second original wave",
            looping_mask(),
            [128, 128, 0, 0],
            second,
        ),
        (
            "load then cross-half overwrite",
            half_swap(),
            [128, 64, 0, 0],
            swap.clone(),
        ),
        (
            "original two-dimensional IDs",
            multidimensional(),
            [128, 64, 0, 0],
            swap,
        ),
        (
            "early return in only one original wave",
            early_return(),
            [128, 64, 32, 0],
            (0..128).map(|t| if t < 64 { 1 } else { 19 }).collect(),
        ),
        (
            "bounded loop before later wait",
            guarded_loop(),
            [128, 64, 32, 0],
            first,
        ),
    ] {
        let shader = emit(&native, true).unwrap();
        let StageIo::Cs(cs) = native.io else {
            unreachable!()
        };
        check(&shader, cs.threads);
        let (root, pipeline) = host.compute_pipeline(&shader).unwrap();
        let mut user_data = vec![0; shader.user_data_dwords().max(1) as usize];
        for u in &shader.user_data {
            if let (RootType::Constants, 0, d @ 0..=3) = (u.root, u.slot, u.dword) {
                user_data[u.index as usize] = constants[d as usize];
            }
        }
        let output = host
            .dispatch_independent(
                &root,
                &pipeline,
                &shader,
                &Dispatch {
                    roots: vec![(0, Root::Constants(user_data))],
                    views: &[View::RawUav(128)],
                    samplers: &[],
                    groups: [1, 1, 1],
                },
            )
            .unwrap();
        assert_eq!(output[0], expected, "{name}");
        eprintln!("independent Wave64 hardware case passed: {name}");
    }
}
