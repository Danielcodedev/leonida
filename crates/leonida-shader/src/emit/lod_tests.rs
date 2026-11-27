//! A level query (`image_get_lod`) on a 2D array, lowered whole and
//! validated by `dxil.dll` when present: the validator wants undef past the
//! spatial coordinates ("out of bound coord must be undef").

use super::tests::texture_tables;
use crate::native::{HwStage, NativeProgram, StageIo};
use crate::{io, ir, resource, structure};

#[test]
fn a_level_query_on_an_array_leaves_the_slice_undefined() {
    // image_get_lod on a 2D array at (0.5, 0.5) slice 2, both levels
    // exported.
    use super::super::container::{self, SigElement};
    let words = [
        0xBE84_0300u32, // s_mov_b32 s4, s0
        0xBE85_0380,    // s_mov_b32 s5, 0
        0xBE86_0301,    // s_mov_b32 s6, s1
        0xBE87_0380,    // s_mov_b32 s7, 0
        0xF40C_0202,
        0xFA00_0000, // s_load_dwordx8 s[8:15], s[4:5], null
        0xF408_0403,
        0xFA00_0000, // s_load_dwordx4 s[16:19], s[6:7], null
        0x7E00_02F0, // v_mov_b32 v0, 0.5
        0x7E02_02F0, // v_mov_b32 v1, 0.5
        0x7E04_02F4, // v_mov_b32 v2, 2.0
        0xF180_0328,
        0x0082_0400, // image_get_lod v[4:5], v[0:2], s[8:15], s[16:19] dmask:0x3 dim:2D_ARRAY
        0xF800_180F,
        0x0504_0504, // exp mrt0 v4, v5, v4, v5 done vm
        0xBF81_0000, // s_endpgm
    ];
    let (layout, used) = texture_tables();
    let native = NativeProgram {
        stage: HwStage::Ps,
        wave64: false,
        vgprs: 8,
        layout,
        used,
        io: StageIo::Ps {
            inputs: vec![],
            input_addr: 0,
            db_shader_control: 0,
            patches: vec![],
        },
        code: words.iter().flat_map(|w| w.to_le_bytes()).collect(),
    };
    let target = SigElement {
        name: "SV_Target".into(),
        index: 0,
        kind: 16,
        comp: 9,
        interp: 0,
        row: Some(0),
        col: 0,
        cols: 4,
        usage: 15,
        half: false,
    };
    let isg1 = container::signature(&[], true);
    let osg1 = container::signature(&[target], false);
    let parts = [
        (crate::FourCC::ISG1, &isg1[..]),
        (crate::FourCC::OSG1, &osg1[..]),
    ];
    let bytes = crate::dxbc::build(&parts);
    let c = crate::Container::parse(&bytes).unwrap();
    let p = ir::build(&native.patched_code(), false, 8).unwrap();
    let st = structure::structure(&p).unwrap();
    let res = resource::track(&p, &native.layout, native.stage, Some(&st)).unwrap();
    let io = io::raise(&p, &native).unwrap();
    let out = super::super::emit(&c, &native, &p, &st, &io, &res).unwrap();
    #[cfg(windows)]
    if let Ok(mut v) = super::super::validator::Validator::load(
        super::super::validator::Validator::default_path().as_deref(),
    ) {
        v.validate(&mut out.dxil.clone()).unwrap();
    }
    crate::Container::parse(&out.dxil).unwrap();
}
