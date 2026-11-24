#include "../src/vk_bootstrap.h"

#include <cstdio>

int main() {
    if (!rt::vk_bootstrap::init()) {
        std::fprintf(stderr, "vk_bootstrap_test: failed (see [vk_bootstrap] lines above)\n");
        return 1;
    }
    std::fprintf(stderr, "vk_bootstrap_test: ok (instance + device)\n");
    rt::vk_bootstrap::shutdown();
    return 0;
}