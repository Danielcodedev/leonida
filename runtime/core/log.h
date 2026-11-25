// The runtime's log: the "[rt] ..." lines on stderr, each with a level.
//
//     RT_LOG_WARN("gameinput: LEONIDA_PROMPTS=%s unknown\n", text.c_str());
//
// prints "[rt] gameinput: LEONIDA_PROMPTS=... unknown" when the level in use lets warnings through. The first
// argument is a string literal, "<module>: <text>\n" by convention. The macro puts "[rt] " in front of it and hands
// the rest to std::fprintf as written, so the compiler still checks the arguments against the format, a line is one
// fprintf call as it was before the levels, and a line that is held back evaluates none of its arguments.
//
// The levels, in order: off, error, warn, info, debug, trace. A line is printed when its level is at or below the
// level in use. The default is debug: it prints every line the runtime printed before it had levels, and holds
// back only trace lines. There is one level for all modules; a form such as "warn,gameinput=debug" is not read.
//
// The level in use is one value per program. It starts at the default. gta6rt sets it once at startup from the
// setting log.level (LEONIDA_LOG) with apply_settings(). That function and level_from_settings() are in
// core/log.cpp and need gta6rt_core. Everything else is in this header and needs neither gta6rt_core nor windows.h,
// so a header that logs and a test that links no library can include it. A program that does not call
// apply_settings() logs at the default.
#pragma once

#include <atomic>
#include <cstddef>
#include <cstdio>
#include <optional>
#include <string>
#include <string_view>

namespace rt::log {

enum class Level : int { Off, Error, Warn, Info, Debug, Trace };

inline constexpr Level kDefaultLevel = Level::Debug;
// The values log.level takes, as a warning lists them.
inline constexpr char kLevelList[] = "off, error, warn, info, debug or trace";

constexpr const char* level_name(Level level) {
    switch (level) {
        case Level::Off: return "off";
        case Level::Error: return "error";
        case Level::Warn: return "warn";
        case Level::Info: return "info";
        case Level::Debug: return "debug";
        case Level::Trace: return "trace";
    }
    return "?";
}

// The level `text` names, in any case; nullopt for anything else, also for an empty text.
constexpr std::optional<Level> parse_level(std::string_view text) {
    constexpr Level all[] = {Level::Off, Level::Error, Level::Warn, Level::Info, Level::Debug, Level::Trace};
    for (const Level level : all) {
        const std::string_view name = level_name(level);
        if (name.size() != text.size()) continue;
        bool same = true;
        for (std::size_t i = 0; i < name.size(); ++i) {
            const char c = text[i];
            if ((c >= 'A' && c <= 'Z' ? static_cast<char>(c - 'A' + 'a') : c) != name[i]) same = false;
        }
        if (same) return level;
    }
    return std::nullopt;
}

namespace detail {
inline std::atomic<int> g_level{static_cast<int>(kDefaultLevel)};
}  // namespace detail

// The level in use. Safe to call from any thread.
inline Level level() { return static_cast<Level>(detail::g_level.load(std::memory_order_relaxed)); }
inline void set_level(Level level) { detail::g_level.store(static_cast<int>(level), std::memory_order_relaxed); }

// True when a line of `line_level` is printed at the level in use. Off is not a level a line has: nothing is
// printed for it.
inline bool enabled(Level line_level) {
    return line_level != Level::Off &&
           static_cast<int>(line_level) <= detail::g_level.load(std::memory_order_relaxed);
}

// ---- in core/log.cpp (gta6rt_core) ----

// The level the setting log.level asks for (core/config.h: its variable if set and not empty, else leonida.toml,
// else the default). A value that is not a level gives the default; *warning is then the line that says so, without
// "[rt] " and without a line break, and is empty otherwise.
Level level_from_settings(std::string* warning = nullptr);

// Makes that level the level in use. A value that is not a level is reported once, as the line
// "[rt] log: ..."; print_warning false leaves that line out, for a program whose parent already printed it.
void apply_settings(bool print_warning = true);

}  // namespace rt::log

// The first of the variable arguments is the format, a string literal.
#define RT_LOG_AT(level, ...)                                                           \
    (::rt::log::enabled(level) ? static_cast<void>(std::fprintf(stderr, "[rt] " __VA_ARGS__)) \
                               : static_cast<void>(0))
#define RT_LOG_ERROR(...) RT_LOG_AT(::rt::log::Level::Error, __VA_ARGS__)
#define RT_LOG_WARN(...) RT_LOG_AT(::rt::log::Level::Warn, __VA_ARGS__)
#define RT_LOG_INFO(...) RT_LOG_AT(::rt::log::Level::Info, __VA_ARGS__)
#define RT_LOG_DEBUG(...) RT_LOG_AT(::rt::log::Level::Debug, __VA_ARGS__)
#define RT_LOG_TRACE(...) RT_LOG_AT(::rt::log::Level::Trace, __VA_ARGS__)
