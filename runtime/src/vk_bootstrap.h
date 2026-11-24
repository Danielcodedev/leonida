// Lazy Vulkan 1.2 instance + one graphics device (dynamic vulkan-1.dll load).
// Shared by the GPU test harness and the DXGI/D3D12 bridge skeleton.
#pragma once

#include <cstdint>

namespace rt::vk_bootstrap {

// Creates instance and device on first call. Returns false if vulkan-1.dll is missing.
bool init();

// Non-owning handles; valid after a successful init().
void* instance();
void* physical_device();
void* device();
uint32_t graphics_queue_family();

void shutdown();

}  // namespace rt::vk_bootstrap