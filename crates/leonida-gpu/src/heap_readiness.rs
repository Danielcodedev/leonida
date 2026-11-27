//! Recording-time readiness policy used by directly indexed buffer heaps.
//!
//! The legacy policy remains available unchanged. The opt-in policy caches
//! descriptor discovery per heap, but records readiness for each consumer.

use std::collections::{BTreeMap, HashMap, HashSet};
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};

/// More refreshes can change submission cost and timing. Disabled by default;
/// this does not solve descriptors rewritten after their last recorded bind.
#[cfg(windows)]
pub(crate) fn enabled() -> bool {
    static ON: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *ON.get_or_init(|| {
        let on = std::env::var("LEONIDA_HEAP_READINESS").as_deref() == Ok("1");
        if on {
            tracing::info!("per-recording indexed-buffer readiness enabled; heap time includes cached recording work, passes count descriptor resolution");
        }
        on
    })
}

/// Retain the stride table and decide whether this recording schedules the
/// heap pass. The caller's pass enqueues the actual submission-time refreshes.
pub(crate) fn record_use(
    first_use: impl FnOnce(usize) -> bool,
    retain_strides: impl FnOnce(),
    last_frame: &AtomicU64,
    current_frame: impl FnOnce() -> u64,
) -> Option<u64> {
    const ONCE: usize = usize::MAX - 0x5e;
    if !first_use(ONCE) {
        return None;
    }
    retain_strides();
    let frame = current_frame();
    (last_frame.swap(frame, Ordering::Relaxed) != frame).then_some(frame)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub(crate) struct HeapId(u64);

impl HeapId {
    fn new() -> Self {
        static NEXT: AtomicU64 = AtomicU64::new(1);
        Self(
            NEXT.fetch_update(Ordering::Relaxed, Ordering::Relaxed, |n| n.checked_add(1))
                .expect("heap readiness identity exhausted"),
        )
    }
}

pub(crate) struct Span<T> {
    pub copy: Arc<T>,
    pub from: u64,
    pub to: u64,
}

impl<T> Span<T> {
    /// A view may extend beyond the copy its descriptor actually shows. Match
    /// Shadow::refresh's clipping before dependency analysis sees the range.
    pub(crate) fn bounded(copy: Arc<T>, extent: (u64, u64), from: u64, len: u64) -> Option<Self> {
        let end = extent.0.checked_add(extent.1)?;
        if from < extent.0 || from >= end || len == 0 {
            return None;
        }
        let to = from.checked_add(len.min(end - from))?;
        Some(Self { copy, from, to })
    }
}

impl<T> Clone for Span<T> {
    fn clone(&self) -> Self {
        Self {
            copy: self.copy.clone(),
            from: self.from,
            to: self.to,
        }
    }
}

pub(crate) struct Snapshot<T> {
    pub heap: HeapId,
    pub generation: u64,
    pub spans: Arc<[Span<T>]>,
}

impl<T> Clone for Snapshot<T> {
    fn clone(&self) -> Self {
        Self {
            heap: self.heap,
            generation: self.generation,
            spans: self.spans.clone(),
        }
    }
}

/// Owned by the heap, so neither an allocator address reused by a later heap
/// nor a process-global frame stamp can consume this heap's readiness.
pub(crate) struct Cache<T> {
    revision: Option<u64>,
    frame: Option<u64>,
    frames: u64,
    slots: HashMap<u32, Span<T>>,
    copies: BTreeMap<usize, CopyRanges<T>>,
    snapshot: Snapshot<T>,
}

impl<T> Default for Cache<T> {
    fn default() -> Self {
        Self {
            revision: None,
            frame: None,
            frames: 0,
            slots: HashMap::new(),
            copies: BTreeMap::new(),
            snapshot: Snapshot {
                heap: HeapId::new(),
                generation: 0,
                spans: Arc::from([]),
            },
        }
    }
}

/// Count endpoints rather than rescanning every descriptor when one slot
/// changes. Duplicate and overlapping views still contribute independently.
struct CopyRanges<T> {
    copy: Arc<T>,
    starts: BTreeMap<u64, usize>,
    ends: BTreeMap<u64, usize>,
}

impl<T> CopyRanges<T> {
    fn bounds(&self) -> Option<(u64, u64)> {
        Some((
            *self.starts.first_key_value()?.0,
            *self.ends.last_key_value()?.0,
        ))
    }

    fn remove(&mut self, span: &Span<T>) {
        for (counts, at) in [(&mut self.starts, span.from), (&mut self.ends, span.to)] {
            let count = counts.get_mut(&at).expect("cached slot endpoint exists");
            *count -= 1;
            if *count == 0 {
                counts.remove(&at);
            }
        }
    }
}

impl<T> Cache<T> {
    /// `revision` must be read BEFORE draining changes. A write concurrent
    /// with discovery can then cause an extra later pass, never be labeled
    /// consumed by a revision newer than the content we inspected.
    pub(crate) fn snapshot(
        &mut self,
        frame: u64,
        revision: u64,
        take_changes: impl FnOnce() -> Vec<u32>,
        all_slots: impl FnOnce() -> Vec<u32>,
        mut resolve: impl FnMut(u32) -> Option<Span<T>>,
    ) -> Snapshot<T> {
        if self.frame == Some(frame) && self.revision == Some(revision) {
            return self.snapshot.clone();
        }
        let new_frame = self.frame != Some(frame);
        let full = self.revision.is_none() || (new_frame && self.frames.is_multiple_of(16));
        if new_frame {
            self.frames = self.frames.wrapping_add(1);
        }
        let changes = take_changes();
        let slots = if full {
            self.slots.clear();
            self.copies.clear();
            all_slots()
        } else {
            changes
        };
        let mut previous = HashMap::new();
        for index in slots {
            let next = resolve(index).filter(|span| span.from < span.to);
            if self
                .slots
                .get(&index)
                .zip(next.as_ref())
                .is_some_and(|(a, b)| {
                    Arc::ptr_eq(&a.copy, &b.copy) && a.from == b.from && a.to == b.to
                })
            {
                continue;
            }
            if let Some(old) = self.slots.remove(&index) {
                let key = Arc::as_ptr(&old.copy) as usize;
                let group = self.copies.get_mut(&key).expect("cached copy exists");
                previous.entry(key).or_insert_with(|| group.bounds());
                group.remove(&old);
                if group.starts.is_empty() {
                    self.copies.remove(&key);
                }
            }
            if let Some(span) = next {
                let key = Arc::as_ptr(&span.copy) as usize;
                previous
                    .entry(key)
                    .or_insert_with(|| self.copies.get(&key).and_then(CopyRanges::bounds));
                let group = self.copies.entry(key).or_insert_with(|| CopyRanges {
                    copy: span.copy.clone(),
                    starts: BTreeMap::new(),
                    ends: BTreeMap::new(),
                });
                *group.starts.entry(span.from).or_default() += 1;
                *group.ends.entry(span.to).or_default() += 1;
                self.slots.insert(index, span);
            }
        }
        self.frame = Some(frame);
        self.revision = Some(revision);
        let changed = full
            || previous
                .into_iter()
                .any(|(key, before)| before != self.copies.get(&key).and_then(CopyRanges::bounds));
        if changed {
            let spans: Vec<_> = self
                .copies
                .values()
                .filter_map(|group| {
                    let (from, to) = group.bounds()?;
                    Some(Span {
                        copy: group.copy.clone(),
                        from,
                        to,
                    })
                })
                .collect();
            let unchanged = spans.len() == self.snapshot.spans.len()
                && spans.iter().zip(self.snapshot.spans.iter()).all(|(a, b)| {
                    Arc::ptr_eq(&a.copy, &b.copy) && a.from == b.from && a.to == b.to
                });
            if !unchanged {
                self.snapshot.generation = self
                    .snapshot
                    .generation
                    .checked_add(1)
                    .expect("heap readiness generation exhausted");
                self.snapshot.spans = spans.into();
            }
        }
        self.snapshot.clone()
    }
}

/// A recording owns every bound stride table independently of which recording
/// first discovered its descriptors. Title writes invalidate readiness only;
/// retained resources remain alive until the recording itself is released.
#[derive(Default)]
pub(crate) struct Recording {
    held: HashSet<HeapId>,
    ready: HashMap<HeapId, u64>,
}

impl Recording {
    pub(crate) fn record<T>(
        &mut self,
        snapshot: &Snapshot<T>,
        retain: impl FnOnce(),
        refresh: impl FnOnce(),
    ) -> bool {
        if !self.held.contains(&snapshot.heap) {
            retain();
            self.held.insert(snapshot.heap);
        }
        if self.ready.get(&snapshot.heap) == Some(&snapshot.generation) {
            return false;
        }
        refresh();
        self.ready.insert(snapshot.heap, snapshot.generation);
        true
    }

    pub(crate) fn title_written(&mut self) {
        self.ready.clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::Cell;

    struct Heap {
        strides: Arc<u32>,
        snapshot: Snapshot<u32>,
    }

    impl Heap {
        fn new(value: u32) -> Self {
            let mut cache = Cache::default();
            let copy = Arc::new(value);
            let snapshot = cache.snapshot(
                7,
                0,
                Vec::new,
                || vec![0],
                |_| {
                    Some(Span {
                        copy: copy.clone(),
                        from: 0,
                        to: 4,
                    })
                },
            );
            Self {
                strides: Arc::new(value),
                snapshot,
            }
        }
    }

    /// The same production gate decides retention and refresh scheduling.
    /// No shadow bytes, deferred CPU copies or GPU execution are simulated.
    #[derive(Default)]
    struct List {
        gate: Recording,
        retained: Vec<Arc<u32>>,
        refreshes: Vec<u32>,
        ranges: Vec<(u64, u64)>,
    }

    impl List {
        fn use_heap(&mut self, heap: &Heap) {
            let Self {
                gate,
                retained,
                refreshes,
                ranges,
            } = self;
            gate.record(
                &heap.snapshot,
                || retained.push(heap.strides.clone()),
                || {
                    for span in heap.snapshot.spans.iter() {
                        refreshes.push(*span.copy);
                        ranges.push((span.from, span.to));
                    }
                },
            );
        }
    }

    #[test]
    fn first_recording_schedules_readiness_and_retains_its_stride_table() {
        let heap = Heap::new(37);
        let mut list = List::default();
        list.use_heap(&heap);
        assert_eq!(list.refreshes, [37]);
        assert_eq!(Arc::strong_count(&heap.strides), 2);
        list.use_heap(&heap);
        assert_eq!(list.refreshes, [37]);
        assert_eq!(list.retained.len(), 1);
    }

    #[test]
    fn a_list_submitted_first_does_not_depend_on_an_earlier_recording() {
        let heap = Heap::new(37);
        let mut recorded_first = List::default();
        let mut submitted_first = List::default();
        recorded_first.use_heap(&heap);
        submitted_first.use_heap(&heap);
        assert_eq!(submitted_first.refreshes, [37]);
    }

    #[test]
    fn discarding_a_recording_does_not_consume_another_lists_readiness() {
        let heap = Heap::new(37);
        let mut abandoned = List::default();
        abandoned.use_heap(&heap);
        drop(abandoned);
        let mut submitted = List::default();
        submitted.use_heap(&heap);
        assert_eq!(submitted.refreshes, [37]);
    }

    #[test]
    fn switching_heaps_retains_each_stride_table_until_the_list_is_released() {
        let a = Heap::new(37);
        let b = Heap::new(91);
        let b_lifetime = Arc::downgrade(&b.strides);
        let mut list = List::default();
        list.use_heap(&a);
        list.use_heap(&b);
        drop(b);
        assert!(b_lifetime.upgrade().is_some());
        assert_eq!(list.refreshes, [37, 91]);
        drop(list);
        assert!(b_lifetime.upgrade().is_none());
    }

    #[test]
    fn title_writes_invalidate_readiness_without_losing_held_resources() {
        let heap = Heap::new(37);
        let mut list = List::default();
        list.use_heap(&heap);
        // Both known title copies and unknown title-writing work call this
        // invalidation alongside Deferred.refreshed.clear().
        for _ in 0..2 {
            list.gate.title_written();
            list.use_heap(&heap);
        }
        assert_eq!(list.refreshes, [37, 37, 37]);
        assert_eq!(list.retained.len(), 1);
    }

    #[test]
    fn two_heaps_do_not_suppress_disjoint_ranges_of_the_same_copy() {
        let copy = Arc::new(37);
        let heaps: Vec<_> = [(0, 4), (8, 12)]
            .into_iter()
            .map(|(from, to)| {
                let mut cache = Cache::default();
                Heap {
                    strides: Arc::new(1),
                    snapshot: cache.snapshot(
                        7,
                        0,
                        Vec::new,
                        || vec![0],
                        |_| {
                            Some(Span {
                                copy: copy.clone(),
                                from,
                                to,
                            })
                        },
                    ),
                }
            })
            .collect();
        let mut list = List::default();
        for heap in &heaps {
            list.use_heap(heap);
        }
        assert_eq!(list.ranges, [(0, 4), (8, 12)]);
        assert_eq!(list.retained.len(), 2);
    }

    #[test]
    fn a_recreated_heap_cannot_reuse_a_retired_heaps_identity() {
        let first = Heap::new(37);
        let id = first.snapshot.heap;
        let mut list = List::default();
        list.use_heap(&first);
        drop(first);
        let second = Heap::new(37);
        assert_ne!(id, second.snapshot.heap);
        list.use_heap(&second);
        assert_eq!(list.refreshes, [37, 37]);
    }

    #[test]
    fn unchanged_heap_reuses_its_snapshot_without_resolving_descriptors() {
        let mut cache = Cache::default();
        let copy = Arc::new(37);
        let first = cache.snapshot(
            0,
            1,
            || vec![0],
            || vec![0],
            |_| {
                Some(Span {
                    copy: copy.clone(),
                    from: 0,
                    to: 4,
                })
            },
        );
        let again = cache.snapshot(
            0,
            1,
            || panic!("unchanged revision must not drain"),
            || panic!("unchanged revision must not scan"),
            |_| panic!("unchanged revision must not resolve"),
        );
        let next_frame = cache.snapshot(
            1,
            1,
            Vec::new,
            || panic!("not due for a full scan"),
            |_| panic!("no changed slots"),
        );
        assert!(Arc::ptr_eq(&first.spans, &again.spans));
        assert!(Arc::ptr_eq(&first.spans, &next_frame.spans));
        assert_eq!(first.generation, next_frame.generation);
    }

    #[test]
    fn changed_slots_replace_and_remove_the_old_range() {
        let mut cache = Cache::default();
        let copy = Arc::new(37);
        let first = cache.snapshot(
            0,
            1,
            Vec::new,
            || vec![0, 1],
            |index| {
                Some(Span {
                    copy: copy.clone(),
                    from: u64::from(index) * 8,
                    to: u64::from(index) * 8 + 4,
                })
            },
        );
        assert_eq!((first.spans[0].from, first.spans[0].to), (0, 12));
        let changed = cache.snapshot(0, 2, || vec![1], || panic!("incremental"), |_| None);
        assert_eq!((changed.spans[0].from, changed.spans[0].to), (0, 4));
        assert!(changed.generation > first.generation);
        let mut list = List::default();
        let mut heap = Heap {
            strides: Arc::new(1),
            snapshot: first,
        };
        list.use_heap(&heap);
        heap.snapshot = changed;
        list.use_heap(&heap);
        assert_eq!(list.ranges, [(0, 12), (0, 4)]);
        assert_eq!(list.retained.len(), 1);
    }

    #[test]
    fn periodic_resolution_tracks_copy_identity_even_without_descriptor_writes() {
        let mut cache = Cache::default();
        let original = Arc::new(37);
        let first = cache.snapshot(
            0,
            1,
            Vec::new,
            || vec![0],
            |_| {
                Some(Span {
                    copy: original.clone(),
                    from: 0,
                    to: 4,
                })
            },
        );
        for frame in 1..16 {
            let same = cache.snapshot(
                frame,
                1,
                Vec::new,
                || panic!("not yet due"),
                |_| panic!("no changes"),
            );
            assert!(Arc::ptr_eq(&first.spans, &same.spans));
        }
        let replacement = Arc::new(91);
        let changed = cache.snapshot(
            16,
            1,
            Vec::new,
            || vec![0],
            |_| {
                Some(Span {
                    copy: replacement.clone(),
                    from: 0,
                    to: 4,
                })
            },
        );
        assert_eq!(*changed.spans[0].copy, 91);
        assert!(changed.generation > first.generation);
    }

    #[test]
    fn write_during_discovery_is_not_consumed_as_a_newer_revision() {
        let mut cache = Cache::default();
        let revision = AtomicU64::new(1);
        let copy = Arc::new(37);
        cache.snapshot(
            0,
            revision.load(Ordering::Acquire),
            || {
                revision.store(2, Ordering::Release);
                vec![0]
            },
            || vec![0],
            |_| {
                Some(Span {
                    copy: copy.clone(),
                    from: 0,
                    to: 4,
                })
            },
        );
        let drained = Cell::new(false);
        cache.snapshot(
            0,
            revision.load(Ordering::Acquire),
            || {
                drained.set(true);
                vec![]
            },
            || panic!("same frame"),
            |_| panic!("empty delta"),
        );
        assert!(drained.get(), "newer revision must still be inspected");
    }

    #[test]
    fn unchanged_full_scan_reuses_the_snapshot_allocation() {
        let mut cache = Cache::default();
        let copy = Arc::new(37);
        let mut first = None;
        for frame in 0..=16 {
            let snapshot = cache.snapshot(
                frame,
                1,
                Vec::new,
                || vec![0],
                |_| {
                    Some(Span {
                        copy: copy.clone(),
                        from: 0,
                        to: 4,
                    })
                },
            );
            if let Some(first) = &first {
                assert!(Arc::ptr_eq(first, &snapshot.spans));
            } else {
                first = Some(snapshot.spans);
            }
        }
    }

    #[test]
    fn oversized_views_are_clipped_before_they_become_dependency_ranges() {
        let copy = Arc::new(37);
        let span = Span::bounded(copy.clone(), (100, 16), 104, u64::MAX).unwrap();
        assert_eq!((span.from, span.to), (104, 116));
        let short = Span::bounded(copy.clone(), (100, 16), 104, 4).unwrap();
        assert_eq!((short.from, short.to), (104, 108));
        for (extent, from, len) in [
            ((100, 16), 99, 4),
            ((100, 16), 116, 4),
            ((100, 16), 104, 0),
            ((u64::MAX, 2), u64::MAX, 1),
        ] {
            assert!(Span::bounded(copy.clone(), extent, from, len).is_none());
        }
    }

    #[test]
    fn duplicate_extrema_are_counted_until_their_last_view_is_removed() {
        let mut cache = Cache::default();
        let copy = Arc::new(37);
        let first = cache.snapshot(
            0,
            1,
            Vec::new,
            || vec![0, 1, 2],
            |index| {
                let (from, to) = if index == 2 { (4, 8) } else { (0, 12) };
                Some(Span {
                    copy: copy.clone(),
                    from,
                    to,
                })
            },
        );
        let one_removed = cache.snapshot(0, 2, || vec![0], Vec::new, |_| None);
        assert!(Arc::ptr_eq(&first.spans, &one_removed.spans));
        let both_removed = cache.snapshot(0, 3, || vec![1], Vec::new, |_| None);
        assert_eq!(
            (both_removed.spans[0].from, both_removed.spans[0].to),
            (4, 8)
        );
        let empty = cache.snapshot(0, 4, || vec![2], Vec::new, |_| None);
        assert!(empty.spans.is_empty());
        assert!(empty.generation > both_removed.generation);
    }

    #[test]
    fn moving_one_slot_between_copies_preserves_other_slots_and_old_snapshots() {
        let mut cache = Cache::default();
        let a = Arc::new(37);
        let b = Arc::new(91);
        let first = cache.snapshot(
            0,
            1,
            Vec::new,
            || vec![0, 1],
            |index| {
                Some(Span {
                    copy: a.clone(),
                    from: u64::from(index) * 8,
                    to: u64::from(index) * 8 + 4,
                })
            },
        );
        let second = cache.snapshot(
            0,
            2,
            || vec![0],
            Vec::new,
            |_| {
                Some(Span {
                    copy: b.clone(),
                    from: 20,
                    to: 24,
                })
            },
        );
        let mut ranges: Vec<_> = second
            .spans
            .iter()
            .map(|s| (*s.copy, s.from, s.to))
            .collect();
        ranges.sort_unstable();
        assert_eq!(ranges, [(37, 8, 12), (91, 20, 24)]);
        assert_eq!((first.spans[0].from, first.spans[0].to), (0, 12));
    }

    #[test]
    fn swapping_extrema_in_one_changed_batch_reuses_the_same_union() {
        let mut cache = Cache::default();
        let copy = Arc::new(37);
        let first = cache.snapshot(
            0,
            1,
            Vec::new,
            || vec![0, 1],
            |index| {
                let from = u64::from(index) * 8;
                Some(Span {
                    copy: copy.clone(),
                    from,
                    to: from + 4,
                })
            },
        );
        let swapped = cache.snapshot(
            0,
            2,
            || vec![0, 1],
            Vec::new,
            |index| {
                let from = u64::from(1 - index) * 8;
                Some(Span {
                    copy: copy.clone(),
                    from,
                    to: from + 4,
                })
            },
        );
        assert!(Arc::ptr_eq(&first.spans, &swapped.spans));
        assert_eq!(first.generation, swapped.generation);
    }

    #[test]
    fn legacy_disabled_policy_preserves_its_original_order_and_decisions() {
        let events = std::cell::RefCell::new(vec![]);
        let frame = AtomicU64::new(u64::MAX);
        assert_eq!(
            record_use(
                |_| {
                    events.borrow_mut().push(1);
                    true
                },
                || events.borrow_mut().push(2),
                &frame,
                || {
                    events.borrow_mut().push(3);
                    7
                }
            ),
            Some(7)
        );
        assert_eq!(*events.borrow(), [1, 2, 3]);
        assert_eq!(
            record_use(
                |_| false,
                || panic!("already used"),
                &frame,
                || panic!("must not read frame")
            ),
            None
        );
        assert_eq!(record_use(|_| true, || {}, &frame, || 7), None);
    }
}
