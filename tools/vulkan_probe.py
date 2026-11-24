"""Optional: print Vulkan SDK path and whether Lavapipe ICD is visible (no downloads)."""
import sys

from vulkan_env import lavapipe_icd_json, prepare_icd_env, sdk_root


def main() -> int:
    sdk = sdk_root()
    print(f"VULKAN_SDK (resolved): {sdk or '(not set)'}")
    if sdk:
        icd = lavapipe_icd_json(sdk)
        print(f"Lavapipe ICD: {icd or '(not in SDK)'}")
        if prepare_icd_env():
            print("VK_ICD_FILENAMES set for Lavapipe/SwiftShader")
    return 0 if sdk else 1


if __name__ == "__main__":
    sys.exit(main())