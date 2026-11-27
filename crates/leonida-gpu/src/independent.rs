//! Command admission for one independent logical Wave64 per native group.
//!
//! The compiler proves the shader's execution layout. This module admits
//! complete commands, before any binding or replay can reach a command list.

use leonida_shader::emit::IndependentWaves;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct Replay {
    waves: IndependentWaves,
    parameter: u32,
}

impl Replay {
    /// The private CBV occupies four root DWORDs, outside title user data.
    pub(crate) fn new(waves: IndependentWaves, parameter: u32, root_dwords: u32) -> Option<Self> {
        (parameter <= root_dwords && root_dwords.checked_add(4)? <= 64)
            .then_some(Self { waves, parameter })
    }

    pub(crate) fn parameter(self) -> u32 {
        self.parameter
    }

    pub(crate) fn waves(self) -> IndependentWaves {
        self.waves
    }

    /// The existing direct path has no list-work budget. Keep its legal
    /// original grid, and reject invalid dimensions before the first replay.
    pub(crate) fn direct(self, groups: [u32; 3]) -> Result<bool, &'static str> {
        if groups.into_iter().any(|n| n > 65535) {
            return Err("an independent-wave dispatch exceeds a native grid dimension");
        }
        let original_threads = u64::from(self.waves.wave_count()) * 64;
        groups
            .into_iter()
            .try_fold(original_threads, |n, groups| {
                n.checked_mul(u64::from(groups))
            })
            .ok_or("an independent-wave dispatch's original work overflows")?;
        Ok(!groups.contains(&0))
    }

    /// A dispatch-only signature inherits the private root constant. A
    /// count buffer or several records needs command-major expansion and
    /// one preserved count decision, neither of which this mode implements.
    pub(crate) fn indirect(
        self,
        kind: u32,
        stride: u32,
        max: u32,
        has_count: bool,
    ) -> Result<(), &'static str> {
        if kind != 2 || max != 1 || has_count {
            return Err("independent waves require one indirect dispatch without a count buffer");
        }
        if stride < 12 || !stride.is_multiple_of(4) {
            return Err("an independent-wave indirect dispatch has an invalid stride");
        }
        Ok(())
    }

    /// Bind the complete logical dispatch once. No fallible preparation is
    /// allowed between its native calls: a failure must drop the whole command.
    pub(crate) fn issue(
        self,
        bind: impl FnOnce() -> bool,
        mut command: impl FnMut([u32; 4]),
    ) -> bool {
        if !bind() {
            return false;
        }
        for wave in 0..self.waves.wave_count() {
            command([wave, 0, 0, 0]);
        }
        true
    }

    #[cfg(windows)]
    pub(crate) fn issue_direct(
        self,
        list: &windows::Win32::Graphics::Direct3D12::ID3D12GraphicsCommandList,
        groups: [u32; 3],
        bind: impl FnOnce() -> bool,
    ) -> bool {
        if self.direct(groups) != Ok(true) {
            return false;
        }
        self.issue(bind, |constants| {
            // SAFETY: the caller's open list has the admitted pipeline and its
            // private parameter after binding; the grid was checked above.
            unsafe {
                list.SetComputeRoot32BitConstants(
                    self.parameter(),
                    4,
                    constants.as_ptr().cast(),
                    0,
                );
                list.Dispatch(groups[0], groups[1], groups[2]);
            }
        })
    }

    #[cfg(windows)]
    pub(crate) fn issue_indirect(
        self,
        list: &windows::Win32::Graphics::Direct3D12::ID3D12GraphicsCommandList,
        signature: &windows::Win32::Graphics::Direct3D12::ID3D12CommandSignature,
        snapshot: &windows::Win32::Graphics::Direct3D12::ID3D12Resource,
        bind: impl FnOnce() -> bool,
    ) -> bool {
        self.issue(bind, |constants| {
            // SAFETY: the caller retains the admitted packed snapshot and binds
            // the matching pipeline. Its dispatch-only signature cannot reset
            // the private constant; every replay reads the same record at zero.
            unsafe {
                list.SetComputeRoot32BitConstants(
                    self.parameter(),
                    4,
                    constants.as_ptr().cast(),
                    0,
                );
                list.ExecuteIndirect(signature, 1, snapshot, 0, None, 0);
            }
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::Cell;

    fn replay() -> Replay {
        Replay::new(IndependentWaves::new([8, 16, 1]).unwrap(), 7, 60).unwrap()
    }

    #[test]
    fn a_complete_dispatch_binds_once_then_selects_each_original_wave() {
        let binds = Cell::new(0);
        let mut calls = Vec::new();
        assert!(replay().issue(
            || {
                binds.set(binds.get() + 1);
                true
            },
            |constants| calls.push(constants),
        ));
        assert_eq!(binds.get(), 1);
        assert_eq!(calls, [[0, 0, 0, 0], [1, 0, 0, 0]]);
        calls.clear();
        assert!(!replay().issue(|| false, |constants| calls.push(constants)));
        assert!(
            calls.is_empty(),
            "failed preparation cannot dispatch either wave"
        );
    }

    #[test]
    fn direct_admission_keeps_the_original_grid_and_zero_work() {
        assert_eq!(replay().direct([65535, 65535, 65535]), Ok(true));
        assert_eq!(replay().direct([0, 6, 9]), Ok(false));
        assert_eq!(replay().direct([6, 0, 9]), Ok(false));
        assert_eq!(replay().direct([6, 9, 0]), Ok(false));
        assert!(replay().direct([65536, 1, 1]).is_err());
        assert!(replay().direct([1, u32::MAX, 1]).is_err());
    }

    #[test]
    fn only_one_countless_dispatch_record_can_be_replayed() {
        assert!(replay().indirect(2, 12, 1, false).is_ok());
        assert!(replay().indirect(2, 32, 1, false).is_ok());
        for (kind, stride, max, count) in [
            (0, 16, 1, false),
            (10, 12, 1, false),
            (2, 8, 1, false),
            (2, 13, 1, false),
            (2, 12, 0, false),
            (2, 12, 2, false),
            (2, 12, 1, true),
        ] {
            assert!(replay().indirect(kind, stride, max, count).is_err());
        }
    }

    #[test]
    fn hidden_constants_cannot_overflow_the_root_signature() {
        let waves = IndependentWaves::new([1024, 1, 1]).unwrap();
        let plan = Replay::new(waves, 5, 60).unwrap();
        assert_eq!(plan.parameter(), 5);
        assert_eq!(plan.waves().wave_count(), 16);
        assert!(Replay::new(waves, 5, 61).is_none());
        assert!(Replay::new(waves, 5, u32::MAX).is_none());
        assert!(Replay::new(waves, 64, 60).is_none());
        let mut count = 0;
        assert!(plan.issue(|| true, |_| count += 1));
        assert_eq!(count, 16);
    }
}
