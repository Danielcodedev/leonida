# Tests that need no Vulkan headers: the CPU-only test programs, the stand-in titles and DLLs (tiny_*) that gta6rt
# maps, and the add_test() calls for the shim test programs of windows_runtime.cmake.
# Included by runtime/CMakeLists.txt inside if(BUILD_TESTING).

add_executable(gfx10_tiling_test test/gfx10_tiling_test.cpp)
add_test(NAME gfx10_tiling COMMAND gfx10_tiling_test)

add_executable(retire_tickets_test test/retire_tickets_test.cpp)
add_test(NAME retire_tickets COMMAND retire_tickets_test)
# VulkanContext::buffer_at's VA index (runtime/src/buffer_va_index.h): pure stdlib, no Vulkan instance.
add_executable(buffer_va_index_test test/buffer_va_index_test.cpp)
add_test(NAME buffer_va_index COMMAND buffer_va_index_test)

add_executable(xbox_present_readback_size_test test/xbox_present_readback_size_test.cpp)
add_test(NAME xbox_present_readback_size COMMAND xbox_present_readback_size_test)

add_executable(pipeline_cache_file_test test/pipeline_cache_file_test.cpp)
add_test(NAME pipeline_cache_file COMMAND pipeline_cache_file_test)

add_executable(xdxr_build_output_test test/xdxr_build_output_test.cpp)
add_test(NAME xdxr_build_output COMMAND xdxr_build_output_test)

# vk_pipeline_check's memory budget for large modules: pure stdlib, no Vulkan device.
add_executable(large_module_gate_test test/large_module_gate_test.cpp)
find_package(Threads REQUIRED)
target_link_libraries(large_module_gate_test PRIVATE Threads::Threads)
add_test(NAME large_module_gate COMMAND large_module_gate_test)
# vk_pipeline_check's isolate summary stage set: pure stdlib, no Vulkan device.
add_executable(pipeline_summary_test test/pipeline_summary_test.cpp)
add_test(NAME pipeline_summary COMMAND pipeline_summary_test)
# XDXR build descriptions (docs/xdxr.md); compared with d3d12.h where the Windows SDK provides it.
add_executable(xdxr_descs_test test/xdxr_descs_test.cpp)
add_test(NAME xdxr_descs COMMAND xdxr_descs_test)
# LEONIDA_VK_DEVICE name matching (runtime/src/vulkan_device_filter.h): pure stdlib, no Vulkan instance.
add_executable(vulkan_device_filter_test test/vulkan_device_filter_test.cpp)
target_include_directories(vulkan_device_filter_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
add_test(NAME vulkan_device_filter COMMAND vulkan_device_filter_test)
add_executable(vk_presenter_capture_colour_test test/vk_presenter_capture_colour_test.cpp)
add_test(NAME vk_presenter_capture_colour COMMAND vk_presenter_capture_colour_test)
if(TARGET gta6rt)
  if(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
    add_executable(cpp_unwind_test test/cpp_unwind_test.cpp)
    add_test(NAME cpp_unwind COMMAND cpp_unwind_test)
  endif()

  # Compile-time ABI checks (D3D12/XMem structure sizes, alignments and member offsets against the Windows SDK).
  # The file existed but no target built it, so none of its static_asserts ever ran.
  add_executable(runtime_types_test test/test_runtime_types.cpp)
  target_include_directories(runtime_types_test PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src ${CMAKE_CURRENT_SOURCE_DIR}/shims)
  add_test(NAME runtime_types COMMAND runtime_types_test)

  # Loader tests. They build their own PE images, so they need neither the game nor any other input.
  add_executable(loader_test
    test/loader_test.cpp
    src/pe_loader.cpp
    shims/registry.cpp
  )
  target_compile_definitions(loader_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE)
  target_compile_options(loader_test PRIVATE /W4 /permissive- /utf-8 /EHsc)
  target_link_options(loader_test PRIVATE /OPT:NOREF ${GTA6RT_HOST_BASE})
  add_dependencies(loader_test gta6rt_tls_host)
  add_test(NAME loader COMMAND loader_test)
  # PE loader tests use two locally built fixtures: a DLL with exports, imports and relocations, and an EXE that
  # imports it so Loader::load exercises recursive module loading. They contain no game data.
  set(TINY_FIXTURE_DIR "${CMAKE_CURRENT_BINARY_DIR}/fixtures/$<CONFIG>")

  add_library(tiny_dll SHARED test/fixtures/tiny_dll.cpp)
  target_compile_definitions(tiny_dll PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(tiny_dll PRIVATE /W4 /permissive- /utf-8 /GS-)
  # tiny_fault_caught faults inside its own __try. MSVC always catches that; clang-cl only with asynchronous
  # exceptions, otherwise the access violation escapes and the unwind-registration check fails.
  target_compile_options(tiny_dll PRIVATE $<$<CXX_COMPILER_ID:Clang>:/EHa>)
  set_target_properties(tiny_dll PROPERTIES
    OUTPUT_NAME tiny_dll
    PREFIX ""
    RUNTIME_OUTPUT_DIRECTORY "${TINY_FIXTURE_DIR}"
    ARCHIVE_OUTPUT_DIRECTORY "${TINY_FIXTURE_DIR}"
    MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>"
  )

  add_executable(tiny_exe test/fixtures/tiny_exe.cpp)
  target_link_libraries(tiny_exe PRIVATE tiny_dll)
  target_compile_definitions(tiny_exe PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(tiny_exe PRIVATE /W4 /permissive- /utf-8 /GS-)
  set_target_properties(tiny_exe PROPERTIES
    OUTPUT_NAME tiny_exe
    RUNTIME_OUTPUT_DIRECTORY "${TINY_FIXTURE_DIR}"
    MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>"
  )

  # An EXE built with /GA reads its TLS at index 0 without _tls_index; loader_tls_test maps it and reads it from
  # threads that existed before load() and from ones that did not.
  add_executable(tiny_ga_tls test/fixtures/tiny_ga_tls.cpp)
  target_compile_definitions(tiny_ga_tls PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(tiny_ga_tls PRIVATE /W4 /permissive- /utf-8 /GS- /GA)
  set_target_properties(tiny_ga_tls PROPERTIES
    OUTPUT_NAME tiny_ga_tls
    RUNTIME_OUTPUT_DIRECTORY "${TINY_FIXTURE_DIR}"
    MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>"
  )

  add_executable(module_names_test test/module_names_test.cpp src/pe_loader.cpp shims/registry.cpp)
  target_include_directories(module_names_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
  target_compile_definitions(module_names_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(module_names_test PRIVATE /W4 /permissive- /utf-8 /EHsc)
  target_link_options(module_names_test PRIVATE /OPT:NOREF)
  add_dependencies(module_names_test gta6rt_tls_host tiny_dll)
  add_test(NAME module_names COMMAND module_names_test "$<TARGET_FILE:tiny_dll>")

  add_executable(tiny_module_names test/fixtures/tiny_module_names.cpp)
  target_compile_definitions(tiny_module_names PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(tiny_module_names PRIVATE /W4 /permissive- /utf-8 /EHsc)
  set_target_properties(tiny_module_names PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${TINY_FIXTURE_DIR}")

  # Native Windows and --dry-run/--init/--run share original renamed fixtures, including an ACP-named import.
  if(NOT CMAKE_CROSSCOMPILING)
    find_package(Python3 COMPONENTS Interpreter QUIET)
    if(Python3_FOUND)
      add_test(NAME run_module_names COMMAND "${Python3_EXECUTABLE}" -I
        "${CMAKE_CURRENT_SOURCE_DIR}/test/check_module_names.py"
        "--loader=$<TARGET_FILE:gta6rt>" "--guest=$<TARGET_FILE:tiny_module_names>"
        "--importer=$<TARGET_FILE:tiny_exe>" "--dependency=$<TARGET_FILE:tiny_dll>"
        "--work-dir=${CMAKE_CURRENT_BINARY_DIR}"
        "--report=${CMAKE_CURRENT_BINARY_DIR}/module-names-results.json")
      set_tests_properties(run_module_names PROPERTIES TIMEOUT 90)
    endif()
  endif()

  # pe_loader.cpp needs the shim registry for shims::find/make_unimplemented_thunk. The xmem and d3d12_xs tables
  # are linked too so the optional LEONIDA_GAME_DIR run classifies the shipped modules' imports exactly like
  # gta6rt does (no d3d12.lib is needed: d3d12_xs resolves its host entry points at run time).
  add_executable(pe_loader_test
    test/pe_loader_test.cpp
    src/pe_loader.cpp
    shims/registry.cpp
    shims/xmem.cpp
    shims/d3d12_xs.cpp
    shims/d3d12_xs_device.cpp
  )
  target_include_directories(pe_loader_test PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/shims
  )
  target_compile_definitions(pe_loader_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(pe_loader_test PRIVATE /W4 /permissive- /utf-8 /EHsc)
  target_link_options(pe_loader_test PRIVATE /OPT:NOREF)
  target_link_libraries(pe_loader_test PRIVATE gta6rt_d3d12_xs_rootsig psapi)
  add_dependencies(pe_loader_test tiny_dll tiny_exe gta6rt_tls_host)

  # `gta6rt --run` rehearsal: a stand-in game EXE (CRT startup, statics, heap, files, threads) that imports
  # xgameruntime.dll from a link-time stub; under --run the shim registry answers those imports instead.
  add_library(xgameruntime_stub SHARED test/fixtures/xgameruntime_stub.cpp test/fixtures/xgameruntime_stub.def)
  target_include_directories(xgameruntime_stub PUBLIC ${XTASKQUEUE_DIR}/Include)
  target_compile_definitions(xgameruntime_stub PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  set_target_properties(xgameruntime_stub PROPERTIES
    OUTPUT_NAME xgameruntime
    PREFIX ""
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/fixtures/game/$<CONFIG>"
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/fixtures/game/$<CONFIG>"
  )
  add_executable(tiny_async test/fixtures/tiny_async.cpp)
  target_link_libraries(tiny_async PRIVATE xgameruntime_stub)
  set_target_properties(tiny_async PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/fixtures/game/$<CONFIG>"
  )
  # Reaches xgameruntime.dll through LoadLibraryW/GetProcAddress, as xgameruntime.lib's thunks do (no import).
  add_executable(tiny_gdk_load test/fixtures/tiny_gdk_load.cpp)
  target_compile_definitions(tiny_gdk_load PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(tiny_gdk_load PRIVATE /W4 /permissive- /utf-8)
  set_target_properties(tiny_gdk_load PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/fixtures/game/$<CONFIG>"
  )
  # Run-time LoadLibrary of a bundled Xbox DLL (importing xmem.dll) through rt::Loader.
  add_library(xmem_stub SHARED test/fixtures/xmem_stub.cpp test/fixtures/xmem_stub.def)
  target_compile_definitions(xmem_stub PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(xmem_stub PRIVATE /W4 /permissive- /utf-8)
  set_target_properties(xmem_stub PROPERTIES
    OUTPUT_NAME xmem
    PREFIX ""
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/fixtures/stubs/$<CONFIG>"
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/fixtures/stubs/$<CONFIG>"
  )
  add_library(tiny_bundled_dll SHARED test/fixtures/tiny_bundled_dll.cpp test/fixtures/tiny_bundled_dll.def)
  target_link_libraries(tiny_bundled_dll PRIVATE xmem_stub)
  target_compile_definitions(tiny_bundled_dll PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(tiny_bundled_dll PRIVATE /W4 /permissive- /utf-8)
  set_target_properties(tiny_bundled_dll PROPERTIES
    OUTPUT_NAME tiny_bundled_dll
    PREFIX ""
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/fixtures/game/$<CONFIG>"
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/fixtures/stubs/$<CONFIG>"
  )
  add_executable(tiny_bundled_load test/fixtures/tiny_bundled_load.cpp)
  target_compile_definitions(tiny_bundled_load PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(tiny_bundled_load PRIVATE /W4 /permissive- /utf-8)
  add_dependencies(tiny_bundled_load tiny_bundled_dll)
  set_target_properties(tiny_bundled_load PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/fixtures/game/$<CONFIG>"
  )
  add_library(tiny_startup_cmdline_dll SHARED test/fixtures/tiny_startup_cmdline.cpp)
  target_compile_definitions(tiny_startup_cmdline_dll PRIVATE STARTUP_CMDLINE_DLL)
  add_executable(tiny_startup_cmdline test/fixtures/tiny_startup_cmdline.cpp)
  target_link_libraries(tiny_startup_cmdline PRIVATE tiny_startup_cmdline_dll)
  foreach(target tiny_startup_cmdline_dll tiny_startup_cmdline)
    target_compile_definitions(${target} PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
    target_compile_options(${target} PRIVATE /W4 /permissive- /utf-8)
    set_target_properties(${target} PROPERTIES
      PREFIX ""
      RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/fixtures/game/$<CONFIG>"
    )
  endforeach()
  # These linker-selected startup modes are specific to the MSVC CRT.
  if(MSVC)
    foreach(width a w)
      foreach(mode default expand noargs)
        set(target tiny_argv_${mode}_${width})
        add_executable(${target} test/fixtures/tiny_argv_modes.cpp)
        target_compile_definitions(${target} PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
        target_compile_options(${target} PRIVATE /W4 /permissive- /utf-8)
        if(width STREQUAL "w")
          target_compile_definitions(${target} PRIVATE APP_WIDE)
        endif()
        if(mode STREQUAL "expand")
          if(width STREQUAL "w")
            target_link_options(${target} PRIVATE wsetargv.obj)
          else()
            target_link_options(${target} PRIVATE setargv.obj)
          endif()
        elseif(mode STREQUAL "noargs")
          target_link_options(${target} PRIVATE noarg.obj)
        endif()
        set_target_properties(${target} PROPERTIES
          RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/fixtures/game/$<CONFIG>")
      endforeach()
    endforeach()
  endif()
  add_executable(tiny_atexit test/fixtures/tiny_atexit.cpp)
  target_compile_definitions(tiny_atexit PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(tiny_atexit PRIVATE /W4 /permissive- /utf-8)
  set_target_properties(tiny_atexit PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/fixtures/game/$<CONFIG>"
  )
  add_executable(tiny_game test/fixtures/tiny_game.cpp)
  target_link_libraries(tiny_game PRIVATE xgameruntime_stub)
  target_compile_definitions(tiny_game PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX _CRT_SECURE_NO_WARNINGS)  # plain fopen, as games use
  target_compile_options(tiny_game PRIVATE /W4 /permissive- /utf-8 /EHsc)
  set_target_properties(tiny_game PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/fixtures/game/$<CONFIG>"
  )
  # The same game with no .reloc, at the default EXE base, as RT-22 asks about the real one: it can only run at
  # 0x140000000, which arm64 Wine on macOS uses for itself (src/base_reservation.h).
  add_executable(tiny_game_fixed test/fixtures/tiny_game.cpp)
  target_link_libraries(tiny_game_fixed PRIVATE xgameruntime_stub)
  target_compile_definitions(tiny_game_fixed PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX _CRT_SECURE_NO_WARNINGS)
  target_compile_options(tiny_game_fixed PRIVATE /W4 /permissive- /utf-8 /EHsc)
  target_link_options(tiny_game_fixed PRIVATE /FIXED /DYNAMICBASE:NO /BASE:0x140000000)
  set_target_properties(tiny_game_fixed PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/fixtures/game/$<CONFIG>"
  )
  add_executable(tiny_game_exit_code_test test/tiny_game_exit_code_test.cpp)
  target_compile_definitions(tiny_game_exit_code_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(tiny_game_exit_code_test PRIVATE /W4 /permissive- /utf-8)
  add_dependencies(tiny_game_exit_code_test gta6rt tiny_game tiny_game_fixed)
  # abort() must reach the guest's SIGABRT handler before the run ends with the CRT's abort code (3).
  add_executable(tiny_game_abort_test test/tiny_game_abort_test.cpp)
  target_compile_definitions(tiny_game_abort_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(tiny_game_abort_test PRIVATE /W4 /permissive- /utf-8)
  add_dependencies(tiny_game_abort_test gta6rt tiny_game)
  add_test(NAME pe_loader COMMAND pe_loader_test "$<TARGET_FILE:tiny_dll>" "$<TARGET_FILE:tiny_exe>")

  # Synthetic, hand-built images through Loader::load: range checks, wrapping RVAs, import-table termination and
  # base relocations (HIGHLOW included). No fixture DLL is needed; the images are written to a temporary folder.
  add_executable(test_pe_loader_bounds
    test/test_pe_loader_bounds.cpp
    src/pe_loader.cpp
    shims/registry.cpp
    shims/xmem.cpp
    shims/d3d12_xs.cpp
    shims/d3d12_xs_device.cpp
  )
  target_include_directories(test_pe_loader_bounds PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/shims
  )
  target_compile_definitions(test_pe_loader_bounds PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(test_pe_loader_bounds PRIVATE /W4 /permissive- /utf-8 /EHsc)
  target_link_options(test_pe_loader_bounds PRIVATE /OPT:NOREF ${GTA6RT_HOST_BASE})
  target_link_libraries(test_pe_loader_bounds PRIVATE gta6rt_d3d12_xs_rootsig psapi)
  add_dependencies(test_pe_loader_bounds gta6rt_tls_host)
  add_test(NAME pe_loader_bounds COMMAND test_pe_loader_bounds)

  # RT-388: a deterministic mutation fuzzer over synthetic images through Loader::load (test/pe_loader_fuzz.cpp).
  # ctest runs a fixed seed and case count; docs/testing.md has the long runs. With LEONIDA_LOADER_FUZZ_ASAN the
  # fuzzer and the loader sources it compiles are built with AddressSanitizer (use RelWithDebInfo or Release:
  # /fsanitize=address does not combine with the /RTC1 of a Debug build).
  option(LEONIDA_LOADER_FUZZ_ASAN "Build pe_loader_fuzz with AddressSanitizer" OFF)
  add_executable(pe_loader_fuzz
    test/pe_loader_fuzz.cpp
    src/pe_loader.cpp
    shims/registry.cpp
    shims/xmem.cpp
    shims/d3d12_xs.cpp
    shims/d3d12_xs_device.cpp
  )
  target_include_directories(pe_loader_fuzz PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/shims
  )
  target_compile_definitions(pe_loader_fuzz PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(pe_loader_fuzz PRIVATE /W4 /permissive- /utf-8 /EHsc)
  target_link_options(pe_loader_fuzz PRIVATE /OPT:NOREF ${GTA6RT_HOST_BASE})
  target_link_libraries(pe_loader_fuzz PRIVATE gta6rt_d3d12_xs_rootsig psapi)
  add_dependencies(pe_loader_fuzz gta6rt_tls_host)
  if(LEONIDA_LOADER_FUZZ_ASAN)
    target_compile_options(pe_loader_fuzz PRIVATE /fsanitize=address /Zi)
    target_link_options(pe_loader_fuzz PRIVATE /INCREMENTAL:NO /DEBUG)
    # No STL container annotations: they need stl_asan.lib from the VS component, and the libraries linked here
    # are built without ASan, so the annotate_string/annotate_vector /FAILIFMISMATCH keys must stay as theirs.
    target_compile_definitions(pe_loader_fuzz PRIVATE _DISABLE_STRING_ANNOTATION _DISABLE_VECTOR_ANNOTATION)
    # The ASan runtime: next to cl.exe for MSVC (the VS "C++ AddressSanitizer" component), under the resource
    # directory for clang-cl. Its objects name the runtime libraries; the folder goes on the library path, and the
    # DLL is copied beside the test so it runs without a Developer prompt or a PATH change.
    get_filename_component(_leonida_cc_dir "${CMAKE_CXX_COMPILER}" DIRECTORY)
    file(GLOB _leonida_asan_dll
      "${_leonida_cc_dir}/clang_rt.asan_dynamic-x86_64.dll"
      "${_leonida_cc_dir}/../lib/clang/*/lib/windows/clang_rt.asan_dynamic-x86_64.dll")
    if(_leonida_asan_dll)
      list(GET _leonida_asan_dll 0 _leonida_asan_dll)
      get_filename_component(_leonida_asan_dir "${_leonida_asan_dll}" DIRECTORY)
      target_link_directories(pe_loader_fuzz PRIVATE "${_leonida_asan_dir}")
      if(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
        # clang-cl 23's stack-use-after-return frames break MSVC C++ exception dispatch at /O2: a rethrow faults
        # in vcruntime's _C_specific_handler_noexcept (a five-line try/throw/catch does it). Without them it works.
        target_compile_options(pe_loader_fuzz PRIVATE -fsanitize-address-use-after-return=never)
        # clang-cl names these only when it runs the link itself; CMake calls the linker directly.
        target_link_options(pe_loader_fuzz PRIVATE clang_rt.asan_dynamic-x86_64.lib
                            /wholearchive:clang_rt.asan_dynamic_runtime_thunk-x86_64.lib)
      endif()
      add_custom_command(TARGET pe_loader_fuzz POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different "${_leonida_asan_dll}" "$<TARGET_FILE_DIR:pe_loader_fuzz>")
    else()
      message(WARNING "LEONIDA_LOADER_FUZZ_ASAN: no clang_rt.asan_dynamic-x86_64.dll beside ${CMAKE_CXX_COMPILER}")
    endif()
  endif()
  add_test(NAME pe_loader_fuzz COMMAND pe_loader_fuzz --quiet)

  # Static TLS fixture: a DLL with __declspec(thread) and a TLS callback. It is ordinary test code; no game data
  # is involved. loader_tls_test needs gta6rt_tls_host.dll next to its own EXE, because that is where
  # Loader::initialize_tls looks for the reserved module TLS index.
  add_library(tiny_tls SHARED test/fixtures/tiny_tls.cpp)
  target_compile_definitions(tiny_tls PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(tiny_tls PRIVATE /W4 /permissive- /utf-8 /GS-)
  set_target_properties(tiny_tls PROPERTIES
    OUTPUT_NAME tiny_tls
    PREFIX ""
    RUNTIME_OUTPUT_DIRECTORY "${TINY_FIXTURE_DIR}"
    ARCHIVE_OUTPUT_DIRECTORY "${TINY_FIXTURE_DIR}"
  )

  add_library(tiny_tls_cb_only SHARED test/fixtures/tiny_tls_cb_only.cpp)
  target_compile_definitions(tiny_tls_cb_only PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(tiny_tls_cb_only PRIVATE /W4 /permissive- /utf-8 /GS-)
  target_link_options(tiny_tls_cb_only PRIVATE /NODEFAULTLIB /ENTRY:DllMainCRTStartup)
  target_link_libraries(tiny_tls_cb_only PRIVATE kernel32)
  set_target_properties(tiny_tls_cb_only PROPERTIES
    OUTPUT_NAME tiny_tls_cb_only
    PREFIX ""
    RUNTIME_OUTPUT_DIRECTORY "${TINY_FIXTURE_DIR}"
    ARCHIVE_OUTPUT_DIRECTORY "${TINY_FIXTURE_DIR}"
  )

  # pe_loader.cpp needs the shim registry for shims::find/make_unimplemented_thunk. The fixtures import only host
  # DLLs, so no shim tables are linked.
  add_executable(loader_tls_test
    test/loader_tls_test.cpp
    src/pe_loader.cpp
    shims/registry.cpp
  )
  target_include_directories(loader_tls_test PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
  )
  target_compile_definitions(loader_tls_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(loader_tls_test PRIVATE /W4 /permissive- /utf-8 /EHsc)
  add_dependencies(loader_tls_test tiny_tls tiny_tls_cb_only tiny_ga_tls gta6rt_tls_host)
  add_test(NAME loader_tls
    COMMAND loader_tls_test "$<TARGET_FILE:tiny_tls>"
  )

  # DisableThreadLibraryCalls from a mapped DllMain (shims/library_loader.cpp). The fixture is built without the CRT, so
  # DllMain's only work is that one call. No game files.
  add_library(dll_thread_calls SHARED test/fixtures/dll_thread_calls.cpp)
  target_compile_options(dll_thread_calls PRIVATE /W4 /permissive- /utf-8 /GS-)
  target_link_options(dll_thread_calls PRIVATE /NODEFAULTLIB /ENTRY:dll_thread_calls_main)
  target_link_libraries(dll_thread_calls PRIVATE kernel32)
  set_target_properties(dll_thread_calls PROPERTIES
    OUTPUT_NAME dll_thread_calls
    PREFIX ""
    RUNTIME_OUTPUT_DIRECTORY "${TINY_FIXTURE_DIR}"
    ARCHIVE_OUTPUT_DIRECTORY "${TINY_FIXTURE_DIR}"
  )
  add_executable(dll_thread_calls_test
    test/dll_thread_calls_test.cpp
    src/pe_loader.cpp
    shims/library_loader.cpp
    shims/registry.cpp
    shims/xmem.cpp
  )
  target_include_directories(dll_thread_calls_test PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/shims
  )
  target_compile_definitions(dll_thread_calls_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(dll_thread_calls_test PRIVATE /W4 /permissive- /utf-8 /EHsc)
  target_link_options(dll_thread_calls_test PRIVATE /OPT:NOREF)
  target_link_libraries(dll_thread_calls_test PRIVATE psapi)
  add_dependencies(dll_thread_calls_test dll_thread_calls)
  add_test(NAME dll_thread_calls
    COMMAND dll_thread_calls_test "$<TARGET_FILE:dll_thread_calls>"
  )

  # The host GameInput path (docs/gameinput.md): mapped code that imports GameInputCreate from GameInput.dll, with no
  # GameInput shim linked. Needs the SDK's gameinput.lib and GameInput.h to build the fixture, and a GameInput.dll on
  # the machine to run (the test skips with 77 only when Windows cannot load GameInput.dll). No game files.
  find_library(GAMEINPUT_LIBRARY NAMES gameinput HINTS ${_sdk_lib_hints})
  if(GAMEINPUT_LIBRARY)
    add_library(gameinput_host SHARED test/fixtures/gameinput_host.cpp)
    target_compile_options(gameinput_host PRIVATE /W4 /permissive- /utf-8 /GS-)
    target_link_options(gameinput_host PRIVATE /NODEFAULTLIB /ENTRY:gameinput_host_main)
    target_link_libraries(gameinput_host PRIVATE kernel32 ${GAMEINPUT_LIBRARY})
    set_target_properties(gameinput_host PROPERTIES
      OUTPUT_NAME gameinput_host
      PREFIX ""
      RUNTIME_OUTPUT_DIRECTORY "${TINY_FIXTURE_DIR}"
      ARCHIVE_OUTPUT_DIRECTORY "${TINY_FIXTURE_DIR}"
    )
    add_executable(gameinput_host_test
      test/gameinput_host_test.cpp
      src/pe_loader.cpp
      shims/registry.cpp
    )
    target_include_directories(gameinput_host_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
    target_compile_definitions(gameinput_host_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
    target_compile_options(gameinput_host_test PRIVATE /W4 /permissive- /utf-8 /EHsc)
    add_dependencies(gameinput_host_test gameinput_host)
    add_test(NAME gameinput_host COMMAND gameinput_host_test "$<TARGET_FILE:gameinput_host>")
    set_tests_properties(gameinput_host PROPERTIES SKIP_RETURN_CODE 77)  # Windows cannot load GameInput.dll
  endif()

  # LEONIDA_UNIMPLEMENTED=log|fail|stop: builds its own image with two imports that bind to nothing, calls them in
  # process (log, fail) and in child processes (default/env parsing, stop). No game files, no GPU.
  add_executable(unimplemented_policy_test
    test/unimplemented_policy_test.cpp
    src/pe_loader.cpp
    shims/registry.cpp
  )
  # The register-preservation check needs a caller that sets rbx/rbp/rdi/rsi/r12-r15 and xmm6-15, which MSVC x64
  # cannot do inline: test/fixtures/abi_probe.asm (MASM). Without ml64 the rest of the test still runs.
  # Visual Studio locates cl.exe without adding its directory to PATH.
  # Keep looking for ml64 specifically so Ninja cannot select the 32-bit assembler.
  get_filename_component(_gta6rt_compiler_bin "${CMAKE_CXX_COMPILER}" DIRECTORY)
  find_program(LEONIDA_ML64 NAMES ml64 HINTS "${_gta6rt_compiler_bin}")
  if(LEONIDA_ML64)
    set(CMAKE_ASM_MASM_COMPILER "${LEONIDA_ML64}")
    enable_language(ASM_MASM)
    target_sources(unimplemented_policy_test PRIVATE test/fixtures/abi_probe.asm)
    target_compile_definitions(unimplemented_policy_test PRIVATE LEONIDA_HAVE_ABI_PROBE=1)
  else()
    message(STATUS "ml64 not found: unimplemented_policy_test skips the register-preservation check")
  endif()
  target_include_directories(unimplemented_policy_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
  target_compile_definitions(unimplemented_policy_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE _CRT_SECURE_NO_WARNINGS)
  target_compile_options(unimplemented_policy_test PRIVATE $<$<COMPILE_LANGUAGE:CXX>:/W4 /permissive- /utf-8 /EHsc>)
  target_link_options(unimplemented_policy_test PRIVATE /OPT:NOREF)
  add_dependencies(unimplemented_policy_test gta6rt_tls_host)
  add_test(NAME unimplemented_policy COMMAND unimplemented_policy_test)

  # gta6rt --trace FILE (shims/startup_trace.h): a synthetic image with an unimplemented import, an
  # OutputDebugStringA call and a read of address 0; checks the JSON lines. No game files, no GPU.
  add_executable(startup_trace_test
    test/startup_trace_test.cpp
    src/pe_loader.cpp
    shims/registry.cpp
  )
  target_include_directories(startup_trace_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
  target_compile_definitions(startup_trace_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE _CRT_SECURE_NO_WARNINGS)
  target_compile_options(startup_trace_test PRIVATE /W4 /permissive- /utf-8 /EHsc)
  target_link_options(startup_trace_test PRIVATE /OPT:NOREF)
  add_dependencies(startup_trace_test gta6rt_tls_host)
  add_test(NAME startup_trace COMMAND startup_trace_test)
endif()

if(TARGET device_proxy_test)
  add_test(NAME device_proxy COMMAND device_proxy_test)
  set_tests_properties(device_proxy PROPERTIES SKIP_RETURN_CODE 77)  # no WARP adapter (Wine)
  # With --trace-d3d12 the 24 D3D12XboxCreateDevice parameter words still print (docs/boot.md, question 1),
  # and the line with run-specific pointers does not.
  add_test(NAME device_proxy_trace COMMAND device_proxy_test --trace-d3d12)
  set_tests_properties(device_proxy_trace PROPERTIES SKIP_RETURN_CODE 77
      PASS_REGULAR_EXPRESSION "D3D12XboxCreateDevice params\\[24\\] =1234abcd"
      FAIL_REGULAR_EXPRESSION "FAIL;D3D12XboxCreateDevice adapter=")
endif()
if(TARGET xs_proxy_mock_test)
  add_test(NAME xs_proxy_mock COMMAND xs_proxy_mock_test)
  # The guard region's setup failing (one process each: the tables are built once per process).
  add_test(NAME xs_proxy_mock_no_reserve COMMAND xs_proxy_mock_test --fail-virtualalloc)
  add_test(NAME xs_proxy_mock_no_protect COMMAND xs_proxy_mock_test --fail-virtualprotect)
  add_test(NAME xs_proxy_mock_no_handler COMMAND xs_proxy_mock_test --fail-veh)
  # The routes are read once per process, so each override case is its own test.
  add_test(NAME xs_proxy_mock_env_slots COMMAND xs_proxy_mock_test --env-slots)
  add_test(NAME xs_proxy_mock_env_slots_invalid COMMAND xs_proxy_mock_test --env-slots-invalid)
  # PresentX on the queue: the slot is read once per process, so the named slot and the ignored value are two tests.
  add_test(NAME xs_proxy_mock_present_slot COMMAND xs_proxy_mock_test --present-slot)
  add_test(NAME xs_proxy_mock_present_slot_invalid COMMAND xs_proxy_mock_test --present-slot-invalid)
endif()
if(TARGET root_sig_test)
  add_test(NAME root_sig COMMAND root_sig_test)
endif()
add_executable(command_list_test test/command_list_test.cpp)
add_test(NAME command_list COMMAND command_list_test)
# Which SPIR-V modules declare a storage image or buffer they may write (src/spirv_stores.h), on hand-built words.
add_executable(spirv_stores_test test/spirv_stores_test.cpp)
add_test(NAME spirv_stores COMMAND spirv_stores_test)
add_executable(shader_fixture_path_test test/shader_fixture_path_test.cpp)
add_test(NAME shader_fixture_path COMMAND shader_fixture_path_test)
add_executable(resource_tiling_test test/resource_tiling_test.cpp)
add_test(NAME resource_tiling COMMAND resource_tiling_test)
add_executable(resource_detile_test test/resource_detile_test.cpp)
add_test(NAME resource_detile COMMAND resource_detile_test)
add_executable(descriptor_table_test test/descriptor_table_test.cpp)
add_test(NAME descriptor_table COMMAND descriptor_table_test)
add_executable(shader_library_test test/shader_library_test.cpp)
add_test(NAME shader_library COMMAND shader_library_test)
add_executable(spirv_f16_halves_test test/spirv_f16_halves_test.cpp)
add_test(NAME spirv_f16_halves COMMAND spirv_f16_halves_test)
# Optional: skips unless LEONIDA_SHADERS names a translated work folder (<work>/shaders/spirv).
add_executable(shader_library_corpus_test test/shader_library_corpus_test.cpp)
add_test(NAME shader_library_corpus COMMAND shader_library_corpus_test)
# Reads all 26,503 containers and modules: about 9 minutes from a hard disk.
set_tests_properties(shader_library_corpus PROPERTIES SKIP_RETURN_CODE 77 TIMEOUT 3600)
if(TARGET gta6rt)
  # Optional: skips unless LEONIDA_GAME_DIR and LEONIDA_MOVIE are set.
  add_executable(bink_decode_test
    test/bink_decode_test.cpp
    src/pe_loader.cpp
    shims/registry.cpp
    shims/xmem.cpp
  )
  target_compile_definitions(bink_decode_test PRIVATE
    WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE _CRT_SECURE_NO_WARNINGS)
  target_compile_options(bink_decode_test PRIVATE /W4 /permissive- /EHsc /utf-8)
  target_link_options(bink_decode_test PRIVATE /OPT:NOREF)
  target_link_libraries(bink_decode_test PRIVATE psapi)
  add_dependencies(bink_decode_test gta6rt_tls_host)
  add_test(NAME bink_decode COMMAND bink_decode_test)
  set_tests_properties(bink_decode PROPERTIES SKIP_RETURN_CODE 77)

  # Optional: skips unless LEONIDA_GAME_DIR and LEONIDA_BINK_INDEX are set. Measures the HBINK/BINKSUMMARY
  # offsets and the decode return values over every stream of movies.rpf (docs/movies.md section 5).
  add_executable(bink_abi_test
    test/bink_abi_test.cpp
    src/pe_loader.cpp
    shims/registry.cpp
    shims/xmem.cpp
  )
  target_compile_definitions(bink_abi_test PRIVATE
    WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE _CRT_SECURE_NO_WARNINGS)
  target_compile_options(bink_abi_test PRIVATE /W4 /permissive- /EHsc /utf-8)
  target_link_options(bink_abi_test PRIVATE /OPT:NOREF)
  target_link_libraries(bink_abi_test PRIVATE psapi)
  add_dependencies(bink_abi_test gta6rt_tls_host)
  add_test(NAME bink_abi COMMAND bink_abi_test)
  set_tests_properties(bink_abi PROPERTIES SKIP_RETURN_CODE 77 TIMEOUT 3600)

  # Optional local viewer: plays a .bk2 in a window through the package's Bink2Scarlett.dll (test/bink_play.cpp).
  # The CTest entry is the headless smoke run; it skips unless LEONIDA_GAME_DIR and LEONIDA_MOVIE are set.
  add_executable(bink_play
    test/bink_play.cpp
    src/pe_loader.cpp
    shims/registry.cpp
    shims/xmem.cpp
  )
  target_compile_definitions(bink_play PRIVATE
    WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE _CRT_SECURE_NO_WARNINGS)
  target_compile_options(bink_play PRIVATE /W4 /permissive- /EHsc /utf-8)
  target_link_options(bink_play PRIVATE /OPT:NOREF)
  target_link_libraries(bink_play PRIVATE psapi user32 gdi32)
  add_dependencies(bink_play gta6rt_tls_host)
  add_test(NAME bink_play_headless COMMAND bink_play --headless --frames 30)
  set_tests_properties(bink_play_headless PROPERTIES SKIP_RETURN_CODE 77)

  # Optional: skips unless LEONIDA_GAME_DIR is set. Drives the package's FSR DLL on the Xbox-ABI device proxy.
  if(D3D12_LIBRARY AND DXGI_LIBRARY)
    add_executable(fsr_dispatch_test
      test/fsr_dispatch_test.cpp
      src/pe_loader.cpp
      shims/registry.cpp
      shims/xmem.cpp
      shims/d3d12_xs.cpp
      shims/d3d12_xs_device.cpp
    )
    target_compile_definitions(fsr_dispatch_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX _CRT_SECURE_NO_WARNINGS)
    target_compile_options(fsr_dispatch_test PRIVATE /W4 /permissive- /EHsc /utf-8)
    target_link_options(fsr_dispatch_test PRIVATE /OPT:NOREF)
    target_link_libraries(fsr_dispatch_test PRIVATE gta6rt_d3d12_xs_rootsig ${D3D12_LIBRARY} ${DXGI_LIBRARY} psapi)
    add_dependencies(fsr_dispatch_test gta6rt_tls_host)
    add_test(NAME fsr_dispatch COMMAND fsr_dispatch_test)
    set_tests_properties(fsr_dispatch PROPERTIES SKIP_RETURN_CODE 77)

    # Optional: skips unless LEONIDA_GAME_DIR is set. Constructs the package's XboxBvhBuilder on the device proxy.
    add_executable(bvh_builder_test
      test/bvh_builder_test.cpp
      src/pe_loader.cpp
      shims/registry.cpp
      shims/xmem.cpp
      shims/d3d12_xs.cpp
      shims/d3d12_xs_device.cpp
    )
    target_compile_definitions(bvh_builder_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX _CRT_SECURE_NO_WARNINGS)
    target_compile_options(bvh_builder_test PRIVATE /W4 /permissive- /EHsc /utf-8)
    target_link_options(bvh_builder_test PRIVATE /OPT:NOREF)
    target_link_libraries(bvh_builder_test PRIVATE gta6rt_d3d12_xs_rootsig ${D3D12_LIBRARY} ${DXGI_LIBRARY} psapi)
    add_dependencies(bvh_builder_test gta6rt_tls_host)
    add_test(NAME bvh_builder COMMAND bvh_builder_test)
    set_tests_properties(bvh_builder PROPERTIES SKIP_RETURN_CODE 77)
  endif()

  # Optional: skips unless LEONIDA_GAME_DIR and LEONIDA_MOVIE_AUDIO are set.
  add_executable(bink_audio_test
    test/bink_audio_test.cpp
    src/pe_loader.cpp
    shims/registry.cpp
    shims/xmem.cpp
  )
  target_compile_definitions(bink_audio_test PRIVATE
    WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE _CRT_SECURE_NO_WARNINGS)
  target_compile_options(bink_audio_test PRIVATE /W4 /permissive- /EHsc /utf-8)
  target_link_options(bink_audio_test PRIVATE /OPT:NOREF)
  target_link_libraries(bink_audio_test PRIVATE psapi)
  add_dependencies(bink_audio_test gta6rt_tls_host)
  add_test(NAME bink_audio COMMAND bink_audio_test)
  set_tests_properties(bink_audio PROPERTIES SKIP_RETURN_CODE 77)
endif()
if(WIN32 AND TARGET xmem_test)
  add_test(NAME xmem COMMAND xmem_test)
endif()
if(WIN32 AND TARGET xg_xs_test)
  add_test(NAME xg_xs COMMAND xg_xs_test)
endif()
if(WIN32 AND TARGET acphal_test)
  add_test(NAME acphal COMMAND acphal_test)
endif()
if(WIN32 AND TARGET cpu_emulation_test)
  add_test(NAME cpu_emulation COMMAND cpu_emulation_test)
endif()
if(WIN32 AND TARGET xapu_chad_test)
  add_test(NAME xapu_chad COMMAND xapu_chad_test)
endif()
if(WIN32 AND TARGET process_cmdline_test)
  add_test(NAME process_cmdline COMMAND process_cmdline_test)
endif()
if(WIN32 AND TARGET file_system_test)
  add_test(NAME file_system COMMAND file_system_test)
endif()
if(WIN32 AND TARGET int3_skip_test)
  add_test(NAME int3_skip COMMAND int3_skip_test)
endif()
if(WIN32 AND TARGET winhttp_offline_test)
  add_test(NAME winhttp_offline COMMAND winhttp_offline_test)
endif()
if(WIN32 AND TARGET com_shim_test)
  add_test(NAME com_shim COMMAND com_shim_test)
endif()
if(WIN32 AND TARGET bcrypt_rng_test)
  add_test(NAME bcrypt_rng COMMAND bcrypt_rng_test)
  add_test(NAME bcrypt_rng_seeded COMMAND bcrypt_rng_test --seeded)
  set_tests_properties(bcrypt_rng_seeded PROPERTIES ENVIRONMENT "LEONIDA_RNG_SEED=0x123456789abcdef0")
endif()
if(WIN32 AND TARGET api_ref_state_test)
  add_test(NAME api_ref_state COMMAND api_ref_state_test)
  set_tests_properties(api_ref_state PROPERTIES TIMEOUT 30)
endif()
if(WIN32 AND TARGET api_global_refs_test)
  add_test(NAME api_global_refs COMMAND api_global_refs_test)
  set_tests_properties(api_global_refs PROPERTIES TIMEOUT 30)
endif()
# Internal XTaskQueue context pinning and rundown regression tests.
if(WIN32 AND TARGET gta6rt_xtaskqueue)
  foreach(_context_test context_pinning context_rundown context_reentrant context_concurrent_detach context_attach_detach_stress)
    add_executable(${_context_test}_test
      test/${_context_test}_test.cpp
    )
    target_include_directories(${_context_test}_test PRIVATE
      ${CMAKE_CURRENT_SOURCE_DIR}/shims/xtaskqueue
      ${XTASKQUEUE_DIR}/Source/Task
      ${XTASKQUEUE_DIR}/Source/Common
    )
    target_compile_definitions(${_context_test}_test PRIVATE
      WIN32_LEAN_AND_MEAN NOMINMAX
    )
    target_compile_options(${_context_test}_test PRIVATE
      /W4 /permissive- /utf-8 /EHsc
    )
    target_link_libraries(${_context_test}_test PRIVATE
      gta6rt_xtaskqueue
    )
    add_test(NAME ${_context_test}
      COMMAND ${_context_test}_test
    )
    set_tests_properties(${_context_test} PROPERTIES TIMEOUT 15)
  endforeach()

  add_executable(wait_registration_test test/wait_registration_test.cpp)
  target_include_directories(wait_registration_test PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/shims/xtaskqueue ${XTASKQUEUE_DIR}/Source/Task ${XTASKQUEUE_DIR}/Source/Common)
  target_link_libraries(wait_registration_test PRIVATE gta6rt_xtaskqueue)
  foreach(_case unregister undispatched terminate parked self presignaled monitor close composite snapshot
                cross concurrent held_snapshot admission cancel_unregister reentrant_admission
                reentrant_vs_external_unregister multi_dispatcher_terminate multi_dispatcher_unregister_replace)
    add_test(NAME wait_registration_${_case} COMMAND wait_registration_test ${_case})
    set_tests_properties(wait_registration_${_case} PROPERTIES TIMEOUT 15)
  endforeach()
endif()
if(WIN32 AND TARGET dstorage_test)
  add_test(NAME dstorage COMMAND dstorage_test)
endif()
if(WIN32 AND TARGET xgameruntime_test)
  add_test(NAME xgameruntime COMMAND xgameruntime_test)
  add_test(NAME xgameruntime_user COMMAND xgameruntime_user_test)
  add_test(NAME xgameruntime_gamesave COMMAND xgameruntime_gamesave_test)
  add_test(NAME xgameruntime_store COMMAND xgameruntime_store_test)
  add_test(NAME xgameruntime_offline COMMAND xgameruntime_offline_test)
  add_test(NAME xgameruntime_offline_hdr COMMAND xgameruntime_offline_test)
  set_tests_properties(xgameruntime_offline_hdr PROPERTIES ENVIRONMENT "LEONIDA_HDR=1")
  add_test(NAME xgameruntime_user_gamertag COMMAND xgameruntime_user_test --expect-gamertag Tester42)
  set_tests_properties(xgameruntime_user_gamertag PROPERTIES ENVIRONMENT "LEONIDA_GAMERTAG=Tester42")
  # Longer than getenv_s's old 64-byte buffer: still the "Player" fallback (and its message), not a silent one.
  add_test(NAME xgameruntime_user_gamertag_long COMMAND xgameruntime_user_test --expect-gamertag Player)
  set_tests_properties(xgameruntime_user_gamertag_long PROPERTIES ENVIRONMENT "LEONIDA_GAMERTAG=GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG")
endif()
# The active-input tracker the GameInput shim feeds (src/active_input.h), on synthetic samples: no SDL, no
# controller, no GPU, so it builds and runs everywhere, with or without SDL3.
add_executable(active_input_test test/active_input_test.cpp)
if(MSVC)
  target_compile_options(active_input_test PRIVATE /W4 /permissive- /utf-8)
endif()
add_test(NAME active_input COMMAND active_input_test)
if(WIN32 AND TARGET gameinput_test)
  add_test(NAME gameinput COMMAND gameinput_test)
elseif(TARGET gta6rt)
  # Built without SDL3: listed as "Not Run (Disabled)" so it is visible that the shim was not tested.
  add_test(NAME gameinput COMMAND ${CMAKE_COMMAND} -E echo "built without SDL3")
  set_tests_properties(gameinput PROPERTIES DISABLED TRUE)
endif()
if(WIN32 AND TARGET gta6rt AND TARGET tiny_game)
  if(TARGET tiny_argv_default_a AND NOT CMAKE_CROSSCOMPILING)
    find_package(Python3 COMPONENTS Interpreter QUIET)
    if(Python3_FOUND)
      add_test(NAME run_argv_modes COMMAND "${Python3_EXECUTABLE}" -I
        "${CMAKE_CURRENT_SOURCE_DIR}/test/check_argv_modes.py"
        --loader "$<TARGET_FILE:gta6rt>" --fixtures "$<TARGET_FILE_DIR:tiny_argv_default_a>"
        --work-dir "${CMAKE_CURRENT_BINARY_DIR}")
      set_tests_properties(run_argv_modes PROPERTIES TIMEOUT 90)
    endif()
  endif()
  add_test(NAME run_startup_cmdline COMMAND ${CMAKE_COMMAND}
    "-DLOADER=$<TARGET_FILE:gta6rt>" "-DGUEST=$<TARGET_FILE:tiny_startup_cmdline>"
    "-DRUNNER=${CMAKE_CROSSCOMPILING_EMULATOR}" -P "${CMAKE_CURRENT_SOURCE_DIR}/test/check_startup_cmdline.cmake")
  add_test(NAME run_tiny_async COMMAND ${CMAKE_COMMAND}
    "-DLOADER=$<TARGET_FILE:gta6rt>" "-DGUEST=$<TARGET_FILE:tiny_async>"
    "-DRUNNER=${CMAKE_CROSSCOMPILING_EMULATOR}" -P "${CMAKE_CURRENT_SOURCE_DIR}/test/check_loaded_async.cmake")
  add_test(NAME run_tiny_gdk_load COMMAND ${CMAKE_COMMAND}
    "-DLOADER=$<TARGET_FILE:gta6rt>" "-DGUEST=$<TARGET_FILE:tiny_gdk_load>"
    "-DRUNNER=${CMAKE_CROSSCOMPILING_EMULATOR}" -P "${CMAKE_CURRENT_SOURCE_DIR}/test/check_loaded_gdk.cmake")
  add_test(NAME run_tiny_bundled_load COMMAND ${CMAKE_COMMAND}
    "-DLOADER=$<TARGET_FILE:gta6rt>" "-DGUEST=$<TARGET_FILE:tiny_bundled_load>"
    "-DRUNNER=${CMAKE_CROSSCOMPILING_EMULATOR}" -P "${CMAKE_CURRENT_SOURCE_DIR}/test/check_loaded_bundled.cmake")
  # atexit handlers, static destructors and the ways out, compared with the same program run natively.
  add_test(NAME run_tiny_atexit COMMAND ${CMAKE_COMMAND}
    "-DLOADER=$<TARGET_FILE:gta6rt>" "-DGUEST=$<TARGET_FILE:tiny_atexit>"
    "-DRUNNER=${CMAKE_CROSSCOMPILING_EMULATOR}" -P "${CMAKE_CURRENT_SOURCE_DIR}/test/check_atexit.cmake")
  add_test(NAME run_tiny_game COMMAND gta6rt --run $<TARGET_FILE:tiny_game> -- hello 42)
  add_test(NAME run_tiny_game_console_paths COMMAND ${CMAKE_COMMAND}
    "-DLOADER=$<TARGET_FILE:gta6rt>" "-DGUEST=$<TARGET_FILE:tiny_game>"
    "-DRUNNER=${CMAKE_CROSSCOMPILING_EMULATOR}" -P "${CMAKE_CURRENT_SOURCE_DIR}/test/check_console_paths.cmake")
  add_test(NAME run_tiny_game_exit_code COMMAND tiny_game_exit_code_test
           "$<TARGET_FILE:gta6rt>" "$<TARGET_FILE:tiny_game>")
  add_test(NAME run_tiny_game_abort_exit_codes COMMAND tiny_game_abort_test
           "$<TARGET_FILE:gta6rt>" "$<TARGET_FILE:tiny_game>")
  # Without relocations it can only run at 0x140000000 (base_reservation.h), so passing means it got there; the
  # game's exact exit code comes back through the relaunch.
  add_test(NAME run_tiny_game_fixed COMMAND gta6rt --run $<TARGET_FILE:tiny_game_fixed> -- hello 42)
  add_test(NAME run_tiny_game_fixed_exit_code COMMAND tiny_game_exit_code_test
           "$<TARGET_FILE:gta6rt>" "$<TARGET_FILE:tiny_game_fixed>")
  # Two modes at once are refused before anything is mapped (#886). The stand-in game's own arguments are passed,
  # so a gta6rt that ignored the conflict would run it, print "running" and exit 0.
  foreach(modes "dry-run;run" "dry-run;init" "init;run")
    string(REPLACE ";" "_" name "${modes}")
    list(TRANSFORM modes PREPEND "--")
    add_test(NAME gta6rt_rejects_${name} COMMAND gta6rt ${modes} $<TARGET_FILE:tiny_game> -- hello 42)
    set_tests_properties(gta6rt_rejects_${name} PROPERTIES
      PASS_REGULAR_EXPRESSION "usage: gta6rt"
      FAIL_REGULAR_EXPRESSION "running |module\\(s\\) mapped")
  endforeach()
  # The opt-in checks, one test each: thread_local on the game's threads, a C++ exception caught inside the image.
  add_test(NAME run_tiny_game_tls COMMAND gta6rt --run $<TARGET_FILE:tiny_game> -- hello 42 tls)
  add_test(NAME run_tiny_game_eh COMMAND gta6rt --run $<TARGET_FILE:tiny_game> -- hello 42 eh)
  # BUILD-1457: the stack a game thread gets. gta6rt_stack reads SizeOfStackReserve from the built loader (nothing
  # is run); run_tiny_game_stack asks Windows, on the entry thread and on a thread created with dwStackSize 0.
  add_test(NAME gta6rt_stack COMMAND "${CMAKE_COMMAND}"
           "-DTOOL=$<TARGET_FILE:gta6rt>" "-DWANT=${GTA6RT_STACK}"
           -P "${CMAKE_CURRENT_SOURCE_DIR}/test/check_stack_reserve.cmake")
  add_test(NAME run_tiny_game_stack COMMAND gta6rt --run $<TARGET_FILE:tiny_game> -- hello 42 stack)
  # GAME: is the game folder, absolute, when gta6rt is given a bare image name or `--game-dir .`.
  add_test(NAME run_tiny_game_dir COMMAND ${CMAKE_COMMAND}
    "-DLOADER=$<TARGET_FILE:gta6rt>" "-DGUEST=$<TARGET_FILE:tiny_game>"
    "-DRUNNER=${CMAKE_CROSSCOMPILING_EMULATOR}" -P "${CMAKE_CURRENT_SOURCE_DIR}/test/check_game_dir.cmake")
endif()
if(TARGET root_signature_test)
  add_test(NAME root_signature COMMAND root_signature_test)
endif()
if(TARGET host_cpu_test)
  add_test(NAME host_cpu COMMAND host_cpu_test)
endif()
if(TARGET core_config_test)
  # The example file is an argument, so the test reads the tracked file and not a copy made at configure time.
  add_test(NAME core_config COMMAND core_config_test "${CMAKE_CURRENT_SOURCE_DIR}/leonida.example.toml")
endif()
if(TARGET core_log_test)
  add_test(NAME core_log COMMAND core_log_test)
endif()
if(WIN32 AND TARGET root_signature_oracle_test)
  add_test(NAME root_signature_oracle COMMAND root_signature_oracle_test)
endif()
