// Skeleton bridge: Xbox D3D12 will record into Vulkan command buffers here later.
#pragma once

namespace rt::d3d12_vk {

// Called when graphics shims first need a Vulkan device.
bool ensure_graphics_backend();

bool graphics_ready();

}  // namespace rt::d3d12_vk