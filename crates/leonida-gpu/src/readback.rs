//! Dependencies on texture readbacks still to land in title memory.
//!
//! Unlike a shader's broad writable view, a readback describes bytes that
//! will be copied. Submission preparation must not speculate past them.
//! This orders separate submissions and partitions grouped lists before
//! dependent CPU preparation. Commands inside one recorded list stay together.

/// The title memory a submission-time step reads or overwrites.
#[derive(Clone, Copy)]
pub(crate) enum Access {
    Range(usize, usize),
    Copy { dst: usize, src: usize, len: usize },
    Unknown,
    HostOnly,
}

impl Access {
    /// Whether pending writes overlap this CPU access. A wrapped range
    /// cannot prove independence from any pending write.
    pub(crate) fn blocked_by(self, ranges: &[(usize, usize)]) -> bool {
        let hits = |at: usize, len: usize| {
            at.checked_add(len)
                .map_or(!ranges.is_empty(), |end| touches(ranges, at, end))
        };
        match self {
            Self::Range(at, len) => hits(at, len),
            Self::Copy { dst, src, len } => hits(src, len) || hits(dst, len),
            Self::Unknown => !ranges.is_empty(),
            Self::HostOnly => false,
        }
    }
}

/// Exact destination ranges, kept until their flights have landed.
#[derive(Clone, Default)]
pub(crate) struct ReadBacks(Vec<(usize, usize)>);

impl ReadBacks {
    pub(crate) const fn new() -> Self {
        Self(Vec::new())
    }

    pub(crate) fn ranges(&self) -> &[(usize, usize)] {
        &self.0
    }

    pub(crate) fn extend(&mut self, ranges: impl IntoIterator<Item = (usize, usize)>) {
        join_ranges(&mut self.0, ranges);
    }

    /// Only written bytes, not the padding between the title's rows.
    pub(crate) fn rows(&mut self, at: usize, [row, rows, pitch]: [usize; 3]) -> bool {
        if row == 0 || rows == 0 {
            return true;
        }
        if (rows - 1)
            .checked_mul(pitch)
            .and_then(|offset| at.checked_add(offset))
            .and_then(|last| last.checked_add(row))
            .is_none()
        {
            return false;
        }
        self.extend((0..rows).map(|line| {
            let from = at + line * pitch;
            (from, from + row)
        }));
        true
    }

    pub(crate) fn clear(&mut self) {
        self.0.clear();
    }

    /// This check precedes the optional read-ahead of shader-write ranges.
    pub(crate) fn blocks(&self, access: Access) -> bool {
        access.blocked_by(&self.0)
    }
}

/// List boundaries at which prior readbacks must land before preparation
/// continues. A list's own readbacks follow its CPU accesses: dependencies
/// within one already-recorded list need a separate recording-time split.
#[derive(Default)]
pub(crate) struct Segments {
    pending: ReadBacks,
    ends: Vec<usize>,
    lists: usize,
}

impl Segments {
    /// Preserve one legacy submission when disabled, without inspecting
    /// deferred metadata or adding readback waits. `lists` includes repeats.
    pub(crate) fn plan(enabled: bool, lists: usize, inspect: impl FnOnce(&mut Self)) -> Vec<usize> {
        if !enabled {
            return vec![lists];
        }
        let mut segments = Self::default();
        inspect(&mut segments);
        segments.finish()
    }

    /// Adds one ordered list occurrence. `produced` records its readbacks
    /// after checking its CPU accesses, without an intermediate range copy.
    pub(crate) fn push(
        &mut self,
        accesses: impl IntoIterator<Item = Access>,
        produced: impl FnOnce(&mut ReadBacks),
    ) {
        if !self.pending.ranges().is_empty()
            && accesses
                .into_iter()
                .any(|access| self.pending.blocks(access))
        {
            self.ends.push(self.lists);
            self.pending.clear();
        }
        produced(&mut self.pending);
        self.lists += 1;
    }

    /// Includes the final boundary, even for an empty synchronous
    /// submission, whose existing wait/settle behavior still runs once.
    pub(crate) fn finish(mut self) -> Vec<usize> {
        self.ends.push(self.lists);
        self.ends
    }
}

/// Whether `[from, to)` touches a sorted, joined range.
pub(crate) fn touches(ranges: &[(usize, usize)], from: usize, to: usize) -> bool {
    if from >= to {
        return false;
    }
    let at = ranges.partition_point(|r| r.1 <= from);
    ranges.get(at).is_some_and(|r| r.0 < to)
}

/// Adds ranges in order, joining overlapping or adjacent spans.
pub(crate) fn join_ranges(
    ranges: &mut Vec<(usize, usize)>,
    more: impl IntoIterator<Item = (usize, usize)>,
) {
    ranges.extend(more.into_iter().filter(|r| r.0 < r.1));
    ranges.sort_unstable();
    let mut out: Vec<(usize, usize)> = Vec::with_capacity(ranges.len());
    for &(from, to) in ranges.iter() {
        match out.last_mut() {
            Some(last) if from <= last.1 => last.1 = last.1.max(to),
            _ => out.push((from, to)),
        }
    }
    *ranges = out;
}

#[cfg(test)]
mod tests {
    use super::{Access, ReadBacks, Segments};

    #[test]
    fn readback_producer_and_cpu_consumer_use_distinct_segments() {
        let ends = Segments::plan(true, 2, |segments| {
            segments.push([], |pending| assert!(pending.rows(0x1000, [4, 1, 256])));
            segments.push(
                [Access::Copy {
                    dst: 0x2000,
                    src: 0x1000,
                    len: 4,
                }],
                |_| {},
            );
        });
        assert_eq!(ends, [1, 2]);
    }

    #[test]
    fn disabled_ordering_keeps_one_submission_without_inspecting_lists() {
        for lists in [0, 1, 4] {
            let ends = Segments::plan(false, lists, |_| {
                panic!("disabled ordering must not inspect readback metadata");
            });
            assert_eq!(ends, [lists]);
        }
    }

    #[test]
    fn independent_lists_stay_in_the_prefix_until_the_dependency() {
        let mut segments = Segments::default();
        segments.push([], |pending| assert!(pending.rows(0x1000, [8, 2, 256])));
        segments.push([Access::HostOnly], |_| {});
        // Only row padding and unrelated memory, not the produced bytes.
        segments.push(
            [Access::Range(0x1008, 248), Access::Range(0x2000, 16)],
            |_| {},
        );
        segments.push([Access::Range(0x1104, 4)], |_| {});
        assert_eq!(segments.finish(), [3, 4]);
    }

    #[test]
    fn overwritten_ranges_unknown_work_and_overflow_end_a_segment() {
        for access in [
            Access::Copy {
                dst: 0x1000,
                src: 0x2000,
                len: 4,
            },
            Access::Unknown,
            Access::Range(usize::MAX - 1, 4),
        ] {
            let mut segments = Segments::default();
            segments.push([], |pending| pending.extend([(0x1000, 0x1004)]));
            segments.push([access], |_| {});
            assert_eq!(segments.finish(), [1, 2]);
        }
    }

    #[test]
    fn dependent_chain_and_repeated_occurrences_are_kept_in_order() {
        let mut chain = Segments::default();
        chain.push([], |pending| pending.extend([(0x1000, 0x1004)]));
        chain.push([Access::Range(0x1000, 4)], |pending| {
            pending.extend([(0x2000, 0x2004)]);
        });
        chain.push([Access::Range(0x2000, 4)], |_| {});
        assert_eq!(chain.finish(), [1, 2, 3]);

        let mut repeated = Segments::default();
        for list in [0, 1, 0, 1] {
            match list {
                0 => repeated.push([], |pending| pending.extend([(0x1000, 0x1004)])),
                _ => repeated.push([Access::Range(0x1000, 4)], |_| {}),
            }
        }
        assert_eq!(repeated.finish(), [1, 3, 4]);
    }

    #[test]
    fn empty_work_and_same_list_dependencies_do_not_invent_empty_prefixes() {
        assert_eq!(Segments::default().finish(), [0]);
        let mut segments = Segments::default();
        segments.push([Access::Range(0x1000, 4)], |pending| {
            pending.extend([(0x1000, 0x1004)]);
        });
        segments.push([Access::Range(0x1000, 0)], |_| {});
        assert_eq!(segments.finish(), [2]);
    }

    /// Two separate submissions: the first texture copy has not landed
    /// when the second's CPU-side buffer copy is prepared. Its source must
    /// become visible first, even with speculative shader fills enabled.
    #[test]
    fn later_submission_copies_the_readback_result() {
        let mut pending = ReadBacks::default();
        pending.rows(0x1000, [4, 1, 256]);
        let access = Access::Copy {
            dst: 0x2000,
            src: 0x1000,
            len: 4,
        };
        let mut source = 0;
        let mut copied = None;
        // This is the mandatory production decision, before fill_ahead.
        if !pending.blocks(access) {
            copied = Some(source);
        }
        assert_eq!(copied, None, "copy prepared before its producer landed");
        source = 37;
        pending.clear();
        if !pending.blocks(access) {
            copied = Some(source);
        }
        assert_eq!(copied, Some(37));
    }

    #[test]
    fn overwritten_readback_and_cpu_uploads_wait_too() {
        let mut pending = ReadBacks::default();
        pending.rows(0x1000, [16, 1, 256]);
        assert!(pending.blocks(Access::Copy {
            dst: 0x1008,
            src: 0x2000,
            len: 4
        }));
        // Fills, shadow refreshes, write snapshots and texture staging all
        // read a range of title memory during submission preparation.
        assert!(pending.blocks(Access::Range(0x1008, 4)));
        assert!(pending.blocks(Access::Unknown));
        assert!(!pending.blocks(Access::HostOnly));
        assert!(!pending.blocks(Access::Range(0x2000, 16)));
    }

    #[test]
    fn overflowing_cpu_ranges_do_not_bypass_pending_writes() {
        let mut pending = ReadBacks::default();
        pending.rows(0x1000, [16, 1, 256]);
        assert!(pending.blocks(Access::Range(usize::MAX - 3, 8)));
        assert!(!pending.blocks(Access::Range(usize::MAX, 0)));
        pending.clear();
        assert!(!pending.blocks(Access::Range(usize::MAX - 3, 8)));
    }

    #[test]
    fn pitched_rows_do_not_block_padding_or_unrelated_memory() {
        let mut pending = ReadBacks::default();
        pending.rows(0x1000, [8, 2, 256]);
        assert!(pending.blocks(Access::Range(0x1004, 4)));
        assert!(pending.blocks(Access::Range(0x1104, 4)));
        assert!(!pending.blocks(Access::Range(0x1008, 248)));
        assert!(!pending.blocks(Access::Range(0x0ff0, 16)));
        assert!(!pending.blocks(Access::Range(0x1108, 16)));
        assert!(!pending.blocks(Access::Range(0x1000, 0)));
    }

    #[test]
    fn empty_and_overflowing_footprints_do_not_add_partial_ranges() {
        let mut pending = ReadBacks::new();
        assert!(pending.rows(usize::MAX, [0, 2, 256]));
        assert!(pending.rows(usize::MAX, [16, 0, 256]));
        assert!(!pending.rows(usize::MAX - 3, [8, 1, 256]));
        assert!(!pending.rows(0x1000, [8, usize::MAX, 256]));
        assert!(!pending.blocks(Access::Unknown));
    }

    #[test]
    fn landing_one_flight_keeps_later_readbacks_pending() {
        let mut first = ReadBacks::default();
        first.rows(0x1000, [16, 1, 256]);
        let mut later = ReadBacks::default();
        later.rows(0x1008, [16, 1, 256]);
        later.extend([(0x3000, 0x3100)]); // A tiled texture readback.
        let mut pending = first.clone();
        pending.extend(later.ranges().iter().copied());
        // Removing flights from the queue to land them does not clear the
        // pending ranges: a CPU readback can still be in progress.
        assert!(pending.blocks(Access::Range(0x1000, 4)));
        // After the first flight's copy-back, rebuild from those still in
        // flight. Overlap with the landed flight must not erase the later one.
        pending.clear();
        pending.extend(later.ranges().iter().copied());
        assert!(!pending.blocks(Access::Range(0x1000, 4)));
        assert!(pending.blocks(Access::Range(0x1008, 4)));
        assert!(pending.blocks(Access::Range(0x3000, 4)));
    }
}
