//! Exercise the public graphics configuration CLI in isolated child processes.
//! Every input is original synthetic data, and all temporary files stay outside the repo.
#![cfg(windows)]

use std::path::{Path, PathBuf};
use std::process::{Command, Output};

use serde_json::{Value, json};
use tempfile::TempDir;

const BASE: [&str; 8] = [
    "LEONIDA_ASYNC_SUBMIT",
    "LEONIDA_QUEUE2",
    "LEONIDA_INDIRECT_WINDOW",
    "LEONIDA_COPY_PLAIN",
    "LEONIDA_JOIN_PARTS",
    "LEONIDA_BACK_OWN_VIEW",
    "LEONIDA_INDIRECT_GATHER",
    "LEONIDA_CARD_REHASH_RUNS",
];

struct Fixture {
    root: TempDir,
    config: PathBuf,
}

impl Fixture {
    fn new(config: &str) -> Self {
        let root = tempfile::tempdir().unwrap();
        leonida_core::ensure_outside_repo(root.path()).unwrap();
        let path = root.path().join("leonida.toml");
        std::fs::write(&path, config).unwrap();
        Self { root, config: path }
    }

    fn path(&self, name: &str) -> PathBuf {
        self.root.path().join(name)
    }

    fn local(&self, value: Value) {
        std::fs::write(
            self.path("gpu-profiles.local.json"),
            serde_json::to_vec(&value).unwrap(),
        )
        .unwrap();
    }

    fn command(&self) -> Command {
        let mut cmd = Command::new(env!("CARGO_BIN_EXE_leonida"));
        cmd.env_clear();
        // Keep only OS discovery/loading variables; no caller's LEONIDA_* state leaks in.
        for name in ["SystemRoot", "WINDIR", "PATH", "TEMP", "TMP", "USERPROFILE"] {
            if let Some(value) = std::env::var_os(name) {
                cmd.env(name, value);
            }
        }
        cmd.current_dir(self.root.path())
            .env("LOCALAPPDATA", self.path("local-app-data"))
            .env("LEONIDA_CONFIG", &self.config)
            .env("LEONIDA_CACHE_DIR", self.path("cache"))
            .env("LEONIDA_DATA_DIR", self.path("data"));
        cmd
    }

    fn graphics(&self, env: &[(&str, &str)]) -> Value {
        let mut cmd = self.command();
        cmd.args(["config", "--graphics"]);
        for (name, value) in env {
            cmd.env(name, value);
        }
        graphics_output(cmd.output().unwrap())
    }
}

fn graphics_output(output: Output) -> Value {
    assert!(
        output.status.success(),
        "status: {}\nstdout: {}\nstderr: {}",
        output.status,
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr),
    );
    let value: Value = serde_json::from_slice(&output.stdout).unwrap_or_else(|error| {
        panic!(
            "graphics stdout is not one JSON document: {error}\n{:?}",
            output.stdout
        )
    });
    assert!(value["profiles"].is_array(), "{value}");
    let settings = value["settings"].as_object().expect("settings map");
    let sources = value["sources"].as_object().expect("sources map");
    assert_eq!(settings.len(), sources.len(), "{value}");
    for (name, setting) in settings {
        assert!(setting.is_string(), "{name}: {setting}");
        assert!(sources.get(name).is_some_and(Value::is_string), "{value}");
    }
    if !value["gpu"].is_null() {
        assert!(value["gpu"]["name"].is_string(), "{value}");
        assert!(value["gpu"]["vendor"].is_string(), "{value}");
        assert!(value["gpu"]["vram_mb"].is_u64(), "{value}");
    }
    value
}

fn setting(plan: &Value, name: &str, value: &str, source: &str) {
    assert_eq!(plan["settings"][name], value, "{plan}");
    assert_eq!(plan["sources"][name], source, "{plan}");
}

fn absent(plan: &Value, name: &str) {
    assert!(plan["settings"].get(name).is_none(), "{plan}");
    assert!(plan["sources"].get(name).is_none(), "{plan}");
}

#[test]
fn graphics_defaults_report_eight_base_settings_without_card_windows() {
    let fixture = Fixture::new("");
    let plan = fixture.graphics(&[]);
    assert_eq!(plan["profiles"], json!(["base"]));
    assert_eq!(plan["settings"].as_object().unwrap().len(), BASE.len());
    for name in BASE {
        setting(&plan, name, "1", "profile:base");
    }
    for name in [
        "LEONIDA_CARD_WINDOWS_MB",
        "LEONIDA_WINDOW_UPLOAD",
        "LEONIDA_TEXTURE_ROOM_PERCENT",
    ] {
        absent(&plan, name);
    }
}

#[test]
fn graphics_sources_report_environment_over_config_over_profiles() {
    let fixture = Fixture::new("[graphics]\nasync_submit = false\nqueue2 = 3\n");
    let plan = fixture.graphics(&[("LEONIDA_QUEUE2", "2")]);
    setting(&plan, "LEONIDA_ASYNC_SUBMIT", "0", "config");
    setting(&plan, "LEONIDA_QUEUE2", "2", "environment");
    setting(&plan, "LEONIDA_INDIRECT_GATHER", "1", "profile:base");
    absent(&plan, "LEONIDA_CONFIG");
    absent(&plan, "LEONIDA_CACHE_DIR");
}

#[test]
fn graphics_none_and_empty_profile_lists_preserve_config_values() {
    for selection in ["profiles = []\n", "profiles = [\"none\"]\n"] {
        let fixture = Fixture::new(&format!("[graphics]\n{selection}async_submit = false\n"));
        let plan = fixture.graphics(&[]);
        assert_eq!(plan["profiles"], json!([]));
        assert_eq!(plan["settings"].as_object().unwrap().len(), 1);
        setting(&plan, "LEONIDA_ASYNC_SUBMIT", "0", "config");
    }
    let fixture = Fixture::new("[graphics]\nprofiles = [\"card-windows\"]\nasync_submit = false\n");
    let plan = fixture.graphics(&[("LEONIDA_PROFILE", "none")]);
    assert_eq!(plan["profiles"], json!([]));
    setting(&plan, "LEONIDA_ASYNC_SUBMIT", "0", "config");
    absent(&plan, "LEONIDA_CARD_WINDOWS_MB");
    absent(&plan, "LEONIDA_QUEUE2");
}

#[test]
fn graphics_environment_profile_selection_overrides_config_selection() {
    let fixture = Fixture::new("[graphics]\nprofiles = []\ncard_windows_mb = 4096\n");
    let plan = fixture.graphics(&[("LEONIDA_PROFILE", "card-windows")]);
    assert_eq!(plan["profiles"], json!(["base", "card-windows"]));
    setting(&plan, "LEONIDA_CARD_WINDOWS_MB", "4096", "config");
    setting(&plan, "LEONIDA_WINDOW_UPLOAD", "1", "profile:card-windows");
    setting(
        &plan,
        "LEONIDA_TEXTURE_ROOM_PERCENT",
        "70",
        "profile:card-windows",
    );
}

#[test]
fn graphics_off_preserves_only_explicit_switches() {
    let fixture = Fixture::new(
        "[graphics]\nprofiles = [\"card-windows\"]\nasync_submit = false\nqueue2 = 3\n",
    );
    let plan = fixture.graphics(&[("LEONIDA_GRAPHICS_OFF", "1"), ("LEONIDA_QUEUE2", "2")]);
    assert_eq!(plan["profiles"], json!([]));
    assert_eq!(plan["settings"], json!({"LEONIDA_QUEUE2": "2"}));
    setting(&plan, "LEONIDA_QUEUE2", "2", "environment");
    absent(&plan, "LEONIDA_GRAPHICS_OFF");
}

#[test]
fn graphics_local_profiles_follow_catalog_order_and_preserve_user_overrides() {
    let fixture =
        Fixture::new("[graphics]\nprofiles = [\"last\", \"first\"]\nasync_submit = false\n");
    fixture.local(json!({"profiles": [
        {"name": "first", "opt_in": true, "env": {
            "LEONIDA_JOIN_PARTS": "0", "LEONIDA_ASYNC_SUBMIT": "1", "LEONIDA_QUEUE2": "3"
        }},
        {"name": "last", "opt_in": true, "env": {
            "LEONIDA_JOIN_PARTS": null, "LEONIDA_ASYNC_SUBMIT": null,
            "LEONIDA_QUEUE2": null, "LEONIDA_COPY_PLAIN": "0"
        }}
    ]}));
    let plan = fixture.graphics(&[("LEONIDA_QUEUE2", "2")]);
    assert_eq!(plan["profiles"], json!(["base", "first", "last"]));
    absent(&plan, "LEONIDA_JOIN_PARTS");
    setting(&plan, "LEONIDA_ASYNC_SUBMIT", "0", "config");
    setting(&plan, "LEONIDA_QUEUE2", "2", "environment");
    setting(&plan, "LEONIDA_COPY_PLAIN", "0", "profile:last");
}

#[test]
fn graphics_local_catalog_is_relative_to_the_explicit_config() {
    let fixture = Fixture::new("");
    let config_dir = fixture.path("configuration");
    std::fs::create_dir(&config_dir).unwrap();
    let config = config_dir.join("settings.toml");
    std::fs::write(&config, "[graphics]\nprofiles = [\"placed\"]\n").unwrap();
    std::fs::write(fixture.path("gpu-profiles.local.json"), "not JSON").unwrap();
    std::fs::write(
        config_dir.join("gpu-profiles.local.json"),
        serde_json::to_vec(&json!({"profiles": [{
            "name": "placed", "env": {"LEONIDA_COPY_PLAIN": "0"}
        }]}))
        .unwrap(),
    )
    .unwrap();
    let output = fixture
        .command()
        .args(["config", "--graphics"])
        .env("LEONIDA_CONFIG", &config)
        .output()
        .unwrap();
    let plan = graphics_output(output);
    assert_eq!(plan["profiles"], json!(["base", "placed"]));
    setting(&plan, "LEONIDA_COPY_PLAIN", "0", "profile:placed");
}

#[test]
fn graphics_local_catalog_uses_cwd_when_no_config_exists() {
    let fixture = Fixture::new("");
    std::fs::remove_file(&fixture.config).unwrap();
    fixture.local(json!({"profiles": [{
        "name": "from-cwd", "env": {"LEONIDA_COPY_PLAIN": "0"}
    }]}));
    let output = fixture
        .command()
        .args(["config", "--graphics"])
        .env_remove("LEONIDA_CONFIG")
        .output()
        .unwrap();
    let plan = graphics_output(output);
    assert_eq!(plan["profiles"], json!(["base", "from-cwd"]));
    setting(&plan, "LEONIDA_COPY_PLAIN", "0", "profile:from-cwd");
}

#[test]
fn graphics_disabled_profiles_do_not_parse_a_broken_local_catalog() {
    let fixture = Fixture::new("[graphics]\nasync_submit = false\n");
    std::fs::write(fixture.path("gpu-profiles.local.json"), "not JSON").unwrap();
    let none = fixture.graphics(&[("LEONIDA_PROFILE", "none")]);
    setting(&none, "LEONIDA_ASYNC_SUBMIT", "0", "config");
    let off = fixture.graphics(&[("LEONIDA_GRAPHICS_OFF", "1")]);
    assert_eq!(off["settings"], json!({}));
}

#[test]
fn graphics_invalid_local_catalog_reports_its_source() {
    let fixture = Fixture::new("");
    std::fs::write(fixture.path("gpu-profiles.local.json"), "not JSON").unwrap();
    let output = fixture
        .command()
        .args(["config", "--graphics"])
        .output()
        .unwrap();
    assert!(!output.status.success());
    assert!(output.stdout.is_empty());
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("gpu-profiles.local.json"), "{stderr}");
}

#[test]
fn graphics_validation_precedes_run_reads_and_translation_probing() {
    let fixture = Fixture::new("[graphics]\nprofiles = [\"missing-profile\"]\n");
    let missing = fixture.path("not-a-title.exe");
    let hashes = fixture.path("not-a-hash-list.txt");
    let commands = [
        vec!["run".as_ref(), missing.as_os_str()],
        vec![
            "translate".as_ref(),
            missing.as_os_str(),
            "--warm".as_ref(),
            hashes.as_os_str(),
        ],
    ];
    for args in commands {
        let output = fixture.command().args(args).output().unwrap();
        assert!(!output.status.success());
        let stderr = String::from_utf8_lossy(&output.stderr);
        assert!(stderr.contains("unknown graphics profile"), "{stderr}");
        assert!(stderr.contains("missing-profile"), "{stderr}");
        assert!(
            !stderr.contains("reading "),
            "input was read before graphics validation: {stderr}"
        );
        assert!(
            !stderr.contains("no host D3D12 device"),
            "translation host probed first: {stderr}"
        );
    }
}

#[test]
fn graphics_json_cannot_be_combined_with_saving_a_game_directory() {
    let fixture = Fixture::new("# keep this file unchanged\n");
    let before = std::fs::read(&fixture.config).unwrap();
    let output = fixture
        .command()
        .args(["config", "--graphics", "--game-dir"])
        .arg(fixture.path("not-a-game-directory"))
        .output()
        .unwrap();
    assert!(!output.status.success());
    assert!(output.stdout.is_empty());
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("--graphics") && stderr.contains("--game-dir"),
        "{stderr}"
    );
    assert_eq!(std::fs::read(&fixture.config).unwrap(), before);
}

/// An original AMD64 PE with one import and no title data or compiler subprocess.
/// Its entry returns 73 only if GetEnvironmentVariableA reads the expected one-byte value.
#[cfg(target_arch = "x86_64")]
fn write_environment_probe(path: &Path, expected: u8) {
    let mut bytes = vec![0u8; 0x400];
    fn u16_at(bytes: &mut [u8], at: usize, value: u16) {
        bytes[at..at + 2].copy_from_slice(&value.to_le_bytes());
    }
    fn u32_at(bytes: &mut [u8], at: usize, value: u32) {
        bytes[at..at + 4].copy_from_slice(&value.to_le_bytes());
    }
    fn u64_at(bytes: &mut [u8], at: usize, value: u64) {
        bytes[at..at + 8].copy_from_slice(&value.to_le_bytes());
    }
    bytes[..2].copy_from_slice(b"MZ");
    u32_at(&mut bytes, 0x3c, 0x80);
    bytes[0x80..0x84].copy_from_slice(b"PE\0\0");
    u16_at(&mut bytes, 0x84, 0x8664); // AMD64
    u16_at(&mut bytes, 0x86, 1); // one section
    u16_at(&mut bytes, 0x94, 0xf0);
    u16_at(&mut bytes, 0x96, 0x0022); // executable, large-address-aware
    let optional = 0x98;
    u16_at(&mut bytes, optional, 0x20b); // PE32+
    u32_at(&mut bytes, optional + 4, 0x200);
    u32_at(&mut bytes, optional + 16, 0x1000); // original entry
    u32_at(&mut bytes, optional + 20, 0x1000);
    u64_at(&mut bytes, optional + 24, 0x1_8000_0000);
    u32_at(&mut bytes, optional + 32, 0x1000);
    u32_at(&mut bytes, optional + 36, 0x200);
    u16_at(&mut bytes, optional + 40, 6);
    u16_at(&mut bytes, optional + 48, 6);
    u32_at(&mut bytes, optional + 56, 0x2000);
    u32_at(&mut bytes, optional + 60, 0x200);
    u16_at(&mut bytes, optional + 68, 3); // console subsystem
    u16_at(&mut bytes, optional + 70, 0x0140); // ASLR and NX compatible
    u64_at(&mut bytes, optional + 72, 0x10_0000);
    u64_at(&mut bytes, optional + 80, 0x1000);
    u64_at(&mut bytes, optional + 88, 0x10_0000);
    u64_at(&mut bytes, optional + 96, 0x1000);
    u32_at(&mut bytes, optional + 108, 16);
    for (directory, rva, size) in [(1, 0x1080, 40), (5, 0x1100, 12), (12, 0x10d0, 16)] {
        u32_at(&mut bytes, optional + 112 + directory * 8, rva);
        u32_at(&mut bytes, optional + 116 + directory * 8, size);
    }
    let section = 0x188;
    bytes[section..section + 6].copy_from_slice(b".probe");
    u32_at(&mut bytes, section + 8, 0x200);
    u32_at(&mut bytes, section + 12, 0x1000);
    u32_at(&mut bytes, section + 16, 0x200);
    u32_at(&mut bytes, section + 20, 0x200);
    u32_at(&mut bytes, section + 36, 0xe000_0020); // code, read/write/execute

    // Win64 entry: reserve aligned shadow/buffer space, call the sole import,
    // check length and value, and return the sentinel while preserving saved registers.
    let entry = [
        0x48, 0x83, 0xec, 0x38, // sub rsp, 56
        0x48, 0x8d, 0x0d, 0x35, 0, 0, 0, // lea rcx, [environment-name]
        0x48, 0x8d, 0x54, 0x24, 0x20, // lea rdx, [rsp + 32]
        0x41, 0xb8, 2, 0, 0, 0, // mov r8d, 2
        0xff, 0x15, 0xb4, 0, 0, 0, // call [GetEnvironmentVariableA IAT slot]
        0x83, 0xf8, 1, // cmp eax, 1
        0x75, 0x11, // jne failure
        0x80, 0x7c, 0x24, 0x20, expected, // cmp byte [rsp + 32], expected
        0x75, 0x0a, // jne failure
        0xb8, 73, 0, 0, 0, // mov eax, 73
        0x48, 0x83, 0xc4, 0x38, 0xc3, // restore stack; ret
        0x31, 0xc0, // failure: xor eax, eax
        0x48, 0x83, 0xc4, 0x38, 0xc3, // restore stack; ret
    ];
    bytes[0x200..0x200 + entry.len()].copy_from_slice(&entry);
    for (at, text) in [
        (0x240, b"LEONIDA_QUEUE2\0".as_slice()),
        (0x2b0, b"KERNEL32.dll\0".as_slice()),
        (0x2e2, b"GetEnvironmentVariableA\0".as_slice()),
    ] {
        bytes[at..at + text.len()].copy_from_slice(text);
    }
    // Import descriptor, original lookup thunk and writable IAT thunk.
    u32_at(&mut bytes, 0x280, 0x10c0);
    u32_at(&mut bytes, 0x28c, 0x10b0);
    u32_at(&mut bytes, 0x290, 0x10d0);
    u64_at(&mut bytes, 0x2c0, 0x10e0);
    u64_at(&mut bytes, 0x2d0, 0x10e0);
    // A genuine DIR64 relocation on an unused pointer allows ordinary loader rebasing.
    u32_at(&mut bytes, 0x300, 0x1000);
    u32_at(&mut bytes, 0x304, 12);
    u16_at(&mut bytes, 0x308, 0xa120);
    u64_at(&mut bytes, 0x320, 0x1_8000_0000);
    std::fs::write(path, bytes).unwrap();
}

#[cfg(target_arch = "x86_64")]
#[test]
fn graphics_plan_reaches_the_actual_title_environment() {
    let cases: [(&str, &[(&str, &str)], &str, &str); 3] = [
        ("", &[], "1", "profile:base"),
        ("[graphics]\nqueue2 = 0\n", &[], "0", "config"),
        (
            "[graphics]\nqueue2 = 0\n",
            &[("LEONIDA_QUEUE2", "2")],
            "2",
            "environment",
        ),
    ];
    for (config, env, expected, source) in cases {
        let fixture = Fixture::new(config);
        let plan = fixture.graphics(env);
        setting(&plan, "LEONIDA_QUEUE2", expected, source);
        let probe = fixture.path("graphics-probe.exe");
        write_environment_probe(&probe, expected.as_bytes()[0]);
        let mut command = fixture.command();
        command.arg("run").arg(&probe).arg("--execute");
        for (name, value) in env {
            command.env(name, value);
        }
        let output = command.output().unwrap();
        let stdout = String::from_utf8_lossy(&output.stdout);
        let stderr = String::from_utf8_lossy(&output.stderr);
        assert!(
            output.status.success(),
            "source {source}: {stdout}\n{stderr}"
        );
        assert!(
            stdout.contains("title exited with 73"),
            "source {source}: actual title code did not read the reported setting\n{stdout}\n{stderr}",
        );
    }
    eprintln!("graphics runtime probe: 3 plans matched the title environment");
}

#[cfg(feature = "diagnostics")]
#[test]
fn graphics_warp_presence_never_reports_a_hardware_adapter() {
    let fixture = Fixture::new("");
    // The runtime selects WARP by presence, so even the text "0" requests software.
    let output = fixture
        .command()
        .args(["config", "--graphics"])
        .env("LEONIDA_D3D12_WARP", "0")
        .output()
        .unwrap();
    let stderr = String::from_utf8_lossy(&output.stderr).into_owned();
    let plan = graphics_output(output);
    if plan["gpu"].is_null() {
        assert!(stderr.contains("graphics adapter unavailable"), "{stderr}");
    } else {
        assert_eq!(plan["gpu"]["vendor"], "other", "{plan}");
        let name = plan["gpu"]["name"].as_str().unwrap();
        assert!(name.to_ascii_lowercase().contains("microsoft"), "{plan}");
    }
    absent(&plan, "LEONIDA_D3D12_WARP");
}
