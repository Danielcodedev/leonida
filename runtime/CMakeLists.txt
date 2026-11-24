cmake_minimum_required(VERSION 3.24)
project(gta6rt LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
  message(FATAL_ERROR "gta6rt must be built for x64 (run from an x64 Native Tools prompt or vcvars64.bat)")
endif()

get_filename_component(LEONIDA_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
find_path(LEONIDA_VK_INCLUDE NAMES vulkan/vulkan.h
  PATHS "${LEONIDA_ROOT}/deps/Vulkan-Headers/include"
        "$ENV{VULKAN_SDK}/Include" "C:/VulkanSDK/*/Include"
        "$ENV{PROGRAMFILES}/VulkanSDK/*/Include")
if(NOT LEONIDA_VK_INCLUDE)
  message(FATAL_ERROR
    "Vulkan headers not found. Install the Vulkan SDK and set VULKAN_SDK, or place Khronos Vulkan-Headers under deps/Vulkan-Headers/include (manual, optional).")
endif()

add_executable(gta6rt
  src/main.cpp
  src/pe_loader.cpp
  src/vk_bootstrap.cpp
  src/d3d12_vk.cpp
  shims/registry.cpp
  shims/xmem.cpp
  shims/d3d12_xs.cpp
)
target_include_directories(gta6rt PRIVATE ${LEONIDA_VK_INCLUDE})
target_compile_definitions(gta6rt PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE)
target_compile_options(gta6rt PRIVATE /W4 /permissive- /utf-8)
# Static shim tables register themselves at startup; keep the linker from dropping their objects.
target_link_options(gta6rt PRIVATE /OPT:NOREF)
target_link_libraries(gta6rt PRIVATE psapi)

add_executable(vk_harness test/vk_harness.cpp)
target_compile_definitions(vk_harness PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_include_directories(vk_harness PRIVATE ${LEONIDA_VK_INCLUDE})

add_executable(vk_bootstrap_test test/vk_bootstrap_test.cpp src/vk_bootstrap.cpp)
target_compile_definitions(vk_bootstrap_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_include_directories(vk_bootstrap_test PRIVATE ${LEONIDA_VK_INCLUDE})
