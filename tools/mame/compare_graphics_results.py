#!/usr/bin/env python3
"""Compare pinned-MAME and RTL graphics results with a closed divergence map."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "sim/vectors/mame_graphics_manifest.json"
REFERENCE = ROOT / "sim/vectors/mame_graphics_reference.txt"
EXPECTED = ROOT / "sim/vectors/mame_graphics_expected.txt"
LEDGER = ROOT / "sim/vectors/mame_graphics_divergences.json"


@dataclass(frozen=True)
class Result:
    pc: int
    sp: int
    st: int
    a: tuple[int, ...]
    b: tuple[int, ...]
    io: tuple[int, ...]
    memory: tuple[int, ...]


def parse_results(path: Path) -> dict[int, Result]:
    tokens = path.read_text(encoding="ascii").split()
    cursor = 0

    def take() -> str:
        nonlocal cursor
        if cursor >= len(tokens):
            raise SystemExit(f"{path}: premature end of file")
        value = tokens[cursor]
        cursor += 1
        return value

    if take() != "TMS34010_GRAPHICS_RESULTS_V1":
        raise SystemExit(f"{path}: invalid header")
    count = int(take(), 16)
    result: dict[int, Result] = {}
    for _ in range(count):
        if take() != "CASE":
            raise SystemExit(f"{path}: expected CASE")
        ident = int(take(), 16)
        pc, sp, st = (int(take(), 16) for _ in range(3))
        if take() != "A":
            raise SystemExit(f"{path}: expected A")
        a = tuple(int(take(), 16) for _ in range(15))
        if take() != "B":
            raise SystemExit(f"{path}: expected B")
        b = tuple(int(take(), 16) for _ in range(15))
        if take() != "IO":
            raise SystemExit(f"{path}: expected IO")
        io = tuple(int(take(), 16) for _ in range(6))
        if take() != "MEM":
            raise SystemExit(f"{path}: expected MEM")
        # The committed Task 0172 corpus uses one fixed 512-word watch region.
        memory = tuple(int(take(), 16) for _ in range(512))
        if take() != "END":
            raise SystemExit(f"{path}: expected END")
        result[ident] = Result(pc, sp, st, a, b, io, memory)
    if cursor != len(tokens):
        raise SystemExit(f"{path}: trailing tokens")
    return result


def exact_compare(actual: Path, accepted: Path, label: str) -> None:
    if actual.read_bytes() != accepted.read_bytes():
        raise SystemExit(f"{label} differs from checked-in accepted results")


def fields(result: Result) -> dict[str, tuple[int, ...]]:
    return {
        "PC": (result.pc,),
        "SP": (result.sp,),
        "ST": (result.st,),
        "A": result.a,
        "B": result.b,
        "IO": result.io,
        "MEM": result.memory,
    }


def classify(tags: set[str], field: str) -> str | None:
    if field == "PC":
        return "endpoint_pc_observation"
    if "array-edge" in tags:
        return "array_extent_and_terminal_context"
    if "direction" in tags:
        return "directional_array_context"
    if "interrupt-resume-endpoint" in tags:
        return "atomic_reference_checkpoint_limit"
    if "array" in tags:
        return "array_terminal_context"
    if "pixblt" in tags and field in {"B", "MEM", "ST"}:
        return "array_terminal_context"
    if any(tag.startswith("window:") for tag in tags):
        return "window_mode_reference_gap"
    if "pmask" in tags or "transparency" in tags:
        return "physical_plane_mask_order"
    if "pixt" in tags and field in {"MEM", "ST", "A", "B"}:
        return "subword_pixel_addressing"
    return None


def make_ledger(mame: dict[int, Result], rtl: dict[int, Result],
                cases: dict[int, dict[str, object]]) -> dict[str, object]:
    counts: Counter[str] = Counter()
    first_case: dict[str, int] = {}
    field_counts: Counter[str] = Counter()
    unexplained: list[dict[str, object]] = []

    if set(mame) != set(rtl) or set(mame) != set(cases):
        raise SystemExit("result and manifest case sets differ")
    for ident in sorted(mame):
        mame_fields = fields(mame[ident])
        rtl_fields = fields(rtl[ident])
        tags = set(str(tag) for tag in cases[ident]["tags"])
        for field in mame_fields:
            if mame_fields[field] == rtl_fields[field]:
                continue
            mismatch_class = classify(tags, field)
            if mismatch_class is None:
                unexplained.append({
                    "case": ident,
                    "name": cases[ident]["name"],
                    "field": field,
                    "tags": sorted(tags),
                })
                continue
            counts[mismatch_class] += 1
            field_counts[f"{mismatch_class}:{field}"] += 1
            first_case.setdefault(mismatch_class, ident)
    if unexplained:
        raise SystemExit(
            "unexplained MAME/RTL mismatches: "
            + json.dumps(unexplained[:8], sort_keys=True)
        )

    descriptions = {
        "endpoint_pc_observation":
            "MAME holds PC on JRUC -1; RTL pc_o is the postfetch address.",
        "subword_pixel_addressing":
            "MAME rounds multi-bit pixels through size-specific helpers; "
            "RTL preserves the TI bit-addressed field position.",
        "physical_plane_mask_order":
            "Pinned MAME applies its legacy plane-mask/transparency ordering; "
            "RTL follows the production physical-word rule closed by Task 0169.",
        "window_mode_reference_gap":
            "Pinned MAME logs unsupported window combinations; RTL follows "
            "the production W=0/1/2/3 definitions.",
        "array_terminal_context":
            "Pinned MAME exposes legacy array scratch context; RTL publishes "
            "the production terminal/checkpoint image closed by Tasks 0162/0166.",
        "directional_array_context":
            "Pinned MAME and production RTL differ in PBH/PBV automatic corner "
            "selection and terminal context; Task 0163 is TI-spec authoritative.",
        "array_extent_and_terminal_context":
            "Pinned MAME interprets empty/terminal 16-bit extents differently; "
            "Task 0162 follows the production array definitions.",
        "atomic_reference_checkpoint_limit":
            "MAME executes a graphics opcode atomically and cannot expose TI "
            "mid-array checkpoint/resume images; final framebuffer remains useful.",
    }
    classes = []
    for name in sorted(counts):
        ident = first_case[name]
        classes.append({
            "class": name,
            "description": descriptions[name],
            "mismatching_case_field_groups": counts[name],
            "field_counts": {
                key.split(":", 1)[1]: value
                for key, value in sorted(field_counts.items())
                if key.startswith(name + ":")
            },
            "minimized_reproducer": {
                "case": ident,
                "name": cases[ident]["name"],
                "opcode": cases[ident]["opcode"],
                "tags": cases[ident]["tags"],
            },
        })
    return {
        "format": 1,
        "case_count": len(cases),
        "mame_commit": "70725158b4e9d2e1230c0515faec754f9cee86a2",
        "unexplained_mismatches": 0,
        "classes": classes,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mame", type=Path, default=REFERENCE)
    parser.add_argument("--rtl", type=Path, default=EXPECTED)
    parser.add_argument("--write-ledger", action="store_true")
    args = parser.parse_args()

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    cases = {int(case["id"]): case for case in manifest["cases"]}
    mame = parse_results(args.mame)
    rtl = parse_results(args.rtl)
    ledger = make_ledger(mame, rtl, cases)
    text = json.dumps(ledger, indent=2, sort_keys=True) + "\n"
    if args.write_ledger:
        LEDGER.write_text(text, encoding="utf-8")
    elif not LEDGER.exists() or LEDGER.read_text(encoding="utf-8") != text:
        raise SystemExit("checked-in divergence ledger is stale")

    if args.mame != REFERENCE:
        exact_compare(args.mame, REFERENCE, "live pinned-MAME output")
    if args.rtl != EXPECTED:
        exact_compare(args.rtl, EXPECTED, "live RTL output")
    mismatch_groups = sum(
        int(item["mismatching_case_field_groups"]) for item in ledger["classes"]
    )
    print(
        f"PASS: {len(cases)} cases, {mismatch_groups} classified "
        "case/field groups, 0 unexplained mismatches"
    )


if __name__ == "__main__":
    main()
