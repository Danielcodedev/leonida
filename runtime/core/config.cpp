#include "config.h"

#include <fstream>
#include <iterator>
#include <mutex>
#include <system_error>
#include <utility>
#include <vector>

#if defined(_WIN32)
#include <windows.h>
#else
#include <cstdlib>
#endif

namespace rt::config {

namespace {

// ---- text, paths and the environment ----

#if defined(_WIN32)
// Flags 0 in both directions: a character that cannot be converted is replaced, so neither conversion fails.
std::string narrow(std::wstring_view wide) {
    if (wide.empty()) return {};
    const int size = WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()), nullptr, 0, nullptr,
                                         nullptr);
    if (size <= 0) return {};
    std::string text(static_cast<std::size_t>(size), '\0');
    WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()), text.data(), size, nullptr, nullptr);
    return text;
}

std::wstring widen(std::string_view text) {
    if (text.empty()) return {};
    const int size = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
    if (size <= 0) return {};
    std::wstring wide(static_cast<std::size_t>(size), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), wide.data(), size);
    return wide;
}

std::string to_utf8(const std::filesystem::path& p) { return narrow(p.native()); }
std::filesystem::path to_path(std::string_view text) { return std::filesystem::path(widen(text)); }
#else
std::string to_utf8(const std::filesystem::path& p) { return p.string(); }
std::filesystem::path to_path(std::string_view text) { return std::filesystem::path(std::string(text)); }
#endif

// The variable's value in UTF-8; nullopt when it is unset or empty, which get() treats alike.
std::optional<std::string> environment(const char* variable) {
#if defined(_WIN32)
    // GetEnvironmentVariableW and not getenv: the CRT's copy of the environment does not follow
    // SetEnvironmentVariable, which the tests use to set a variable in their own process. The thread's last error
    // is put back, because shims read settings in the middle of a call from the title.
    const DWORD last_error = GetLastError();
    std::wstring name;
    for (const char* c = variable; *c; ++c) name.push_back(static_cast<wchar_t>(static_cast<unsigned char>(*c)));
    std::wstring wide(260, L'\0');
    DWORD length = 0;
    for (;;) {
        length = GetEnvironmentVariableW(name.c_str(), wide.data(), static_cast<DWORD>(wide.size()));
        if (length < wide.size()) break;                    // 0: unset or empty; else the length without the terminator
        wide.resize(static_cast<std::size_t>(length) + 1);  // too small: `length` is the size the value needs
    }
    SetLastError(last_error);
    if (length == 0) return std::nullopt;
    wide.resize(length);
    return narrow(wide);
#else
    const char* value = std::getenv(variable);
    if (!value || !*value) return std::nullopt;
    return std::string(value);
#endif
}

// ---- the loaded file ----

struct Loaded {
    std::mutex mutex;
    FileValues values;
    std::filesystem::path file;
};

// Never destroyed: a thread of the title may still read a setting while the process exits.
Loaded& loaded() {
    static Loaded* const state = new Loaded;
    return *state;
}

// ---- the file format ----

constexpr bool is_blank(char c) { return c == ' ' || c == '\t' || c == '\r'; }
constexpr bool is_digit(char c) { return c >= '0' && c <= '9'; }

std::string_view trim(std::string_view s) {
    while (!s.empty() && is_blank(s.front())) s.remove_prefix(1);
    while (!s.empty() && is_blank(s.back())) s.remove_suffix(1);
    return s;
}

// A section or setting name as TOML allows it without quotes: letters, digits, _ and -.
bool is_name(std::string_view s) {
    if (s.empty()) return false;
    for (const char c : s)
        if (!(is_digit(c) || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || c == '-')) return false;
    return true;
}

// A number in the forms a setting uses: 30, -1, 1.5, 0x1f.
bool is_number(std::string_view s) {
    const bool has_sign = !s.empty() && (s.front() == '+' || s.front() == '-');
    if (has_sign) s.remove_prefix(1);
    if (!has_sign && s.size() > 2 && s[0] == '0' && s[1] == 'x') {
        for (const char c : s.substr(2))
            if (!(is_digit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) return false;
        return true;
    }
    std::size_t i = 0;
    while (i < s.size() && is_digit(s[i])) ++i;
    if (i == 0) return false;
    if (i == s.size()) return true;
    if (s[i] != '.') return false;
    const std::size_t fraction = ++i;
    while (i < s.size() && is_digit(s[i])) ++i;
    return i > fraction && i == s.size();
}

bool has_section(std::string_view section) {
    for (const Setting& setting : kSettings) {
        const std::string_view key = setting.key;
        if (key.size() > section.size() && key[section.size()] == '.' && key.substr(0, section.size()) == section)
            return true;
    }
    return false;
}

// True when nothing but a comment follows.
bool ends_here(std::string_view rest) {
    rest = trim(rest);
    return rest.empty() || rest.front() == '#';
}

// The value `rest` starts with, as the text get() returns. False with the reason in *what when it is not a value
// this reader takes or something other than a comment follows it.
bool read_value(std::string_view rest, std::string* value, std::string* what) {
    value->clear();
    std::size_t end = 0;
    if (rest.empty() || rest.front() == '#') {
        *what = "the value after = is missing";
        return false;
    }
    if (rest.front() == '\'') {
        const std::size_t close = rest.find('\'', 1);
        if (close == std::string_view::npos) {
            *what = "the closing ' is missing";
            return false;
        }
        value->assign(rest.substr(1, close - 1));
        end = close + 1;
    } else if (rest.front() == '"') {
        std::size_t i = 1;
        for (;; ++i) {
            if (i == rest.size()) {
                *what = "the closing \" is missing";
                return false;
            }
            if (rest[i] == '"') break;
            if (rest[i] == '\\') {
                if (i + 1 == rest.size() || (rest[i + 1] != '\\' && rest[i + 1] != '"')) {
                    *what = "in double quotes a backslash starts an escape, and only \\\\ and \\\" are read here; "
                            "write a Windows path in single quotes";
                    return false;
                }
                ++i;
            }
            value->push_back(rest[i]);
        }
        end = i + 1;
    } else {
        while (end < rest.size() && !is_blank(rest[end]) && rest[end] != '#') ++end;
        const std::string_view word = rest.substr(0, end);
        if (word == "true") *value = "1";
        else if (word == "false") *value = "0";
        else if (is_number(word)) value->assign(word);
        else {
            *what = "the value must be text in quotes, a number, true or false";
            return false;
        }
    }
    if (!ends_here(rest.substr(end))) {
        *what = "only a # comment may follow the value";
        return false;
    }
    return true;
}

std::string padded(std::string_view text, std::size_t width) {
    std::string out(text);
    if (out.size() < width) out.append(width - out.size(), ' ');
    return out;
}

}  // namespace

std::optional<Name> Name::find(std::string_view key_or_variable) {
    for (std::size_t i = 0; i < kSettingCount; ++i)
        if (key_or_variable == kSettings[i].key || key_or_variable == kSettings[i].variable) return at(i);
    return std::nullopt;
}

const char* source_name(Source source) {
    switch (source) {
        case Source::Environment: return "environment";
        case Source::File: return "file";
        default: return "default";
    }
}

Value get(Name name) {
    const Setting& setting = name.setting();
    if (auto value = environment(setting.variable)) return Value{std::move(*value), Source::Environment};
    {
        Loaded& state = loaded();
        const std::lock_guard lock(state.mutex);
        if (const auto& value = state.values[name.index()]) return Value{*value, Source::File};
    }
    return Value{setting.fallback, Source::Default};
}

std::filesystem::path path(Name name) { return to_path(get(name).text); }

bool parse(std::string_view text, std::string_view file_name, FileValues* values, std::string* error) {
    FileValues found;
    std::array<bool, kSettingCount> seen{};  // apart from `found`: a setting set to '' is seen and stays unset
    std::vector<std::string_view> sections;
    std::string_view section;
    std::size_t line_number = 0;
    const auto fail = [&](const std::string& what) {
        if (error) *error = std::string(file_name) + ":" + std::to_string(line_number) + ": " + what;
        return false;
    };

    if (text.starts_with("\xEF\xBB\xBF")) text.remove_prefix(3);  // a UTF-8 byte order mark, as Notepad writes it
    while (!text.empty()) {
        ++line_number;
        const std::size_t newline = text.find('\n');
        const std::string_view line = trim(text.substr(0, newline));
        text.remove_prefix(newline == std::string_view::npos ? text.size() : newline + 1);
        if (line.empty() || line.front() == '#') continue;

        if (line.front() == '[') {
            const std::size_t close = line.find(']');
            if (close == std::string_view::npos) return fail("the closing ] is missing");
            const std::string_view name = trim(line.substr(1, close - 1));
            if (!is_name(name) || !has_section(name))
                return fail("there is no section [" + std::string(name) + "]");
            if (!ends_here(line.substr(close + 1))) return fail("only a # comment may follow a [section]");
            for (const std::string_view earlier : sections)
                if (earlier == name) return fail("[" + std::string(name) + "] is in the file twice");
            sections.push_back(name);
            section = name;
            continue;
        }

        const std::size_t equals = line.find('=');
        const std::string_view name = trim(line.substr(0, equals));
        if (equals == std::string_view::npos || !is_name(name)) return fail("expected [section] or name = value");
        if (section.empty()) return fail("a setting needs its [section] line above it");
        const std::string key = std::string(section) + "." + std::string(name);
        const std::size_t index = index_of_key(key);
        if (index == kSettingCount)
            return fail("there is no setting " + key + "; `gta6rt config` lists the settings");
        if (seen[index]) return fail(key + " is set twice");
        seen[index] = true;
        std::string value, what;
        if (!read_value(trim(line.substr(equals + 1)), &value, &what)) return fail(key + ": " + what);
        if (!value.empty()) found[index] = std::move(value);
    }
    *values = std::move(found);
    return true;
}

bool load_file(const std::filesystem::path& file, std::string* error) {
    const std::string name = to_utf8(file);
    std::ifstream in(file, std::ios::binary);
    const std::string text{std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>()};
    if (!in.is_open() || in.bad()) {
        if (error) *error = name + ": cannot be read";
        return false;
    }
    FileValues values;
    if (!parse(text, name, &values, error)) return false;
    // Absolute, so that the report still names the file after the title has changed the current directory.
    std::error_code failed;
    std::filesystem::path absolute = std::filesystem::absolute(file, failed);
    Loaded& state = loaded();
    const std::lock_guard lock(state.mutex);
    state.values = std::move(values);
    state.file = failed ? file : std::move(absolute);
    return true;
}

bool load(const std::filesystem::path& program_dir, std::string* error) {
    std::error_code ignored;
    if (const auto named = environment(kFileVariable)) {
        const std::filesystem::path file = to_path(*named);
        if (!std::filesystem::is_regular_file(file, ignored)) {
            if (error) *error = std::string(kFileVariable) + " names " + *named + ", which is not a file";
            return false;
        }
        return load_file(file, error);
    }
    if (program_dir.empty()) return true;
    const std::filesystem::path file = program_dir / kFileName;
    if (!std::filesystem::is_regular_file(file, ignored)) return true;
    return load_file(file, error);
}

void unload() {
    Loaded& state = loaded();
    const std::lock_guard lock(state.mutex);
    state.values = {};
    state.file.clear();
}

std::filesystem::path loaded_file() {
    Loaded& state = loaded();
    const std::lock_guard lock(state.mutex);
    return state.file;
}

std::string report() {
    const std::filesystem::path file = loaded_file();
    std::string out = "settings file: ";
    out += file.empty() ? std::string("none (") + kFileVariable + ", or " + kFileName + " next to the program)"
                        : to_utf8(file);
    out += '\n';
    std::size_t key_width = 0, variable_width = 0;
    for (const Setting& setting : kSettings) {
        if (const std::size_t n = std::string_view(setting.key).size(); n > key_width) key_width = n;
        if (const std::size_t n = std::string_view(setting.variable).size(); n > variable_width) variable_width = n;
    }
    for (std::size_t i = 0; i < kSettingCount; ++i) {
        const Setting& setting = kSettings[i];
        const Value value = get(Name::at(i));
        out += padded(setting.key, key_width + 2) + padded(source_name(value.source), 13) +
               padded(setting.variable, variable_width + 2) + (value.text.empty() ? "(not set)" : value.text) + '\n';
    }
    return out;
}

}  // namespace rt::config
