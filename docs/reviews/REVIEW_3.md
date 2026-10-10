# REVIEW_3: commits 3bc34f5..bda0104 (timing closure)

Independent review of 9ecd008, 8b5b680, b5f1e4c, 3dd4233, 1538f59, bda0104.
Worktrees used: <scratch>/tms34010_sv_review3 (bda0104), <scratch>/tms34010_sv_review3_base (3bc34f5).
Status: complete.

## Findings

Nothing in 3bc34f5..bda0104 changes behaviour or is unsafe in hardware, as far as I can prove
and test. The two new SDC multicycle exceptions are correct. Details of what was checked are
below the findings.

1. Not from these commits, low: with CYCLE_ACCURATE=1 a FILL or PIXBLT whose linear destination
   is not pixel-aligned hangs the CPU. Example: PSIZE 8, DADDR = word + 4 bits, DX >= 2. The
   first step writes 1 pixel (room = (16-4)>>3 = 1), the next address has nibble 12, room =
   (16-12)>>3 = 0, so the step is 0, the row never ends and no checkpoint is due: the engine
   writes 0 bits forever (core.sv:602-650 fill_word_px/fill_step_px, the same for pbw_room).
   Confirmed by test: 120 random misaligned FILL L / PIXBLT L,L / B,L cases, 76 of 240 runs time
   out, identically on 3bc34f5 and bda0104; with CYCLE_ACCURATE=0 none time out. The guide says
   linear pixel addresses must be pixel-aligned (1988 UG, PIXT section "Linear addresses must be
   pixel aligned"; OFFSET "should contain a pixel-aligned value"), so this is out-of-spec input,
   but a hang on the cabinet is worse than wrong pixels. Fix idea (later, not for this patch):
   never let the step be 0 (fall back to 1 pixel). Sure: confirmed by test.
2. Note, no defect: the registered step sizes are safe only because of two invariants the RTL
   does not check locally: (a) every full-color word step ends on a word boundary or a row end,
   so a checkpoint (7 clocks) always follows a write ack; (b) pace_write_hold keeps the first
   request of an instruction back for at least 4 states (CLKS_PER_STATE >= 8, setup >= 4).
   (a) holds for pixel-aligned addresses only (see 1). Anyone changing the checkpoint chain or
   the setup pacing later must keep both. The comments at core.sv:630-633 and 1094-1096 say so
   in short.
3. Note for NARC: the new exceptions only act if the game core's SDC carries them with paths
   that match its hierarchy (`*|u_core|u_pc|*`, `*|u_core|mpy_product_q*`). If they are not
   carried over, timing is only pessimistic, never unsafe.

## Checked and found correct

### Priority 1: the two new SDC multicycle exceptions (fpga/tms34010_cyclone_v.sdc:64-82)

Proved from the RTL. Both are safe.

- `decoded` has one writer (tms34010_core.sv:376-384): reset clears it, otherwise it loads only
  when state_q == CORE_DECODE_WAIT. CORE_DECODE_WAIT always goes to CORE_DISPATCH (core.sv
  CORE_DECODE_WAIT arm, no later override of state_d after the case). So if `decoded` changes at
  edge k, the state in the clock ending at edge k+1 is always CORE_DISPATCH. Every other state is
  reached at edge k+1 or later and captures at k+2 or later. The whole proof reduces to: in
  CORE_DISPATCH neither destination loads.
- PC: u_pc (tms34010_pc.sv) holds one register, pc_q; pc_d = load_value if load_en, else
  pc_q + 16 if advance_en, else pc_q. pc_load_en is 1 only in CORE_WRITEBACK, in CORE_RESET (with
  ack; value mem_rdata_eff, a registered read, address RESET_VECTOR_ADDR) and in CORE_INT_DONE
  (value popped_pc_q). pc_advance_en is 1 only in CORE_FETCH and the four CORE_FETCH_IMM_* states,
  on ack. None of these is CORE_DISPATCH, so pc_d = pc_q at edge k+1. Earliest WRITEBACK capture
  is k+3 (DISPATCH, EXECUTE, WRITEBACK); earliest FETCH_IMM_LO capture k+2; FETCH, INT_DONE and
  RESET cannot follow DISPATCH directly (DISPATCH -> INT_PUSH_PC / FETCH_IMM_LO / EXECUTE only).
  Covers JRcc/JAcc/DSJ*/CALL*/RETS/RETI/TRAP (all loads in WRITEBACK), interrupt entry and the
  illegal-opcode trap (DISPATCH -> INT_PUSH_PC -> ... -> INT_DONE), cache refill (only changes
  ack timing in fetch states), host halt / EMU halt (no PC write), CYCLE_ACCURATE 0 and 1 (same
  FSM; pacing only holds states longer).
- Reset: rst clears `decoded` and sets pc_q in the same edge. A PC load one clock later needs
  CORE_RESET with an ack, whose value and address do not depend on `decoded`. The reset is held
  for more than one clock by the reset conditioner, so `decoded` is constant 0 then anyway.
- mpy_product_q (core.sv:2984-2992) loads only when state_q == CORE_EXECUTE && is_mpy. EXECUTE
  is entered no sooner than edge k+1 (from DISPATCH), so it captures at k+2 or later.
- Patterns: `*|u_core|u_pc|*` - u_pc contains only pc_q (pc_d is combinational). `decoded*` and
  `mpy_product_q*` match no other register names in u_core (grep). No physical-synthesis
  retiming/duplication settings in fpga/tms34010_cyclone_v.qsf, so the names keep their meaning.
- Hold: `-setup -end 2` with `-hold -end 1` is the standard pair (hold check stays at the launch
  edge). Same form as the upstream decoded -> regfile exception, whose reasoning (record fixed
  from DISPATCH, EXECUTE before any use) is the same argument.
- Caveat, not a defect: the argument (like upstream's) relies on the destination's enable/mux
  select being a function of state only in DISPATCH; that is ordinary multicycle practice.
  For NARC: these exceptions only take effect if the game core's SDC carries them with the
  right instance path; if not, timing is just pessimistic, never unsafe.

### Priority 2: registered values used a clock early (9ecd008, 8b5b680, 3dd4233)

Proved by reading the RTL for pixel-aligned addresses (what the guide requires); confirmed by A/B
simulation against 3bc34f5 (see "Tests run").

Lag of each register:
- fill_word_px_q / pbw_room_q: on a step's write ack they load the room of the address the
  engine moves to (fill_next_nib / pbw_next_nib match the fill_addr_q / pblt_dst_addr_q updates
  exactly: row end -> row base + pitch, else +/- step bits, done -> next address). Otherwise they
  follow the address one clock late. Late only after a non-ack address load: CORE_FILL_SETUP,
  CORE_FILL_SETUP_WIN (W=3 clip), EXECUTE/ARRAY_RESUME1 (resume), CORE_PBLT_SETUP, WIN_APPLY.
- fill_rem_q / pblt_rem_q: unchanged scheme from 3bc34f5.
- fill_step_px_q / pbw_step_px_q: one more clock on top. So after a write ack at edge a the
  step is stale during the clock starting at a and right from a+1; after a non-ack address load
  at edge s it is right from s+2.

Where the step is used (fsm_mem_size, write data/keep masks, fill_row_end, fill_next_addr,
checkpoint_due, pbw_src_ready/pbw_miss/src_end, substep advance) and why it is never stale there:
- After every full-color write ack the FSM leaves CORE_FILL / CORE_PBLT: the step runs to the
  word boundary or the row end, so fill_checkpoint_due / pblt_checkpoint_due or done is always
  true (pixel-aligned addresses), giving 7 checkpoint clocks (ARRAY_CKPT_B0..B14) or WB.
- Read substep then write substep inside one step: nothing the step depends on changes.
- First step of an instruction (FILL_SETUP, FILL_SETUP_WIN, PBLT_SETUP/SETUP2/WIN_APPLY,
  ARRAY_RESUME4 -> engine): the request is held at the cache by pace_write_hold (c_req mask,
  core.sv ~4851) until cpu_cnt_q + 1 >= wthresh_q = setup states + 1 >= 5 states, i.e. at least
  4 x CLKS_PER_STATE (>= 8, asserted) clocks after the instruction's release, while the FSM
  reaches the engine within about 12 clocks (cpu_cnt_q <= 1). wthresh_q is never below 5
  because fill_setup_q / pblt_setup_q are never below 4 (also when still holding the previous
  instruction's value). In substep 0 of full-color PIXBLT pbw_src_ready needs pbw_reads_q >= 1,
  which is 0 at the first step, so the stale step cannot advance the substep; the first source
  word address (pbw_miss) does not depend on the step in either direction.
- Resume: ARRAY_RESUME1 loads the address/DX, RESUME2..4 follow, so the step is right by
  RESUME3, one clock before CORE_FILL/CORE_PBLT.
- Expand (PBX) segment read: the read itself does not use the step (address pblt_src_addr_q,
  size from pblt_rem_q). The read ack at edge r sets pbx_valid_q; the substep moves to 1/2 at
  r+1, when pbw_step_px_q has already been loaded from the new segment values. pbx_wait_q also
  holds the request for 1-3 states. An expand step that ends mid-word (segment end) clears
  pbx_valid_q, so the next clock issues a segment read, again step-independent.
- Row ends, PBH (room = nib or 16), PBV (row step negative), W=1/2/3: covered by the same
  argument; pbw_next_nib uses pblt_dst_row_step, which already carries PBV.
- FILL W=3 two-clock SETUP_WIN (8b5b680): clock 1 latches WSTART/WEND (read selectors depend
  only on the state, so clock 2 reads the same B5/B6), clock 2 evaluates the clip from
  fill_wstart_q/fill_wend_q. fill_win_eval_q is 1 only in that second clock (cleared by rst,
  cannot be 1 on entry). W=1 / W=2 decisions also move to clock 2 and use the same registered
  corners as fill_array_hit already did. The extra clock is far inside the setup states, so
  the instruction time does not change (bench: identical times).
- Widths (8b5b680): FIELD_SIZE_WIDTH is 6. All callers pass io_psize (6 bits) or step bits
  (<= 16), so the 5 -> 6 bit port change gives the same result for every legal PSIZE.

### Priority 3: CYCLE_ACCURATE=0 unchanged

- fill_step_px = 1 and pbw_step_px = 1 when CYCLE_ACCURATE=0 (pbw_word = CYCLE_ACCURATE), so the
  new registers are unused; fill_win_s/e select the live rf_rs1/rs2 reads; fill_win_eval_q is
  forced 0 and both new conditions are written `!CYCLE_ACCURATE || ...` / `CYCLE_ACCURATE && ...`;
  the fill_win_q change at core.sv:5344 is inside the g_pace generate (CYCLE_ACCURATE only).
- Confirmed by test: bench `16 0` gives identical RUN lines (time, A0-A3, B0, B2, B7, B10, ST,
  memory hash) for 3bc34f5 and bda0104 on all 2254 cases and on 800 random cases.

### Priority 4: test-only commits

- tb_illegal_opcode (1538f59): the author's explanation is right. I ran the 3bc34f5 version
  with a $display in the probe: the probe fires ("CORE_DECODE with 0200 at 695000,
  saw_decode=1") and the main block later reads saw_decode=0 (Verilator 5.032). All other checks
  pass (exactly 1 failure). With the clear removed the test passes. The core does show the
  opcode in CORE_DECODE.
- cases.py ANDI/ANDNI (bda0104): matches the guide (12-43: the assembler stores the 1s
  complement of IL for ANDI; 12-45: ANDNI stores IL as given). Bench-only.
- Cache-miss case (b5f1e4c): bench-only; passes (13 / 16 states).

## Tests run

All A/B: bda0104 against 3bc34f5, same case files, RUN lines compared (time, hidden, A0-A3,
B0, B2, B7, B10, ST, memory hash).

| Bench | Cases | Result |
|---|---|---|
| ACK 1, CA=1 | 2254 standard (bda0104 cases.py) | identical, 0 timeouts |
| ACK 16, CA=0 | 2254 standard | identical |
| ACK 37, CA=1 | 2254 standard | identical |
| ACK 1 / 16 / 37 | 800 random FILL L/XY W0-3, PIXBLT L,L / XY,L / L,XY / XY,XY / B,L / B,XY, PBH/PBV, PSIZE 1-16, PPOP, T, PMASK | identical, 0 timeouts |
| ACK 1, CA=1 | 1200 more random (seed 7) | identical |
| ACK 1, CA=1, interrupts | 500 random INT variants, INTAT 60/130/260/400/650/900 | identical (handler taken in ~77%) |
| ACK 37, CA=1, interrupts | same, INTAT 200/500 | identical |
| ACK 1, CA=1, interrupts | 1364 standard INT variants, INTAT 40/97/150/211/300/450/700/1000 | identical |
| ACK 1, CA=1 | 240 misaligned (finding 1) | identical, 76 timeouts on both |
| tb_illegal_opcode | bda0104 version | PASS |

Generator: <scratch>/review3_builds/randcases.py (uses tools/accuracy/cases.py). Builds and logs in
<scratch>/review3_builds; worktrees <scratch>/tms34010_sv_review3 (bda0104) and
<scratch>/tms34010_sv_review3_base (3bc34f5), both detached and unmodified.
