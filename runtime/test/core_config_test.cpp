// rt::config (core/config.h): the shape of the table, the order environment > file > default, the file reader and
// what it refuses, the file load() picks, the report, and leonida.example.toml against the table. No game files.
//
//     core_config_test <path to runtime/leonida.example.toml>
#include "../core/config.h"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <set>
#include <string>
#include <string_view>
#include <system_error>

#if defined(_WIN32)
#include <windows.h>
#endif

namespace {

namespace config = rt::config;

// A key that is in the table builds and names its row. One that is not does not build (Name's constructor), which
// a test that has to build cannot show; index_of_key is what that constructor asks.
static_assert(config::Name("paths.game_dir").index() == 0);
static_assert(config::Name("input.mouse_sensitivity").index() == config::kSettingCount - 1);
static_assert(config::index_of_key("vulkan.no_such_setting") == config::kSettingCount);

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

void set_env_path(const char* name, const std::filesystem::path& value) {
#if defined(_WIN32)
    std::wstring wide_name;
    for (const char* c = name; *c; ++c) wide_name.push_back(static_cast<wchar_t>(*c));
    SetEnvironmentVariableW(wide_name.c_str(), value.c_str());
#else
    setenv(name, value.c_str(), 1);
#endif
}

void write_file(const std::filesystem::path& file, std::string_view text) {
    std::ofstream out(file, std::ios::binary);
    out.write(text.data(), static_cast<std::streamsize>(text.size()));
}

// What `values` holds for `key`; "<unset>" when the file did not set it.
std::string file_value(const config::FileValues& values, std::string_view key) {
    const std::size_t index = config::index_of_key(key);
    if (index == config::kSettingCount) return "<no such key>";
    return values[index] ? *values[index] : "<unset>";
}

void test_table() {
    std::set<std::string_view> keys, variables;
    for (std::size_t i = 0; i < config::kSettingCount; ++i) {
        const config::Setting& setting = config::kSettings[i];
        const std::string_view key = setting.key, variable = setting.variable;
        const std::string name(key);
        const std::size_t dot = key.find('.');
        expect(dot != std::string_view::npos && dot > 0 && dot + 1 < key.size() &&
                   key.find('.', dot + 1) == std::string_view::npos,
               name + ": a key is section.name");
        expect(!variable.empty(), name + ": has a variable");
        expect(setting.fallback != nullptr, name + ": has a default, \"\" for not set");
        expect(keys.insert(key).second, name + ": the key is in the table once");
        expect(variables.insert(variable).second, name + ": its variable belongs to no other setting");
        const auto by_key = config::Name::find(key);
        const auto by_variable = config::Name::find(variable);
        expect(by_key && by_key->index() == i, name + ": found by key");
        expect(by_variable && by_variable->index() == i, name + ": found by variable");
        expect(&config::Name::at(i).setting() == &setting, name + ": at() names the row");
    }
    expect(!config::Name::find("vulkan.no_such_setting"), "a key that is not in the table is not found");
    expect(!config::Name::find(""), "an empty name is not found");
    expect(variables.count(config::kFileVariable) == 0, "the variable that names the file is not a setting");
    expect(std::string_view(config::source_name(config::Source::Default)) == "default" &&
               std::string_view(config::source_name(config::Source::File)) == "file" &&
               std::string_view(config::source_name(config::Source::Environment)) == "environment",
           "the three sources have their names");
}

void test_order(const std::filesystem::path& dir) {
    const auto validation = [] { return config::get("vulkan.validation"); };
    config::Value value = validation();
    expect(value.text == "0" && value.source == config::Source::Default && !value.is_set(),
           "nothing set: the default");

    const std::filesystem::path file = dir / "order.toml";
    write_file(file, "[vulkan]\nvalidation = true\n");
    std::string error;
    expect(config::load_file(file, &error), "load_file reads a good file: " + error);
    value = validation();
    expect(value.text == "1" && value.source == config::Source::File && value.is_set(),
           "set in the file: the file's value");
    expect(config::get("vulkan.arena_mb").source == config::Source::Default,
           "a setting the file leaves out keeps its default");

    // The environment is read at each call, so a variable set after an earlier read is seen.
    set_env("LEONIDA_VK_VALIDATION", "2");
    value = validation();
    expect(value.text == "2" && value.source == config::Source::Environment, "the variable wins over the file");
    set_env("LEONIDA_VK_VALIDATION", "");
    expect(validation().source == config::Source::File, "an empty variable counts as not set");
    set_env("LEONIDA_VK_VALIDATION", nullptr);
    expect(validation().source == config::Source::File, "the variable removed: the file's value again");

    config::unload();
    expect(validation().source == config::Source::Default && config::loaded_file().empty(),
           "unload() forgets the file");

    expect(config::path("paths.game_dir").empty(), "a path that is not set is empty");
    const std::filesystem::path game = dir / "game folder";
    set_env_path("LEONIDA_GAME_DIR", game);
    expect(config::path("paths.game_dir") == game, "a path from the environment");
    set_env("LEONIDA_GAME_DIR", nullptr);
#if defined(_WIN32)
    // UTF-8 in Value::text and the same characters back in path(): a folder named outside the ANSI code page
    // reaches the reader intact.
    const wchar_t wide[] = L"C:\\Spiele\\Gr\u00F6\u00DFe \u30B2\u30FC\u30E0";
    SetEnvironmentVariableW(L"LEONIDA_GAME_DIR", wide);
    expect(config::get("paths.game_dir").text ==
               "C:\\Spiele\\Gr\xC3\xB6\xC3\x9F" "e \xE3\x82\xB2\xE3\x83\xBC\xE3\x83\xA0",
           "a wide value is returned as UTF-8");
    expect(config::path("paths.game_dir").native() == wide, "a wide value comes back whole as a path");
    SetEnvironmentVariableW(L"LEONIDA_GAME_DIR", nullptr);
#endif
}

void test_parse() {
    const std::string_view good =
        "\xEF\xBB\xBF# a comment, after the byte order mark Notepad writes\r\n"
        "[paths]\r\n"
        "game_dir = 'D:\\games\\gta6'  # single quotes: as written\r\n"
        "save_dir = \"D:\\\\saves \\\"one\\\"\"\r\n"
        "shaders = ''\r\n"
        "\r\n"
        "  [vulkan]  # a second section\r\n"
        "validation = true\r\n"
        "graphics_family_only=false\r\n"
        "arena_mb = 512\r\n"
        "[input]\n"
        "ds_trigger_gain = 1.5\n"
        "[loader]\n"
        "rng_seed = 0x1F\n"
        "[present]\n"
        "sdr_eotf = 'gamma22 # not a comment'";  // and no line break at the end
    config::FileValues values;
    std::string error;
    expect(config::parse(good, "f.toml", &values, &error), "a file in the format is read: " + error);
    const auto is = [&](std::string_view key, std::string_view want) {
        const std::string got = file_value(values, key);
        expect(got == want, std::string(key) + ": read \"" + got + "\", expected \"" + std::string(want) + "\"");
    };
    is("paths.game_dir", "D:\\games\\gta6");
    is("paths.save_dir", "D:\\saves \"one\"");
    is("paths.shaders", "<unset>");  // '' leaves a setting unset
    is("vulkan.validation", "1");
    is("vulkan.graphics_family_only", "0");
    is("vulkan.arena_mb", "512");
    is("vulkan.device", "<unset>");
    is("input.ds_trigger_gain", "1.5");
    is("loader.rng_seed", "0x1F");
    is("present.sdr_eotf", "gamma22 # not a comment");

    struct Refused {
        const char* what;
        const char* text;
        int line;          // the line the error names
        const char* part;  // text the error contains
    };
    const Refused refused[] = {
        {"an unknown section", "[nope]\n", 1, "no section [nope]"},
        {"a section with a dot", "# first\n[paths.sub]\n", 2, "no section [paths.sub]"},
        {"an unknown name", "[paths]\nnope = 1\n", 2, "no setting paths.nope"},
        {"a name of another section", "[paths]\nvalidation = true\n", 2, "no setting paths.validation"},
        {"a name set twice", "[paths]\ngame_dir = 'a'\ngame_dir = 'b'\n", 3, "paths.game_dir is set twice"},
        {"a name set twice, first to ''", "[paths]\nshaders = ''\nshaders = 'b'\n", 3, "set twice"},
        {"a section twice", "[paths]\n[vulkan]\n[paths]\n", 3, "[paths] is in the file twice"},
        {"a setting above every section", "game_dir = 'a'\n", 1, "[section]"},
        {"a single quote left open", "[paths]\ngame_dir = 'a\n", 2, "closing '"},
        {"a double quote left open", "[paths]\ngame_dir = \"a\n", 2, "closing \""},
        {"a Windows path in double quotes", "[paths]\ngame_dir = \"D:\\games\"\n", 2, "single quotes"},
        {"text without quotes", "[paths]\ngame_dir = D:\\games\n", 2, "in quotes"},
        {"True with a capital", "[vulkan]\nvalidation = True\n", 2, "in quotes"},
        {"a number that ends in a dot", "[vulkan]\narena_mb = 1.\n", 2, "in quotes"},
        {"two values", "[paths]\ngame_dir = 'a' 'b'\n", 2, "# comment"},
        {"no value", "[paths]\ngame_dir =\n", 2, "missing"},
        {"no equals sign", "[paths]\ngame_dir\n", 2, "name = value"},
        {"a section left open", "[paths\n", 1, "closing ]"},
        {"text after a section", "[paths] x\n", 1, "# comment"},
    };
    for (const Refused& r : refused) {
        config::FileValues kept;
        kept[0] = "kept";
        error.clear();
        const bool ok = config::parse(r.text, "f.toml", &kept, &error);
        const std::string start = "f.toml:" + std::to_string(r.line) + ": ";
        expect(!ok && error.rfind(start, 0) == 0 && contains(error, r.part),
               std::string(r.what) + " is refused with its line; the error was \"" + error + "\"");
        expect(kept[0] == "kept", std::string(r.what) + ": a refused file changes no value");
    }
}

void test_load(const std::filesystem::path& dir) {
    const auto gamertag = [] { return config::get("system.gamertag"); };
    std::string error;
    expect(config::load({}, &error) && config::loaded_file().empty(),
           "no program folder and no variable: nothing to read, and that is not an error");
    expect(config::load(dir, &error) && config::loaded_file().empty(),
           "a program folder without leonida.toml: nothing to read");
    expect(gamertag().text == "Player" && gamertag().source == config::Source::Default, "no file: the default");

    write_file(dir / config::kFileName, "[system]\ngamertag = 'Beside'\n");
    expect(config::load(dir, &error), "leonida.toml in the program folder is read: " + error);
    expect(config::loaded_file().filename() == config::kFileName && config::loaded_file().is_absolute(),
           "loaded_file() names it with its folder");
    expect(gamertag().text == "Beside" && gamertag().source == config::Source::File,
           "its value is the one get() returns");

    write_file(dir / "named.toml", "[system]\ngamertag = 'Named'\n");
    set_env_path(config::kFileVariable, dir / "named.toml");
    expect(config::load(dir, &error) && gamertag().text == "Named",
           "the file the variable names is read instead of the one in the program folder: " + error);

    set_env_path(config::kFileVariable, dir / "missing.toml");
    error.clear();
    expect(!config::load(dir, &error) && contains(error, config::kFileVariable) && contains(error, "missing.toml"),
           "a variable that names no file is an error that says so; the error was \"" + error + "\"");
    expect(gamertag().text == "Named", "a failed load keeps the values loaded before");

    write_file(dir / "bad.toml", "[system]\ngamer_tag = 'Typo'\n");
    set_env_path(config::kFileVariable, dir / "bad.toml");
    error.clear();
    expect(!config::load(dir, &error) && contains(error, "bad.toml:2: ") && contains(error, "system.gamer_tag"),
           "a misspelt setting is an error with file and line; the error was \"" + error + "\"");
    expect(gamertag().text == "Named", "a refused file keeps the values loaded before");

    set_env(config::kFileVariable, nullptr);
    config::unload();
    expect(gamertag().text == "Player", "unloaded: the default again");
}

// The report's line for `key`, without its line break; empty when there is none.
std::string_view report_line(std::string_view report, std::string_view key) {
    while (!report.empty()) {
        const std::size_t newline = report.find('\n');
        const std::string_view line = report.substr(0, newline);
        report.remove_prefix(newline == std::string_view::npos ? report.size() : newline + 1);
        if (line.size() > key.size() && line.substr(0, key.size()) == key && line[key.size()] == ' ') return line;
    }
    return {};
}

void test_report() {
    config::unload();
    set_env("LEONIDA_GAMERTAG", "Tester");
    const std::string report = config::report();
    set_env("LEONIDA_GAMERTAG", nullptr);

    std::size_t lines = 0;
    for (const char c : report) lines += c == '\n';
    expect(lines == config::kSettingCount + 1, "the report has a line for the file and one per setting");
    expect(report.rfind("settings file: none", 0) == 0, "without a file the first line says so");
    const std::string_view from_environment = report_line(report, "system.gamertag");
    expect(contains(from_environment, " environment ") && contains(from_environment, " LEONIDA_GAMERTAG ") &&
               from_environment.ends_with(" Tester"),
           "a setting from the environment: source, variable and value; the line was \"" +
               std::string(from_environment) + "\"");
    const std::string_view not_set = report_line(report, "paths.game_dir");
    expect(contains(not_set, " default ") && not_set.ends_with(" (not set)"),
           "a setting without a value; the line was \"" + std::string(not_set) + "\"");
}

// The name a line of the example file sets: "name = value", or the same behind "# " (a default, shown but off).
// Empty for any other line.
std::string_view setting_name(std::string_view line, bool* commented) {
    *commented = line.substr(0, 2) == "# ";
    if (*commented) line.remove_prefix(2);
    const auto in_name = [](char c) { return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_'; };
    std::size_t n = 0;
    while (n < line.size() && in_name(line[n])) ++n;
    if (n == 0 || line.substr(n, 3) != " = ") return {};
    return line.substr(0, n);
}

// True when `text` names `variable` as a whole word, not as the start or end of a longer name.
bool names_variable(std::string_view text, std::string_view variable) {
    const auto in_name = [](char c) { return (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_'; };
    for (std::size_t at = text.find(variable); at != std::string_view::npos; at = text.find(variable, at + 1)) {
        const std::size_t end = at + variable.size();
        if ((at == 0 || !in_name(text[at - 1])) && (end == text.size() || !in_name(text[end]))) return true;
    }
    return false;
}

void test_example(const std::filesystem::path& file) {
    std::ifstream in(file, std::ios::binary);
    expect(in.is_open(), "the example file named on the command line can be opened");
    if (!in.is_open()) return;
    const std::string text{std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>()};
    const std::string name = "leonida.example.toml";

    config::FileValues as_written;
    std::string error;
    expect(config::parse(text, name, &as_written, &error), "the example is read as it is written: " + error);
    expect(names_variable(text, config::kFileVariable), "the example names the variable that selects the file");

    // With every "# name = value" line switched on, the file has to name each setting once, under its section and
    // with its variable, and give it the default of the table.
    std::string switched_on, section;
    std::set<std::string> listed;
    std::string_view rest = text;
    while (!rest.empty()) {
        const std::size_t newline = rest.find('\n');
        std::string_view line = rest.substr(0, newline);
        rest.remove_prefix(newline == std::string_view::npos ? rest.size() : newline + 1);
        if (!line.empty() && line.back() == '\r') line.remove_suffix(1);
        if (line.size() > 2 && line.front() == '[' && line.back() == ']') section = line.substr(1, line.size() - 2);
        bool commented = false;
        if (const std::string_view setting = setting_name(line, &commented); !setting.empty()) {
            listed.insert(section + "." + std::string(setting));
            if (commented) line.remove_prefix(2);
        }
        switched_on.append(line).append("\n");
    }
    config::FileValues defaults;
    error.clear();
    const bool parsed = config::parse(switched_on, name, &defaults, &error);
    expect(parsed, "the example is read with every setting switched on: " + error);
    for (std::size_t i = 0; i < config::kSettingCount; ++i) {
        const config::Setting& setting = config::kSettings[i];
        const std::string key = setting.key;
        expect(listed.count(key) == 1, key + " is in the example");
        expect(names_variable(text, setting.variable), key + ": the example names " + setting.variable);
        if (parsed)
            expect(defaults[i].value_or("") == setting.fallback,
                   key + ": the example shows the default, \"" + setting.fallback + "\"");
    }
    expect(listed.size() == config::kSettingCount, "the example lists the settings of the table and no others");
}

}  // namespace

int main(int argc, char** argv) {
    if (argc != 2) {
        std::fprintf(stderr, "usage: core_config_test <path to runtime/leonida.example.toml>\n");
        return 2;
    }
    // The settings of whoever runs this must not decide its result.
    for (const config::Setting& setting : config::kSettings) set_env(setting.variable, nullptr);
    set_env(config::kFileVariable, nullptr);

    std::error_code failed;
    const auto now = std::chrono::steady_clock::now().time_since_epoch().count();
    const std::filesystem::path dir =
        std::filesystem::temp_directory_path(failed) / ("leonida_core_config_test_" + std::to_string(now));
    std::filesystem::create_directories(dir, failed);
    expect(!failed, "the scratch folder can be made");

    test_table();
    test_order(dir);
    test_parse();
    test_load(dir);
    test_report();
    test_example(argv[1]);

    std::filesystem::remove_all(dir, failed);
    if (g_failures) {
        std::fprintf(stderr, "%d check(s) failed\n", g_failures);
        return 1;
    }
    std::puts("core_config_test: ok");
    return 0;
}
