#include "vk_bootstrap.h"

#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>

#include <windows.h>

#include <cstdio>
#include <vector>

namespace rt::vk_bootstrap {
namespace {

HMODULE lib = nullptr;
PFN_vkGetInstanceProcAddr gipa = nullptr;
VkInstance inst = VK_NULL_HANDLE;
VkPhysicalDevice pd = VK_NULL_HANDLE;
VkDevice dev = VK_NULL_HANDLE;
uint32_t queue_family = 0;
bool tried = false;
bool ok = false;

bool check(VkResult r, const char* what) {
    if (r == VK_SUCCESS) return true;
    std::fprintf(stderr, "[vk_bootstrap] %s failed (%d)\n", what, int(r));
    return false;
}

}  // namespace

bool init() {
    if (tried) return ok;
    tried = true;
    lib = LoadLibraryW(L"C:\\Windows\\System32\\vulkan-1.dll");
    if (!lib) lib = LoadLibraryA("vulkan-1.dll");
    if (!lib) {
        std::fprintf(stderr, "[vk_bootstrap] vulkan-1.dll not found\n");
        return false;
    }
    gipa = reinterpret_cast<PFN_vkGetInstanceProcAddr>(GetProcAddress(lib, "vkGetInstanceProcAddr"));
    if (!gipa) return false;

    auto vkCreateInstance = reinterpret_cast<PFN_vkCreateInstance>(gipa(nullptr, "vkCreateInstance"));
    auto vkEnumeratePhysicalDevices =
        reinterpret_cast<PFN_vkEnumeratePhysicalDevices>(gipa(nullptr, "vkEnumeratePhysicalDevices"));
    auto vkGetPhysicalDeviceProperties =
        reinterpret_cast<PFN_vkGetPhysicalDeviceProperties>(gipa(nullptr, "vkGetPhysicalDeviceProperties"));
    auto vkGetPhysicalDeviceQueueFamilyProperties = reinterpret_cast<PFN_vkGetPhysicalDeviceQueueFamilyProperties>(
        gipa(nullptr, "vkGetPhysicalDeviceQueueFamilyProperties"));
    auto vkCreateDevice = reinterpret_cast<PFN_vkCreateDevice>(gipa(nullptr, "vkCreateDevice"));
    if (!vkCreateInstance || !vkEnumeratePhysicalDevices || !vkGetPhysicalDeviceProperties ||
        !vkGetPhysicalDeviceQueueFamilyProperties || !vkCreateDevice)
        return false;

    VkApplicationInfo app{VK_STRUCTURE_TYPE_APPLICATION_INFO};
    app.pApplicationName = "Leonida Legacy";
    app.applicationVersion = 1;
    app.apiVersion = VK_API_VERSION_1_2;
    VkInstanceCreateInfo ici{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
    ici.pApplicationInfo = &app;
    VkResult cr = vkCreateInstance(&ici, nullptr, &inst);
    if (cr != VK_SUCCESS) {
        app.apiVersion = VK_API_VERSION_1_0;
        cr = vkCreateInstance(&ici, nullptr, &inst);
    }
    if (!check(cr, "vkCreateInstance")) return false;

    vkEnumeratePhysicalDevices =
        reinterpret_cast<PFN_vkEnumeratePhysicalDevices>(gipa(inst, "vkEnumeratePhysicalDevices"));
    vkGetPhysicalDeviceProperties =
        reinterpret_cast<PFN_vkGetPhysicalDeviceProperties>(gipa(inst, "vkGetPhysicalDeviceProperties"));
    vkGetPhysicalDeviceQueueFamilyProperties = reinterpret_cast<PFN_vkGetPhysicalDeviceQueueFamilyProperties>(
        gipa(inst, "vkGetPhysicalDeviceQueueFamilyProperties"));
    vkCreateDevice = reinterpret_cast<PFN_vkCreateDevice>(gipa(inst, "vkCreateDevice"));

    uint32_t n = 0;
    vkEnumeratePhysicalDevices(inst, &n, nullptr);
    if (n == 0) {
        std::fprintf(stderr,
                     "[vk_bootstrap] no physical devices (GPU Vulkan driver or Lavapipe via VULKAN_SDK)\n");
        return false;
    }
    std::vector<VkPhysicalDevice> pds(n);
    vkEnumeratePhysicalDevices(inst, &n, pds.data());
    for (auto d : pds) {
        VkPhysicalDeviceProperties p{};
        vkGetPhysicalDeviceProperties(d, &p);
        if (p.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU || !pd) pd = d;
    }
    if (!pd) return false;

    uint32_t qn = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(pd, &qn, nullptr);
    std::vector<VkQueueFamilyProperties> qf(qn);
    vkGetPhysicalDeviceQueueFamilyProperties(pd, &qn, qf.data());
    queue_family = 0;
    while (queue_family < qn && !(qf[queue_family].queueFlags & VK_QUEUE_GRAPHICS_BIT)) queue_family++;
    if (queue_family >= qn) return false;

    float prio = 1.f;
    VkDeviceQueueCreateInfo qci{VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
    qci.queueFamilyIndex = queue_family;
    qci.queueCount = 1;
    qci.pQueuePriorities = &prio;
    VkDeviceCreateInfo dci{VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
    dci.queueCreateInfoCount = 1;
    dci.pQueueCreateInfos = &qci;
    if (!check(vkCreateDevice(pd, &dci, nullptr, &dev), "vkCreateDevice")) return false;

    ok = true;
    return true;
}

void* instance() { return inst; }
void* physical_device() { return pd; }
void* device() { return dev; }
uint32_t graphics_queue_family() { return queue_family; }

void shutdown() {
    if (dev) {
        auto vkDestroyDevice =
            reinterpret_cast<PFN_vkDestroyDevice>(gipa(inst, "vkDestroyDevice"));
        if (vkDestroyDevice) vkDestroyDevice(dev, nullptr);
        dev = VK_NULL_HANDLE;
    }
    if (inst) {
        auto vkDestroyInstance =
            reinterpret_cast<PFN_vkDestroyInstance>(gipa(nullptr, "vkDestroyInstance"));
        if (vkDestroyInstance) vkDestroyInstance(inst, nullptr);
        inst = VK_NULL_HANDLE;
    }
    if (lib) {
        FreeLibrary(lib);
        lib = nullptr;
    }
    gipa = nullptr;
    tried = false;
    ok = false;
    pd = VK_NULL_HANDLE;
}

}  // namespace rt::vk_bootstrap