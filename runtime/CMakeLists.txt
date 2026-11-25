cmake_minimum_required(VERSION 3.24)
project(gta6rt LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# The sources are UTF-8. Without /utf-8, MSVC reads them in the system's ANSI code page, so on code page 936 (or
# any other non-1252 locale) it prints C4819 for every non-ASCII comment. Many targets set /utf-8 themselves; this
# covers every target, including those that don't. clang-cl accepts it too. Only C and C++: ml64 (abi_probe.asm) has
# no /utf-8 and warns A4018 for it.
if(MSVC)
  add_compile_options($<$<COMPILE_LANGUAGE:C,CXX>:/utf-8>)
endif()

if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
  message(FATAL_ERROR "gta6rt must be built for x64 (run from an x64 Native Tools prompt or vcvars64.bat)")
endif()

# The diagnostics build (the `diag` preset in CMakePresets.json): every target is compiled with LEONIDA_DIAGNOSTICS
# defined. Code that only helps to find a fault (debug and trace logging, captures, stack dumps) goes behind it, so
# a release build neither carries nor runs it.
option(LEONIDA_DIAGNOSTICS "Compile in the diagnostics a release build leaves out" OFF)
if(LEONIDA_DIAGNOSTICS)
  add_compile_definitions(LEONIDA_DIAGNOSTICS=1)
endif()

# Portable root-signature model + packer to user SGPRs (no d3d12.h, no windows.h), and the host CPU preflight of
# --init/--run (src/host_cpu.h). Built on every OS, so their tests run in the Linux and macOS jobs as well as with the
# Windows runtime.
add_library(gta6rt_root_signature STATIC
  src/root_signature.cpp
)
target_include_directories(gta6rt_root_signature PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)
# Portable contract test: model, packer, canonical codec and RTS0 hypothesis. Needs neither d3d12.lib nor the game.
add_executable(root_signature_test
  test/root_signature_test.cpp
)
target_link_libraries(root_signature_test PRIVATE gta6rt_root_signature)
# AVX, OSXSAVE and XCR0 YMM state from synthetic CPUID/XCR0 words, plus one call on the real host.
add_executable(host_cpu_test test/host_cpu_test.cpp src/host_cpu.cpp)
target_include_directories(host_cpu_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
# The core layer: what every other part of the runtime may use, and which uses none of them. It holds the settings
# table (core/config.h): a value comes from its environment variable, else from leonida.toml, else from the default.
add_library(gta6rt_core STATIC
  core/config.cpp
)
# The table's shape, the order of the three sources, the file reader and leonida.example.toml against the table.
add_executable(core_config_test test/core_config_test.cpp)
target_link_libraries(core_config_test PRIVATE gta6rt_core)
if(MSVC)
  foreach(_portable gta6rt_root_signature root_signature_test host_cpu_test gta6rt_core core_config_test)
    target_compile_definitions(${_portable} PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
    target_compile_options(${_portable} PRIVATE /W4 /permissive- /utf-8)
  endforeach()
  target_link_options(root_signature_test PRIVATE /OPT:NOREF)
endif()

option(LEONIDA_BUILD_WINDOWS_RUNTIME "Build the Windows runtime, its shims and their tests" ${WIN32})
if(WIN32 AND LEONIDA_BUILD_WINDOWS_RUNTIME)
  # gta6rt.exe, the libraries its shims link and the shim test programs.
  include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/windows_runtime.cmake")

elseif(NOT WIN32)
  message(STATUS "gta6rt requires Windows; only Vulkan tools are available on Linux")
endif()

include(CTest)
# LEONIDA_TRANSLATOR_DEPS: what the rules that run test/shaders/build.py depend on besides their .asm files.
include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/translator_deps.cmake")
# leonida_add_d3d12_xs_stub(): the import stub the stand-in titles link.
include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/fixtures.cmake")
if(BUILD_TESTING)
  # The tests that need no Vulkan headers, and the stand-in titles gta6rt maps in them.
  include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/runtime_tests.cmake")
endif()

if(TARGET gta6rt_d3d12_xs_rootsig)
option(LEONIDA_D3D12_SHIM_TESTS "Build the standalone D3D12 root-signature shim test" OFF)
if(LEONIDA_D3D12_SHIM_TESTS)
  enable_testing()
  add_executable(d3d12_xs_root_signature_test
    test/d3d12_xs_root_signature_test.cpp
    shims/d3d12_xs.cpp
    shims/registry.cpp
    shims/d3d12_xs_device.cpp
  )
  target_include_directories(d3d12_xs_root_signature_test PRIVATE shims)
  target_compile_definitions(d3d12_xs_root_signature_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(d3d12_xs_root_signature_test PRIVATE /W4 /permissive- /EHsc /utf-8)
  target_link_options(d3d12_xs_root_signature_test PRIVATE /OPT:NOREF)
  target_link_libraries(d3d12_xs_root_signature_test PRIVATE gta6rt_d3d12_xs_rootsig d3d12 dxgi)
  add_test(NAME d3d12_xs_root_signature COMMAND d3d12_xs_root_signature_test)
  set_tests_properties(d3d12_xs_root_signature PROPERTIES SKIP_RETURN_CODE 77)  # no WARP adapter (Wine)
endif()
endif()

# CPU-only: which SPIR-V capabilities make the standalone GPU tools ask for shaderInt64 (TEST-468). It includes no
# Vulkan header, so it builds and runs without them, unlike the tools below that use it.
add_executable(spirv_capability_test test/spirv_capability_test.cpp)
if(BUILD_TESTING)
  add_test(NAME spirv_capability COMMAND spirv_capability_test)
endif()

# GPU test and pipeline tools load Vulkan at run time, so only the Vulkan headers are needed at build time.
# Nothing is downloaded unless asked: set VULKAN_SDK, install the Vulkan headers, pass
# -DLEONIDA_VULKAN_HEADERS_FETCH=ON to download the pinned Khronos Vulkan-Headers release once at configure time
# (hash-checked), or pass -DFETCHCONTENT_SOURCE_DIR_VULKANHEADERS=<path> to use a local copy without downloading.
option(LEONIDA_VULKAN_HEADERS_FETCH "Download the pinned Khronos Vulkan-Headers release if no Vulkan headers are found" OFF)
option(LEONIDA_REQUIRE_VULKAN "Fail the configure instead of warning when no Vulkan headers are found" OFF)
find_package(Vulkan QUIET)
if(NOT TARGET Vulkan::Headers)
  find_path(Vulkan_INCLUDE_DIR
    NAMES vulkan/vulkan.h
    HINTS "$ENV{VULKAN_SDK}/Include" "$ENV{VULKAN_SDK}/include"
  )
  if(Vulkan_INCLUDE_DIR AND EXISTS "${Vulkan_INCLUDE_DIR}/vulkan/vulkan.h")
    add_library(Vulkan::Headers INTERFACE IMPORTED)
    set_target_properties(Vulkan::Headers PROPERTIES
      INTERFACE_INCLUDE_DIRECTORIES "${Vulkan_INCLUDE_DIR}"
    )
  elseif(LEONIDA_VULKAN_HEADERS_FETCH OR FETCHCONTENT_SOURCE_DIR_VULKANHEADERS)
    include(FetchContent)
    FetchContent_Declare(VulkanHeaders
      # vulkan-sdk-1.4.363.0 (same commit pinned in .github/workflows/runtime.yml)
      URL https://github.com/KhronosGroup/Vulkan-Headers/archive/6802bb4733b63ed5efd3adb308a6c885ef180ea1.tar.gz
      URL_HASH SHA256=9044fbb356160e43201dc2094acb44c8a906722a63a35f48fc0f051579db9bb6
      DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
    set(VULKAN_HEADERS_ENABLE_TESTS OFF CACHE BOOL "" FORCE)
    set(VULKAN_HEADERS_ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
    set(VULKAN_HEADERS_ENABLE_MODULE OFF CACHE BOOL "" FORCE)
    FetchContent_MakeAvailable(VulkanHeaders)
  endif()
endif()
if(TARGET Vulkan::Headers)
  # The standalone Vulkan tools and the Vulkan tests that do not use the D3D12 COM objects.
  include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/vulkan_tools.cmake")
  # The D3D12 COM objects over the Vulkan backend and their tests.
  include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/d3d12_vulkan.cmake")

  # The tests of the Vulkan layer that need its headers but no GPU.
  include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/vulkan_cpu_tests.cmake")
else()
  include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/vulkan_headers_missing.cmake")
  leonida_vulkan_headers_missing()
endif()

# The sources that read a setting from the table (core/config.h). Many targets compile them directly (the loader
# tests build src/pe_loader.cpp themselves), so every target that compiles one of them links gta6rt_core here, in one
# place, and a source that moves to the table is added to this list. The list goes when the layers are libraries
# that carry the dependency themselves.
set(LEONIDA_SETTING_READERS
  src/host_cpu.cpp
  src/pe_loader.cpp
  shims/registry.cpp
  shims/bcrypt_rng.cpp
  shims/xgameruntime.cpp
  shims/xgameruntime_user.cpp
  shims/xgameruntime_offline.cpp
  shims/xgameruntime_gamesave.cpp
  shims/d3d12_xs.cpp
  shims/d3d12_xs_device.cpp
  shims/xbox_present.cpp
)
list(TRANSFORM LEONIDA_SETTING_READERS PREPEND "${CMAKE_CURRENT_SOURCE_DIR}/")
get_property(_gta6rt_targets DIRECTORY PROPERTY BUILDSYSTEM_TARGETS)
foreach(_target IN LISTS _gta6rt_targets)
  get_target_property(_type ${_target} TYPE)
  get_target_property(_sources ${_target} SOURCES)
  if(NOT _sources OR NOT _type MATCHES "^(EXECUTABLE|STATIC_LIBRARY|SHARED_LIBRARY|MODULE_LIBRARY)$")
    continue()
  endif()
  foreach(_source IN LISTS _sources)
    if(_source MATCHES "^\\$<")
      continue()  # a generator expression: objects of another target, not a source file
    endif()
    get_filename_component(_source "${_source}" ABSOLUTE BASE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
    if(_source IN_LIST LEONIDA_SETTING_READERS)
      target_link_libraries(${_target} PRIVATE gta6rt_core)
      break()
    endif()
  endforeach()
endforeach()

# Timed condition-variable waits on Wine 9 (#3796): every Windows executable and DLL built against the dynamic CRT
# (/MD, the default) gets src/crt_timed_wait.cpp, which keeps msvcprt.lib's statically linked timed wait out of the
# link so that a wait and the mutex it unlocks always use msvcp140's own layout. A target that links the CRT
# statically (MSVC_RUNTIME_LIBRARY MultiThreaded, MultiThreadedDebug) already agrees with itself and is left alone,
# as are the fixtures linked with /NODEFAULTLIB, which have no CRT.
if(WIN32 AND MSVC)
  add_library(gta6rt_crt_timed_wait OBJECT src/crt_timed_wait.cpp)
  target_compile_definitions(gta6rt_crt_timed_wait PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(gta6rt_crt_timed_wait PRIVATE /W4 /permissive- /utf-8)
  # A timed wait is woken by a thread that takes its mutex; shared_mutex and sleep_for still work.
  add_executable(crt_timed_wait_test test/crt_timed_wait_test.cpp)
  target_compile_options(crt_timed_wait_test PRIVATE /W4 /permissive- /EHsc /utf-8)
  add_test(NAME crt_timed_wait COMMAND crt_timed_wait_test)
  set_tests_properties(crt_timed_wait PROPERTIES TIMEOUT 60)
  get_property(_gta6rt_targets DIRECTORY PROPERTY BUILDSYSTEM_TARGETS)
  foreach(_target IN LISTS _gta6rt_targets)
    get_target_property(_type ${_target} TYPE)
    if(NOT _type MATCHES "^(EXECUTABLE|SHARED_LIBRARY|MODULE_LIBRARY)$")
      continue()
    endif()
    get_target_property(_crt ${_target} MSVC_RUNTIME_LIBRARY)
    get_target_property(_link_options ${_target} LINK_OPTIONS)
    if((_crt AND NOT _crt MATCHES "DLL") OR "/NODEFAULTLIB" IN_LIST _link_options)
      continue()  # static CRT, or no CRT at all (the CRT-free fixtures)
    endif()
    target_sources(${_target} PRIVATE $<TARGET_OBJECTS:gta6rt_crt_timed_wait>)
  endforeach()
endif()
