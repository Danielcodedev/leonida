// rt::log (core/log.h): which lines each level lets through, the "[rt] " prefix, that a line held back evaluates
// none of its arguments, a value that is not a level, and the order environment > file > default of log.level
// (LEONIDA_LOG), where an empty variable falls through to the file. No game files.
#include "../core/log.h"

#include "../core/config.h"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iterator>
#include <string>
#include <string_view>
#include <system_error>

#if defined(_WIN32)
#include <io.h>
#include <windows.h>
#else
#include <unistd.h>
#endif

namespace {

namespace config = rt::config;
namespace rtlog = rt::log;
using rtlog::Level;

constexpr Level kLevels[] = {Level::Off, Level::Error, Level::Warn, Level::Info, Level::Debug, Level::Trace};

// A level is named in any case; nothing else is a level.
static_assert(rtlog::parse_level("off") == Level::Off && rtlog::parse_level("trace") == Level::Trace);
static_assert(rtlog::parse_level("WARN") == Level::Warn && rtlog::parse_level("Debug") == Level::Debug);
static_assert(!rtlog::parse_level("") && !rtlog::parse_level("warning") && !rtlog::parse_level("warn ") &&
              !rtlog::parse_level("1"));

int g_failures = 0;

void expect(bool ok, const std::string& what) {
    if (ok) return;
    std::fprintf(stderr, "FAIL: %s\n", what.c_str());
    ++g_failures;
}

bool contains(std::string_view text, std::string_view part) { return text.find(part) != std::string_view::npos; }

// Sets (value) or removes (nullptr) an environment variable of this process.
void set_env(const char* name, const char* value) {
#if defined(_WIN32)
    SetEnvironmentVariableA(name, value);
#else
    if (value)
        setenv(name, value, 1);
    else
        unsetenv(name);
#endif
}

void write_file(const std::filesystem::path& file, std::string_view text) {
    std::ofstream out(file, std::ios::binary);
    out.write(text.data(), static_cast<std::streamsize>(text.size()));
}

#if defined(_WIN32)
int dup_fd(int fd) { return _dup(fd); }
int dup2_fd(int from, int to) { return _dup2(from, to); }
void close_fd(int fd) { _close(fd); }
int fd_of(std::FILE* stream) { return _fileno(stream); }
std::FILE* open_for_writing(const std::filesystem::path& file) {
    std::FILE* out = nullptr;
    if (_wfopen_s(&out, file.c_str(), L"wb") != 0) return nullptr;  // wide: a TEMP outside the ANSI code page
    return out;
}
#else
int dup_fd(int fd) { return dup(fd); }
int dup2_fd(int from, int to) { return dup2(from, to); }
void close_fd(int fd) { close(fd); }
int fd_of(std::FILE* stream) { return fileno(stream); }
std::FILE* open_for_writing(const std::filesystem::path& file) { return std::fopen(file.c_str(), "wb"); }
#endif

// What `body` writes to stderr, without carriage returns. *redirected is false when stderr could not be sent to
// `file`; the text is then empty, which must not read as "nothing was printed".
std::string stderr_of(const std::filesystem::path& file, bool* redirected, const std::function<void()>& body) {
    *redirected = false;
    std::fflush(stderr);
    const int stderr_fd = fd_of(stderr);
    const int saved = dup_fd(stderr_fd);
    std::FILE* out = open_for_writing(file);
    if (out && saved >= 0) *redirected = dup2_fd(fd_of(out), stderr_fd) >= 0;
    if (out) std::fclose(out);
    if (*redirected) body();
    std::fflush(stderr);
    if (saved >= 0) {
        if (*redirected) dup2_fd(saved, stderr_fd);
        close_fd(saved);
    }
    if (!*redirected) return {};
    std::ifstream in(file, std::ios::binary);
    std::string text{std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>()};
    std::erase(text, '\r');
    return text;
}

void test_levels() {
    expect(rtlog::level() == rtlog::kDefaultLevel, "a program that sets no level logs at the default");
    expect(rtlog::kDefaultLevel == Level::Debug,
           "the default lets every line through but trace lines, which is what was printed before the levels");
    for (const Level in_use : kLevels) {
        const std::string name = rtlog::level_name(in_use);
        rtlog::set_level(in_use);
        expect(rtlog::level() == in_use, "set_level(" + name + ") is the level in use");
        for (const Level line : kLevels) {
            const bool want = line != Level::Off && static_cast<int>(line) <= static_cast<int>(in_use);
            expect(rtlog::enabled(line) == want, "at " + name + ", a line of level " + rtlog::level_name(line) +
                                                     (want ? " is printed" : " is held back"));
        }
        const auto named = rtlog::parse_level(name);
        expect(named && *named == in_use, name + " is read back from its name");
        expect(contains(rtlog::kLevelList, name), "the list a warning shows names " + name);
    }
    rtlog::set_level(rtlog::kDefaultLevel);
}

void test_output(const std::filesystem::path& dir) {
    int evaluated = 0;
    const auto number = [&](int value) {
        ++evaluated;
        return value;
    };
    const auto all_five = [&] {
        RT_LOG_ERROR("log_test: error %d\n", number(1));
        RT_LOG_WARN("log_test: warn %d\n", number(2));
        RT_LOG_INFO("log_test: info %s %d\n", "text", number(3));
        RT_LOG_DEBUG("log_test: debug %d\n", number(4));
        RT_LOG_TRACE("log_test: trace %d\n", number(5));
        RT_LOG_ERROR("log_test: no arguments\n");
    };
    struct Case {
        Level in_use;
        const char* text;
        int evaluated;
    };
    const Case cases[] = {
        {Level::Off, "", 0},
        {Level::Error, "[rt] log_test: error 1\n[rt] log_test: no arguments\n", 1},
        {Level::Warn, "[rt] log_test: error 1\n[rt] log_test: warn 2\n[rt] log_test: no arguments\n", 2},
        {Level::Info,
         "[rt] log_test: error 1\n[rt] log_test: warn 2\n[rt] log_test: info text 3\n"
         "[rt] log_test: no arguments\n",
         3},
        {Level::Debug,
         "[rt] log_test: error 1\n[rt] log_test: warn 2\n[rt] log_test: info text 3\n[rt] log_test: debug 4\n"
         "[rt] log_test: no arguments\n",
         4},
        {Level::Trace,
         "[rt] log_test: error 1\n[rt] log_test: warn 2\n[rt] log_test: info text 3\n[rt] log_test: debug 4\n"
         "[rt] log_test: trace 5\n[rt] log_test: no arguments\n",
         5},
    };
    for (const Case& c : cases) {
        const std::string name = rtlog::level_name(c.in_use);
        rtlog::set_level(c.in_use);
        evaluated = 0;
        bool redirected = false;
        const std::string text = stderr_of(dir / "output.txt", &redirected, all_five);
        expect(redirected, "at " + name + ": stderr can be sent to a file");
        if (!redirected) continue;
        expect(text == c.text,
               "at " + name + " the lines printed are its own, each with the [rt] prefix; got \"" + text + "\"");
        expect(evaluated == c.evaluated,
               "at " + name + " a line held back evaluates none of its arguments (" + std::to_string(evaluated) +
                   " evaluated, expected " + std::to_string(c.evaluated) + ")");
    }
    rtlog::set_level(rtlog::kDefaultLevel);
}

void test_settings(const std::filesystem::path& dir) {
    constexpr config::Name setting("log.level");
    const char* const variable = setting.setting().variable;
    expect(std::string_view(variable) == "LEONIDA_LOG", "log.level is set by LEONIDA_LOG");
    expect(std::string_view(setting.setting().fallback) == rtlog::level_name(rtlog::kDefaultLevel),
           "the default in kSettings is the default of the log");

    // environment > file > default
    std::string warning = "left over";
    const auto asked = [&] { return rtlog::level_from_settings(&warning); };
    expect(asked() == rtlog::kDefaultLevel && warning.empty(), "nothing set: the default, and no warning");

    const std::filesystem::path file = dir / "log.toml";
    write_file(file, "[log]\nlevel = 'warn'\n");
    std::string error;
    expect(config::load_file(file, &error), "a file that sets log.level is read: " + error);
    expect(asked() == Level::Warn && warning.empty(), "set in the file: the file's level");

    set_env(variable, "error");
    expect(asked() == Level::Error && warning.empty(), "the variable wins over the file");
    const std::string report = config::report();
    const std::size_t at = report.find("\nlog.level ");
    std::string_view line;
    if (at != std::string::npos) {
        line = std::string_view(report).substr(at + 1);
        line = line.substr(0, line.find('\n'));
    }
    expect(contains(line, " environment ") && contains(line, " LEONIDA_LOG ") && line.ends_with(" error"),
           "the report (`gta6rt config`) shows log.level with its source, variable and value; the line was \"" +
               std::string(line) + "\"");
    set_env(variable, "TRACE");
    expect(asked() == Level::Trace && warning.empty(), "a level is named in any case");
    set_env(variable, "");
    expect(asked() == Level::Warn && warning.empty(), "an empty variable falls through to the file");
    set_env(variable, nullptr);
    expect(asked() == Level::Warn && warning.empty(), "the variable removed: the file's level again");

    // A value that is not a level: the default, and one warning that lists the levels.
    set_env(variable, "loud");
    const std::string want = "log: LEONIDA_LOG=loud unknown (off, error, warn, info, debug or trace), using debug";
    Level got = asked();
    expect(got == rtlog::kDefaultLevel && warning == want,
           "an unknown value gives the default and a warning that lists the levels; the warning was \"" + warning +
               "\"");
    expect(rtlog::level_from_settings() == rtlog::kDefaultLevel, "the warning is optional");
    set_env(variable, nullptr);
    write_file(file, "[log]\nlevel = 'verbose'\n");
    expect(config::load_file(file, &error), "a file with an unknown level is still a file in the format: " + error);
    got = asked();
    expect(got == rtlog::kDefaultLevel && contains(warning, "LEONIDA_LOG=verbose "),
           "an unknown value from the file gives the default too and names the variable; the warning was \"" +
               warning + "\"");
    config::unload();
    expect(asked() == rtlog::kDefaultLevel && warning.empty(), "the file forgotten: the default again");

    // apply_settings() makes it the level in use and prints the warning once, as a log line.
    bool redirected = false;
    rtlog::set_level(Level::Off);  // the warning is printed although the level before was off
    set_env(variable, "loud");
    std::string text = stderr_of(dir / "apply.txt", &redirected, [] { rtlog::apply_settings(); });
    expect(redirected, "stderr can be sent to a file");
    if (redirected)
        expect(text == "[rt] " + want + "\n", "apply_settings() prints the warning once; got \"" + text + "\"");
    expect(rtlog::level() == rtlog::kDefaultLevel, "apply_settings() with an unknown value: the default is in use");

    rtlog::set_level(Level::Off);
    text = stderr_of(dir / "apply.txt", &redirected, [] { rtlog::apply_settings(false); });
    expect(redirected && text.empty() && rtlog::level() == rtlog::kDefaultLevel,
           "apply_settings(false) uses the default for an unknown value without printing; got \"" + text + "\"");

    set_env(variable, "off");
    text = stderr_of(dir / "apply.txt", &redirected, [] {
        rtlog::apply_settings();
        RT_LOG_ERROR("log_test: must not be printed\n");
    });
    expect(redirected && text.empty() && rtlog::level() == Level::Off,
           "LEONIDA_LOG=off: apply_settings() prints nothing and no line follows; got \"" + text + "\"");

    set_env(variable, "warn");
    text = stderr_of(dir / "apply.txt", &redirected, [] {
        rtlog::apply_settings();
        RT_LOG_WARN("log_test: kept\n");
        RT_LOG_INFO("log_test: held back\n");
    });
    expect(redirected && text == "[rt] log_test: kept\n" && rtlog::level() == Level::Warn,
           "LEONIDA_LOG=warn: warnings are printed, info lines are not; got \"" + text + "\"");

    set_env(variable, nullptr);
    rtlog::apply_settings();
    expect(rtlog::level() == rtlog::kDefaultLevel, "nothing set: apply_settings() goes back to the default");
}

}  // namespace

int main() {
    // The settings of whoever runs this must not decide its result.
    for (const config::Setting& setting : config::kSettings) set_env(setting.variable, nullptr);
    set_env(config::kFileVariable, nullptr);

    std::error_code failed;
    const auto now = std::chrono::steady_clock::now().time_since_epoch().count();
    const std::filesystem::path dir =
        std::filesystem::temp_directory_path(failed) / ("leonida_core_log_test_" + std::to_string(now));
    std::filesystem::create_directories(dir, failed);
    expect(!failed, "the scratch folder can be made");

    test_levels();
    test_output(dir);
    test_settings(dir);

    std::filesystem::remove_all(dir, failed);
    if (g_failures) {
        std::fprintf(stderr, "%d check(s) failed\n", g_failures);
        return 1;
    }
    std::puts("core_log_test: ok");
    return 0;
}
