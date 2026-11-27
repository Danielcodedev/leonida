// Included inside indirect::tests to share its authored device/resource harness.
mod independent_gpu_tests {
    use super::*;
    use crate::independent::Replay;
    use leonida_shader::emit::IndependentWaves;
    use std::time::{Duration, Instant};

    const WORK: &str = r#"
#define RS "UAV(u0), UAV(u1), RootConstants(num32BitConstants=4, b0, space=3)"
RWByteAddressBuffer hits : register(u0);
RWByteAddressBuffer original : register(u1);
cbuffer Wave : register(b0, space3) { uint wave; uint unused0; uint unused1; uint unused2; };
[RootSignature(RS)]
[numthreads(64, 1, 1)]
void main(uint lane : SV_GroupIndex, uint3 group : SV_GroupID) {
    uint previous;
    hits.InterlockedAdd(4 * (64 * wave + lane), 1, previous);
    // A later replay must still read the private snapshot, not these changed arguments.
    if (wave == 0 && lane == 0 && all(group == 0)) original.Store3(16, uint3(0, 0, 0));
}
"#;

    /// No error after Execute may unwind and drop resources the queue still owns.
    fn finish_bounded(gpu: &mut WarpHarness) {
        gpu.submitted += 1;
        // SAFETY: the authored test owns this open list and allocator.
        let command = unsafe {
            gpu.list.Close().unwrap();
            gpu.list.cast::<ID3D12CommandList>().unwrap()
        };
        // SAFETY: every owner stays in the caller's scope until this fence completes.
        unsafe {
            gpu.queue.ExecuteCommandLists(&[Some(command)]);
            if let Err(error) = gpu.queue.Signal(&gpu.fence, gpu.submitted) {
                eprintln!("independent-wave test Signal failed: {error}");
                std::process::abort();
            }
        }
        let started = Instant::now();
        loop {
            // SAFETY: a retained live fence, queried without blocking.
            let completed = unsafe { gpu.fence.GetCompletedValue() };
            if completed == u64::MAX || started.elapsed() >= Duration::from_secs(5) {
                eprintln!(
                    "independent-wave test lost the device or exceeded its five-second fence"
                );
                std::process::abort();
            }
            if completed >= gpu.submitted {
                break;
            }
            std::thread::sleep(Duration::from_millis(1));
        }
        // SAFETY: the exact submission fence completed before allocator/list reuse.
        unsafe {
            gpu.allocator.Reset().unwrap();
            gpu.list.Reset(&gpu.allocator, None).unwrap();
        }
    }

    #[test]
    #[ignore = "explicit authored device test; set LEONIDA_TEST_INDEPENDENT_RUNTIME"]
    fn independent_runtime_replays_and_charges_original_work() {
        // This test must never create a device merely because the CPU suite runs.
        let Some(mode) = std::env::var("LEONIDA_TEST_INDEPENDENT_RUNTIME").ok() else {
            return;
        };
        let mut gpu = match mode.as_str() {
            "warp" => WarpHarness::new().expect("an explicitly requested software adapter"),
            "hardware" => {
                let host = super::super::host().expect("an explicitly requested hardware device");
                // SAFETY: a read-only query of the device's actual adapter.
                let description = unsafe {
                    CreateDXGIFactory2::<IDXGIFactory4>(DXGI_CREATE_FACTORY_FLAGS(0))
                        .unwrap()
                        .EnumAdapterByLuid::<IDXGIAdapter1>(host.device.GetAdapterLuid())
                        .unwrap()
                        .GetDesc1()
                        .unwrap()
                };
                assert_eq!(description.Flags & DXGI_ADAPTER_FLAG_SOFTWARE.0 as u32, 0);
                WarpHarness::on_device(host.device.clone()).expect("authored runtime harness")
            }
            _ => panic!("LEONIDA_TEST_INDEPENDENT_RUNTIME must be warp or hardware"),
        };
        let worker = compile_cs(&gpu.device, WORK).expect("authored replay worker");
        let admission = make_from(&gpu.device, include_str!("independent_bound.hlsl"))
            .expect("production argument admission helper");
        let signature = gpu.signature(2, 12);
        const CAP: u32 = 1 << 27;
        // (indirect, original threads, original grid, budget before, accepted, budget after)
        let cases = [
            (false, 128, [2, 3, 1], 0, true, 0),
            (false, 1024, [1, 1, 1], 0, true, 0),
            (false, 128, [0, 3, 1], 0, false, 0),
            (false, 128, [65536, 1, 1], 0, false, 0),
            (true, 128, [2, 3, 1], 0, true, 768),
            (true, 1024, [1, 1, 1], 0, true, 1024),
            (true, 128, [2, 3, 1], CAP - 768, true, CAP),
            (true, 128, [2, 3, 1], CAP - 767, false, CAP),
            (true, 128, [1, 1, 1], CAP, false, CAP),
            (true, 128, [1, 1, 1], u32::MAX, false, u32::MAX),
            (true, 128, [0, 3, 1], 9, false, 9),
            (true, 128, [65536, 1, 1], 9, false, 9),
            (true, 128, [65535, 65535, 1], 9, false, 9),
        ];
        for (case, (indirect, threads, groups, spent, accepted, charged)) in
            cases.into_iter().enumerate()
        {
            let waves = IndependentWaves::new([threads, 1, 1]).unwrap();
            let replay = Replay::new(waves, 2, 4).unwrap();
            let (source, source_ptr, source_gpu) = gpu.shared_buffer(64);
            let (hits, hits_ptr, hits_gpu) = gpu.shared_buffer(4096);
            let (budget, budget_ptr, budget_gpu) = gpu.shared_buffer(256);
            let scratch = gpu.default_uav(12);
            let (copy, copy_ptr, _) = gpu.shared_buffer(64);
            // SAFETY: these mappings are newly allocated and no GPU work is pending.
            unsafe {
                std::ptr::write_bytes(source_ptr, 0xff, 64);
                std::ptr::copy_nonoverlapping(groups.as_ptr(), source_ptr.add(16).cast(), 3);
                std::ptr::write_bytes(hits_ptr, 0, 4096);
                budget_ptr.cast::<u32>().write_volatile(spent);
                gpu.list.ResourceBarrier(&[
                    transition(
                        &source,
                        D3D12_RESOURCE_STATE_COMMON,
                        if indirect {
                            D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE
                        } else {
                            D3D12_RESOURCE_STATE_UNORDERED_ACCESS
                        },
                    ),
                    transition(
                        &hits,
                        D3D12_RESOURCE_STATE_COMMON,
                        D3D12_RESOURCE_STATE_UNORDERED_ACCESS,
                    ),
                    transition(
                        &budget,
                        D3D12_RESOURCE_STATE_COMMON,
                        D3D12_RESOURCE_STATE_UNORDERED_ACCESS,
                    ),
                ]);
            }
            if indirect {
                assert!(replay.indirect(2, 32, 1, false).is_ok());
                record_independent(
                    &admission,
                    &gpu.list,
                    (&scratch, D3D12_RESOURCE_STATE_COMMON),
                    budget_gpu,
                    (source_gpu, 16),
                    waves,
                )
                .unwrap();
                // SAFETY: the helper has finished reading the original record before
                // the worker may overwrite it. The private snapshot remains indirect.
                unsafe {
                    gpu.list.ResourceBarrier(&[transition(
                        &source,
                        D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE,
                        D3D12_RESOURCE_STATE_UNORDERED_ACCESS,
                    )]);
                }
            }
            let binds = std::cell::Cell::new(0);
            let bind = || {
                binds.set(binds.get() + 1);
                // SAFETY: every resource and pipeline is owned through the final fence.
                unsafe {
                    gpu.list.SetComputeRootSignature(&worker.root);
                    gpu.list.SetPipelineState(&worker.pso);
                    gpu.list.SetComputeRootUnorderedAccessView(0, hits_gpu);
                    gpu.list.SetComputeRootUnorderedAccessView(1, source_gpu);
                }
                true
            };
            let issued = if indirect {
                replay.issue_indirect(&gpu.list, &signature, &scratch, bind)
            } else {
                replay.issue_direct(&gpu.list, groups, bind)
            };
            assert_eq!(issued, indirect || accepted);
            assert_eq!(binds.get(), usize::from(indirect || accepted));
            if indirect {
                // SAFETY: preserve the admitted record for a CPU check after all its reads.
                unsafe {
                    gpu.list.ResourceBarrier(&[
                        transition(
                            &scratch,
                            D3D12_RESOURCE_STATE_INDIRECT_ARGUMENT,
                            D3D12_RESOURCE_STATE_COPY_SOURCE,
                        ),
                        transition(
                            &copy,
                            D3D12_RESOURCE_STATE_COMMON,
                            D3D12_RESOURCE_STATE_COPY_DEST,
                        ),
                    ]);
                    gpu.list.CopyBufferRegion(&copy, 0, &scratch, 0, 12);
                }
            }
            finish_bounded(&mut gpu);
            let expected = if accepted {
                groups.into_iter().product()
            } else {
                0
            };
            // SAFETY: the actual fence completed; all mappings still have their resource owners.
            unsafe {
                let values = std::slice::from_raw_parts(hits_ptr.cast::<u32>(), 1024);
                assert!(
                    values[..threads as usize].iter().all(|&n| n == expected),
                    "case {case}: each original lane runs the same original group grid"
                );
                assert!(values[threads as usize..].iter().all(|&n| n == 0));
                assert_eq!(
                    budget_ptr.cast::<u32>().read_volatile(),
                    charged,
                    "case {case}"
                );
                if indirect {
                    let snapshot = std::slice::from_raw_parts(copy_ptr.cast::<u32>(), 3);
                    assert_eq!(snapshot, if accepted { groups } else { [0, 0, 0] });
                }
                if accepted {
                    assert_eq!(
                        std::slice::from_raw_parts(source_ptr.add(16).cast::<u32>(), 3),
                        [0, 0, 0],
                        "the first wave changed the original arguments"
                    );
                }
            }
            eprintln!("independent runtime case {case}: indirect={indirect}, accepted={accepted}");
        }
    }
}
