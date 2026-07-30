#!/usr/bin/env python3
"""Generate deterministic programs for the pinned MAME/RTL graphics corpus."""

from __future__ import annotations

import argparse
import hashlib
import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parents[2]
VECTOR_PATH = ROOT / "sim/vectors/mame_graphics_vectors.txt"
MANIFEST_PATH = ROOT / "sim/vectors/mame_graphics_manifest.json"
EXPECTED_PATH = ROOT / "sim/vectors/mame_graphics_expected.txt"
REFERENCE_PATH = ROOT / "sim/vectors/mame_graphics_reference.txt"

IO_BASE = 0xC0000000
IO_DPYCTL = IO_BASE + 8 * 0x10
IO_CONTROL = IO_BASE + 11 * 0x10
IO_CONVSP = IO_BASE + 19 * 0x10
IO_CONVDP = IO_BASE + 20 * 0x10
IO_PSIZE = IO_BASE + 21 * 0x10
IO_PMASK = IO_BASE + 22 * 0x10

FB_WORD = 0x0800
FB_BIT = FB_WORD * 16
WATCH_WORDS = 0x0200
DONE_PREFIX = 0xD1720000


def movi_a(reg: int, value: int) -> list[int]:
    return [0x09E0 | reg, value & 0xFFFF, (value >> 16) & 0xFFFF]


def movi_b(reg: int, value: int) -> list[int]:
    return [0x09F0 | reg, value & 0xFFFF, (value >> 16) & 0xFFFF]


def store_abs(reg: int, address: int) -> list[int]:
    return [0x0580 | reg, address & 0xFFFF, (address >> 16) & 0xFFFF]


@dataclass
class Vector:
    ident: int
    name: str
    tags: list[str]
    opcode: int
    psize: int = 8
    control: int = 0
    pmask: int = 0
    convsp: int = 23
    convdp: int = 23
    dpyctl: int = 0
    a: list[int] = field(default_factory=lambda: [
        0xA0000000 + index for index in range(15)
    ])
    b: list[int] = field(default_factory=lambda: [
        0xB0000000 + index for index in range(15)
    ])
    st: int = 0x00000010
    memory: dict[int, int] = field(default_factory=dict)

    def program(self) -> list[int]:
        words: list[int] = [0x0550]  # SETF FS0=16
        for reg, value in enumerate(self.a):
            words += movi_a(reg, value)
        for reg, value in enumerate(self.b):
            words += movi_b(reg, value)
        for address, value in (
            (IO_DPYCTL, self.dpyctl),
            (IO_CONTROL, self.control),
            (IO_CONVSP, self.convsp),
            (IO_CONVDP, self.convdp),
            (IO_PSIZE, self.psize),
            (IO_PMASK, self.pmask),
        ):
            words += movi_a(0, value)
            words += store_abs(0, address)
        words += movi_a(0, self.a[0])
        words += movi_a(13, self.st)
        words += [0x01AD]  # PUTST A13
        words += [self.opcode]
        words += movi_a(14, DONE_PREFIX | self.ident)
        words += [0xC0FF]  # JRUC -1: stable endpoint for scheduled MAME capture
        return words


def seed_memory(vector: Vector) -> None:
    for offset in range(WATCH_WORDS):
        value = ((offset * 0x9E37) ^ (vector.ident * 0x45D9) ^ 0xA55A) & 0xFFFF
        vector.memory[FB_WORD + offset] = value


def base_vector(ident: int, name: str, tags: Iterable[str], opcode: int) -> Vector:
    vector = Vector(ident=ident, name=name, tags=list(tags), opcode=opcode)
    seed_memory(vector)
    vector.a[1] = 0x000000A5
    vector.a[2] = FB_BIT + 0x112
    vector.b[0] = FB_BIT + 0x0200
    vector.b[1] = 0x00000100
    vector.b[2] = FB_BIT + 0x0800
    vector.b[3] = 0x00000100
    vector.b[4] = FB_BIT
    vector.b[5] = (1 << 16) | 1
    vector.b[6] = (8 << 16) | 8
    vector.b[7] = (2 << 16) | 3
    vector.b[8] = 0x3C3C3C3C
    vector.b[9] = 0xA5A5A5A5
    vector.b[10] = 3
    vector.b[11] = 0x00010000
    vector.b[12] = 0x00010000
    vector.b[13] = 0x5A5A5A5A
    vector.b[14] = 0
    return vector


def build_vectors() -> list[Vector]:
    vectors: list[Vector] = []
    ident = 0

    # Complete defined PPOP/PSIZE domain.  A register-to-linear PIXT isolates
    # the pixel equation while using a deliberately unaligned destination.
    for psize in (1, 2, 4, 8, 16):
        for ppop in range(0x16):
            if ppop >= 0x10 and psize < 4:
                continue
            vector = base_vector(
                ident,
                f"ppop_{ppop:02x}_psize_{psize}",
                ["pixt", f"psize:{psize}", f"ppop:{ppop:02x}"],
                0xF800 | (1 << 5) | 2,
            )
            vector.psize = psize
            vector.control = ppop << 10
            vector.a[1] = 0x0000A55A
            vector.a[2] = FB_BIT + 0x100 + ((ident * psize) & 0xF)
            vectors.append(vector)
            ident += 1

    forms = [
        ("pixt_linear_store", 0xF822, ["pixt", "linear", "store"]),
        ("pixt_xy_store", 0xF022, ["pixt", "xy", "store"]),
        ("pixt_linear_load", 0xFA22, ["pixt", "linear", "load"]),
        ("pixt_xy_load", 0xF222, ["pixt", "xy", "load"]),
        ("pixt_linear_m2m", 0xFC22, ["pixt", "linear", "m2m"]),
        ("pixt_xy_m2m", 0xF422, ["pixt", "xy", "m2m"]),
        ("drav", 0xF622, ["drav", "xy"]),
        ("line", 0xDF1A, ["line", "array"]),
        ("fill_linear", 0x0FC0, ["fill", "linear", "array"]),
        ("fill_xy", 0x0FE0, ["fill", "xy", "array"]),
        ("pixblt_ll", 0x0F00, ["pixblt", "linear", "array"]),
        ("pixblt_lxy", 0x0F20, ["pixblt", "mixed", "array"]),
        ("pixblt_xyl", 0x0F40, ["pixblt", "mixed", "array"]),
        ("pixblt_xyxy", 0x0F60, ["pixblt", "xy", "array"]),
        ("pixblt_bl", 0x0F80, ["pixblt", "binary", "linear", "array"]),
        ("pixblt_bxy", 0x0FA0, ["pixblt", "binary", "xy", "array"]),
    ]
    for form_index, (name, opcode, tags) in enumerate(forms):
        vector = base_vector(ident, name, tags, opcode)
        vector.psize = (1, 2, 4, 8, 16)[form_index % 5]
        vector.a[1] = FB_BIT + 0x0200
        vector.a[2] = FB_BIT + 0x0800
        if "xy" in tags:
            vector.a[1] = (2 << 16) | 2
            vector.a[2] = (3 << 16) | 4
        vector.b[0] = FB_BIT + 0x0200
        vector.b[2] = FB_BIT + 0x0800
        vector.b[7] = (2 << 16) | 3
        if name in ("pixt_xy_store", "drav"):
            vector.a[2] = (3 << 16) | 4
        if name == "pixt_xy_load":
            vector.a[1] = (2 << 16) | 2
        if name == "pixt_xy_m2m":
            vector.a[1] = (2 << 16) | 2
            vector.a[2] = (3 << 16) | 4
        if name == "line":
            vector.b[0] = 0xFFFFFFFD
            vector.b[2] = (2 << 16) | 4
            vector.b[7] = 3
            vector.b[10] = 4
        if name in ("fill_xy", "pixblt_lxy", "pixblt_xyxy", "pixblt_bxy"):
            vector.b[2] = (3 << 16) | 4
        if name in ("pixblt_xyl", "pixblt_xyxy"):
            vector.b[0] = (2 << 16) | 2
        vectors.append(vector)
        ident += 1

    # Orthogonal mode coverage selected by the graphics conformance matrix.
    for mode in range(4):
        vector = base_vector(
            ident,
            f"window_mode_{mode}",
            ["pixt", "xy", f"window:{mode}"],
            0xF022,
        )
        vector.control = mode << 6
        vector.a[2] = ((9 if mode & 1 else 4) << 16) | 4
        vectors.append(vector)
        ident += 1

    for mode, pmask, transparent in (
        ("pmask_low", 0x00F0, False),
        ("pmask_high", 0xF000, False),
        ("transparent_zero", 0, True),
        ("pmask_transparent", 0x0FF0, True),
    ):
        vector = base_vector(
            ident,
            mode,
            ["pixt", "pmask" if pmask else "transparency"],
            0xF822,
        )
        vector.pmask = pmask
        vector.control = 0x20 if transparent else 0
        vector.a[1] = 0 if transparent else 0x5A
        vector.a[2] = FB_BIT + 0x118
        vectors.append(vector)
        ident += 1

    for pitch in (20, 23, 27):
        vector = base_vector(
            ident,
            f"pitch_{pitch}",
            ["pixblt", "xy", f"pitch:{pitch}"],
            0x0F60,
        )
        vector.convsp = pitch
        vector.convdp = pitch
        vector.b[0] = (1 << 16) | 1
        vector.b[2] = (2 << 16) | 3
        vector.b[7] = (1 << 16) | 2
        vectors.append(vector)
        ident += 1

    for direction in range(4):
        vector = base_vector(
            ident,
            f"direction_{direction}",
            ["pixblt", "direction", f"pbh:{direction & 1}",
             f"pbv:{(direction >> 1) & 1}"],
            0x0F60,
        )
        vector.control = ((direction & 1) << 9) | (((direction >> 1) & 1) << 8)
        vector.b[0] = (4 << 16) | 4
        vector.b[2] = (6 << 16) | 6
        vector.b[7] = (2 << 16) | 2
        vectors.append(vector)
        ident += 1

    for dy, dx, label in (
        (0, 0, "empty"),
        (0, 3, "zero_height"),
        (3, 0, "zero_width"),
        (1, 1, "singleton"),
        (1, 16, "word_edge"),
    ):
        vector = base_vector(
            ident,
            f"array_edge_{label}",
            ["fill", "array-edge", label],
            0x0FC0,
        )
        vector.b[7] = ((dy & 0xFFFF) << 16) | (dx & 0xFFFF)
        vectors.append(vector)
        ident += 1

    # MAME executes each graphics opcode atomically.  These vectors lock the
    # architectural endpoints used by the RTL's checkpoint/resume tests; the
    # atomic-observation limitation is classified in the divergence ledger.
    for family, opcode in (("fill", 0x0FC0), ("pixblt", 0x0F00),
                           ("line", 0xDF1A)):
        vector = base_vector(
            ident,
            f"resume_endpoint_{family}",
            [family, "interrupt-resume-endpoint"],
            opcode,
        )
        if family == "line":
            vector.b[0] = 0xFFFFFFFD
            vector.b[2] = (2 << 16) | 4
            vector.b[7] = 3
            vector.b[10] = 4
        vectors.append(vector)
        ident += 1

    return vectors


def render_vectors(vectors: list[Vector]) -> str:
    lines = [f"TMS34010_GRAPHICS_V1 {len(vectors):x}"]
    for vector in vectors:
        program = vector.program()
        memory = sorted(vector.memory.items())
        lines.append(
            f"CASE {vector.ident:08x} {len(program):x} {len(memory):x} "
            f"{FB_WORD:x} {WATCH_WORDS:x}"
        )
        lines.append("PROGRAM")
        lines.extend(f"{word:04x}" for word in program)
        lines.append("MEMORY")
        lines.extend(f"{address:08x} {word:04x}" for address, word in memory)
        lines.append("END")
    return "\n".join(lines) + "\n"


def write_or_check(path: Path, content: str, check: bool) -> None:
    if check:
        if not path.exists() or path.read_text(encoding="ascii") != content:
            raise SystemExit(f"{path.relative_to(ROOT)} is stale; regenerate vectors")
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="ascii")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    vectors = build_vectors()
    vector_text = render_vectors(vectors)
    digest = hashlib.sha256(vector_text.encode("ascii")).hexdigest()
    manifest = {
        "format": 1,
        "generator": "tools/mame/generate_graphics_vectors.py",
        "vector_sha256": digest,
        "case_count": len(vectors),
        "expected_sha256": (
            hashlib.sha256(EXPECTED_PATH.read_bytes()).hexdigest()
            if EXPECTED_PATH.exists()
            else None
        ),
        "reference_sha256": (
            hashlib.sha256(REFERENCE_PATH.read_bytes()).hexdigest()
            if REFERENCE_PATH.exists()
            else None
        ),
        "cases": [
            {
                "id": vector.ident,
                "name": vector.name,
                "opcode": f"{vector.opcode:04x}",
                "tags": vector.tags,
            }
            for vector in vectors
        ],
    }
    manifest_text = json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    write_or_check(VECTOR_PATH, vector_text, args.check)
    write_or_check(MANIFEST_PATH, manifest_text, args.check)
    print(f"generated {len(vectors)} cases, sha256={digest}")


if __name__ == "__main__":
    main()
