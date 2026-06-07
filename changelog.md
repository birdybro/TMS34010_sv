# Changelog

All notable changes to this project will be documented here.
Dates are ISO 8601. Each completed task should add at least one entry.

## Unreleased

## 2026-06-07

### Added (Task 0105 — FILL XY window clipping, CONTROL.W=3)
- The FILL XY engine now clips to the destination window when CONTROL.W=3
  (1988 UG §7.10.3). WSTART(B5)/WEND(B6) are read in a new CORE_FILL_SETUP_WIN
  cycle (only entered for windowed XY fills, so non-windowed FILL timing is
  unchanged). Each pixel's absolute XY = (DADDR.X+col, DADDR.Y+row) is tested
  against the inclusive [WSTART..WEND] rectangle; out-of-window pixels are left
  unchanged (reusing the transparency write-back-dest skip path).
- A0031: only W=3 (clip) for FILL XY is implemented. W=1/W=2 (hit/miss
  detection), the WV interrupt, the V-bit window semantics, and clipping for
  PIXBLT/LINE/DRAV/PIXT are explicitly deferred (documented, not silently
  stubbed) — see docs/instruction_coverage.md and docs/assumptions.md.
- New `sim/tb/tb_fill_window.sv`: a 2×2 FILL XY with a window excluding one
  column verifies in-window pixels are drawn and out-of-window pixels skipped,
  and DADDR still advances over the full array.

## 2026-06-04

### Added (Task 0104 — NMI + maskable interrupt priority integration test)
- New `sim/tb/tb_int_priority.sv` arms an NMI (NMIM=0) and a maskable display
  interrupt simultaneously and verifies the core takes the NMI first, then the
  DI after NMI's RETI restores ST.IE — NMI → RETI → DI → RETI → resume, with SP
  balanced and both sources cleared. Ordering is guaranteed by construction
  (the NMI entry clears IE, so DI cannot preempt the NMI handler). Test-only
  (no RTL change); exercises the shared interrupt entry FSM under both sources.

### Added (Task 0103 — nonmaskable interrupt (NMI) via HSTCTLH)
- The core now takes a nonmaskable interrupt when the host sets HSTCTLH.NMI
  (bit 8). NMI ignores ST.IE and takes priority over maskable interrupts; it
  vectors through trap 8 (0xFFFFFEE0) and reuses the entry FSM from Task 0100.
- HSTCTLH.NMIM (bit 9) selects context save: NMIM=0 pushes PC+ST (then RETI
  can resume); NMIM=1 saves nothing and jumps straight to the vector (SP and ST
  untouched). The entry FSM branches on NMIM at CORE_FETCH.
- The device auto-clears HSTCTLH.NMI on taking the interrupt — required since,
  being non-maskable, it would otherwise re-trigger forever. Implemented as a
  one-cycle `nmi_clear` side channel into `tms34010_io_regs` (asserted in
  CORE_INT_DONE); a new HSTCTLH tap feeds the NMI/NMIM bits to the core.
- New `sim/tb/tb_nmi.sv` (NMIM=0: taken with IE=0, PC/ST pushed, auto-cleared,
  RETI resumes) and `sim/tb/tb_nmi_nopush.sv` (NMIM=1: no push, SP unchanged).
- pkg: INT_VEC_NMI, HSTCTL_NMI_BIT, HSTCTL_NMIM_BIT. tb_io_regs updated for the
  new tap + input.

### Added (Task 0102 — interrupt + RETI round-trip integration test)
- New `sim/tb/tb_int_reti.sv` validates the full maskable-interrupt lifecycle
  end-to-end: entry (Task 0100) → ISR clears INTPEND and sets a marker → RETI
  restores PC+ST → execution resumes at the instruction that was pending when
  the interrupt fired, with ST.IE re-enabled and SP returned to its start, and
  no spurious re-entry. Test-only (no RTL change); locks in Task 0100 + RETI.

### Added (Task 0101 — JRcc/JAcc general-arithmetic condition codes)
- Added the five single-flag condition codes from Table 12-8 (page 12-31) to
  the branch-condition evaluator and all three decoder recognition blocks
  (JRcc short, JRcc long, JAcc): C/B (1000, C=1), V (1100, V=1), NV (1101,
  V=0), N (1110, N=1), NN (1111, N=0). JRcc now recognizes all 16 cc codes
  (previously the 11 compare-form codes; the rest trapped as illegal).
- New CC_C/CC_V/CC_NV/CC_N/CC_NN constants in the package.
- New `sim/tb/tb_jrcc_arith.sv`: each of the five codes exercised take + skip
  via CMP-set flags (C via unsigned borrow, N via negative result, V via
  signed overflow).

### Added (Task 0100 — maskable-interrupt recognition + entry sequence)
- The interrupt priority encoder (Task 0098) is now wired into the core. New
  INTENB/INTPEND taps on `tms34010_io_regs` feed `tms34010_int_ctrl`, whose
  `int_req`/`int_vector` drive a new entry sequence in the core FSM.
- At the CORE_FETCH boundary, if `int_req` (ST.IE=1 and an enabled INTPEND bit
  set), the core diverts instead of fetching: CORE_INT_PUSH_PC (push resume PC
  at SP-32) → CORE_INT_PUSH_ST (push ST at SP-64) → CORE_INT_VECTOR (read the
  trap vector → PC) → CORE_INT_DONE (SP-=64, ST.IE←0). The push order matches
  RETI's pop, so an interrupt + RETI round-trips. No new core ports.
- A0030: the interrupt entry clears only ST.IE and preserves the other ST bits
  (the full ST is saved/restored by RETI), in contrast to TRAP which loads
  ST_RESET_VALUE.
- New `sim/tb/tb_int_entry.sv`: drives INTENB.DI/INTPEND.DI + EINT and verifies
  the ISR is entered (vector taken), the instruction after EINT is skipped, SP
  is decremented by 64, the pushed PC/ST are correct, and ST.IE is cleared.
- `tb_io_regs` updated for the two new taps.

## 2026-06-02

### Added (Task 0099 — DRAM-refresh address generator)
- New `rtl/video/tms34010_refresh.sv`: generates the periodic DRAM-refresh
  cycles (1988 UG §6, REFCNT / CONTROL.RR). A prescaler off the local clock
  ticks every 32 (RR=00) or 64 (RR=01) clocks; RR=10 (reserved) and RR=11 are
  treated as no-refresh. Each tick increments the 8-bit REFCNT row address
  (0..255 wrap) and pulses `refresh_req` for one clock. Not yet wired to the
  memory arbiter (the RAS-only refresh cycle issue is a follow-up).
- New `sim/tb/tb_refresh.sv` checks the 32/64-clock interval per RR, the row
  increment, and that RR=11 disables refresh.

## 2026-06-02

### Added (Task 0098 — maskable-interrupt priority encoder)
- New `rtl/core/tms34010_int_ctrl.sv`: a combinational priority encoder for the
  maskable interrupts (1988 UG §8.3/§8.4, Tables 8-2/8-3). Given INTPEND,
  INTENB, and the global IE bit it decides whether to take a maskable interrupt
  (`int_req = IE && |(INTPEND & INTENB)`) and supplies the trap-vector address
  of the highest-priority pending-and-enabled source. Priority HI(bit9) >
  DI(bit10) > WV(bit11) > INT1(bit1) > INT2(bit2) (internal before external);
  vectors HI=0xFFFFFEC0, DI=0xFFFFFEA0, WV=0xFFFFFE80, INT1=0xFFFFFFC0,
  INT2=0xFFFFFFA0. (NMI is requested via HSTCTL and handled separately.)
- New pkg constants for the INTENB/INTPEND bit positions and the vectors.
- The interrupt RECOGNITION (sampling int_req at an instruction boundary) and
  ENTRY sequence (push ST/PC, clear IE, load PC from the vector — reusing the
  TRAP push path) are the core-FSM follow-up.
- New `sim/tb/tb_int_ctrl.sv` checks the INTENB/IE gating, the full priority
  order, and the vector mapping.

## 2026-06-02

### Added (Task 0097 — video timing generator)
- New `rtl/video/tms34010_video.sv`: a standalone, synthesizable horizontal /
  vertical timing generator (1988 UG §"Video Timing"). Free-running HCOUNT/
  VCOUNT off the video clock: HCOUNT wraps at HTOTAL (VCOUNT increments on the
  wrap), VCOUNT wraps at VTOTAL (a new frame). HSYNC/HBLANK/VSYNC/VBLANK are
  window compares against HESYNC/HEBLNK/HSBLNK / VESYNC/VEBLNK/VSBLNK; BLANK is
  the combined blank; DPYINT_PULSE is a one-clock strobe at the start of the
  scan line equal to DPYINT.
- Standalone for now (not yet wired to the I/O register timing values or a real
  pixel clock — that integration, plus the display-interrupt request into the
  interrupt block, is a follow-up).
- New `sim/tb/tb_video.sv` drives small timing values and checks every cycle
  over ~2.5 frames: counter transitions/wraps, the sync/blank windows, and the
  DPYINT strobe.

## 2026-06-02

### Added (Task 0096 — PIXBLT B,L / B,XY; 1-bit source color-expand)
- PIXBLT B,L (0x0F80) and B,XY (0x0FA0): the source is a 1-bit-per-pixel
  bitmap; each source bit expands to COLOR1 (B9) if 1, COLOR0 (B8) if 0
  (`blt_binary` flag), then processes with the destination through the shared
  pixel engine. SPVU001A.
- The source is read 1 bit at a time (mem_size=1 in the source sub-step) and
  the source address advances by 1 bit per pixel (vs PSIZE for the dest);
  COLOR0/COLOR1 are read in a new second setup cycle (CORE_PBLT_SETUP2, enum
  5'd16). B,XY also converts the XY destination (reusing blt_dst_xy / CONVDP).
- New `sim/tb/tb_pixblt_b.sv`: a 4-bit source bitmap (1010) expanded to
  COLOR0/COLOR1 over a destination row, checking the pixels and the updated
  SADDR (advanced by bits) / DADDR. Completes all 6 PIXBLT addressing forms.

## 2026-06-01

### Added (Task 0095 — PIXBLT XY variants)
- PIXBLT L,XY (0x0F20), XY,L (0x0F40), and XY,XY (0x0F60): the SADDR / DADDR
  implied register holds an XY value that the PIXBLT engine converts to a
  linear address at CORE_PBLT_SETUP — source via CONVSP, destination via CONVDP,
  + OFFSET(B4) + PSIZE (same shift form as CVXYL / FILL XY). Read port 3 reads
  OFFSET at SETUP. The rest of the engine is shared with PIXBLT L,L; the updated
  SADDR/DADDR are written back as linear addresses. SPVU001A.
- New decoded struct flags `blt_src_xy` / `blt_dst_xy` (all variants reuse the
  INSTR_PIXBLT_LL iclass). New `sim/tb/tb_pixblt_xy.sv` tests PIXBLT XY,XY with
  both addresses XY-converted.
- The B (1-bit source color-expand) PIXBLT forms (0x0F80/0x0FA0) remain
  unimplemented (trap as illegal).

### Added (Task 0094 — PIXBLT L,L; source-array graphics engine)
- PIXBLT L,L (0x0F00) implemented: transfer a DY×DX source pixel array
  (SADDR=B0/SPTCH=B1) to a destination array (DADDR=B2/DPTCH=B3), processing
  each pixel through the shared pixel engine (PPOP + transparency + plane mask)
  with the source pixel and destination pixel as operands. SPVU001A PIXBLT L,L.
  All flags Unaffected.
- New core states CORE_PBLT_SETUP / CORE_PBLT / CORE_PBLT_WB / CORE_PBLT_WB2
  (the core_state_t enum is widened to 5 bits). The 5 implied B-regs are read
  across EXECUTE (SADDR/DADDR/DYDX) + CORE_PBLT_SETUP (SPTCH/DPTCH); the
  CORE_PBLT loop is a per-pixel 3-step sequence (read source, read destination,
  write `ppop_apply(src,dest)` merged), with two address trackers that advance
  ±PSIZE per pixel and row-step by their pitch. SADDR and DADDR are updated to
  the pixel following their last (written back to B0 then B2).
- New pkg constants INSTR_PIXBLT_LL, B_SADDR_IDX (B0), B_SPTCH_IDX (B1),
  B_COLOR0_IDX (B8). Deferred: corner adjust (PBH/PBV), window checking, the
  XY-addressed variants, and the B (1-bit source expand) form.
- New `sim/tb/tb_pixblt_ll.sv`: transfers a 2×4 source array to a dest array
  and checks the copied pixels, the unchanged source, and the updated
  SADDR/DADDR.

### Added (Task 0093 — FILL pixel processing; shared PPOP function)
- The 22-way PPOP computation is factored into a reusable `ppop_apply(src,
  dest, ppop, fmask)` function, shared by the PIXT store engine and FILL.
- FILL now applies the full pixel engine per pixel: the CORE_FILL loop is a
  per-pixel read-modify-write (sub-step 0 reads the destination pixel, sub-step
  1 writes `merged = PPOP(COLOR1, dest)` plane-masked and transparency-checked).
  At reset defaults (PPOP=0/PMASK=0/T=0) merged = COLOR1, so a plain fill is
  unchanged (it now also reads first). SPVU001A FILL/CONTROL.
- New `sim/tb/tb_fill_ppop.sv`: an XOR fill, a transparent (COLOR1=0) fill, and
  a plane-masked fill over preloaded destination pixels.

### Added (Task 0092 — PIXT store arithmetic pixel processing (PPOP))
- The 6 arithmetic CONTROL.PPOP ops (0x10-0x15) now operate on the unsigned
  PSIZE-bit pixel values: 0x10 D+S (wrap), 0x11 ADDS (add, saturate to all-1s
  on overflow), 0x12 D-S (wrap), 0x13 SUBS (subtract, saturate to 0 on
  underflow), 0x14 MAX(D,S), 0x15 MIN(D,S). Completes all 22 PPOP operations.
  SPVU001A CONTROL.PPOP. (The spec restricts arithmetic ops to 4/8/16-bit
  pixels; they are computed for all sizes — 1/2-bit results are spec-Undefined.)
- New `sim/tb/tb_pixt_ppop_arith.sv` checks all six ops including ADDS/SUBS
  saturation.

### Added (Task 0091 — PIXT store Boolean pixel processing (PPOP))
- PIXT store now applies the CONTROL.PPOP (bits 14-10) pixel-processing
  operation: the 16 Boolean codes (replace, AND, OR, XOR, NAND/NOR/XNOR, NOT-S,
  NOT-D, 0, 1, no-change, and their NOT-operand variants) computed bitwise on
  (source, destination). The 6 arithmetic codes (0x10-0x15) are not yet
  implemented and fall back to replace (TODO). SPVU001A CONTROL.PPOP.
- The pixel write engine is now unified: `processed = PPOP(src, dest)`, then
  transparency (CONTROL.T — now correctly tests the PROCESSED value, not the
  source) leaves the destination unchanged when the processed pixel is 0, then
  the plane mask merges. This folds the Task 0089 transparency into the 2-step
  RMW path (the EXECUTE-skip is removed; a transparent store now does the RMW
  and writes the dest back, which the spec confirms — "memory cycles still
  occur"). At reset (PPOP=0, T=0, PMASK=0) the behavior is plain replace, so
  all existing PIXT/MOVE-store tests are unchanged.
- New `sim/tb/tb_pixt_ppop.sv`: replace / AND / OR / XOR / NOT-S / no-change
  with S=0xCC, D=0xAA.

### Added (Task 0090 — PIXT store plane masking; read-modify-write pixel write)
- PIXT store now honors PMASK (plane mask): a non-transparent PIXT store is a
  2-step CORE_MEMORY read-modify-write — step 0 reads the destination pixel,
  step 1 writes `merged = (src & ~PMASK) | (dest & PMASK)` confined to the
  PSIZE-bit pixel (a PMASK bit of 1 protects that plane). With PMASK=0 (reset)
  the full source is written, so all existing PIXT tests are unchanged.
  SPVU001A PMASK.
- The 2-step is gated on `force_pixel` (a regular MOVE store stays single
  step). New core signals pixt_rmw / pixt_pmask_field / pix_dest_q /
  pixt_merged; io_regs gains a `pmask_o` tap.
- This is the read-modify-write pixel-write foundation that PPOP (pixel
  processing) will build on: today the processed value is the source (replace
  mode); PPOP will replace it with a function of (source, dest).
- New `sim/tb/tb_pixt_pmask.sv`: low-nibble and high-nibble masks over
  preloaded destination pixels, checking that protected planes keep the
  destination and unmasked planes take the source.

### Added (Task 0089 — PIXT store transparency)
- PIXT store transparency (CONTROL.T, bit 5): when transparency is enabled and
  the source pixel is 0 (in replace mode the processed value equals the
  source), the store is inhibited — the instruction skips its memory write
  (EXECUTE → WRITEBACK), leaving the destination pixel unchanged. SPVU001A
  CONTROL.T. Applies to the register-source store forms (PIXT Rs,*Rd and
  PIXT Rs,*Rd.XY); load/M2M are unaffected (loads write a register; M2M source
  transparency is deferred with the rest of pixel processing).
- io_regs gains a `control_o` tap; pkg gains CONTROL bit-field constants
  (CTRL_T_BIT, CTRL_W_*, CTRL_PBH/PBV, CTRL_PPOP_*).
- New `sim/tb/tb_pixt_transp.sv`: a 0 pixel with T=1 is skipped (dest
  preserved), a 0 pixel with T=0 is written, and a nonzero pixel always writes.

### Added (Task 0088 — FILL XY)
- FILL XY (0x0FE0): like FILL L, but DADDR (B2) holds an XY value that the FILL
  engine converts to a linear start address (CONVDP + OFFSET(B4) + PSIZE, the
  same shift form as CVXYL) at CORE_FILL_SETUP, where read port 3 reads OFFSET.
  Rows still step by the linear DPTCH; the rest of the engine is shared with
  FILL L. SPVU001A 12-82. All flags Unaffected. Window checking deferred.
- New INSTR_FILL_XY; `is_fill` now covers both forms and `fill_is_xy` selects
  the start conversion. The final DADDR is written back as a linear address
  (assumption A0029).
- New `sim/tb/tb_fill_xy.sv`: converts an XY start (X=0x20,Y=1 with CONVDP=0x1B,
  OFFSET=0x800 → 0x910) and fills a 2×2 array, checking the filled words, the
  untouched gap, and the updated DADDR.

### Added (Task 0087 — FILL L; first multi-cycle graphics engine)
- FILL L (0x0FC0) implemented: fill a DY×DX pixel array with COLOR1 (B9),
  starting at DADDR (B2), rows DPTCH (B3) bits apart, each pixel a PSIZE-bit
  field write. SPVU001A 12-80. All flags Unaffected.
- This is the first multi-cycle graphics engine. New core states
  CORE_FILL_SETUP / CORE_FILL / CORE_FILL_WB. The implied B-file operands are
  read across the 3 ports at EXECUTE (DADDR/DPTCH/DYDX) and at CORE_FILL_SETUP
  (COLOR1); the CORE_FILL loop writes one pixel per ack, advancing a column
  counter within each row and stepping the row base by DPTCH; on completion
  DADDR is updated to the address following the last pixel and written back to
  B2 in CORE_FILL_WB.
- New pkg constants INSTR_FILL_L, B_DADDR_IDX (B2), B_DYDX_IDX (B7),
  B_COLOR1_IDX (B9). Replace mode only — window checking never applies to FILL;
  PMASK/transparency/PPOP default to no-op at reset and are not yet applied.
- New `sim/tb/tb_fill_l.sv`: fills a 2×4 array (PSIZE=8, COLOR1=0xAA), checks
  the filled words, the untouched inter-row gap, and the updated DADDR.

## 2026-05-31

### Added (Task 0086 — XY-to-XY PIXT M2M; PIXT family complete)
- PIXT *Rs.XY,*Rd.XY (0xF400): both pointers hold XY values. The 2-step M2M
  converts the source (Rs) via CONVSP and the destination (Rd) via CONVDP,
  both + OFFSET(B4) (new `pix_xy_dst_linear` for the destination; the existing
  `pix_xy_linear` already converts the source). Reuses the field M2M datapath
  with force_pixel + xy_addr.
- This completes all six PIXT forms (linear store/load/M2M and XY
  store/load/M2M), replace mode.
- `sim/tb/tb_pixt_xy.sv` extended with the XY-to-XY M2M case (copy a pixel from
  one XY location through CONVSP to another through CONVDP).

### Added (Task 0085 — XY-addressed PIXT store/load)
- PIXT Rs,*Rd.XY (0xF000 store) and PIXT *Rs.XY,Rd (0xF200 load): the pointer
  register holds an XY value that the core converts to a linear bit address
  before the pixel field access (new `decoded.xy_addr` path, same shift form as
  CVXYL). The store's destination pointer uses CONVDP; the load's source pointer
  uses CONVSP (SPVU001A: source vs destination pitch); OFFSET = B-file B4 (read
  port 3), PSIZE from the tap.
- io_regs gains a `convsp_o` tap. The pixel field machinery (force_pixel) is
  reused, so zero-extend on load and V=(pixel!=0) carry over.
- New `sim/tb/tb_pixt_xy.sv`: stores a pixel via an XY pointer (CONVDP) and
  reads it back via an XY pointer (CONVSP), then changes CONVSP and shows the
  load now targets the source-pitch address — proving the source/destination
  conversion factors are selected correctly.
- The XY-to-XY PIXT M2M (0xF400) needs dual conversion across the 2-step M2M
  and remains deferred (traps as illegal).

### Added (Task 0084 — CVXYL convert XY address to linear)
- CVXYL Rs,Rd (0xE800) implemented: `Rd = [(Y << (31-CONVDP[4:0])) | (X <<
  log2(PSIZE))] + OFFSET`, where X=Rs[15:0], Y=Rs[31:16] (signed). The screen
  pitch and pixel size are powers of two, so the multiplies are shifts. SPVU001A
  page 12-59. All status bits Unaffected.
- OFFSET is the B-file register B4, read on regfile port 3 (the spare 3rd read
  port also used by CPW/DIV). CONVDP and PSIZE come from new/existing I/O
  register taps (io_regs gains a `convdp_o` tap; `psize_o` already existed).
- New pkg constants: INSTR_CVXYL, B_DPTCH_IDX (B3), B_OFFSET_IDX (B4).
- New `sim/tb/tb_cvxyl.sv` validates all rows of TI's CVXYL example table
  (X=0x30,Y=0x40 at PSIZE 16/8/4/2/1, two CONVDP values, and a nonzero OFFSET).
  Note: the spec's printed table is OCR-corrupted for the PSIZE=4 / nonzero-
  OFFSET rows (it drops the low X byte); the test uses the recomputed exact
  values, which the uncorrupted rows confirm.

### Added (Task 0083 — PIXT pixel transfer, linear forms; first graphics op)
- PIXT linear forms implemented: PIXT Rs,*Rd (0xF800 store), PIXT *Rs,Rd
  (0xFA00 load), PIXT *Rs,*Rd (0xFC00 indirect-to-indirect). A new
  `decoded.force_pixel` flag makes the core use FS = the PSIZE I/O register
  value (1/2/4/8/16) and zero-extend on load (pixels are unsigned), reusing
  the MOVE field store/load/M2M datapaths. SPVU001A §"PIXT".
- `tms34010_io_regs` gains a `psize_o` tap (combinational view of PSIZE); the
  core feeds it into mv_fs when force_pixel is set.
- PIXT store/M2M leave all flags Unaffected; PIXT load reports V = (pixel != 0)
  with N/C/Z Undefined (the decode masks them off). Replace mode only —
  PMASK / transparency / pixel-processing (PPOP) are not yet applied (their
  reset defaults are no-op, so this matches a post-reset machine).
- The XY-addressed PIXT forms (0xF000/0xF200/0xF400) remain unimplemented
  (need XY→linear conversion via CONVDP/CONVSP + OFFSET); they trap as illegal.
- New `sim/tb/tb_pixt.sv`: sets PSIZE via a MOVE to the I/O register (exercising
  the Task 0082 path), then PIXT store/load/M2M at PSIZE=8 and a PSIZE=4 pixel,
  checking zero-extend (vs MOVB sign-extend) and the V=(pixel!=0) flag.

### Added (Task 0082 — wire the I/O register file into the core memory path)
- `tms34010_io_regs` is now instantiated inside `tms34010_core`. An access
  whose bit-address decodes as I/O space (0xC0000000–0xC00001FF) is serviced
  on-chip: the external write is gated off (`mem_we = mem_we_int && !io_is_io`)
  so I/O writes never corrupt external RAM, and the read data is muxed from
  the register file. The I/O read is latched at the access ack (`io_rdata_q`/
  `io_is_io_q`) so it persists into WRITEBACK the way the external memory
  model holds `mem_rdata`. See assumption A0028.
- Internal `mem_rdata` consumers now read `mem_rdata_eff` (the muxed effective
  read data); the FSM's write intent is `mem_we_int`, gated to the external
  `mem_we` port.
- New `sim/tb/tb_io_access.sv`: MOVE absolute (FS=16) writes PSIZE and PMASK
  on-chip and reads them back, confirms no aliasing, and confirms a normal
  external MOVE still works through the read-data mux.
- A debugging note for posterity: the simulation memory model only decodes
  the low address bits, so before the external-write gating an I/O write
  aliased onto a low program word and corrupted it — fixed by the gating.

### Added (Task 0081 — I/O register file foundation)
- New `rtl/io/tms34010_io_regs.sv`: the on-chip memory-mapped I/O register
  file (1988 UG Figure 6-1). 32×16-bit registers in the bit-address range
  0xC0000000–0xC00001FF; each at a 0x10-bit-aligned address. I/O-space decode
  (`addr[31:30]==11 && addr[29:9]==0`), register index `addr[8:4]`, sync
  active-high reset to 0, sync write, async read, and an `is_io` output for
  the surrounding memory fabric. This is the foundation for graphics
  (PSIZE/PMASK/CONVSP/CONVDP/CONTROL), video timing, and interrupts.
- `rtl/tms34010_pkg.sv`: `IO_BASE_ADDR`, `IO_REG_COUNT`, `IO_REG_IDX_W`, and
  `IO_IDX_<NAME>` constants for all 28 named registers.
- The block is plain R/W storage; read-only (HCOUNT/VCOUNT/REFCNT/DPYADR) and
  write-to-clear (INTPEND) behaviors are deferred to the video/interrupt
  blocks. Not yet wired into the core memory path (address-decode routing is
  the next step).
- New `sim/tb/tb_io_regs.sv`: reset-to-0, per-register write/read-back,
  is_io decode (in/out of range, wrong MSBs), and that non-I/O writes are
  ignored. `docs/memory_map.md` now carries the full register table.

### Added (Task 0080 — MOVB move byte)
- MOVB (move byte) implemented: a special MOVE form with the field size fixed
  at 8 bits. New `decoded.force_byte` flag makes the core force `mv_fs = 8`
  and, for loads, sign-extension (`mv_fe = 1`) regardless of ST — MOVB loads
  are always right-justified and sign-extended to 32 bits with implicit
  compare-to-0; stores leave flags Unaffected. SPVU001A pp.12-118ff.
- 7 of MOVB's 9 forms reuse the MOVE field/offset/absolute datapaths: Rs,*Rd
  (0x8C00), *Rs,Rd (0x8E00), *Rs,*Rd (0x9C00), Rs,*Rd(off) (0xAC00),
  *Rs(off),Rd (0xAE00), Rs,@DAddr (0x05E0), @SAddr,Rd (0x07E0). The store/load
  indirect forms decode on top7 (they differ in bit9); the absolute forms are
  in the 0000-01.. family at sub-op instr[7:5]=111 (store bit9=0 / load bit9=1).
- New `sim/tb/tb_movb.sv` covers all 7 forms incl. sign-extend vs positive
  byte, M2M, offset, absolute, and an unaligned (boff=4) byte. The test
  deliberately does not SETF — proving force_byte overrides the reset FS0=16.
- Deferred: MOVB *Rs(SOff),*Rd(DOff) (0xBC00) and MOVB @SAddr,@DAddr (0x0340)
  need new multi-word datapaths (also deferred for MOVE); they trap as illegal.

### Added (Task 0079 — field-size-aware MOVE indirect-to-indirect; MOVE field machinery complete)
- The M2M (indirect↔indirect) MOVE forms (MOVE *Rs,*Rd / *Rs+,*Rd+ /
  -*Rs,-*Rd) now honor the field size: both steps of the 2-step CORE_MEMORY
  sequence use `mem_size = mv_fs` (step 0 reads the FS-bit field into
  move_data_q, step 1 writes its low FS bits), and both pointers step by ±FS.
  No FE extension — mem→mem has no register destination. SPVU001A
  pp.12-137/12-138.
- New `sim/tb/tb_move_m2m_field.sv`: FS=8 plain copy, FS=8 postincrement
  (both pointers +8), and an FS=12 copy where source and destination fields
  both straddle 16-bit word boundaries.
- tb_move_m2m / tb_move_m2m_incdec now SETF FS0=0 up front (reset FS0=16).
- **All MOVE addressing forms now honor arbitrary FS 1..31 + FE, unaligned and
  word-straddling fields.** The remaining field-related item is MOVB (byte
  move, FS fixed at 8 over this machinery).

### Added (Task 0078 — field-size-aware MOVE offset & absolute forms)
- The OFFSET (MOVE Rs,*Rd(off) / *Rs(off),Rd) and ABSOLUTE (MOVE Rs,@DAddr /
  @SAddr,Rd) MOVE forms now honor the field size, reusing the Task 0077
  `mv_fs` / `mv_load_data` machinery: stores drive `mem_size = FS` and write
  the low FS bits; loads read FS bits and sign/zero-extend per FE, setting N/Z
  from the extended value. Neither form steps a pointer. SPVU001A
  pp.12-132/12-141/12-134/12-153.
- New `sim/tb/tb_move_offabs_field.sv`: offset FS=8 zero/sign-extend round-trip,
  absolute FS=16 zero/sign-extend round-trip, and an absolute FS=12 field
  straddling a 16-bit word boundary.
- **Compatibility note**: tb_move_offset and tb_move_abs now SETF FS0=0 up
  front (reset ST has FS0=16) to keep their 32-bit-move intent.
- Only the M2M (indirect↔indirect) MOVE forms remain FS=32; MOVB falls out of
  the now-complete field machinery for the single-pointer forms.

### Added (Task 0077 — field-size-aware MOVE register↔indirect)
- The MOVE register↔indirect forms (store/load, plain + postinc + predec) now
  honor the field size. The core derives FS/FE from the F-selected ST pair
  (FS0/FE0 if instr bit 9 = 0, else FS1/FE1; FS=0 means 32), drives
  `mem_size = FS`, sign-extends (FE=1) or zero-extends (FE=0) the loaded field
  to 32 bits, sets N/Z from the extended value, and steps the auto-inc/dec
  pointer by ±FS. Unaligned and word-straddling fields are handled by the
  Task 0076 memory model. SPVU001A pp.12-127/12-135.
- New `sim/tb/tb_move_field.sv`: FS=8 zero-extend round-trip, FS=8 sign-extend
  load, FS=16 sign-extend round-trip, zero field (Z=1), FS-aware postincrement
  (+8), and an FS=16 field straddling a 16-bit word boundary.
- **Compatibility note**: because MOVE now honors the actual FS, the existing
  FS=32 round-trip tests (tb_move_indirect, tb_move_indirect_incdec) now issue
  `SETF FS0=0` (encodes 32) up front — the reset ST has FS0=16, so without it
  those moves would transfer 16 bits.
- The M2M (indirect↔indirect), offset, and absolute MOVE forms remain FS=32;
  their field-awareness is a later task.

### Added (Task 0076 — sim_memory_model arbitrary bit-field access)
- The behavioral memory model now reads and writes fields of 1..32 bits at
  any bit address, including fields that straddle 16-bit word boundaries (a
  field spans at most 3 words). Writes are read-modify-write, so bits outside
  the field are preserved; reads return the field zero-extended into the
  32-bit bus. The core's existing aligned 16/32-bit accesses are the boff=0
  special cases of this path — the full integration regression is unchanged.
- This is the memory-model foundation for the TMS34010 field-size (FS/FE)
  machinery. The core-side field extract/insert and FS-aware pointer step
  are later tasks; today the core still issues only aligned 16/32 accesses.
- New `sim/tb/tb_mem_field.sv` drives the request/ack protocol directly (no
  core): aligned 32/16, sub-word read, RMW preservation, a 9-bit field
  straddling a word boundary, an unaligned 32-bit field spanning 3 words,
  and single-bit write/read.

### Added (Task 0075 — MPYS / MPYU variable multiplier width)
- MPYS/MPYU now honor field size 1: the Rs multiplier is an FS1-bit field,
  not always the full 32-bit register. The core extracts the low FS1 bits of
  Rs (`st_value[ST_FS1_HI:ST_FS1_LO]`) into `mpy_rs_field`, sign-extending
  (MPYS) or zero-extending (MPYU) to 32 bits before the multiply; FS1=0 still
  means width 32. Rd (the multiplicand) stays full 32-bit. SPVU001A
  pp.12-164/12-166.
- New `sim/tb/tb_mpy_fs1.sv` validates MPYU at FS1=16/8/4 against TI's MPYU
  example (Rd=0xFFFF0000, Rs=0x10001010 → 0x0000100F_EFF00000 /
  0x0000000F_FFF00000 / 0), plus MPYS sign-extension of a negative field and
  positive-field cases. FS1 set via SETF (F=1).
- Lifts the FS1=32-only limitation noted on the MPYS/MPYU coverage rows
  (Task 0071).

### Added (Task 0074 — DIVS / MODS signed divide & modulo)
- **DIVS Rs,Rd** (`0101 100S SSSR DDDD`, 0x5800) — signed divide (even Rd =
  64-bit signed dividend). **MODS Rs,Rd** (`0110 110S SSSR DDDD`, 0x6C00) —
  signed 32-bit modulo (remainder takes the dividend's sign). SPVU001A
  pp.12-63/12-112. Completes the divide family.
- The `tms34010_divider` stays unsigned; the core feeds |dividend| /
  |divisor| and sign-conditions the outputs: quotient sign = Rd.sign ^
  Rs.sign, remainder sign = Rd.sign. Signed overflow (V) = the magnitude
  quotient won't fit a signed 32-bit value (the -2^31 result is valid),
  plus the unsigned divider's Rs=0 / |quotient|≥2^32. N = result sign.
- **Bug caught & fixed during bring-up:** the operand signs were initially
  recomputed each cycle from the live Rd, but an even-Rd DIVS's pass-0
  write overwrites Rd with the quotient before the pass-1 remainder write —
  so the remainder (and N) got the quotient's sign. Fixed by latching the
  signs at divide-start (`div_dvd_sign_q` / `div_dvs_sign_q`).
- The four divide-family ops (DIVU/DIVS/MODU/MODS) now share unified
  rf_wr_data / flag_input muxes; MODS reuses MODU's runtime
  `effective_flag_mask` ("Z unaffected if Rs=0"). INSTR_DIVS = 7'd91,
  INSTR_MODS = 7'd92.
- Test: new `sim/tb/tb_divs_mods.sv` — DIVS even (both result signs, exact
  TI quotient/remainder), DIVS odd, Rs=0, MODS negative remainder, and
  MODS Rs=0 (Z unaffected); N/Z/V verified against TI's tables.

### Added (Task 0073 — MODU unsigned modulo)
- **MODU Rs,Rd** (`0110 111S SSSR DDDD`, 0x6E00) — unsigned 32-bit modulo:
  `Rd mod Rs -> Rd` (the remainder). SPVU001A p.12-113. Reuses the
  `tms34010_divider` (dividend = {0, Rd}); single writeback of the
  remainder to Rd.
- Status: N/C Unaffected; Z = (remainder==0); V = 1 if Rs=0, in which case
  Rd is unchanged and **Z is left Unaffected**. The "Z unaffected only when
  Rs=0" rule is a runtime condition the static decode flag-mask can't
  express, so the core now computes an `effective_flag_mask` that clears
  the Z mask bit for MODU on overflow.
- INSTR_MODU = 7'd90. The divide-family helper `is_div` now covers DIVU and
  MODU; only DIVU-even uses the 64-bit {Rd,Rd+1} dividend and the
  pair-writeback (MODU is always {0,Rd} + single writeback).
- Test: new `sim/tb/tb_modu.sv` — normal (Z=0), exact division (Z=1), and
  Rs=0 (V=1, Rd unchanged, Z unaffected — verified by leaving Z=0 before
  the op and confirming it stays 0).
- Deferred: signed DIVS/MODS reuse the divider with operand abs +
  result sign-conditioning (follow-up).

### Added (Task 0072 — DIVU unsigned divide + multi-cycle divider)
- **DIVU Rs,Rd** (`0101 101S SSSR DDDD`, 0x5A00) — unsigned divide.
  SPVU001A p.12-69.
  - Even Rd: 64-bit dividend {Rd, Rd+1} ÷ Rs → quotient in Rd, remainder
    in Rd+1.
  - Odd  Rd: 32-bit dividend Rd ÷ Rs → quotient in Rd.
  - Status: N Unaffected; Z = quotient==0; V = overflow (Rs=0 or quotient
    doesn't fit 32 bits), in which case the result registers are unchanged.
- New module **`rtl/core/tms34010_divider.sv`** — a restoring long-division
  unit (64÷32 → 32-bit quotient + 32-bit remainder + overflow), ~32+1+1
  cycles; start/busy/done handshake; results persist until the next start.
- Core integration: new **`CORE_DIVIDE`** FSM state (the state enum widened
  from 3 to 4 bits) holds the core while the divider runs, then proceeds to
  WRITEBACK. The even-Rd quotient/remainder pair-writeback reuses MPY's
  pair-writeback step (renamed `mpy_wb_step` → `pair_wb_step`). Read port 3
  carries Rd+1 (the dividend low half). On overflow the regfile write is
  suppressed.
- INSTR_DIVU = 7'd89.
- Test: new `sim/tb/tb_divu.sv` — TI's even-Rd example (quotient/remainder
  checked exactly), an odd-Rd divide, divide-by-zero, a quotient-overflow,
  and a zero-quotient; results and the Z/V flags verified.
- Deferred: MODU and the signed DIVS/MODS reuse this divider (follow-ups).

### Added (Task 0071 — MPYS / MPYU multiply, FS1=32)
- **MPYS Rs,Rd** (`0101 110S SSSR DDDD`, 0x5C00) — signed 32×32 → 64-bit.
  **MPYU Rs,Rd** (`0101 111S SSSR DDDD`, 0x5E00) — unsigned. SPVU001A
  pp.12-164/12-166. Rd is the 32-bit multiplicand and destination; Rs is
  the multiplier.
  - Even Rd: 64-bit result → {Rd = hi32, Rd+1 = lo32}.
  - Odd  Rd: low 32 bits → Rd.
  - MPYS: N=result[63], Z=(result==0). MPYU: Z only.
- INSTR_MPYS = 7'd87, INSTR_MPYU = 7'd88. The 64-bit product is computed
  combinationally and latched in CORE_EXECUTE (`mpy_product_q` — the
  registered output, regfile-registered inputs, so DSP-inference-friendly).
  An even-Rd multiply writes back over two WRITEBACK cycles (a new
  `mpy_wb_step` loops the WRITEBACK state once: hi32→Rd, then lo32→Rd+1).
- **Scope: FS1 = 32** (the reset-default field size, = the full 32-bit
  Rs). The variable Rs field size (FS1 = 2..30) is deferred — it needs the
  field-size machinery (A0020). At FS1=32 the multiplier is the whole Rs,
  so no field extraction is required.
- Test: new `sim/tb/tb_mpy.sv` — TI's MPYU example (even), MPYU odd-Rd,
  signed-negative MPYS (even), zero MPYS, and signed-negative MPYS odd-Rd,
  checking the register-pair result and the N/Z flags (GETST snapshots).

### Added (Task 0070 — CPW Compare Point to Window)
- **CPW Rs,Rd** (`1110 011S SSSR DDDD`, 0xE600) — compares the signed XY
  point in Rs against the window corners WSTART = B5 and WEND = B6
  (implied B-file operands), loading a 4-bit out-of-window code into
  `Rd[8:5]`: bit5=WSTART.X>Rs.X, bit6=Rs.X>WEND.X, bit7=WSTART.Y>Rs.Y,
  bit8=Rs.Y>WEND.Y (all else 0). SPVU001A p.12-57. Used for trivial-reject
  line clipping. Status: N/C/Z Unaffected; V=1 iff the point is outside
  the window.
- INSTR_CPW = 7'd86. Completes the XY-coordinate instruction family.
- **Added a 3rd read port to `tms34010_regfile.sv`** — CPW needs three
  simultaneous sources (the point + WSTART + WEND). On the flop-based
  register file a 3rd async read mux is cheap (no memory blocks). The
  core reads Rs on port 1, overrides port 2 to WSTART (B5), and drives the
  new port 3 to WEND (B6). New pkg constants CPW_WSTART_IDX / CPW_WEND_IDX.
- Comparisons are signed (the spec states signed; A0027 does not apply).
  CPW stays a single-cycle register op.
- Test: new `sim/tb/tb_cpw.sv` — TI's example window (5,5)-(A,A) across
  several points checking the code in Rd and the V flag, plus a
  negative-X point that distinguishes signed from unsigned comparison.
  tb_regfile updated to wire the new port.

### Changed (Task 0069 — word-step / mem-size magic numbers → DATA_WIDTH constants)
- Completed the magic-number cleanup deferred from Task 0068. The
  pervasive `32'd32` / `32'd64` / `6'd32` literals in `tms34010_core.sv`
  are semantically `DATA_WIDTH` (one 32-bit word in bit-addresses), two
  words, and the 32-bit memory-transfer size. Added three pkg constants
  derived from `DATA_WIDTH`:
  - `WORD_BIT_SIZE = DATA_WIDTH` (32) — stack/pointer step per 32-bit word.
  - `WORD_BIT_SIZE_2 = 2*DATA_WIDTH` (64) — two-word step (TRAP/RETI).
  - `MEM_SIZE_32 = DATA_WIDTH` (6'd32) — the `mem_size` value for a
    full-word transfer.
  Replaced all 33 occurrences in core.sv. `32'd0`/`32'd1` and the
  shifter's internal `6'd32` (rotate modulus) were intentionally left.
- Pure refactor; no behavioral change. The project now has no remaining
  word-step/transfer-size magic numbers in the core datapath.
- Tests: full 59-tb integration regression PASS under Verilator; lint clean.

### Changed (Task 0068 — HDL coding-guidelines audit + compliance fixes)
- The user added a Cyclone V HDL coding-guidelines bundle at
  `docs/hdl-coding-guidelines/` (23 docs; target part 5CSEBA6U23I7 /
  DE10-Nano). Audited the existing RTL against it (rule extraction +
  full RTL scan). **The code was already compliant on every hard [C]
  rule** — consistent always_ff/always_comb split, safe combinational
  defaults, single-driver, `unique case`+default almost everywhere, no
  unsynthesizable constructs, no `/`%`*`, complete synchronous resets.
- Fixes applied for the few gaps found:
  - `tms34010_decode.sv`: added a `default: ;` to the UNARY
    `case(instr[6:5])` (was latch-safe via full 2-bit enumeration but
    lacked the required `default:` — guidelines 90 AP4/AP13, 14 §3.5).
  - Added `` `default_nettype none `` (and `` `default_nettype wire ``
    restore) to all 8 RTL files (guidelines 12 §2 / 91 G3). No implicit
    nets were exposed — lint stays clean.
  - Removed magic-number duplicates: TRAP entry-ST literal `0x10` now
    references the existing pkg `ST_RESET_VALUE`; new pkg constants
    `REV_VALUE` (0x08) and `TRAP_VECTOR_BASE` (0xFFFFFFE0) replace the
    inline literals in `tms34010_core.sv`.
- CLAUDE.md updated to make the guidelines bundle the authoritative RTL
  style reference and to record two intentional, [C]-compliant deviations
  from its [V] conventions: synchronous active-high `rst` (A0003, the
  "sync clear" option) and the `default_nettype` placement.
- Deferred (tracked): the pervasive `32'd32`/`32'd64`/`6'd32` literals are
  really `DATA_WIDTH` / `2*DATA_WIDTH` / the 32-bit transfer size; a
  DATA_WIDTH-based sweep is a separate follow-up to keep this change
  focused and low-risk.
- Tests: full 59-tb integration regression PASS under Verilator; lint
  clean. No behavioral change.

### Added (Task 0067 — CMPXY nondestructive XY compare)
- **CMPXY Rs,Rd** (`1110 010S SSSR DDDD`, 0xE400) — compares the X (low
  16) and Y (high 16) halves of Rs and Rd, setting status bits as if
  `RdX-RsX` / `RdY-RsY` were computed, WITHOUT modifying Rd. SPVU001A
  p.12-55.
- Status: N=(Xres==0), V=Xres[15], Z=(Yres==0), C=Yres[15] — i.e. the
  per-half subtract result sign bits (NOT the unsigned borrow SUBXY
  uses), so CMPXY is fully unambiguous (no A0027 dependency). Verified
  against TI's example table.
- INSTR_CMPXY = 7'd85. Decoder top7 1110_010; wb_reg_en=0 (nondestructive),
  wb_flags_en=1. Reuses the XY subtract datapath (xy_x_sub/xy_y_sub) with
  a new cmpxy_flags assign feeding the flag_input mux.
- Test: new `sim/tb/tb_cmpxy.sv` — TI example cases checking NCZV (GETST
  snapshots) and that Rd/Rs are unchanged.

### Added (Task 0066 — ADDXY / SUBXY dual 16-bit XY arithmetic)
- **ADDXY Rs,Rd** (`1110 000S SSSR DDDD`, 0xE000) — `Rd.X += Rs.X,
  Rd.Y += Rs.Y` on the two 16-bit halves independently, with NO carry
  between halves (X=low 16, Y=high 16). SPVU001A p.12-41.
- **SUBXY Rs,Rd** (`1110 001S SSSR DDDD`, 0xE200) — `Rd.X -= Rs.X,
  Rd.Y -= Rs.Y` per half. SPVU001A p.12-252.
- Status bits encode graphics-clipping info (NOT ordinary arithmetic
  flags):
  - ADDXY: N=(Xres==0), V=Xres[15], Z=(Yres==0), C=Yres[15].
  - SUBXY: N=(RsX==RdX), V=(RsX>RdX), Z=(RsY==RdY), C=(RsY>RdY); the
    `>` comparisons are unsigned (= the per-half subtract borrow). All
    verified against TI's worked example tables.
- INSTR_ADDXY = 7'd83, INSTR_SUBXY = 7'd84. New XY datapath in the core:
  separate 16-bit adders/subtractors for the X and Y halves (blocking
  inter-half carry), feeding the rf_wr_data and flag_input muxes. Pure
  register op — no memory.
- New assumption A0027: the SUBXY/CMPXY `>` comparison is taken as
  unsigned (TI's examples don't distinguish; pending MAME cross-check).
- Test: new `sim/tb/tb_addxy_subxy.sv` — ADDXY/SUBXY cases from TI's
  tables checking both the result and the NCZV pattern (GETST snapshots).

### Added (Task 0065 — MOVX / MOVY half-register moves)
- **MOVX Rs,Rd** (`1110 110S SSSR DDDD`, 0xEC00) — `Rd.X <- Rs.X` (low 16
  bits); Rd's Y half (high 16) unchanged. SPVU001A p.12-162.
- **MOVY Rs,Rd** (`1110 111S SSSR DDDD`, 0xEE00) — `Rd.Y <- Rs.Y` (high 16
  bits); Rd's X half unchanged. SPVU001A p.12-163.
- Both leave all status bits Unaffected. First of the XY-coordinate
  instruction family (used for packed-16-bit / XY-address handling).
- INSTR_MOVX = 7'd81, INSTR_MOVY = 7'd82. Pure register ops — the result
  is composed in the rf_wr_data mux from Rs and the old Rd (async-read
  regfile delivers the old Rd in the same WRITEBACK cycle). No memory,
  no ALU, no flags.
- Also fixed a stale comment block above the MOVE_RR decode arm that
  still cited the pre-Task-0058 (wrong) 0x9000 encoding.
- Test: new `sim/tb/tb_movx_movy.sv` — half-replace-with-other-half-
  preserved checks plus TI's worked examples (MOVX A4,A5 -> 0x00005678;
  MOVY A6,A7 -> 0x12340000).

### Added (Task 0064 — MOVE register-indirect with offset, field-size 32)
- The register-indirect-with-offset MOVE forms (FS=32, word-aligned):
  - **MOVE Rs,\*Rd(off)** (`1011 00FS SSSR DDDD` + off16, base 0xB000) —
    `mem[Rd + sext(off16)] <- Rs`. Rd pointer unchanged. Flags Unaffected.
    SPVU001A p.12-132.
  - **MOVE \*Rs(off),Rd** (`1011 01FS SSSR DDDD` + off16, base 0xB400) —
    `Rd <- mem[Rs + sext(off16)]`. Rs pointer unchanged. Implicit
    compare-to-0: N=data[31], Z=(data==0), V=0, C Unaffected. SPVU001A
    p.12-147.
- INSTR_MOVE_OFF_STORE = 7'd79, INSTR_MOVE_OFF_LOAD = 7'd80. Decoder
  matches top6 101100/101101; the signed 16-bit offset is the 2nd word,
  fetched via the imm16 path (needs_imm16=1, imm_sign_extend=1). The
  effective address is `pointer + imm32` (imm32 = sext(off16)) — a single
  combinational add in CORE_MEMORY. Rs=instr[8:5], Rd=instr[3:0].
- Test: new `sim/tb/tb_move_offset.sv` — store->load round-trips with
  positive (+0x20), negative (-0x20), and zero offsets, checking memory,
  recovered register, pointer-unchanged, and load N/Z flags. PASS.
- Scope: field-size-32, word-aligned (A0020). The indirect-with-offset to
  indirect-with-offset form (3-word) remains deferred.

### Added (Task 0063 — MOVE absolute addressing, field-size 32)
- The absolute-address MOVE forms (FS=32, word-aligned):
  - **MOVE Rs,@DAddr** (`0000 01F1 100R SSSS` + 32-bit addr, base 0x0580)
    — `mem[DAddr] <- Rs`. All flags Unaffected. SPVU001A p.12-134.
  - **MOVE @SAddr,Rd** (`0000 01F1 101R DDDD` + 32-bit addr, base 0x05A0)
    — `Rd <- mem[SAddr]`. Implicit compare-to-0: N=data[31], Z=(data==0),
    V=0, C Unaffected. SPVU001A p.12-153.
- INSTR_MOVE_ABS_STORE = 7'd77, INSTR_MOVE_ABS_LOAD = 7'd78. These join
  the existing `0000 01F1` field-op family (SETF/SEXT/ZEXT) with the
  sub-op in instr[7:5] (100=store, 101=load); the register operand is at
  instr[3:0]. The 32-bit absolute bit-address is the two words after the
  opcode (LSBs first), fetched via the imm32 path; CORE_MEMORY drives
  `mem_addr = imm32` for a single read (load) or write (store).
- Test: new `sim/tb/tb_move_abs.sv` — three store->load round-trips
  (negative/zero/positive) verifying memory contents, recovered register,
  and load N/Z flags (GETST snapshots). PASS.
- Scope: field-size-32, word-aligned (A0020). MOVE @SAddr,@DAddr (5-word
  mem-to-mem absolute) and the offset addressing modes remain deferred.

### Added (Task 0062 — MOVE indirect-to-indirect with auto inc/dec)
- The two auto-update indirect-to-indirect MOVE forms (FS=32, word-aligned),
  completing the indirect-to-indirect family (SPVU001A p.12-138):
  - **MOVE \*Rs+,\*Rd+** (0x9800) — `mem[Rd]<-mem[Rs]; Rs+=32; Rd+=32`.
  - **MOVE -\*Rs,-\*Rd** (0xA800) — `Rs-=32; Rd-=32; mem[Rd]<-mem[Rs]`.
  Both leave all flags Unaffected.
- Reuse INSTR_MOVE_FIELD_M2M with move_mode. The two pointers update
  through the single regfile write port at different times: the source
  pointer (Rs) at the step-0 read ack (new `m2m_src_wr` path), the
  destination pointer (Rd) at WRITEBACK. Address helpers `m2m_src_addr` /
  `m2m_dst_addr` fold in the predecrement -32.
- **Rs==Rd edge case** (spec 12-138, postincrement): the data must be
  written to the *incremented* location and the register steps once.
  This falls out for free — the step-1 write address reads `rf_rs2_data`
  which (when Rs==Rd) already holds the step-0-updated Rs — and the
  WRITEBACK Rd write is suppressed when Rs==Rd to avoid double-stepping.
  Verified in tb_move_m2m_incdec Case C.
- Test: new `sim/tb/tb_move_m2m_incdec.sv` — postinc + predec (Rs!=Rd)
  round-trips and the Rs==Rd postincrement incremented-location case.
- The Rs==Rd predecrement corner is undefined by the spec; the
  implementation single-steps the register (documented in A0020).

### Added (Task 0061 — MOVE *Rs,*Rd indirect-to-indirect, field-size 32)
- **MOVE \*Rs,\*Rd** (`1000 10FS SSSR DDDD`, base 0x8800) — copies the
  32-bit field at mem[*Rs] to mem[*Rd]. Both Rs and Rd are bit-address
  pointers (unchanged for this plain form). All status bits Unaffected.
  SPVU001A p.12-137.
- First memory-to-memory instruction: a two-step CORE_MEMORY sequence
  (INSTR_MOVE_FIELD_M2M = 7'd76) reusing the `mem_op_step` counter.
  Step 0 reads mem[Rs] into a new `move_data_q` latch; step 1 writes it
  to mem[Rd]; the FSM exits to WRITEBACK after step 1.
- Test: new `sim/tb/tb_move_m2m.sv` — two memory-to-memory copies
  verifying the destination receives the data, the source is unchanged,
  and the pointer registers are unchanged. PASS.
- Scope: plain form only, field-size-32, word-aligned. The inc/dec
  indirect-to-indirect forms (`*Rs+,*Rd+` 0x9800, `-*Rs,-*Rd` 0xA800)
  auto-update BOTH pointers and have an Rs==Rd corner case the spec only
  partly defines; deferred to a follow-up (still ILLEGAL). A0020.

### Added (Task 0060 — MOVE indirect with auto inc/dec, field-size 32)
- Four auto-update addressing variants of the indirect MOVE, reusing the
  Task 0059 datapath (SPVU001A pages 12-129/12-130/12-139/12-143):
  - **MOVE Rs,\*Rd+** (0x9000) — `mem[Rd] <- Rs; Rd += 32`. Flags Unaffected.
  - **MOVE Rs,-\*Rd** (0xA000) — `Rd -= 32; mem[Rd] <- Rs`. Flags Unaffected.
  - **MOVE \*Rs+,Rd** (0x9400) — `Rd <- mem[Rs]; Rs += 32`. N/Z flags.
  - **MOVE -\*Rs,Rd** (0xA400) — `Rs -= 32; Rd <- mem[Rs]`. N/Z flags.
- New `move_addr_mode_t move_mode` field on `decoded_instr_t`
  (NONE/POSTINC/PREDEC); the two existing MOVE iclasses now carry it.
  Decoder matches top6 100100/101000 (store post/pre) and 100101/101001
  (load post/pre).
- Core: `mv_ptr` / `mv_addr` / `mv_ptr_new` combinational helpers compute
  the transaction address (pointer, or pointer-32 for predecrement) and
  the post-update pointer (±32). Stores write the updated pointer (Rd)
  back at WRITEBACK; loads write the updated pointer (Rs) during
  CORE_MEMORY via a new `mv_load_ptr_wr` regfile-write path (a second
  user of the write port, like `mmfm_pop_wr`), with the data write to Rd
  at WRITEBACK.
- **Rs==Rd edge case** (load, spec 12-143: "pointer information is
  overwritten by the data fetched"): handled for free — the pointer is
  written in CORE_MEMORY and the data at WRITEBACK, so the data wins.
- Test: new `sim/tb/tb_move_indirect_incdec.sv` — post/pre store+load
  round-trips, pointer ±32 checks, load N/Z flags, and the Rs==Rd
  data-wins case. PASS.
- Scope unchanged from Task 0059: field-size-32, word-aligned only. The
  offset/absolute addressing modes, arbitrary field sizes, and FE
  sign/zero extension remain deferred (A0020).

### Added (Task 0059 — MOVE register <-> indirect, field-size 32)
- First increment of the MOVE-indirect family (the opcodes freed by
  Task 0058):
  - **MOVE Rs,\*Rd** (`1000 00FS SSSR DDDD`, base 0x8000) — store
    `mem[*Rd] <- Rs`. Rd is a bit-address pointer (read, not written
    back); Rs is the data. All status bits Unaffected. SPVU001A p.12-127.
  - **MOVE \*Rs,Rd** (`1000 01FS SSSR DDDD`, base 0x8400) — load
    `Rd <- mem[*Rs]`. Rs is the pointer; Rd receives the data. Implicit
    compare-to-0: N=data[31], Z=(data==0), V=0, C Unaffected.
    SPVU001A p.12-135.
- INSTR_MOVE_FIELD_STORE = 7'd74, INSTR_MOVE_FIELD_LOAD = 7'd75. Decoder
  matches top6 (instr[15:10]) = 100000 / 100001. Both are single 32-bit
  memory transactions through the existing CORE_MEMORY path:
  - store: `mem_we=1, mem_addr=rf_rs2_data (Rd), mem_wdata=rf_rs1_data (Rs)`.
  - load:  `mem_we=0, mem_addr=rf_rs1_data (Rs)`; `mem_rdata` flows to the
    regfile-write mux and the flag_input mux at WRITEBACK.
- **Scope limitation (documented):** field size 32 only, word-aligned
  pointer. The F bit and the runtime FS0/FS1 are ignored, so smaller
  field sizes, unaligned pointers, FE sign/zero extension, and the
  inc/dec/offset/absolute addressing modes are NOT yet handled — they
  remain a deferred follow-up (assumptions.md A0020). At FS=32 the field
  fills the register, so FE is a no-op and the access is a clean 32-bit
  aligned transfer.
- Test: new `sim/tb/tb_move_indirect.sv` — three store->load round-trips
  (negative/zero/positive) verifying memory contents, the recovered
  register, pointer-unchanged-by-store, and the load's N/Z flags
  (captured with GETST snapshots). PASS.

### Fixed (Task 0058 — register-to-register MOVE opcode + cross-file)
- **Corrected a real opcode bug**: register-to-register `MOVE Rs,Rd` was
  decoded at `0x9000` (`1001 00FS`), which both TI editions (1986 first
  edition and 1988 User's Guide) actually assign to `MOVE Rs,*Rd+`
  (postincrement register-to-indirect, a memory store). The correct
  reg-to-reg encoding is `0100 11MS SSSR DDDD` (base `0x4C00`),
  confirmed by the object-code example `MOVE A0,B1 = 0x4E01`
  (Figure 12-3, SPVU001A p.12-126). The bug had been masked because the
  decoder and every test shared the same wrong encoding.
- **Added M-bit cross-file support**: `MOVE Rs,Rd` is the only MOVE that
  can cross register files. M=bit[9] selects same-file (0) vs cross-file
  (1); R=bit[4] is the file for both registers (M=0) or the *source*
  file (M=1, destination is the other file). New `rs_file` field in
  `decoded_instr_t` carries the (possibly different) source file; the
  core routes `rf_rs1_file` from it only for `INSTR_MOVE_RR`.
- **Corrected status-flag behavior**: per SPVU001A p.12-126, MOVE Rs,Rd
  sets N=data[31], Z=(data==0), V=0, and leaves **C Unaffected**. The
  prior all-ones flag mask wrongly clobbered C; now masked off.
- **Fixed all affected testbenches**: every stack/control testbench that
  set SP via "MOVE A0/A2/A14, A15" used the wrong `0x9000`-form opcode
  (tb_pushst, tb_popst, tb_call_rs, tb_calla_callr, tb_rets, tb_reti,
  tb_trap, tb_trap0, tb_mmtm) — all updated to the `0x4C00` form.
  `tb_move_rr` rewritten with the corrected encoding plus A↔B cross-file
  cases (verified against TI's `0x4E01` object code).
- The freed `0x9000` / `0x8000` / `0xA000` opcodes are now correctly
  ILLEGAL until the MOVE-indirect family is implemented.

### Added (Task 0057 — MMTM N flag)
- Closed the one deferred piece of MMTM: the **N status bit**. Per
  SPVU001A page 12-111, MMTM sets N = sign of (0 - original Rp) with
  two stated exceptions (Rp=0 → N=1, Rp=0x80000000 → N=0); C, Z, V
  remain Unaffected.
- That definition reduces to the closed form **N = ~Rp[31]** (inverted
  sign bit of the original Rp), which covers the typical case and both
  edge cases uniformly — the ALU's raw `0 - Rp` sign bit would be wrong
  at exactly those two points.
- Implementation:
  - decode: MMTM arm now sets `wb_flags_en=1` with an N-only
    `wb_flag_mask` (`{n:1, c:0, z:0, v:0}`).
  - core: new `INSTR_MMTM` case in the `flag_input` mux sets
    `n = ~rf_rs2_data[31]`. `rf_rs2_data` still reads the original Rp
    during WRITEBACK (the final-Rp regfile write is in flight on the
    same edge and async read returns the pre-write value), so no extra
    latch is needed.
- Tests: new `sim/tb/tb_mmtm_nflag.sv` checks all four cases
  (positive→1, negative→0, and both spec edge cases) by snapshotting ST
  with GETST after each MMTM. `tb_mmtm` gains an N=1 assertion for its
  positive-Rp 8-register push. Both PASS.

### Added (Task 0056 — MMFM Rp, register list)
- Implemented **MMFM** per SPVU001A page 12-109 — the pop
  counterpart of MMTM. Encoding `0000 1001 101R DDDD` + the same
  16-bit register-list mask. For each set bit (highest-order
  register first): `Rn <- mem[Rp]; Rp += 32`. The post-increment
  fires after **every** read including the last, so final
  `Rp = initial Rp + 32·count` (points one word past the restored
  block). All four status bits are Unaffected.
- INSTR_MMFM = 7'd73. Decoder arm: `top11 == MMFM_TOP11`
  (`11'b00001001_101`), rd/rs carry the Rp index and file,
  needs_imm16=1 (mask fetch), wb_reg_en=1 (final Rp), wb_flags_en=0,
  needs_memory_op=1.
- Core changes:
  - Generalised the MMTM iterator into a **shared MMTM/MMFM
    iterator**: renamed `mmtm_rp_q`/`mmtm_mask_q`/`mmtm_iter_idx`/
    `mmtm_mask_will_be_empty` → `mm_*`, added `is_mmtm`/`is_mmfm`/
    `is_mm` selectors. `mm_iter_idx` now picks the **lowest** set
    bit for MMTM and the **highest** set bit for MMFM.
  - Seed/step asymmetry: MMTM pre-decrements (`mm_rp_q <= Rp-32`
    on entry, `-32` after each ack except the last); MMFM starts
    at `Rp` and `+32` after every ack including the last.
  - MMFM restores each register through the existing single
    regfile write port during CORE_MEMORY (new `mmfm_pop_wr`
    path: `rf_wr_en` pulses on each ack, `rf_wr_idx = mm_iter_idx`,
    `rf_wr_data = mem_rdata`). The final-Rp write still happens at
    CORE_WRITEBACK; Rp is never in the list so the two write users
    never collide.
  - CORE_MEMORY arm and the `mm_mask_will_be_empty` →
    CORE_WRITEBACK transition extended to cover INSTR_MMFM.
- Test: new `sim/tb/tb_mmfm.sv` with two subtests — (1) TI's worked
  example on page 12-110 reproduced verbatim in the B file
  (absolute-correctness check, pins down assumption A0026 against
  TI's published register results), and (2) an A-file
  MMTM → corrupt → MMFM round-trip (internal-consistency check +
  MMTM regression after the `mm_*` rename). Both PASS.

### Added (Task 0055 — MMTM Rp, register list)
- Implemented **MMTM** per SPVU001A page 12-111. Encoding
  `0000 1001 100R DDDD` + 16-bit register-list mask. For each set
  bit (lowest-order first): `Rp -= 32; mem[Rp] <- Rn`. Final Rp
  points at the address of the lowest-written register.
- First instruction in the project where the *number* of memory
  transactions is data-dependent (1..16 32-bit writes, driven by
  `popcount(mask)`).
- INSTR_MMTM = 7'd72. Decoder arm: `top11 == MMTM_TOP11`, rd/rs
  carry the Rp index and file, needs_imm16=1 (mask fetch),
  needs_memory_op=1.
- Core changes:
  - New state: `mmtm_rp_q` (32-bit working Rp), `mmtm_mask_q`
    (16-bit residual mask, bits cleared as processed),
    `mmtm_iter_idx` (4-bit priority-encoded lowest set bit of
    mask_q).
  - `rf_rs1_idx` is multiplexed during CORE_MEMORY for MMTM to
    point at `mmtm_iter_idx`, so the regfile's async read port
    serves as the per-cycle push data source (no new regfile
    ports required).
  - Init: on CORE_EXECUTE → CORE_MEMORY transition for MMTM,
    capture `mmtm_rp_q <= rf_rs2_data - 32` and
    `mmtm_mask_q <= imm_lo_q`.
  - CORE_MEMORY arm issues a 32-bit write at `mmtm_rp_q` with
    `mem_wdata = rf_rs1_data`. On ack, clears the just-pushed
    bit and decrements `mmtm_rp_q` by 32 if more pushes remain.
  - CORE_MEMORY → CORE_WRITEBACK transition gates on
    `mmtm_mask_will_be_empty` for INSTR_MMTM.
  - rf_wr_data mux returns `mmtm_rp_q` for INSTR_MMTM (= final
    Rp value = address of last push).
- Assumption A0026: bit N of the mask = register R(N) for both
  MMTM and MMFM. The spec's actual chart is a graphical figure
  that didn't survive `pdftotext -layout` extraction. The natural
  reading is self-consistent and matches the spec's "lowest-order
  register saved first" requirement when scanning LSB-first.
- Added `sim/tb/tb_mmtm.sv`. Loads A0..A15 with recognisable
  sentinel values (0xAnAnAnAn-style), sets Rp=A1=0x800, executes
  `MMTM A1, {A0, A2, A4, A8, A12, A13, A14, SP}` (mask=0xF115).
  Verifies final A1 = 0x0700 (= 0x0800 - 8*32) and all eight
  pushed memory slots, lowest-order register at highest address.
- Known limitations:
  - N flag computation deferred. Per spec: "N: Set to the sign of
    the result of 0 - Rp" with two edge cases (Rp=0 → N=1,
    Rp=0x80000000 → N=0). All four flags currently left
    unchanged (C, Z, V are "Unaffected" by spec; N is the gap).
  - MMFM (the pop counterpart) is the planned next task.
- Regression: full 28-tb sweep PASS; Verilator
  `--lint-only -Wall` clean.

### Added (Task 0054 — TRAP 0 special case)
- Implemented the **TRAP 0** carve-out from SPVU001A page 12-253
  note 1: the level-0 trap does not push PC'/ST and does not
  decrement SP — it only fetches the vector at `0xFFFFFFE0` and
  sets ST to `0x00000010`. Spec intent: usable when SP is corrupt
  or uninitialised.
- Added `trap_skip_push` wire = `(iclass == INSTR_TRAP) && (k5 == 0)`.
- Core changes (all confined to the INSTR_TRAP paths):
  - alu_b mux returns 0 for TRAP 0 (so the ALU SUB yields SP - 0
    and the regfile writeback is a no-op).
  - CORE_MEMORY arm collapses to a single 32-bit read at
    `0xFFFFFFE0` for TRAP 0; the N>0 three-step write/write/read
    sequence is unchanged.
  - mem_op_step / popped_pc_q / state transition logic all
    branch on `trap_skip_push` so the single-step path latches
    the vector on step 0 and exits to CORE_WRITEBACK immediately.
- Added `sim/tb/tb_trap0.sv`. Pre-places sentinel values
  (DEAD/BEEF/FEED/FACE) at mem[SP-32] and mem[SP-64] and verifies
  they are UNTOUCHED after TRAP 0 — proves the pushes were
  genuinely skipped, not just landed somewhere else. Also
  verifies SP unchanged, ST = 0x10, and that the service routine
  at the popped-vector target ran.
- Regression: full 25-tb sweep PASS (including tb_trap N=3,
  which exercises the unchanged N>0 path); Verilator lint clean.

## 2026-05-26

### Added (Task 0053 — TRAP N, three-transaction software interrupt)
- Implemented **TRAP N** per SPVU001A page 12-252. Encoding
  `0000 1001 000N NNNN` (= `0x0900 | N`, N at instr[4:0]). Action:
    SP -= 32; mem[SP] <- PC'         (push return address)
    SP -= 32; mem[SP] <- ST          (push status register)
    ST <- 0x00000010                  (clear flags + IE; FS0=16)
    PC <- mem[0xFFFFFFE0 - N*32]     (fetch trap vector)
  First three-transaction instruction (write/write/read).
- INSTR_TRAP = 7'd71. Decoder arms on `top11 == TRAP_TOP11`
  (=`11'b00001001_000`); k5 carries the trap number. alu_op=SUB,
  rs/rd both target SP, wb_reg_en=1, needs_memory_op=1.
- Core changes:
  - alu_a swap group adds INSTR_TRAP (alu_a = SP via rs2).
  - alu_b mux: `INSTR_TRAP → 32'd64` (combined with SUB this gives
    SP - 64 to the regfile writeback).
  - mem_op_step counter extended to 3 steps for INSTR_TRAP. The
    same counter still stays at 0 for all single-transaction
    instructions (unchanged behavior there).
  - popped_pc_q latches `mem_rdata` on step 2 (= the trap-vector
    word fetched from `0xFFFFFFE0 - N*32`).
  - CORE_MEMORY arm cycles per step: push PC' at SP-32 (step 0),
    push ST at SP-64 (step 1), read vector (step 2). The vector
    address comes from a 32-bit subtractor: `0xFFFFFFE0 - (k5<<5)`.
  - CORE_MEMORY → CORE_WRITEBACK transition gates on
    `mem_op_step == 2` for INSTR_TRAP.
  - st_write_en/st_write_data extended: INSTR_TRAP writes the
    spec-fixed `32'h00000010` through the existing full-ST path.
  - PC-load mux: INSTR_TRAP loads `popped_pc_q` into PC.
- Added `sim/tb/tb_trap.sv` — runs TRAP 3. The trap vector at
  bit-address `0xFFFFFF80` aliases to word 1016/1017 in a
  DEPTH=1024 memory model (the model's `word_idx` slice ignores
  high bits, mirroring what real-world top-of-memory aliasing
  would do for an FPGA build with a small physical address space).
  Pre-TRAP program runs PUTST A1 with A1=0xCAFEBABE so the pushed
  ST is distinguishable from TRAP's own `0x10` overwrite —
  confirms push-then-replace ordering unambiguously. Service
  routine at the vector target writes A6=0x0BADC0DE and halts.
  Verifies: A6 sentinel (routine ran), SP=SP_INIT-64, ST=0x10
  post-TRAP, pushed ST = 0xCAFEBABE, pushed PC' nonzero.
- Known limitations: TRAP 0 not yet handled. Per spec, TRAP 0
  skips the pushes (intended for use when SP is uninitialised)
  and only loads ST=0x10 + PC=mem[0xFFFFFFE0]. Follow-up task.
- Regression: full 24-tb sweep PASS; Verilator
  `--lint-only -Wall` clean.

## 2026-05-25

### Added (Task 0052 — RETI + multi-transaction memory FSM)
- Implemented **RETI** (Return from Interrupt) per SPVU001A page
  12-230. Single fixed encoding `0x0940`. Pops ST then PC from the
  stack and resumes execution:
    `ST <- mem[SP]; SP += 32; PC <- mem[SP]; SP += 32`
  All four flag bits are restored atomically as part of the full
  ST pop. RETI is the project's first instruction that issues more
  than one memory transaction.
- INSTR_RETI = 7'd70. Single-fixed-encoding decoder arm: rd_idx=15,
  rs_idx=15, alu_op=ADD (the SP +64 increment), wb_reg_en=1,
  needs_memory_op=1.
- Core changes:
  - alu_a swap group adds INSTR_RETI (alu_a = SP via rs2).
  - alu_b mux: `INSTR_RETI → 32'd64` (= 32 + 32 for the two pops).
  - New multi-transaction infrastructure:
    - `mem_op_step` (2-bit) counter. Increments on every `mem_ack`
      while CORE_MEMORY is active for multi-step iclasses; stays at
      0 for all single-transaction iclasses (which keeps PUSHST,
      POPST, CALL Rs, RETS, CALLA, CALLR identical to before).
    - `popped_st_q` / `popped_pc_q`: 32-bit latches that capture
      `mem_rdata` at step 0 and step 1 respectively.
    - CORE_MEMORY → CORE_WRITEBACK transition now per-iclass: RETI
      stays in CORE_MEMORY until `mem_op_step == 1`; everything
      else still transitions on every ack.
  - CORE_MEMORY arm for INSTR_RETI: 32-bit read at `rf_rs2_data`
    (step 0) or `rf_rs2_data + 32` (step 1).
  - st_write_en/st_write_data extended: INSTR_RETI writes
    `popped_st_q` through the existing full-ST path, restoring all
    four flag bits atomically.
  - PC-load mux: INSTR_RETI loads `popped_pc_q` into PC.
- Added `sim/tb/tb_reti.sv` — hand-builds a stack frame (saved ST
  at `mem[SP]`, saved PC at `mem[SP+32]`), executes RETI, then
  verifies ST = saved ST (incl. all flag bits), PC reached the
  popped-PC target, and SP = SP_INIT + 64.
  - Crucially, the popped-PC target must be `0xC0FF` (halt) and
    nothing else. The first version of the test placed an arith
    instruction there; it ran *after* RETI's WRITEBACK and cleared
    N/Z, corrupting the popped ST's top nibble before the check.
    Lesson archived in memory under `tb-flag-side-effects.md`.
- Regression: all 23 instruction tbs (tb_pushst, tb_popst,
  tb_call_rs, tb_rets, tb_calla_callr, tb_jacc, tb_jruc_short,
  tb_jrcc_unsigned, tb_immi_il, tb_movi, tb_movk, tb_add_rr,
  tb_sub_rr, tb_cmp_rr, tb_addk_subk, tb_addc_subb, tb_logical_rr,
  tb_shift_rr, tb_shift_k, tb_setf, tb_exgf, tb_dint_eint,
  tb_smoke) PASS. Verilator `--lint-only -Wall` clean.

## 2026-05-12

### Added
- Added `https://github.com/birdybro/TMS34010_Info` as a git submodule under
  `third_party/TMS34010_Info`, pinned at commit `0f5094bf`. This is the
  authoritative specification source — the 1988 TMS34010 User's Guide and
  the SPVS002C datasheet inside it are the primary references for all RTL
  decisions.
- Added project planning files: `tasks.md`, `changelog.md`.
- Added documentation scaffolds: `docs/architecture.md`,
  `docs/assumptions.md`, `docs/instruction_coverage.md`,
  `docs/timing_notes.md`, `docs/memory_map.md`. All marked as scaffolds with
  unimplemented sections explicitly flagged.
- Added build/sim/lint launcher scripts under `scripts/`.
- Added `CLAUDE.md` describing project conventions for future Claude Code
  sessions (RTL style, spec workflow, doc requirements, git workflow).
- Added `.gitignore` for simulator work directories and synthesis output.
- Added `rtl/tms34010_pkg.sv` with `ADDR_WIDTH`, `DATA_WIDTH`,
  `FIELD_SIZE_WIDTH`, and the `core_state_t` typed enum.
- Added `rtl/core/tms34010_core.sv` — Phase 0 skeleton: single sequential
  always_ff for state, single always_comb for next-state + memory IF
  outputs with safe defaults, observability `state_o` port. CORE_RESET →
  CORE_FETCH on first clock after reset; CORE_FETCH asserts `mem_req`
  with 16-bit field size and waits for `mem_ack`.
- Added `sim/tb/tb_smoke.sv` — drives reset for 3 cycles, releases,
  watches the FSM advance to CORE_FETCH within 8 cycles, checks
  `mem_req` is asserted there. Prints `TEST_RESULT: PASS`/`FAIL` for
  the `scripts/sim.sh` grep-based pass/fail check.
- Updated `scripts/sim.sh` to capture transcript and grep for
  `TEST_RESULT: PASS` (vsim batch exit code is unreliable for test
  status).
- Added `rtl/core/tms34010_pc.sv` — bit-addressed program counter with
  parameterized `RESET_VALUE`, absolute-load port, and forward-advance
  port measured in bits. Single `always_ff` + single `always_comb` with
  safe defaults; no `/`, no `%`, no implicit-width adds.
- Extended `rtl/tms34010_pkg.sv` with `INSTR_WORD_BITS = 6'd16`,
  `PC_ADVANCE_WIDTH = 8`, and `RESET_PC` (placeholder until Phase 8
  resolves the architectural reset-vector fetch sequence — see
  assumption A0008).
- Added `sim/tb/tb_pc.sv` — unit test covering reset, hold-when-idle,
  single advance by `INSTR_WORD_BITS`, cumulative advances, absolute
  load, and load-wins-over-advance precedence.
- Added `docs/assumptions.md` entry A0008 (reset-vector deferral).
- Added `sim/models/sim_memory_model.sv` — non-synthesizable behavioral
  memory with two-state mini-FSM, one-cycle ack pulse, and a guard
  against re-latching while still driving an ack (the producer's
  `mem_req` is combinational from a state register that NBA-updates
  the cycle after, so on the ack cycle `mem_req` is still high
  for one delta-cycle).
- Added `sim/tb/tb_fetch_walk.sv` — end-to-end fetch-loop test
  connecting `tms34010_core` to `sim_memory_model`. Preloads 8 words,
  watches every ack with an active-region monitor, and verifies the
  full handshake: address tracks PC, PC advances by `INSTR_WORD_BITS`
  on each ack, `mem_size` matches, `mem_rdata` low 16 bits match the
  preloaded word and high 16 bits are zero, and the final PC commits
  to `N*16`.
- Added `rtl/core/tms34010_regfile.sv` — A0..A14 + B0..B14 + shared SP
  (aliased as A15/B15). Two combinational read ports, one synchronous
  write port, sync active-high reset clears all entries. SP aliasing
  centralized in the read/write decode so callers never deal with it.
  Package gains `reg_file_t`, `reg_idx_t`, and `REG_SP_IDX`.
- Added `sim/tb/tb_regfile.sv` — coverage: reset clears all 31 slots,
  per-file isolation (A vs B), SP aliasing (write A15 visible via B15
  and `sp_o`), independent read ports, synchronous-write contract
  (same-cycle read returns old value, next-cycle read returns new).
- Added `rtl/core/tms34010_alu.sv` — purely combinational 32-bit ALU
  with operations ADD, ADDC, SUB, SUBB, CMP, AND, ANDN, OR, XOR, NOT,
  NEG, PASS_A, PASS_B. Produces a 32-bit result and an `alu_flags_t`
  struct (N, C, Z, V). Arithmetic ops use a single 33-bit adder for
  carry extraction (`{cout, sum} = a + b + cin`) and the symmetric
  subtractor form (`a + ~b + 1`) for SUB/SUBB/CMP/NEG.
- Added package types `alu_op_t` and `alu_flags_t`.
- Added `sim/tb/tb_alu.sv` — per-operation vectors covering normal,
  zero-result, negative-result, unsigned-carry and signed-overflow
  edge cases. PASS on ModelSim ASE 17.0.
- Added `docs/assumptions.md` A0009 covering the ALU flag-update
  convention until SPVU001A Appendix A is read per-instruction.
- Added `rtl/core/tms34010_shifter.sv` — purely combinational 32-bit
  barrel shifter. Operations: SLL, SLA (same output as SLL in Phase 2;
  the V-on-sign-change quirk is tracked in A0009), SRL, SRA (signed
  `>>>`), RL, RR. amount == 0 is identity (no shifts evaluated for
  flags). Output reuses `alu_flags_t` with V tied 0 for now.
- Added package types `shift_op_t` and `SHIFT_AMOUNT_WIDTH = 5`.
- Added `sim/tb/tb_shifter.sv` — covers amount==0 identity per op,
  small/large shift amounts, the half-word swap on rotate by 16,
  signed extension on SRA, carry from MSB on left shifts/rotates,
  carry from LSB on right shifts/rotates.
- Added `rtl/core/tms34010_status_reg.sv` — 32-bit ST register.
  Update priority: reset → 0, then `st_write_en` (full POPST-style
  write) wins, then `flag_update_en` (selective N/C/Z/V update from
  `alu_flags_t`) updates only the four flag bits and preserves the
  other 28. Exposes named outputs `n_o`/`c_o`/`z_o`/`v_o`.
- Added package parameters `ST_N_BIT/ST_C_BIT/ST_Z_BIT/ST_V_BIT` as
  placeholder bit positions for the four flags, plus assumption A0010
  for the rest of the ST bit layout (deferred to SPVU001A Ch. 2 read).
- Added `sim/tb/tb_status_reg.sv` — reset, selective flag update,
  full ST write, non-flag-bit preservation across selective updates,
  precedence (st_write wins over flag_update).
- Added `rtl/core/tms34010_decode.sv` — Phase 3 combinational decode
  skeleton. Currently flags every 16-bit encoding as ILLEGAL; SPVU004
  opcode-chart rows populate in Task 0011 onwards (one instruction
  per task, each citing the chart row).
- Added package types `instr_word_t` (alias for `logic [15:0]`),
  `instr_class_t` (4-bit enum, currently only `INSTR_ILLEGAL`),
  `decoded_instr_t` (packed `{illegal, iclass}`), and constant
  `INSTR_WORD_WIDTH = 16`.
- Added `sim/tb/tb_illegal_opcode.sv` — preloads memory, runs the
  core, verifies (a) `illegal_opcode_o` is 0 during reset, (b) the
  sticky illegal latch asserts after the first CORE_DECODE, (c)
  remains high (stickiness), (d) `instr_word_o` carries the
  preloaded value `0xDEAD` from the first decode, (e) the PC has
  advanced past reset value.
- Added `initial` block to `sim_memory_model` to zero the backing
  store so tests that don't preload every fetched address see 0,
  not X. Also switched the memory model from `always_ff` to plain
  `always` since `initial` and `always_ff` cannot both write to the
  same array under SV-2009.
- First real instruction: **MOVI IW K, Rd** (move 16-bit sign-extended
  immediate to register). Encoding `0x09C0 | (R<<4) | N` (per A0012);
  flag effects N/Z from result, C/V cleared (per A0011). End-to-end:
  decoder recognizes the pattern, FSM fetches the 16-bit immediate
  word from a new CORE_FETCH_IMM_LO state, ALU PASS_B routes through
  to regfile write, ST flag-update fires on writeback.
- Added `sim/tb/tb_movi.sv` — 5 MOVI IW instructions covering a mix
  of A-file and B-file destinations and immediate values exercising
  N/Z flag semantics (positive, all-ones, zero, max positive, min
  negative sign-extended). Verifies each register value via
  hierarchical reference and the final ST flag bits.
- Added `docs/assumptions.md` A0011 (MOVI flag-update convention)
  and A0012 (MOVI IW encoding extracted from SPVU004 listings).
- Added first real row to `docs/instruction_coverage.md` for MOVI
  IW; placeholder row for MOVI IL until Task 0013.
- Second instruction: **MOVI IL K, Rd** (move 32-bit immediate to
  register). Encoding `0x09E0 | (R<<4) | N` (A0012); 32-bit immediate
  stored as two 16-bit words in memory (low half first, then high).
  Exercises the existing `CORE_FETCH_IMM_HI` state and the
  `imm32 = {imm_hi_q, imm_lo_q}` assembly path. Reuses the same
  ALU PASS_B and writeback logic as MOVI IW; only one new arm in the
  decoder.
- Added `sim/tb/tb_movi_il.sv` — 5 MOVI IL instructions with
  immediates that the IW form physically cannot encode (0xCAFE_BABE,
  0xDEAD_BEEF, 0x0000_FFFF, 0xFFFF_0000, 0x0000_0000).
- Third instruction: **MOVK K, Rd** (move 5-bit constant). Encoding
  `0x1800 | (K<<5) | (R<<4) | N` (A0013); single-word; **does not
  affect ST** per SPVU004. Adds `k5` field to `decoded_instr_t` and a
  new arm to the alu_b mux that zero-extends K to 32 bits.
- Added `sim/tb/tb_movk.sv` — 5 MOVK instructions covering K range
  edges (1, 31, 0, 16, 5) and verifying both regfile content and
  that ST is unchanged from reset zeros (confirming the "no flag
  update" contract).
- Added `docs/assumptions.md` A0013 covering MOVK encoding, the
  no-flag-effect contract, and the K=0 = literal-0 hypothesis.
- Fourth instruction (first arithmetic): **ADD Rs, Rd**. Encoding
  `0100 000S SSSR DDDD` from SPVU001A Appendix A page A-14
  (A0014/A0015). The TMS34010 reg-reg encoding shares a single R
  bit between Rs and Rd, so **Rs and Rd must be in the same file**
  for ADD and the rest of the reg-reg family. `decoded_instr_t` now
  includes `rs_idx`; the core's regfile rs1/rs2 selectors are driven
  from `decoded.rs_idx`/`decoded.rd_idx` (file shared).
- Added `sim/tb/tb_add_rr.sv` — 4 ADD RR cases: simple positive add,
  signed-overflow (0x7FFF_FFFF + 1 → 0x8000_0000 with N=1, V=1),
  unsigned wrap to zero (0xFFFF_FFFF + 1 → 0 with C=1, Z=1), and a
  B-file add (0x1111_1111 + 0x2222_2222 → 0x3333_3333) with all
  flags clear. Encoding helper independently verified against the
  hand-decoded `ADD A1,A2 → 0x4022`.
- Resolved encoding-source uncertainty: extracted SPVU001A page A-14
  via `pdftotext -layout` — this is the authoritative opcode chart
  for every '34010 instruction. Logged as A0014.
- Fifth instruction: **SUB Rs, Rd** (Rd - Rs → Rd). 7-bit prefix
  `7'b0100010` from SPVU001A A-14. Added `alu_a` mux in the core
  that swaps operands for INSTR_SUB_RR so the ALU's natural `a - b`
  produces the spec-mandated `Rd - Rs`.
- Added `sim/tb/tb_sub_rr.sv` — five cases: simple positive, equal
  operands (Z=1), borrow (3-10 = -7 with C, N), signed-overflow
  (MIN_INT - 1 = MAX_INT with V), and a B-file SUB.
- Reg-reg logical block: **AND, ANDN, OR, XOR Rs, Rd**. 7-bit
  prefixes `7'b0101_0XX` per SPVU001A A-14. AND/OR/XOR are
  commutative and use the default alu_a/b routing; ANDN
  (`Rd & ~Rs → Rd`) reuses the SUB-style operand swap (`alu_a = Rd`,
  `alu_b = Rs`) so the ALU's `a & ~b` computes the right value.
  All four set N/Z from the result; C, V cleared (logical-op
  convention from A0009).
- Added `sim/tb/tb_logical_rr.sv` — covers all four ops with
  characteristic bit-pattern test cases (alternating bits, bit
  isolation, sign-bit flips). Encoder helper cross-checked against
  the SPVU004 listing `XOR A0,A0 = 0x5600`.
- Tenth instruction: **CMP Rs, Rd**. 7-bit prefix `7'b0100100`.
  Computes the same arithmetic as SUB but with `wb_reg_en = 0` —
  the destination register is **not** modified, only the status
  register changes. First instruction in the project that
  exercises the flag-only writeback path. Reuses the SUB operand-
  swap in the alu_a/b muxes.
- Added `sim/tb/tb_cmp_rr.sv` — verifies (a) Rs and Rd both
  unchanged after CMP, (b) flags match the equivalent SUB.
- **First branch instruction**: **JRUC short** (Jump Relative
  Unconditional, 8-bit signed displacement). Encoding
  `1100 0000 dddd_dddd` per SPVU001A A-14 + condition-code
  table 12-8 (cc = `4'b0000` = UC). Branch target =
  `PC_post_fetch + sign_extend(disp8) * 16`, verified by hand-
  decoding `JRGT L5 = 0xC70B` against the assembler listing in
  SPVU004 (logged as A0016). The PC module's `load_en` /
  `load_value` ports are now driven dynamically by the core's
  `CORE_WRITEBACK` logic.
- Added `sim/tb/tb_jruc_short.sv` — program with three MOVI IL
  instructions where the middle one is skipped by a JRUC +3. Verifies
  the destination register holds the **landing-site** value (proving
  the branch took) and never holds the skipped value.
- Added assumption A0016 covering the branch-target math and pointing
  forward to the future long/conditional/absolute variants.
- Generalized branch handling: `INSTR_JRUC_SHORT` is now
  `INSTR_JRCC_SHORT` with a `branch_cc` field. Decoder accepts the
  three verified condition codes (UC, EQ, NE per A0017); other cc
  values on the JRcc encoding fall through to ILLEGAL. The core
  gains a combinational `branch_taken` evaluator that picks the
  right ST-flag combination for each cc.
- Package adds `CC_UC=0000`, `CC_EQ=0100`, `CC_NE=0111` constants
  for use across decoder and core.
- Added `sim/tb/tb_jrcc_short.sv` — three scenarios: JREQ taken
  (Z=1 from equal-CMP), JRNE taken (Z=0 from unequal-CMP), and JREQ
  not-taken (with fall-through executing). Encoder helper
  cross-checked against hand-computed `JREQ +5 = 0xC405` and
  `JRNE +5 = 0xC705`.
- `tb_jruc_short` unchanged — UC (cc=0000) still encodes the same
  opcodes, so the existing test continues to verify the unconditional
  path through the refactored code.
- K-form arithmetic: **ADDK K, Rd** and **SUBK K, Rd**. Chart top-6
  prefixes `6'b000100` and `6'b000101` (per A0018). Reuses the
  `k5` field that MOVK already populates and the SUB-style operand
  swap pattern (alu_a = Rd, alu_b = K_zero_extended). Updates
  N/C/Z/V from the result.
- Added `sim/tb/tb_addk_subk.sv` — six cases: increment (ADDK 5),
  decrement (SUBK 1), max-K (ADDK 31), unsigned wrap (ADDK 1 of
  0xFFFFFFFF → 0 with C, Z), zero-result (SUBK 5 of 5 → 0 with Z),
  B-file (ADDK 16). Encoder verified against three hand-computed
  encodings (0x1020, 0x17E0, 0x10F5).
- Added assumption A0018 documenting the literal-K interpretation
  and flagging the unresolved K=0 → 32 hypothesis that some TI
  K-form ISAs use.
- Single-register unary block: **NEG Rd** and **NOT Rd**.
  Encoding family `0000 0011 XX1R DDDD` (the "unary" group) per
  SPVU001A A-14, with `bits[6:5]` selecting sub-op (01=NEG, 11=NOT).
  Both join the SUB-style alu_a swap group (Rd → alu_a). The ALU's
  existing NEG and NOT ops produce the right flag patterns,
  including V=1 on `NEG 0x8000_0000`.
- Deferred from this batch: **ABS** (needs an ALU op variant that
  conditionally negates based on sign + sets V on MIN_INT) and
  **NEGB** (Rd - 0 - C; needs carry-in routing). Tracked as
  not-started rows in `docs/instruction_coverage.md`.
- Widened `instr_class_t` from 4 bits to 5 bits to make room for
  the growing instruction set.
- Added `sim/tb/tb_neg_not.sv` — six cases covering NEG of a small
  positive, NEG of 0, NEG of MIN_INT (V-flag check), NOT of a
  mixed pattern, NOT of 0 → all-ones, and a B-file NOT.
- IW-form immediate arithmetic batch: **ADDI IW, SUBI IW, CMPI IW**.
  All three share encoding shape `0000 1011 XXXR DDDD` + 16-bit
  immediate word, with bits[7:5] selecting op (000=ADDI, 111=SUBI,
  010=CMPI per SPVU001A A-14). Decoder gets a `top11` view for
  matching the 11-bit prefix. Operand routing: alu_a = Rd,
  alu_b = imm32 (sign-extended from the 16-bit immediate). CMPI
  uses `wb_reg_en = 0` (nondestructive, same contract as CMP Rs,Rd).
- All three reuse MOVI IW's CORE_FETCH_IMM_LO state; no new FSM
  states needed.
- Added `sim/tb/tb_immi_iw.sv` — five cases: ADDI positive,
  SUBI to zero (Z=1), ADDI with negative sign-extended immediate
  (verifies sign-extension), CMPI equal (Z=1, Rd unchanged), and
  a B-file ADDI.
- K-form shift batch: **SLA, SLL, SRA, SRL, RL** (all K K, Rd
  forms). Top-6 prefixes 6'b001000..001100 per SPVU001A A-14.
  Wires the shifter module — previously built but unused — into
  the writeback path via a new `use_shifter` field in
  `decoded_instr_t`. The result-data and flag-input muxes pick
  between ALU and shifter outputs.
- Added package shift-op constant routing in `decoded_instr_t`
  (`shift_op` field of type `shift_op_t`).
- Added `sim/tb/tb_shift_k.sv` — six cases: SLL of 1 (basic left
  shift), SRA of 0x80000000 (sign-extension verification), SRL
  of 0x80000000 (logical right verification), SLA of a pattern,
  RL by 16 (half-word swap), and a B-file SRL.
- Added assumption A0019 covering the literal-K interpretation
  and flagging the unresolved K=0 → 32 hypothesis for shifts
  (parallel to A0018 for ADDK/SUBK).
- IL-form immediate batch: **ADDI IL, SUBI IL, CMPI IL, ANDI IL,
  ORI IL, XORI IL**. Six 32-bit-immediate instructions all sharing
  the 11-bit-prefix encoding shape. SUBI IL is the odd one out with
  a different base prefix (`0000_1101_000` vs `0000_1011_XXX` for
  the others). Reuses MOVI IL's CORE_FETCH_IMM_HI path.
- Added `sim/tb/tb_immi_il.sv` — six cases exercising 32-bit
  immediates that the IW form cannot encode (large values, full
  bit patterns). Includes CMPI IL with `wb_reg_en=0` verification
  and an XORI to invert (B-file).
- **MOVE Rs, Rd** (register-to-register move, same file). Encoding
  `1001 00FS SSSR DDDD` (top6 = `6'b100100`) per SPVU001A A-14.
  Routes through ALU PASS_A. The F bit (field-size selector,
  bit[9]) is ignored — Phase 4 implements full-width 32-bit
  register copy. Documented as A0020; field-size mechanics + the
  MOVE indirect-addressing variants are Phase 5 work.
- Added `sim/tb/tb_move_rr.sv` — four cases covering A-to-A move
  of a pattern, MOVE of zero (Z=1), MOVE of MIN_INT (N=1), and a
  B-file move. Encoder verified against hand-decoded
  `MOVE A1,A2 = 0x9022` and `MOVE B5,B7 = 0x90B7`.
- Added **unsigned-compare condition codes** to JRcc: LO (cc=0001,
  C=1), LS (cc=0010, C|Z), HI (cc=0011, ~C&~Z), HS (cc=1001, !C).
  These are universally defined across the field and can be added
  without ambiguity from the garbled spec table. Signed-compare
  codes (LT/LE/GT/GE) remain deferred until cleaner spec access.
- Added `sim/tb/tb_jrcc_unsigned.sv` — six scenarios covering each
  cc's take and skip paths. Uses a "sentinel register" pattern:
  each scenario pre-initializes its sentinel to a recognizable
  marker, then the fall-through MOVI overwrites it only if the
  branch did NOT take. The landing site writes elsewhere. This
  cleanly distinguishes "branch took" from "branch didn't take"
  by checking whether the sentinel still holds its marker.
- Added **NOP (No Operation)** — single fixed encoding `0x0300` per
  SPVU001A §"NOP" page 12-170 (A0021). `INSTR_NOP` joins the
  instruction-class enum; the decoder recognizes the exact 16-bit
  pattern; both writeback gates stay 0 so the only architectural
  effect is the PC advance the FETCH-ack pulse already provides. No
  core changes required. Distinct from the unary family at
  `0000 0011 1xxx xxxx` (ABS A0 = `0x0380`, not `0x0300`).
- Added `sim/tb/tb_nop.sv` — exercises MOVI → NOP → MOVK and verifies
  A0 untouched across NOP, B5 reached (PC advanced), ST.N/ST.Z
  preserved, and `illegal_opcode_o == 0`. Memory is pre-filled with
  NOP so the CPU keeps NOPing past the meaningful program, keeping
  the illegal-flag check meaningful at end-of-test.
- Added `docs/assumptions.md` A0021 capturing the NOP encoding source
  and the encoding distinction from the unary family.
- Added **ADDC Rs, Rd** (`0100 001S SSSR DDDD`) and **SUBB Rs, Rd**
  (`0100 011S SSSR DDDD`) — reg-reg arithmetic with carry-in /
  borrow-in from ST.C, used for extended-precision arithmetic chained
  with ADD/SUB/SUBI/etc. Both write N, C, Z, V from the 33-bit
  adder/subtractor. The ALU already implemented ADDC/SUBB; the work
  here is decode arms, the SUBB operand-swap (alu_a=Rd, alu_b=Rs to
  match SUB), and the test. A0022 captures the semantics and the use
  of SPVU001A page 12-248's worked SUBB examples as test vectors.
- Widened `instr_class_t` from 5 to 6 bits (Task 0029) — INSTR_NOP at
  5'd31 had exhausted the 5-bit space. All existing enumerator values
  preserved; only the enum width and the literal-width prefixes
  changed.
- Added `sim/tb/tb_addc_subb.sv` — five test cases landing in distinct
  destinations: ADDC with C=0; ADDC with C=1; SUBB with C=0; SUBB
  with C=1; and the SPVU001A page 12-248 row 7 spec vector
  (`0x7FFFFFFE - 0xFFFFFFFE` with C=0 → `0x80000000`, NCZV=1101)
  serving as the signed-overflow corner case. The carry-in for each
  test is set up using either MOVI/MOVK (preserve / clear C) or a
  deliberately-overflowing ADD (set C=1).

### Fixed
- **JRcc EQ/NE condition codes were WRONG.** A0017 (Task 0020) guessed
  CC_EQ = `4'b0100` and CC_NE = `4'b0111` from a garbled `pdftotext`
  extraction of Table 12-8. SPVU001A actually defines those codes as
  the signed-compare LT and GT, respectively. The correct encodings,
  confirmed by a clean `pdftotext -layout` re-extraction from the
  long-form JRcc page (12-96), are EQ = `4'b1010` and NE = `4'b1011`.
  Task 0030 corrects the package constants. Existing tests passed
  only because their encoding helpers composed the cc field from the
  same wrong constants; with the package fix the helpers now produce
  the spec-correct binary for JREQ (0xCAdd) and JRNE (0xCBdd). The
  two hard-coded hex sanity checks in `tb_jrcc_short.sv` were
  updated. A0017 marked SUPERSEDED; A0023 records the full corrected
  Table 12-8.
- Lesson: `pdftotext` without `-layout` mangles columnar charts beyond
  recoverability. The new `pdf-layout-for-charts` memory captures
  this so future spec extractions use the right invocation.

### Added (continued)
- **Signed-compare JRcc condition codes (Task 0030)**: LT (`4'b0100`,
  `N^V = 1`), GE (`4'b0101`, `N^V = 0`), LE (`4'b0110`, `(N^V) | Z`),
  GT (`4'b0111`, `!(N^V) & !Z`). The decoder accepts all 11 confirmed
  cc codes now (UC, LO, LS, HI, LT, GE, LE, GT, HS, EQ, NE). Codes
  not in this list still trap as ILLEGAL.
- Added `sim/tb/tb_jrcc_signed.sv` — eight scenarios spanning all
  four signed cc's in both directions, using the sentinel-register
  pattern from `tb_jrcc_unsigned.sv` (each sentinel is pre-set to a
  marker; if the JRcc takes, the marker survives; if it falls through,
  the marker is overwritten). The operand pairs (Rd, Rs) = (-5, 5),
  (5, -5), and (5, 5) drive the (N, V, Z) flags such that each cc's
  take and skip paths are both exercised.
- Added `docs/assumptions.md` A0023 with the full corrected Table
  12-8 (11 currently-recognized codes; deferred codes for P/N, V/NV,
  JRYxx XY-compares explicitly listed).
- Added **JRcc long form (16-bit displacement)** — Task 0031. Per
  SPVU001A page 12-96, when the opcode word's low byte is `0x00`,
  the next 16-bit word is a signed word-displacement and the range
  becomes ±32K words. `INSTR_JRCC_LONG` joins the iclass enum; the
  decoder routes the long form to `needs_imm16 = 1`; the core's
  `branch_target_long` adds the sign-extended disp×16 to the PC
  value seen at CORE_WRITEBACK (which has already advanced through
  both fetches, matching the spec's PC').
- Added `sim/tb/tb_jrcc_long.sv` — four scenarios: JRUC long taken
  (small positive disp), JREQ long taken via CMPI Z=1, JREQ long
  NOT taken via CMPI Z=0, and JRUC long with disp = +64 words to
  exercise the high byte of the disp word. Memory NOP-pre-filled.
- Added **JUMP Rs (register-indirect jump)** — Task 0032. Per
  SPVU001A page 12-98: encoding `0000 0001 011R DDDD`; semantics
  `PC ← (Rs & ~0xF)` (word-aligned). Single-word instruction, no
  status effect. `INSTR_JUMP_RS` joins the iclass enum; the
  decoder routes the rs1 port to read Rs; the core's PC-load mux
  gains an unconditional JUMP arm that masks the bottom 4 bits of
  rf_rs1_data before writing it to the PC.
- Added `sim/tb/tb_jump_rs.sv` — two scenarios: aligned A-file
  target; messy-LSB B-file target (verifies the bottom-nibble mask).
  Plus a sentinel check confirming no fall-through MOVI ran, and
  the standard illegal-flag check (memory NOP-pre-filled).
- Added **DSJ / DSJEQ / DSJNE Rd, Address** (Task 0033) — the
  Decrement-and-Skip-Jump family for loop primitives. Per SPVU001A
  pages 12-70..12-73, encodings `0000 1101 100R DDDD`,
  `_101R_`, `_110R_` followed by a 16-bit signed word-offset.
  Semantics: decrement Rd (if pre-condition holds for the
  conditional variants — Z=1 for DSJEQ, Z=0 for DSJNE); if the
  post-decrement value is non-zero, branch by `offset×16`; else
  fall through. Status register unaffected.
- The core gains a `dsj_precondition` signal that gates `rf_wr_en`
  (so DSJEQ Z=0 / DSJNE Z=1 leave Rd untouched per spec) and the
  PC-load (so the branch only fires when both the pre-condition and
  the `alu_result != 0` post-decrement check hold). Branch target
  reuses the existing `branch_target_long` computation. DSJ-family
  joins the alu_a operand-swap group (Rd routes to alu_a) and the
  K-form alu_b mux arm (decoded.k5 = 1 → alu_b = 32'd1).
- Added `sim/tb/tb_dsj.sv` — eight scenarios using DISTINCT counter
  registers per scenario (so end-of-test checks aren't clobbered by
  subsequent scenarios), covering the SPVU001A spec-table boundary
  cases for all three instructions. Test ends with a `0xC0FF`
  infinite-loop halt to prevent memory wraparound re-executing the
  program. Both gotchas (the comment-swallow and the halt pattern)
  are now captured in the `testbench-pitfalls` memory.
- DSJS (Decrement and Skip Jump — Short, single-word, 5-bit offset +
  direction bit) explicitly deferred — different encoding shape.
- Added **JAcc Address (absolute conditional jump)** — Task 0034.
  Per SPVU001A page 12-91: when the JRcc-shape opcode word's low
  byte is `0x80`, the next two words are a 32-bit absolute target
  address (LO, HI). PC ← address with bottom 4 bits forced to 0
  (spec-mandated word alignment). `INSTR_JACC` joins the iclass
  enum; the decoder routes it to `needs_imm32 = 1`; the core's new
  `branch_target_jacc` assembles `{imm_hi_q, imm_lo_q[15:4], 4'h0}`
  and feeds it into a new PC-load arm gated by the existing JRcc
  `branch_taken` evaluator.
- Added `sim/tb/tb_jacc.sv` — three scenarios: JAUC absolute taken
  with deliberately-messy bottom nibble (verifies the alignment
  mask), JAEQ absolute taken via CMPI Z=1, JANE absolute NOT taken
  via CMPI Z=1 (fall-through MOVI runs).
- Added **DSJS Rd, Address** (Task 0035) — the single-word
  short-form decrement-and-skip-jump that completes the DSJ family.
  Per SPVU001A page 12-74: encoding `0011 1Dxx xxxR DDDD`. The
  D bit (10) selects direction (0 = forward, 1 = backward); the
  5-bit offset (bits[9:5]) gives the word-displacement. Target =
  PC' ± offset×16. Rd is decremented unconditionally; branch is
  taken iff post-decrement Rd != 0. Status N/C/Z/V unaffected.
- The core extracts the direction bit and offset combinationally
  from `instr_word_q[10]` and `[9:5]` for `branch_target_dsjs`,
  rather than carrying them in the decoded struct. `INSTR_DSJS`
  joins the DSJ-family alu_a swap group, the K-form alu_b mux
  arm, and the dsj_precondition logic (with precondition = 1
  like DSJ). A new PC-load mux arm fires the branch when
  `dsj_rd_nonzero` (the post-decrement is nonzero).
- Added `sim/tb/tb_dsjs.sv` — four scenarios: forward take (9→8),
  forward skip (1→0), backward take (choreographed with a pre-
  executed back-target MOVI so the backward jump lands at a known
  sentinel), and the 0→0xFFFFFFFF spec corner case. Distinct
  counter registers per scenario; halt at end-of-program.
- Added **ABS Rd** and **NEGB Rd** (Task 0036) — completes the
  unary-instruction family that NEG and NOT started in Task 0022.
  Per SPVU001A pages 12-34 (ABS) and 12-168 (NEGB), encodings
  `0000 0011 100R DDDD` (ABS) and `0000 0011 110R DDDD` (NEGB).
  - ABS uses a new ALU_OP_ABS that mux-selects between `a` and
    `0-a` based on the sign of `0-a`. V=1 only when Rd was MIN_INT
    (`0x8000_0000`), matching the spec's V-overflow convention.
    N reflects the sign of `0-Rd` (NOT the sign of the result),
    again per spec.
  - NEGB reuses ALU_OP_SUBB with alu_a forced to 0 by a new core
    mux arm; the existing carry-in path (from ST.C) gives
    `Rd ← 0 - Rd - C` as required.
- Added `sim/tb/tb_abs_negb.sv` — 6 ABS test vectors lifted verbatim
  from SPVU001A page 12-34's worked example table (positive max,
  -1 → +1, MIN_INT V-flag case, MIN_INT+1, zero, and a generic
  negative). 4 NEGB vectors from page 12-168 covering both
  carry-in values × representative operands. Final ST.NCZV is
  cross-checked against the last NEGB row's NCZV column.
- Added `docs/assumptions.md` A0024 documenting one deviation: ABS
  currently CLEARS C, but the spec says C should be "Unaffected".
  This is a consequence of the project's still-all-or-nothing
  `wb_flags_en`. The fix is a per-flag mask in
  `decoded_instr_t` + `tms34010_status_reg`, planned to land
  together with BTST (which also needs selective Z-only updates).
- **A0024 RESOLVED in Task 0037** via the per-flag-mask refactor
  described below.

### Changed
- **Per-flag writeback mask** (Task 0037): added
  `wb_flag_mask : alu_flags_t` to `decoded_instr_t` and a
  `flag_update_mask` input to `tms34010_status_reg.sv`. The status
  register's always_ff now gates each of N, C, Z, V independently:
  a flag updates iff `flag_update_en && flag_update_mask.{flag}`.
  The decoder's always_comb defaults `wb_flag_mask = '1` so every
  pre-existing instruction continues with full flag-update behavior
  unchanged. New instructions that need selective updates override
  the mask in their decoder arms.
- ABS arm now sets `wb_flag_mask = '{n:1, c:0, z:1, v:1}` so C is
  truly "Unaffected" per SPVU001A page 12-34. (A0024 was created
  in Task 0036 as a deviation; Task 0037 marks it RESOLVED.)
- `sim/tb/tb_status_reg.sv` updated to drive the new `flag_update_mask`
  port with all-ones for its existing pre-refactor checks.

### Added
- **BTST K, Rd** and **BTST Rs, Rd** (Task 0037) — Bit-Test family.
  Per SPVU001A pages 12-46 / 12-47 + summary table lines
  26942/26943, encodings `0001 11KK KKKR DDDD` (BTST K) and
  `0100 101S SSSR DDDD` (BTST Rs). Semantics: test a single bit
  of Rd (selected by K or by Rs[4:0]); Z = 1 iff that bit is 0.
  Rd is NOT written. N, C, V are truly Unaffected (verified via the
  new mask).
- Implementation:
  - `INSTR_BTST_K = 6'd43`, `INSTR_BTST_RR = 6'd44` in iclass.
  - Decoder arms with `alu_op = ALU_OP_AND`, `wb_reg_en = 0`,
    `wb_flag_mask = '{n:0, c:0, z:1, v:0}`.
  - Core's alu_b mux drives `32'd1 << decoded.k5` for BTST K and
    `32'd1 << rf_rs1_data[4:0]` for BTST Rs. alu_a = Rd via the
    existing rs2-swap group. The resulting AND has a single bit
    set iff that bit was 1 in Rd, so Z falls out of the standard
    "Z = (result == 0)" ALU convention.
- Added `sim/tb/tb_btst.sv` — 5 JRZ/JRNE-probed scenarios covering
  BTST K (with K=0, K=1, K=31) and BTST Rs forms; plus a final
  CMP-NCZV=1101 → BTST → halt sequence directly verifying that
  N, C, V are preserved across the BTST (the wb_flag_mask
  end-to-end check).
- Added **CLRC / SETC / GETST / PUTST** (Task 0038) — the
  status-register manipulation family.
  - CLRC (0x0320) / SETC (0x0DE0): single-fixed-encoding control
    instructions. Both use the new wb_flag_mask with c-only
    enabled. The core's flag-input mux gains constant `{c:0,…}`
    and `{c:1,…}` arms so only ST.C is touched; N, Z, V are truly
    Unaffected.
  - GETST Rd (`0x0180 | (R<<4) | Rd`): copies the 32-bit status
    register into Rd. The core's `rf_wr_data` mux gains an arm
    routing `st_value` for this iclass.
  - PUTST Rs (`0x01A0 | (R<<4) | Rs`): full 32-bit write of Rs
    into ST. Uses the existing `st_write_en` + `st_write_data`
    path; the N/C/Z/V bits embedded in Rs become the new flags
    automatically.
- Added `sim/tb/tb_st_ops.sv` — PUTST + GETST round-trip with a
  custom ST value, then SETC and CLRC each followed by a GETST
  capture, then bit-level checks confirming CLRC/SETC truly only
  touch C (N/Z/V preserved from the prior PUTST value).
- Added **Shift Rs-form family** — SLA / SLL / SRA / SRL / RL with
  the shift amount sourced from Rs's low 5 bits instead of a 5-bit
  literal (Task 0039). Five new iclass values and decoder arms with
  the `0110_0NN` top-7 prefix shape from SPVU001A page A-15. The
  core's shifter-amount input gains a new mux: K-form arms drive
  `decoded.k5` (unchanged); Rs-form left/rotate shifts (SLA/SLL/RL)
  drive `rf_rs1_data[4:0]` directly; Rs-form right shifts (SRA/SRL)
  drive `(~rf_rs1_data[4:0]) + 1` to apply the 2's-complement
  convention spelled out on page 12-219 ("the SRA Rs, Rd and SRL
  Rs, Rd use the 2s complement value of the 5 LSBs in Rs"). This
  extends A0019 to cover the Rs form.
- Added `sim/tb/tb_shift_rr.sv` — five scenarios, one per opcode,
  each shifting by 4. For SRA/SRL the test loads A1 = 28 (5-bit
  2's-comp of -4) to drive a magnitude-4 right shift, verifying
  the negation in the shifter-amount mux end-to-end.
- Added **GETPC / EXGPC / REV** (Task 0040) — three small
  PC/register-context ops.
  - GETPC Rd: copies the current pc_value (at CORE_WRITEBACK, i.e.,
    one word past the GETPC opcode) into Rd.
  - EXGPC Rd: atomic swap PC ↔ Rd. The new PC has its bottom 4 bits
    forced to 0 (word alignment per A0025); the regfile's async-read
    rf_rs2_data delivers the OLD Rd value during the same WRITEBACK
    cycle that writes the new Rd, so no extra pipeline stage is
    needed.
  - REV Rd: writes the chip-revision constant 0x0000_0008 into Rd,
    per the spec's worked example on page 12-233.
- Added `docs/assumptions.md` A0025 capturing two related choices:
  the REV constant value and the EXGPC bottom-nibble PC mask. Both
  are clean reads of the 1988 User's Guide.
- Added `sim/tb/tb_pc_ops.sv` — verifies GETPC's PC bit-address
  capture, REV's constant write, and EXGPC's atomic swap (with a
  trap-sentinel MOVI right after EXGPC that must NOT execute, plus
  a known landing-site MOVI at the EXGPC target verifying the swap
  actually transferred control there).
- Added **LMO Rs, Rd** (Task 0041) — Find Leftmost-One priority
  encoder. Per SPVU001A page 12-108, encoding `0110 101S SSSR DDDD`
  (top7 = 7'b0110_101). Semantics: Rd ← 31 - bit_pos(leftmost-1 in
  Rs) in the bottom 5 bits (upper 27 = 0). If Rs == 0, Rd = 0 and
  Z = 1. N, C, V Unaffected (via the wb_flag_mask from Task 0037).
- Core gains a combinational LMO datapath: a synthesizable
  low-to-high scan over Rs's 32 bits (the last hit wins, so we
  end up with the highest-set bit position), then a conditional
  one's-complement (5 bits) into the bottom of Rd. The `flag_input`
  mux delivers `{z: (rs == 0), others: 0}` for INSTR_LMO_RR.
- Added `sim/tb/tb_lmo.sv` — all 5 worked examples from the spec's
  page-12-108 table (Rs=0, 1, 0x10, 0x08000000, 0x80000000) plus
  an N/C/V-preservation check that runs a CMP to set NCZV=1101,
  then an LMO, then verifies the three flags survived.

### Changed (Task 0042 — Phase 5 foundation)
- **Status register layout finalized** against SPVU001A §5.2 Table 5-2
  (page 5-18). The N/C/Z/V positions at 31..28 (originally A0010
  placeholders) happened to match the spec; the new constants pin
  down FS0[4:0], FE0[5], FS1[10:6], FE1[11], IE[21], PBX[25] to
  their authoritative positions.
- `tms34010_pkg.sv` gains six new ST-bit-position parameters plus
  `ST_RESET_VALUE = 32'h0000_0010` (per spec page 5-18 — FS0 = 16
  at reset, all flags clear).
- `tms34010_status_reg.sv` initializes `st_q` to `ST_RESET_VALUE`
  on reset instead of all-zeros.
- `sim/tb/tb_status_reg.sv`'s "after reset" check updated for the
  new reset value.
- `docs/assumptions.md` A0010 marked RESOLVED with the full layout
  spelled out.
- No instruction changes in this task — it's foundational for the
  upcoming SETF / EXGF / SEXT / ZEXT / DINT / EINT tasks.

### Added (Task 0043 — SETF FS, FE, F)
- Implemented **SETF FS, FE, F** per SPVU001A page 12-237. Encoding
  `0000 01F1 01FE FFFFF` — bit[9]=F selector, bit[5]=FE, bits[4:0]=FS.
  When F=0, updates FS0/FE0; when F=1, updates FS1/FE1. FS=0 encodes
  field-size 32 (per Table 5-3). Other ST bits (flags, the other FS/FE
  pair, IE, PBX, reserved) are preserved — verified end-to-end by a
  CMP-set-NCZV → SETF → GETST sequence in tb_setf.
- Core changes:
  - `st_write_en` now fires for both INSTR_PUTST (existing) and
    INSTR_SETF.
  - `st_write_data` is a small case mux: PUTST routes Rs unchanged;
    SETF routes a spliced-ST value built by reading the current
    `st_value` and overwriting the F-selected FS/FE bits with the
    literal values pulled directly from `instr_word_q[4:0]` and
    `instr_word_q[5]`.
- Added `sim/tb/tb_setf.sv` — 5 scenarios covering FS0/FE0 update,
  FS1/FE1 update, FS=0 encodes 32, FS=31 boundary, and N/C/V/Z
  preservation across SETF.

### Added (Task 0044 — SEXT and ZEXT)
- Implemented **SEXT Rd, F** (sign-extend a field) per SPVU001A page
  12-238 and **ZEXT Rd, F** (zero-extend) per page 12-256. Both
  share the encoding shape `0000 01F1 SS_R_DDDD` with bits[7:5]
  selecting sub-op (000 = SEXT, 001 = ZEXT). The F bit at instr[9]
  selects FS0/FS1 from ST.
- Core gains a field-extension datapath: `fs_selected` reads the
  F-chosen FS bits from `st_value`; `field_mask` is built dynamically
  (`(1 << fs_selected) - 1`, with FS=0 treated as identity per
  Table 5-3's "encoding 00000 = size 32"); `sext_result` and
  `zext_result` are then a mask + optional sign-fill.
- Flag policy via wb_flag_mask: SEXT updates N, Z (C, V Unaffected);
  ZEXT updates only Z (N, C, V Unaffected) — both spec-correct.
- Added `sim/tb/tb_sext_zext.sv` running the spec's worked examples
  verbatim: 6 SEXT vectors (FS = 15, 16, 17 × F = 0, 1) and 5 ZEXT
  vectors (FS = 32-encoded-as-0, 31, 1, 16 × F = 0/1).

### Added (Task 0045 — EXGF Rd, F)
- Implemented **EXGF Rd, F** per SPVU001A page 12-77. Encoding
  `1101 01F1 000R DDDD` — top6 = 0x35, F at instr[9]. Atomic swap of
  Rd's low 6 bits with the F-selected `{FE, FS}` pair in ST; Rd's
  upper 26 bits are cleared.
- Core gains a small atomic-swap datapath: `exgf_cur_fs`/`exgf_cur_fe`
  read the OLD field values from ST; `exgf_new_rd = {26'b0, cur_fe,
  cur_fs}`; `exgf_new_st` splices the OLD Rd[5:0] (from the
  async-read rf_rs2_data, which sees the value BEFORE the same-cycle
  write) into the F-selected slot. `st_write_en` now triggers for
  INSTR_EXGF as well as PUTST and SETF; the st_write_data mux gains
  the matching arm.
- Added `sim/tb/tb_exgf.sv` running both spec-page-12-77 worked
  examples (F=0 and F=1) verbatim. Test-design note in the file
  documents a gotcha: MOVI must precede PUTST when seeding ST,
  because MOVI's default wb_flag_mask updates N/C/Z/V and would
  otherwise clobber the freshly-PUTST'd ST.

### Added (Task 0046 — DINT and EINT)
- Implemented **DINT (`0x0360`)** and **EINT (`0x0D60`)** — single-
  fixed-encoding interrupt-enable control instructions. DINT clears
  ST.IE (bit 21); EINT sets it. All status flag bits Unaffected.
  Implemented via the existing full-ST-write path with a small
  st_write_data mux extension:
    INSTR_DINT → `st_value & ~(1 << ST_IE_BIT)`
    INSTR_EINT → `st_value |  (1 << ST_IE_BIT)`
- `st_write_en` now triggers for {PUTST, SETF, EXGF, DINT, EINT}.
- Finally uses the `ST_IE_BIT` constant from Task 0042 — resolves
  one of the UNUSEDPARAM lint warnings.
- Added `sim/tb/tb_dint_eint.sv` — PUTSTs the seed value
  `0xA5A5_05A5 & ~IE`, then EINT → GETST → check IE=1 and other
  bits preserved, then DINT → GETST → check IE=0 and other bits
  still preserved. The scattered bit pattern in the seed catches
  any accidental wider write.

### Added (Task 0047 — Memory-write infrastructure + PUSHST)
- **Memory-write infrastructure** is now live. The core's
  previously-stubbed `CORE_MEMORY` FSM state actively drives
  `mem_req`/`mem_we`/`mem_addr`/`mem_size`/`mem_wdata` for write
  transactions and transitions to `CORE_WRITEBACK` on `mem_ack`.
  A new `decoded.needs_memory_op` field signals the decoder's
  intent to slot a memory transaction between EXECUTE and WRITEBACK.
- `sim_memory_model.sv` now handles 32-bit reads and writes
  atomically: when `latched_size == 32`, two adjacent 16-bit words
  are written/read in a single ack. (16-bit transactions remain
  single-word as before.)
- `instr_class_t` widened from 6 to 7 bits (INSTR_PUSHST = 64
  overflowed the prior 6-bit cap).
- **PUSHST** (= 0x01E0) implemented as the first user of the
  memory-write path. `SP <- SP - 32; mem[SP] <- ST`. ALU computes
  the new SP via SUB with `alu_b = 32` (new mux entry); the
  CORE_MEMORY state writes ST to mem[alu_result] as a 32-bit
  transfer; WRITEBACK updates SP (regfile index 15 = SP alias).
  Status bits Unaffected per spec.
- Added `sim/tb/tb_pushst.sv` — initializes SP to a mid-memory
  bit-address, PUTSTs a seed pattern, runs PUSHST, then verifies
  (a) SP decremented by 32, (b) both 16-bit memory words at the
  new SP hold the low/high halves of ST, (c) ST itself is unchanged.
- Going forward: POPST, CALL/CALLA/CALLR, RETS/RETI, TRAP, MMTM/
  MMFM, MOVE memory-indirect, and MOVB all unblock on this
  infrastructure.

### Added (Task 0048 — POPST)
- Implemented **POPST** (= 0x01C0) — the inverse of PUSHST and the
  first instruction in the project that reads a 32-bit memory word
  and writes it to a non-regfile destination (ST). Per SPVU001A:
  `ST <- mem[SP]; SP <- SP + 32`. All four status flags are taken
  from the popped value's bits[31:28].
- INSTR_POPST = 7'd65. Decoder arm matches the literal opcode and
  sets `alu_op = ADD` (so the ALU produces `SP + 32` for the
  regfile-SP writeback), `wb_reg_en = 1`, `needs_memory_op = 1`.
  `wb_flags_en` stays 0 because the ST update goes through
  `st_write_en`/`st_write_data`, not the per-flag mask path.
- Core changes:
  - `alu_b` mux: INSTR_POPST joins PUSHST's `→ 32'd32` entry.
  - `CORE_MEMORY` arm for POPST drives `mem_we=0`,
    `mem_addr = rf_rs1_data` (= OLD SP, NOT `alu_result`), `mem_size=32`.
  - `st_write_en` triggers for INSTR_POPST as well as PUTST/SETF/
    EXGF/DINT/EINT.
  - `st_write_data` mux: INSTR_POPST → `mem_rdata` (the popped
    32-bit value).
- Added `sim/tb/tb_popst.sv` — runs a full PUSHST/POPST round-trip:
  seed ST, PUSHST, clobber ST with a different value, POPST,
  verify ST recovered, SP restored, and the four flag bits in the
  popped ST match `ST_SEED[31:28]`.

### Added (Task 0049 — CALL Rs)
- Implemented **CALL Rs** (= `0x0920 | (R<<4) | Rs`) — the first
  subroutine-call instruction. Per SPVU001A page 12-47:
    SP -= 32
    mem[new SP] = PC'      (return address)
    PC = Rs                 (with bottom 4 bits cleared for alignment)
- INSTR_CALL_RS = 7'd66. Decoder arm with top11 = 0x049. Reuses the
  memory-write path from PUSHST plus the bottom-nibble-mask PC-load
  pattern from JUMP Rs.
- Core changes:
  - `alu_a` swap group factored: INSTR_PUSHST, INSTR_POPST, and
    INSTR_CALL_RS all read SP via rs2 (since rd_idx=15 for all three).
  - `alu_b` mux: all three constants converge on `32'd32`.
  - CORE_MEMORY: new INSTR_CALL_RS arm. mem_addr = alu_result
    (= new SP), mem_we=1, mem_size=32, mem_wdata=pc_value (= PC',
    which is the bit-address of the instruction following the CALL
    opcode at this point in the FSM).
  - PC-load mux: INSTR_CALL_RS unconditionally loads PC with
    `{rf_rs1_data[31:4], 4'h0}` (Rs with bottom nibble cleared).
- Added `sim/tb/tb_call_rs.sv` — places a subroutine at word 100
  that writes A6 = 0xCAFE_BABE; CALL A5 (= 0x640 = word 100*16);
  verifies (a) subroutine ran, (b) SP decremented, (c) mem[126..127]
  holds PC' (= bit-address of the instruction right after the CALL).

### Added (Task 0050 — RETS [N])
- Implemented **RETS [N]** per SPVU001A page 12-231. Encoding
  `0000 1001 011N NNNN` (`0x0960 | N`). Semantics:
    PC <- mem[SP]    (32-bit pop)
    SP <- SP + 32 + 16*N
  Status bits all "Unaffected". N at instr[4:0] is an optional
  argument-pop count (0..31); RETS without N defaults to N=0.
- INSTR_RETS = 7'd67. The decoder routes `instr[4:0] → decoded.k5`.
- Core changes:
  - alu_a swap group: INSTR_RETS joins (alu_a = SP via rs2).
  - alu_b mux new entry: `INSTR_RETS → 32'd32 + (decoded.k5 << 4)`.
    Computes 32 + 16*N. For N=0 → 32; for N=31 → 528 (per the spec
    page-12-231 worked example showing `SP -> SP+0x210` for N=31).
  - CORE_MEMORY: INSTR_RETS arm reads 32 bits from `rf_rs2_data` (=
    old SP), `mem_we=0`, `mem_size=32`.
  - PC-load mux: INSTR_RETS unconditionally loads `mem_rdata` into
    PC (no bottom-nibble mask, since the popped PC was already
    word-aligned when pushed).
- Added `sim/tb/tb_rets.sv` — full CALL → subroutine → RETS
  round-trip. Pre-CALL sentinel `A7 = 0xAAAA_AAAA`; subroutine
  writes A6 = 0xCAFE_BABE then RETS; post-CALL MOVI writes
  A7 = 0x0000_BEEF — that MOVI only runs if RETS actually returned
  correctly. So end-of-test `A7 == 0xBEEF` directly confirms the
  full subroutine round-trip, with `SP` restored to the original
  value.

### Added (Task 0051 — CALLA + CALLR)
- Implemented **CALLA Address** (= `0x0D5F` + 32-bit absolute) and
  **CALLR Address** (= `0x0D3F` + 16-bit signed disp). Both per
  SPVU001A pages 12-48 / 12-49. Each pushes PC' (the post-CALL
  return address) and jumps:
    CALLA  PC <- absolute address (low 4 bits cleared)
    CALLR  PC <- PC' + sign_ext(disp16) * 16
- INSTR_CALLA = 7'd68, INSTR_CALLR = 7'd69.
- Decoder: two new single-fixed-encoding arms. CALLA sets
  `needs_imm32 = 1`; CALLR sets `needs_imm16 = 1`. Both set
  `needs_memory_op = 1`, `alu_op = SUB`, `wb_reg_en = 1`,
  `wb_flags_en = 0`.
- Core changes:
  - Both join the alu_a swap group (alu_a = SP via rs2) and the
    constant-32 alu_b mux entry.
  - CORE_MEMORY: CALLA / CALLR / CALL_RS now share a single arm
    that pushes `pc_value` (the FSM-advanced PC' for each variant)
    to `mem[alu_result]`.
  - PC-load mux: CALLA → `branch_target_jacc` (same as JAcc);
    CALLR → `branch_target_long` (same as JRcc long form). Both
    target paths were already in place from Tasks 0031 / 0034.
- Added `sim/tb/tb_calla_callr.sv` — two full call/return round
  trips. Scenario A uses CALLA with target = 0x0640 (= word 100
  bit-address). Scenario B uses CALLR with a computed positive
  disp that lands on word 200. Each subroutine writes a distinct
  marker register and ends with RETS; each post-CALL MOVI writes
  another marker that only runs if the return landed correctly.
  Final SP must equal the original SP after both round-trips.

### Changed
- `rtl/core/tms34010_core.sv` now also instantiates `tms34010_regfile`,
  `tms34010_alu`, and `tms34010_status_reg`. Datapath wires connect
  ALU `result` to the regfile's `wr_data` port and ALU `flags` to the
  status register's `flags_in` port. Every control signal (`rf_wr_en`,
  `st_flag_update_en`, `st_write_en`) is tied 0 in this commit so no
  visible behavior changes; Task 0012 replaces those tie-offs with
  decoded-instruction-driven values for the first real instruction.
- `rtl/core/tms34010_core.sv` then: latches imm_lo_q in the new
  CORE_FETCH_IMM_LO state, drives the writeback path
  (`rf_wr_en = (state == CORE_WRITEBACK) && decoded.wb_reg_en`),
  selects `alu_b` from the assembled `imm32` when the decoded class is
  `INSTR_MOVI_*`. CORE_FETCH_IMM_HI state added in preparation for
  MOVI IL (Task 0013) but not yet reachable.
- `tms34010_pkg.sv` core_state_t enum widened to 3 bits and two new
  states added: CORE_FETCH_IMM_LO, CORE_FETCH_IMM_HI. `decoded_instr_t`
  extended with `rd_file`, `rd_idx`, `needs_imm16`, `needs_imm32`,
  `imm_sign_extend`, `alu_op`, `wb_reg_en`, `wb_flags_en`.
- `instr_class_t` adds INSTR_MOVI_IW (used) and INSTR_MOVI_IL
  (reserved, decoded but currently routed to ILLEGAL).
- `rtl/core/tms34010_core.sv` now instantiates `tms34010_pc`, drives
  `mem_addr` from `pc_o`, and asserts `pc_advance_en` for one cycle on
  `mem_ack` in `CORE_FETCH`. New observability port `pc_o` on the core.
- `rtl/core/tms34010_core.sv` now also: (a) latches the fetched
  instruction word into `instr_word_q` on `mem_ack` in `CORE_FETCH`,
  (b) instantiates `tms34010_decode`, (c) walks the full FSM
  `CORE_FETCH → CORE_DECODE → CORE_EXECUTE → CORE_WRITEBACK → CORE_FETCH`
  (no instruction reaches `CORE_MEMORY` yet), and (d) maintains a
  sticky `illegal_q` latch set when a CORE_DECODE sees
  `decoded.illegal = 1`. Two new observability ports `instr_word_o`
  and `illegal_opcode_o`.
- `sim/tb/tb_smoke.sv` consumes the new `pc_o` and additionally asserts
  that `mem_addr === pc_o` while in `CORE_FETCH`.
- `scripts/sim.sh` discovers all `rtl/**/*.sv` and `sim/models/**/*.sv`
  sources automatically (package first, then RTL, then behavioral
  models, then the TB).

### Fixed
- N/A

### Known Limitations
- No register file, decode, or execute yet. The CORE_DECODE / EXECUTE /
  MEMORY / WRITEBACK arms of the FSM return to CORE_FETCH and have no
  side effects.
- The PC starts at the placeholder `RESET_PC = '0`; the architecturally-
  correct reset-vector fetch is Phase 8 work (assumption A0008).
- No branches/jumps yet, so the PC's `load_en` is currently tied 0 at
  the core boundary. The port is wired and tested in `tb_pc`.
- Smoke + tb_pc pass with Intel ModelSim ASE 17.0. Questa FSE 25.1.1
  on this dev box errors out on a license check
  (`SALT_LICENSE_SERVER` not configured); functionally equivalent for
  SystemVerilog compile + run.
- No FPGA synthesis flow yet beyond a placeholder script.
