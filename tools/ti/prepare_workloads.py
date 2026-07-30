#!/usr/bin/env python3
"""Extract preserved TI media and prepare deterministic workload vectors.

The disk images remain the source of truth.  Extracted executables and the
generated word-level vector are written only below work/ and are never
redistributed by this repository.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import struct
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MEDIA = ROOT / "third_party/TMS34010_Info/tools/original-disks"
WORK = ROOT / "work/ti_workloads"
VECTOR_PATH = WORK / "ti_workload_vectors.txt"
METADATA_PATH = ROOT / "sim/vectors/ti_workload_manifest.json"

DISKS = {
    "rom_sources": (
        "1985-05-20 TMS34010 Assembly Language Package (4 of 4) "
        "ROM-DEMO revD 1604811-1604.img",
        "5fe40c36e33073b9ce332ff23c6499405ea1f6bef24865f01561476686672115",
    ),
    "rom_prebuilt": (
        "1985-05-20 TMS34010 Assembly Language Package (2 of 4) "
        "GSPSIM-COMP revD 1604811-1602.img",
        "9ba15c34b1add956a002ba1e0f22fc35be41b6e95c67a62baa1fda6a98c52244",
    ),
    "assembler": (
        "1985-05-20 TMS34010 Assembly Language Package (1 of 4) "
        "ASM-LNK-ARCH revD 1604811-1601.img",
        "3dd3fe2dd751f3b48ac53409d4c67d72a7564c3c102d3a48acd85de5942d92a9",
    ),
    "sample": (
        "1987-05-19 TMS34010 Sample Function Library Package "
        "rev2547232-1601.img",
        "e929970e757abf4cbccb49b29d22c8821e86ae4925ba4a13f4610a70791cfa2d",
    ),
    "graphics_math": (
        "1987-12-03 TMS34010 Graphics Math Function Library r1.0.img",
        "e1390cc7efb008785f962269286a71e791978fcecf2258e1130516562996068e",
    ),
    "paint": (
        "1987-12-04 TMS34010 GSP Paint.img",
        "15b066507b8e9970523706782946ade8121b4f64e5c6958812cd7ae9bd1a6392",
    ),
}


@dataclass(frozen=True)
class Section:
    name: str
    address: int
    size_bits: int
    file_offset: int
    flags: int
    data: bytes


@dataclass(frozen=True)
class Coff:
    path: Path
    entry: int
    sections: tuple[Section, ...]

    @property
    def load_words(self) -> dict[int, int]:
        words: dict[int, int] = {}
        for section in self.sections:
            if not section.data:
                continue
            if section.address & 15:
                raise ValueError(
                    f"{self.path}: section {section.name} is not word aligned"
                )
            data = section.data
            if len(data) & 1:
                data += b"\x00"
            for offset in range(0, len(data), 2):
                words[(section.address + offset * 8) & 0xFFFFFFFF] = (
                    data[offset] | (data[offset + 1] << 8)
                )
        return words


@dataclass(frozen=True)
class Workload:
    ident: int
    name: str
    category: str
    disk: str
    relative_path: str
    checkpoint: int
    timeout_polls: int
    watches: tuple[tuple[str, int, int], ...]
    patches: tuple[tuple[int, int], ...] = ()
    related_media: tuple[str, ...] = ()


WORKLOADS = (
    Workload(
        0x17300001,
        "rom_tutorial",
        "TI ROM/demo tutorial",
        "rom_prebuilt",
        "TUTOR_C.OUT",
        0x00020270,
        2_000_000,
        (
            ("framebuffer", 0x00000000, 0x20000 // 16),
            ("program_workspace", 0x00020000, (0x4DA00 - 0x20000) // 16),
        ),
        (
            # The original simulator uses TRAP 29 as its display pause.
            # Replace the first pause with a stable breakpoint loop after the
            # border has been drawn; the source/listing fixes this address.
            (0x00020270, 0xC0FF),
        ),
    ),
    Workload(
        0x17300002,
        "sample_function_library",
        "TI Sample Function Library display-list demo",
        "sample",
        "INTERP.OUT",
        0x00080260,
        2_000_000,
        (
            ("framebuffer", 0x00000000, 0x80000 // 16),
            ("program_workspace", 0x00080000, (0x85930 - 0x80000) // 16),
        ),
    ),
    Workload(
        0x17300003,
        "graphics_math_arcs",
        "Math/Graphics Function Library TEST06",
        "paint",
        "TESTS/TEST06.OUT",
        0xFFC01160,
        2_000_000,
        (
            ("framebuffer", 0x00000000, (640 * 480 * 4) // 16),
            ("program_workspace", 0xFFC00000, 0x400000 // 16),
        ),
        (
            # Stop at main's RETS, after all eight pie slices are complete.
            (0xFFC01160, 0xC0FF),
        ),
        ("graphics_math",),
    ),
    Workload(
        0x17300004,
        "graphics_math_transfer",
        "Math/Graphics Function Library TEST09",
        "paint",
        "TESTS/TEST09.OUT",
        0xFFC01570,
        2_000_000,
        (
            ("framebuffer", 0x00000000, (640 * 480 * 4) // 16),
            ("program_workspace", 0xFFC00000, 0x400000 // 16),
        ),
        (
            # Stop at main's RETS after the fifth zoom_rect transfer.
            (0xFFC01570, 0xC0FF),
        ),
        ("graphics_math",),
    ),
    Workload(
        0x17300005,
        "gsp_paint",
        "1987 TI GSP Paint",
        "paint",
        "PAINTLIB/PAINT.OUT",
        0xFFC7EEA0,
        2_000_000,
        (
            ("framebuffer", 0x00000000, (640 * 480 * 4) // 16),
            ("program_workspace", 0xFFC00000, 0x400000 // 16),
        ),
        (
            # host_on is the first operation that requires an attached SDB
            # host. Stop at its documented entry after graphics/text/video
            # initialization and the startup messages have completed.
            (0xFFC7EEA0, 0xC0FF),
        ),
    ),
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require_tool(name: str) -> str:
    value = shutil.which(name)
    if value is None:
        raise RuntimeError(f"required tool is unavailable: {name}")
    return value


def extract_disk(key: str) -> Path:
    filename, expected_hash = DISKS[key]
    image = MEDIA / filename
    if not image.is_file():
        raise RuntimeError(f"preserved media is unavailable: {image}")
    actual_hash = sha256(image)
    if actual_hash != expected_hash:
        raise RuntimeError(
            f"{filename}: SHA256 {actual_hash}, expected {expected_hash}"
        )
    destination = WORK / "extracted" / key
    destination.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            require_tool("mcopy"),
            "-sn",
            "-i",
            str(image),
            "::*",
            str(destination) + "/",
        ],
        check=True,
    )
    return destination


def parse_coff(path: Path) -> Coff:
    blob = path.read_bytes()
    if len(blob) < 20:
        raise ValueError(f"{path}: truncated COFF header")
    magic, section_count, _, _, _, optional_size, _ = struct.unpack_from(
        "<HHLLLHH", blob
    )
    if magic != 0x0090:
        raise ValueError(f"{path}: unexpected TMS340 COFF magic {magic:#06x}")
    if optional_size < 28:
        raise ValueError(f"{path}: executable optional header is absent")
    _, _, _, _, _, entry, _, _ = struct.unpack_from("<HHLLLLLL", blob, 20)
    section_offset = 20 + optional_size
    sections: list[Section] = []
    for index in range(section_count):
        offset = section_offset + index * 40
        if offset + 40 > len(blob):
            raise ValueError(f"{path}: truncated section table")
        (
            raw_name,
            physical,
            _,
            size_bits,
            file_offset,
            _,
            _,
            _,
            _,
            flags,
        ) = struct.unpack_from("<8sLLLLLLHHL", blob, offset)
        name = raw_name.rstrip(b"\x00").decode("ascii", errors="replace")
        byte_count = (size_bits + 7) // 8 if file_offset else 0
        if file_offset + byte_count > len(blob):
            raise ValueError(f"{path}: truncated section {name}")
        sections.append(
            Section(
                name,
                physical,
                size_bits,
                file_offset,
                flags,
                blob[file_offset : file_offset + byte_count]
                if file_offset
                else b"",
            )
        )
    return Coff(path, entry, tuple(sections))


def load_image_sha256(coff: Coff) -> str:
    digest = hashlib.sha256()
    for address, value in sorted(coff.load_words.items()):
        digest.update(struct.pack("<IH", address, value))
    return digest.hexdigest()


def prepare() -> tuple[list[tuple[Workload, Coff, dict[int, int]]], dict]:
    WORK.mkdir(parents=True, exist_ok=True)
    extracted = {key: extract_disk(key) for key in DISKS}
    prepared = []
    cases = []
    for workload in WORKLOADS:
        path = extracted[workload.disk] / workload.relative_path
        if not path.is_file():
            raise RuntimeError(f"workload is absent after extraction: {path}")
        coff = parse_coff(path)
        words = coff.load_words
        for address, value in workload.patches:
            words[address] = value
        prepared.append((workload, coff, words))
        cases.append(
            {
                "id": f"{workload.ident:08x}",
                "name": workload.name,
                "category": workload.category,
                "source_disk": workload.disk,
                "source_path": workload.relative_path,
                "coff_sha256": sha256(path),
                "load_image_sha256": load_image_sha256(coff),
                "entry": f"{coff.entry:08x}",
                "checkpoint": f"{workload.checkpoint:08x}",
                "timeout_polls": workload.timeout_polls,
                "related_media": list(workload.related_media),
                "deterministic_patches": [
                    {"address": f"{address:08x}", "word": f"{value:04x}"}
                    for address, value in workload.patches
                ],
                "sections": [
                    {
                        "name": section.name,
                        "address": f"{section.address:08x}",
                        "size_bits": section.size_bits,
                        "load_sha256": hashlib.sha256(section.data).hexdigest()
                        if section.data
                        else None,
                    }
                    for section in coff.sections
                ],
                "watches": [
                    {"name": name, "address": f"{address:08x}", "words": words}
                    for name, address, words in workload.watches
                ],
            }
        )
    metadata = {
        "format": "tms34010-ti-workloads-v1",
        "copyright_policy": (
            "Metadata only; executables are extracted from preserved "
            "do-not-redistribute media into ignored work space."
        ),
        "disks": {
            key: {"path": filename, "sha256": digest}
            for key, (filename, digest) in DISKS.items()
        },
        "rom_source_build": {
            "commands": [
                "gspa -l tutor_c",
                "gspa data",
                "gspa label",
                "gsplnk tutor_c.cmd",
            ],
            "prebuilt_coff_sha256":
                "9a3ff91300e2470494ae07d422f2ae9b679b2d8b8275702b72309b73223d46bb",
            "rebuilt_coff_sha256":
                "cf332d767088f1d9cd4f2dc8d5d4ea7001633e1ae4806704da35efa068ec0d08",
            "identical_load_image_sha256":
                "c37fc1d12a47c0e2b4878ea5feff577fbee0c7da81d3105f45a072cb8cc73a2c",
            "note": (
                "The preserved linker emits time-dependent COFF metadata; "
                "the rebuilt and prebuilt address/word load images are identical."
            ),
        },
        "cases": cases,
    }
    return prepared, metadata


def write_vector(prepared: list[tuple[Workload, Coff, dict[int, int]]]) -> None:
    with VECTOR_PATH.open("w", encoding="ascii", newline="\n") as stream:
        stream.write(f"TMS34010_TI_WORKLOADS_V1 {len(prepared):x}\n")
        for workload, coff, words in prepared:
            stream.write(
                f"CASE {workload.ident:08x} {coff.entry:08x} "
                f"{workload.checkpoint:08x} {workload.timeout_polls:x} "
                f"{len(words):x} {len(workload.watches):x}\n"
            )
            stream.write("LOAD\n")
            for address, value in sorted(words.items()):
                stream.write(f"{address:08x} {value:04x}\n")
            for name, address, word_count in workload.watches:
                stream.write(f"WATCH {name} {address:08x} {word_count:x}\n")
            stream.write("END\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--write-metadata",
        action="store_true",
        help="refresh the checked-in provenance manifest",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="require generated metadata to match the checked-in manifest",
    )
    args = parser.parse_args()
    if args.check and args.write_metadata:
        parser.error("--check and --write-metadata are mutually exclusive")
    try:
        prepared, metadata = prepare()
        write_vector(prepared)
        rendered = json.dumps(metadata, indent=2, sort_keys=True) + "\n"
        if args.write_metadata:
            METADATA_PATH.write_text(rendered, encoding="utf-8")
        elif args.check:
            if not METADATA_PATH.is_file():
                raise RuntimeError(f"metadata manifest is absent: {METADATA_PATH}")
            if METADATA_PATH.read_text(encoding="utf-8") != rendered:
                raise RuntimeError(
                    "generated TI workload metadata differs; run "
                    "tools/ti/prepare_workloads.py --write-metadata and review"
                )
        print(
            f"prepare_workloads.py: {len(prepared)} workloads, "
            f"vector={VECTOR_PATH.relative_to(ROOT)}"
        )
        return 0
    except (OSError, RuntimeError, ValueError, subprocess.CalledProcessError) as exc:
        print(f"prepare_workloads.py: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
