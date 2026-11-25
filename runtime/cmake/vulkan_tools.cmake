# The standalone Vulkan tools (vk_harness, vk_pipeline_check, vk_sandbox and the others of the loop below) and the
# Vulkan tests that do not use the D3D12 COM objects.
# Included by runtime/CMakeLists.txt inside if(TARGET Vulkan::Headers).

foreach(tool vk_harness vk_ps_sweep vk_texture_test vk_sampler_test vk_compute_test vk_store_test vk_pipeline_check vk_command_replay_test
        vk_bindless_test vk_image_fuzz vk_descriptor_bench depth24_convert_test vk_predicate_capture_test vk_predicated_copy_test
        vk_xdxr_build_test vk_queue_test vk_sandbox)
  add_executable(${tool} test/${tool}.cpp)
  target_link_libraries(${tool} PRIVATE Vulkan::Headers ${CMAKE_DL_LIBS})
  if(WIN32)
    target_compile_definitions(${tool} PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  endif()
endforeach()
# OpFmaKHR width gate of vk_shader_fma.h (shaderFmaFloat32 / shaderFmaFloat64): no Vulkan instance, no GPU.
add_executable(vk_shader_fma_test test/vk_shader_fma_test.cpp)
target_link_libraries(vk_shader_fma_test PRIVATE Vulkan::Headers)
add_test(NAME vk_shader_fma COMMAND vk_shader_fma_test)
# LEONIDA_VK_DEVICE names the GPU in every harness (docs/testing.md, "Choosing the GPU"): a filter that matches no
# device fails the run in vk_descriptor_bench and vk_sandbox too, instead of testing another GPU (TEST-1141).
find_package(Python3 COMPONENTS Interpreter QUIET)
if(Python3_FOUND)
  add_test(NAME vk_device_filter_tools COMMAND "${Python3_EXECUTABLE}" -I
           "${CMAKE_CURRENT_SOURCE_DIR}/test/check_device_filter_tools.py" "$<TARGET_FILE:vk_descriptor_bench>"
           "$<TARGET_FILE:vk_sandbox>" "${CMAKE_CURRENT_BINARY_DIR}/vk_device_filter_tools")
  set_tests_properties(vk_device_filter_tools PROPERTIES SKIP_RETURN_CODE 77)
endif()
if(MSVC)
  # Keep the checker and its worker threads on the toolchain's C++ runtime under Wine.
  set_property(TARGET vk_pipeline_check PROPERTY
    MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()
# BUILD-1457: a driver compiles on the thread that creates the pipeline, and its compiler can recurse with the
# shader's nesting. On Windows a thread that asks for no size gets the reserve in the PE header, 1 MB by default:
# the main thread and every std::thread worker of the checker. AMD's Windows compiler (26.11.2) overflows that
# on 26 of the corpus's mesh shaders, and 2 MB is still too little for compute shaders nested deeper than 16
# (docs/pipeline_check.md, "Stack reserve"). Keep the number in step with scripts/build_runtime.ps1.
set(LEONIDA_PIPELINE_CHECK_STACK 8388608)
if(WIN32)
  if(MSVC)
    target_link_options(vk_pipeline_check PRIVATE /STACK:${LEONIDA_PIPELINE_CHECK_STACK})
  else()
    target_link_options(vk_pipeline_check PRIVATE -Wl,--stack,${LEONIDA_PIPELINE_CHECK_STACK})
  endif()
endif()
if(BUILD_TESTING)
  if(WIN32 AND LEONIDA_BUILD_WINDOWS_RUNTIME)
    # Real Win32 environment and DXGI names, with D3D12 device creation stubbed: no GPU commands or game files.
    # It includes the runtime's D3D12 shim headers, so it needs the same Windows SDK as the runtime.
    add_executable(host_adapter_test test/host_adapter_test.cpp)
    target_link_libraries(host_adapter_test PRIVATE Vulkan::Headers dxgi)
    target_compile_definitions(host_adapter_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
    if(MSVC)
      target_compile_options(host_adapter_test PRIVATE /W4 /permissive- /EHsc /utf-8)
    endif()
    add_test(NAME host_adapter COMMAND host_adapter_test)
  endif()
  add_test(NAME vk_pipeline_check_cli COMMAND "${CMAKE_COMMAND}"
           "-DTOOL=$<TARGET_FILE:vk_pipeline_check>"
           "-DTEST_DIR=${CMAKE_CURRENT_BINARY_DIR}/vk_pipeline_check_cli_input"
           "-DRUNNER=${CMAKE_CROSSCOMPILING_EMULATOR}"
           -P "${CMAKE_CURRENT_SOURCE_DIR}/test/check_vk_pipeline_cli.cmake")
  add_test(NAME vk_texture_cube_alpha COMMAND vk_texture_test --self-test-cube-alpha)
  if(WIN32)
    # Reads SizeOfStackReserve from the built file; the program is not run, so it needs no emulator.
    add_test(NAME vk_pipeline_check_stack COMMAND "${CMAKE_COMMAND}"
             "-DTOOL=$<TARGET_FILE:vk_pipeline_check>"
             "-DWANT=${LEONIDA_PIPELINE_CHECK_STACK}"
             -P "${CMAKE_CURRENT_SOURCE_DIR}/test/check_stack_reserve.cmake")
  endif()
  add_test(NAME depth24_convert COMMAND depth24_convert_test)
  set_tests_properties(depth24_convert PROPERTIES SKIP_RETURN_CODE 77)
  # Self-checking Vulkan tests with no shaders or game data; each exits 77 without a Vulkan device (TEST-514).
  foreach(test vk_command_replay vk_predicated_copy vk_predicate_capture vk_queue)
    add_test(NAME ${test} COMMAND ${test}_test)
    set_tests_properties(${test} PROPERTIES SKIP_RETURN_CODE 77)
  endforeach()
  # The XDXR BVH builder: the GPU writes every case, then tools/xdxr_bvh.py validates and traces them.
  set(LEONIDA_XDXR_OUT "${CMAKE_CURRENT_BINARY_DIR}/xdxr_build_cases")
  file(MAKE_DIRECTORY "${LEONIDA_XDXR_OUT}")
  add_test(NAME xdxr_build COMMAND vk_xdxr_build_test "${LEONIDA_XDXR_OUT}")
  set_tests_properties(xdxr_build PROPERTIES SKIP_RETURN_CODE 77 FIXTURES_SETUP xdxr_build_cases)
  find_package(Python3 COMPONENTS Interpreter QUIET)
  if(Python3_FOUND)
    add_test(NAME xdxr_build_check COMMAND "${Python3_EXECUTABLE}" -I
             "${CMAKE_CURRENT_SOURCE_DIR}/../tools/xdxr_bvh.py" check-build "${LEONIDA_XDXR_OUT}" --rays 1000)
    set_tests_properties(xdxr_build_check PROPERTIES FIXTURES_REQUIRED xdxr_build_cases SKIP_RETURN_CODE 77)
  endif()
endif()
# VulkanQueue/VulkanContext query-state synchronization (remove_query_pool vs commit, cross-queue plan/commit)
# and pending Wait() preservation across transient vkQueueSubmit failures.
add_executable(vk_queue_query_sync_test test/vk_queue_query_sync_test.cpp)
target_link_libraries(vk_queue_query_sync_test PRIVATE Vulkan::Headers ${CMAKE_DL_LIBS})
if(WIN32)
  target_compile_definitions(vk_queue_query_sync_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
else()
  find_package(Threads REQUIRED)
  target_link_libraries(vk_queue_query_sync_test PRIVATE Threads::Threads)
endif()
if(MSVC)
  target_compile_options(vk_queue_query_sync_test PRIVATE /W4 /permissive- /utf-8)
endif()
if(BUILD_TESTING)
  add_test(NAME vk_queue_query_sync COMMAND vk_queue_query_sync_test)
  set_tests_properties(vk_queue_query_sync PROPERTIES SKIP_RETURN_CODE 77)
endif()
# With LEONIDA_VK_VALIDATION=1: synchronization validation reports a missing barrier (and not a present one), so
# the other GPU tests' "0 validation errors" was checked by an active layer. 77 without validation or a device.
add_executable(vk_sync_validation_selftest test/vk_sync_validation_selftest.cpp)
target_link_libraries(vk_sync_validation_selftest PRIVATE Vulkan::Headers ${CMAKE_DL_LIBS})
if(WIN32)
  target_compile_definitions(vk_sync_validation_selftest PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
endif()
if(MSVC)
  target_compile_options(vk_sync_validation_selftest PRIVATE /W4 /permissive- /utf-8)
endif()
if(BUILD_TESTING)
  add_test(NAME vk_sync_validation COMMAND vk_sync_validation_selftest)
  set_tests_properties(vk_sync_validation PROPERTIES SKIP_RETURN_CODE 77)
endif()
if(NOT Vulkan_GLSLANG_VALIDATOR_EXECUTABLE)
  find_program(Vulkan_GLSLANG_VALIDATOR_EXECUTABLE glslangValidator HINTS "$ENV{VULKAN_SDK}/Bin" "$ENV{VULKAN_SDK}/bin")
endif()
if(Vulkan_GLSLANG_VALIDATOR_EXECUTABLE)
  add_executable(vk_overlapping_occlusion_test test/vk_overlapping_occlusion_test.cpp)
  target_link_libraries(vk_overlapping_occlusion_test PRIVATE Vulkan::Headers ${CMAKE_DL_LIBS})
  if(WIN32)
    target_compile_definitions(vk_overlapping_occlusion_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  endif()
  foreach(stage vert frag)
    set(source "${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/overlapping_occlusion.${stage}")
    set(output "${CMAKE_CURRENT_BINARY_DIR}/overlapping_occlusion.${stage}.spv")
    add_custom_command(OUTPUT "${output}"
                       COMMAND "${Vulkan_GLSLANG_VALIDATOR_EXECUTABLE}" -V --target-env vulkan1.0
                               -o "${output}" "${source}"
                       DEPENDS "${source}" VERBATIM)
    target_sources(vk_overlapping_occlusion_test PRIVATE "${output}")
  endforeach()
  if(BUILD_TESTING)
    add_test(NAME vk_overlapping_occlusion COMMAND vk_overlapping_occlusion_test
             "${CMAKE_CURRENT_BINARY_DIR}/overlapping_occlusion.vert.spv"
             "${CMAKE_CURRENT_BINARY_DIR}/overlapping_occlusion.frag.spv")
    # The same test as a device without pipelineStatisticsQuery runs it (MoltenVK), on whatever device is here.
    add_test(NAME vk_overlapping_occlusion_no_statistics COMMAND vk_overlapping_occlusion_test
             "${CMAKE_CURRENT_BINARY_DIR}/overlapping_occlusion.vert.spv"
             "${CMAKE_CURRENT_BINARY_DIR}/overlapping_occlusion.frag.spv" --no-statistics)
    set_tests_properties(vk_overlapping_occlusion vk_overlapping_occlusion_no_statistics
                         PROPERTIES SKIP_RETURN_CODE 77)
  endif()
endif()
# CPU-only: the ranking that makes these harnesses prefer a native ICD over Mesa's Dozen (#915). No GPU needed.
add_executable(vk_device_pick_test test/vk_device_pick_test.cpp)
target_link_libraries(vk_device_pick_test PRIVATE Vulkan::Headers)
if(BUILD_TESTING)
  add_test(NAME vk_device_pick COMMAND vk_device_pick_test)
endif()
# Committed BC* texture zero-initialization via vk.zero_buffer or vk.copy_scratch (D3D-220).
add_executable(vk_bc_zero_init_test test/vk_bc_zero_init_test.cpp)
target_link_libraries(vk_bc_zero_init_test PRIVATE Vulkan::Headers ${CMAKE_DL_LIBS})
if(WIN32)
  target_compile_definitions(vk_bc_zero_init_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
endif()
if(MSVC)
  target_compile_options(vk_bc_zero_init_test PRIVATE /W4 /permissive- /utf-8)
endif()
if(BUILD_TESTING)
  add_test(NAME vk_bc_zero_init COMMAND vk_bc_zero_init_test)
  set_tests_properties(vk_bc_zero_init PROPERTIES SKIP_RETURN_CODE 77)
endif()
# FenceWaitDispatcher concurrency and device-lost regressions (re-entrant callbacks, wakeup on device lost, counter error drain).
add_executable(vk_fence_dispatcher_sync_test test/vk_fence_dispatcher_sync_test.cpp)
target_link_libraries(vk_fence_dispatcher_sync_test PRIVATE Vulkan::Headers ${CMAKE_DL_LIBS})
if(WIN32)
  target_compile_definitions(vk_fence_dispatcher_sync_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
else()
  find_package(Threads REQUIRED)
  target_link_libraries(vk_fence_dispatcher_sync_test PRIVATE Threads::Threads)
endif()
if(MSVC)
  target_compile_options(vk_fence_dispatcher_sync_test PRIVATE /W4 /permissive- /utf-8)
endif()
if(BUILD_TESTING)
  add_test(NAME vk_fence_dispatcher_sync COMMAND vk_fence_dispatcher_sync_test)
  set_tests_properties(vk_fence_dispatcher_sync PROPERTIES SKIP_RETURN_CODE 77)
endif()
# CPU-only: the bindless set's array sizes from synthetic device limits.
add_executable(bindless_sizing_test test/bindless_sizing_test.cpp)
target_link_libraries(bindless_sizing_test PRIVATE Vulkan::Headers)
if(BUILD_TESTING)
  add_test(NAME bindless_sizing COMMAND bindless_sizing_test)
endif()
# CPU-only: a mesh PSO's output, workgroup and shared-memory needs against synthetic device limits (vulkan_mesh_limits.h).
add_executable(vulkan_mesh_limits_test test/vulkan_mesh_limits_test.cpp)
target_link_libraries(vulkan_mesh_limits_test PRIVATE Vulkan::Headers)
if(BUILD_TESTING)
  add_test(NAME vulkan_mesh_limits COMMAND vulkan_mesh_limits_test)
endif()
# CPU-only: Vulkan 1.3 core vs 1.2 KHR/EXT feature probing and proc fallback (runtime/src/vulkan13_features.h).
add_executable(vulkan13_features_test test/vulkan13_features_test.cpp)
target_link_libraries(vulkan13_features_test PRIVATE Vulkan::Headers)
if(MSVC)
  target_compile_options(vulkan13_features_test PRIVATE /W4 /permissive- /utf-8)
endif()
if(BUILD_TESTING)
  add_test(NAME vulkan13_features COMMAND vulkan13_features_test)
endif()
# Buffer registrations keep their binding, VA lookup, and sparse owner in step on host allocation failure.
add_executable(vk_buffer_registration_oom_test test/vk_buffer_registration_oom_test.cpp)
target_link_libraries(vk_buffer_registration_oom_test PRIVATE Vulkan::Headers ${CMAKE_DL_LIBS})
if(WIN32)
  target_compile_definitions(vk_buffer_registration_oom_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  if(MSVC)
    target_compile_options(vk_buffer_registration_oom_test PRIVATE /W4 /permissive- /EHsc /utf-8)
  endif()
endif()
if(BUILD_TESTING)
  add_test(NAME vk_buffer_registration_oom COMMAND vk_buffer_registration_oom_test)
endif()
# CPU-only: ScratchBuffers chunk alignment, retire/collect/forget, and spare cap (runtime/src/vulkan_scratch.h).
add_executable(vulkan_scratch_test test/vulkan_scratch_test.cpp)
target_link_libraries(vulkan_scratch_test PRIVATE Vulkan::Headers)
if(MSVC)
  target_compile_options(vulkan_scratch_test PRIVATE /W4 /permissive- /utf-8)
endif()
if(BUILD_TESTING)
  add_test(NAME vulkan_scratch COMMAND vulkan_scratch_test)
endif()
if(WIN32 AND BUILD_TESTING)
  # VulkanPresenter tracker lock / failed-submit rollback and capture-buffer WAW synchronization.
  add_executable(vk_presenter_sync_test test/vk_presenter_sync_test.cpp)
  target_link_libraries(vk_presenter_sync_test PRIVATE Vulkan::Headers user32)
  target_compile_definitions(vk_presenter_sync_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  if(MSVC)
    target_compile_options(vk_presenter_sync_test PRIVATE /W4 /permissive- /utf-8)
  endif()
  add_test(NAME vk_presenter_sync COMMAND vk_presenter_sync_test)
  set_tests_properties(vk_presenter_sync PROPERTIES SKIP_RETURN_CODE 77)
endif()
if(NOT Vulkan_GLSLANG_VALIDATOR_EXECUTABLE)
  find_program(Vulkan_GLSLANG_VALIDATOR_EXECUTABLE glslangValidator HINTS "$ENV{VULKAN_SDK}/Bin" "$ENV{VULKAN_SDK}/bin")
endif()
if(Vulkan_GLSLANG_VALIDATOR_EXECUTABLE)
  add_executable(vk_binary_occlusion_test test/vk_binary_occlusion_test.cpp)
  target_link_libraries(vk_binary_occlusion_test PRIVATE Vulkan::Headers ${CMAKE_DL_LIBS})
  if(WIN32)
    target_compile_definitions(vk_binary_occlusion_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  endif()
  foreach(stage vert frag)
    set(source "${CMAKE_CURRENT_SOURCE_DIR}/test/glsl/binary_occlusion.${stage}")
    set(output "${CMAKE_CURRENT_BINARY_DIR}/binary_occlusion.${stage}.spv")
    add_custom_command(OUTPUT "${output}"
                       COMMAND "${Vulkan_GLSLANG_VALIDATOR_EXECUTABLE}" -V --target-env vulkan1.0
                               -o "${output}" "${source}"
                       DEPENDS "${source}" VERBATIM)
    target_sources(vk_binary_occlusion_test PRIVATE "${output}")
  endforeach()
  if(BUILD_TESTING)
    add_test(NAME vk_binary_occlusion COMMAND vk_binary_occlusion_test
             "${CMAKE_CURRENT_BINARY_DIR}/binary_occlusion.vert.spv"
             "${CMAKE_CURRENT_BINARY_DIR}/binary_occlusion.frag.spv")
    set_tests_properties(vk_binary_occlusion PROPERTIES SKIP_RETURN_CODE 77)
  endif()
endif()
