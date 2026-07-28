# Memory map

> Status: **implemented at the architectural/simulation boundary**. The core
> issues bit-addressed 1–32-bit accesses and the simulation memory model
> handles unaligned/straddling fields. The on-chip I/O page is decoded and
> stored in the core. Physical external-bus translation and several I/O side
> effects remain open.

## Architectural address space

The TMS34010 uses a **32-bit bit-addressed** memory model. Address bits
[31:4] select a 16-bit word in external memory; address bits [3:0] select
a bit within that word.

```
   bit 31                                  bit 4 bit 3      bit 0
   ┌──────────────────────────────────────┐─────┬───────────┐
   │           word address (28 bits)     │     │ bit offset│
   └──────────────────────────────────────┘─────┴───────────┘
```

Field operations specify a **field size** (1–32 bits) and read/write that
many bits starting at the byte address, crossing word boundaries as needed.

The simulation memory model (`sim/models/sim_memory_model.sv`) implements
this field semantics as of Task 0076: 1–32-bit reads/writes at any bit address,
straddling 16-bit words, with read-modify-write preservation of surrounding
bits. Tasks 0077–0079 wired field size, FE-driven extension, unaligned access,
and FS-aware pointer stepping through every implemented MOVE form. Pixel
operations similarly drive `mem_size` from PSIZE.

External memory glue (outside the core) is responsible for translating
bit addresses to whatever the physical memory expects. The core's memory
interface (see `docs/architecture.md`) exposes the bit address directly.

## Architectural vector words

Reset and TRAP 0 read the same 32-bit level-0 vector at bit address
`0xFFFF_FFE0` (1988 User's Guide pages 8-10 and 8-12). Task 0121 makes
`CORE_RESET` issue that read before the first instruction fetch.

The simulation model is intentionally much smaller than the architectural
address space. It therefore exposes a dedicated public `level0_vector` word
instead of folding `0xFFFF_FFE0` through its low index bits and aliasing an
ordinary program/data word. The word defaults to zero for focused programs
that begin at word zero; `tb_reset_vector` assigns a nonzero value, and
`tb_trap0` retargets it after boot for the later software trap.

Illegal opcodes use the 32-bit vector-30 word at bit address `0xFFFF_FC20`
(1988 User's Guide §8.7). Unlike the dedicated level-0 test-model word, this
and other nonzero trap vectors currently fold through the bounded backing
store's low address-index bits. `tb_illegal_opcode` verifies the full
architectural bus address before the model applies that simulation alias.

## I/O register space

The TMS34010 maps 32 on-chip 16-bit I/O registers into the bit-address
range `0xC0000000`–`0xC00001FF` (1988 User's Guide Figure 6-1, page 6-3).
Each register sits at a `0x10`-bit-aligned address (16 bits apart). An
address decodes to I/O space when its two MSBs are `11` and bits[29:9] are
`0`; the register index is `addr[8:4]`. **All I/O registers reset to 0**
(UG §6; the only documented exception is the HLT bit's dependence on the
`HCS` host-interface pin, not yet modelled).

`rtl/io/tms34010_io_regs.sv` implements the register file and is wired into
the core memory path (Tasks 0081–0082). Graphics-control taps drive PSIZE,
PMASK, conversion pitch, CONTROL/PPOP, and interrupt behavior. HSTCTLH.NMI is
auto-cleared on entry and the window engine can set INTPEND.WV.

The remaining register semantics are incomplete: video/refresh counters are
not driven into HCOUNT/VCOUNT/REFCNT/DPYADR, most read-only/write-to-clear
rules are still plain storage behavior, and I/O accesses still rely on an
external request/ack cycle as documented in A0028.

| Addr (bit) | Index | Name | Group | Notes |
|------------|-------|------|-------|-------|
| C0000000 | 0x00 | HESYNC  | video timing | Horizontal End Sync |
| C0000010 | 0x01 | HEBLNK  | video timing | Horizontal End Blank |
| C0000020 | 0x02 | HSBLNK  | video timing | Horizontal Start Blank |
| C0000030 | 0x03 | HTOTAL  | video timing | Horizontal Total |
| C0000040 | 0x04 | VESYNC  | video timing | Vertical End Sync |
| C0000050 | 0x05 | VEBLNK  | video timing | Vertical End Blank |
| C0000060 | 0x06 | VSBLNK  | video timing | Vertical Start Blank |
| C0000070 | 0x07 | VTOTAL  | video timing | Vertical Total |
| C0000080 | 0x08 | DPYCTL  | video timing | Display Control |
| C0000090 | 0x09 | DPYSTRT | video timing | Display Start |
| C00000A0 | 0x0A | DPYINT  | video timing | Display Interrupt |
| C00000B0 | 0x0B | CONTROL | graphics ctl | Control (transparency, window, PPOP, ...) |
| C00000C0 | 0x0C | HSTDATA | host         | Host Data |
| C00000D0 | 0x0D | HSTADRL | host         | Host Address (LSBs) |
| C00000E0 | 0x0E | HSTADRH | host         | Host Address (MSBs) |
| C00000F0 | 0x0F | HSTCTLL | host         | Host Control (LSBs) |
| C0000100 | 0x10 | HSTCTLH | host         | Host Control (MSBs) |
| C0000110 | 0x11 | INTENB  | interrupt    | Interrupt Enable |
| C0000120 | 0x12 | INTPEND | interrupt    | Interrupt Pending (write-to-clear; plain storage for now) |
| C0000130 | 0x13 | CONVSP  | graphics ctl | Source Conversion Pitch |
| C0000140 | 0x14 | CONVDP  | graphics ctl | Destination Conversion Pitch |
| C0000150 | 0x15 | PSIZE   | graphics ctl | Pixel Size (1/2/4/8/16) |
| C0000160 | 0x16 | PMASK   | graphics ctl | Plane Mask |
| C0000170–C00001A0 | 0x17–0x1A | — | reserved | (storage present, no defined function) |
| C00001B0 | 0x1B | DPYTAP  | video timing | Display Tap Point |
| C00001C0 | 0x1C | HCOUNT  | video timing | Horizontal Count (read-only on silicon) |
| C00001D0 | 0x1D | VCOUNT  | video timing | Vertical Count (read-only on silicon) |
| C00001E0 | 0x1E | DPYADR  | video timing | Display Address (read-only on silicon) |
| C00001F0 | 0x1F | REFCNT  | refresh      | DRAM Refresh Count (read-only on silicon) |

Indices are named in `rtl/tms34010_pkg.sv` as `IO_IDX_<NAME>`. Implemented bit
fields for graphics and interrupt behavior are also named in the package.
Remaining video, refresh, and host fields must be documented as their
consuming blocks are integrated.

## Host-interface-visible registers

A small subset of the I/O space is also visible to the host CPU on original
silicon. The host interface and its locking/access restrictions are not
implemented.

## Display / video memory behavior

The original device interacts with VRAM through random-access and serial-shift
cycles. The current repository has timing counters but no display-memory
fetch, VRAM shift-register model, pixel output, or arbitration with core and
graphics accesses.

## Uncertain / partially implemented areas

- Physical 16-bit external-bus phasing and wait-state behavior.
- The dedicated on-chip ack path for I/O accesses (A0028).
- Read-only, write-to-clear, and hardware-driven behavior for registers not
  yet consumed by graphics/interrupt logic.
- Host-visible register access and locking semantics.
- Video/display address generation and VRAM shift-register behavior.
