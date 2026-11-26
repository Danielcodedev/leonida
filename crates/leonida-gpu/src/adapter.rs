//! Adapter metadata for startup settings, before any GPU switches are cached.

#[derive(Debug, Clone)]
pub struct Description {
    pub name: String,
    pub vendor_id: u32,
    pub vram_mb: u64,
}

/// Describes the adapter that `host::create` will use, without making the host
/// device or starting its workers. A failed probe leaves automatic settings
/// limited to profiles that do not require a particular card.
#[cfg(windows)]
pub fn describe() -> Result<Description, String> {
    use windows::Win32::Graphics::Dxgi::*;
    use windows::core::Interface;

    // RenderDoc must hook DXGI before the first graphics interface is created.
    // Profiles cannot change its startup variables or the WARP selection.
    #[cfg(feature = "diagnostics")]
    crate::renderdoc::load();

    let probe = || -> windows::core::Result<Description> {
        // SAFETY: DXGI queries own their returned interfaces; no title pointers
        // or D3D12 device state are accessed.
        unsafe {
            let adapter: IDXGIAdapter1 = if cfg!(feature = "diagnostics")
                && std::env::var_os("LEONIDA_D3D12_WARP").is_some_and(|v| v == "1")
            {
                crate::host::warp_adapter()?.cast()?
            } else {
                let factory: IDXGIFactory1 = CreateDXGIFactory1()?;
                // D3D12CreateDevice(None), used by the host, selects this first
                // adapter, not necessarily the one with the most memory.
                factory.EnumAdapters(0)?.cast()?
            };
            let desc = adapter.GetDesc1()?;
            let end = desc.Description.iter().position(|&c| c == 0).unwrap_or(128);
            Ok(Description {
                name: String::from_utf16_lossy(&desc.Description[..end]),
                vendor_id: desc.VendorId,
                vram_mb: (desc.DedicatedVideoMemory as u64) >> 20,
            })
        }
    };
    probe().map_err(|error| error.to_string())
}

#[cfg(not(windows))]
pub fn describe() -> Result<Description, String> {
    Err("Direct3D adapter discovery requires Windows or Wine".into())
}
