"""End-of-build verification for the Leonida runtime (PE loader, Vulkan, optional GPU shader draw).

Called automatically from make_game.py after the runtime stage. Does not download dependencies.
"""
from __future__ import annotations

import argparse
import glob
import os
import struct
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUNTIME_BUILD = os.path.join(ROOT, "runtime", "build")
SCRIPTS = os.path.join(ROOT, "scripts")

sys.path.insert(0, os.path.dirname(__file__))
from vulkan_env import prepare_icd_env, sdk_root  # noqa: E402


def fail(msg: str) -> None:
    print(f"\nERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def run_checked(args: list[str], what: str) -> None:
    r = subprocess.run([str(a) for a in args])
    if r.returncode != 0:
        fail(f"{what} failed (exit {r.returncode})")


def build_runtime() -> None:
    ps1 = os.path.join(SCRIPTS, "build_runtime.ps1")
    if not os.path.isfile(ps1):
        fail(f"missing {ps1}")
    run_checked(
        ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ps1],
        "build_runtime.ps1",
    )


def exe(name: str) -> str:
    path = os.path.join(RUNTIME_BUILD, name)
    if not os.path.isfile(path):
        fail(f"missing {path} (build the runtime first)")
    return path


def verify_pe_loader() -> None:
    run_checked([exe("gta6rt.exe"), "--self-test"], "gta6rt --self-test")


def verify_vulkan() -> None:
    sdk = sdk_root()
    if sdk:
        print(f"Vulkan SDK: {sdk}")
    else:
        print("Vulkan SDK: not found on PATH (set VULKAN_SDK if headers/tools are installed)")
    prepare_icd_env()
    run_checked([exe("vk_bootstrap_test.exe")], "vk_bootstrap_test")


def find_shader_pair(spirv_dir: str) -> tuple[str, str]:
    def pick(patterns: list[str]) -> str:
        for pat in patterns:
            hits = sorted(glob.glob(os.path.join(spirv_dir, pat)))
            if hits:
                return hits[0]
        return ""

    vs = pick(["VS_Passthrough*.spv", "VS_*.spv"])
    ps = pick(["PS_Passthrough*.spv", "PS_PassthroughCopy*.spv", "PS_*.spv"])
    if not vs or not ps:
        n = len(glob.glob(os.path.join(spirv_dir, "*.spv")))
        fail(f"need a VS and PS .spv in {spirv_dir} ({n} files); finish the shaders stage first")
    return vs, ps


def verify_gpu_draw(work: str) -> None:
    spirv = os.path.join(work, "shaders", "spirv")
    if not os.path.isdir(spirv):
        fail(f"shader output missing: {spirv}")
    vs, ps = find_shader_pair(spirv)
    out = os.path.join(work, "verify", "gpu_smoke.raw")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    run_checked([exe("vk_harness.exe"), vs, ps, out, "64", "64"], "vk_harness")
    with open(out, "rb") as f:
        data = f.read()
    if len(data) < 64 * 64 * 16:
        fail("GPU smoke: output too small")
    # Harness clears to -1; any other float means something was drawn.
    for off in range(0, min(len(data), 4096), 4):
        if struct.unpack("<f", data[off:off + 4])[0] != -1.0:
            print(f"GPU smoke: ok ({os.path.basename(vs)} + {os.path.basename(ps)})")
            return
    fail("GPU smoke: only clear pixels (shader pipeline did not run)")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--work", required=True, help="build work directory (contains shaders/spirv after shader stage)")
    ap.add_argument("--require-gpu", action="store_true", help="require vk_harness draw (full build with shaders)")
    ap.add_argument("--skip-build", action="store_true", help="assume runtime/build already exists")
    a = ap.parse_args()
    work = os.path.abspath(a.work)
    if not a.skip_build:
        build_runtime()
    verify_pe_loader()
    verify_vulkan()
    if a.require_gpu:
        verify_gpu_draw(work)
    print("verify_build: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())