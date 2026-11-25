# The D3D12 COM objects over the Vulkan backend (gta6rt_d3d12_com), their generated method stubs and their tests.
# Included by runtime/CMakeLists.txt inside if(TARGET Vulkan::Headers).

# D3D12 COM objects over the Vulkan backend. Their method stubs are generated from the SDK's d3d12.h at build
# time (tools/gen_d3d12_stubs.py), so nothing derived from the SDK header is checked in.
find_package(Python3 COMPONENTS Interpreter QUIET)
# The generator finds d3d12.h through INCLUDE, which a Developer Prompt sets. A cross build (for example
# runtime/cmake/clang-cl-xwin.cmake) has no such prompt, so it is handed the header CMake finds.
set(_stubs_header)
set(_stubs_header_ok TRUE)
if(TARGET gta6rt AND CMAKE_CROSSCOMPILING)
  find_file(LEONIDA_D3D12_HEADER d3d12.h)
  if(LEONIDA_D3D12_HEADER)
    set(_stubs_header --header "${LEONIDA_D3D12_HEADER}")
  else()
    set(_stubs_header_ok FALSE)
    message(STATUS "d3d12.h not found (set CMAKE_INCLUDE_PATH): the D3D12 COM objects are not built")
  endif()
endif()
if(TARGET gta6rt AND Python3_FOUND AND _stubs_header_ok)
  set(LEONIDA_STUBS ${CMAKE_CURRENT_BINARY_DIR}/generated/d3d12_stubs.h)
  add_custom_command(
    OUTPUT ${LEONIDA_STUBS}
    COMMAND "${Python3_EXECUTABLE}" -I ${CMAKE_CURRENT_SOURCE_DIR}/../tools/gen_d3d12_stubs.py --out ${LEONIDA_STUBS}
            ${_stubs_header}
            ID3D12GraphicsCommandList8 ID3D12CommandQueue ID3D12CommandAllocator ID3D12Fence1
            ID3D12Device11 ID3D12DescriptorHeap ID3D12Heap ID3D12Resource ID3D12QueryHeap ID3D12RootSignature
            ID3D12PipelineState ID3D12CommandSignature ID3D12PipelineLibrary1 ID3D12ShaderCacheSession
    DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/../tools/gen_d3d12_stubs.py ${LEONIDA_D3D12_HEADER}
    COMMENT "Generating D3D12 COM stubs"
    VERBATIM)
  add_library(gta6rt_d3d12_com STATIC shims/d3d12_com.cpp shims/d3d12_vulkan_device.cpp shims/d3d12_xs_device.cpp shims/xbox_present.cpp
              shims/dxgi_com.cpp ${LEONIDA_STUBS})   # d3d12_vulkan_device.cpp reads the PC device behind the proxy (#224)
  target_include_directories(gta6rt_d3d12_com PRIVATE ${CMAKE_CURRENT_BINARY_DIR}/generated)
  target_link_libraries(gta6rt_d3d12_com PUBLIC Vulkan::Headers gta6rt_root_signature)
  target_compile_definitions(gta6rt_d3d12_com PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  # /bigobj: a Debug build of d3d12_vulkan_device.cpp has more sections than a COFF object holds by default
  # (fatal error C1128), because without optimisation every inline function keeps its own COMDAT.
  target_compile_options(gta6rt_d3d12_com PRIVATE /W4 /permissive- /utf-8 /bigobj)

  add_executable(d3d12_com_test test/d3d12_com_test.cpp)
  target_link_libraries(d3d12_com_test PRIVATE gta6rt_d3d12_com)
  target_compile_definitions(d3d12_com_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_com_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_com COMMAND d3d12_com_test)
  set_tests_properties(d3d12_com PROPERTIES SKIP_RETURN_CODE 77)

  # Where the device finds its translated shaders (shader_path.txt, a path that is not UTF-8). No GPU.
  add_executable(d3d12_shader_path_test test/d3d12_shader_path_test.cpp)
  target_link_libraries(d3d12_shader_path_test PRIVATE gta6rt_d3d12_com)
  target_compile_definitions(d3d12_shader_path_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_shader_path_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_shader_path COMMAND d3d12_shader_path_test)

  # Multi-threaded concurrent submissions across two D3D12 queues + resource creation/destruction churn.
  add_executable(d3d12_multithread_test test/d3d12_multithread_test.cpp)
  target_link_libraries(d3d12_multithread_test PRIVATE gta6rt_d3d12_com)
  target_compile_definitions(d3d12_multithread_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_multithread_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_multithread COMMAND d3d12_multithread_test)
  # 300 s, not 120: the test's 60 s fence waits need headroom when other GPU tests share the device
  # (two concurrent `ctest -j 6` suites pushed it to 91-120 s; TEST-514 follow-up).
  set_tests_properties(d3d12_multithread PROPERTIES SKIP_RETURN_CODE 77 TIMEOUT 300)
  # Several threads make the first CheckFeatureSupport(D3D12_OPTIONS1) call of a new device at the same time.
  add_executable(d3d12_options1_first_use_test test/d3d12_options1_first_use_test.cpp)
  target_link_libraries(d3d12_options1_first_use_test PRIVATE gta6rt_d3d12_com)
  target_compile_definitions(d3d12_options1_first_use_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_options1_first_use_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_options1_first_use COMMAND d3d12_options1_first_use_test)
  set_tests_properties(d3d12_options1_first_use PROPERTIES SKIP_RETURN_CODE 77 TIMEOUT 120)
  # A queued Wait must not block a Signal submitted by another D3D12 queue.
  add_executable(d3d12_queue_wait_test test/d3d12_queue_wait_test.cpp)
  target_link_libraries(d3d12_queue_wait_test PRIVATE gta6rt_d3d12_com)
  target_compile_definitions(d3d12_queue_wait_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_queue_wait_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_queue_wait COMMAND d3d12_queue_wait_test)
  add_executable(d3d12_noop_copy_test test/d3d12_noop_copy_test.cpp)
  target_link_libraries(d3d12_noop_copy_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_noop_copy_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_noop_copy_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_noop_copy COMMAND d3d12_noop_copy_test)
  set_tests_properties(d3d12_noop_copy PROPERTIES SKIP_RETURN_CODE 77 TIMEOUT 45)
  set_tests_properties(d3d12_queue_wait PROPERTIES SKIP_RETURN_CODE 77 TIMEOUT 60)
  add_test(NAME d3d12_queue_wait_timeout COMMAND d3d12_queue_wait_test --timeout-control)
  # Under Ubuntu's Wine 9.0 this test runs into the 10 s without printing anything. With 60 s (9002b42) it no longer
  # did, but the tests after it stayed slow and the wine (ubuntu) job was cancelled at 30 minutes (run 45428701383);
  # with 10 s the same job passed in 694 s (run 45410688081). Why is not known yet, so the limit stays.
  set_tests_properties(d3d12_queue_wait_timeout PROPERTIES SKIP_RETURN_CODE 77 WILL_FAIL TRUE TIMEOUT 10)
  # ExecuteCommandLists refuses a list whose type isn't the queue's (debug-layer message 836).
  add_executable(d3d12_queue_list_type_test test/d3d12_queue_list_type_test.cpp)
  target_link_libraries(d3d12_queue_list_type_test PRIVATE gta6rt_d3d12_com)
  target_compile_definitions(d3d12_queue_list_type_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_queue_list_type_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_queue_list_type COMMAND d3d12_queue_list_type_test)
  set_tests_properties(d3d12_queue_list_type PROPERTIES SKIP_RETURN_CODE 77 TIMEOUT 30)
  # Cross-device ownership validation: Signal, Wait, SetEventOnMultipleFenceCompletion, ExecuteCommandLists, ExecuteBundle.
  add_executable(d3d12_cross_device_validation_test test/d3d12_cross_device_validation_test.cpp)
  target_link_libraries(d3d12_cross_device_validation_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_cross_device_validation_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_cross_device_validation_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_cross_device_validation COMMAND d3d12_cross_device_validation_test)
  set_tests_properties(d3d12_cross_device_validation PROPERTIES SKIP_RETURN_CODE 77 TIMEOUT 60
                       FAIL_REGULAR_EXPRESSION "Validation Error;VUID-")
  # Wait-before-Signal with a texture and a buffer handed over between the COPY, COMPUTE and DIRECT queues, in every
  # submission order, on the layer and on the host runtime (docs/d3d12_vulkan.md section 4.4).
  add_executable(d3d12_queue_handover_test test/d3d12_queue_handover_test.cpp)
  target_link_libraries(d3d12_queue_handover_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_queue_handover_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_queue_handover_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_queue_handover COMMAND d3d12_queue_handover_test)
  set_tests_properties(d3d12_queue_handover PROPERTIES SKIP_RETURN_CODE 77 TIMEOUT 400
                       FAIL_REGULAR_EXPRESSION "Validation Error;VUID-")
  # The same on a caller-owned device: two VkQueues handed to the layer (the D3D12 queues share them), and one
  # (every D3D12 queue shares it, where a Wait ahead of its Signal would never progress on the GPU).
  add_test(NAME d3d12_queue_handover_two_queues COMMAND d3d12_queue_handover_test --two-queues)
  add_test(NAME d3d12_queue_handover_shared_queue COMMAND d3d12_queue_handover_test --shared-queue)
  set_tests_properties(d3d12_queue_handover_two_queues d3d12_queue_handover_shared_queue PROPERTIES
                       SKIP_RETURN_CODE 77 TIMEOUT 400 FAIL_REGULAR_EXPRESSION "Validation Error;VUID-")
  # More D3D12 queues than Vulkan queues: they share VkQueues, keeping fences and Wait-before-Signal (section 4.4).
  # The _one_queue runs make every GPU look like the Intel UHD 770 (one family, one VkQueue): every queue shares it.
  add_executable(d3d12_queue_share_test test/d3d12_queue_share_test.cpp)
  target_link_libraries(d3d12_queue_share_test PRIVATE gta6rt_d3d12_com)
  target_compile_definitions(d3d12_queue_share_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_queue_share_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_queue_share COMMAND d3d12_queue_share_test)
  add_test(NAME d3d12_queue_share_one_queue COMMAND d3d12_queue_share_test)
  set_tests_properties(d3d12_queue_share d3d12_queue_share_one_queue PROPERTIES SKIP_RETURN_CODE 77 TIMEOUT 300
                       FAIL_REGULAR_EXPRESSION "Validation Error;VUID-")
  add_test(NAME d3d12_queue_wait_one_queue COMMAND d3d12_queue_wait_test)
  set_tests_properties(d3d12_queue_wait_one_queue PROPERTIES SKIP_RETURN_CODE 77 TIMEOUT 60)
  set_tests_properties(d3d12_queue_share_one_queue d3d12_queue_wait_one_queue PROPERTIES
                       ENVIRONMENT "LEONIDA_VK_MAX_QUEUES_PER_FAMILY=1;LEONIDA_VK_GRAPHICS_FAMILY_ONLY=1")
  # A misspelt case or count is refused with the usage line (exit code 2) before a device exists, instead of
  # passing with nothing run. No GPU needed.
  set(_share_bad_arguments "case_typo|--case|typo" "iterations_zero|--iterations|0"
      "iterations_word|--iterations|banana" "iterations_too_many|--iterations|99999999999")
  foreach(_bad IN LISTS _share_bad_arguments)
    string(REPLACE "|" ";" _bad "${_bad}")
    list(POP_FRONT _bad _bad_name)
    add_test(NAME d3d12_queue_share_rejects_${_bad_name} COMMAND d3d12_queue_share_test ${_bad})
    set_tests_properties(d3d12_queue_share_rejects_${_bad_name} PROPERTIES TIMEOUT 60
                         PASS_REGULAR_EXPRESSION "\nusage: d3d12_queue_share_test ")
  endforeach()

  # XDXR acceleration structures through BuildRaytracingAccelerationStructure (docs/d3d12_vulkan.md 4.8): the
  # device builds them, tools/xdxr_bvh.py checks them.
  add_executable(d3d12_xdxr_rt_test test/d3d12_xdxr_rt_test.cpp)
  target_link_libraries(d3d12_xdxr_rt_test PRIVATE gta6rt_d3d12_com)
  target_compile_definitions(d3d12_xdxr_rt_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_xdxr_rt_test PRIVATE /W4 /permissive- /utf-8)
  set(LEONIDA_D3D12_XDXR_OUT "${CMAKE_CURRENT_BINARY_DIR}/d3d12_xdxr_cases")
  file(MAKE_DIRECTORY "${LEONIDA_D3D12_XDXR_OUT}")
  add_test(NAME d3d12_xdxr_rt COMMAND d3d12_xdxr_rt_test "${LEONIDA_D3D12_XDXR_OUT}")
  set_tests_properties(d3d12_xdxr_rt PROPERTIES SKIP_RETURN_CODE 77 TIMEOUT 60 FIXTURES_SETUP d3d12_xdxr_cases)
  find_package(Python3 COMPONENTS Interpreter QUIET)
  if(Python3_FOUND)
    add_test(NAME d3d12_xdxr_rt_check COMMAND "${Python3_EXECUTABLE}" -I
             "${CMAKE_CURRENT_SOURCE_DIR}/../tools/xdxr_bvh.py" check-build "${LEONIDA_D3D12_XDXR_OUT}" --rays 1000)
    set_tests_properties(d3d12_xdxr_rt_check PROPERTIES FIXTURES_REQUIRED d3d12_xdxr_cases SKIP_RETURN_CODE 77)
  endif()

  # GCL8's QueryInterface and its one method need an allocator and a list, not a Vulkan device.
  add_executable(d3d12_gcl8_test test/d3d12_gcl8_test.cpp)
  target_link_libraries(d3d12_gcl8_test PRIVATE gta6rt_d3d12_com)
  target_compile_definitions(d3d12_gcl8_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_gcl8_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_gcl8 COMMAND d3d12_gcl8_test)
  # Python runs on the host; a cross-compiled fixture runs through the emulator (Wine), which the script prepends.
  # The interpreter is named by path, because ctest would put the emulator in front of an executable target.
  set(_trace_runner)
  foreach(_part IN LISTS CMAKE_CROSSCOMPILING_EMULATOR)
    list(APPEND _trace_runner "--runner=${_part}")  # one word each, even one that starts with "-" (xvfb-run -a)
  endforeach()
  add_test(NAME d3d12_trace COMMAND "${Python3_EXECUTABLE}" -I
           "${CMAKE_CURRENT_SOURCE_DIR}/test/check_d3d12_trace.py" "$<TARGET_FILE:d3d12_gcl8_test>" ${_trace_runner})

  # The Vulkan device behind the Xbox-ABI proxy, end to end.
  add_executable(d3d12_vulkan_device_test test/d3d12_vulkan_device_test.cpp)
  target_link_libraries(d3d12_vulkan_device_test PRIVATE gta6rt_d3d12_com dxguid)  # IID_ID3D12MetaCommand (#1440)
  target_compile_definitions(d3d12_vulkan_device_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_vulkan_device_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_vulkan_device COMMAND d3d12_vulkan_device_test)

  add_executable(d3d12_buffer_tiles_test test/d3d12_buffer_tiles_test.cpp)
  target_link_libraries(d3d12_buffer_tiles_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_buffer_tiles_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_buffer_tiles_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_buffer_tiles COMMAND d3d12_buffer_tiles_test)
  set_tests_properties(d3d12_buffer_tiles PROPERTIES SKIP_RETURN_CODE 77
                       FAIL_REGULAR_EXPRESSION "Validation Error;VUID-")
  add_executable(d3d12_texture_tiles_test test/d3d12_texture_tiles_test.cpp)
  target_link_libraries(d3d12_texture_tiles_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_texture_tiles_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_texture_tiles_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_texture_tiles COMMAND d3d12_texture_tiles_test)
  set_tests_properties(d3d12_texture_tiles PROPERTIES SKIP_RETURN_CODE 77
                       FAIL_REGULAR_EXPRESSION "Validation Error;VUID-")

  # DXR acceleration-structure prebuild and command-list recording validation parity test.
  add_executable(d3d12_dxr_validation_test test/d3d12_dxr_validation_test.cpp)
  target_link_libraries(d3d12_dxr_validation_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_dxr_validation_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_dxr_validation_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_dxr_validation COMMAND d3d12_dxr_validation_test)
  add_test(NAME d3d12_dxr_validation_khr COMMAND d3d12_dxr_validation_test)
  set_tests_properties(d3d12_dxr_validation d3d12_dxr_validation_khr PROPERTIES SKIP_RETURN_CODE 77
                       FAIL_REGULAR_EXPRESSION "Validation Error;VUID-")
  set_tests_properties(d3d12_dxr_validation_khr PROPERTIES ENVIRONMENT "LEONIDA_RT_AS=khr")

  # D3D12 permits UpdateTileMappings on DIRECT/COPY/COMPUTE and a sparse buffer must remain
  # accessible across their selected Vulkan families. The optional API-dump check catches an
  # EXCLUSIVE VkBuffer even on drivers that happen to return correct bytes without ownership barriers.
  add_executable(d3d12_sparse_queue_family_test test/d3d12_sparse_queue_family_test.cpp)
  target_link_libraries(d3d12_sparse_queue_family_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_sparse_queue_family_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_sparse_queue_family_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_sparse_queue_family COMMAND d3d12_sparse_queue_family_test)
  set_tests_properties(d3d12_sparse_queue_family PROPERTIES SKIP_RETURN_CODE 77
                       FAIL_REGULAR_EXPRESSION "Validation Error;VUID-")
  if(Python3_FOUND AND NOT CMAKE_CROSSCOMPILING)
    add_test(NAME d3d12_sparse_queue_family_contract COMMAND "${Python3_EXECUTABLE}" -I
             "${CMAKE_CURRENT_SOURCE_DIR}/test/check_sparse_queue_family.py"
             "$<TARGET_FILE:d3d12_sparse_queue_family_test>")
    set_tests_properties(d3d12_sparse_queue_family_contract PROPERTIES SKIP_RETURN_CODE 77 TIMEOUT 65)
  endif()
  set_tests_properties(d3d12_vulkan_device PROPERTIES SKIP_RETURN_CODE 77)

  add_executable(d3d12_texture1d_test test/d3d12_texture1d_test.cpp)
  target_link_libraries(d3d12_texture1d_test PRIVATE gta6rt_d3d12_com dxguid)
  target_compile_definitions(d3d12_texture1d_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_texture1d_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_texture1d COMMAND d3d12_texture1d_test)
  set_tests_properties(d3d12_texture1d PROPERTIES SKIP_RETURN_CODE 77)

  # Placed 1D and 3D textures against the host runtime and WARP, and a copy round trip through them.
  add_executable(d3d12_placed_dimensions_test test/d3d12_placed_dimensions_test.cpp)
  target_link_libraries(d3d12_placed_dimensions_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_placed_dimensions_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_placed_dimensions_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_placed_dimensions COMMAND d3d12_placed_dimensions_test)
  set_tests_properties(d3d12_placed_dimensions PROPERTIES SKIP_RETURN_CODE 77
                       FAIL_REGULAR_EXPRESSION "Validation Error;VUID-")

  # FORMAT_SUPPORT of the depth- and stencil-plane view formats and comparison sampling, against the host runtime.
  add_executable(d3d12_depth_view_format_support_test test/d3d12_depth_view_format_support_test.cpp)
  target_link_libraries(d3d12_depth_view_format_support_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_depth_view_format_support_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_depth_view_format_support_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_depth_view_format_support COMMAND d3d12_depth_view_format_support_test)
  set_tests_properties(d3d12_depth_view_format_support PROPERTIES SKIP_RETURN_CODE 77)

  # A placed buffer keeps its heap's arena range after the application releases the heap.
  add_executable(d3d12_placed_heap_lifetime_test test/d3d12_placed_heap_lifetime_test.cpp)
  target_link_libraries(d3d12_placed_heap_lifetime_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_placed_heap_lifetime_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_placed_heap_lifetime_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_placed_heap_lifetime COMMAND d3d12_placed_heap_lifetime_test)
  set_tests_properties(d3d12_placed_heap_lifetime PROPERTIES SKIP_RETURN_CODE 77
                       FAIL_REGULAR_EXPRESSION "Validation Error;VUID-")

  # ClearUnorderedAccessViewUint/Float on buffers and textures, read back through D3D12.
  add_executable(d3d12_uav_clear_test test/d3d12_uav_clear_test.cpp)
  target_link_libraries(d3d12_uav_clear_test PRIVATE gta6rt_d3d12_com)
  target_compile_definitions(d3d12_uav_clear_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_uav_clear_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_uav_clear COMMAND d3d12_uav_clear_test)
  set_tests_properties(d3d12_uav_clear PROPERTIES SKIP_RETURN_CODE 77)

  add_executable(d3d12_short_uav_clear_test test/d3d12_short_uav_clear_test.cpp)
  target_link_libraries(d3d12_short_uav_clear_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_short_uav_clear_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_short_uav_clear_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_short_uav_clear COMMAND d3d12_short_uav_clear_test)
  set_tests_properties(d3d12_short_uav_clear PROPERTIES SKIP_RETURN_CODE 77
    ENVIRONMENT "LEONIDA_HOST_ADAPTER=warp")

  # Emulation of R9G9B9E5_SHAREDEXP UAV textures as mutable R32_UINT on GPUs without E5B9G9R9 storage:
  # format support, 1D/2D/3D/reserved creation, SRV/UAV T#s, WARP differential UAV clears, cross-backing copies,
  # and set-0 storage write -> E5B9G9R9 sampled HDR round-trip.
  add_executable(d3d12_d24_support_test test/d3d12_d24_support_test.cpp)
  target_link_libraries(d3d12_d24_support_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_d24_support_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_d24_support_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_d24_support COMMAND d3d12_d24_support_test)
  set_tests_properties(d3d12_d24_support PROPERTIES SKIP_RETURN_CODE 77)
  add_executable(d3d12_b5g5r5a1_uav_test test/d3d12_b5g5r5a1_uav_test.cpp)
  target_link_libraries(d3d12_b5g5r5a1_uav_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_b5g5r5a1_uav_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_b5g5r5a1_uav_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_b5g5r5a1_uav COMMAND d3d12_b5g5r5a1_uav_test)
  set_tests_properties(d3d12_b5g5r5a1_uav PROPERTIES SKIP_RETURN_CODE 77)
  add_executable(d3d12_srgb_uav_test test/d3d12_srgb_uav_test.cpp)
  target_link_libraries(d3d12_srgb_uav_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_srgb_uav_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_srgb_uav_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_srgb_uav COMMAND d3d12_srgb_uav_test)
  set_tests_properties(d3d12_srgb_uav PROPERTIES SKIP_RETURN_CODE 77)  # native sRGB storage, no Vulkan GPU, or Wine
  add_executable(d3d12_r9g9b9e5_uav_test test/d3d12_r9g9b9e5_uav_test.cpp)
  target_link_libraries(d3d12_r9g9b9e5_uav_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_r9g9b9e5_uav_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_r9g9b9e5_uav_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_r9g9b9e5_uav COMMAND d3d12_r9g9b9e5_uav_test)
  set_tests_properties(d3d12_r9g9b9e5_uav PROPERTIES SKIP_RETURN_CODE 77)
  if(Vulkan_GLSLANG_VALIDATOR_EXECUTABLE)
    set(LEONIDA_TEST_CS_R9G9B9E5_UAV ${CMAKE_CURRENT_BINARY_DIR}/generated/cs_r9g9b9e5_uav.spv)
    add_custom_command(
      OUTPUT ${LEONIDA_TEST_CS_R9G9B9E5_UAV}
      COMMAND ${Vulkan_GLSLANG_VALIDATOR_EXECUTABLE} -V --target-env vulkan1.3 -o ${LEONIDA_TEST_CS_R9G9B9E5_UAV}
              ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/cs_r9g9b9e5_uav.comp
      DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/cs_r9g9b9e5_uav.comp
      COMMENT "Compiling cs_r9g9b9e5_uav.comp"
      VERBATIM)
    target_sources(d3d12_r9g9b9e5_uav_test PRIVATE ${LEONIDA_TEST_CS_R9G9B9E5_UAV})
    target_compile_definitions(d3d12_r9g9b9e5_uav_test PRIVATE
      LEONIDA_TEST_CS_R9G9B9E5_UAV_SPV="${LEONIDA_TEST_CS_R9G9B9E5_UAV}")
  endif()

  # Debug markers as VK_EXT_debug_utils labels, and private data on every object (D3D-24).
  add_executable(d3d12_debug_markers_test test/d3d12_debug_markers_test.cpp)
  target_link_libraries(d3d12_debug_markers_test PRIVATE gta6rt_d3d12_com)
  target_compile_definitions(d3d12_debug_markers_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_debug_markers_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_debug_markers COMMAND d3d12_debug_markers_test)
  set_tests_properties(d3d12_debug_markers PROPERTIES SKIP_RETURN_CODE 77)

  # Existing-memory heaps and lifetime trackers: the arguments the host refuses (OpenExistingHeapFromAddress,
  # OpenExistingHeapFromFileMapping, CreateLifetimeTracker).
  add_executable(d3d12_existing_heap_test test/d3d12_existing_heap_test.cpp)
  target_link_libraries(d3d12_existing_heap_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_existing_heap_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_existing_heap_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_existing_heap COMMAND d3d12_existing_heap_test)
  set_tests_properties(d3d12_existing_heap PROPERTIES SKIP_RETURN_CODE 77)
  # Slot 133 on untouched xmem physical pages: committed through the pages hook, then imported. xmem.cpp and
  # registry.cpp are compiled in, as xmem_test does, to reach the registered XMem* exports.
  add_executable(d3d12_xmem_placed_test test/d3d12_xmem_placed_test.cpp shims/xmem.cpp shims/registry.cpp)
  target_link_libraries(d3d12_xmem_placed_test PRIVATE gta6rt_d3d12_com d3d12 dxgi psapi)
  target_compile_definitions(d3d12_xmem_placed_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_xmem_placed_test PRIVATE /W4 /permissive- /utf-8)
  target_link_options(d3d12_xmem_placed_test PRIVATE /OPT:NOREF)
  add_test(NAME d3d12_xmem_placed COMMAND d3d12_xmem_placed_test)
  set_tests_properties(d3d12_xmem_placed PROPERTIES SKIP_RETURN_CODE 77)

  # Fences and timing (D3D-30): multiple-fence waits, clock calibration, adapter LUID, custom heap properties.
  add_executable(d3d12_fence_timing_test test/d3d12_fence_timing_test.cpp)
  target_link_libraries(d3d12_fence_timing_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_fence_timing_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_fence_timing_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_fence_timing COMMAND d3d12_fence_timing_test)
  set_tests_properties(d3d12_fence_timing PROPERTIES SKIP_RETURN_CODE 77)
  # Fence events the host runtime sets or refuses (released fences, no fences), compared with the host devices.
  add_executable(d3d12_fence_events_test test/d3d12_fence_events_test.cpp)
  target_link_libraries(d3d12_fence_events_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_fence_events_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_fence_events_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_fence_events COMMAND d3d12_fence_events_test)
  set_tests_properties(d3d12_fence_events PROPERTIES SKIP_RETURN_CODE 77)
  add_executable(d3d12_fence_device_lost_counter_test test/d3d12_fence_device_lost_counter_test.cpp)
  target_link_libraries(d3d12_fence_device_lost_counter_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_fence_device_lost_counter_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_fence_device_lost_counter_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_fence_device_lost_counter COMMAND d3d12_fence_device_lost_counter_test)
  set_tests_properties(d3d12_fence_device_lost_counter PROPERTIES SKIP_RETURN_CODE 77 TIMEOUT 60)
  # Xbox-ABI queue and fence proxies behind the device proxy, on the host runtime (WARP, a hardware adapter) and
  # on the Vulkan device: forwarding, refusal past the public chain, fence unwrapping. 77: no device at all.
  add_executable(queue_proxy_test test/queue_proxy_test.cpp)
  target_link_libraries(queue_proxy_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(queue_proxy_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(queue_proxy_test PRIVATE /W4 /permissive- /utf-8 /EHsc)
  add_test(NAME queue_proxy COMMAND queue_proxy_test)
  set_tests_properties(queue_proxy PROPERTIES SKIP_RETURN_CODE 77)
  # Xbox-ABI command allocator proxies (device slot 9) on the Vulkan device, and the unwrapped PC allocator on the
  # host runtime: forwarding, refused tail, guard region, lists and GPU copies on the proxy. 77: no device at all.
  add_executable(allocator_proxy_test test/allocator_proxy_test.cpp)
  target_link_libraries(allocator_proxy_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(allocator_proxy_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(allocator_proxy_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME allocator_proxy COMMAND allocator_proxy_test)
  set_tests_properties(allocator_proxy PROPERTIES SKIP_RETURN_CODE 77)
  # IDXGIDevice1 on the device proxy (the GDKX boot step: QueryInterface, GetAdapter, EnumOutputs), on the host
  # runtime and on the Vulkan device: COM identity with the device, the adapter's LUID. 77: no device at all.
  add_executable(dxgi_device_test test/dxgi_device_test.cpp)
  target_link_libraries(dxgi_device_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(dxgi_device_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(dxgi_device_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME dxgi_device COMMAND dxgi_device_test)
  set_tests_properties(dxgi_device PROPERTIES SKIP_RETURN_CODE 77)
  add_executable(dxgi_host_answers_test test/dxgi_host_answers_test.cpp)
  target_link_libraries(dxgi_host_answers_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(dxgi_host_answers_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(dxgi_host_answers_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME dxgi_host_answers COMMAND dxgi_host_answers_test)
  set_tests_properties(dxgi_host_answers PROPERTIES SKIP_RETURN_CODE 77)
  # The countdown behind those event-backed waits, with no GPU: the full unsigned count, no wrap past zero.
  add_executable(d3d12_fence_waiter_test test/d3d12_fence_waiter_test.cpp)
  target_compile_definitions(d3d12_fence_waiter_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_fence_waiter_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_fence_waiter COMMAND d3d12_fence_waiter_test)
  # The 1/2/3 method variants (D3D-28) against the methods they wrap, on the Vulkan device directly.
  add_executable(d3d12_method_variants_test test/d3d12_method_variants_test.cpp)
  target_link_libraries(d3d12_method_variants_test PRIVATE gta6rt_d3d12_com)
  target_compile_definitions(d3d12_method_variants_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_method_variants_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_method_variants COMMAND d3d12_method_variants_test)
  # ID3D12Device9::CreateShaderCacheSession, ID3D12ShaderCacheSession and ShaderCacheControl (D3D-34).
  add_executable(d3d12_shader_cache_test test/d3d12_shader_cache_test.cpp)
  target_link_libraries(d3d12_shader_cache_test PRIVATE gta6rt_d3d12_com)
  target_compile_definitions(d3d12_shader_cache_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_shader_cache_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_shader_cache COMMAND d3d12_shader_cache_test)
  set_tests_properties(d3d12_shader_cache PROPERTIES SKIP_RETURN_CODE 77)
  set_tests_properties(d3d12_method_variants PROPERTIES SKIP_RETURN_CODE 77)
  # ID3D12Object private data (GetPrivateData, SetPrivateData, SetPrivateDataInterface, SetName) compared with
  # the host runtime's answers on the device and four child objects.
  add_executable(d3d12_private_data_test test/d3d12_private_data_test.cpp)
  target_link_libraries(d3d12_private_data_test PRIVATE gta6rt_d3d12_com)
  target_compile_definitions(d3d12_private_data_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_private_data_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_private_data COMMAND d3d12_private_data_test)
  set_tests_properties(d3d12_private_data PROPERTIES SKIP_RETURN_CODE 77)

  # CreateSampler2 (D3D-28) against CreateSampler, and its refusals against the host's PC runtime.
  add_executable(d3d12_sampler2_test test/d3d12_sampler2_test.cpp)
  target_link_libraries(d3d12_sampler2_test PRIVATE gta6rt_d3d12_com)
  target_compile_definitions(d3d12_sampler2_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_sampler2_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_sampler2 COMMAND d3d12_sampler2_test)
  set_tests_properties(d3d12_sampler2 PROPERTIES SKIP_RETURN_CODE 77)

  # Descriptors through the proxy: copies between heaps, what texture views and samplers write into their slots,
  # and (where glslangValidator is found) a compute shader the test runs on the device's bindless set, which
  # finds a T# and an S# through the hash table and samples. The shader is GLSL, compiled here.
  add_executable(d3d12_descriptor_test test/d3d12_descriptor_test.cpp)
  target_link_libraries(d3d12_descriptor_test PRIVATE gta6rt_d3d12_com)
  target_compile_definitions(d3d12_descriptor_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_descriptor_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_descriptor COMMAND d3d12_descriptor_test)
  set_tests_properties(d3d12_descriptor PROPERTIES SKIP_RETURN_CODE 77)
  if(Vulkan_GLSLANG_VALIDATOR_EXECUTABLE)
    function(descriptor_test_shader shader definition)
      set(source ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/${shader})
      set(binary ${CMAKE_CURRENT_BINARY_DIR}/generated/${definition}.spv)
      add_custom_command(OUTPUT ${binary}
        COMMAND ${Vulkan_GLSLANG_VALIDATOR_EXECUTABLE} -V --target-env vulkan1.3 ${ARGN} -o ${binary} ${source}
        DEPENDS ${source} COMMENT "Compiling descriptor test shader ${shader}" VERBATIM)
      target_sources(d3d12_descriptor_test PRIVATE ${binary})
      target_compile_definitions(d3d12_descriptor_test PRIVATE ${definition}="${binary}")
    endfunction()
    descriptor_test_shader(cs_sample.comp LEONIDA_TEST_CS_SAMPLE_SPV)
    descriptor_test_shader(cs_sample.comp LEONIDA_TEST_GATHER_ALPHA_SPV -DTEST_GATHER_ALPHA=1)
    descriptor_test_shader(cs_sample.comp LEONIDA_TEST_MS_FLOAT_SPV -DTEST_MS_FLOAT=1)
    descriptor_test_shader(cs_sample.comp LEONIDA_TEST_MS_UINT_SPV -DTEST_MS_UINT=1)
    descriptor_test_shader(cs_sample.comp LEONIDA_TEST_MS_SINT_SPV -DTEST_MS_SINT=1)
    descriptor_test_shader(msaa_seed.vert LEONIDA_TEST_MSAA_VERT_SPV)
    descriptor_test_shader(msaa_seed.frag LEONIDA_TEST_MSAA_FRAG_SPV)
  else()
    message(STATUS "glslangValidator not found: d3d12_descriptor_test skips its shader")
  endif()

  add_executable(d3d12_predicated_copy_test test/d3d12_predicated_copy_test.cpp)
  target_link_libraries(d3d12_predicated_copy_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_predicated_copy_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_predicated_copy_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_predicated_copy COMMAND d3d12_predicated_copy_test)
  set_tests_properties(d3d12_predicated_copy PROPERTIES SKIP_RETURN_CODE 77)
  # A DISPATCH-only ExecuteIndirect signature with a GPU count buffer: native Windows WARP versus Vulkan GPU,
  # including a GPU-written count that changes between two calls in the same command list.
  if(Vulkan_GLSLANG_VALIDATOR_EXECUTABLE)
    set(_indirect_count_spv ${CMAKE_CURRENT_BINARY_DIR}/generated/cs_indirect_dispatch_count.spv)
    add_custom_command(OUTPUT ${_indirect_count_spv}
      COMMAND ${Vulkan_GLSLANG_VALIDATOR_EXECUTABLE} -V --target-env vulkan1.2
        -o ${_indirect_count_spv} ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/cs_indirect_dispatch_count.comp
      DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/cs_indirect_dispatch_count.comp
      COMMENT "Compiling the counted indirect dispatch test shader" VERBATIM)
    add_executable(d3d12_indirect_dispatch_count_test test/d3d12_indirect_dispatch_count_test.cpp
      ${_indirect_count_spv})
    target_link_libraries(d3d12_indirect_dispatch_count_test PRIVATE gta6rt_d3d12_com d3d12 dxgi version)
    target_compile_definitions(d3d12_indirect_dispatch_count_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX
      LEONIDA_TEST_INDIRECT_COUNT_SPV="${_indirect_count_spv}")
    target_compile_options(d3d12_indirect_dispatch_count_test PRIVATE /W4 /permissive- /utf-8)
    add_test(NAME d3d12_indirect_dispatch_count COMMAND d3d12_indirect_dispatch_count_test)
    set_tests_properties(d3d12_indirect_dispatch_count PROPERTIES SKIP_RETURN_CODE 77)
  endif()

  # What Close returns after one recorded call, against WARP; today's differences are listed in the test.
  add_executable(d3d12_close_parity_test test/d3d12_close_parity_test.cpp)
  target_link_libraries(d3d12_close_parity_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_close_parity_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_close_parity_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_close_parity COMMAND d3d12_close_parity_test)
  set_tests_properties(d3d12_close_parity PROPERTIES SKIP_RETURN_CODE 77)

  # ExecuteIndirect recording-time Close() parity against live WARP and hardware D3D12, plus GPU dispatch sanity.
  add_executable(d3d12_execute_indirect_validation_test test/d3d12_execute_indirect_validation_test.cpp)
  target_link_libraries(d3d12_execute_indirect_validation_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_execute_indirect_validation_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_execute_indirect_validation_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_execute_indirect_validation COMMAND d3d12_execute_indirect_validation_test)
  set_tests_properties(d3d12_execute_indirect_validation PROPERTIES
    SKIP_RETURN_CODE 77
    FAIL_REGULAR_EXPRESSION "Validation Error;VUID-")

  # Set{Compute,Graphics}Root* closed-list, zero-count null, CBV alignment, and foreign root signature parity.
  add_executable(d3d12_root_args_validation_test test/d3d12_root_args_validation_test.cpp)
  target_link_libraries(d3d12_root_args_validation_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_root_args_validation_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_root_args_validation_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_root_args_validation COMMAND d3d12_root_args_validation_test)
  set_tests_properties(d3d12_root_args_validation PROPERTIES
    SKIP_RETURN_CODE 77
    FAIL_REGULAR_EXPRESSION "Validation Error;VUID-")

  # ClearState predication reset (GPU readback) + SetPredication / AtomicCopyBuffer Close() parity against WARP & HW.
  add_executable(d3d12_predication_atomic_copy_test test/d3d12_predication_atomic_copy_test.cpp)
  target_link_libraries(d3d12_predication_atomic_copy_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_predication_atomic_copy_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_predication_atomic_copy_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_predication_atomic_copy COMMAND d3d12_predication_atomic_copy_test)
  set_tests_properties(d3d12_predication_atomic_copy PROPERTIES
    SKIP_RETURN_CODE 77
    FAIL_REGULAR_EXPRESSION "Validation Error;VUID-"
  )

  # Differential regression: run explicitly (requires Vulkan hardware and Windows WARP).
  add_executable(d3d12_clear_test test/d3d12_clear_test.cpp)
  target_link_libraries(d3d12_clear_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_clear_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_clear_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_rgb9e5_rtv COMMAND d3d12_clear_test --rgb9e5)
  set_tests_properties(d3d12_rgb9e5_rtv PROPERTIES SKIP_RETURN_CODE 77)
  add_test(NAME d3d12_clear COMMAND d3d12_clear_test)
  set_tests_properties(d3d12_clear PROPERTIES SKIP_RETURN_CODE 77)

  # Synthetic typed-view readbacks against Windows WARP; run explicitly on a Vulkan GPU.
  add_executable(d3d12_typeless_rtv_test test/d3d12_typeless_rtv_test.cpp)
  target_link_libraries(d3d12_typeless_rtv_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_typeless_rtv_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_typeless_rtv_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_typeless_rtv COMMAND d3d12_typeless_rtv_test)
  # 1D render targets and depth buffers: creation against the host and WARP, clears read back against WARP.
  add_executable(d3d12_texture1d_target_test test/d3d12_texture1d_target_test.cpp)
  target_link_libraries(d3d12_texture1d_target_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_texture1d_target_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_texture1d_target_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_texture1d_target COMMAND d3d12_texture1d_target_test)
  set_tests_properties(d3d12_texture1d_target PROPERTIES SKIP_RETURN_CODE 77)  # no Vulkan GPU, or Wine

  # ArraySize -1 in array RTVs and DSVs (every slice from the first on), against the host on the same adapter
  # and WARP.
  add_executable(d3d12_view_slices_test test/d3d12_view_slices_test.cpp)
  target_link_libraries(d3d12_view_slices_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_view_slices_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_view_slices_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_view_slices COMMAND d3d12_view_slices_test)
  set_tests_properties(d3d12_view_slices PROPERTIES SKIP_RETURN_CODE 77)

  # Typed RTV clears and draws of every TYPELESS color family against the host on the same adapter and WARP
  # (D3D-275). The draws need glslangValidator for their GLSL stand-ins of translated shaders.
  add_executable(d3d12_typeless_families_test test/d3d12_typeless_families_test.cpp)
  target_link_libraries(d3d12_typeless_families_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_typeless_families_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_typeless_families_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_typeless_families COMMAND d3d12_typeless_families_test)
  set_tests_properties(d3d12_typeless_families PROPERTIES SKIP_RETURN_CODE 77)
  if(Vulkan_GLSLANG_VALIDATOR_EXECUTABLE)
    foreach(pair "vs_fullscreen.vert;LEONIDA_TYPELESS_VS_SPV;typeless_vs.spv"
                 "ps_typeless_float.frag;LEONIDA_TYPELESS_PS_FLOAT_SPV;typeless_ps_float.spv"
                 "ps_typeless_uint.frag;LEONIDA_TYPELESS_PS_UINT_SPV;typeless_ps_uint.spv")
      list(GET pair 0 shader)
      list(GET pair 1 definition)
      list(GET pair 2 name)
      set(binary ${CMAKE_CURRENT_BINARY_DIR}/generated/${name})
      add_custom_command(OUTPUT ${binary}
        COMMAND ${Vulkan_GLSLANG_VALIDATOR_EXECUTABLE} -V --target-env vulkan1.3 -o ${binary}
                ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/${shader}
        DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/${shader}
        COMMENT "Compiling the typeless draw test shader ${shader}" VERBATIM)
      target_sources(d3d12_typeless_families_test PRIVATE ${binary})
      target_compile_definitions(d3d12_typeless_families_test PRIVATE ${definition}="${binary}")
    endforeach()
  else()
    message(STATUS "glslangValidator not found: d3d12_typeless_families_test runs its clears only")
  endif()

  # Fixed-function state (blend, depth, stencil) swept against the host D3D12 device on the same adapter. Needs
  # glslangValidator for the GLSL stand-ins of translated shaders.
  if(Vulkan_GLSLANG_VALIDATOR_EXECUTABLE)
    add_executable(d3d12_state_sweep_test test/d3d12_state_sweep_test.cpp)
    target_link_libraries(d3d12_state_sweep_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
    target_compile_definitions(d3d12_state_sweep_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
    target_compile_options(d3d12_state_sweep_test PRIVATE /W4 /permissive- /utf-8)
    foreach(pair "vs_fullscreen.vert;LEONIDA_SWEEP_VS_SPV;sweep_vs.spv"
                 "ps_sweep.frag;LEONIDA_SWEEP_PS_SPV;sweep_ps.spv")
      list(GET pair 0 shader)
      list(GET pair 1 definition)
      list(GET pair 2 name)
      set(binary ${CMAKE_CURRENT_BINARY_DIR}/generated/${name})
      add_custom_command(OUTPUT ${binary}
        COMMAND ${Vulkan_GLSLANG_VALIDATOR_EXECUTABLE} -V --target-env vulkan1.3 -o ${binary}
                ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/${shader}
        DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/${shader}
        COMMENT "Compiling the state sweep test shader ${shader}" VERBATIM)
      target_sources(d3d12_state_sweep_test PRIVATE ${binary})
      target_compile_definitions(d3d12_state_sweep_test PRIVATE ${definition}="${binary}")
    endforeach()
    add_test(NAME d3d12_state_sweep COMMAND d3d12_state_sweep_test)
    set_tests_properties(d3d12_state_sweep PROPERTIES SKIP_RETURN_CODE 77)
  endif()

  # 96-bit R32G32B32 textures (D3D-62): footprints and every copy path against Windows WARP.
  add_executable(d3d12_rgb96_test test/d3d12_rgb96_test.cpp)
  target_link_libraries(d3d12_rgb96_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_rgb96_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_rgb96_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_rgb96 COMMAND d3d12_rgb96_test)
  set_tests_properties(d3d12_rgb96 PROPERTIES SKIP_RETURN_CODE 77)  # no Vulkan GPU or no WARP adapter
  set_tests_properties(d3d12_typeless_rtv PROPERTIES SKIP_RETURN_CODE 77)

  # Depth/stencil ResolveSubresourceRegion against the host runtime and WARP; run explicitly on a Vulkan GPU.
  add_executable(d3d12_depth_resolve_test test/d3d12_depth_resolve_test.cpp)
  target_link_libraries(d3d12_depth_resolve_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_depth_resolve_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_depth_resolve_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_depth_resolve COMMAND d3d12_depth_resolve_test)
  set_tests_properties(d3d12_depth_resolve PROPERTIES SKIP_RETURN_CODE 77)
  # The edge cases (TEST-848) draw with a GLSL stand-in for a translated vertex shader; without glslangValidator
  # only the clear cases run.
  if(Vulkan_GLSLANG_VALIDATOR_EXECUTABLE)
    set(binary ${CMAKE_CURRENT_BINARY_DIR}/generated/depth_edge_vs.spv)
    add_custom_command(OUTPUT ${binary}
      COMMAND ${Vulkan_GLSLANG_VALIDATOR_EXECUTABLE} -V --target-env vulkan1.3 -o ${binary}
              ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/vs_depth_edge.vert
      DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/vs_depth_edge.vert
      COMMENT "Compiling the depth resolve test shader vs_depth_edge.vert" VERBATIM)
    target_sources(d3d12_depth_resolve_test PRIVATE ${binary})
    target_compile_definitions(d3d12_depth_resolve_test PRIVATE LEONIDA_DEPTH_EDGE_VS_SPV="${binary}")
  endif()

  # ID3D12Resource::GetDesc against the host runtime and WARP; run explicitly on a Vulkan GPU.
  add_executable(d3d12_resource_desc_test test/d3d12_resource_desc_test.cpp)
  target_link_libraries(d3d12_resource_desc_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_resource_desc_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_resource_desc_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_resource_desc COMMAND d3d12_resource_desc_test)
  set_tests_properties(d3d12_resource_desc PROPERTIES SKIP_RETURN_CODE 77)

  # Typeless depth-stencil textures without ALLOW_DEPTH_STENCIL, copied from a depth buffer, against WARP.
  add_executable(d3d12_typeless_depth_test test/d3d12_typeless_depth_test.cpp)
  target_link_libraries(d3d12_typeless_depth_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_typeless_depth_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_typeless_depth_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_typeless_depth COMMAND d3d12_typeless_depth_test)
  set_tests_properties(d3d12_typeless_depth PROPERTIES SKIP_RETURN_CODE 77)

  # WriteToSubresource/ReadFromSubresource arguments and bytes, compared with the host runtime.
  add_executable(d3d12_subresource_copy_test test/d3d12_subresource_copy_test.cpp)
  target_link_libraries(d3d12_subresource_copy_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_subresource_copy_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_subresource_copy_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_subresource_copy COMMAND d3d12_subresource_copy_test)
  set_tests_properties(d3d12_subresource_copy PROPERTIES SKIP_RETURN_CODE 77)

  # MakeResident, Evict, SetResidencyPriority and EnqueueMakeResident, compared with the host runtime.
  add_executable(d3d12_residency_test test/d3d12_residency_test.cpp)
  target_link_libraries(d3d12_residency_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_residency_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_residency_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_residency COMMAND d3d12_residency_test)
  set_tests_properties(d3d12_residency PROPERTIES SKIP_RETURN_CODE 77)

  # ID3D12Resource::GetHeapProperties for committed, placed and reserved resources, compared with the host runtime.
  add_executable(d3d12_heap_properties_test test/d3d12_heap_properties_test.cpp)
  target_link_libraries(d3d12_heap_properties_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_heap_properties_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_heap_properties_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_heap_properties COMMAND d3d12_heap_properties_test)
  set_tests_properties(d3d12_heap_properties PROPERTIES SKIP_RETURN_CODE 77)

  # CreatePipelineLibrary and ID3D12PipelineLibrary1 arguments, compared with the host runtime.
  add_executable(d3d12_pipeline_library_host_test test/d3d12_pipeline_library_host_test.cpp)
  target_link_libraries(d3d12_pipeline_library_host_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_pipeline_library_host_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_pipeline_library_host_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_pipeline_library_host COMMAND d3d12_pipeline_library_host_test)
  set_tests_properties(d3d12_pipeline_library_host PROPERTIES SKIP_RETURN_CODE 77)

  # Milestone M0: a window, 60 cleared frames presented through the proxy on Vulkan.
  add_executable(d3d12_present_test test/d3d12_present_test.cpp)
  target_link_libraries(d3d12_present_test PRIVATE gta6rt_d3d12_com user32 gdi32 dxgi)
  target_compile_definitions(d3d12_present_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_present_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_present COMMAND d3d12_present_test)
  set_tests_properties(d3d12_present PROPERTIES SKIP_RETURN_CODE 77)

  # Per-pipeline --f16-interp-fallback linking (SHADER-378): 16-param VS + colliding PS rendered on Vulkan.
  add_executable(d3d12_f16_halves_test test/d3d12_f16_halves_test.cpp shims/d3d12_xs_device.cpp)
  target_link_libraries(d3d12_f16_halves_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_f16_halves_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_f16_halves_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_f16_halves COMMAND d3d12_f16_halves_test)
  set_tests_properties(d3d12_f16_halves PROPERTIES SKIP_RETURN_CODE 77)

  # PresentX and the frame events on the Vulkan device (shims/xbox_present.h), checked on swapchain pixels.
  add_executable(xbox_present_test test/xbox_present_test.cpp)
  target_link_libraries(xbox_present_test PRIVATE gta6rt_d3d12_com user32)
  target_compile_definitions(xbox_present_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(xbox_present_test PRIVATE /W4 /permissive- /utf-8)
  # Needs a Vulkan GPU and a window; exits 77 (skipped) without a Vulkan device.
  add_test(NAME xbox_present COMMAND xbox_present_test)
  set_tests_properties(xbox_present PROPERTIES SKIP_RETURN_CODE 77)

  # TEST-528: a real boot-movie frame (the package's Bink2Scarlett.dll) uploaded through the Xbox-ABI proxy and
  # presented with PresentX, checked against the decoded BGRA. Package-gated like bink_decode_test: skips (77)
  # unless LEONIDA_GAME_DIR and LEONIDA_MOVIE are set; no game data is written into the repo.
  add_executable(d3d12_boot_movie_test
    test/d3d12_boot_movie_test.cpp
    src/pe_loader.cpp
    shims/registry.cpp
    shims/xmem.cpp
  )
  target_link_libraries(d3d12_boot_movie_test PRIVATE gta6rt_d3d12_com user32 psapi)
  target_compile_definitions(d3d12_boot_movie_test PRIVATE
    WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE _CRT_SECURE_NO_WARNINGS)
  target_compile_options(d3d12_boot_movie_test PRIVATE /W4 /permissive- /utf-8 /EHsc)
  target_link_options(d3d12_boot_movie_test PRIVATE /OPT:NOREF)
  add_dependencies(d3d12_boot_movie_test gta6rt_tls_host)
  add_test(NAME d3d12_boot_movie COMMAND d3d12_boot_movie_test)
  set_tests_properties(d3d12_boot_movie PROPERTIES SKIP_RETURN_CODE 77)

  # First light through D3D12 (docs/first_light.md): the real model and translated VS/PS that tools/first_light.py
  # wrote to LEONIDA_FIRST_LIGHT_DIR, drawn through the device proxy. Skips (77) unless that variable is set.
  add_executable(d3d12_first_light_test test/d3d12_first_light_test.cpp shims/d3d12_xs_device.cpp)
  target_link_libraries(d3d12_first_light_test PRIVATE gta6rt_d3d12_com)
  target_compile_definitions(d3d12_first_light_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX _CRT_SECURE_NO_WARNINGS)
  target_compile_options(d3d12_first_light_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_first_light COMMAND d3d12_first_light_test)
  set_tests_properties(d3d12_first_light PROPERTIES SKIP_RETURN_CODE 77)

  # M1.5 (D3D-53): a draw whose VS and PS are translator output. test/shaders/vs_m15.asm and ps_m15.asm are assembled
  # with llvm-mc and translated by tools/rdna2spirv.py through test/shaders/build.py, which also writes the FSSM
  # programs their index entries are keyed by. Needs llvm-mc with the AMDGPU target (LLVM_MC in the environment, as
  # for the other shader tests, or llvm-mc on PATH or in C:/msys64/ucrt64/bin) and the Vulkan SDK's spirv-as and
  # spirv-val; without them the test is not built.
  if(NOT LEONIDA_LLVM_MC)
    if(DEFINED ENV{LLVM_MC})
      set(LEONIDA_LLVM_MC "$ENV{LLVM_MC}")
    else()
      find_program(LEONIDA_LLVM_MC llvm-mc HINTS "C:/msys64/ucrt64/bin")
    endif()
  endif()
  find_program(LEONIDA_SPIRV_AS spirv-as HINTS "$ENV{VULKAN_SDK}/Bin" "$ENV{VULKAN_SDK}/bin")
  find_program(LEONIDA_SPIRV_VAL spirv-val HINTS "$ENV{VULKAN_SDK}/Bin" "$ENV{VULKAN_SDK}/bin")
  if(LEONIDA_LLVM_MC AND LEONIDA_SPIRV_AS AND LEONIDA_SPIRV_VAL)
    set(LEONIDA_M15_DIR ${CMAKE_CURRENT_BINARY_DIR}/generated/m15_shaders)
    get_filename_component(LEONIDA_SPIRV_TOOLS_DIR ${LEONIDA_SPIRV_AS} DIRECTORY)
    file(TO_NATIVE_PATH "${LEONIDA_SPIRV_TOOLS_DIR}" LEONIDA_SPIRV_TOOLS_NATIVE)
    set(LEONIDA_M15_FILES ${LEONIDA_M15_DIR}/spirv/index.json ${LEONIDA_M15_DIR}/fssm/vs_m15.fssm
                          ${LEONIDA_M15_DIR}/fssm/ps_m15.fssm)
    add_custom_command(
      OUTPUT ${LEONIDA_M15_FILES}
      COMMAND ${CMAKE_COMMAND} -E remove_directory ${LEONIDA_M15_DIR}
      COMMAND ${CMAKE_COMMAND} -E env "LLVM_MC=${LEONIDA_LLVM_MC}" "LEONIDA_SPIRV_TOOLS=${LEONIDA_SPIRV_TOOLS_NATIVE}"
              $<TARGET_FILE:Python3::Interpreter> -I ${CMAKE_CURRENT_SOURCE_DIR}/test/shaders/build.py
              ${LEONIDA_M15_DIR} vs_m15 ps_m15
      DEPENDS ${LEONIDA_TRANSLATOR_DEPS}
              ${CMAKE_CURRENT_SOURCE_DIR}/test/shaders/vs_m15.asm
              ${CMAKE_CURRENT_SOURCE_DIR}/test/shaders/ps_m15.asm
      COMMENT "Translating vs_m15 and ps_m15 for the translated draw test"
      VERBATIM)
    add_executable(d3d12_translated_draw_test test/d3d12_translated_draw_test.cpp shims/d3d12_xs_device.cpp
                   ${LEONIDA_M15_FILES})
    target_link_libraries(d3d12_translated_draw_test PRIVATE gta6rt_d3d12_com)
    target_compile_definitions(d3d12_translated_draw_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX
                               LEONIDA_TEST_M15_DIR="${LEONIDA_M15_DIR}")
    target_compile_options(d3d12_translated_draw_test PRIVATE /W4 /permissive- /utf-8)
    add_test(NAME d3d12_translated_draw COMMAND d3d12_translated_draw_test)
    set_tests_properties(d3d12_translated_draw PROPERTIES SKIP_RETURN_CODE 77)

    # vk_bindless_test (the bindless set and its table at the Vulkan level, no D3D12) takes the translated vs_ids,
    # ps_tex and ps_imgatomic; it was only run by scripts/run_gpu_tests.py and check.py until D3D-314 needed it.
    set(LEONIDA_BINDLESS_DIR ${CMAKE_CURRENT_BINARY_DIR}/generated/bindless_shaders)
    set(LEONIDA_BINDLESS_FILES ${LEONIDA_BINDLESS_DIR}/spirv/vs_ids.spv ${LEONIDA_BINDLESS_DIR}/spirv/ps_tex.spv
                               ${LEONIDA_BINDLESS_DIR}/spirv/ps_imgatomic.spv)
    add_custom_command(
      OUTPUT ${LEONIDA_BINDLESS_FILES}
      COMMAND ${CMAKE_COMMAND} -E remove_directory ${LEONIDA_BINDLESS_DIR}
      COMMAND ${CMAKE_COMMAND} -E env "LLVM_MC=${LEONIDA_LLVM_MC}" "LEONIDA_SPIRV_TOOLS=${LEONIDA_SPIRV_TOOLS_NATIVE}"
              $<TARGET_FILE:Python3::Interpreter> -I ${CMAKE_CURRENT_SOURCE_DIR}/test/shaders/build.py
              ${LEONIDA_BINDLESS_DIR} vs_ids ps_tex ps_imgatomic
      DEPENDS ${LEONIDA_TRANSLATOR_DEPS}
              ${CMAKE_CURRENT_SOURCE_DIR}/test/shaders/vs_ids.asm
              ${CMAKE_CURRENT_SOURCE_DIR}/test/shaders/ps_tex.asm
              ${CMAKE_CURRENT_SOURCE_DIR}/test/shaders/ps_imgatomic.asm
      COMMENT "Translating vs_ids, ps_tex and ps_imgatomic for vk_bindless_test"
      VERBATIM)
    add_custom_target(vk_bindless_shaders ALL DEPENDS ${LEONIDA_BINDLESS_FILES})
    add_dependencies(vk_bindless_test vk_bindless_shaders)
    add_test(NAME vk_bindless_ps_tex COMMAND vk_bindless_test ${LEONIDA_BINDLESS_DIR}/spirv/vs_ids.spv
             ${LEONIDA_BINDLESS_DIR}/spirv/ps_tex.spv)
    add_test(NAME vk_bindless_ps_imgatomic COMMAND vk_bindless_test ${LEONIDA_BINDLESS_DIR}/spirv/vs_ids.spv
             ${LEONIDA_BINDLESS_DIR}/spirv/ps_imgatomic.spv)
    set_tests_properties(vk_bindless_ps_tex vk_bindless_ps_imgatomic PROPERTIES SKIP_RETURN_CODE 77)

    # M2: a textured quad. vs_m2.asm and ps_m2.asm (the PS samples a T#/S# it loads from two descriptor tables) go
    # through the same build; the test creates the heaps, the SRV, the sampler and the root signature through the
    # D3D12 API only.
    set(LEONIDA_M2_DIR ${CMAKE_CURRENT_BINARY_DIR}/generated/m2_shaders)
    set(LEONIDA_M2_FILES ${LEONIDA_M2_DIR}/spirv/index.json ${LEONIDA_M2_DIR}/fssm/vs_m2.fssm
                         ${LEONIDA_M2_DIR}/fssm/ps_m2.fssm ${LEONIDA_M2_DIR}/fssm/ps_m2_uoff.fssm
                         ${LEONIDA_M2_DIR}/fssm/ps_m2_literal.fssm)
    add_custom_command(
      OUTPUT ${LEONIDA_M2_FILES}
      COMMAND ${CMAKE_COMMAND} -E remove_directory ${LEONIDA_M2_DIR}
      COMMAND ${CMAKE_COMMAND} -E env "LLVM_MC=${LEONIDA_LLVM_MC}" "LEONIDA_SPIRV_TOOLS=${LEONIDA_SPIRV_TOOLS_NATIVE}"
              $<TARGET_FILE:Python3::Interpreter> -I ${CMAKE_CURRENT_SOURCE_DIR}/test/shaders/build.py
              ${LEONIDA_M2_DIR} vs_m2 ps_m2 ps_m2_uoff ps_m2_literal
      DEPENDS ${LEONIDA_TRANSLATOR_DEPS}
              ${CMAKE_CURRENT_SOURCE_DIR}/test/shaders/vs_m2.asm
              ${CMAKE_CURRENT_SOURCE_DIR}/test/shaders/ps_m2.asm
              ${CMAKE_CURRENT_SOURCE_DIR}/test/shaders/ps_m2_uoff.asm
              ${CMAKE_CURRENT_SOURCE_DIR}/test/shaders/ps_m2_literal.asm
      COMMENT "Translating vs_m2 and ps_m2 for the textured draw test"
      VERBATIM)
    add_executable(d3d12_m2_textured_test test/d3d12_m2_textured_test.cpp shims/d3d12_xs_device.cpp
                   ${LEONIDA_M2_FILES})
    target_link_libraries(d3d12_m2_textured_test PRIVATE gta6rt_d3d12_com)
    target_compile_definitions(d3d12_m2_textured_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX
                               LEONIDA_TEST_M2_DIR="${LEONIDA_M2_DIR}")
    target_compile_options(d3d12_m2_textured_test PRIVATE /W4 /permissive- /utf-8)
    add_test(NAME d3d12_m2_textured COMMAND d3d12_m2_textured_test)
    set_tests_properties(d3d12_m2_textured PROPERTIES SKIP_RETURN_CODE 77)

    # M2, formats: BC1 and BC7 textures with mip chains and an R8G8B8A8 2D array through the same descriptor path.
    # vs_m2.asm with ps_m2.asm (2D) and ps_m2_array.asm (2D array, slice 1.0 of the view).
    set(LEONIDA_M2F_DIR ${CMAKE_CURRENT_BINARY_DIR}/generated/m2f_shaders)
    set(LEONIDA_M2F_FILES ${LEONIDA_M2F_DIR}/spirv/index.json ${LEONIDA_M2F_DIR}/fssm/vs_m2.fssm
                          ${LEONIDA_M2F_DIR}/fssm/ps_m2.fssm ${LEONIDA_M2F_DIR}/fssm/ps_m2_array.fssm)
    add_custom_command(
      OUTPUT ${LEONIDA_M2F_FILES}
      COMMAND ${CMAKE_COMMAND} -E remove_directory ${LEONIDA_M2F_DIR}
      COMMAND ${CMAKE_COMMAND} -E env "LLVM_MC=${LEONIDA_LLVM_MC}" "LEONIDA_SPIRV_TOOLS=${LEONIDA_SPIRV_TOOLS_NATIVE}"
              $<TARGET_FILE:Python3::Interpreter> -I ${CMAKE_CURRENT_SOURCE_DIR}/test/shaders/build.py
              ${LEONIDA_M2F_DIR} vs_m2 ps_m2 ps_m2_array
      DEPENDS ${LEONIDA_TRANSLATOR_DEPS}
              ${CMAKE_CURRENT_SOURCE_DIR}/test/shaders/vs_m2.asm
              ${CMAKE_CURRENT_SOURCE_DIR}/test/shaders/ps_m2.asm
              ${CMAKE_CURRENT_SOURCE_DIR}/test/shaders/ps_m2_array.asm
      COMMENT "Translating vs_m2, ps_m2 and ps_m2_array for the M2 formats test"
      VERBATIM)
    add_executable(d3d12_m2_formats_test test/d3d12_m2_formats_test.cpp shims/d3d12_xs_device.cpp
                   ${LEONIDA_M2F_FILES})
    target_link_libraries(d3d12_m2_formats_test PRIVATE gta6rt_d3d12_com)
    target_compile_definitions(d3d12_m2_formats_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX
                               LEONIDA_TEST_M2F_DIR="${LEONIDA_M2F_DIR}")
    target_compile_options(d3d12_m2_formats_test PRIVATE /W4 /permissive- /utf-8)
    add_test(NAME d3d12_m2_formats COMMAND d3d12_m2_formats_test)
    set_tests_properties(d3d12_m2_formats PROPERTIES SKIP_RETURN_CODE 77)

    # M3 (synthetic part): frames with two render targets and a depth/stencil buffer, an occlusion query, resource
    # barriers and a second pass that samples the first one's target, three frames in flight with a fence each.
    # Pass 1's two-output PS and its single-output occlusion probe go through the same translator build.
    set(LEONIDA_M3_DIR ${CMAKE_CURRENT_BINARY_DIR}/generated/m3_shaders)
    set(LEONIDA_M3_FILES ${LEONIDA_M3_DIR}/spirv/index.json ${LEONIDA_M3_DIR}/fssm/vs_m3.fssm
                         ${LEONIDA_M3_DIR}/fssm/ps_m3.fssm ${LEONIDA_M3_DIR}/fssm/vs_m2.fssm
                         ${LEONIDA_M3_DIR}/fssm/ps_m3_post.fssm ${LEONIDA_M3_DIR}/fssm/ps_m3_query.fssm)
    add_custom_command(
      OUTPUT ${LEONIDA_M3_FILES}
      COMMAND ${CMAKE_COMMAND} -E remove_directory ${LEONIDA_M3_DIR}
      COMMAND ${CMAKE_COMMAND} -E env "LLVM_MC=${LEONIDA_LLVM_MC}" "LEONIDA_SPIRV_TOOLS=${LEONIDA_SPIRV_TOOLS_NATIVE}"
              $<TARGET_FILE:Python3::Interpreter> -I ${CMAKE_CURRENT_SOURCE_DIR}/test/shaders/build.py
              ${LEONIDA_M3_DIR} vs_m3 ps_m3 vs_m2 ps_m3_post ps_m3_query
      DEPENDS ${LEONIDA_TRANSLATOR_DEPS}
              ${CMAKE_CURRENT_SOURCE_DIR}/test/shaders/vs_m3.asm
              ${CMAKE_CURRENT_SOURCE_DIR}/test/shaders/ps_m3.asm
              ${CMAKE_CURRENT_SOURCE_DIR}/test/shaders/vs_m2.asm
              ${CMAKE_CURRENT_SOURCE_DIR}/test/shaders/ps_m3_post.asm
              ${CMAKE_CURRENT_SOURCE_DIR}/test/shaders/ps_m3_query.asm
      COMMENT "Translating M3 frame and single-output occlusion-probe shaders"
      VERBATIM)
    add_executable(d3d12_m3_frame_test test/d3d12_m3_frame_test.cpp shims/d3d12_xs_device.cpp ${LEONIDA_M3_FILES})
    target_link_libraries(d3d12_m3_frame_test PRIVATE gta6rt_d3d12_com)
    target_compile_definitions(d3d12_m3_frame_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX
                               LEONIDA_TEST_M3_DIR="${LEONIDA_M3_DIR}")
    target_compile_options(d3d12_m3_frame_test PRIVATE /W4 /permissive- /utf-8)
    add_test(NAME d3d12_m3_frame COMMAND d3d12_m3_frame_test)
    add_test(NAME d3d12_m3_first_pass COMMAND d3d12_m3_frame_test --first-pass-only)
    set_tests_properties(d3d12_m3_frame d3d12_m3_first_pass PROPERTIES SKIP_RETURN_CODE 77)

    # M4 (synthetic part): compute PSOs, a UAV table (structured and raw buffers, an R32_UINT storage image), an indirect
    # dispatch from arguments a first dispatch wrote, and a copy queue that streams the input in and reads the results
    # back across queue fences. cs_m4_fill.asm and cs_m4_indirect.asm go through the same build; build.py publishes
    # their synthetic FSSM programs (the compute header and the words their "fssm-data" comments give), which the
    # test wraps in shader containers.
    set(LEONIDA_M4_DIR ${CMAKE_CURRENT_BINARY_DIR}/generated/m4_shaders)
    set(LEONIDA_M4_FILES ${LEONIDA_M4_DIR}/spirv/index.json ${LEONIDA_M4_DIR}/fssm/cs_m4_fill.fssm
                         ${LEONIDA_M4_DIR}/fssm/cs_m4_indirect.fssm)
    add_custom_command(
      OUTPUT ${LEONIDA_M4_FILES}
      COMMAND ${CMAKE_COMMAND} -E remove_directory ${LEONIDA_M4_DIR}
      # LEONIDA_USER_DATA_SHIFT=4: the fixtures read their user data from s0; a D3D12 compute PSO gets its root
      # arguments from s4 (rt::rootsig::pack_stage, D3D-448), so they are built with every SGPR 4 higher.
      COMMAND ${CMAKE_COMMAND} -E env "LLVM_MC=${LEONIDA_LLVM_MC}" "LEONIDA_SPIRV_TOOLS=${LEONIDA_SPIRV_TOOLS_NATIVE}"
              LEONIDA_USER_DATA_SHIFT=4
              $<TARGET_FILE:Python3::Interpreter> -I ${CMAKE_CURRENT_SOURCE_DIR}/test/shaders/build.py
              ${LEONIDA_M4_DIR} cs_m4_fill cs_m4_indirect
      DEPENDS ${LEONIDA_TRANSLATOR_DEPS}
              ${CMAKE_CURRENT_SOURCE_DIR}/test/shaders/cs_m4_fill.asm
              ${CMAKE_CURRENT_SOURCE_DIR}/test/shaders/cs_m4_indirect.asm
      COMMENT "Translating cs_m4_fill and cs_m4_indirect for the compute test"
      VERBATIM)
    add_executable(d3d12_m4_compute_test test/d3d12_m4_compute_test.cpp shims/d3d12_xs_device.cpp ${LEONIDA_M4_FILES})
    target_link_libraries(d3d12_m4_compute_test PRIVATE gta6rt_d3d12_com)
    target_compile_definitions(d3d12_m4_compute_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX
                               LEONIDA_TEST_M4_DIR="${LEONIDA_M4_DIR}")
    target_compile_options(d3d12_m4_compute_test PRIVATE /W4 /permissive- /utf-8)
    add_test(NAME d3d12_m4_compute COMMAND d3d12_m4_compute_test)
    set_tests_properties(d3d12_m4_compute PROPERTIES SKIP_RETURN_CODE 77)

    # Typed buffer UAVs and UAV counters: cs_buf_typed.asm writes typed views through V#s with a FORMAT, and
    # cs_buf_counter.asm appends to and consumes from a structured view whose counter is the second V# of its slot;
    # the test also compares typed-buffer and counter clears with the host runtime on the layer's adapter.
    set(LEONIDA_BUFFER_UAV_DIR ${CMAKE_CURRENT_BINARY_DIR}/generated/buffer_uav_shaders)
    set(LEONIDA_BUFFER_UAV_FILES ${LEONIDA_BUFFER_UAV_DIR}/spirv/index.json
                                 ${LEONIDA_BUFFER_UAV_DIR}/fssm/cs_buf_typed.fssm
                                 ${LEONIDA_BUFFER_UAV_DIR}/fssm/cs_buf_counter.fssm)
    add_custom_command(
      OUTPUT ${LEONIDA_BUFFER_UAV_FILES}
      COMMAND ${CMAKE_COMMAND} -E remove_directory ${LEONIDA_BUFFER_UAV_DIR}
      # LEONIDA_USER_DATA_SHIFT=4: root arguments from s4 in a D3D12 compute PSO (see the M4 shaders above).
      COMMAND ${CMAKE_COMMAND} -E env "LLVM_MC=${LEONIDA_LLVM_MC}" "LEONIDA_SPIRV_TOOLS=${LEONIDA_SPIRV_TOOLS_NATIVE}"
              LEONIDA_USER_DATA_SHIFT=4
              $<TARGET_FILE:Python3::Interpreter> -I ${CMAKE_CURRENT_SOURCE_DIR}/test/shaders/build.py
              ${LEONIDA_BUFFER_UAV_DIR} cs_buf_typed cs_buf_counter
      DEPENDS ${LEONIDA_TRANSLATOR_DEPS}
              ${CMAKE_CURRENT_SOURCE_DIR}/test/shaders/cs_buf_typed.asm
              ${CMAKE_CURRENT_SOURCE_DIR}/test/shaders/cs_buf_counter.asm
      COMMENT "Translating cs_buf_typed and cs_buf_counter for the buffer UAV test"
      VERBATIM)
    add_executable(d3d12_buffer_uav_test test/d3d12_buffer_uav_test.cpp shims/d3d12_xs_device.cpp ${LEONIDA_BUFFER_UAV_FILES})
    target_link_libraries(d3d12_buffer_uav_test PRIVATE gta6rt_d3d12_com)
    target_compile_definitions(d3d12_buffer_uav_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX
                               LEONIDA_TEST_BUFFER_UAV_DIR="${LEONIDA_BUFFER_UAV_DIR}")
    target_compile_options(d3d12_buffer_uav_test PRIVATE /W4 /permissive- /utf-8)
    add_test(NAME d3d12_buffer_uav COMMAND d3d12_buffer_uav_test)
    set_tests_properties(d3d12_buffer_uav PROPERTIES SKIP_RETURN_CODE 77)
  else()
    message(STATUS "llvm-mc (set LLVM_MC) or the SDK's spirv-as/spirv-val not found: d3d12_translated_draw_test, d3d12_m2_textured_test, d3d12_m2_formats_test, d3d12_m3_frame_test, d3d12_m4_compute_test and d3d12_buffer_uav_test are not built")
  endif()
  # ID3D12Resource::GetHeapProperties and ID3D12DescriptorHeap::GetDesc (node masks, resolved heap flags) against the
  # host runtime and WARP; run explicitly on a Vulkan GPU.
  add_executable(d3d12_node_mask_test test/d3d12_node_mask_test.cpp)
  target_link_libraries(d3d12_node_mask_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_node_mask_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_node_mask_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_node_mask COMMAND d3d12_node_mask_test)

  # Console Xbox CreateDescriptorHeap extended ABI (issue #313 comment 7107265058): the title passes address/size
  # after the PC desc and expects GetCPU/GPUDescriptorHandleForHeapStart() == address. Synthetic test; no title-memory
  # aliasing / §3.3 backing coverage.
  add_executable(d3d12_console_descriptor_heap_test test/d3d12_console_descriptor_heap_test.cpp shims/d3d12_xs_device.cpp)
  target_link_libraries(d3d12_console_descriptor_heap_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_console_descriptor_heap_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_console_descriptor_heap_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_console_descriptor_heap COMMAND d3d12_console_descriptor_heap_test)
  set_tests_properties(d3d12_console_descriptor_heap PROPERTIES SKIP_RETURN_CODE 77)
  add_executable(d3d12_indirect_zero_test test/d3d12_indirect_zero_test.cpp)
  target_link_libraries(d3d12_indirect_zero_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_indirect_zero_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_indirect_zero_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_indirect_zero COMMAND d3d12_indirect_zero_test)
  set_tests_properties(d3d12_indirect_zero PROPERTIES SKIP_RETURN_CODE 77)
  set_tests_properties(d3d12_node_mask PROPERTIES SKIP_RETURN_CODE 77)
  set_tests_properties(d3d12_indirect_zero PROPERTIES SKIP_RETURN_CODE 77)

  # CopyResource / CopyTextureRegion between BC and its uncompressed equivalent (and depth <-> colour) against the
  # host runtime and WARP; run explicitly on a Vulkan GPU.
  add_executable(d3d12_copy_xfmt_test test/d3d12_copy_xfmt_test.cpp)
  target_link_libraries(d3d12_copy_xfmt_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_copy_xfmt_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_copy_xfmt_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_copy_xfmt COMMAND d3d12_copy_xfmt_test)
  set_tests_properties(d3d12_copy_xfmt PROPERTIES SKIP_RETURN_CODE 77)

  add_executable(d3d12_stencil_copy_test test/d3d12_stencil_copy_test.cpp)
  target_link_libraries(d3d12_stencil_copy_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_stencil_copy_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_stencil_copy_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_stencil_copy COMMAND d3d12_stencil_copy_test)
  set_tests_properties(d3d12_stencil_copy PROPERTIES SKIP_RETURN_CODE 77
    ENVIRONMENT "LEONIDA_HOST_ADAPTER=warp")

  # Query heaps and query calls by list type (Close results, CreateQueryHeap node masks, timestamp heap kinds)
  # against the host runtime and WARP; run explicitly on a Vulkan GPU.
  add_executable(d3d12_query_rules_test test/d3d12_query_rules_test.cpp)
  target_link_libraries(d3d12_query_rules_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_query_rules_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_query_rules_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_query_rules COMMAND d3d12_query_rules_test)
  set_tests_properties(d3d12_query_rules PROPERTIES SKIP_RETURN_CODE 77)

  # Vulkan-backed IDXGIFactory4 / IDXGISwapChain3 presentation over a Win32 HWND.
  add_executable(dxgi_swapchain_test test/dxgi_swapchain_test.cpp)
  target_link_libraries(dxgi_swapchain_test PRIVATE gta6rt_d3d12_com)
  target_compile_definitions(dxgi_swapchain_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(dxgi_swapchain_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME dxgi_swapchain COMMAND dxgi_swapchain_test)
  set_tests_properties(dxgi_swapchain PROPERTIES SKIP_RETURN_CODE 77)

  # The layer's DXGI against the host runtime's (hardware adapter, or WARP with PROBE_WARP=1): IDXGIAdapter4,
  # GetRestrictToOutput without an output, ResizeBuffers flag bits and null out-pointers.
  add_executable(dxgi_host_parity_test test/dxgi_host_parity_test.cpp)
  target_link_libraries(dxgi_host_parity_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(dxgi_host_parity_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(dxgi_host_parity_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME dxgi_host_parity COMMAND dxgi_host_parity_test)
  set_tests_properties(dxgi_host_parity PROPERTIES SKIP_RETURN_CODE 77)

  # Host-parity test for DXGI waitable swap chain frame-latency semaphore behavior.
  add_executable(dxgi_waitable_latency_test test/dxgi_waitable_latency_test.cpp)
  target_link_libraries(dxgi_waitable_latency_test PRIVATE gta6rt_d3d12_com)
  target_compile_definitions(dxgi_waitable_latency_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(dxgi_waitable_latency_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME dxgi_waitable_latency COMMAND dxgi_waitable_latency_test)
  set_tests_properties(dxgi_waitable_latency PROPERTIES
    SKIP_RETURN_CODE 77
    FAIL_REGULAR_EXPRESSION "Validation Error;VUID-")

  # Synthetic (no GPU): VulkanSwapchain's DXGI BufferCount contract when Vulkan returns more images than the
  # app asked for, or the surface minimum exceeds the request (D3D-389).
  add_executable(dxgi_swapchain_count_test test/dxgi_swapchain_count_test.cpp)
  target_link_libraries(dxgi_swapchain_count_test PRIVATE Vulkan::Headers)
  target_compile_definitions(dxgi_swapchain_count_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(dxgi_swapchain_count_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME dxgi_swapchain_count COMMAND dxgi_swapchain_count_test)

  # ExecuteIndirect with CountBuffer (vkCmdDrawIndirectCount) + optional BLAS/TLAS/RayQueryKHR GPU test.
  add_executable(d3d12_indirect_rt_test test/d3d12_indirect_rt_test.cpp)
  target_link_libraries(d3d12_indirect_rt_test PRIVATE gta6rt_d3d12_com)
  target_compile_definitions(d3d12_indirect_rt_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_indirect_rt_test PRIVATE /W4 /permissive- /utf-8)
  if(Vulkan_GLSLANG_VALIDATOR_EXECUTABLE)
    set(LEONIDA_TEST_VS_TRI ${CMAKE_CURRENT_BINARY_DIR}/generated/vs_tri.spv)
    set(LEONIDA_TEST_FS_SOLID ${CMAKE_CURRENT_BINARY_DIR}/generated/fs_solid.spv)
    set(LEONIDA_TEST_CS_RAYQUERY ${CMAKE_CURRENT_BINARY_DIR}/generated/cs_rayquery.spv)
    add_custom_command(
      OUTPUT ${LEONIDA_TEST_VS_TRI}
      COMMAND ${Vulkan_GLSLANG_VALIDATOR_EXECUTABLE} -V --target-env vulkan1.3 -o ${LEONIDA_TEST_VS_TRI}
              ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/vs_tri.vert
      DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/vs_tri.vert
      COMMENT "Compiling vs_tri.vert"
      VERBATIM)
    add_custom_command(
      OUTPUT ${LEONIDA_TEST_FS_SOLID}
      COMMAND ${Vulkan_GLSLANG_VALIDATOR_EXECUTABLE} -V --target-env vulkan1.3 -o ${LEONIDA_TEST_FS_SOLID}
              ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/fs_solid.frag
      DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/fs_solid.frag
      COMMENT "Compiling fs_solid.frag"
      VERBATIM)
    add_custom_command(
      OUTPUT ${LEONIDA_TEST_CS_RAYQUERY}
      COMMAND ${Vulkan_GLSLANG_VALIDATOR_EXECUTABLE} -V --target-env vulkan1.3 -o ${LEONIDA_TEST_CS_RAYQUERY}
              ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/cs_rayquery.comp
      DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/cs_rayquery.comp
      COMMENT "Compiling cs_rayquery.comp"
      VERBATIM)
    target_sources(d3d12_indirect_rt_test PRIVATE
                   ${LEONIDA_TEST_VS_TRI} ${LEONIDA_TEST_FS_SOLID} ${LEONIDA_TEST_CS_RAYQUERY})
    target_compile_definitions(d3d12_indirect_rt_test PRIVATE
      LEONIDA_TEST_VS_TRI_SPV="${LEONIDA_TEST_VS_TRI}"
      LEONIDA_TEST_FS_SOLID_SPV="${LEONIDA_TEST_FS_SOLID}"
      LEONIDA_TEST_CS_RAYQUERY_SPV="${LEONIDA_TEST_CS_RAYQUERY}")
  endif()
  add_test(NAME d3d12_indirect_rt COMMAND d3d12_indirect_rt_test)
  set_tests_properties(d3d12_indirect_rt PROPERTIES SKIP_RETURN_CODE 77)
  # Upload heaps in system memory, as on a GPU without Resizable BAR: their VAs can lie below the arena and wrap.
  add_test(NAME d3d12_indirect_rt_upload_sysmem COMMAND d3d12_indirect_rt_test)
  set_tests_properties(d3d12_indirect_rt_upload_sysmem PROPERTIES SKIP_RETURN_CODE 77
                       ENVIRONMENT "LEONIDA_UPLOAD_SYSMEM=1")

  # The compute path: root signature, compute PSO from a translator-style index, root arguments, dispatch. Its
  # shader is GLSL written to the translator's push-constant/address contract, compiled here.
  if(NOT Vulkan_GLSLANG_VALIDATOR_EXECUTABLE)
    find_program(Vulkan_GLSLANG_VALIDATOR_EXECUTABLE glslangValidator HINTS "$ENV{VULKAN_SDK}/Bin" "$ENV{VULKAN_SDK}/bin")
  endif()
  if(Vulkan_GLSLANG_VALIDATOR_EXECUTABLE)
    set(LEONIDA_TEST_CS ${CMAKE_CURRENT_BINARY_DIR}/generated/cs_user_data.spv)
    add_custom_command(
      OUTPUT ${LEONIDA_TEST_CS}
      COMMAND ${Vulkan_GLSLANG_VALIDATOR_EXECUTABLE} -V --target-env vulkan1.3 -o ${LEONIDA_TEST_CS}
              ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/cs_user_data.comp
      DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/cs_user_data.comp
      COMMENT "Compiling the compute test shader"
      VERBATIM)
    add_executable(d3d12_compute_test test/d3d12_compute_test.cpp shims/d3d12_xs_device.cpp ${LEONIDA_TEST_CS})
    target_link_libraries(d3d12_compute_test PRIVATE gta6rt_d3d12_com)
    target_compile_definitions(d3d12_compute_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX
                               LEONIDA_TEST_CS_SPV="${LEONIDA_TEST_CS}")
    target_compile_options(d3d12_compute_test PRIVATE /W4 /permissive- /utf-8)
    add_test(NAME d3d12_compute COMMAND d3d12_compute_test)
    set_tests_properties(d3d12_compute PROPERTIES SKIP_RETURN_CODE 77)
    # Compute PSOs from FSPX programs (docs/fspx.md): an ACCC container at slot 62 and a bare kind-6 program.
    add_executable(d3d12_fspx_compute_test test/d3d12_fspx_compute_test.cpp shims/d3d12_xs_device.cpp ${LEONIDA_TEST_CS})
    target_link_libraries(d3d12_fspx_compute_test PRIVATE gta6rt_d3d12_com)
    target_compile_definitions(d3d12_fspx_compute_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX
                               LEONIDA_TEST_CS_SPV="${LEONIDA_TEST_CS}")
    target_compile_options(d3d12_fspx_compute_test PRIVATE /W4 /permissive- /utf-8)
    add_test(NAME d3d12_fspx_compute COMMAND d3d12_fspx_compute_test)
    set_tests_properties(d3d12_fspx_compute PROPERTIES SKIP_RETURN_CODE 77)
    # Milestone M1: a VS+PS pipeline and indexed draws, shaders written to the same contract.
    set(LEONIDA_TEST_VS ${CMAKE_CURRENT_BINARY_DIR}/generated/vs_draw.spv)
    set(LEONIDA_TEST_PS ${CMAKE_CURRENT_BINARY_DIR}/generated/ps_draw.spv)
    set(LEONIDA_TEST_PS_UINT ${CMAKE_CURRENT_BINARY_DIR}/generated/ps_draw_uint.spv)
    set(LEONIDA_TEST_VS_FULLSCREEN ${CMAKE_CURRENT_BINARY_DIR}/generated/vs_fullscreen.spv)
    set(LEONIDA_TEST_VS_INT ${CMAKE_CURRENT_BINARY_DIR}/generated/vs_draw_int.spv)
    set(LEONIDA_TEST_GS_DOUBLE ${CMAKE_CURRENT_BINARY_DIR}/generated/gs_double.spv)
    foreach(pair "vs_draw.vert;${LEONIDA_TEST_VS}" "ps_draw.frag;${LEONIDA_TEST_PS}"
                 "ps_draw_uint.frag;${LEONIDA_TEST_PS_UINT}" "vs_fullscreen.vert;${LEONIDA_TEST_VS_FULLSCREEN}" "vs_draw_int.vert;${LEONIDA_TEST_VS_INT}"
                 "gs_double.geom;${LEONIDA_TEST_GS_DOUBLE}")
      list(GET pair 0 source)
      list(GET pair 1 output)
      add_custom_command(
        OUTPUT ${output}
        COMMAND ${Vulkan_GLSLANG_VALIDATOR_EXECUTABLE} -V --target-env vulkan1.3 -o ${output}
                ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/${source}
        DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/${source}
        COMMENT "Compiling the draw test shader ${source}"
        VERBATIM)
    endforeach()
    add_executable(d3d12_draw_test test/d3d12_draw_test.cpp shims/d3d12_xs_device.cpp ${LEONIDA_TEST_VS}
                   ${LEONIDA_TEST_PS} ${LEONIDA_TEST_PS_UINT} ${LEONIDA_TEST_VS_FULLSCREEN} ${LEONIDA_TEST_VS_INT})
    target_link_libraries(d3d12_draw_test PRIVATE gta6rt_d3d12_com)
    target_compile_definitions(d3d12_draw_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX
                               LEONIDA_TEST_VS_SPV="${LEONIDA_TEST_VS}" LEONIDA_TEST_PS_SPV="${LEONIDA_TEST_PS}"
                               LEONIDA_TEST_PS_UINT_SPV="${LEONIDA_TEST_PS_UINT}"
                               LEONIDA_TEST_VS_FULLSCREEN_SPV="${LEONIDA_TEST_VS_FULLSCREEN}"
                               LEONIDA_TEST_VS_INT_SPV="${LEONIDA_TEST_VS_INT}")
    target_compile_options(d3d12_draw_test PRIVATE /W4 /permissive- /utf-8)
    add_test(NAME d3d12_draw COMMAND d3d12_draw_test)
    set_tests_properties(d3d12_draw PROPERTIES SKIP_RETURN_CODE 77)
    # Graphics & compute PSO descriptor validation parity against live Windows D3D12 (WARP and HW).
    add_executable(d3d12_pso_validation_test test/d3d12_pso_validation_test.cpp ${LEONIDA_TEST_VS}
                   ${LEONIDA_TEST_PS} ${LEONIDA_TEST_PS_UINT} ${LEONIDA_TEST_VS_FULLSCREEN} ${LEONIDA_TEST_CS})
    target_link_libraries(d3d12_pso_validation_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
    target_compile_definitions(d3d12_pso_validation_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX
                               LEONIDA_TEST_VS_SPV="${LEONIDA_TEST_VS}" LEONIDA_TEST_PS_SPV="${LEONIDA_TEST_PS}"
                               LEONIDA_TEST_PS_UINT_SPV="${LEONIDA_TEST_PS_UINT}"
                               LEONIDA_TEST_VS_FULLSCREEN_SPV="${LEONIDA_TEST_VS_FULLSCREEN}"
                               LEONIDA_TEST_CS_SPV="${LEONIDA_TEST_CS}")
    target_compile_options(d3d12_pso_validation_test PRIVATE /W4 /permissive- /utf-8)
    add_test(NAME d3d12_pso_validation COMMAND d3d12_pso_validation_test)
    set_tests_properties(d3d12_pso_validation PROPERTIES SKIP_RETURN_CODE 77
                         FAIL_REGULAR_EXPRESSION "Validation Error;VUID-")
    # Conservative raster Tier 1, with geometric coverage bounds and host D3D12 references.
    set(LEONIDA_CONSERVATIVE_VS ${CMAKE_CURRENT_BINARY_DIR}/generated/vs_conservative.spv)
    set(LEONIDA_CONSERVATIVE_PS ${CMAKE_CURRENT_BINARY_DIR}/generated/ps_conservative.spv)
    foreach(pair "vs_conservative.vert;${LEONIDA_CONSERVATIVE_VS}" "ps_conservative.frag;${LEONIDA_CONSERVATIVE_PS}")
      list(GET pair 0 source)
      list(GET pair 1 output)
      add_custom_command(OUTPUT ${output}
        COMMAND ${Vulkan_GLSLANG_VALIDATOR_EXECUTABLE} -V --target-env vulkan1.3 -o ${output}
                ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/${source}
        DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/${source} VERBATIM)
    endforeach()
    add_executable(d3d12_conservative_raster_test test/d3d12_conservative_raster_test.cpp
      ${LEONIDA_CONSERVATIVE_VS} ${LEONIDA_CONSERVATIVE_PS})
    target_link_libraries(d3d12_conservative_raster_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
    target_compile_definitions(d3d12_conservative_raster_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX
      LEONIDA_CONSERVATIVE_VS="${LEONIDA_CONSERVATIVE_VS}" LEONIDA_CONSERVATIVE_PS="${LEONIDA_CONSERVATIVE_PS}")
    target_compile_options(d3d12_conservative_raster_test PRIVATE /W4 /permissive- /utf-8)
    add_test(NAME d3d12_conservative_raster COMMAND d3d12_conservative_raster_test)
    set_tests_properties(d3d12_conservative_raster PROPERTIES SKIP_RETURN_CODE 77
      ENVIRONMENT "LEONIDA_HOST_ADAPTER=warp")
    set(LEONIDA_CONSERVATIVE_TIER2_VS ${CMAKE_CURRENT_BINARY_DIR}/generated/vs_conservative_tier2.spv)
    set(LEONIDA_CONSERVATIVE_TIER2_PS ${CMAKE_CURRENT_BINARY_DIR}/generated/ps_conservative_tier2.spv)
    foreach(pair "vs_conservative_tier2.vert;${LEONIDA_CONSERVATIVE_TIER2_VS}" "ps_conservative_tier2.frag;${LEONIDA_CONSERVATIVE_TIER2_PS}")
      list(GET pair 0 source)
      list(GET pair 1 output)
      add_custom_command(OUTPUT ${output}
        COMMAND ${Vulkan_GLSLANG_VALIDATOR_EXECUTABLE} -V --target-env vulkan1.3 -o ${output}
                ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/${source}
        DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/${source} VERBATIM)
    endforeach()
    add_executable(d3d12_conservative_tier2_test test/d3d12_conservative_tier2_test.cpp
      ${LEONIDA_CONSERVATIVE_TIER2_VS} ${LEONIDA_CONSERVATIVE_TIER2_PS})
    target_link_libraries(d3d12_conservative_tier2_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
    target_compile_definitions(d3d12_conservative_tier2_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX
      LEONIDA_CONSERVATIVE_TIER2_VS="${LEONIDA_CONSERVATIVE_TIER2_VS}" LEONIDA_CONSERVATIVE_TIER2_PS="${LEONIDA_CONSERVATIVE_TIER2_PS}")
    target_compile_options(d3d12_conservative_tier2_test PRIVATE /W4 /permissive- /utf-8)
    add_test(NAME d3d12_conservative_tier2 COMMAND d3d12_conservative_tier2_test)
    set_tests_properties(d3d12_conservative_tier2 PROPERTIES SKIP_RETURN_CODE 77 ENVIRONMENT "LEONIDA_HOST_ADAPTER=warp")
    set(LEONIDA_CONSERVATIVE_TIER3_PS ${CMAKE_CURRENT_BINARY_DIR}/generated/ps_conservative_tier3.spv)
    add_custom_command(OUTPUT ${LEONIDA_CONSERVATIVE_TIER3_PS}
      COMMAND ${Vulkan_GLSLANG_VALIDATOR_EXECUTABLE} -V --target-env vulkan1.3 -o ${LEONIDA_CONSERVATIVE_TIER3_PS}
              ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/ps_conservative_tier3.frag
      DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/ps_conservative_tier3.frag VERBATIM)
    add_executable(d3d12_conservative_tier3_test test/d3d12_conservative_tier3_test.cpp
      ${LEONIDA_CONSERVATIVE_VS} ${LEONIDA_CONSERVATIVE_TIER3_PS})
    target_link_libraries(d3d12_conservative_tier3_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
    target_compile_definitions(d3d12_conservative_tier3_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX
      LEONIDA_CONSERVATIVE_VS="${LEONIDA_CONSERVATIVE_VS}"
      LEONIDA_CONSERVATIVE_TIER3_PS="${LEONIDA_CONSERVATIVE_TIER3_PS}")
    target_compile_options(d3d12_conservative_tier3_test PRIVATE /W4 /permissive- /utf-8)
    add_test(NAME inner_coverage_oracle COMMAND d3d12_conservative_tier3_test --oracle-only)
    add_test(NAME d3d12_inner_coverage_guards COMMAND d3d12_conservative_tier3_test --guards-only)
    add_test(NAME d3d12_inner_coverage_native COMMAND d3d12_conservative_tier3_test --native-only)
    add_test(NAME d3d12_conservative_tier3 COMMAND d3d12_conservative_tier3_test)
    set_tests_properties(d3d12_inner_coverage_guards d3d12_inner_coverage_native d3d12_conservative_tier3
      PROPERTIES SKIP_RETURN_CODE 77)
    add_executable(d3d12_msaa_draw_test test/d3d12_msaa_draw_test.cpp shims/d3d12_xs_device.cpp
                   ${LEONIDA_TEST_VS} ${LEONIDA_TEST_PS})
    target_link_libraries(d3d12_msaa_draw_test PRIVATE gta6rt_d3d12_com)
    target_compile_definitions(d3d12_msaa_draw_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX
                               LEONIDA_TEST_VS_SPV="${LEONIDA_TEST_VS}" LEONIDA_TEST_PS_SPV="${LEONIDA_TEST_PS}")
    target_compile_options(d3d12_msaa_draw_test PRIVATE /W4 /permissive- /utf-8)
    add_test(NAME d3d12_msaa_draw COMMAND d3d12_msaa_draw_test)
    set_tests_properties(d3d12_msaa_draw PROPERTIES SKIP_RETURN_CODE 77)
    # Geometry shaders: a VS+GS+PS pipeline whose GS emits each triangle twice.
    add_executable(d3d12_geometry_test test/d3d12_geometry_test.cpp shims/d3d12_xs_device.cpp
                   ${LEONIDA_TEST_VS} ${LEONIDA_TEST_GS_DOUBLE} ${LEONIDA_TEST_PS})
    target_link_libraries(d3d12_geometry_test PRIVATE gta6rt_d3d12_com)
    target_compile_definitions(d3d12_geometry_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX
                               LEONIDA_TEST_VS_SPV="${LEONIDA_TEST_VS}" LEONIDA_TEST_GS_SPV="${LEONIDA_TEST_GS_DOUBLE}"
                               LEONIDA_TEST_PS_SPV="${LEONIDA_TEST_PS}")
    target_compile_options(d3d12_geometry_test PRIVATE /W4 /permissive- /utf-8)
    add_test(NAME d3d12_geometry COMMAND d3d12_geometry_test)
    set_tests_properties(d3d12_geometry PROPERTIES SKIP_RETURN_CODE 77)
    # D3D-309: D24 depth bias and 24-bit depth in draws, with and without a pixel shader and with a geometry shader
    # (src/depth24_fragment.h).
    set(LEONIDA_TEST_VS_DEPTH ${CMAKE_CURRENT_BINARY_DIR}/generated/vs_depth.spv)
    set(LEONIDA_TEST_PS_DEPTH_EMPTY ${CMAKE_CURRENT_BINARY_DIR}/generated/ps_depth_empty.spv)
    set(LEONIDA_TEST_PS_DEPTH_WRITE ${CMAKE_CURRENT_BINARY_DIR}/generated/ps_depth_write.spv)
    set(LEONIDA_TEST_GS_DEPTH ${CMAKE_CURRENT_BINARY_DIR}/generated/gs_depth.spv)
    foreach(pair "vs_depth.vert;${LEONIDA_TEST_VS_DEPTH}" "ps_depth_empty.frag;${LEONIDA_TEST_PS_DEPTH_EMPTY}"
                 "ps_depth_write.frag;${LEONIDA_TEST_PS_DEPTH_WRITE}" "gs_depth.geom;${LEONIDA_TEST_GS_DEPTH}")
      list(GET pair 0 source)
      list(GET pair 1 output)
      add_custom_command(
        OUTPUT ${output}
        COMMAND ${Vulkan_GLSLANG_VALIDATOR_EXECUTABLE} -V --target-env vulkan1.3 -o ${output}
                ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/${source}
        DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/${source}
        COMMENT "Compiling the D24 draw test shader ${source}"
        VERBATIM)
    endforeach()
    add_executable(d3d12_depth24_draw_test test/d3d12_depth24_draw_test.cpp shims/d3d12_xs_device.cpp
                   ${LEONIDA_TEST_VS_DEPTH} ${LEONIDA_TEST_PS_DEPTH_EMPTY} ${LEONIDA_TEST_PS_DEPTH_WRITE}
                   ${LEONIDA_TEST_GS_DEPTH})
    target_link_libraries(d3d12_depth24_draw_test PRIVATE gta6rt_d3d12_com)
    target_compile_definitions(d3d12_depth24_draw_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX
                               LEONIDA_TEST_VS_DEPTH_SPV="${LEONIDA_TEST_VS_DEPTH}"
                               LEONIDA_TEST_PS_DEPTH_EMPTY_SPV="${LEONIDA_TEST_PS_DEPTH_EMPTY}"
                               LEONIDA_TEST_PS_DEPTH_WRITE_SPV="${LEONIDA_TEST_PS_DEPTH_WRITE}"
                               LEONIDA_TEST_GS_DEPTH_SPV="${LEONIDA_TEST_GS_DEPTH}")
    target_compile_options(d3d12_depth24_draw_test PRIVATE /W4 /permissive- /utf-8)
    add_test(NAME d3d12_depth24_draw COMMAND d3d12_depth24_draw_test)
    set_tests_properties(d3d12_depth24_draw PROPERTIES SKIP_RETURN_CODE 77)
    # Set 0 from the compute bind point: a compute PSO whose shader declares set-0 bindings samples through the
    # device's bindless set, which nothing but the layer binds.
    set(LEONIDA_TEST_CS_SET0_SAMPLE ${CMAKE_CURRENT_BINARY_DIR}/generated/cs_set0_sample.spv)
    add_custom_command(
      OUTPUT ${LEONIDA_TEST_CS_SET0_SAMPLE}
      COMMAND ${Vulkan_GLSLANG_VALIDATOR_EXECUTABLE} -V --target-env vulkan1.3 -o ${LEONIDA_TEST_CS_SET0_SAMPLE}
              ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/cs_set0_sample.comp
      DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/cs_set0_sample.comp
      COMMENT "Compiling the set-0 compute test shader"
      VERBATIM)
    add_executable(d3d12_set0_compute_test test/d3d12_set0_compute_test.cpp shims/d3d12_xs_device.cpp
                   ${LEONIDA_TEST_CS_SET0_SAMPLE})
    target_link_libraries(d3d12_set0_compute_test PRIVATE gta6rt_d3d12_com)
    target_compile_definitions(d3d12_set0_compute_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX
                               LEONIDA_TEST_CS_SET0_SAMPLE_SPV="${LEONIDA_TEST_CS_SET0_SAMPLE}")
    target_compile_options(d3d12_set0_compute_test PRIVATE /W4 /permissive- /utf-8)
    add_test(NAME d3d12_set0_compute COMMAND d3d12_set0_compute_test)
    set_tests_properties(d3d12_set0_compute PROPERTIES SKIP_RETURN_CODE 77)
    # Bindless table churn on a direct and a compute queue: the table grows and live keys move without a
    # device-idle wait (D3D-314); the same shader, run twice (deferred retirement, and the old wait for timing).
    add_executable(d3d12_bindless_churn_test test/d3d12_bindless_churn_test.cpp shims/d3d12_xs_device.cpp
                   ${LEONIDA_TEST_CS_SET0_SAMPLE})
    target_link_libraries(d3d12_bindless_churn_test PRIVATE gta6rt_d3d12_com)
    target_compile_definitions(d3d12_bindless_churn_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX
                               LEONIDA_TEST_CS_SET0_SAMPLE_SPV="${LEONIDA_TEST_CS_SET0_SAMPLE}")
    target_compile_options(d3d12_bindless_churn_test PRIVATE /W4 /permissive- /utf-8)
    add_test(NAME d3d12_bindless_churn COMMAND d3d12_bindless_churn_test)
    set_tests_properties(d3d12_bindless_churn PROPERTIES SKIP_RETURN_CODE 77)
    add_test(NAME d3d12_bindless_churn_validated COMMAND d3d12_bindless_churn_test --validated)
    set_tests_properties(d3d12_bindless_churn_validated PROPERTIES SKIP_RETURN_CODE 77)
    add_executable(d3d12_pipeline_library_test test/d3d12_pipeline_library_test.cpp
                   ${LEONIDA_TEST_CS} ${LEONIDA_TEST_VS} ${LEONIDA_TEST_PS})
    target_link_libraries(d3d12_pipeline_library_test PRIVATE gta6rt_d3d12_com)
    target_compile_definitions(d3d12_pipeline_library_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX
                               LEONIDA_TEST_CS_SPV="${LEONIDA_TEST_CS}"
                               LEONIDA_TEST_VS_SPV="${LEONIDA_TEST_VS}"
                               LEONIDA_TEST_PS_SPV="${LEONIDA_TEST_PS}")
    target_compile_options(d3d12_pipeline_library_test PRIVATE /W4 /permissive- /utf-8)
    add_test(NAME d3d12_pipeline_library COMMAND d3d12_pipeline_library_test)
    set_tests_properties(d3d12_pipeline_library PROPERTIES SKIP_RETURN_CODE 77)
    # ExecuteBundle: what a bundle's draws inherit and hand back, against the host runtime and WARP.
    add_executable(d3d12_bundle_test test/d3d12_bundle_test.cpp ${LEONIDA_TEST_VS} ${LEONIDA_TEST_PS})
    target_link_libraries(d3d12_bundle_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
    target_compile_definitions(d3d12_bundle_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX _CRT_SECURE_NO_WARNINGS
                               LEONIDA_TEST_VS_SPV="${LEONIDA_TEST_VS}" LEONIDA_TEST_PS_SPV="${LEONIDA_TEST_PS}")
    target_compile_options(d3d12_bundle_test PRIVATE /W4 /permissive- /utf-8)
    add_test(NAME d3d12_bundle COMMAND d3d12_bundle_test)
    set_tests_properties(d3d12_bundle PROPERTIES SKIP_RETURN_CODE 77)
    # Calls a bundle may not make, Close of the bundle and of its parent, against the host runtime and WARP.
    add_executable(d3d12_bundle_forbidden_test test/d3d12_bundle_forbidden_test.cpp)
    target_link_libraries(d3d12_bundle_forbidden_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
    target_compile_definitions(d3d12_bundle_forbidden_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
    target_compile_options(d3d12_bundle_forbidden_test PRIVATE /W4 /permissive- /utf-8)
    add_test(NAME d3d12_bundle_forbidden COMMAND d3d12_bundle_forbidden_test)
    set_tests_properties(d3d12_bundle_forbidden PROPERTIES SKIP_RETURN_CODE 77)
    # A pixel shader with a writable storage image (an image atomic) needs fragmentStoresAndAtomics: refused on a
    # device without it, created on the runtime's own device, under the validation layer where it is installed.
    set(LEONIDA_TEST_PS_ATOMIC ${CMAKE_CURRENT_BINARY_DIR}/generated/ps_image_atomic.spv)
    add_custom_command(
      OUTPUT ${LEONIDA_TEST_PS_ATOMIC}
      COMMAND ${Vulkan_GLSLANG_VALIDATOR_EXECUTABLE} -V --target-env vulkan1.3 -o ${LEONIDA_TEST_PS_ATOMIC}
              ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/ps_image_atomic.frag
      DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/ps_image_atomic.frag
      COMMENT "Compiling the stores-and-atomics test shader ps_image_atomic.frag"
      VERBATIM)
    add_executable(d3d12_stores_atomics_test test/d3d12_stores_atomics_test.cpp ${LEONIDA_TEST_VS_FULLSCREEN}
                   ${LEONIDA_TEST_PS} ${LEONIDA_TEST_PS_ATOMIC})
    target_link_libraries(d3d12_stores_atomics_test PRIVATE gta6rt_d3d12_com)
    target_compile_definitions(d3d12_stores_atomics_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX
                               LEONIDA_TEST_VS_FULLSCREEN_SPV="${LEONIDA_TEST_VS_FULLSCREEN}"
                               LEONIDA_TEST_PS_SPV="${LEONIDA_TEST_PS}"
                               LEONIDA_TEST_PS_ATOMIC_SPV="${LEONIDA_TEST_PS_ATOMIC}")
    target_compile_options(d3d12_stores_atomics_test PRIVATE /W4 /permissive- /utf-8)
    add_test(NAME d3d12_stores_atomics COMMAND d3d12_stores_atomics_test)
    set_tests_properties(d3d12_stores_atomics PROPERTIES SKIP_RETURN_CODE 77)

    # D3D-29: mesh-shader PSOs from pipeline state streams and DispatchMesh (skips without VK_EXT_mesh_shader).
    set(LEONIDA_TEST_MS ${CMAKE_CURRENT_BINARY_DIR}/generated/ms_draw.spv)
    add_custom_command(
      OUTPUT ${LEONIDA_TEST_MS}
      # Vulkan 1.2 (SPIR-V 1.5), the translator's target: 1.3 would emit LocalSizeId, which needs maintenance4.
      COMMAND ${Vulkan_GLSLANG_VALIDATOR_EXECUTABLE} -V --target-env vulkan1.2 -o ${LEONIDA_TEST_MS}
              ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/ms_draw.mesh
      DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/ms_draw.mesh
      COMMENT "Compiling the mesh test shader ms_draw.mesh"
      VERBATIM)
    add_executable(d3d12_mesh_test test/d3d12_mesh_test.cpp shims/d3d12_xs_device.cpp ${LEONIDA_TEST_MS}
                   ${LEONIDA_TEST_PS} ${LEONIDA_TEST_VS_FULLSCREEN})
    target_link_libraries(d3d12_mesh_test PRIVATE gta6rt_d3d12_com)
    target_compile_definitions(d3d12_mesh_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX
                               LEONIDA_TEST_MS_SPV="${LEONIDA_TEST_MS}" LEONIDA_TEST_PS_SPV="${LEONIDA_TEST_PS}"
                               LEONIDA_TEST_VS_FULLSCREEN_SPV="${LEONIDA_TEST_VS_FULLSCREEN}")
    target_compile_options(d3d12_mesh_test PRIVATE /W4 /permissive- /utf-8)
    add_test(NAME d3d12_mesh COMMAND d3d12_mesh_test)
    set_tests_properties(d3d12_mesh PROPERTIES SKIP_RETURN_CODE 77)
  else()
    message(STATUS "glslangValidator not found: d3d12_compute_test, d3d12_draw_test, d3d12_set0_compute_test and d3d12_mesh_test are not built")
  endif()

  # Native D3D12 SV_InnerCoverage reference; its HLSL is compiled at runtime, so glslang is not needed.
  add_executable(d3d12_conservative_tier3_reference_test test/d3d12_conservative_tier3_reference_test.cpp)
  target_link_libraries(d3d12_conservative_tier3_reference_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_conservative_tier3_reference_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_conservative_tier3_reference_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_conservative_tier3_reference COMMAND d3d12_conservative_tier3_reference_test)
  set_tests_properties(d3d12_conservative_tier3_reference PROPERTIES SKIP_RETURN_CODE 77)

  # Subgroup size control in PSOs, end to end: runtime/test/shaders/cs_w64x_readlane.asm translated natively and with
  # --wave64-emulate, and cs_wqm_w32.asm, built here with tools/rdna2spirv.py through test/shaders/build.py. Needs
  # llvm-mc with the AMDGPU target (LLVM_MC in the environment, as for the other shader tests, or llvm-mc on PATH)
  # and the Vulkan SDK's spirv tools; without them the test is not built.
  if(DEFINED ENV{LLVM_MC})
    set(LEONIDA_LLVM_MC "$ENV{LLVM_MC}")
  else()
    find_program(LEONIDA_LLVM_MC llvm-mc HINTS "C:/msys64/ucrt64/bin")
  endif()
  if(LEONIDA_LLVM_MC AND Vulkan_GLSLANG_VALIDATOR_EXECUTABLE)
    set(LEONIDA_SG_DIR ${CMAKE_CURRENT_BINARY_DIR}/generated/subgroup_shaders)
    set(LEONIDA_SG_INDEXES "")
    foreach(case "w64_native;cs_w64x_readlane;0" "w64_emulated;cs_w64x_readlane;1" "w32_native;cs_wqm_w32;0"
                     "ps_w64_native;ps_w64x_readlane;0")
      list(GET case 0 folder)
      list(GET case 1 shader)
      list(GET case 2 emulate)
      set(index ${LEONIDA_SG_DIR}/${folder}/spirv/index.json)
      add_custom_command(
        OUTPUT ${index}
        # The standalone harness runs these with the V# at s[0:3]; d3d12_subgroup_test passes it as four root
        # constants, which the D3D12 compute layout puts at s[4:7] (LEONIDA_USER_DATA_SHIFT=4, D3D-448).
        COMMAND ${CMAKE_COMMAND} -E env LLVM_MC=${LEONIDA_LLVM_MC} LEONIDA_W64_EMULATE=${emulate}
                LEONIDA_USER_DATA_SHIFT=4
                $<TARGET_FILE:Python3::Interpreter> -I ${CMAKE_CURRENT_SOURCE_DIR}/test/shaders/build.py
                ${LEONIDA_SG_DIR}/${folder} ${shader}
        DEPENDS ${LEONIDA_TRANSLATOR_DEPS}
                ${CMAKE_CURRENT_SOURCE_DIR}/test/shaders/${shader}.asm
        COMMENT "Translating ${shader} for the subgroup size test (${folder})"
        VERBATIM)
      list(APPEND LEONIDA_SG_INDEXES ${index})
    endforeach()
    # The probe shaders that store the subgroup size the driver ran them with, and a one-triangle vertex shader.
    foreach(source cs_sg_probe.comp ps_sg_probe.frag vs_sg_fullscreen.vert)
      set(output ${LEONIDA_SG_DIR}/glsl/${source}.spv)
      add_custom_command(
        OUTPUT ${output}
        COMMAND ${CMAKE_COMMAND} -E make_directory ${LEONIDA_SG_DIR}/glsl
        COMMAND ${Vulkan_GLSLANG_VALIDATOR_EXECUTABLE} -V --target-env vulkan1.3 -o ${output}
                ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/${source}
        DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/${source}
        COMMENT "Compiling ${source}"
        VERBATIM)
      list(APPEND LEONIDA_SG_INDEXES ${output})
    endforeach()
    add_executable(d3d12_subgroup_test test/d3d12_subgroup_test.cpp shims/d3d12_xs_device.cpp ${LEONIDA_SG_INDEXES})
    target_link_libraries(d3d12_subgroup_test PRIVATE gta6rt_d3d12_com)
    target_compile_definitions(d3d12_subgroup_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX
                               LEONIDA_TEST_SUBGROUP_SHADERS="${LEONIDA_SG_DIR}")
    target_compile_options(d3d12_subgroup_test PRIVATE /W4 /permissive- /utf-8)
    add_test(NAME d3d12_subgroup COMMAND d3d12_subgroup_test)
    set_tests_properties(d3d12_subgroup PROPERTIES SKIP_RETURN_CODE 77)
  else()
    message(STATUS "llvm-mc (set LLVM_MC) or glslangValidator not found: d3d12_subgroup_test is not built")
  endif()

  # Clears on every format class against WARP (needs a Vulkan GPU; exit 77 without one).
  add_executable(d3d12_clear_formats_test test/d3d12_clear_formats_test.cpp)
  target_link_libraries(d3d12_clear_formats_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_clear_formats_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_clear_formats_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_clear_formats COMMAND d3d12_clear_formats_test)
  set_tests_properties(d3d12_clear_formats PROPERTIES SKIP_RETURN_CODE 77)

  # SetDescriptorHeaps validation, Reset/ClearState/bundle parity, lifetime pinning, direct-index flags.
  add_executable(d3d12_set_descriptor_heaps_test test/d3d12_set_descriptor_heaps_test.cpp)
  target_link_libraries(d3d12_set_descriptor_heaps_test PRIVATE gta6rt_d3d12_com d3d12 dxgi)
  target_compile_definitions(d3d12_set_descriptor_heaps_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_set_descriptor_heaps_test PRIVATE /W4 /permissive- /utf-8)
  add_test(NAME d3d12_set_descriptor_heaps COMMAND d3d12_set_descriptor_heaps_test)
  set_tests_properties(d3d12_set_descriptor_heaps PROPERTIES SKIP_RETURN_CODE 77
                       FAIL_REGULAR_EXPRESSION "Validation Error;VUID-")

  # The loader can create this device instead of the host's (D3D12XboxCreateDevice, LEONIDA_D3D12=vulkan).
  if(TARGET gta6rt)
    target_link_libraries(gta6rt PRIVATE gta6rt_d3d12_com)
    target_compile_definitions(gta6rt PRIVATE LEONIDA_VULKAN_DEVICE)

    # A stand-in title that imports d3d12_xs.dll!D3D12XboxCreateDevice and runs a clear and a readback on the
    # device it gets, mapped and run by `gta6rt --run` with LEONIDA_D3D12=vulkan: the loader, the game thread, the
    # proxies and the Vulkan device in one process. check_tiny_frame.py reads the verdict, the binding and the
    # call order from outside; d3d12_com_test is its probe for "no usable Vulkan device" (exit code 77).
    leonida_add_d3d12_xs_stub()
    add_executable(tiny_frame test/fixtures/tiny_frame.cpp)
    target_link_libraries(tiny_frame PRIVATE d3d12_xs_stub)
    target_compile_definitions(tiny_frame PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
    target_compile_options(tiny_frame PRIVATE /W4 /permissive- /utf-8)
    set_target_properties(tiny_frame PROPERTIES
      RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/fixtures/game/$<CONFIG>"
    )
    if(Python3_FOUND)
      add_test(NAME run_tiny_frame COMMAND "${Python3_EXECUTABLE}" -I
               "${CMAKE_CURRENT_SOURCE_DIR}/test/check_tiny_frame.py" "$<TARGET_FILE:gta6rt>"
               "$<TARGET_FILE:tiny_frame>" "--probe=$<TARGET_FILE:d3d12_com_test>" ${_trace_runner})
      set_tests_properties(run_tiny_frame PROPERTIES SKIP_RETURN_CODE 77)
      # The queue test settings are for the tests only: left set, they must not shrink the game's device.
      add_test(NAME run_tiny_frame_queue_test_settings COMMAND "${Python3_EXECUTABLE}" -I
               "${CMAKE_CURRENT_SOURCE_DIR}/test/check_tiny_frame.py" "$<TARGET_FILE:gta6rt>"
               "$<TARGET_FILE:tiny_frame>" "--probe=$<TARGET_FILE:d3d12_com_test>" --queue-test-settings
               ${_trace_runner})
      set_tests_properties(run_tiny_frame_queue_test_settings PROPERTIES SKIP_RETURN_CODE 77)
    endif()
  endif()

  # M1.5 as a `gta6rt --run` guest: test/d3d12_translated_draw_test.cpp built again with LEONIDA_M15_GUEST as
  # tiny_guest_draw.exe, whose only device is the D3D12XboxCreateDevice it imports from d3d12_xs.dll. The import
  # library comes from a failing stub built into fixtures/stubs, away from the guest, so only gta6rt's shim registry
  # can answer it. The guest links nothing from src/ or shims/ and can be
  # copied with its ordinary CRT dependencies, given the m15 folder as its argument. test/run_guest_draw.cmake checks the exit code and the marker line.
  # Opt-in: it needs a Vulkan GPU and the guest cannot tell a missing one from a bug, so default runs are unchanged.
  option(LEONIDA_TEST_GUEST_DRAW
         "Build tiny_guest_draw.exe and run the M1.5 draw through gta6rt --run (needs a Vulkan GPU)" OFF)
  option(LEONIDA_GUEST_SCENE "Build the headless 600-frame synthetic guest test (requires static SDL3)" OFF)
  if(LEONIDA_TEST_GUEST_DRAW OR LEONIDA_GUEST_SCENE)
    # The import stub is shared with the tiny_frame clear/readback guest.
    leonida_add_d3d12_xs_stub()
    add_executable(tiny_guest_draw test/d3d12_translated_draw_test.cpp)
    target_link_libraries(tiny_guest_draw PRIVATE d3d12_xs_stub Vulkan::Headers)
    target_compile_definitions(tiny_guest_draw PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX LEONIDA_M15_GUEST)
    target_compile_options(tiny_guest_draw PRIVATE /W4 /permissive- /utf-8)
    set_target_properties(tiny_guest_draw PROPERTIES
      OUTPUT_NAME tiny_guest_draw
      RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/fixtures/guest_draw/$<CONFIG>"
    )
    if(LEONIDA_GUEST_SCENE)
      if(NOT TARGET gta6rt OR NOT TARGET SDL3::SDL3-static OR NOT LEONIDA_SDL3)
        message(FATAL_ERROR "LEONIDA_GUEST_SCENE requires static SDL3; configure SDL3_DIR or LEONIDA_SDL3_FETCH")
      endif()
      target_compile_definitions(tiny_guest_draw PRIVATE LEONIDA_GUEST_SCENE)
      target_sources(gta6rt PRIVATE test/scene_input_driver.cpp)
    endif()
    # This guest can use a synthetic fixture produced on another machine. Register the automated test
    # if the tools to generate the fixture are available locally.
    if(CMAKE_HOST_WIN32 AND NOT CMAKE_CROSSCOMPILING AND TARGET d3d12_translated_draw_test AND TARGET gta6rt)
      add_dependencies(tiny_guest_draw d3d12_translated_draw_test gta6rt)
      add_test(NAME d3d12_translated_draw_guest
               COMMAND ${CMAKE_COMMAND} -DGTA6RT=$<TARGET_FILE:gta6rt> -DGUEST=$<TARGET_FILE:tiny_guest_draw>
                       -DFIXTURE=${LEONIDA_M15_DIR} -P ${CMAKE_CURRENT_SOURCE_DIR}/test/run_guest_draw.cmake)
      set_tests_properties(d3d12_translated_draw_guest PROPERTIES TIMEOUT 180)
    else()
      message(STATUS "tiny_guest_draw will build. For an external synthetic M1.5 fixture or Wine run see runtime/README.md.")
    endif()
    if(LEONIDA_GUEST_SCENE AND Python3_Interpreter_FOUND AND TARGET d3d12_translated_draw_test)
      set(_scene_wine_args)
      if(CMAKE_CROSSCOMPILING AND CMAKE_CROSSCOMPILING_EMULATOR)
        set(_scene_emulator ${CMAKE_CROSSCOMPILING_EMULATOR})
        list(POP_FRONT _scene_emulator _scene_launcher)
        list(APPEND _scene_wine_args "--wine=${_scene_launcher}")
        foreach(_arg IN LISTS _scene_emulator)
          list(APPEND _scene_wine_args "--wine-arg=${_arg}")
        endforeach()
        add_dependencies(tiny_guest_draw d3d12_translated_draw_test gta6rt)
      endif()
      if((CMAKE_HOST_WIN32 AND NOT CMAKE_CROSSCOMPILING) OR _scene_wine_args)
        add_test(NAME d3d12_guest_scene
                 COMMAND "${Python3_EXECUTABLE}" -I "${CMAKE_CURRENT_SOURCE_DIR}/../scripts/run_guest_scene.py"
                         --loader $<TARGET_FILE:gta6rt> --guest $<TARGET_FILE:tiny_guest_draw>
                         --shaders "${LEONIDA_M15_DIR}" --negative-controls ${_scene_wine_args})
        set_tests_properties(d3d12_guest_scene PROPERTIES TIMEOUT 900)
      endif()
    endif()
  endif()
  # bvh_builder_test can put the package's XboxBvhBuilder on this device too (LEONIDA_BVH_DEVICE=vulkan).
  if(TARGET bvh_builder_test)
    target_link_libraries(bvh_builder_test PRIVATE gta6rt_d3d12_com)
    target_compile_definitions(bvh_builder_test PRIVATE LEONIDA_VULKAN_DEVICE)
  endif()
  # fsr_dispatch_test can put the package's FidelityFX DLL on this device too (LEONIDA_FSR_DEVICE=vulkan).
  if(TARGET fsr_dispatch_test)
    target_link_libraries(fsr_dispatch_test PRIVATE gta6rt_d3d12_com)
    target_compile_definitions(fsr_dispatch_test PRIVATE LEONIDA_VULKAN_DEVICE)
  endif()
elseif(TARGET gta6rt)
  message(STATUS "Python 3 or d3d12.h missing: the D3D12 COM objects and d3d12_com_test are not built")
endif()
