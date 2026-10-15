# REVIEW_5 - independent review of 84c96fb..72f17ab (dropin-dev)

Reviewer: no part in the changes. Review copies: <scratch>/tms34010_sv_review5 (72f17ab)
and <scratch>/tms34010_sv_review5_base (84c96fb). The dropin worktree was not touched.

Written as I go. Findings first as found, checked-and-correct items noted alongside.

## 1. ca5135c - registered register-file read addresses

- CHECKED, CORRECT: rf_addr_fn body vs the removed assigns. I diffed them mechanically (old lines with
  state_q->st, decoded.->dc., is_*->f_*, line_rd_b->f_lrb, array_resume->f_ar, mm_iter_idx->f_mmiter).
  Only whitespace/comments differ. The helper terms inside the function (f_fill, f_pblt, f_ar, f_drav,
  f_line, f_lrb, f_mmtm/f_mmfm, the mask priority encoder) match the old is_fill/is_pblt/array_resume/
  is_drav/is_line/line_rd_b/is_mm*/mm_mask_idx/mm_iter_idx definitions (core.sv ~1999-2010, ~2162-2185).
- CHECKED, CORRECT: next-values.
  - state_q: only writer is core.sv:340-346 (rst -> CORE_RESET else state_d). Matches.
  - decoded: only writer core.sv:379-386 (rst -> '0, DECODE_WAIT -> decoded_comb). decoded_next matches.
  - mm_mask_q: three writes (rst, EXECUTE->MEMORY capture, MEMORY ack clear) all now load mm_mask_d,
    whose if/else-if has the same priority as the always_ff. Matches.
  - ST: tms34010_status_reg.sv is the only ST register. st_q loads st_write_data when st_write_en, else
    only N/C/Z/V bits via the flag port. PBX can only change through st_write_en (interrupt entry
    CORE_INT_DONE, RETI, POPST, PUTST, TRAP, array_pbx_complete all go through st_write_data).
    st_pbx_next matches. Stacked PBX at interrupt entry (int_stack_st) is memory, not ST.
  - reset value: fn(CORE_RESET, '0, 0, ST_RESET_VALUE.PBX) equals fn of the registers' reset values.
- CHECKED, CORRECT: the guard (core.sv ~2311-2319) compares rf_addr_q with rf_addr_fn of the *current*
  registers every clock, outside reset. That is the right comparison: with the function body proven equal
  to the old logic, guard-never-fires means the ports saw exactly the old addresses. It is inside
  `ifdef VERILATOR`; every bench script here uses Verilator, so it is compiled into every run. A firing
  guard calls $fatal(1), which fails the regression worker. (Mutation tests: see section 5.)

## 2. FINDING A (behaviour-changing, high confidence): the delayed writes eat the memory's time budget

What: 0c7bed8 (PIXBLT word writes, 2 clocks later) and, smaller, a740d23 (pixel writes, 1 clock later) change
machine-state counts when the external memory acknowledges in more than about 7 clocks. The "same state, so
bus cycles unchanged" claim only holds when the memory answers quickly (the bench's ACK_DELAY=1).

Where: rtl/core/tms34010_core.sv, `fsm_mem_req = (pbw_wr_stage_q == 2'd2)` in CORE_PBLT sub-step 2
(~line 4654) and the `pix_wr_step && !pix_wr_cnt_q` override at the end of the FSM block (~line 4990);
interacts with rtl/memory/tms34010_bus_timer.sv (credit/claim, `last && !ready` -> one wait state).

Why: the bus timer back-dates a CPU cycle to the start of the state the core raised it in (credit = clocks
since the state began). The 16-clock window (2 states) is fixed, so every clock the core spends before raising
the request is a clock the external memory no longer has. The external `cycle_ack_i` must arrive by the last
clock of the cycle's second state or a whole wait state is added. Raising the request 2 clocks later leaves the
memory 2 clocks less. docs/cycle_accuracy.md itself says the core's clocks "are kept inside the cycle's two
states" - so they are taken from the memory's share.

Evidence (my runs, review copies; bench = tb_accuracy, all 2,254 runs, accurate mode, 84c96fb vs 72f17ab):
- ACK_DELAY 1, 11, 13, 14: every RUN line identical (registers, memory hash, clock counts).
- ACK_DELAY 9: 564 of 2,254 runs differ, all PIXBLT; registers and memory identical, but the measured time is
  longer in 72f17ab by 2 to 150 states (e.g. RUN 1074 PIXBLT L,L PBH0 Replace psize4: 240 clocks = 30 states,
  the guide's figure, at 84c96fb; 264 clocks = 33 states at 72f17ab). Runs matching the guide's states:
  1,450 at 84c96fb, 1,010 at 72f17ab.
- Clock trace of RUN 1074 (+TRACE): source-read ack reaches the core at clock 3272; 84c96fb raises the write
  at 3274 and the external cycle starts 3278, ext ack 3287 = the window's last clock, no wait. 72f17ab raises
  at 3276, external start 3280, ext ack 3289, two clocks after the last clock -> one wait state (timer ack 3295).
  Each such word adds a state; the queue of posted writes then delays everything after.
- (11/13/14 are equal only because both versions already miss the window there.)

How sure: high. It is a direct, reproducible state-count change.
Does it matter: yes, if the game core's memory bridge answers in roughly 8-9 core clocks (an SDRAM bridge
at ~48-50 MHz core clock easily does). It would make PIXBLT slower than the guide on real hardware builds
while the timing bench (ACK_DELAY=1) stays green. I have not checked what NARC's bridge latency is.
How to confirm: build tb_accuracy with -GACK_DELAY=9 -GCYCLE_ACCURATE=1 at 84c96fb and 72f17ab and diff
the RUN lines (scripts in <scratch>/r5_build.sh, r5_ack_sweep.sh, r5_cmp.py; logs in <scratch>/r5out/).
Fix direction (not done): either keep the request raised at the original clock and register data a clock
later into the fabric's own request register, or compensate credit by the clocks the core added, or document a
tighter memory-latency limit. Whatever is chosen, add an ACK_DELAY sweep (e.g. 1..14) to the evidence.

Full ACK_DELAY sweep (accurate mode, all 2,254 runs, 72f17ab vs 84c96fb):

| ACK_DELAY | runs differing | which | direction | runs on the guide's states, 72f17ab / 84c96fb |
|---|---|---|---|---|
| 1 | 0 | - | - | same |
| 7 | 0 | - | - | 1,679 / 1,679 |
| 8 | 248 | PIXBLT | all slower | 1,332 / 1,546 |
| 9 | 564 | PIXBLT | all slower | 1,010 / 1,450 |
| 10 | 326 | PIXBLT 316, LINE 10 | all slower | 1,010 / 1,236 |
| 11, 12, 13, 14 | 0 | - | - | same |

So there is a band of memory latencies (8-10 clocks here) where 72f17ab is slower than 84c96fb. LINE appears
at 10, which is a740d23's one-clock delay; PIXBLT at 8-10 is 0c7bed8's two clocks. Registers and memory are
identical everywhere; only time changes. The bench's ACK_DELAY=1 (the setting the docs use for accurate mode)
cannot see this.

## 3. FINDING B (behaviour-changing, medium confidence on relevance): misaligned bus cycles break "same state"

What: when an earlier bus cycle ends off the state grid, a write step can start late in a state, and the
delayed raise then lands in the next state. This changes state counts even with ACK_DELAY=1.

How found: I added periodic host reads of HSTDATA to tb_accuracy (+HOSTPER=n, a host read every n clocks,
review copies only) and a Verilator-only monitor in a third copy (<scratch>/tms34010_sv_review5_mon,
`g_r5mon` before `assign state_o`) that prints R5CROSS when the original raise clock is the last clock of a
state and no pacing hold applies (i.e. the delayed raise moves to the next state).
- Without host traffic: 0 crossings in all 2,254 runs. Unheld pixel writes always start their step at phase 1,
  PIXBLT word writes at phase 1 or 2. So, on the bench's grid, the claim "raised in the same state" is right.
- With a host read every 211 clocks: 802 crossings (784 PIXBLT, 18 LINE). 291 PIXBLT runs end with different
  clock counts (first divergence RUN 1096 PIXBLT ... AND_PMASK psize4: 368 vs 360 clocks, +1 state; later runs
  then cascade both ways). Single-run reproducer: +ONLY=1096 +HOSTPER=207 (360 vs 352 clocks). Trace: a host
  cycle leaves the timer ack at phase 4 (clock 4788); sub-step 2 starts at phase 6; 84c96fb raises at 4790,
  72f17ab at 4792 = phase 0 of the next state; the following acks come 3 clocks later and the run ends a state
  later. The 18 LINE crossings did not change any run's count here.
- With a host read every 37 clocks the bus is saturated and nothing differs.
Why it matters: host-indirect cycles (and probably HOLD, which I did not test) put bus cycles off the grid. On
such boards (a host CPU polling or streaming through HSTDATA while the GSP draws) PIXBLT timing differs from
84c96fb by whole states. Note that the base itself is already off the guide's grid in this situation, so this is
"different from before", not clearly "less accurate"; but it contradicts "no behaviour change at state level".
How to confirm: <scratch>/r5out/acch_base and acch_mon builds; run
`Vtb_accuracy +CASES=<scratch>/r5out/cases.txt +ONLY=1096 +HOSTPER=207` in each.

## 4. Sub-state interrupt claim (0c7bed8, a740d23)

What I ran (ACK_DELAY=1, accurate mode, 72f17ab vs 84c96fb, tb_accuracy interrupt variants, INT1 pulled for
64 clocks):
- FILL/PIXBLT variants (1,364 runs each): INTAT 40, 80, 160, 400, 1000 (multiples of 8): 0 differ. INTAT 43: 0,
  85: 26, 166: 34, 404: 13, 1007: 0 differ. So the shape of the original result holds: state-aligned edges
  identical, some mid-state edges differ. Small correction: not every mid-state point differs (43 and 1007 don't).
- What differs is stronger than "which opportunity catches it": in every differing run I looked at, one version
  takes the interrupt and the other never does (A3, the handler's counter, is 1 vs 0; memory hash differs; the
  measured time differs, e.g. 312 vs 768 clocks). With a pulse shorter than the checkpoint spacing, the 2-clock
  shift decides whether any checkpoint falls inside the pulse.
- Single-pixel instructions (I generated LINE/PIXT/DRAV interrupt variants, 252 runs, with a copy of cases.py
  whose filter is ('LINE','PIXT','DRAV'): <scratch>/r5out/cases_line.py): INTAT 40, 45, 61, 85, 87, 121,
  166, 203, 259, 331, 404, 517, 1000, 1003, 1600, 1605: 0 differ. In the bench's runs LINE pixel writes are
  held by pacing, so the 1-clock delay is absorbed. (Not covered: LINE under host traffic or slow memory, where
  sections 2-3 show the write can move.)

Is "the guide defines nothing below a state" a fair reading? Only partly. SPVU001A 1988, section 8.4/8.5 (text
near "Signals input to the local interrupt pins are assumed to be asynchronous..."): the GSP samples LINT1/LINT2
at each high-to-low transition of LCLK1 and X1P/X2P change 1 to 2 states after the pin, depending on the phase.
So the chip samples once per state at a fixed point; two edges inside the same sampling window behave the same.
The model samples every FPGA clock (rtl/io/tms34010_io_regs.sv:295, a plain 2-flop tms34010_sync_bit, both
before and after these commits), which is why internal clock shifts can show at all. The guide also says the pin
"should remain active low until the TMS34010 has recognized the request" and interrupts are level-triggered
(LINT pin description; RETI page). So:
- the bench's 8-state pulse that ends unrecognised is outside the guide's contract; a real board holds the line
  until the handler clears it, and then the change only moves the take-point by at most one checkpoint
  interval (a few states). A real game is very unlikely to notice that.
- but the stated reason is not quite right: the guide does define sub-state behaviour (once-per-state sampling at
  LCLK1). Suggestion (pre-existing gap, not introduced here): in accurate mode sample the synchronised LINT/host
  interrupt inputs once per state at the phase matching LCLK1's fall. That would make interrupt behaviour
  independent of internal clock shuffles like these commits, and future timing work would not have to argue it.
How sure: high on the measurements, medium on the "real game" judgement.

## 5. Other checks on a740d23 / 0c7bed8 (operands, counters, guards)

- CHECKED, CORRECT: operand stability. Every input of the pixel operation in a write step is a register that only
  changes on the step's own ack or earlier (pix_dest_q/drav_dest_q/line_dest_q/pblt_dst_pix_q at the read ack,
  move_data_q, mv_store_data_q, colours, CONTROL/PMASK/PSIZE). A posted I/O write to CONTROL commits 3 clocks
  after it is taken (io_post_d1..d3), long before the next instruction reaches a write step.
- CHECKED, CORRECT: pix_wr_cnt_q. Reset on rst, on any clock without a write step, and on the ack. Every write
  step that can raise a pixel write (PIXT store write branch, PIXT memory-to-memory write, DRAV sub-step 1,
  LINE sub-step 1) leaves its state on the write ack (WRITEBACK / LINE_CKPT_D / LINE_WB_D), so there is no
  back-to-back pixel write in one step that could reuse stale operands. line_skip: no request, no step, counter
  stays 0. When the pacing hold (pace_write_hold, applied downstream at the cache's c_req) covers the first
  clock, fsm_mem_req is still 1 there, so the counter is already 1 when the hold lifts and no clock is added.
- CHECKED, CORRECT: pbw_wr_stage_q. It resets whenever state != CORE_PBLT or sub-step != 2; sub-step always
  goes to 0 on a write ack, so every word restarts at stage 0. pbw_result_q is captured on the first clock of
  sub-step 2, after the read-ack edge that loads pblt_dst_pix_q. Upstream mode never uses pbw_* (pbw_word =
  CYCLE_ACCURATE) and keeps the live pixel path (pixel_wr_data = pixel_ppop_merged when !CYCLE_ACCURATE).
- CHECKED: the pixel-write guard (core.sv ~2560) fires when it should. Mutation in a copy
  (<scratch>/tms34010_sv_review5_mut, -DR5M5: pix_res_q never captured): "PIXWR MISMATCH" and $fatal in
  the timing bench at run 308. A first mutation (pix_dest_raw_q never captured) did NOT fire and changed no
  result at all: in accurate mode the CPU never reads the destination for plane mask/transparency alone, the
  memory controller keeps those bits, so that operand is irrelevant. Not a bug, but it means the guard's data
  comparison of destination bits proves little.
- CHECKED: the register-address guard fires for each of: decode capture removed (-DR5M1, tb_add_rr), mm_mask_q
  used instead of mm_mask_d (-DR5M3, tb_mmtm), ST write ignored for PBX (-DR5M4, tb_array_checkpoint).
  Note: tb_int_reti did not catch R5M4 (no PBX traffic), so the PBX path is only exercised by array
  interrupt benches.
- GAP (low): 0c7bed8 has no guard in the RTL. dropin_measure.md says a temporary check was used and removed.
  The pixel path and the address path keep theirs; the PIXBLT word path should too, for the same reason.
- Pixel matrix (tools/dropin/ppop_matrix.py, 2,598 runs, accurate mode, ACK 1): identical 72f17ab vs 84c96fb,
  no guard fired.
- Measured phases (bench, no host traffic): unheld pixel writes start their step at phase 1 (raise at 2);
  PIXBLT words at phase 1 or 2 (raise at 3 or 4). So on the bench the "third clock" statement holds. With host
  traffic I saw PIXBLT sub-step 2 start at phase 6 (finding B), so "sub-step 2 starts no later than a state's
  third clock" (dropin_measure.md and the RTL comment) is not true in general: it assumes acks on the state grid.
- Not tested: HOLD (hold_req_i) and screen-refresh (SRT) traffic during pixel writes. HOLD will misalign the
  bus like host cycles do, so I expect finding B to apply there too.

## 6. 72f17ab - default switch

- CHECKED, CORRECT: every instantiation in sim/tb of tms34010_system/core/memory_fabric (125 files) now passes
  CLKS_PER_STATE=1, CYCLE_ACCURATE=0 explicitly (124 with the same text, tb_fpga_refresh_ratio with the
  arguments in the other order). The other 33 tb_* files instantiate only sub-blocks. Of the sub-blocks with
  mode parameters (bus_timer, io_regs, refresh) all are only instantiated with the parameter passed down.
- CHECKED, CORRECT: tms34010_pin_system keeps CLKS_PER_STATE=1/CYCLE_ACCURATE=0 as its own defaults and passes
  both explicitly to tms34010_system (pin_system.sv:199-201); the Cyclone V top passes both to pin_system
  (cyclone_v_top.sv:144-146). tb_pin_system/tb_pin_srt use pin_system defaults = upstream, as before. So
  nothing silently changed mode.
- sim/accuracy/tb_accuracy.sv, sim/dropin/tb_host_sys.sv, tools/dropin/mk_b1.sh pass both parameters
  explicitly (unchanged).
- NOTE (pre-existing, low): tb_accuracy's own default is CYCLE_ACCURATE=0 with CLKS_PER_STATE=8, and
  scripts/accuracy.sh only sets CYCLE_ACCURATE, so "accuracy.sh 16 0" runs upstream mode at 8 clocks per
  state, not the CLKS_PER_STATE=1 that the docs call upstream mode. Same for host_sys.sh 0 (tb default CPS=8).
  Worth saying in the docs or passing -GCLKS_PER_STATE=1 for the upstream run.
- NOTE: since the 160-bench regression is all upstream mode, the a740d23/0c7bed8 changes (accurate only) are
  covered only by tb_accuracy, the pixel matrix and the host bench, all at ACK_DELAY=1 with no host/HOLD
  traffic during drawing. That is why findings A and B were not seen.

## 7. Timing constraints (fpga/tms34010_cyclone_v.sdc)

- CHECKED, CORRECT: none of the new registers match an exception pattern. rf_addr_q, pbw_result_q, pbw_keep_q,
  pbw_wr_stage_q, pix_wr_cnt_q, pix_res_q, pix_dest_raw_q, pix_pmask_q, pix_fmask_q, pix_inhibit_q are not
  `decoded*`, `instr_word_q*`, `mm_mask_q*`, `mpy_product_q*`, `state_q.CORE_*`, and are not under u_pc or
  u_regfile. decoded_next, mm_mask_d and st_pbx_next are combinational. So every new path is timed as a
  full single-cycle path (conservative).
- CHECKED, CORRECT: existing exceptions stay valid. Each is a property of its source register (decoded stable
  from DISPATCH, mm_mask_q changing only on ack, the graphics read-only states never writing the register file),
  and none of those registers changed behaviour (mm_mask_q now loads mm_mask_d, which is the same value).
  Moving the read addresses into rf_addr_q only takes paths out of the exceptions; it cannot make a relaxed path
  real. The graphics_read_only_states false path and the CORE_MEMORY / mm_mask_q multicycles now cover fewer
  paths, which is safe.
- NOTE: rf_addr_q's input now includes instr_word_q -> decoder -> decoded_comb (in DECODE_WAIT) and state_d.
  The instr_word_q -> decoded* 2-cycle exception does not cover instr_word_q -> rf_addr_q, so the whole decoder
  plus rf_addr_fn must fit in one clock. That is correctly constrained (not a correctness risk), and the
  the work's Fmax reports include it, but it is a candidate next limit; if anyone later adds rf_addr_q to the
  decode multicycle, that would be WRONG (rf_addr_q is consumed the very next clock in DISPATCH).
- I did not run Quartus (as instructed), so the Fmax figures are not checked.

## 8. Documents (docs/dropin_measure.md, dropin_audit.md, accuracy_evidence.md)

- WRONG/OVERSTATED (dropin_measure.md, B3 second and fourth steps): "the write is raised in the same state, so the
  bus cycle starts in the same state" / "no state changes". True only with fast memory and acks on the state
  grid (findings A and B). The evidence (bench and matrix at ACK_DELAY=1, no host traffic) cannot show it.
- WRONG (dropin_measure.md and the RTL comment above pbw_result_q): "Sub-step 2 starts no later than the third
  clock of a state (bus acknowledges come in a state's last clock)". Host-indirect cycles make acks come mid-state;
  I saw sub-step 2 start at phase 6.
- OVERSTATED (dropin_measure.md, B3 second step): "the guide times interrupts in states ... the mid-state outcome
  was never defined by the guide". The guide defines once-per-state sampling at LCLK1's falling edge with a 1-2
  state recognition delay (section 4 above). Also "with the edge mid-state, all 24 do" - in my points some
  mid-state edges give no difference (INTAT 43, 1007), and the differing runs are "taken vs not taken", not
  just a different opportunity.
- DOES NOT SUPPORT ITS CLAIM (dropin_measure.md, B3 fourth step): "interrupts at 24 state-aligned points identical
  to 0d8379c" is quoted as evidence for the single-pixel change, but the bench's interrupt variants are FILL and
  PIXBLT only (cases.py main(): `c.name.startswith(('FILL', 'PIXBLT'))`), which in accurate mode use the word
  engines, not the single-pixel path. I ran LINE/PIXT/DRAV interrupt variants myself: no difference at 16 points.
  So the conclusion holds on the bench, but the cited evidence did not test it.
- CORRECT: "The new register is deliberately not named decoded*, so the existing decode multicycle exceptions do
  not reach it." (section 7).
- CORRECT: guard descriptions (both guards exist, are Verilator-only, $fatal on difference, and fire on mutation).
- CORRECT: 1,003 cases (1,003 distinct names, 2,254 runs in both cache states).
- CORRECT: pixel matrix 2,598 cases identical (re-run, section 5).
- CORRECT: dropin_audit.md and accuracy_evidence.md default-switch wording matches the RTL (system/core/fabric
  accurate by default, pin wrapper and Cyclone V top upstream).
- NOT CHECKED: Fmax / ALM figures (no Quartus).
- SUGGEST: the CLKS_PER_STATE 4-8 table's lesson (one core clock of slack per state for stores) and finding A are
  the same budget seen from two sides; the docs should state the memory-latency budget for accurate mode
  (how many core clocks the bridge has to answer a CPU cycle without a wait state, per access type) and test it.

## 9. Regression

- `VERILATOR=... REGRESS_JOBS=2 scripts/regress.sh` on the 72f17ab review copy: **160/160 PASS**, no guard message
  in any log. (All 160 run upstream mode, so this mainly re-proves ca5135c there.)

## Files I left (all under <scratch>, nothing in the dropin worktree)

- Review copies: tms34010_sv_review5 (72f17ab + bus logger in two tb files), tms34010_sv_review5_base (84c96fb +
  bus logger + host-traffic option), tms34010_sv_review5_mon (72f17ab + crossing monitor + host traffic),
  tms34010_sv_review5_mut (72f17ab + switchable mutations R5M1-R5M5). All can go when no longer needed.
- Scripts: r5_build.sh, r5_ack_sweep.sh, r5_cmp.py, r5_vwrap.sh. Logs: r5out/.

## Summary, ranked by severity

1. **A - behaviour-changing (high confidence): slower PIXBLT/LINE with slower memory.** 0c7bed8 (2 clocks) and
   a740d23 (1 clock) raise writes later inside the state; the bus timer back-dates the cycle to the state start,
   so the external memory loses those clocks. With ACK_DELAY 8-10, 248-564 of 2,254 timing-bench runs get
   slower by whole states (up to 150 states; RUN 1074 goes from the guide's 30 states to 33). Registers and
   memory unchanged. Invisible at ACK_DELAY=1, which all the evidence uses. Matters for any game-core memory
   bridge answering in ~8-10 core clocks.
2. **B - behaviour-changing (medium relevance): misaligned bus cycles.** With host-indirect reads during drawing,
   write steps can start late in a state and the delayed raise crosses into the next state (802 crossings, 291
   PIXBLT runs with different counts; single-run reproducer +ONLY=1096 +HOSTPER=207: 360 vs 352 clocks). HOLD
   likely the same (not tested). Contradicts "no state-level change"; affects boards that use the host port.
3. **Interrupts (low for games, but the docs reason is off):** state-aligned edges identical (confirmed);
   mid-state edges can decide taken vs not taken with the bench's 8-state pulse. The guide does define
   sub-state behaviour (once-per-state LINT sampling at LCLK1 fall); the model samples every clock, before and
   after. A level-held interrupt only moves by one checkpoint; a game is unlikely to notice. Suggest per-state
   sampling in accurate mode.
4. **Docs (medium):** "same state / no state change" and "sub-step 2 by the third clock" are unproven in general
   and false under A/B; the a740d23 interrupt evidence used FILL/PIXBLT variants that do not exercise the
   single-pixel path (my own LINE/PIXT/DRAV variants show no difference).
5. **Gaps (low):** no RTL guard kept for the PIXBLT word path (0c7bed8); accuracy.sh/host_sys.sh "upstream" runs
   use CLKS_PER_STATE=8, not 1; all 160 regression benches are upstream only.
6. **Correct:** ca5135c is exactly equivalent (function body = old logic, every next-value path right incl.
   reset, decode capture, both mask paths, every PBX writer; guard compiled in all Verilator runs and fires on
   three mutations); a740d23 operand/counter logic sound and its guard fires on mutation; 72f17ab leaves nothing
   silently in the wrong mode; no new register falls under an SDC exception and no exception's proof is broken;
   bench (ACK 1, both modes), pixel matrix, regression 160/160 all reproduce.

**Verdict:** ca5135c and 72f17ab are sound; 0c7bed8 and a740d23 are functionally correct but are NOT
timing-neutral at the state level: they shorten the memory's time budget and change state counts with memory
latency of 8-10 clocks or with host/HOLD traffic, so they should not be called "no behaviour change" until that
is fixed or bounded and tested with an ACK_DELAY sweep.
