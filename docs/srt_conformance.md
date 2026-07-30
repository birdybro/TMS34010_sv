# Program-controlled VRAM transfer conformance

> Status: **closed through Task 0171** for the TMS34010 processor boundary.
> Attached VRAM serial storage/output, board electrical behavior, and analog
> video generation are surrounding-system responsibilities.

## Source boundary

The authoritative sources are the 1988 TI TMS34010 User's Guide DPYCTL
description on pages 6-20/6-21, §9.10.2 on pages 9-26/9-27, and
§§11.4.3–11.4.4 plus Figures 11-5/11-6 on pages 11-9/11-10. The LRDY
extension behavior is reconciled against §11.4.10 and Figure 11-14.
SPVS002C supplies the matching processor-pin timing diagrams.

DPYCTL.SRT converts only pixel accesses initiated by DRAV, PIXT, LINE, FILL,
and PIXBLT. Pixel reads select memory-to-register (MTR); pixel writes select
register-to-memory (RTM). Program addresses are unaltered and DPYTAP does not
participate in a program-controlled transfer. Instruction acquisition,
extension/vector/stack traffic, ordinary MOVE/data, on-chip I/O,
host-indirect access, DRAM refresh, and scheduled screen transfer retain
their independent cycle classes.

## Architectural classification matrix

| Graphics path | Required read/write classification | Direct evidence |
|---|---|---|
| PIXT register-to-linear/XY | Optional destination MTR, then RTM; direct replacement omits the destination read | `tb_graphics_ppop_matrix`, `tb_pixel_srt`, `tb_pin_srt` |
| PIXT linear/XY-to-register | One MTR; the processor result is deterministic zero under A0048 | `tb_graphics_ppop_matrix`, `tb_pixel_srt`, `tb_pin_srt` |
| PIXT linear/XY-to-linear/XY | Source MTR, optional destination MTR, then RTM | `tb_graphics_ppop_matrix` |
| DRAV | Optional destination MTR, then RTM | `tb_graphics_ppop_matrix`, `tb_pixel_srt` |
| LINE | Per surviving pixel: optional destination MTR, then RTM | `tb_graphics_ppop_matrix`, `tb_line_interrupt`, `tb_pixel_srt` |
| FILL L/XY | Per surviving pixel: optional destination MTR, then RTM | `tb_graphics_ppop_matrix`, `tb_window_preclip`, `tb_array_checkpoint`, `tb_pixel_srt` |
| PIXBLT L,L/L,XY/XY,L/XY,XY | Source MTR, optional destination MTR, then RTM | `tb_graphics_ppop_matrix`, `tb_window_preclip`, `tb_array_checkpoint`, `tb_pixel_srt` |
| PIXBLT B,L/B,XY | Source MTR for the packed bit source, optional destination MTR, then RTM | `tb_graphics_ppop_matrix`, `tb_window_preclip`, `tb_array_checkpoint` |

`tb_graphics_ppop_matrix` enables SRT for all 1,186 generated cases and
asserts that every and only graphics-pixel requests carry the SRT sideband.
It crosses every defined PPOP/PSIZE/backend cell plus applicable PMASK,
transparency, field-position, and held-request cases. `tb_pixel_srt` executes
all five graphics families through `tms34010_system` and checks exact
per-engine controller kinds and addresses: its program emits three MTR and
seven RTM cycles while ordinary MOVE, instruction, immediate, and I/O
requests retain their original classes.

## No-request and continuation matrix

| Condition | Required result | Direct evidence |
|---|---|---|
| FILL/PIXBLT zero DX or DY | No source read, destination read, MTR, RTM, write, or architectural completion writeback | `tb_graphics_array_edges` |
| W=1 common-rectangle query | No graphics memory request for hit or miss | `tb_window_common_rect` |
| W=3 preclipped/excluded pixel | No request for each excluded pixel; a fully excluded rectangle is memory-quiescent | `tb_window_preclip` |
| W=1/W=2 abort | The violating pixel completes or aborts per its instruction contract without a restart duplicate | `tb_line_abort`, `tb_window_preclip` |
| Completed destination word/row checkpoint | All prior traffic, including partial RMW, has retired before context publication | `tb_array_checkpoint` |
| Interrupted/resumed FILL/PIXBLT | The post-RETI request stream is exactly the uninterrupted remaining suffix | `tb_array_checkpoint` |
| Interrupted/resumed LINE | Each remaining pixel request occurs exactly once after B0/B2/B10 publication | `tb_line_interrupt` |

The zero-work benches run with SRT enabled so absence is proved at the
physical-request precursor, not inferred from ordinary memory contents.
Checkpoint tests include direction, W=3, destination-read processing,
partial-word RMW, arbitrary waits, repeated DI/NMI, and exact request traces.

## Controller, CDC, and package-pin matrix

| Boundary/phase | Required behavior | Direct evidence |
|---|---|---|
| Registered fabric ingress | Capture SRT with the complete held CPU request; each aligned read/write maps to MTR/RTM | `tb_pixel_srt`, `tb_system_fabric` |
| Fixed-priority arbitration | HOLD, screen, DRAM refresh, host, then CPU/graphics; no selected command changes before acknowledge | `tb_bus_arbiter` |
| Partial-field insertion | MTR read and RTM write remain an indivisible RMW pair; HOLD repeats the read before the sole write | `tb_bus_arbiter_rmw` |
| Core-to-8× crossing | Cycle kind/address/IAQ payload and completion cross coherently, one outstanding command | `tb_pin_srt`, `tb_pin_system` |
| First-period Q3B / RAS fall | Unaltered row; IAQ inactive; TR/QE low; RTM alone has W low | `tb_local_bus`, `tb_pin_srt` |
| First-period Q4A / column | Unaltered column with active TR status; W released high | `tb_local_bus`, `tb_pin_srt` |
| Second-period Q1B | RAS/CAS/LAL and TR/QE active; no CPU pixel data exchanged on LAD | `tb_local_bus`, `tb_pin_srt` |
| Second-period Q3A | TR/QE released before transfer completion | `tb_local_bus`, `tb_pin_srt` |
| LRDY wait | RAS/CAS/LAL extend; the MTR/RTM TR/QE and RTM W envelopes do not stretch | `tb_local_bus` |
| HOLD during transfer | The active physical transfer completes before HLDA; a broken partial RMW restarts as above | `tb_local_bus_hold`, `tb_bus_arbiter_rmw` |
| Simultaneous clients/final ratios | Graphics request survives higher-priority HOLD/screen/refresh/host service; refresh retains its minimum-interval bound | `tb_bus_arbiter`, `tb_system_fabric`, `tb_fpga_refresh_ratio` |

`tb_pin_srt` is the full hierarchy proof. With asynchronous 14 ns core,
2 ns 8×, and 10 ns VCLK periods, a pin-supplied program emits the ordered
`RTM 0x800`, `MTR 0x800`, `MTR 0x900`, `RTM 0x900` sequence. It checks every
listed row/column/control phase on the original outputs after field
sequencing, arbitration, both CDC directions, and local-bus decoding.

## Defined project choice and external scope

An MTR loads the attached VRAM serial register and returns no pixel data on
LAD. When software nevertheless uses an SRT PIXT memory-to-register form,
this RTL returns deterministic zero instead of propagating an unknown.
A0048 records that isolated choice; it is not claimed as an
original-silicon value guarantee.

The processor-side proof ends at LAD, RAS, CAS, LAL, W, TR/QE, DEN, DDOUT,
LRDY, HOLD/HLDA, and the video timing pins. A complete board must attach
compatible VRAM/DRAM, consume the transfer cycles, shift VRAM serial data,
and perform any palette/DAC conversion. Those functions are not TMS34010
processor pins and are not duplicated inside this RTL.
