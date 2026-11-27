#!/usr/bin/env bash
# Run a Windows Leonida build through Proton's Wine inside the Steam Flatpak.
# The game, Windows SDK DLL, Proton installation and derived data stay outside
# this repository. This is a compatibility launcher, not malware isolation.
set -euo pipefail
umask 077

usage() {
    cat <<'EOF'
Usage: ./scripts/run-gta6-linux.sh --game-dir DIR --proton DIR --compiler DLL [options]

Required:
  --game-dir DIR       Your game folder (with MicrosoftGame.config and its exe)
  --proton DIR         Installed Steam Flatpak Proton directory
  --compiler DLL       Native x64 d3dcompiler_47.dll from your Windows SDK

Options:
  --exe EXE            Windows Leonida build (default: target/.../leonida.exe)
  --config FILE        Leonida settings (default: the repository's leonida.toml, if present)
  --vkd3d-dir DIR      x64 DLL folder from a separate vkd3d-proton build
  --state-dir DIR      Prefix, cache and saves (default: ~/.local/share/leonida/proton)
  --read-only-dir DIR  Also expose a symlink target inside Steam Flatpak (repeatable)
  --bind-only          Bind imports without starting the title
  --help               Show this help

The launcher requires Flatpak Steam and a working PulseAudio-compatible socket.
It keeps the title offline, but it does not isolate untrusted executables from
Steam's app data. Use only game files you trust.
EOF
}

fail() {
    printf 'Leonida Linux launcher: %s\n' "$*" >&2
    exit 2
}

require_dir() {
    [[ -d "$2" ]] || fail "$1 is not a directory: $2"
    realpath -e -- "$2"
}

require_file() {
    [[ -f "$2" ]] || fail "$1 is not a file: $2"
    realpath -e -- "$2"
}

require_outside_source() {
    local ancestor=$1
    while :; do
        [[ ! -f "$ancestor/.leonida-root" ]] ||
            fail "$2 must be outside every Leonida source tree: $1"
        [[ "$ancestor" != / ]] || break
        ancestor=$(dirname -- "$ancestor")
    done
}

script_dir=$(dirname -- "$(realpath -e -- "$0")")
repo_dir=$(dirname -- "$script_dir")
game_dir=''
proton_dir=''
compiler=''
exe="$repo_dir/target/x86_64-pc-windows-msvc/release/leonida.exe"
config=''
vkd3d_dir=''
[[ ! -f "$repo_dir/leonida.toml" ]] || config="$repo_dir/leonida.toml"
state_dir="${XDG_DATA_HOME:-$HOME/.local/share}/leonida/proton"
read_only_dirs=()
bind_only=false

while (($#)); do
    case "$1" in
        --game-dir|--proton|--compiler|--exe|--config|--vkd3d-dir|--state-dir|--read-only-dir)
            (($# >= 2)) || fail "$1 needs a path"
            case "$1" in
                --game-dir) game_dir=$2 ;;
                --proton) proton_dir=$2 ;;
                --compiler) compiler=$2 ;;
                --exe) exe=$2 ;;
                --config) config=$2 ;;
                --vkd3d-dir) vkd3d_dir=$2 ;;
                --state-dir) state_dir=$2 ;;
                --read-only-dir) read_only_dirs+=("$2") ;;
            esac
            shift 2
            ;;
        --bind-only) bind_only=true; shift ;;
        --help|-h) usage; exit 0 ;;
        *) fail "unknown option: $1 (see --help)" ;;
    esac
done

[[ -n "$game_dir" && -n "$proton_dir" && -n "$compiler" ]] || {
    usage >&2
    fail 'game folder, Proton directory and native compiler DLL are required'
}
for command in flatpak realpath flock install; do
    command -v "$command" >/dev/null || fail "$command is required"
done
flatpak info com.valvesoftware.Steam >/dev/null 2>&1 ||
    fail 'install the Steam Flatpak (com.valvesoftware.Steam) first'

game_dir=$(require_dir 'game folder' "$game_dir")
proton_dir=$(require_dir 'Proton directory' "$proton_dir")
compiler=$(require_file 'native compiler DLL' "$compiler")
exe=$(require_file 'Leonida executable' "$exe")
require_outside_source "$game_dir" 'game folder'
require_outside_source "$proton_dir" 'Proton directory'
require_outside_source "$compiler" 'native compiler DLL'
manifest_found=false
for manifest in "$game_dir"/*; do
    name=${manifest##*/}
    if [[ -f "$manifest" && "${name,,}" == microsoftgame.config ]]; then
        manifest_found=true
        break
    fi
done
"$manifest_found" ||
    fail "no MicrosoftGame.config in game folder: $game_dir"

wine=$(require_file 'Proton Wine' "$proton_dir/files/bin/wine")
dxgi=$(require_file 'Proton DXVK DXGI' \
    "$proton_dir/files/lib/wine/dxvk/x86_64-windows/dxgi.dll")
if [[ -n "$vkd3d_dir" ]]; then
    vkd3d_dir=$(require_dir 'vkd3d-proton x64 DLL folder' "$vkd3d_dir")
    require_outside_source "$vkd3d_dir" 'vkd3d-proton DLL folder'
    d3d12=$(require_file 'vkd3d-proton D3D12' "$vkd3d_dir/d3d12.dll")
    d3d12core=$(require_file 'vkd3d-proton D3D12Core' "$vkd3d_dir/d3d12core.dll")
else
    d3d12=$(require_file 'Proton vkd3d D3D12' \
        "$proton_dir/files/lib/wine/vkd3d-proton/x86_64-windows/d3d12.dll")
    d3d12core=$(require_file 'Proton vkd3d D3D12Core' \
        "$proton_dir/files/lib/wine/vkd3d-proton/x86_64-windows/d3d12core.dll")
fi
if [[ -n "$config" ]]; then
    config=$(require_file 'Leonida config' "$config")
fi

state_dir=$(realpath -m -- "$state_dir")
require_outside_source "$state_dir" 'state directory'
case "$state_dir/" in
    "$game_dir/"*) fail 'state directory must be separate from the game folder' ;;
esac
case "$game_dir/" in
    "$state_dir/"*) fail 'state directory must be separate from the game folder' ;;
esac
mkdir -p -- "$state_dir"
state_dir=$(require_dir 'state directory' "$state_dir")
for path in "$game_dir" "$proton_dir" "$compiler" "$exe" "$config" "$vkd3d_dir" "$state_dir"; do
    [[ "$path" != *:* ]] || fail "colon in path is unsupported by Flatpak/Wine: $path"
done

for subdir in prefix cache data gpu-cache gpu-logs; do
    [[ ! -L "$state_dir/$subdir" ]] || fail "$subdir directory must not be a symlink"
done
mkdir -p -- "$state_dir/prefix" "$state_dir/cache" "$state_dir/data" \
    "$state_dir/gpu-cache" "$state_dir/gpu-logs"
[[ ! -L "$state_dir/prefix" ]] || fail 'Wine prefix must not be a symlink'
exec 9>"$state_dir/.launch.lock"
flock -n 9 || fail "another run is using $state_dir"

flatpak_args=(
    --unshare=network
    --socket=pulseaudio
    --nofilesystem=home
    --nofilesystem=host
    "--filesystem=$game_dir:ro"
    "--filesystem=$(dirname -- "$exe"):ro"
    "--filesystem=$proton_dir:ro"
    "--filesystem=$state_dir"
    "--env=WINEPREFIX=$state_dir/prefix"
    --env=WINEARCH=win64
    "--env=DXVK_LOG_PATH=$state_dir/gpu-logs"
    "--env=DXVK_STATE_CACHE_PATH=$state_dir/gpu-cache"
    "--env=VKD3D_SHADER_CACHE_PATH=$state_dir/gpu-cache"
)
config_args=()
if [[ -n "$config" ]]; then
    flatpak_args+=("--filesystem=$config:ro")
    config_args+=("--env=LEONIDA_CONFIG=Z:$config")
    local_profiles=$(dirname -- "$config")/gpu-profiles.local.json
    if [[ -f "$local_profiles" ]]; then
        local_profiles=$(require_file 'local graphics profiles' "$local_profiles")
        flatpak_args+=("--filesystem=$local_profiles:ro")
    fi
fi
for path in "${read_only_dirs[@]}"; do
    path=$(require_dir 'additional read-only directory' "$path")
    require_outside_source "$path" 'additional read-only directory'
    [[ "$path" != *:* ]] || fail "colon in path is unsupported by Flatpak: $path"
    flatpak_args+=("--filesystem=$path:ro")
done

# Wine's endpoint APIs can succeed even when Steam's host audio socket is
# absent. Check the socket from inside the actual Flatpak before title launch.
flatpak run "${flatpak_args[@]}" --command=sh com.valvesoftware.Steam -c '
    if ! test -S "$XDG_RUNTIME_DIR/pulse/native"; then
        echo "No PulseAudio-compatible socket inside Steam Flatpak; enable host audio." >&2
        exit 2
    fi
' || fail 'could not confirm an audio socket inside Steam Flatpak; check the error above'

# Directly invoking Proton Wine creates a prefix with Wine built-in graphics
# DLLs. Replace those in this dedicated prefix with Proton's DXVK/vkd3d DLLs
# and the user's native compiler, then force native resolution for this run.
flatpak run "${flatpak_args[@]}" \
    --env=WINEDLLOVERRIDES=winemenubuilder.exe=d \
    --command="$wine" com.valvesoftware.Steam cmd /c exit 0
system32="$state_dir/prefix/drive_c/windows/system32"
[[ -d "$system32" && ! -L "$system32" ]] ||
    fail "Wine did not create a normal system32 directory in $state_dir/prefix"
for spec in "$dxgi:dxgi.dll" "$d3d12:d3d12.dll" \
    "$d3d12core:d3d12core.dll" "$compiler:d3dcompiler_47.dll"; do
    source=${spec%:*}
    name=${spec##*:}
    install -m 0644 -- "$source" "$system32/$name.new.$$"
    mv -f -- "$system32/$name.new.$$" "$system32/$name"
done

run_args=(run)
if ! "$bind_only"; then
    run_args+=(--execute)
fi
cd -- "$game_dir"
unset LEONIDA_CONFIG
flatpak run "${flatpak_args[@]}" \
    "${config_args[@]}" \
    --env='WINEDLLOVERRIDES=winemenubuilder.exe=d;dxgi,d3d12,d3d12core,d3dcompiler_47=n' \
    "--env=LEONIDA_GAME_DIR=Z:$game_dir" \
    "--env=LEONIDA_CACHE_DIR=Z:$state_dir/cache" \
    "--env=LEONIDA_DATA_DIR=Z:$state_dir/data" \
    "--env=LEONIDA_LOG=${LEONIDA_LOG:-warn}" \
    --command="$wine" com.valvesoftware.Steam "$exe" "${run_args[@]}"
