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

External memory glue (outside the core) is responsible for translating
bit addresses to whatever the physical memory expects. The core's memory
interface (see `docs/architecture.md`) exposes the bit address directly.

## I/O register space

The TMS34010 maps its on-chip I/O registers into the high end of address
space. Concrete addresses, names, reset values, and bit fields are
**deferred to Phase 6** when `rtl/io/tms34010_io_regs.sv` lands. The
authoritative source for the table is the 1988 User's Guide I/O register
chapter.

Anticipated register groups (names from the User's Guide):

- **Graphics control**: `CONVDP`, `CONVSP`, `DPTCH`, `SPTCH`, `OFFSET`,
  `WSTART`, `WEND`, `PSIZE`, `PMASK`, `CONTROL`, etc.
- **Video timing**: `HESYNC`, `HEBLNK`, `HSBLNK`, `HTOTAL`, `VESYNC`,
  `VEBLNK`, `VSBLNK`, `VTOTAL`, `DPYCTL`, `DPYSTRT`, `DPYINT`, `DPYTAP`.
- **Interrupt / host**: `INTENB`, `INTPEND`, `HSTCTLH`, `HSTCTLL`,
  `HSTADRH`, `HSTADRL`, `HSTDATA`.
- **Refresh**: `REFCNT`.

Each will get a row here with `address | reset value | read/write | spec
page | implementation status`.

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
