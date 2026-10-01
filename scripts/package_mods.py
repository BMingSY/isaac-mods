#!/usr/bin/env python3
"""Build independent installable ZIP archives for the mods in this repository."""

import argparse
from pathlib import Path
import re
import xml.etree.ElementTree as ET
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

ROOT = Path(__file__).resolve().parents[1]
MODS = ROOT / "mods"
DIST = ROOT / "dist"


def package_mod(mod: Path) -> Path:
    metadata = ET.parse(mod / "metadata.xml").getroot()
    version = metadata.findtext("version", "").strip()
    if metadata.tag != "metadata" or metadata.findtext("directory") != mod.name:
        raise ValueError(f"{mod.name}: metadata directory must match the folder")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", version):
        raise ValueError(f"{mod.name}: missing or invalid version")
    if not (mod / "main.lua").is_file():
        raise ValueError(f"{mod.name}: missing main.lua")

    files = []
    for path in sorted(mod.rglob("*")):
        if path.is_symlink():
            raise ValueError(f"{mod.name}: symlinks are not supported: {path.name}")
        relative = path.relative_to(mod)
        if any(part.startswith(".") or part == "__pycache__" for part in relative.parts):
            continue
        if path.name in {"disable.it", "log.txt", "Thumbs.db"}:
            continue
        if path.match("save*.dat") or path.suffix == ".pyc":
            continue
        if path.is_file():
            files.append(path)

    DIST.mkdir(exist_ok=True)
    archive = DIST / f"{mod.name}-{version}.zip"
    with ZipFile(archive, "w") as output:
        for path in files:
            # Fixed timestamps and permissions make unchanged builds reproducible.
            info = ZipInfo((Path(mod.name) / path.relative_to(mod)).as_posix())
            info.compress_type = ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            output.writestr(info, path.read_bytes())
    return archive


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mods", nargs="*", help="Mod folder names; defaults to all mods")
    args = parser.parse_args()
    available = {path.name: path for path in MODS.iterdir() if path.is_dir()}
    selected = args.mods or sorted(available)
    for name in selected:
        if name not in available:
            parser.error(f"unknown mod: {name}")
    for name in selected:
        print(package_mod(available[name]).relative_to(ROOT))


if __name__ == "__main__":
    main()
