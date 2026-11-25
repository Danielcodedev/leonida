// The runtime's settings: one table, looked up one way.
//
// Every setting has a name in leonida.toml ("section.name"), an environment variable and a default. A value is taken
// from the first of these that has one: the environment variable, the file, the default. The environment is read at
// each call and not cached, so a variable that a test or a launcher sets is seen by the next read. The file is read
// once, by load().
//
// A reader names its setting with a string literal, and the name is checked when the code is compiled:
//
//     if (rt::config::get("vulkan.validation").text != "0") ...
//
// A name that is not in kSettings does not build. A new setting gets a row in kSettings, a line in
// leonida.example.toml (test/core_config_test.cpp compares the two) and a line in a document
// (tests/test_docs_env_vars.py).
//
// Nothing here needs windows.h, so it is built and tested on every OS.
#pragma once

#include <array>
#include <cstddef>
#include <filesystem>
#include <iterator>
#include <optional>
#include <string>
#include <string_view>

namespace rt::config {

struct Setting {
    const char* key;       // "section.name": [section] and name in leonida.toml
    const char* variable;  // the environment variable; when set, it wins over the file
    const char* fallback;  // the default as text; "" when the default is "not set"
};

// The defaults repeat what each reader does when nothing is set. What the values mean is in leonida.example.toml,
// runtime/README.md, docs/gameinput.md and docs/d3d12_vulkan.md.
inline constexpr Setting kSettings[] = {
    {"paths.game_dir", "LEONIDA_GAME_DIR", ""},
    {"paths.save_dir", "LEONIDA_SAVE_DIR", ""},
    {"paths.shaders", "LEONIDA_SHADERS", ""},
    {"paths.compat_dir", "LEONIDA_COMPAT_DIR", ""},

    {"loader.unimplemented", "LEONIDA_UNIMPLEMENTED", "log"},
    {"loader.tls_ga_patch", "LEONIDA_TLS_GA_PATCH", "1"},
    {"loader.skip_cpu_check", "LEONIDA_SKIP_CPU_CHECK", "0"},
    {"loader.skip_int3", "LEONIDA_SKIP_INT3", "0"},
    {"loader.rng_seed", "LEONIDA_RNG_SEED", ""},

    {"log.level", "LEONIDA_LOG", "debug"},  // core/log.h

    {"system.device_type", "LEONIDA_DEVICE_TYPE", "7"},
    {"system.analytics_form", "LEONIDA_ANALYTICS_FORM", ""},
    {"system.package_id", "LEONIDA_PACKAGE_ID", "LeonidaPackageIdentifier00000000"},
    {"system.content_packages", "LEONIDA_CONTENT_PACKAGES", ""},
    {"system.packaged", "LEONIDA_PACKAGED", "1"},
    {"system.gamertag", "LEONIDA_GAMERTAG", "Player"},
    {"system.hdr", "LEONIDA_HDR", "0"},
    {"system.log_game_events", "LEONIDA_LOG_GAME_EVENTS", "0"},

    {"d3d12.backend", "LEONIDA_D3D12", "host"},
    {"d3d12.xs_trace", "XS_TRACE", "0"},
    {"d3d12.frame_interval_slot", "LEONIDA_XS_FRAME_INTERVAL_SLOT", "78"},
    {"d3d12.schedule_event_slot", "LEONIDA_XS_SCHEDULE_EVENT_SLOT", "79"},
    {"d3d12.wait_event_slot", "LEONIDA_XS_WAIT_EVENT_SLOT", "80"},
    {"d3d12.queue_x_slot", "LEONIDA_XS_QUEUE_X_SLOT", "48"},
    {"d3d12.list_x_slot", "LEONIDA_XS_LIST_X_SLOT", "73"},

    {"vulkan.device", "LEONIDA_VK_DEVICE", ""},
    {"vulkan.validation", "LEONIDA_VK_VALIDATION", "0"},
    {"vulkan.max_queues_per_family", "LEONIDA_VK_MAX_QUEUES_PER_FAMILY", "16"},
    {"vulkan.graphics_family_only", "LEONIDA_VK_GRAPHICS_FAMILY_ONLY", "0"},
    {"vulkan.arena_mb", "LEONIDA_ARENA_MB", "256"},
    {"vulkan.arena_log", "LEONIDA_ARENA_LOG", "0"},
    {"vulkan.upload_sysmem", "LEONIDA_UPLOAD_SYSMEM", "0"},
    {"vulkan.bindless_idle_wait", "LEONIDA_BINDLESS_IDLE_WAIT", "0"},
    {"vulkan.rt_as", "LEONIDA_RT_AS", "xdxr"},

    {"present.sdr_eotf", "LEONIDA_SDR_EOTF", "srgb"},
    {"present.uncap", "LEONIDA_PRESENT_UNCAP", "0"},
    {"present.no_tear", "LEONIDA_PRESENT_NO_TEAR", "0"},
    {"present.capture_dir", "LEONIDA_CAPTURE", ""},
    {"present.capture_every", "LEONIDA_CAPTURE_EVERY", "30"},
    {"present.capture_limit", "LEONIDA_CAPTURE_LIMIT", "24"},

    {"input.prompts", "LEONIDA_PROMPTS", "auto"},
    {"input.prompts_switch_ms", "LEONIDA_PROMPTS_SWITCH_MS", "300"},
    {"input.ds_triggers", "LEONIDA_DS_TRIGGERS", "rumble"},
    {"input.ds_trigger_gain", "LEONIDA_DS_TRIGGER_GAIN", "1"},
    {"input.ds_trigger_freq", "LEONIDA_DS_TRIGGER_FREQ", "30"},
    {"input.ds_lightbar", "LEONIDA_DS_LIGHTBAR", ""},
    {"input.rumble", "LEONIDA_RUMBLE", "1"},
    {"input.thread", "LEONIDA_GAMEINPUT_THREAD", "1"},
    {"input.keyboard_pad", "LEONIDA_KEYBOARD_PAD", "off"},
    {"input.mouse_sensitivity", "LEONIDA_MOUSE_SENSITIVITY", "1"},
};
inline constexpr std::size_t kSettingCount = std::size(kSettings);

// The settings file: the one this variable names, else kFileName in the folder of the program (load()).
inline constexpr char kFileVariable[] = "LEONIDA_CONFIG";
inline constexpr char kFileName[] = "leonida.toml";

// The row of kSettings with this key; kSettingCount when there is none.
constexpr std::size_t index_of_key(std::string_view key) {
    for (std::size_t i = 0; i < kSettingCount; ++i)
        if (key == kSettings[i].key) return i;
    return kSettingCount;
}

namespace detail {
// Declared, never defined and not constexpr: Name's constructor reaches it only for a name that is not in kSettings,
// and the compiler reports that as an error at the place that wrote the name.
void this_setting_name_is_not_in_kSettings();
}  // namespace detail

// A setting, by its key. Made from a string literal at compile time, so a misspelt key is a build error and a read
// costs no search.
class Name {
public:
    consteval Name(const char* key) : index_(index_of_key(key)) {
        if (index_ == kSettingCount) detail::this_setting_name_is_not_in_kSettings();
    }

    // For a name that is only known at run time (the file reader, a test): by key or by variable.
    static std::optional<Name> find(std::string_view key_or_variable);
    // The setting in row `index` of kSettings; `index` must be below kSettingCount.
    static constexpr Name at(std::size_t index) { return Name(index, Row{}); }

    constexpr std::size_t index() const { return index_; }
    constexpr const Setting& setting() const { return kSettings[index_]; }

private:
    struct Row {};
    constexpr Name(std::size_t index, Row) : index_(index) {}

    std::size_t index_;
};

enum class Source { Default, File, Environment };

// "default", "file" or "environment".
const char* source_name(Source source);

struct Value {
    std::string text;                 // UTF-8
    Source source = Source::Default;  // where `text` comes from

    // True when the environment or the file gave the value, false when it is the default.
    bool is_set() const { return source != Source::Default; }
};

// The setting's value: the environment variable if it is set and not empty, else what the loaded file says, else the
// default. Safe to call from any thread.
Value get(Name name);

// The same value as a path; empty when the setting is not set.
std::filesystem::path path(Name name);

// What a settings file sets, one entry per row of kSettings.
using FileValues = std::array<std::optional<std::string>, kSettingCount>;

// Reads `text` as a settings file. The format is the part of TOML the file needs: [section] lines, `name = value`
// lines and # comments, where a value is text in single quotes (taken as written) or double quotes (\\ and \" only),
// a number, or true/false (stored as 1/0). A value of '' leaves the setting unset.
//
// A section or name that is not in kSettings, a name set twice and anything else this reader does not take make it
// return false with "<file_name>:<line>: <what>" in *error; *values is then unchanged. A misspelt setting is
// therefore an error and not a setting that silently does nothing.
bool parse(std::string_view text, std::string_view file_name, FileValues* values, std::string* error);

// Reads `file` and makes its values the ones get() falls back on. On failure the values loaded before stay.
bool load_file(const std::filesystem::path& file, std::string* error);

// What gta6rt does at startup: reads the file kFileVariable names (an error if it does not exist), else
// <program_dir>/leonida.toml if there is one. True when there is no file to read.
bool load(const std::filesystem::path& program_dir, std::string* error);

// Forgets the loaded file (tests).
void unload();

// The file whose values are loaded; empty when none is.
std::filesystem::path loaded_file();

// What `gta6rt config` prints: the loaded file, then one line per setting with its key, where its value comes from,
// its variable and the value.
std::string report();

}  // namespace rt::config
