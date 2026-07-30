#!/usr/bin/env python3
"""Rebuild TI's ROM tutorial with its preserved original DOS toolchain."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

from prepare_workloads import ROOT, WORK, extract_disk, load_image_sha256, parse_coff, sha256


EXPECTED_COFF_SHA256 = (
    "cf332d767088f1d9cd4f2dc8d5d4ea7001633e1ae4806704da35efa068ec0d08"
)
EXPECTED_LOAD_SHA256 = (
    "c37fc1d12a47c0e2b4878ea5feff577fbee0c7da81d3105f45a072cb8cc73a2c"
)


def find_dosbox(requested: str | None) -> Path:
    candidates: list[str] = []
    if requested:
        candidates.append(requested)
    if os.environ.get("DOSBOX"):
        candidates.append(os.environ["DOSBOX"])
    discovered = shutil.which("dosbox")
    if discovered:
        candidates.append(discovered)
    # A locally unpacked package is a convenient, ignored cache; it is never
    # treated as source or committed.
    candidates.append(str(WORK / "dosbox-pkg/usr/bin/dosbox"))
    for candidate in candidates:
        path = Path(candidate).expanduser().resolve()
        if path.is_file() and os.access(path, os.X_OK):
            return path
    raise RuntimeError(
        "DOSBox is unavailable; install dosbox or pass --dosbox /path/to/dosbox"
    )


def build(dosbox: Path) -> Path:
    assembler = extract_disk("assembler")
    sources = extract_disk("rom_sources")
    prebuilt = extract_disk("rom_prebuilt") / "TUTOR_C.OUT"
    build_dir = WORK / "rom_demo_build"
    if build_dir.exists():
        shutil.rmtree(build_dir)
    build_dir.mkdir(parents=True)

    for name in ("GSPA.EXE", "GSPLNK.EXE"):
        shutil.copy2(assembler / name, build_dir / name)
    for name in (
        "TUTOR_C.ASM",
        "TUTOR_C.CMD",
        "TUTOR.INC",
        "DATA.ASM",
        "LABEL.ASM",
    ):
        shutil.copy2(sources / name, build_dir / name)

    # DOSBox receives a short, deterministic batch file in ignored work space.
    # ERRORLEVEL checks make tool failures visible even though DOSBox itself
    # normally exits successfully.
    (build_dir / "BUILD.BAT").write_text(
        "@echo off\r\n"
        "gspa -l tutor_c\r\n"
        "if errorlevel 1 goto fail\r\n"
        "gspa data\r\n"
        "if errorlevel 1 goto fail\r\n"
        "gspa label\r\n"
        "if errorlevel 1 goto fail\r\n"
        "gsplnk tutor_c.cmd\r\n"
        "if errorlevel 1 goto fail\r\n"
        "echo PASS>BUILD.OK\r\n"
        "goto done\r\n"
        ":fail\r\n"
        "echo FAIL>BUILD.OK\r\n"
        ":done\r\n"
        "exit\r\n",
        encoding="ascii",
        newline="",
    )
    environment = os.environ.copy()
    environment.setdefault("SDL_VIDEODRIVER", "dummy")
    environment.setdefault("SDL_AUDIODRIVER", "dummy")
    private_lib = dosbox.parent.parent / "lib"
    if private_lib.is_dir():
        inherited = environment.get("LD_LIBRARY_PATH")
        environment["LD_LIBRARY_PATH"] = (
            f"{private_lib}:{inherited}" if inherited else str(private_lib)
        )
    subprocess.run(
        [
            str(dosbox),
            "-noconsole",
            "-c",
            f"mount c {build_dir}",
            "-c",
            "c:",
            "-c",
            "build.bat",
        ],
        check=True,
        env=environment,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=120,
    )
    marker = build_dir / "BUILD.OK"
    output = build_dir / "TUTOR_C.OUT"
    if not marker.is_file() or marker.read_text(
        encoding="ascii", errors="replace"
    ).strip() != "PASS":
        raise RuntimeError("preserved TI assembler/linker reported a build failure")
    if not output.is_file():
        raise RuntimeError("preserved TI linker did not produce TUTOR_C.OUT")

    output_hash = sha256(output)
    if output_hash != EXPECTED_COFF_SHA256:
        raise RuntimeError(
            f"rebuilt TUTOR_C.OUT SHA256 {output_hash}, "
            f"expected {EXPECTED_COFF_SHA256}"
        )
    load_hash = load_image_sha256(parse_coff(output))
    prebuilt_load_hash = load_image_sha256(parse_coff(prebuilt))
    if load_hash != EXPECTED_LOAD_SHA256 or load_hash != prebuilt_load_hash:
        raise RuntimeError(
            "rebuilt and prebuilt ROM tutorial load images are not identical"
        )
    return output


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dosbox", help="explicit DOSBox executable")
    args = parser.parse_args()
    try:
        dosbox = find_dosbox(args.dosbox)
        output = build(dosbox)
        print(
            "build_rom_demo.py: PASS "
            f"coff_sha256={sha256(output)} "
            f"load_sha256={load_image_sha256(parse_coff(output))} "
            f"output={output.relative_to(ROOT)}"
        )
        return 0
    except (
        OSError,
        RuntimeError,
        ValueError,
        subprocess.CalledProcessError,
        subprocess.TimeoutExpired,
    ) as exc:
        print(f"build_rom_demo.py: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
