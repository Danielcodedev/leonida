// gta6rt: native runtime for the Xbox Series build.
//
//   gta6rt --dry-run <image> [--game-dir DIR]
//       Maps the image and its bundled modules, applies relocations, binds every import and prints a report.
//       No code from the image runs.
#include <windows.h>

#include <cstdio>
#include <map>
#include <string>

#include "d3d12_vk.h"
#include "pe_loader.h"
#include "vk_bootstrap.h"

namespace {

const char* binding_name(rt::Binding b) {
    switch (b) {
        case rt::Binding::Shim: return "shim";
        case rt::Binding::Host: return "host";
        case rt::Binding::Module: return "module";
        default: return "UNIMPLEMENTED";
    }
}

int usage() {
    std::fprintf(stderr, "usage: gta6rt --dry-run <image> [--game-dir DIR]\n"
                          "       gta6rt --self-test [--game-dir DIR]\n");
    return 2;
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
    std::filesystem::path image, game_dir;
    bool dry_run = false;
    bool self_test = false;
    for (int i = 1; i < argc; ++i) {
        std::wstring a = argv[i];
        if (a == L"--dry-run") dry_run = true;
        else if (a == L"--self-test") self_test = true;
        else if (a == L"--game-dir" && i + 1 < argc) game_dir = argv[++i];
        else if (image.empty()) image = a;
        else return usage();
    }
    if (self_test) {
        wchar_t self[MAX_PATH];
        DWORD n = GetModuleFileNameW(nullptr, self, MAX_PATH);
        if (!n) return 1;
        image = self;
        dry_run = true;
    }
    if (image.empty()) return usage();
    if (!dry_run) {
        std::fprintf(stderr,
                     "Only --dry-run and --self-test exist so far: running game code needs the shims listed by it "
                     "first.\n");
        return 2;
    }
    if (game_dir.empty()) game_dir = image.parent_path();

    if (self_test) {
        const bool vk = rt::d3d12_vk::ensure_graphics_backend();
        std::printf("self-test: Vulkan graphics backend %s\n",
                    vk ? "ready" : "unavailable (see vk_bootstrap_test or install GPU Vulkan drivers)");
    }

    try {
        rt::Loader loader(game_dir);
        loader.load(image);
        int unimplemented = 0;
        for (auto* m : loader.modules()) {
            std::map<rt::Binding, int> counts;
            for (auto& r : m->imports) counts[r.binding]++;
            std::printf("%-36s base=%p%s size=%u entry=+%#x  shim=%d host=%d module=%d unimplemented=%d\n",
                        m->name.c_str(), m->base, m->relocated ? " (relocated)" : "", m->size, m->entry_rva,
                        counts[rt::Binding::Shim], counts[rt::Binding::Host], counts[rt::Binding::Module],
                        counts[rt::Binding::Unimplemented]);
            for (auto& r : m->imports)
                if (r.binding == rt::Binding::Unimplemented || r.binding == rt::Binding::Shim) {
                    std::printf("    %-13s %s!%s\n", binding_name(r.binding), r.dll.c_str(), r.name.c_str());
                    unimplemented += r.binding == rt::Binding::Unimplemented;
                }
        }
        std::printf("%zu module(s) mapped, %d unimplemented import(s)\n", loader.modules().size(), unimplemented);
        return 0;
    } catch (const std::exception& e) {
        std::fprintf(stderr, "error: %s\n", e.what());
        return 1;
    }
}
