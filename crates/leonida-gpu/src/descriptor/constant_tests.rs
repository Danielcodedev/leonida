//! Opt-in device check of the full fresh-table path, with authored shader input.

use super::*;
use crate::object::S_OK;
use windows::Win32::Graphics::Direct3D12::*;

const READ: &str = r#"
#define RS "DescriptorTable(CBV(b0)), UAV(u0)"
cbuffer Input : register(b0) { uint4 values[4]; };
RWByteAddressBuffer output : register(u0);
[RootSignature(RS)]
[numthreads(1, 1, 1)]
void main() {
    output.Store4(0, values[0]);
    output.Store4(16, values[3]);
}
"#;

struct TitleHeap(This);

impl Drop for TitleHeap {
    fn drop(&mut self) {
        release(self.0);
    }
}

/// No device is created unless explicitly enabled. Four one-thread dispatches
/// check null variants and a nonempty control through the real table walker.
#[test]
fn fresh_table_null_cbvs_read_zero_on_the_device() {
    if std::env::var_os("LEONIDA_TEST_NULL_CBV").is_none_or(|v| v != "1") {
        eprintln!("set LEONIDA_TEST_NULL_CBV=1 to run the device check");
        return;
    }
    let host = crate::host::host().expect("the explicitly requested test device");
    #[repr(C)]
    struct Extended(HeapDesc, Placement);
    let desc = Extended(
        HeapDesc {
            kind: 0,
            count: 4,
            flags: 1,
            nodes: 0,
        },
        Placement {
            address: 0,
            size: 0,
        },
    );
    let mut title_heap = std::ptr::null();
    assert_eq!(
        create_heap(std::ptr::null(), &desc.0, &HEAP_IIDS[0], &mut title_heap),
        S_OK,
    );
    let _owner = TitleHeap(title_heap);
    let heap = heap(title_heap);
    let native_heap = heap.host().expect("the test descriptor heap");
    let code = crate::host::compile(READ, windows::core::s!("main"), windows::core::s!("cs_5_1"))
        .expect("the authored test shader");
    // SAFETY: the shader carries its own root signature, and the bytecode stays live.
    let (root, pso): (ID3D12RootSignature, ID3D12PipelineState) = unsafe {
        let root = host
            .device
            .CreateRootSignature(0, &code)
            .expect("root signature");
        let pso = host
            .device
            .CreateComputePipelineState(&D3D12_COMPUTE_PIPELINE_STATE_DESC {
                pRootSignature: std::mem::transmute_copy(&root),
                CS: D3D12_SHADER_BYTECODE {
                    pShaderBytecode: code.as_ptr().cast(),
                    BytecodeLength: code.len(),
                },
                ..Default::default()
            })
            .expect("compute pipeline");
        (root, pso)
    };
    #[repr(align(16))]
    struct Constants([u32; 16]);
    let constants = Constants(std::array::from_fn(|i| 37 + i as u32));
    let used = [leonida_shader::native::UsedResource {
        kind: leonida_shader::native::ResourceType::Cbv,
        root: leonida_shader::native::RootType::Table,
        table_offset_dwords: 0,
        lower_bound: 0,
        stride: 0,
        dwords: 8,
        user_data: 0,
        slot: 0,
    }];
    let cases = [
        (0, 0),
        (0, 256),
        (0x10000, 0),
        (constants.0.as_ptr() as u64, 64),
    ];
    for (case, (address, size)) in cases.into_iter().enumerate() {
        let handle = heap.start + case as u64 * 32;
        create_cbv(
            std::ptr::null(),
            &[address as u32, (address >> 32) as u32, size, 0],
            handle,
        );
        let list = host.new_list().expect("test list");
        let mut state = crate::draw::State::default();
        state.set_heaps(&[title_heap]);
        state.set_table(true, 0, handle);
        let table = state.tables(&list, &used, &[], true);
        assert_eq!(table.len(), 1);
        assert_eq!(table[0].0, 0);
        assert_ne!(table[0].1, u32::MAX);
        if case < 3 {
            assert_eq!(list.scratch_kept(), 0, "null case {case} allocated scratch");
        } else {
            assert!(list.scratch_kept() > 0, "nonempty control must upload");
        }
        let output = host.uav_buffer(32).expect("output");
        let readback = host.read_back_buffer(32).expect("readback");
        // SAFETY: a private completion fence, created before submitting any work.
        let completed: ID3D12Fence = unsafe {
            host.device
                .CreateFence(0, D3D12_FENCE_FLAG_NONE)
                .expect("completion fence")
        };
        // SAFETY: all resources, descriptors and pipeline owners live through execute;
        // the output starts in COMMON and its states follow the two barriers.
        unsafe {
            list.list
                .SetDescriptorHeaps(&[Some(native_heap.heap.clone())]);
            list.list.SetComputeRootSignature(&root);
            list.list.SetPipelineState(&pso);
            list.list
                .SetComputeRootDescriptorTable(0, native_heap.gpu_handle(table[0].1 / 32));
            list.list
                .SetComputeRootUnorderedAccessView(1, output.GetGPUVirtualAddress());
            list.list.ResourceBarrier(&[crate::host::transition(
                &output,
                D3D12_RESOURCE_STATE_COMMON,
                D3D12_RESOURCE_STATE_UNORDERED_ACCESS,
            )]);
            list.list.Dispatch(1, 1, 1);
            list.list.ResourceBarrier(&[crate::host::transition(
                &output,
                D3D12_RESOURCE_STATE_UNORDERED_ACCESS,
                D3D12_RESOURCE_STATE_COPY_SOURCE,
            )]);
            list.list.CopyBufferRegion(&readback, 0, &output, 0, 32);
        }
        list.close();
        host.execute(&[&list]);
        // execute can warn and return if its internal completion setup fails.
        // Prove completion ourselves before mapping or releasing any GPU owner.
        // SAFETY: signal the same queue after all test commands were submitted.
        if let Err(error) = unsafe { host.queue().Signal(&completed, 1) } {
            eprintln!("test completion signal failed: {error}");
            std::process::abort();
        }
        let until = std::time::Instant::now() + std::time::Duration::from_secs(5);
        loop {
            // SAFETY: query the private live fence without changing resource ownership.
            match unsafe { completed.GetCompletedValue() } {
                u64::MAX => {
                    eprintln!("device removed before test completion");
                    std::process::abort();
                }
                1.. => break,
                _ if std::time::Instant::now() >= until => {
                    eprintln!("test completion exceeded five seconds");
                    std::process::abort();
                }
                _ => std::thread::sleep(std::time::Duration::from_millis(1)),
            }
        }
        let mut mapped = std::ptr::null_mut();
        // SAFETY: execute completed the copy; exactly 32 mapped bytes are read.
        let actual = unsafe {
            readback
                .Map(
                    0,
                    Some(&D3D12_RANGE { Begin: 0, End: 32 }),
                    Some(&mut mapped),
                )
                .expect("mapped readback");
            let value = mapped.cast::<[u32; 8]>().read_unaligned();
            readback.Unmap(0, Some(&D3D12_RANGE::default()));
            value
        };
        let expected = if case < 3 {
            [0; 8]
        } else {
            [37, 38, 39, 40, 49, 50, 51, 52]
        };
        assert_eq!(actual, expected, "table case {case}");
        eprintln!("null CBV case {case}: {actual:?}");
    }
}
