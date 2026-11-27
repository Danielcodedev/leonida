//! Constant-buffer descriptions and the upload path for fresh descriptor tables.

/// The two fields passed to the native constant-buffer descriptor creation call.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) struct Description {
    pub(crate) address: u64,
    pub(crate) size: u32,
}

impl Description {
    pub(crate) fn new(address: u64, size: u32) -> Self {
        if is_null(address, size) {
            return Self::default();
        }
        Self {
            address,
            size: size.next_multiple_of(256),
        }
    }

    #[cfg(windows)]
    pub(crate) fn native(
        self,
    ) -> windows::Win32::Graphics::Direct3D12::D3D12_CONSTANT_BUFFER_VIEW_DESC {
        windows::Win32::Graphics::Direct3D12::D3D12_CONSTANT_BUFFER_VIEW_DESC {
            BufferLocation: self.address,
            SizeInBytes: self.size,
        }
    }
}

/// Zero location is a null CBV. D3D12 also makes a zero-sized view unbound and
/// ignores its address. Canonicalize both forms before making an upload.
pub(crate) fn is_null(address: u64, size: u32) -> bool {
    address == 0 || size == 0
}

/// Allocates and schedules the title bytes only for a nonempty constant buffer.
/// A missing allocation still needs a null CBV, rather than a null texture SRV.
pub(crate) fn upload(
    address: u64,
    size: u32,
    scratch: impl FnOnce(u64) -> Option<(u64, *mut u8)>,
    fill: impl FnOnce(*mut u8, *const u8, usize),
) -> Description {
    if is_null(address, size) {
        return Description::default();
    }
    let Some((gpu, to)) = scratch(u64::from(size)) else {
        return Description::default();
    };
    fill(to, address as *const u8, size as usize);
    Description::new(gpu, size)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::descriptor::{View, create_cbv, view};
    use std::cell::Cell;

    /// Start with the same title descriptor record the table walker decodes.
    fn from_record(address: u64, size: u32) -> (Description, usize, usize) {
        let mut record = [0u64; 4];
        let handle = record.as_mut_ptr() as u64;
        create_cbv(
            std::ptr::null(),
            &[address as u32, (address >> 32) as u32, size, 0],
            handle,
        );
        let View::Constant(address, size) = view(handle).expect("constant record") else {
            panic!("wrong descriptor type");
        };
        let allocations = Cell::new(0);
        let fills = Cell::new(0);
        let desc = upload(
            address,
            size,
            |bytes| {
                assert_eq!(bytes, u64::from(size));
                allocations.set(allocations.get() + 1);
                Some((0x10000, std::ptr::dangling_mut()))
            },
            |_, source, bytes| {
                assert_eq!((source as u64, bytes), (address, size as usize));
                fills.set(fills.get() + 1);
            },
        );
        (desc, allocations.get(), fills.get())
    }

    #[test]
    fn null_table_cbv_never_allocates_or_copies() {
        for (address, size) in [(0, 0), (0, 256), (0x20000, 0)] {
            assert_eq!(from_record(address, size), (Description::default(), 0, 0));
        }
    }

    #[test]
    fn nonempty_table_cbv_keeps_its_upload_and_alignment() {
        for (size, aligned) in [(1, 256), (96, 256), (256, 256), (257, 512), (65536, 65536)] {
            assert_eq!(
                from_record(0x20010, size),
                (
                    Description {
                        address: 0x10000,
                        size: aligned
                    },
                    1,
                    1
                )
            );
        }
    }

    #[test]
    fn failed_upload_is_a_null_cbv_without_a_copy() {
        let desc = upload(
            0x20000,
            96,
            |_| None,
            |_, _, _| panic!("no allocation to fill"),
        );
        assert_eq!(desc, Description::default());
    }

    #[test]
    fn native_description_preserves_null_and_empty_views() {
        for (address, size) in [(0, 0), (0, 256), (0x10000, 0)] {
            assert_eq!(Description::new(address, size), Description::default());
        }
        assert_eq!(
            Description::new(0x10000, 96),
            Description {
                address: 0x10000,
                size: 256
            }
        );
    }

    #[cfg(windows)]
    #[test]
    fn native_fields_match_the_prepared_description() {
        for (address, size) in [(0, 0), (0, 256), (0x10000, 0), (0x10000, 96)] {
            let desc = Description::new(address, size);
            let native = desc.native();
            assert_eq!(
                (native.BufferLocation, native.SizeInBytes),
                (desc.address, desc.size)
            );
        }
    }
}
