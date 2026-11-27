use super::*;
use crate::emit::bitcode::execute;
use crate::native::ComputeIo;

/// The latch is before both headers in machine-code order. Its conditional
/// branch chooses the inner header; fallthrough chooses the outer header.
/// Both are back edges in reverse postorder, without copying any title code.
fn nested_words(take_inner: bool) -> Vec<u32> {
    vec![
        0xBE80_0380 | u32::from(!take_inner), // s_mov_b32 s0, 0 or 1
        0xBE82_0380,                          // s_mov_b32 s2, 0
        0xBF82_0002,                          // s_branch outer
        0xBF06_8000,                          // latch: s_cmp_eq_u32 s0, 0
        0xBF85_0001,                          // s_cbranch_scc1 inner
        0x8102_8102,                          // outer: s_add_i32 s2, s2, 1
        0xBF82_FFFC,                          // inner: s_branch latch
        0xBF81_0000,                          // unreachable s_endpgm
    ]
}

fn with_lower(words: &[u32], test: impl FnOnce(Lower<'_>)) {
    with_stage(words, false, test);
}

fn with_stage(words: &[u32], pixel: bool, test: impl FnOnce(Lower<'_>)) {
    let native = NativeProgram {
        stage: if pixel { HwStage::Ps } else { HwStage::Cs },
        wave64: false,
        vgprs: 1,
        layout: vec![],
        used: vec![],
        io: if pixel {
            StageIo::Ps {
                inputs: vec![],
                input_addr: 0,
                db_shader_control: 0,
                patches: vec![],
            }
        } else {
            StageIo::Cs(ComputeIo {
                rsrc2: 0,
                threads: [1, 1, 1],
            })
        },
        code: words.iter().flat_map(|word| word.to_le_bytes()).collect(),
    };
    let p = crate::ir::build(&native.code, false, 1).unwrap();
    let st = crate::structure::structure(&p).unwrap();
    let io = crate::io::raise(&p, &native).unwrap();
    let res = crate::resource::track(&p, &[], native.stage, Some(&st)).unwrap();
    let parts = Parts {
        native: &native,
        p: &p,
        st: &st,
        io: &io,
        res: &res,
        inputs: vec![],
        outputs: vec![],
        prims: vec![],
        mesh_stride: 0,
        independent_waves: None,
    };
    // The normal public emission path must also produce a complete container.
    let empty = crate::dxbc::build(&[]);
    let container = crate::Container::parse(&empty).unwrap();
    let shader = crate::emit::emit(&container, &native, &p, &st, &io, &res).unwrap();
    crate::Container::parse(&shader.dxil).unwrap();
    #[cfg(windows)]
    if let Ok(mut validator) = crate::emit::validator::Validator::load(
        crate::emit::validator::Validator::default_path().as_deref(),
    ) {
        validator.validate(&mut shader.dxil.clone()).unwrap();
    }
    let bad = HashMap::new();
    let mut lower = Lower::new(&parts, &bad);
    assert!(lower.body().is_ok(), "synthetic native program must lower");
    test(lower);
}

#[test]
fn both_back_edges_have_complete_counter_and_register_phis() {
    for (take_inner, negated) in [false, true]
        .into_iter()
        .flat_map(|inner| [false, true].map(move |negated| (inner, negated)))
    {
        let mut words = nested_words(take_inner != negated);
        if negated {
            words[4] = 0xBF84_0001;
        } // s_cbranch_scc0 inner
        with_lower(&words, |mut lower| {
            // Include ordinary register phis as well as the synthesized counters.
            assert!(lower.x.p.blocks.iter().any(|b| !b.phis.is_empty()));
            execute::check_phis(&lower.s.m);
            let result = execute::run(&lower.s.m, 100_000);
            assert_eq!(result.blocks.last(), lower.abort.as_ref());
            let latch = lower
                .x
                .p
                .blocks
                .iter()
                .position(|b| b.offset == 12)
                .unwrap();
            let outer = lower
                .x
                .p
                .blocks
                .iter()
                .position(|b| b.offset == 20)
                .unwrap();
            let inner = lower
                .x
                .p
                .blocks
                .iter()
                .position(|b| b.offset == 24)
                .unwrap();
            let selected = if take_inner { inner } else { outer };
            let other = if take_inner { outer } else { inner };
            assert_eq!(
                result
                    .blocks
                    .iter()
                    .filter(|&&b| b == lower.edges[&(latch, selected)])
                    .count(),
                4096
            );
            assert!(!result.blocks.contains(&lower.edges[&(latch, other)]));
            let value = lower.x.p.blocks[outer].insts[0].write(Reg::S(2)).unwrap();
            let Val::I32(value) = lower.vals[&value] else {
                panic!("integer register")
            };
            assert_eq!(result.values[&value], if take_inner { 1 } else { 4096 });
            // The writer's later loop normalization must retain valid incoming edges.
            lower.s.m.single_latches();
            execute::check_phis(&lower.s.m);
            lower.s.m.optimise(crate::emit::bitcode::opt::MODULE);
            execute::check_phis(&lower.s.m);
            execute::run(&lower.s.m, 100_000);
        });
    }
}

#[test]
fn aliased_back_edges_share_one_counter_predecessor() {
    for branch in [0xBF84_0000, 0xBF85_0000] {
        let words = [
            0xBE80_0380, // s_mov_b32 s0, 0
            0xBF82_0002, // entry -> header
            0xBF06_8000, // latch: s_cmp_eq_u32 s0, 0
            branch,      // either condition goes to header
            0xBF82_FFFD, // header -> latch
            0xBF81_0000,
        ];
        with_lower(&words, |lower| {
            execute::check_phis(&lower.s.m);
            let result = execute::run(&lower.s.m, 100_000);
            assert_eq!(result.blocks.last(), lower.abort.as_ref());
            assert_eq!(lower.edges.len(), 1);
        });
    }
}

#[test]
fn a_self_loop_and_outer_back_edge_count_only_the_selected_loop() {
    for take_inner in [false, true] {
        let words = [
            0xBE80_0380 | u32::from(!take_inner),
            0xBF82_0002, // entry -> outer
            0xBF06_8000, // latch: s_cmp_eq_u32 s0, 0
            0xBF85_FFFE, // inner back edge to this same block
            0xBF82_FFFD, // outer -> latch
            0xBF81_0000,
        ];
        with_lower(&words, |lower| {
            execute::check_phis(&lower.s.m);
            let result = execute::run(&lower.s.m, 100_000);
            assert_eq!(result.blocks.last(), lower.abort.as_ref());
            let latch = lower.x.p.blocks.iter().position(|b| b.offset == 8).unwrap();
            let guard = lower.edges[&(latch, latch)];
            assert_eq!(
                result.blocks.iter().filter(|&&b| b == guard).count(),
                if take_inner { 4096 } else { 0 }
            );
        });
    }
}

#[test]
fn single_back_edge_keeps_its_forward_exit_at_the_limit() {
    for (condition, branch) in [(0xBF06_8000, 0xBF85_FFFE), (0xBF07_8000, 0xBF84_FFFE)] {
        let words = [0xBE80_0380, condition, branch, 0xBF81_0000];
        with_lower(&words, |lower| {
            execute::check_phis(&lower.s.m);
            let result = execute::run(&lower.s.m, 100_000);
            assert!(
                lower.abort.is_none(),
                "the original forward exit remains available"
            );
            assert_eq!(result.blocks.last(), lower.block.last().unwrap().as_ref());
            assert_eq!(result.blocks.len(), 4098);
        });
    }
}

#[test]
fn finite_nested_loops_keep_their_register_result() {
    let words = [
        0xBE80_0380, // s_mov_b32 s0, 0
        0xBE82_0380, // s_mov_b32 s2, 0
        0xBF82_0003, // entry -> outer
        0x8101_8101, // latch: s_add_i32 s1, s1, 1
        0xBF04_8301, // s_cmp_lt_i32 s1, 3
        0xBF85_0004, // s_cbranch_scc1 inner
        0x8100_8100, // outer: s_add_i32 s0, s0, 1
        0xBF04_8300, // s_cmp_lt_i32 s0, 3
        0xBF84_0003, // s_cbranch_scc0 end
        0xBE81_0380, // s_mov_b32 s1, 0
        0x8102_8102, // inner: s_add_i32 s2, s2, 1
        0xBF82_FFF7, // -> latch
        0xBF81_0000,
    ];
    with_lower(&words, |lower| {
        execute::check_phis(&lower.s.m);
        let result = execute::run(&lower.s.m, 100);
        assert_ne!(result.blocks.last(), lower.abort.as_ref());
        let value = lower
            .x
            .p
            .blocks
            .iter()
            .flat_map(|b| &b.insts)
            .find(|i| i.machine.offset == 40)
            .unwrap()
            .write(Reg::S(2))
            .unwrap();
        let Val::I32(value) = lower.vals[&value] else {
            panic!("integer register")
        };
        assert_eq!(
            result.values[&value], 6,
            "two outer iterations, three inner iterations each"
        );
    });
}

#[test]
fn exhausted_dual_back_edge_discards_a_pixel() {
    for take_inner in [false, true] {
        with_stage(&nested_words(take_inner), true, |lower| {
            execute::check_phis(&lower.s.m);
            let result = execute::run(&lower.s.m, 10_000);
            assert_eq!(result.blocks.last(), lower.abort.as_ref());
            assert!(result.discarded);
        });
    }
}
