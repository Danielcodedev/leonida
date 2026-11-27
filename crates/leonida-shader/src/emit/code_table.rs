//! Program-code constant tables with bounded runtime-indexed arrays.

use super::bitcode::{Bin, Module, V, pred};

/// Keep runtime-indexed constant arrays small without discarding any addressable bytes.
/// In particular, a joined CODE address can name instruction bytes as well as appended data.
pub(super) struct CodeTable {
    chunks: Vec<(V, u32)>,
    base: u32,
    len: u32,
}

/// `LEONIDA_CODE_TABLE_CHUNKS=1` avoids large dynamically indexed constant arrays
/// rejected by the NVIDIA Vulkan compiler. Off by default until other cards are measured;
/// selecting among chunks can cost more loads. The translator fingerprint includes it.
pub(super) fn enabled() -> bool {
    static ON: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *ON.get_or_init(|| std::env::var_os("LEONIDA_CODE_TABLE_CHUNKS").is_some_and(|v| v == "1"))
}

impl CodeTable {
    const CHUNK_DWORDS: usize = 1024;

    pub(super) fn new(m: &mut Module, base: u32, words: &[u32], chunked: bool) -> Self {
        assert!(!words.is_empty());
        let i32t = m.int(32);
        // Leave arrays of at most 16 KiB in their original form. Every refused array
        // measured on this card exceeded that size; smaller tables need no extra loads.
        let chunk_len = if chunked && words.len() > 4096 {
            Self::CHUNK_DWORDS
        } else {
            words.len()
        };
        let chunks = words
            .chunks(chunk_len)
            .enumerate()
            .map(|(i, words)| {
                let elems: Vec<V> = words.iter().map(|&w| m.i32(w)).collect();
                let arr = m.array(words.len() as u32, i32t);
                let init = m.aggregate(arr, &elems);
                let name = if i == 0 {
                    "code".into()
                } else {
                    format!("code_{i}")
                };
                (m.constant_global(&name, init), words.len() as u32)
            })
            .collect();
        Self {
            chunks,
            base,
            len: words.len() as u32,
        }
    }

    pub(super) fn read(&self, m: &mut Module, block: usize, byte: V) -> V {
        // Preserve the original unsigned subtraction, dword alignment and last-word clamp.
        let base = m.i32(self.base);
        let rel = m.bin(block, Bin::Sub, byte, base);
        let two = m.i32(2);
        let index = m.bin(block, Bin::LShr, rel, two);
        let last = m.i32(self.len - 1);
        let over = m.cmp(block, pred::IUGT, index, last);
        let index = m.select(block, over, last, index);
        if self.chunks.len() == 1 {
            let at = m.element(block, self.chunks[0].0, index);
            return m.load(block, at);
        }
        let shift = m.i32(Self::CHUNK_DWORDS.trailing_zeros());
        let chunk = m.bin(block, Bin::LShr, index, shift);
        let mask = m.i32(Self::CHUNK_DWORDS as u32 - 1);
        let local = m.bin(block, Bin::And, index, mask);
        let mut result = None;
        for (i, &(global, len)) in self.chunks.iter().enumerate() {
            // Select evaluates both operands. The final, short chunk must be safe to load
            // even when another chunk is selected; full chunks already fit the local index.
            let local = if len < Self::CHUNK_DWORDS as u32 {
                let last = m.i32(len - 1);
                let over = m.cmp(block, pred::IUGT, local, last);
                m.select(block, over, last, local)
            } else {
                local
            };
            let at = m.element(block, global, local);
            let word = m.load(block, at);
            result = Some(match result {
                None => word,
                Some(previous) => {
                    let id = m.i32(i as u32);
                    let selected = m.cmp(block, pred::EQ, chunk, id);
                    m.select(block, selected, word, previous)
                }
            });
        }
        result.expect("a nonempty table")
    }
}
