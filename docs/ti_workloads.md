# Preserved TI graphics software workloads

Task 0173 runs surviving TI-authored TMS34010 software as an integration gate.
It does not add an emulator to the RTL and does not redistribute extracted TI
executables. The pinned disk images remain the source of truth; generated
files are written only below ignored `work/`.

## Provenance and redistribution boundary

`tools/ti/prepare_workloads.py` verifies every source image before extraction.
The exact filenames and SHA-256 values are recorded in
`sim/vectors/ti_workload_manifest.json`:

| Media | SHA-256 |
|---|---|
| ROM demo sources | `5fe40c36e33073b9ce332ff23c6499405ea1f6bef24865f01561476686672115` |
| ROM demo prebuilt/simulator disk | `9ba15c34b1add956a002ba1e0f22fc35be41b6e95c67a62baa1fda6a98c52244` |
| TI assembler/linker | `3dd3fe2dd751f3b48ac53409d4c67d72a7564c3c102d3a48acd85de5942d92a9` |
| Sample Function Library | `e929970e757abf4cbccb49b29d22c8821e86ae4925ba4a13f4610a70791cfa2d` |
| Graphics/Math Function Library | `e1390cc7efb008785f962269286a71e791978fcecf2258e1130516562996068e` |
| 1987 GSP Paint | `15b066507b8e9970523706782946ade8121b4f64e5c6958812cd7ae9bd1a6392` |

Only scripts, metadata, expected text results, and original testbench code are
committed. COFF files, extracted sources, disk contents, generated load
vectors, MAME binaries, and DOSBox caches remain ignored.

## Reproducible ROM build

`tools/ti/build_rom_demo.py` extracts TI's original `GSPA.EXE` and
`GSPLNK.EXE`, then runs the preserved build:

```text
gspa -l tutor_c
gspa data
gspa label
gsplnk tutor_c.cmd
```

DOSBox may be supplied with `--dosbox`, `DOSBOX`, `PATH`, or an ignored local
package cache. The linker embeds variable COFF metadata, so the rebuilt
container hash is
`cf332d767088f1d9cd4f2dc8d5d4ea7001633e1ae4806704da35efa068ec0d08`
while the preserved container differs. The sorted `(bit address, 16-bit
word)` load image is exactly identical in both:
`c37fc1d12a47c0e2b4878ea5feff577fbee0c7da81d3105f45a072cb8cc73a2c`.

## Selected programs and milestones

The loader parses TMS34010 COFF directly, records every section and watch
range, and emits one deterministic text vector used by both engines.

| ID | Workload | Entry | Milestone | Deterministic stop |
|---|---|---:|---:|---|
| `17300001` | ROM tutorial `TUTOR_C.OUT` | `00020000` | `00020270` | first simulator display-pause TRAP replaced by `JRUC -1` after border draw |
| `17300002` | Sample Function Library `INTERP.OUT` | `00080000` | `00080260` | program's natural terminal loop |
| `17300003` | Graphics/Math TEST06 arcs | `ffc107f0` | `ffc01160` | main RETS replaced after all pie slices |
| `17300004` | Graphics/Math TEST09 transfer | `ffc0cb00` | `ffc01570` | main RETS replaced after the fifth zoom transfer |
| `17300005` | 1987 GSP Paint | `ffca1000` | `ffc7eea0` | stop at `host_on`, after graphics/text/video initialization and startup output |

TEST06/TEST09 executables are distributed on the Paint disk and exercise the
Graphics/Math library whose independent library disk is also hash-verified.
Each case has a two-million-poll model timeout. RTL additionally has a hard
testbench watchdog and fails immediately on an illegal opcode.

At each milestone both engines serialize PC, SP, ST, A0–A14, B0–B14, DPYCTL,
CONTROL, CONVSP, CONVDP, PSIZE, PMASK, and FNV-1a hashes over the declared
framebuffer and program/workspace ranges. Exact accepted outputs are stored
separately for MAME and RTL.

## Closed compatibility findings

The surviving programs exposed four integration gaps that short synthetic
graphics opcodes did not:

- SUBI and CMPI IW/IL object code stores the one's complement of the
  source-level immediate, as explicitly drawn on User's Guide pages 12-54,
  12-55, 12-249, and 12-250.
- MMTM and MMFM list masks are asymmetric. MMTM bit 15-N selects R(N);
  MMFM bit N selects R(N). Original TI assembler masks and the published MMFM
  example now lock both independently.
- `MOVE *Rs(SOff),*Rd(DOff)[,F]` and
  `MOVE @SAddr,@DAddr[,F]` were missing even though their MOVB counterparts
  existed.
- Processor field MOVE to the on-chip I/O page must honor the addressed
  subfield and may span two adjacent 16-bit registers. This is required by
  TI library save/restore sequences for CONVDP/PSIZE.

Focused tests cover every correction independently before the software gate.

The pinned MAME result and production RTL result agree exactly for the ROM
tutorial. Across the remaining programs there are nine differing case/field
groups. `tools/ti/compare_workloads.py` accepts only their exact case, field,
and register-index shapes and maps them to Task 0172's minimized production
graphics semantics: legacy array terminal scratch, framebuffer effects of
the already classified subword/plane/window/direction/array behaviors, and
stack/workspace residue from saved legacy scratch values. Endpoint control
state and nonclassified architectural fields agree. The generated
`ti_workload_divergences.json` reports zero unexplained mismatches; any new
value, field, or index is a failure.

## Running the gates

Offline extraction and RTL replay require the preserved submodule media,
Python 3, `mcopy` from mtools, and an RTL simulator:

```sh
python3 tools/ti/prepare_workloads.py --check
scripts/sim.sh tb_ti_workload_replay
```

Rebuild the ROM tutorial with DOSBox:

```sh
python3 tools/ti/build_rom_demo.py
```

The complete live comparison verifies exact MAME commit
`70725158b4e9d2e1230c0515faec754f9cee86a2`, builds its minimal
BSD-3-Clause adapter, runs both engines, byte-locks each output, and applies
the closed divergence ledger:

```sh
# First run only; this is the explicit network/setup action:
scripts/ti_workloads.sh --setup --build-rom

# Later live runs use the pinned ignored cache:
scripts/ti_workloads.sh --build-rom
```

Ordinary regression needs neither network nor a MAME checkout. It regenerates
vectors from the pinned media and compares RTL against the checked-in lock.

## Optional legal arcade-ROM readiness

Arcade ROM availability is not a project completion gate, and this repository
never downloads or commits one. A user who owns a legal set and has built the
full pinned MAME target can run:

```sh
MAME_ARCADE_BIN=/path/to/pinned/mame \
  scripts/mame_arcade_smoke.sh <driver> /path/to/legal/roms
```

The script first runs MAME's ROM verification, then a bounded headless smoke.
It does not interpret a missing or incompatible copyrighted set as an RTL
failure.
