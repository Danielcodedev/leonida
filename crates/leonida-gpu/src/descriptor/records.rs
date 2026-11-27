//! One serialized state for host descriptors and the guest records observed at their slots.

/// The first three words are the entire record identity, including inline views.
pub(super) fn key(words: [u32; 3]) -> u64 {
    if words[0] == super::VIEW_TAG {
        u64::from(words[2]) << 32 | u64::from(words[1])
    } else {
        0
    }
}

pub(super) fn captured(record: &[u8]) -> Option<u64> {
    let words = record.get(..12)?;
    Some(key(std::array::from_fn(|i| {
        u32::from_le_bytes(words[i * 4..i * 4 + 4].try_into().unwrap())
    })))
}

pub(super) struct Records {
    pub made: Vec<u64>,
    observed: Vec<u64>,
}

impl Records {
    pub fn new(count: usize) -> Self {
        Self {
            made: vec![0; count],
            observed: Vec::new(),
        }
    }

    pub fn track_raw(&mut self) {
        self.observed.resize(self.made.len(), 0);
    }

    pub fn changed(&self, index: usize, key: u64) -> bool {
        self.observed
            .get(index)
            .is_some_and(|previous| *previous != key)
    }

    /// `raw` skips unchanged snapshots; API/draw calls always apply their existing heuristics.
    pub fn apply<T>(
        &mut self,
        index: usize,
        key: u64,
        raw: bool,
        apply: impl FnOnce(&mut [u64], u64) -> T,
    ) -> Option<T> {
        if index >= self.made.len() {
            return None;
        }
        let previous = self.observed.get(index).copied().unwrap_or(0);
        if raw && previous == key {
            return None;
        }
        // API and draw writes must publish too: raw bytes may restore an older record.
        // The caller holds one lock through this observation and the native slot update.
        if let Some(observed) = self.observed.get_mut(index) {
            *observed = key;
        }
        Some(apply(&mut self.made, previous))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn raw_restore_after_api_write_applies_the_original_record_again() {
        let mut records = Records::new(1);
        records.track_raw();
        let a = 0x1_0000_0003;
        let b = 0x1_0000_0007;
        assert!(records.apply(0, a, true, |made, _| made[0] = a).is_some());
        assert!(records.apply(0, b, false, |made, _| made[0] = b).is_some());
        assert_eq!(records.made[0], b);
        assert!(records.apply(0, a, true, |made, _| made[0] = a).is_some());
        assert_eq!(records.made[0], a);
    }

    #[test]
    fn raw_restore_after_null_and_first_api_then_raw_clear_are_observed() {
        let a = 0x1_0000_0003;
        let mut records = Records::new(2);
        records.track_raw();
        records.apply(0, a, true, |made, _| made[0] = a);
        records.apply(0, 0, false, |made, _| made[0] = 0);
        assert!(records.apply(0, a, true, |made, _| made[0] = a).is_some());
        records.apply(1, a, false, |made, _| made[1] = a);
        assert!(records.apply(1, 0, true, |made, _| made[1] = 0).is_some());
        assert_eq!(records.made, [a, 0]);
    }

    #[test]
    fn deferred_and_invalidated_views_keep_their_observed_identity() {
        let a = 0x1_0000_0003;
        let mut records = Records::new(1);
        records.track_raw();
        records.apply(0, a, false, |made, _| made[0] = 0); // Deferred native view.
        assert!(
            records
                .apply(0, a, true, |_, _| panic!("unchanged"))
                .is_none()
        );
        records.apply(0, a, false, |made, _| made[0] = a); // Draw must still apply.
        records.made[0] = 0; // Texture invalidation does not imply new guest bytes.
        assert!(
            records
                .apply(0, a, true, |_, _| panic!("unchanged"))
                .is_none()
        );
        assert!(
            records
                .apply(0, 0, true, |_, previous| assert_eq!(previous, a))
                .is_some()
        );
    }

    #[test]
    fn snapshot_uses_exact_identity_ignoring_padding_and_later_guest_changes() {
        let mut guest = [0_u8; 32];
        for (i, word) in [super::super::VIEW_TAG, 3, 1].into_iter().enumerate() {
            guest[i * 4..i * 4 + 4].copy_from_slice(&word.to_le_bytes());
        }
        let snapshot = captured(&guest).unwrap();
        guest[4..8].copy_from_slice(&7_u32.to_le_bytes());
        assert_eq!(snapshot, 0x1_0000_0003);
        assert_eq!(captured(&guest), Some(0x1_0000_0007));
        guest[12..].fill(0xff);
        assert_eq!(captured(&guest), Some(0x1_0000_0007));
        guest[..4].fill(0);
        assert_eq!(captured(&guest), Some(0));
        assert_eq!(captured(&guest[..11]), None);
    }

    #[test]
    fn untracked_heaps_and_out_of_range_slots_keep_api_semantics() {
        let mut records = Records::new(1);
        assert!(
            records
                .apply(0, 37, false, |made, _| made[0] = 37)
                .is_some()
        );
        assert!(
            records
                .apply(0, 37, false, |made, _| assert_eq!(made[0], 37))
                .is_some()
        );
        assert!(
            records
                .apply(1, 37, false, |_, _| panic!("outside heap"))
                .is_none()
        );
    }

    #[test]
    fn gathering_or_skipping_a_snapshot_does_not_acknowledge_it() {
        let mut records = Records::new(1);
        records.track_raw();
        assert!(records.changed(0, 37));
        assert!(records.changed(0, 37)); // A table skip leaves it due.
        records.apply(0, 41, false, |made, _| made[0] = 41);
        assert!(records.apply(0, 37, true, |made, _| made[0] = 37).is_some());
        assert!(!records.changed(0, 37));
        assert!(!records.changed(1, 37));
    }
}
