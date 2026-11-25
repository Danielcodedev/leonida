// rt::log (core/log.h): the level the setting log.level asks for.
#include "log.h"

#include "config.h"

namespace rt::log {

Level level_from_settings(std::string* warning) {
    if (warning) warning->clear();
    constexpr rt::config::Name setting("log.level");
    const std::string text = rt::config::get(setting).text;
    if (const std::optional<Level> named = parse_level(text)) return *named;
    // The variable is named also when the value came from the file, as the other readers do.
    if (warning)
        *warning = std::string("log: ") + setting.setting().variable + "=" + text + " unknown (" + kLevelList +
                   "), using " + level_name(kDefaultLevel);
    return kDefaultLevel;
}

void apply_settings(bool print_warning) {
    std::string warning;
    set_level(level_from_settings(&warning));
    // With a warning the level in use is the default, which lets warnings through.
    if (print_warning && !warning.empty()) RT_LOG_WARN("%s\n", warning.c_str());
}

}  // namespace rt::log
