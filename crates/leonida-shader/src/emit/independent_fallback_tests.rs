//! The opt-in replay contract must not replace a usable legacy shader.
use super::{HostShader, independent, lower};
use crate::native::NativeProgram;
use crate::{Container, ShaderError, io, ir, resource, structure};

fn emitted(native: &NativeProgram, enabled: bool) -> Result<HostShader, ShaderError> {
    let p = ir::build(&native.patched_code(), native.wave64, native.vgprs)?;
    let st = structure::structure(&p)?;
    let res = resource::track(&p, &native.layout, native.stage, Some(&st))?;
    let io = io::raise(&p, native)?;
    let bytes = crate::dxbc::build(&[]);
    let container = Container::parse(&bytes)?;
    struct Restore(Option<u32>, Option<bool>, Option<bool>);
    impl Drop for Restore {
        fn drop(&mut self) {
            lower::TEST_HOST_WAVE.set(self.0);
            independent::TEST_ENABLED.set(self.1);
            super::TEST_STRICT_LOCAL.set(self.2);
        }
    }
    let _restore = Restore(
        lower::TEST_HOST_WAVE.replace(Some(32)),
        independent::TEST_ENABLED.replace(Some(enabled)),
        super::TEST_STRICT_LOCAL.replace(Some(false)),
    );
    super::emit(&container, native, &p, &st, &io, &res)
}

fn assert_legacy_parity(native: &NativeProgram) {
    let off = emitted(native, false).expect("authored fixture has a usable legacy result");
    assert!(off.independent_waves.is_none());
    let container = Container::parse(&off.dxil).unwrap();
    let psv = container.part(crate::dxbc::FourCC::PSV0).unwrap().data;
    let minimum_wave = u32::from_le_bytes(psv[20..24].try_into().unwrap());
    assert!(
        minimum_wave <= 32,
        "legacy emission must run on a Wave32 host"
    );
    let on = emitted(native, true).unwrap();
    // This checks all resource metadata as well as bytes and absence of the replay contract.
    assert_eq!(
        on, off,
        "enabling replay must preserve a usable legacy result"
    );
}

#[test]
fn usable_legacy_wave_fallback_keeps_its_bytes_and_complete_binding_contract() {
    assert_legacy_parity(&super::independent_tests::looping_mask());
}
