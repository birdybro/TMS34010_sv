# Graphics conformance matrix

> Status: **closed for the production TMS34010 revision through Task 0169**.
> Every defined cell below has a primary source, an RTL owner, observable
> side effects, and named self-checking evidence. Reserved or architecturally
> undefined combinations are identified explicitly and are not assigned
> invented behavior.

The primary authority is the 1988 TI TMS34010 User's Guide in
`third_party/TMS34010_Info/docs/ti-official/1988_TI_TMS34010_Users_Guide.pdf`.
Chapter 6 defines the graphics I/O registers, Chapter 7 defines graphics
addressing, pixel processing, windowing, and interrupt context, and the
individual Chapter 12 pages define each instruction. The graphics-library
guide is useful secondary software evidence but does not override the
processor guide.

## Production instruction forms

`core` below means `rtl/core/tms34010_core.sv`; `decode` means
`rtl/decode/tms34010_decode.sv`; `status` means
`rtl/core/tms34010_status_reg.sv`; and `field` means
`rtl/memory/tms34010_field_sequencer.sv`.

| Instruction form | Primary source | RTL owner and architectural side effects | Named evidence |
|---|---|---|---|
| ADDXY Rs,Rd | 12-41 | `decode`, XY ALU in `core`; writes packed X/Y sum to Rd and defined N/C/Z/V, with no cross-half carry | `tb_addxy_subxy`, `tb_status_decode` |
| SUBXY Rs,Rd | §4.3, 12-252 | `decode`, XY ALU in `core`; writes packed X/Y difference and signed-coordinate N/C/Z/V comparisons | `tb_addxy_subxy`, `tb_status_decode` |
| CMPXY Rs,Rd | 12-55 | `decode`, XY ALU/status path; preserves Rd and writes the defined per-half comparison flags | `tb_cmpxy`, `tb_status_decode` |
| CPW Rs,Rd | 12-57 | `decode`, three-port B-register read in `core`; writes the four-bit outside code into Rd[8:5] and V only | `tb_cpw`, `tb_status_decode` |
| CVXYL Rs,Rd | 12-59 | `decode`, XY conversion in `core`; writes `OFFSET + Y*pitch + X*PSIZE`, preserves status | `tb_cvxyl`, `tb_status_decode` |
| PIXT Rs,*Rd and Rs,*Rd.XY | 12-210 through 12-213, 12-220 through 12-222 | `decode`, PIXT RMW path in `core`, `field`; applies PPOP/T/PMASK, conversion/window side effects where applicable, and preserves or writes V exactly as specified | `tb_pixt`, `tb_pixt_xy`, `tb_pixt_win`, `tb_graphics_ppop_matrix`, `tb_pixel_srt` |
| PIXT *Rs,Rd and *Rs.XY,Rd | 12-214 through 12-217 | `decode`, PIXT load path in `core`, `field`; applies source-word-aligned PMASK, zero-extends the visible source pixel, and writes V from that masked value | `tb_pixt`, `tb_pixt_xy`, `tb_graphics_ppop_matrix`, `tb_status_decode` |
| PIXT *Rs,*Rd and *Rs.XY,*Rd.XY | 12-218/219, 12-223 through 12-225 | `decode`, PIXT read/process/write path in `core`, `field`; applies source/destination PMASK, PPOP, result masking, and transparency, with conversion and destination-window behavior on XY forms | `tb_pixt`, `tb_pixt_xy`, `tb_pixt_win`, `tb_graphics_ppop_matrix`, `tb_pixel_srt` |
| DRAV Rs,Rd | 12-67 | `decode`, DRAV RMW/XY-advance path in `core`, `field`; selects the destination-aligned COLOR1 field, processes/draws the pixel, advances Rd by Rs, and writes only window V when enabled | `tb_drav`, `tb_drav_win`, `tb_graphics_ppop_matrix` |
| LINE Z=0 and Z=1 | 12-99 through 12-104 | `decode`, LINE engine in `core`, `field`; selects destination-aligned COLOR1, performs Bresenham stepping, updates B0/B2/B10, applies window/status rules, and exposes completed-pixel interrupt checkpoints | `tb_line`, `tb_line_win`, `tb_line_abort`, `tb_line_interrupt`, `tb_graphics_ppop_matrix` |
| FILL L and FILL XY | 12-80, 12-84 through 12-86 | `decode`, FILL engine in `core`, `field`; selects destination-aligned COLOR1, processes an array, updates DADDR, and applies XY window/status/checkpoint rules | `tb_fill_l`, `tb_fill_xy`, `tb_fill_ppop`, `tb_graphics_array_edges`, `tb_window_common_rect`, `tb_window_preclip`, `tb_array_checkpoint`, `tb_graphics_ppop_matrix` |
| PIXBLT B,L and B,XY | 12-176 through 12-185 | `decode`, PIXBLT engine in `core`, `field`; consumes source bits LSB first, selects the destination-aligned COLOR0/COLOR1 field, ignores PBH/PBV, updates B0/B2, and applies XY window/checkpoint rules | `tb_pixblt_b`, `tb_pixblt_direction`, `tb_window_common_rect`, `tb_window_preclip`, `tb_array_checkpoint`, `tb_graphics_ppop_matrix` |
| PIXBLT L,L | 12-186 through 12-191 | `decode`, PIXBLT engine in `core`, `field`; transfers full-color fields, applies PPOP/T/PMASK and direction, and returns next-row B0/B2 context | `tb_pixblt_ll`, `tb_pixblt_direction`, `tb_graphics_array_edges`, `tb_array_checkpoint`, `tb_graphics_ppop_matrix` |
| PIXBLT L,XY; XY,L; XY,XY | 12-192 through 12-209 | `decode`, PIXBLT conversion/window/direction/checkpoint paths in `core`, `field`; converts applicable endpoints and returns specified B0/B2/DYDX/status context | `tb_pixblt_xy`, `tb_pixblt_direction`, `tb_window_common_rect`, `tb_window_preclip`, `tb_array_checkpoint`, `tb_graphics_ppop_matrix` |

## Defined graphics-register fields

The B-file registers are ordinary software-visible 32-bit registers as well
as implied graphics operands. Unnamed bits have ordinary register storage;
the table maps every production-defined graphics interpretation.

| Register / field | Primary source | RTL owner and expected effects | Named evidence |
|---|---|---|---|
| B0 SADDR / LINE d | 5-5, 5-6; Chapter 12 instruction pages | Regfile plus FILL/PIXBLT/LINE setup and writeback in `core`; source address for PIXBLT, error term for LINE | `tb_pixblt_ll`, `tb_graphics_array_edges`, `tb_array_checkpoint`, `tb_line`, `tb_line_interrupt` |
| B1 SPTCH | 5-7; PIXBLT pages | Regfile and PIXBLT row traversal; signed bit pitch between source rows | `tb_pixblt_xy`, `tb_pixblt_direction`, `tb_window_preclip`, `tb_array_checkpoint` |
| B2 DADDR | 5-8; FILL/PIXBLT/LINE pages | Regfile and all destination engines; raw XY input where defined, linear working/completion address as specified | `tb_fill_xy`, `tb_graphics_array_edges`, `tb_window_common_rect`, `tb_window_preclip`, `tb_array_checkpoint`, `tb_line_interrupt` |
| B3 DPTCH | 5-9; FILL/PIXBLT pages | Regfile and destination row traversal; signed bit pitch between rows | `tb_fill_l`, `tb_pixblt_direction`, `tb_window_preclip`, `tb_array_checkpoint` |
| B4 OFFSET | 5-10; §7.3 | Shared XY conversion path in `core`; base bit address for CVXYL and every XY operand | `tb_cvxyl`, `tb_pixt_xy`, `tb_drav`, `tb_fill_xy`, `tb_pixblt_xy`, `tb_line` |
| B5 WSTART, B6 WEND | 5-11/12; §7.10 | Signed inclusive XY rectangle in `core`; drives CPW, W=1/2/3 status, clipping, and WV | `tb_cpw`, `tb_pixt_win`, `tb_drav_win`, `tb_line_win`, `tb_line_abort`, `tb_window_common_rect`, `tb_window_preclip` |
| B7 DYDX | 5-13; array/LINE pages | Array dimensions `{DY,DX}` and LINE step selector operands in `core`; array W=1 may return the common dimensions | `tb_graphics_array_edges`, `tb_pixblt_direction`, `tb_window_common_rect`, `tb_window_preclip`, `tb_line_interrupt` |
| B8 COLOR0, B9 COLOR1 low 16 bits | 5-14/15; §7.8 and drawing pages | Color-expansion and drawing sources in `core`; the field corresponding to destination address bits [3:0] is selected before PPOP, permitting non-replicated dither patterns; registers are preserved by execution | `tb_pixblt_b`, `tb_graphics_ppop_matrix`, plus uniform-color legacy drawing benches |
| B10 COUNT | 5-16; LINE and interrupt-context sections | LINE remaining count and array checkpoint cursor in `core`; updated only at committed instruction/checkpoint boundaries | `tb_line`, `tb_line_abort`, `tb_line_interrupt`, `tb_array_checkpoint` |
| B11 INC1, B12 INC2 | 5-16/17; LINE pages | LINE minor/major packed-XY increments; B11/B12 also hold documented checkpoint context for an interrupted array | `tb_line`, `tb_line_interrupt`, `tb_array_checkpoint` |
| B13 PATTRN / internal context | 5-17; §7.2.3 | Production software must initialize the reserved pattern register to all ones where required for compatibility; the implementation gives its otherwise unspecified array-checkpoint image a deterministic value and requires handlers to preserve it | `tb_array_checkpoint` |
| B14 TEMP | 5-17; §7.2.3 | Architecturally available temporary and final word of the coherent internal graphics checkpoint; no framebuffer role | `tb_array_checkpoint` |
| CONTROL.RM [2], RR [4:3] | 6-10 through 6-14, 6-45/46 | `tms34010_io_regs`/`tms34010_refresh`; selects refresh cycle type/rate, independent of pixel result | `tb_io_refresh`, `tb_refresh`, `tb_system`, `tb_io_regs` |
| CONTROL.T [5] | 6-10 through 6-14, §7.7 | Shared pixel processor in `core`; suppresses a destination write only when the processed result is zero | `tb_pixt_transp`, `tb_fill_ppop`, `tb_graphics_ppop_matrix` |
| CONTROL.W [7:6] | 6-10 through 6-14, §7.10 | Window paths in `core`; 0 off, 1 hit detect, 2 miss detect, 3 clipping/preclipping, with instruction-specific V/WV/context | `tb_pixt_win`, `tb_drav_win`, `tb_line_win`, `tb_line_abort`, `tb_window_common_rect`, `tb_window_preclip` |
| CONTROL.PBH [8], PBV [9] | 6-10 through 6-14, §7.2.2 | PIXBLT direction setup in `core`; all four orders for full-color forms, ignored by both binary forms | `tb_pixblt_direction`, `tb_window_common_rect`, `tb_window_preclip`, `tb_array_checkpoint` |
| CONTROL.PPOP [14:10] | 6-10 through 6-14, §7.7 | Shared `ppop_apply` in `core`; 16 Boolean operations for every legal PSIZE and six arithmetic operations for PSIZE 4/8/16 | `tb_graphics_ppop_matrix`, `tb_pixt_ppop`, `tb_pixt_ppop_arith`, `tb_fill_ppop` |
| CONTROL.CD [15] | 6-10 through 6-14 | Stored/masked by `tms34010_io_regs`; disables the optional instruction cache. This design has no cache, so both values have the same uncached execution behavior | `tb_io_regs`, complete instruction-fetch regression |
| CONTROL [1:0] | 6-10 through 6-14 | Reserved: writes are masked and reads return zero | `tb_io_regs`, `tb_host_integration` |
| CONVSP [4:0], CONVDP [4:0] | 6-33/34; §7.3 | `tms34010_io_regs` and conversion paths in `core`; encode source/destination power-of-two pitch as `31-field` | `tb_cvxyl`, `tb_pixt_xy`, `tb_pixblt_xy`, `tb_pixblt_direction`, `tb_window_preclip` |
| PSIZE [4:0] | 6-37; §7.5 | `tms34010_io_regs`, `core`, `field`; defined pixel sizes are 1, 2, 4, 8, and 16 bits | `tb_graphics_ppop_matrix`, `tb_pixblt_direction`, `tb_window_preclip`, `tb_field_sequencer` |
| PMASK [15:0] | 6-38; §7.6 | `tms34010_io_regs` plus aligned mask selection and shared processing in `core`; each bit maps to the same physical position in a 16-bit memory word. Protected memory-source/destination bits read as zero before PPOP, the result is masked before transparency, protected raw destination bits survive the write, and register sources are unaffected | `tb_pixt_pmask`, `tb_fill_ppop`, `tb_graphics_ppop_matrix` |
| DPYCTL.SRT | 6-18; Chapter 9 transfer descriptions | `tms34010_io_regs`, `core`, fabric and local bus; converts only graphics pixel accesses to explicit MTR/RTM cycles | `tb_pixel_srt`, `tb_pin_srt` |

## Exhaustive processing domain

`tb_graphics_ppop_matrix` is a generated, deterministic end-to-end reference
model. It executes 1,186 cases:

- all 16 Boolean PPOP values at PSIZE 1/2/4/8/16;
- all six arithmetic PPOP values at PSIZE 4/8/16, the only sizes for which
  the production CONTROL table defines them;
- register-to-linear PIXT, register-to-XY PIXT, DRAV, LINE, both FILL forms,
  both full-color PIXBLT destinations, both binary-source PIXBLTs, and
  linear/XY memory-to-memory PIXT: 1,176 PPOP cells total;
- linear and XY memory-to-register PIXT at every PSIZE: 10 additional
  PMASK-read cases;
- deterministic cross-variation of transparency and physical-word-positioned
  PMASK, including cases where result masking induces transparency;
  non-replicated COLOR0/COLOR1 fields, binary source bits in increasing-
  address LSB-first order, sub-word source/destination offsets, status
  preservation, held requests, SRT classification, and three-cycle memory
  stalls.

PPOP 0x16 through 0x1F is reserved. Arithmetic PPOP with PSIZE 1 or 2 is not
defined. Those cells are deliberately excluded rather than mapped to the
RTL's defensive default. PSIZE values other than 1/2/4/8/16 and reversed
window limits have their documented reserved/empty handling in the I/O and
window tests; they are not treated as extra pixel formats.

## Cross-feature closure

| Feature | Reference-model or focused closure |
|---|---|
| Plane mask, transparency, PPOP, PSIZE, aligned color/dither fields | `tb_graphics_ppop_matrix`; focused `tb_pixt_pmask`, `tb_pixt_transp`, `tb_pixt_ppop`, `tb_pixt_ppop_arith`, `tb_fill_ppop` |
| Binary color expansion and bit order | `tb_graphics_ppop_matrix`, `tb_pixblt_b`, `tb_pixblt_direction`, `tb_window_preclip` |
| Source/destination conversion pitches and PBH/PBV | `tb_pixblt_direction`, `tb_window_preclip`, `tb_array_checkpoint` |
| W=0/1/2/3, reversed limits, boundaries, status and WV | `tb_pixt_win`, `tb_drav_win`, `tb_line_win`, `tb_line_abort`, `tb_window_common_rect`, `tb_window_preclip`, `docs/status_audit.md` |
| Zero dimensions, terminal B results, signed/non-unit pitches | `tb_graphics_array_edges`, `tb_pixblt_direction` |
| Word/row boundaries, arbitrary stalls, partial RMW, SRT | `tb_field_sequencer`, `tb_array_checkpoint`, `tb_line_interrupt`, `tb_pixel_srt`, `tb_pin_srt` |
| Interrupt destruction/resume and repeated entry | `tb_array_checkpoint`, `tb_line_interrupt`, `tb_int_reti`, `tb_nmi_nopush` |
| Graphics arithmetic/address results and implicit B destruction | `tb_addxy_subxy`, `tb_cmpxy`, `tb_cpw`, `tb_cvxyl`, `tb_graphics_array_edges`, `tb_window_common_rect`, `tb_array_checkpoint`, `tb_line_interrupt` |

There is no defined production graphics cell marked pending, untested, or
`TBD` in this matrix. Original-silicon instruction cycle parity, the optional
instruction cache, first-silicon-only behavior, external VRAM serial shifting,
and later TMS34020 behavior are separate non-goals.
