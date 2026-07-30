# Pinned MAME graphics differential reference

Task 0172 uses MAME only as a secondary functional reference. The TI 1988
TMS34010 User's Guide remains authoritative. No MAME processor implementation,
generated decode table, or emulator architecture is copied into the RTL.

## Provenance and license boundary

- Upstream: <https://github.com/mamedev/mame>
- Exact revision: `70725158b4e9d2e1230c0515faec754f9cee86a2`
- Referenced core: `src/devices/cpu/tms34010/`
- Upstream core and the local adapter carry BSD-3-Clause headers. The complete
  MAME checkout retains its own per-file licenses and `COPYING`.
- MAME is cloned into ignored `work/` storage. It is not vendored, submoduled,
  redistributed, or linked into the synthesizable design.
- `tools/mame/tms34010_graphics_diff.cpp` is minimal driver glue: it installs a
  RAM map, runs supplied programs, and serializes public architectural state.

The setup script rejects every MAME commit except the one above. It copies the
adapter into the cached checkout and adds one cache-local driver-list entry;
the upstream TMS34010 core is not modified.

## Running

The ordinary regression needs only the checked-in accepted vectors:

```sh
scripts/sim.sh tb_mame_graphics_replay
```

The first live run is an explicit network/build operation:

```sh
scripts/mame_graphics_diff.sh --setup
```

Later runs reuse the ignored exact-revision cache:

```sh
scripts/mame_graphics_diff.sh
```

`MAME_CACHE_DIR` selects another exact-revision checkout and
`MAME_BUILD_JOBS` controls the external build. A missing cache fails with the
exact opt-in setup command rather than silently skipping reference coverage.

The one command:

1. verifies the generator and pinned Git revision;
2. builds the minimal MAME target;
3. runs all 137 cases through the unmodified pinned core;
4. runs the same programs and memory images through RTL;
5. compares each live output byte-for-byte with its checked-in accepted file;
6. regenerates the cross-reference comparison in memory and rejects an
   unclassified MAME/RTL difference.

## Corpus and replay contract

`tools/mame/generate_graphics_vectors.py` deterministically emits:

- `sim/vectors/mame_graphics_vectors.txt`, the identical program/memory input;
- `sim/vectors/mame_graphics_manifest.json`, hashes, opcodes, names, and tags.

Each bootstrap initializes all A and B registers, ST, and DPYCTL, CONTROL,
CONVSP, CONVDP, PSIZE, and PMASK before one selected graphics instruction. A
stable terminal loop makes PC/state capture deterministic. Both engines report
PC, SP, ST, A0-A14, B0-B14, the six graphics I/O registers, and a fixed
512-word framebuffer window.

The 137 cases cover:

- all 16 Boolean PPOP values at PSIZE 1/2/4/8/16;
- arithmetic PPOP 10-15 at every defined PSIZE 4/8/16;
- PIXT linear/XY store, load, and memory-to-memory forms, DRAV, LINE, both
  FILL forms, and all six full-color/binary PIXBLT forms;
- physical PMASK and transparency combinations;
- W=0/1/2/3;
- three source/destination pitches;
- all PBH/PBV pairs;
- empty, zero-height, zero-width, singleton, and physical-word-edge arrays;
- final endpoints for FILL, PIXBLT, and LINE interrupt/resume equivalence.

The checked-in outputs are:

- `mame_graphics_reference.txt`: the exact pinned MAME result;
- `mame_graphics_expected.txt`: the accepted production RTL result;
- `mame_graphics_divergences.json`: every differing case/field group, its
  class, count, and smallest corpus reproducer.

## Classified secondary-reference differences

The comparator reports zero unexplained mismatches. The remaining classes are
intentional and do not supersede TI behavior:

| Class | Scope and source-backed resolution |
| --- | --- |
| Endpoint PC observation | MAME holds PC on the `JRUC -1` instruction; RTL's `pc_o` exposes the postfetch address. Program completion and all architectural writes agree. |
| Array terminal context | Pinned MAME exposes legacy scratch values after FILL/PIXBLT. TI User's Guide array completion rules and Tasks 0162/0166 require the RTL's published terminal/checkpoint B-register image. |
| Directional array context | Pinned MAME differs in PBH/PBV corner/context publication. TI PIXBLT direction pages and Task 0163 are authoritative. |
| Array extent/context | Empty, singleton, and physical-word-edge extent endpoints differ in selected status/context fields. TI array definitions and Task 0162 resolve the RTL behavior. |
| Atomic checkpoint limit | MAME executes one graphics opcode atomically, so it cannot expose the TI mid-array images used by Tasks 0166-0168. Final framebuffer/state endpoints remain differential evidence; exhaustive RTL checkpoint/resume benches supply the intra-instruction proof. |

Exact case/field counts and minimized reproducers live in the generated JSON
ledger. `compare_graphics_results.py` has no fallback class: any new field
difference without a declared rule fails the suite.
