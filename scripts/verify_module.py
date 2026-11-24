#!/usr/bin/env python3
"""Verification suite for Caventus Pixel 6 (oriole) KernelSU module + WebUI."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
MODULE_DIR = ROOT / "module"
DIST_DIR = ROOT / "dist"

REQUIRED_PROP_KEYS = {"id", "name", "version", "versionCode", "author", "description"}
REQUIRED_SYSTEM_PROPS = {
    "dalvik.vm.dex2oat-filter": "speed-profile",
    "dalvik.vm.image-dex2oat-filter": "speed-profile",
    "pm.dexopt.install": "speed-profile",
    "pm.dexopt.bg-dexopt": "speed-profile",
    "ro.lmk.use_psi": "true",
    "ro.lmk.use_minfree_levels": "false",
    "ro.lmk.psi_partial_stall_ms": "50",
    "ro.lmk.psi_complete_stall_ms": "500",
    "ro.lmk.thrashing_limit": "60",
    "ro.lmk.swap_free_low_percentage": "20",
    "ro.lmk.swap_util_max": "85",
    "mmd.zram.enabled": "true",
    "mmd.zram.size": "4294967296",
    "mmd.zram.comp_algorithm": "lz77eh",
}


def check_lf_line_endings() -> None:
    for p in sorted(MODULE_DIR.rglob("*")):
        if p.is_file() and b"\r" in p.read_bytes():
            raise AssertionError(f"CRLF detected in {p.relative_to(ROOT)}")
    print("PASS: line endings (all LF)")


def check_shell_syntax() -> None:
    scripts = sorted(
        p for p in MODULE_DIR.rglob("*")
        if p.is_file() and (p.suffix == ".sh" or p.name == "update-binary")
    )
    assert scripts, "No shell scripts found"
    for script in scripts:
        res = subprocess.run(["sh", "-n", str(script)], capture_output=True, text=True)
        if res.returncode != 0:
            raise AssertionError(f"sh -n failed for {script}: {res.stderr}")
    print(f"PASS: sh -n syntax ({len(scripts)} scripts)")


def check_js_syntax() -> None:
    js_files = sorted((MODULE_DIR / "webroot" / "js").glob("*.js"))
    assert len(js_files) == 4, f"Expected 4 JS files, found {len(js_files)}"
    for js in js_files:
        res = subprocess.run(
            ["node", "--input-type=module", "--check"],
            input=js.read_text(encoding="utf-8"),
            capture_output=True,
            text=True,
        )
        if res.returncode != 0:
            raise AssertionError(f"node --check failed for {js.name}: {res.stderr}")
    print(f"PASS: JS ES module syntax ({len(js_files)} files)")


def check_module_prop() -> str:
    lines = (MODULE_DIR / "module.prop").read_text(encoding="utf-8").splitlines()
    props = {}
    for line in lines:
        if line.strip() and not line.strip().startswith("#"):
            assert "=" in line, f"Invalid line in module.prop: {line}"
            k, v = line.split("=", 1)
            props[k.strip()] = v.strip()
    missing = REQUIRED_PROP_KEYS - set(props)
    assert not missing, f"Missing module.prop keys: {missing}"
    assert props["id"] == "caventus_oriole_ram"
    assert props["version"] == "v1.3.0"
    assert props["versionCode"] == "130"
    print(f"PASS: module.prop ({props['id']} {props['version']})")
    return props["version"]


def check_system_prop() -> None:
    lines = (MODULE_DIR / "system.prop").read_text(encoding="utf-8").splitlines()
    props = {}
    for idx, raw in enumerate(lines, 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        assert "=" in line, f"Invalid system.prop line {idx}: {raw}"
        k, v = line.split("=", 1)
        props[k.strip()] = v.strip()
    for k, expected in REQUIRED_SYSTEM_PROPS.items():
        actual = props.get(k)
        assert actual == expected, f"system.prop {k}: expected {expected!r}, got {actual!r}"
    sf_keys = [k for k in props if k.startswith("ro.surface_flinger.")]
    assert not sf_keys, f"Default system.prop must be boot-safe without SurfaceFlinger props: {sf_keys}"
    print(f"PASS: system.prop ({len(props)} properties, boot-safe)")


def check_shell_unit_tests() -> None:
    ctl = MODULE_DIR / "bin" / "caventus-ctl.sh"
    with tempfile.TemporaryDirectory(dir="/var/tmp") as tmpdir:
        sb = Path(tmpdir)
        (sb / "mod").mkdir()
        test_script = f"""
set -eu
export CAVENTUS_SOURCE_ONLY=1
. "{ctl}"

# 1. pick_zram_algo, extract_bracketed_token & token_in_list
[ "$(pick_zram_algo "lz77eh" "zstd lz4 lzo-rle lzo [lz77eh]")" = "lz77eh" ]
[ "$(pick_zram_algo "lz77eh" "zstd lz4 lzo-rle")" = "zstd" ]
[ "$(pick_zram_algo "zstd" "zstd lz4 lzo-rle lzo [lz77eh]")" = "zstd" ]
[ "$(pick_zram_algo "zstd" "lz4 lzo-rle [lzo]")" = "lz4" ]
if pick_zram_algo "zstd" "unknown_algo" >/dev/null 2>&1; then exit 1; fi
[ "$(extract_bracketed_token "coarse_demand [adaptive] always_on")" = "adaptive" ]
[ "$(extract_bracketed_token "[mq-deadline] kyber bfq none")" = "mq-deadline" ]
token_in_list "kyber" "[mq-deadline] kyber bfq none"
token_in_list "mq-deadline" "[mq-deadline] kyber bfq none"
if token_in_list "noop" "[mq-deadline] kyber bfq none" >/dev/null 2>&1; then exit 1; fi

# 2. can_safely_swapoff
can_safely_swapoff 307200 3072000 80
if can_safely_swapoff 2764800 1254016 80; then exit 1; fi

# 3. validate_config_kv whitelist & injection guard (including v1.2.0 GS101 keys)
validate_config_kv ZRAM_SIZE_MB 4096
validate_config_kv ZRAM_ALGO zstd
validate_config_kv MMD_ZRAM_SYNC 1
validate_config_kv THP_MODE madvise
validate_config_kv SCHED_PROFILE ptune
validate_config_kv CPU_RATE_PROFILE responsive
validate_config_kv IO_SCHEDULER kyber
validate_config_kv IO_READ_AHEAD_KB 0
validate_config_kv IO_NR_REQUESTS 512
validate_config_kv GPU_POWER_POLICY adaptive
validate_config_kv GPU_DVFS_PERIOD_MS 20
validate_config_kv SF_TUNING_MODE ptune
validate_config_kv WATCHDOG_ENABLED 1
validate_config_kv ART_DEX2OAT_FILTER speed-profile
validate_config_kv ACTION_MODE both
if validate_config_kv ZRAM_SIZE_MB "4096; id" >/dev/null 2>&1; then exit 1; fi
if validate_config_kv ZRAM_SIZE_MB 99999 >/dev/null 2>&1; then exit 1; fi
if validate_config_kv ZRAM_ALGO badalgo >/dev/null 2>&1; then exit 1; fi
if validate_config_kv SCHED_PROFILE invalid >/dev/null 2>&1; then exit 1; fi
if validate_config_kv IO_READ_AHEAD_KB 2048 >/dev/null 2>&1; then exit 1; fi
if validate_config_kv IO_NR_REQUESTS 16 >/dev/null 2>&1; then exit 1; fi
if validate_config_kv GPU_DVFS_PERIOD_MS 5 >/dev/null 2>&1; then exit 1; fi
if validate_config_kv SF_TUNING_MODE "ptune; rm" >/dev/null 2>&1; then exit 1; fi
if validate_config_kv UNKNOWN_KEY 1 >/dev/null 2>&1; then exit 1; fi

# 4. Sandbox init-defaults + save-config + sync_system_prop (ptune, off, mmd_sync)
export CAVENTUS_SOURCE_ONLY=0
export CAVENTUS_MODDIR="{sb}/mod"
export CAVENTUS_CONFIG_ENV="{sb}/config.env"
export CAVENTUS_LOG_FILE="{sb}/caventus.log"
export CAVENTUS_LOCK_FILE="{sb}/recompile.lock"
export CAVENTUS_WATCHDOG_PID_FILE="{sb}/watchdog.pid"
export CAVENTUS_NO_WATCHDOG=1

sh "{ctl}" init-defaults >/dev/null
grep -q '^ZRAM_ALGO=lz77eh$' "{sb}/config.env"
grep -q '^SF_TUNING_MODE=off$' "{sb}/config.env"
grep -q '^VM_WATERMARK_SCALE_FACTOR=65$' "{sb}/config.env"
grep -q '^IO_NR_REQUESTS=128$' "{sb}/config.env"
grep -q '^mmd.zram.comp_algorithm=lz77eh$' "{sb}/mod/system.prop"
if grep -q '^ro\\.surface_flinger\\.' "{sb}/mod/system.prop"; then exit 1; fi

sh "{ctl}" save-config ZRAM_SIZE_MB=5120 ART_DEX2OAT_FILTER=speed LMKD_PSI_PARTIAL_MS=40 SCHED_PROFILE=ptune SF_TUNING_MODE=ptune IO_READ_AHEAD_KB=0 >/dev/null
grep -q '^ZRAM_SIZE_MB=5120$' "{sb}/config.env"
grep -q '^SCHED_PROFILE=ptune$' "{sb}/config.env"
grep -q '^dalvik.vm.dex2oat-filter=speed$' "{sb}/mod/system.prop"
grep -q '^ro.lmk.psi_partial_stall_ms=40$' "{sb}/mod/system.prop"
grep -q '^mmd.zram.size=5368709120$' "{sb}/mod/system.prop"
grep -q '^ro.surface_flinger.max_frame_buffer_acquired_buffers=6$' "{sb}/mod/system.prop"
grep -q '^ro.surface_flinger.game_default_frame_rate_override=90$' "{sb}/mod/system.prop"

sh "{ctl}" save-config SF_TUNING_MODE=off MMD_ZRAM_SYNC=0 >/dev/null
if grep -q '^ro\\.surface_flinger\\.' "{sb}/mod/system.prop"; then exit 1; fi
if grep -q '^mmd\\.zram\\.' "{sb}/mod/system.prop"; then exit 1; fi

sh "{ctl}" save-config SF_TUNING_MODE=ram_safe MMD_ZRAM_SYNC=1 >/dev/null
grep -q '^ro.surface_flinger.clear_slots_with_set_layer_buffer=true$' "{sb}/mod/system.prop"
grep -q '^mmd.zram.enabled=true$' "{sb}/mod/system.prop"

# 5. status-json emits valid JSON with all v1.2.0 sections
sh "{ctl}" status-json > "{sb}/status.json"
"""
        res = subprocess.run(["sh", "-c", test_script], capture_output=True, text=True)
        if res.returncode != 0:
            raise AssertionError(f"Shell unit tests failed:\nSTDOUT:{res.stdout}\nSTDERR:{res.stderr}")

        status_data = json.loads((sb / "status.json").read_text(encoding="utf-8"))
        for key in ("device", "ram", "zram", "vm", "thp", "sched", "cpufreq", "io", "gpu", "sf", "lmkd", "art", "watchdog_running", "config"):
            assert key in status_data, f"Missing key {key} in status-json"
        assert status_data["config"]["ZRAM_SIZE_MB"] == 5120
        assert status_data["config"]["ART_DEX2OAT_FILTER"] == "speed"
        assert status_data["config"]["SCHED_PROFILE"] == "ptune"
        assert status_data["config"]["IO_READ_AHEAD_KB"] == 0
        assert status_data["config"]["SF_TUNING_MODE"] == "ram_safe"
        assert status_data["config"]["MMD_ZRAM_SYNC"] == 1

    print("PASS: shell unit tests (zram, swapoff guard, config validator, sync_system_prop, status-json)")


def check_zip_artifact(version: str) -> None:
    zip_path = DIST_DIR / f"caventus-oriole-{version}.zip"
    sha_path = DIST_DIR / f"caventus-oriole-{version}.zip.sha256"
    assert zip_path.is_file(), f"Missing {zip_path}"
    assert sha_path.is_file(), f"Missing {sha_path}"

    expected_entries = {
        p.relative_to(MODULE_DIR).as_posix()
        for p in MODULE_DIR.rglob("*")
        if p.is_file()
    }
    required_webui = {
        "webroot/index.html",
        "webroot/css/app.css",
        "webroot/js/presets.js",
        "webroot/js/theme.js",
        "webroot/js/bridge.js",
        "webroot/js/app.js",
    }
    assert required_webui.issubset(expected_entries), "Missing webroot files"

    with zipfile.ZipFile(zip_path, "r") as zf:
        names = set(zf.namelist())
        assert names == expected_entries, f"Zip mismatch: extra={names - expected_entries}, missing={expected_entries - names}"
        assert not any(n.startswith("module/") for n in names), "Zip must not nest under module/"
        assert not any(n.startswith("system/") for n in names), "Module must remain overlay-free"
        for info in zf.infolist():
            mode = (info.external_attr >> 16) & 0o777
            if info.filename.endswith(".sh") or info.filename.endswith("update-binary"):
                assert mode == 0o755, f"Expected 0755 for {info.filename}, got {oct(mode)}"

    expected_hash = sha_path.read_text(encoding="utf-8").split()[0]
    actual_hash = hashlib.sha256(zip_path.read_bytes()).hexdigest()
    assert actual_hash == expected_hash, f"SHA256 mismatch: {actual_hash} != {expected_hash}"
    print(f"PASS: zip artifact ({zip_path.name}, {len(expected_entries)} entries, sha256 verified)")


def main() -> int:
    check_lf_line_endings()
    check_shell_syntax()
    check_js_syntax()
    version = check_module_prop()
    check_system_prop()
    check_shell_unit_tests()
    check_zip_artifact(version)
    print("ALL CHECKS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
