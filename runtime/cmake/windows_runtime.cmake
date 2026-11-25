# The Windows runtime: gta6rt.exe, the libraries its shims link (the root-signature fix, XTaskQueue, the TLS host
# DLL, GameInput on SDL3) and the shim test programs. Their add_test() calls are in runtime_tests.cmake.
# Included by runtime/CMakeLists.txt inside if(WIN32 AND LEONIDA_BUILD_WINDOWS_RUNTIME).

# Custom CMAKE_CXX_FLAGS can replace MSVC's default /EHsc. Require C++ stack unwinding so error
# paths in the runtime and its libraries still destroy automatic objects when an exception leaves a frame.
if(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
  add_compile_options($<$<COMPILE_LANGUAGE:CXX>:/EHsc>)
endif()

# The d3d12_xs shim and its tests use version 1.2 root signatures (D3D12_ROOT_SIGNATURE_DESC2), which the Windows
# SDK declares from 10.0.26100 on. Stop here with the fix instead of failing halfway through the build.
include(CheckCXXSourceCompiles)
check_cxx_source_compiles([=[
  #include <d3d12.h>
  int main() { D3D12_VERSIONED_ROOT_SIGNATURE_DESC d{}; d.Version = D3D_ROOT_SIGNATURE_VERSION_1_2;
               return static_cast<int>(sizeof(d.Desc_1_2)); }
]=] GTA6RT_SDK_HAS_ROOT_SIGNATURE_1_2)
if(NOT GTA6RT_SDK_HAS_ROOT_SIGNATURE_1_2)
  if(CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION)
    set(_gta6rt_sdk "${CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION}")
  elseif(DEFINED ENV{WindowsSDKVersion})
    string(REGEX REPLACE "[\\/]+$" "" _gta6rt_sdk "$ENV{WindowsSDKVersion}")
  else()
    set(_gta6rt_sdk "an older one")
  endif()
  message(FATAL_ERROR
    "gta6rt needs the Windows SDK 10.0.26100 or newer (version 1.2 root signatures); "
    "this build uses ${_gta6rt_sdk}. Install it with "
    "`winget install Microsoft.WindowsSDK.10.0.26100` or the Visual Studio Installer, then delete the build "
    "folder and configure again.")
endif()

# Root-signature flag fix, shared by the d3d12_xs shim and its tests.
add_library(gta6rt_d3d12_xs_rootsig STATIC
  shims/d3d12_xs_rootsig.cpp
)
target_include_directories(gta6rt_d3d12_xs_rootsig PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/shims)
target_compile_definitions(gta6rt_d3d12_xs_rootsig PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(gta6rt_d3d12_xs_rootsig PRIVATE /W4 /permissive- /utf-8)

# XTaskQueue/XAsync from microsoft/libHttpClient (MIT), vendored in third_party/xtaskqueue; shims/xtaskqueue/pch.h
# stands in for libHttpClient's pch.h so only the task queue builds. Used by the xgameruntime shim.
set(XTASKQUEUE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/xtaskqueue)
add_library(gta6rt_xtaskqueue STATIC
  ${XTASKQUEUE_DIR}/Source/Task/TaskQueue.cpp
  ${XTASKQUEUE_DIR}/Source/Task/AsyncLib.cpp
  ${XTASKQUEUE_DIR}/Source/Task/ThreadPool_win32.cpp
  ${XTASKQUEUE_DIR}/Source/Task/WaitTimer_win32.cpp
)
target_include_directories(gta6rt_xtaskqueue
  PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/shims/xtaskqueue ${XTASKQUEUE_DIR}/Source/Task ${XTASKQUEUE_DIR}/Source/Common
  PUBLIC ${XTASKQUEUE_DIR}/Include)
target_compile_definitions(gta6rt_xtaskqueue PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(gta6rt_xtaskqueue PRIVATE /utf-8)  # third-party code: its own warning level
target_link_libraries(gta6rt_xtaskqueue PUBLIC ole32)

# Reserves one loader-assigned module TLS index for mapped images. Loaded from the executable's directory by
# Loader::initialize_tls; its trivial DllMain only keeps the TLS anchor in the image. Built in the same directory as
# the executables that map images, because the loader looks for it next to the running EXE.
add_library(gta6rt_tls_host SHARED src/tls_host.cpp)
target_compile_options(gta6rt_tls_host PRIVATE /W4 /permissive- /utf-8 /GS-)
target_compile_definitions(gta6rt_tls_host PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
set_target_properties(gta6rt_tls_host PROPERTIES
  OUTPUT_NAME gta6rt_tls_host
  PREFIX ""
  MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>"
)

add_executable(gta6rt
  src/main.cpp
  src/host_cpu.cpp
  src/pe_loader.cpp
  shims/registry.cpp
  shims/file_system.cpp
  shims/winhttp_offline.cpp
  shims/xmem.cpp
  shims/xg_xs.cpp
  shims/acphal.cpp
  shims/d3d12_xs.cpp
  shims/d3d12_xs_device.cpp
  shims/xgameruntime.cpp
  shims/xgameruntime_user.cpp
  shims/xgameruntime_gamesave.cpp
  shims/xgameruntime_store.cpp
  shims/xgameruntime_offline.cpp
  shims/library_loader.cpp
  shims/process.cpp
  shims/com_shim.cpp
  shims/bcrypt_rng.cpp
  shims/xapu_chad.cpp
  shims/dstorage.cpp
)
# dstorage.cpp's guarded_move turns an access violation in a title's buffer into E_DSTORAGE_ACCESS_VIOLATION with
# __try. MSVC always catches it; clang-cl only with asynchronous exceptions (as for tiny_dll below). A source file
# property, so gta6rt and dstorage_test both get it.
set_source_files_properties(shims/dstorage.cpp PROPERTIES COMPILE_OPTIONS "$<$<CXX_COMPILER_ID:Clang>:/EHa>")
add_dependencies(gta6rt gta6rt_tls_host)
target_compile_definitions(gta6rt PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE)
target_compile_options(gta6rt PRIVATE /W4 /permissive- /utf-8)
# Static shim tables register themselves at startup; keep the linker from dropping their objects.
# GTA6RT_HOST_BASE keeps the loader's own image off the default x64 EXE base (0x140000000), where a mapped EXE
# without relocations wants to go. Windows moves the EXE with ASLR anyway; Wine loads it at its preferred base.
set(GTA6RT_HOST_BASE /BASE:0x10000000000)
# BUILD-1457: a thread that asks for no stack size gets the reserve in this program's PE header, 1 MB by default:
# a thread the game starts with dwStackSize 0, a thread-pool thread, a std::thread of the shims. The D3D12 shim
# creates Vulkan pipelines on the calling thread, the driver compiles there, and AMD's Windows compiler (26.11.2)
# overflows 1 MB on some of the game's shaders (docs/pipeline_check.md, "Stack reserve"). run_entry already gives
# the entry thread 8 MB (shims/process_shim.h); this is the same number for the others. Keep it in step with
# scripts/build_runtime.ps1.
set(GTA6RT_STACK 8388608)
target_link_options(gta6rt PRIVATE /OPT:NOREF ${GTA6RT_HOST_BASE} /STACK:${GTA6RT_STACK})
target_link_libraries(gta6rt PRIVATE gta6rt_core gta6rt_d3d12_xs_rootsig gta6rt_xtaskqueue psapi)

# Root-signature forwarding test: needs a real PC d3d12.lib to serialize the synthetic descriptors.
# find_library searches %LIB% (a Developer Prompt), not the Windows SDK the Visual Studio generator links
# against, so also look in that SDK's um/x64 folder.
set(_sdk_lib_hints)
if(DEFINED ENV{WindowsSdkDir} AND DEFINED ENV{WindowsSDKLibVersion})
  list(APPEND _sdk_lib_hints "$ENV{WindowsSdkDir}Lib/$ENV{WindowsSDKLibVersion}um/x64")
endif()
get_filename_component(_kits_root
  "[HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows Kits\\Installed Roots;KitsRoot10]" ABSOLUTE)
if(CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION AND EXISTS "${_kits_root}")
  list(APPEND _sdk_lib_hints "${_kits_root}/Lib/${CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION}/um/x64")
endif()
find_library(D3D12_LIBRARY NAMES d3d12 HINTS ${_sdk_lib_hints})
find_library(DXGI_LIBRARY NAMES dxgi HINTS ${_sdk_lib_hints})
if(D3D12_LIBRARY)
  add_executable(root_sig_test
    test/root_sig_test.cpp
    shims/registry.cpp
    shims/d3d12_xs.cpp
    shims/d3d12_xs_device.cpp
  )
  target_link_libraries(root_sig_test PRIVATE gta6rt_d3d12_xs_rootsig ${D3D12_LIBRARY})
  target_compile_definitions(root_sig_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(root_sig_test PRIVATE /W4 /permissive- /utf-8)
  target_link_options(root_sig_test PRIVATE /OPT:NOREF)

  # RTS0 parser oracle: synthetic descriptors only, serialized by the real PC
  # d3d12.dll and parsed back by rt::rootsig::parse_rts0. A layout mismatch
  # fails here with the blob bytes, never silently in a draw.
  add_executable(root_signature_oracle_test
    test/root_signature_oracle_test.cpp
  )
  target_link_libraries(root_signature_oracle_test PRIVATE gta6rt_root_signature ${D3D12_LIBRARY})
  target_compile_definitions(root_signature_oracle_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(root_signature_oracle_test PRIVATE /W4 /permissive- /utf-8)
  target_link_options(root_signature_oracle_test PRIVATE /OPT:NOREF)

  # Xbox-ABI device proxy test: WARP PC device, no game executable. Needs DXGI for the WARP adapter.
  if(DXGI_LIBRARY)
    add_executable(device_proxy_test
      test/device_proxy_test.cpp
      shims/registry.cpp
      shims/d3d12_xs.cpp
      shims/d3d12_xs_device.cpp
    )
    target_link_libraries(device_proxy_test PRIVATE gta6rt_d3d12_xs_rootsig ${D3D12_LIBRARY} ${DXGI_LIBRARY})
    target_compile_definitions(device_proxy_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
    target_compile_options(device_proxy_test PRIVATE /W4 /permissive- /utf-8)
    target_link_options(device_proxy_test PRIVATE /OPT:NOREF)
  else()
    message(STATUS "dxgi.lib not found: device_proxy_test is not built")
  endif()
  # The queue and fence proxies over synthetic COM objects: no D3D12 runtime, no GPU. Replaces operator new and
  # patches its own import table to inject failures, so the proxy source is compiled into it alone.
  add_executable(xs_proxy_mock_test
    test/xs_proxy_mock_test.cpp
    shims/d3d12_xs_device.cpp
  )
  target_compile_definitions(xs_proxy_mock_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(xs_proxy_mock_test PRIVATE /W4 /permissive- /utf-8 /EHsc)
else()
  message(STATUS "d3d12.lib not found: root_sig_test and device_proxy_test are not built")
endif()

# xmem shim ABI test: resolves the registered xmem.dll exports itself, so xmem.cpp and registry.cpp are compiled
# into this executable instead of reusing gta6rt's objects (which would duplicate their symbols).
add_executable(xmem_test
  test/xmem_test.cpp
  shims/xmem.cpp
  shims/registry.cpp
)
target_include_directories(xmem_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/shims)
target_compile_definitions(xmem_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(xmem_test PRIVATE /W4 /permissive- /utf-8 $<$<CXX_COMPILER_ID:Clang>:/EHa>)
target_link_options(xmem_test PRIVATE /OPT:NOREF)
target_link_libraries(xmem_test PRIVATE psapi)

# xg_xs shim: the two exports and the texture computer's slots against the measured call shapes.
add_executable(xg_xs_test
  test/xg_xs_test.cpp
  shims/xg_xs.cpp
  shims/registry.cpp
)
target_include_directories(xg_xs_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/shims)
target_compile_definitions(xg_xs_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(xg_xs_test PRIVATE /W4 /permissive- /utf-8)
target_link_options(xg_xs_test PRIVATE /OPT:NOREF)

# acphal shim ABI test: resolves the registered acphal.dll exports through the registry.
add_executable(acphal_test
  test/acphal_test.cpp
  shims/acphal.cpp
  shims/registry.cpp
)
target_include_directories(acphal_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/shims)
target_compile_definitions(acphal_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(acphal_test PRIVATE /W4 /permissive- /utf-8)
target_link_options(acphal_test PRIVATE /OPT:NOREF)

# The Zen 2 instructions a desktop CPU may lack (src/cpu_emulation.h): decoded, emulated on a CONTEXT, and run for
# real with the #UD handler installed, so an Intel host takes the emulated path and an AMD one the native path.
add_executable(cpu_emulation_test test/cpu_emulation_test.cpp)
target_include_directories(cpu_emulation_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_compile_definitions(cpu_emulation_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(cpu_emulation_test PRIVATE /W4 /permissive- /utf-8)

# Xbox DirectStorage (DStorageGetFactory under dstorage_xs.dll, xcrdapi.dll and dstorage.dll) over synthetic files:
# GAME: paths through the file shims, queues, status arrays, fences and errors. No GPU, no game data.
add_executable(dstorage_test
  test/dstorage_test.cpp
  shims/dstorage.cpp
  shims/file_system.cpp
  shims/registry.cpp
)
target_include_directories(dstorage_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/shims)
target_compile_definitions(dstorage_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(dstorage_test PRIVATE /W4 /permissive- /utf-8)
target_link_options(dstorage_test PRIVATE /OPT:NOREF)

# xapu.dll and chad.dll, the APU and audio DSP command queues, resolved through the registry like xmem_test.
add_executable(xapu_chad_test
  test/xapu_chad_test.cpp
  shims/xapu_chad.cpp
  shims/registry.cpp
)
target_include_directories(xapu_chad_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/shims)
target_compile_definitions(xapu_chad_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(xapu_chad_test PRIVATE /W4 /permissive- /utf-8)
target_link_options(xapu_chad_test PRIVATE /OPT:NOREF)

# The process shim's command line: GetCommandLineW must parse (CommandLineToArgvW) back to its __wargv.
add_executable(process_cmdline_test
  test/process_cmdline_test.cpp
  shims/process.cpp
  shims/registry.cpp
)
target_include_directories(process_cmdline_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/shims)
target_compile_definitions(process_cmdline_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(process_cmdline_test PRIVATE /W4 /permissive- /utf-8)
target_link_options(process_cmdline_test PRIVATE /OPT:NOREF)
target_link_libraries(process_cmdline_test PRIVATE shell32)

# Console paths (GAME:) and the write overlay: the file shims resolved through the registry, over temporary folders.
add_executable(file_system_test
  test/file_system_test.cpp
  shims/file_system.cpp
  shims/registry.cpp
)
target_include_directories(file_system_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/shims)
target_compile_definitions(file_system_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(file_system_test PRIVATE /W4 /permissive- /utf-8)
target_link_options(file_system_test PRIVATE /OPT:NOREF)
target_link_libraries(file_system_test PRIVATE advapi32)  # the ACL calls of the unlistable-marker-folder check

# loader.skip_int3 (LEONIDA_SKIP_INT3; shims/startup_trace.h): its own executable, the switch is for the whole process.
add_executable(int3_skip_test
  test/int3_skip_test.cpp
  shims/registry.cpp
)
target_include_directories(int3_skip_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/shims)
target_compile_definitions(int3_skip_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(int3_skip_test PRIVATE /W4 /permissive- /utf-8)
target_link_options(int3_skip_test PRIVATE /OPT:NOREF)

# Offline WinHTTP for mapped images (the package's XCurl.dll and libHttpClient.GDK.dll); no network is touched.
add_executable(winhttp_offline_test
  test/winhttp_offline_test.cpp
  shims/winhttp_offline.cpp
  shims/registry.cpp
)
target_include_directories(winhttp_offline_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/shims)
target_compile_definitions(winhttp_offline_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(winhttp_offline_test PRIVATE /W4 /permissive- /utf-8)
target_link_options(winhttp_offline_test PRIVATE /OPT:NOREF)

# COM lifecycle and helper shims for api-ms-win-core-com-l1-1-*.dll.
add_executable(com_shim_test
  test/com_shim_test.cpp
  shims/com_shim.cpp
  shims/registry.cpp
)
target_include_directories(com_shim_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/shims)
target_compile_definitions(com_shim_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(com_shim_test PRIVATE /W4 /permissive- /utf-8)
target_link_options(com_shim_test PRIVATE /OPT:NOREF)

# BCrypt RNG and algorithm provider shims.
add_executable(bcrypt_rng_test
  test/bcrypt_rng_test.cpp
  shims/bcrypt_rng.cpp
  shims/registry.cpp
)
target_include_directories(bcrypt_rng_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/shims)
target_compile_definitions(bcrypt_rng_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(bcrypt_rng_test PRIVATE /W4 /permissive- /utf-8)
target_link_options(bcrypt_rng_test PRIVATE /OPT:NOREF)

# Synthetic tests for the atomic API reference lifecycle.
add_executable(api_ref_state_test test/api_ref_state_test.cpp)
target_include_directories(api_ref_state_test PRIVATE
  ${XTASKQUEUE_DIR}/Source/Task)
target_compile_definitions(api_ref_state_test PRIVATE
  WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(api_ref_state_test PRIVATE
  /W4 /permissive- /utf-8)
# Verify global reference accounting during task queue teardown.
add_executable(api_global_refs_test test/api_global_refs_test.cpp)
target_compile_definitions(api_global_refs_test PRIVATE
  WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(api_global_refs_test PRIVATE
  /W4 /permissive- /utf-8)
target_link_libraries(api_global_refs_test PRIVATE
  gta6rt_xtaskqueue)
# Offline GDK runtime shim (XGameRuntime, XSystem, XTaskQueue, XAsync), driven through the shim registry the way
# a title calls it at boot. Like xmem_test it compiles its own registry.cpp.
add_executable(xgameruntime_test
  test/xgameruntime_test.cpp
  shims/xgameruntime.cpp
  shims/xgameruntime_user.cpp
  shims/xgameruntime_gamesave.cpp
  shims/xgameruntime_store.cpp
  shims/xgameruntime_offline.cpp
  shims/library_loader.cpp
  shims/registry.cpp
  shims/file_system.cpp
)
target_include_directories(xgameruntime_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/shims)
target_compile_definitions(xgameruntime_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(xgameruntime_test PRIVATE /W4 /permissive- /utf-8)
target_link_options(xgameruntime_test PRIVATE /OPT:NOREF)
target_link_libraries(xgameruntime_test PRIVATE gta6rt_xtaskqueue)

# XUserImpl (offline local user) through QueryApiImpl, slot by slot as xgameruntime.lib's thunks call it.
add_executable(xgameruntime_user_test
  test/xgameruntime_user_test.cpp
  shims/xgameruntime.cpp
  shims/xgameruntime_user.cpp
  shims/xgameruntime_gamesave.cpp
  shims/xgameruntime_store.cpp
  shims/xgameruntime_offline.cpp
  shims/library_loader.cpp
  shims/registry.cpp
  shims/file_system.cpp
)
target_include_directories(xgameruntime_user_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/shims)
target_compile_definitions(xgameruntime_user_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(xgameruntime_user_test PRIVATE /W4 /permissive- /utf-8)
target_link_options(xgameruntime_user_test PRIVATE /OPT:NOREF)
target_link_libraries(xgameruntime_user_test PRIVATE gta6rt_xtaskqueue)

# XGameSaveImpl (offline saves in LEONIDA_SAVE_DIR) through QueryApiImpl, slot by slot.
add_executable(xgameruntime_gamesave_test
  test/xgameruntime_gamesave_test.cpp
  shims/xgameruntime.cpp
  shims/xgameruntime_user.cpp
  shims/xgameruntime_gamesave.cpp
  shims/xgameruntime_store.cpp
  shims/xgameruntime_offline.cpp
  shims/library_loader.cpp
  shims/registry.cpp
  shims/file_system.cpp
)
target_include_directories(xgameruntime_gamesave_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/shims)
target_compile_definitions(xgameruntime_gamesave_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(xgameruntime_gamesave_test PRIVATE /W4 /permissive- /utf-8)
target_link_options(xgameruntime_gamesave_test PRIVATE /OPT:NOREF)
target_link_libraries(xgameruntime_gamesave_test PRIVATE gta6rt_xtaskqueue)

# XStoreImpl (offline: the game is owned, no add-ons, no updates) through QueryApiImpl, slot by slot.
add_executable(xgameruntime_store_test
  test/xgameruntime_store_test.cpp
  shims/xgameruntime.cpp
  shims/xgameruntime_user.cpp
  shims/xgameruntime_gamesave.cpp
  shims/xgameruntime_store.cpp
  shims/xgameruntime_offline.cpp
  shims/library_loader.cpp
  shims/registry.cpp
  shims/file_system.cpp
)
target_include_directories(xgameruntime_store_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/shims)
target_compile_definitions(xgameruntime_store_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(xgameruntime_store_test PRIVATE /W4 /permissive- /utf-8)
target_link_options(xgameruntime_store_test PRIVATE /OPT:NOREF)
target_link_libraries(xgameruntime_store_test PRIVATE gta6rt_xtaskqueue)

# XGameEventImpl, XGameUiImpl, XGameStreamingImpl (offline) through QueryApiImpl.
add_executable(xgameruntime_offline_test
  test/xgameruntime_offline_test.cpp
  shims/xgameruntime.cpp
  shims/xgameruntime_user.cpp
  shims/xgameruntime_gamesave.cpp
  shims/xgameruntime_store.cpp
  shims/xgameruntime_offline.cpp
  shims/library_loader.cpp
  shims/registry.cpp
  shims/file_system.cpp
)
target_include_directories(xgameruntime_offline_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/shims)
target_compile_definitions(xgameruntime_offline_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(xgameruntime_offline_test PRIVATE /W4 /permissive- /utf-8)
target_link_options(xgameruntime_offline_test PRIVATE /OPT:NOREF)
target_link_libraries(xgameruntime_offline_test PRIVATE gta6rt_xtaskqueue)

# GameInput shim on SDL3 (zlib licence): any controller SDL supports, DualSense trigger effects and lightbar.
# Nothing is downloaded unless asked. The shim is built when SDL3 is available:
#   - an installed SDL3 3.2+ that find_package finds (SDL3_DIR / CMAKE_PREFIX_PATH), or
#   - -DLEONIDA_SDL3_FETCH=ON: download the pinned release below once at configure time (hash-checked) and build it
#     static, or -DFETCHCONTENT_SOURCE_DIR_SDL3=<extracted SDL3-3.4.20> to build that copy without downloading.
# Otherwise, or with -DLEONIDA_SDL3=OFF, gta6rt is built without the shim and the loader binds GameInputCreate to the
# host's GameInput.dll or the unimplemented thunk as before. docs/gameinput.md has the details.
option(LEONIDA_SDL3 "Build the GameInput shim when SDL3 is available" ON)
option(LEONIDA_SDL3_FETCH "Download the pinned SDL3 release if no installed SDL3 is found" OFF)
if(LEONIDA_SDL3)
  find_package(SDL3 3.2 CONFIG QUIET COMPONENTS SDL3-static NO_SYSTEM_ENVIRONMENT_PATH)
  if(NOT TARGET SDL3::SDL3-static AND (LEONIDA_SDL3_FETCH OR FETCHCONTENT_SOURCE_DIR_SDL3))
    include(FetchContent)
    FetchContent_Declare(SDL3
      URL https://github.com/libsdl-org/SDL/releases/download/release-3.4.20/SDL3-3.4.20.tar.gz
      URL_HASH SHA256=f3bb06f55bed9557227a700af2ea62e49497ebdf58037732a731a5fb3ef8581f
      DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
    # Only what gamepads need: the joystick, HIDAPI, haptic, sensor and power code, in a static library.
    set(SDL_SHARED OFF CACHE BOOL "" FORCE)
    set(SDL_STATIC ON CACHE BOOL "" FORCE)
    set(SDL_TEST_LIBRARY OFF CACHE BOOL "" FORCE)
    set(SDL_TESTS OFF CACHE BOOL "" FORCE)
    set(SDL_EXAMPLES OFF CACHE BOOL "" FORCE)
    set(SDL_INSTALL OFF CACHE BOOL "" FORCE)
    set(SDL_DISABLE_INSTALL ON CACHE BOOL "" FORCE)
    foreach(_sdl_off SDL_AUDIO SDL_VIDEO SDL_GPU SDL_RENDER SDL_CAMERA SDL_DIALOG SDL_TRAY)
      set(${_sdl_off} OFF CACHE BOOL "" FORCE)
    endforeach()
    FetchContent_MakeAvailable(SDL3)
  endif()
endif()
if(LEONIDA_SDL3 AND TARGET SDL3::SDL3-static)
  target_sources(gta6rt PRIVATE shims/gameinput.cpp)
  target_link_libraries(gta6rt PRIVATE SDL3::SDL3-static)

  # GameInput through the shim registry on SDL virtual joysticks: no controller, no game data.
  add_executable(gameinput_test test/gameinput_test.cpp shims/gameinput.cpp shims/registry.cpp)
  # gameinput_probe: the same shim on a real controller, run by hand (not a CTest).
  add_executable(gameinput_probe test/gameinput_probe.cpp shims/gameinput.cpp shims/registry.cpp)
  foreach(_gi gameinput_test gameinput_probe)
    target_include_directories(${_gi} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/shims)
    target_compile_definitions(${_gi} PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
    target_compile_options(${_gi} PRIVATE /W4 /permissive- /utf-8)
    target_link_options(${_gi} PRIVATE /OPT:NOREF)
    target_link_libraries(${_gi} PRIVATE SDL3::SDL3-static)
  endforeach()
else()
  if(LEONIDA_SDL3)
    message(STATUS "GameInput shim not built: no installed SDL3 found. Set SDL3_DIR, or pass -DLEONIDA_SDL3_FETCH=ON "
                   "to download the pinned SDL3 release (see docs/gameinput.md)")
  else()
    message(STATUS "GameInput shim not built (LEONIDA_SDL3=OFF)")
  endif()
endif()
