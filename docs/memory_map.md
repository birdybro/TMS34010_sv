# Memory map

> Status: **scaffold**. The bit-addressed model is described; concrete
> register addresses are filled in as the I/O subsystem lands in Phase 6.

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
this field semantics as of Task 0076: 1..32-bit reads/writes at any bit
address, straddling 16-bit words, with read-modify-write preservation of
the surrounding bits. The core itself still issues only aligned 16/32-bit
accesses; wiring field sizes through the core (`mem_size = FS`, FE-driven
sign/zero extension, FS-aware pointer stepping) is the remaining work.

External memory glue (outside the core) is responsible for translating
bit addresses to whatever the physical memory expects. The core's memory
interface (see `docs/architecture.md`) exposes the bit address directly.

## I/O register space

The TMS34010 maps 32 on-chip 16-bit I/O registers into the bit-address
range `0xC0000000`–`0xC00001FF` (1988 User's Guide Figure 6-1, page 6-3).
Each register sits at a `0x10`-bit-aligned address (16 bits apart). An
address decodes to I/O space when its two MSBs are `11` and bits[29:9] are
`0`; the register index is `addr[8:4]`. **All I/O registers reset to 0**
(UG §6; the only documented exception is the HLT bit's dependence on the
`HCS` host-interface pin, not yet modelled).

`rtl/io/tms34010_io_regs.sv` (Task 0081) implements the register file as
plain read/write storage — exactly correct for the control/graphics
registers the instruction set reads. Registers that are read-only or
write-to-clear on real silicon (`HCOUNT`/`VCOUNT`/`REFCNT`/`DPYADR` from
video timing; `INTPEND` write-to-clear) are modelled as plain storage for
now; their side effects arrive with the video-timing and interrupt blocks.
The block is not yet wired into the core's memory path — that address-decode
routing is the next integration step.

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

Indices are named in `rtl/tms34010_pkg.sv` as `IO_IDX_<NAME>`. Per-register
bit fields and reset-value exceptions will be documented as each consuming
block (graphics, video, interrupts) lands.

## Host-interface-visible registers

A small subset of the I/O space is also visible to the host CPU through
the host interface. Phase 6 will document which registers are host-visible
and what restrictions apply (e.g., locked-during-PIXBLT).

## Display / video memory behavior

The original device interacts with VRAM through both random-access and
serial-shift cycles (paired with a TMS34061-class video controller). The
RTL plan (Phase 9) implements display memory as a single-port BRAM with
a separate read port for video output; the serial-shift cycle is modeled
functionally rather than electrically.

## Uncertain / partially-implemented areas (current)

- All of it. Phase 0 has no memory map implemented.

This list is replaced with per-register status rows as the I/O subsystem
is built.
