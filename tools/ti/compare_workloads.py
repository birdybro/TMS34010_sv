#!/usr/bin/env python3
"""Lock live TI workload results and close every MAME/RTL difference."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "sim/vectors/ti_workload_manifest.json"
MAME_EXPECTED = ROOT / "sim/vectors/ti_workload_mame_expected.txt"
RTL_EXPECTED = ROOT / "sim/vectors/ti_workload_rtl_expected.txt"
LEDGER = ROOT / "sim/vectors/ti_workload_divergences.json"


@dataclass(frozen=True)
class Result:
    pc: int
    sp: int
    st: int
    a: tuple[int, ...]
    b: tuple[int, ...]
    io: tuple[int, ...]
    hashes: dict[str, int]


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

    if take() != "TMS34010_TI_RESULTS_V1":
        raise SystemExit(f"{path}: invalid header")
    count = int(take(), 16)
    results: dict[int, Result] = {}
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
        hashes: dict[str, int] = {}
        while tokens[cursor] == "HASH":
            take()
            name = take()
            hashes[name] = int(take(), 16)
        if take() != "END":
            raise SystemExit(f"{path}: expected END")
        if ident in results:
            raise SystemExit(f"{path}: duplicate case {ident:08x}")
        results[ident] = Result(pc, sp, st, a, b, io, hashes)
    if cursor != len(tokens):
        raise SystemExit(f"{path}: trailing tokens")
    return results


def fields(result: Result) -> dict[str, tuple[int, ...]]:
    return {
        "PC": (result.pc,),
        "SP": (result.sp,),
        "ST": (result.st,),
        "A": result.a,
        "B": result.b,
        "IO": result.io,
        **{f"HASH:{name}": (value,) for name, value in result.hashes.items()},
    }


def differing_indices(left: tuple[int, ...], right: tuple[int, ...]) -> tuple[int, ...]:
    if len(left) != len(right):
        return (-1,)
    return tuple(index for index, pair in enumerate(zip(left, right))
                 if pair[0] != pair[1])


def classify(ident: int, field: str, indices: tuple[int, ...]) -> str | None:
    if ident == 0x17300002 and field == "B" and indices == (2, 10, 11, 12, 14):
        return "array_terminal_context"
    if ident == 0x17300005 and field == "B" and indices == (5, 6):
        return "array_terminal_context"
    if (
        ident in {0x17300002, 0x17300003, 0x17300004, 0x17300005}
        and field == "HASH:framebuffer"
    ):
        return "production_graphics_reference_semantics"
    if (
        ident in {0x17300003, 0x17300004, 0x17300005}
        and field == "HASH:program_workspace"
    ):
        return "saved_graphics_context_residue"
    return None


def make_ledger(
    mame: dict[int, Result],
    rtl: dict[int, Result],
    case_names: dict[int, str],
) -> dict[str, object]:
    if set(mame) != set(rtl) or set(mame) != set(case_names):
        raise SystemExit("result and manifest case sets differ")
    counts: Counter[str] = Counter()
    examples: dict[str, list[dict[str, object]]] = {}
    unexplained = []
    for ident in sorted(mame):
        mame_fields = fields(mame[ident])
        rtl_fields = fields(rtl[ident])
        if set(mame_fields) != set(rtl_fields):
            raise SystemExit(f"case {ident:08x}: result field sets differ")
        for field in mame_fields:
            indices = differing_indices(mame_fields[field], rtl_fields[field])
            if not indices:
                continue
            mismatch_class = classify(ident, field, indices)
            item = {
                "case": f"{ident:08x}",
                "name": case_names[ident],
                "field": field,
                "indices": list(indices),
            }
            if mismatch_class is None:
                unexplained.append(item)
            else:
                counts[mismatch_class] += 1
                examples.setdefault(mismatch_class, []).append(item)
    if unexplained:
        raise SystemExit(
            "unexplained MAME/RTL mismatches: "
            + json.dumps(unexplained, sort_keys=True)
        )

    descriptions = {
        "array_terminal_context": (
            "Pinned MAME exposes legacy array scratch/terminal registers; "
            "production RTL follows the TI terminal-context rules closed by "
            "Tasks 0162, 0163, and 0166."
        ),
        "production_graphics_reference_semantics": (
            "The framebuffer is affected only by pinned-MAME legacy "
            "subword, plane-mask, window, direction, or array semantics "
            "already minimized and classified by the complete Task 0172 "
            "differential corpus; production RTL follows the TI User's Guide."
        ),
        "saved_graphics_context_residue": (
            "The watched program/workspace range includes stack slots where "
            "the workload saved legacy MAME graphics scratch context. "
            "Endpoint PC/SP/ST, nonscratch registers, and I/O state agree."
        ),
    }
    classes = [
        {
            "class": name,
            "description": descriptions[name],
            "mismatching_case_field_groups": counts[name],
            "instances": examples[name],
        }
        for name in sorted(counts)
    ]
    return {
        "format": 1,
        "case_count": len(case_names),
        "mame_commit": "70725158b4e9d2e1230c0515faec754f9cee86a2",
        "unexplained_mismatches": 0,
        "classes": classes,
    }


def exact_compare(actual: Path, accepted: Path, label: str) -> None:
    if actual.read_bytes() != accepted.read_bytes():
        raise SystemExit(f"{label} differs from checked-in accepted results")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mame", type=Path, default=MAME_EXPECTED)
    parser.add_argument("--rtl", type=Path, default=RTL_EXPECTED)
    parser.add_argument("--write-ledger", action="store_true")
    args = parser.parse_args()

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    case_names = {
        int(case["id"], 16): str(case["name"]) for case in manifest["cases"]
    }
    mame = parse_results(args.mame)
    rtl = parse_results(args.rtl)
    ledger = make_ledger(mame, rtl, case_names)
    rendered = json.dumps(ledger, indent=2, sort_keys=True) + "\n"
    if args.write_ledger:
        LEDGER.write_text(rendered, encoding="utf-8")
    elif not LEDGER.is_file() or LEDGER.read_text(encoding="utf-8") != rendered:
        raise SystemExit("checked-in TI workload divergence ledger is stale")

    if args.mame != MAME_EXPECTED:
        exact_compare(args.mame, MAME_EXPECTED, "live pinned-MAME output")
    if args.rtl != RTL_EXPECTED:
        exact_compare(args.rtl, RTL_EXPECTED, "live RTL output")
    groups = sum(
        int(item["mismatching_case_field_groups"]) for item in ledger["classes"]
    )
    print(
        f"PASS: {len(case_names)} TI workloads, {groups} classified "
        "case/field groups, 0 unexplained mismatches"
    )


if __name__ == "__main__":
    main()
