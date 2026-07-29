# Memory map

> Status: **field-to-word translation, interrupt-register semantics, and live
> REFCNT implemented through Task 0138**. The core issues bit-addressed
> 1–32-bit accesses, and a synthesizable sequencer
> expands them into aligned 16-bit word cycles. The on-chip I/O page is
> decoded and stored in the core. Original-pin local-bus timing and several
> I/O side effects remain open.

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
many bits starting at the bit address, crossing word boundaries as needed.

`rtl/memory/tms34010_field_sequencer.sv` implements the §4.1 field semantics
as of Task 0136. It issues aligned 16-bit words in ascending address order:
one, two, or three reads; direct writes for every fully covered word; and
read/modify/write for a partial first or last word. These combinations give
the guide's exact seven cases A–G. Read results are masked and right
justified. `word_rmw_lock_o` covers each partial-word read through its
matching write acknowledge, without incorrectly locking the gaps between
different words.

The simulation memory model (`sim/models/sim_memory_model.sv`) retains its
public core-side interface and backing `mem[]`, but now routes every request
through the synthesizable sequencer into a one-cycle aligned 16-bit target.
Thus all integration benches exercise physical word splitting. Tasks
0077–0079 remain responsible for FS, FE, pointer stepping, and MOVE addressing;
pixel operations similarly drive `mem_size` from PSIZE.

Future external-memory glue consumes the sequencer's aligned word requests
and translates them into original local-bus pin phases. The architectural
address is 32 bits; the original multiplexed physical address output uses
bits [29:4] (§4.1), with upper address-space bits also participating in
region/I/O interpretation at the later controller boundary.

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
auto-cleared on entry. Task 0137 made INTENB reserved bits read zero and
implemented INTPEND by source: synchronized read-only LINT1/LINT2 levels,
read-only HSTCTLL.INTIN/HIP, and hardware-set DIP/WVP latches cleared by
writing zero. Processor-side HSTCTLL writes also obey the INTIN, MSGOUT, and
INTOUT restrictions on pages 6-36/6-37. Task 0138 made REFCNT a live
processor-writable continuous interval/row down-counter driven by
CONTROL.RR, with CONTROL.RM and request/row outputs for the future memory
fabric.

The remaining register semantics are incomplete: video state is not driven
into HCOUNT/VCOUNT/DPYADR, host-side HSTCTL behavior is not connected, and
I/O accesses still rely on an external request/ack cycle as documented in
A0028.

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
| C00000F0 | 0x0F | HSTCTLL | host         | CPU clears INTIN, writes MSGOUT, sets INTOUT |
| C0000100 | 0x10 | HSTCTLH | host         | Host Control (MSBs) |
| C0000110 | 0x11 | INTENB  | interrupt    | Five source enables; reserved bits read zero |
| C0000120 | 0x12 | INTPEND | interrupt    | X1P/X2P/HIP read-only; DIP/WVP hardware-set and write-zero-to-clear |
| C0000130 | 0x13 | CONVSP  | graphics ctl | Source Conversion Pitch |
| C0000140 | 0x14 | CONVDP  | graphics ctl | Destination Conversion Pitch |
| C0000150 | 0x15 | PSIZE   | graphics ctl | Pixel Size (1/2/4/8/16) |
| C0000160 | 0x16 | PMASK   | graphics ctl | Plane Mask |
| C0000170–C00001A0 | 0x17–0x1A | — | reserved | (storage present, no defined function) |
| C00001B0 | 0x1B | DPYTAP  | video timing | Display Tap Point |
| C00001C0 | 0x1C | HCOUNT  | video timing | Video-clock counter; CPU access reliable only while VCLK is high |
| C00001D0 | 0x1D | VCOUNT  | video timing | Scan-line counter; CPU access reliable only while VCLK is high |
| C00001E0 | 0x1E | DPYADR  | video timing | Writable live screen-refresh address/counter; video integration pending |
| C00001F0 | 0x1F | REFCNT  | refresh      | Live writable RINTVL/ROWADR down-counter; RR=00/01 requests every 32/64 clocks |

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

- Original-pin 16-bit local-bus phasing and LRDY wait-state behavior.
- The dedicated on-chip ack path for I/O accesses (A0028).
- Read-only, write-to-clear, and hardware-driven behavior for registers not
  yet consumed by host/video/refresh logic.
- Host-visible register access and locking semantics.
- Video/display address generation and VRAM shift-register behavior.
