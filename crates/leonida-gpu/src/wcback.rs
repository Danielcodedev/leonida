//! Write-combined title memory, and leaving what shaders write in its copies
//! on the card (`LEONIDA_WC_NO_BACK`). Ported from readmet3xt-lab/foxhound
//! (50c15a1, 2f81d0c), docs/notes/2026-11-27-wc-no-back.md.
//!
//! The title asks for some of its memory write-combined (the console's
//! 0x400 protection bit, which `xmem` drops before the host sees it): memory
//! its CPU writes and the GPU reads. Reading it back is uncached on the
//! console, so results the title's CPU reads go to cacheable memory.
//! foxhound measured, on a 4070 SUPER, about 360 of 730 MB a frame of the
//! ranges compared after submissions in such memory.

use std::collections::BTreeMap;
use std::sync::RwLock;
#[cfg(feature = "diagnostics")]
use std::sync::atomic::{AtomicU64, Ordering};

/// Title memory asked for write-combined, as disjoint `[start, end)` keyed
/// by start (regions next to each other are one).
#[derive(Default)]
pub(crate) struct Regions(BTreeMap<u64, u64>);

impl Regions {
    /// `[at, end)` is write-combined.
    pub(crate) fn note(&mut self, at: u64, end: u64) {
        if at >= end {
            return;
        }
        // Disjoint and sorted: going down from the last region that starts
        // at or before `end`, the ends go down too.
        let touching: Vec<(u64, u64)> = self
            .0
            .range(..=end)
            .rev()
            .take_while(|&(_, &to)| to >= at)
            .map(|(&from, &to)| (from, to))
            .collect();
        let (mut from, mut to) = (at, end);
        for (start, stop) in touching {
            self.0.remove(&start);
            from = from.min(start);
            to = to.max(stop);
        }
        self.0.insert(from, to);
    }

    /// `[at, end)` is no longer write-combined; the rest of a region it cuts
    /// stays.
    pub(crate) fn forget(&mut self, at: u64, end: u64) {
        if at >= end {
            return;
        }
        let overlapping: Vec<(u64, u64)> = self
            .0
            .range(..end)
            .rev()
            .take_while(|&(_, &to)| to > at)
            .map(|(&from, &to)| (from, to))
            .collect();
        for (start, stop) in overlapping {
            self.0.remove(&start);
            if start < at {
                self.0.insert(start, at);
            }
            if stop > end {
                self.0.insert(end, stop);
            }
        }
    }

    /// Whether all of `[at, at + len)` is write-combined.
    pub(crate) fn covers(&self, at: u64, len: u64) -> bool {
        let Some(end) = at.checked_add(len) else {
            return false;
        };
        len > 0
            && self
                .0
                .range(..=at)
                .next_back()
                .is_some_and(|(_, &to)| end <= to)
    }
}

static WRITE_COMBINED: RwLock<Regions> = RwLock::new(Regions(BTreeMap::new()));

/// The title was given `[at, at + len)` (`XMemVirtualAlloc`, a reservation
/// or a commit); `write_combined`: whether it asked for that memory
/// write-combined. Noted only with [`on`]: nothing else reads it.
///
/// shortcut: the title's `VirtualFree` goes to the host unseen, so a region
/// is forgotten only when `xmem` gives the memory out again without the bit;
/// memory freed and taken again by a host allocation outside `xmem` would
/// still count as write-combined (TODO P-10).
pub fn title_memory_write_combined(at: usize, len: usize, write_combined: bool) {
    if !on() || len == 0 {
        return;
    }
    let (at, end) = (at as u64, (at as u64).saturating_add(len as u64));
    let mut all = WRITE_COMBINED.write().unwrap_or_else(|e| e.into_inner());
    if write_combined {
        all.note(at, end);
    } else {
        all.forget(at, end);
    }
}

/// Whether what shaders write into a host copy with two sides
/// (`crate::shadow::cards`) of `[start, start + len)` stays on the card:
/// with [`on`], a copy of at least [`min_bytes`] that lies all in
/// write-combined title memory.
pub(crate) fn left_on_card(start: u64, len: u64) -> bool {
    on() && stays(
        &WRITE_COMBINED.read().unwrap_or_else(|e| e.into_inner()),
        start,
        len,
        min_bytes(),
    )
}

/// [`left_on_card`] with the regions and the floor given.
fn stays(regions: &Regions, start: u64, len: u64, min: u64) -> bool {
    len >= min && regions.covers(start, len)
}

/// Whether shader writes into big copies of write-combined title memory
/// stay on the card: not hashed, compared, fetched or merged into title
/// memory after the submission (`LEONIDA_WC_NO_BACK=1`; off by default, read
/// once at the first allocation). Copies whose memory is not write-watched
/// (`Shadow::unwatched`) keep their write-back: each refresh sends their
/// whole range up, over what shaders wrote. That is known from the first
/// refresh that finds it, so the lists before it still skip it.
///
/// shortcut: on the console the GPU writes title memory itself; here what
/// shaders wrote in such a copy never reaches title memory, which this
/// assumes the title's CPU does not read (write-combined memory is what the
/// CPU writes and the GPU reads). What it risks:
/// - The title's CPU reading what shaders wrote there reads older bytes.
/// - A 64 KiB page the title writes goes up whole from title memory, and
///   with no write-back that loses what shaders wrote in the rest of the
///   page (foxhound's pages were 4 KiB). The byte-exact merge for ranges
///   still in flight (`Shadow::merge_under_writes`) does not apply either:
///   nothing of these copies is pending.
/// - Another host copy of the same bytes (a texture placed there) does not
///   see what shaders wrote through title memory.
///
/// The floor ([`min_bytes`]) is what keeps the picture: with every
/// write-combined copy left on the card, foxhound's cutscenes went near
/// black on a 4070 SUPER (small results the title reads back came back
/// stale), while most of the saving is in a few ranges of hundreds of MB.
pub(crate) fn on() -> bool {
    static ON: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *ON.get_or_init(|| {
        let on = std::env::var_os("LEONIDA_WC_NO_BACK").is_some_and(|v| v == "1");
        if on {
            tracing::info!(
                min_kb = min_bytes() / 1024,
                "what shaders write into card copies of write-combined title memory is not \
                 copied back (LEONIDA_WC_NO_BACK=1, copies of LEONIDA_WC_NO_BACK_MIN_KB or more)"
            );
        }
        on
    })
}

/// The default of `LEONIDA_WC_NO_BACK_MIN_KB`: 16 MiB. Copies with two
/// sides start at 1 MiB by default (`LEONIDA_CARD_BUFFERS_MIN_MB`), so
/// write-combined copies of 1 to 16 MiB keep their write-back. foxhound's
/// launcher sets 1024 (its 1 MB run kept the picture and saved more than
/// its 16 MB one); 16 MiB is the more careful start until it is measured
/// here.
const MIN_KB: u64 = 16 * 1024;

/// The smallest copy [`on`] leaves on the card, in bytes:
/// `LEONIDA_WC_NO_BACK_MIN_KB` (KiB, default 16384; 0: every copy, which
/// foxhound saw turn cutscenes near black).
fn min_bytes() -> u64 {
    static MIN: std::sync::OnceLock<u64> = std::sync::OnceLock::new();
    *MIN.get_or_init(|| {
        parse_min_kb(std::env::var("LEONIDA_WC_NO_BACK_MIN_KB").ok().as_deref())
    })
}

/// `LEONIDA_WC_NO_BACK_MIN_KB`'s value in bytes; unset or not a number:
/// the default.
fn parse_min_kb(value: Option<&str>) -> u64 {
    value
        .and_then(|v| v.trim().parse::<u64>().ok())
        .unwrap_or(MIN_KB)
        .saturating_mul(1024)
}

/// Bytes shaders were declared to write in copies [`left_on_card`] and that
/// were not copied back, since the last frame-rate line. An upper bound:
/// each draw or dispatch that binds a range declares it again, and these
/// are added before `Shadow::writing` drops repeats, so it is not the same
/// measure as `crate::shadow::back_line`'s bytes.
#[cfg(feature = "diagnostics")]
static LEFT: AtomicU64 = AtomicU64::new(0);

/// Shaders were declared to write `bytes` of a copy [`left_on_card`].
#[cfg(feature = "diagnostics")]
pub(crate) fn left(bytes: u64) {
    LEFT.fetch_add(bytes, Ordering::Relaxed);
}

/// The frame-rate line's figure of what was not copied back.
#[cfg(feature = "diagnostics")]
pub(crate) fn line(frames: f64) {
    let left = LEFT.swap(0, Ordering::Relaxed);
    if on() {
        tracing::info!(
            "declared shader writes into write-combined copies not copied back per frame \
             (LEONIDA_WC_NO_BACK, repeats counted, an upper bound): {:.1} MB",
            left as f64 / 1e6 / frames
        );
    }
}

#[cfg(test)]
mod tests {
    use super::{MIN_KB, Regions, parse_min_kb, stays};

    /// A range counts only inside one region; regions next to each other
    /// join, and what is forgotten is cut out of them.
    #[test]
    fn regions() {
        let mut all = Regions::default();
        all.note(0x1000_0000, 0x1100_0000);
        assert!(all.covers(0x1000_0000, 0x1000));
        assert!(all.covers(0x10ff_f000, 0x1000));
        assert!(!all.covers(0x10ff_f000, 0x2000), "past its end");
        assert!(!all.covers(0x0fff_f000, 0x2000), "before its start");
        assert!(!all.covers(0x1000_0000, 0), "nothing");

        all.note(0x1100_0000, 0x1200_0000);
        assert!(all.covers(0x10ff_f000, 0x2000), "two allocations side by side");
        assert_eq!(all.0.len(), 1);
        all.note(0x1080_0000, 0x1090_0000);
        assert_eq!(all.0.len(), 1, "a commit inside a reservation");

        all.forget(0x1080_0000, 0x1081_0000);
        assert!(!all.covers(0x1080_0000, 0x1000), "given out again plain");
        assert!(!all.covers(0x1000_0000, 0x200_0000), "across the hole");
        assert!(all.covers(0x1000_0000, 0x80_0000));
        assert!(all.covers(0x1081_0000, 0x1000));
        assert_eq!(all.0.len(), 2);

        all.forget(0, u64::MAX);
        assert!(all.0.is_empty());
        assert!(!all.covers(u64::MAX, 2), "no overflow");
    }

    /// The floor: unset or not a number is 16 MiB, 0 is every copy, and a
    /// copy below it is copied back even in write-combined memory.
    #[test]
    fn floor() {
        let mut all = Regions::default();
        all.note(0x2_0000_0000, 0x2_8000_0000);
        let floor = parse_min_kb(None);
        assert!(!stays(&all, 0x2_0000_0000, 1 << 20, floor), "1 MiB under 16");
        assert!(stays(&all, 0x2_0000_0000, 16 << 20, floor));
        assert!(stays(&all, 0x2_0000_0000, 0x1000, 0), "no floor");
        assert!(!stays(&all, 0x1_0000_0000, 16 << 20, floor), "not write-combined");

        assert_eq!(parse_min_kb(None), 16 << 20);
        assert_eq!(MIN_KB * 1024, 16 << 20);
        assert_eq!(parse_min_kb(Some("1024")), 1 << 20);
        assert_eq!(parse_min_kb(Some(" 0 ")), 0);
        assert_eq!(parse_min_kb(Some("16MB")), 16 << 20);
        assert_eq!(parse_min_kb(Some("18446744073709551615")), u64::MAX);
    }
}
