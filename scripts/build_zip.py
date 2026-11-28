#!/usr/bin/env python3
"""Deterministic packager for the Caventus KernelSU module."""

from __future__ import annotations

import hashlib
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parent.parent
MODULE_DIR = ROOT / "module"
DIST_DIR = ROOT / "dist"
FIXED_ZIP_DT = (2026, 11, 24, 0, 0, 0)


def read_module_prop(prop_path: Path) -> dict[str, str]:
    props: dict[str, str] = {}
    for raw in prop_path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        props[k.strip()] = v.strip()
    return props


def is_executable_entry(rel_path: str) -> bool:
    return rel_path.endswith(".sh") or rel_path == "META-INF/com/google/android/update-binary"


def build_zip() -> tuple[Path, Path]:
    props = read_module_prop(MODULE_DIR / "module.prop")
    version = props.get("version", "")
    if not re.fullmatch(r"v\d+\.\d+\.\d+(?:-[A-Za-z0-9.]+)?", version):
        raise ValueError(f"Invalid version in module.prop: {version!r}")

    DIST_DIR.mkdir(parents=True, exist_ok=True)
    for old in DIST_DIR.glob("caventus-oriole-*.zip*"):
        old.unlink()

    zip_path = DIST_DIR / f"caventus-oriole-{version}.zip"
    sha_path = DIST_DIR / f"caventus-oriole-{version}.zip.sha256"

    files = sorted(p for p in MODULE_DIR.rglob("*") if p.is_file())
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for file_path in files:
            rel = file_path.relative_to(MODULE_DIR).as_posix()
            info = zipfile.ZipInfo(filename=rel, date_time=FIXED_ZIP_DT)
            info.create_system = 3  # Unix
            mode = 0o755 if is_executable_entry(rel) else 0o644
            info.external_attr = (0o100000 | mode) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            zf.writestr(info, file_path.read_bytes())

    digest = hashlib.sha256(zip_path.read_bytes()).hexdigest()
    sha_path.write_text(f"{digest}  {zip_path.name}\n", encoding="utf-8")
    print(f"Built {zip_path.relative_to(ROOT)} ({zip_path.stat().st_size} bytes)")
    print(f"SHA256: {digest}")
    return zip_path, sha_path


if __name__ == "__main__":
    build_zip()
