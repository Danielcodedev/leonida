#include "d3d12_vk.h"

#include "vk_bootstrap.h"

namespace rt::d3d12_vk {

bool ensure_graphics_backend() { return vk_bootstrap::init(); }

bool graphics_ready() { return vk_bootstrap::device() != nullptr; }

}  // namespace rt::d3d12_vk