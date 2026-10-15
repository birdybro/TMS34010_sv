# Independent review: TMS34010_sv accuracy-dev @ ee26d33

Scope: diff 94a258e..ee26d33 (no third_party), `docs/cycle_accuracy.md`, `tools/accuracy/cases.py`,
`sim/accuracy/tb_accuracy.sv`, against the 1988 User's Guide (SPVU001). Every doubtful OCR figure
below was checked on the PDF page image.

My test runs were in a separate detached worktree `<scratch>/tms34010_sv_review` (ee26d33). Nothing in
`tms34010_sv_dev`, `tms34010_sv` or `tms34010_sv_reg` was touched. The extra cases I added are in
`<scratch>/tms34010_sv_review/review/extra_cases.py` and `review/haz_cases.py`. They run with the bench's own
binary: `work/verilator_tb_accuracy/Vtb_accuracy +CASES=work/extra_cases.txt`.

PDF page = guide page 12-N + 270 (for example 12-191 is PDF 461). Table 13-4 is PDF 511.

---

## Findings (most serious first)

### F1. The bench works out many expected values from the author's rule, not from the guide. Some of them differ from the printed guide figures and still show as matches.
- `cases.py:558`: every Table 13-4 cache-off expectation is `hit + hid + 3*words`. It is not
  copied from the table. The guide prints other figures for index 6 (C to C) and index 9 (C to G) in the
  indexed and absolute forms. Index 6 (guide / bench): *Rs(S),*Rd+ 13/16, *Rs(S),*Rd(D) 16/19,
  @S,*Rd+ 16/19, @S,@D 24/27. Index 9: 19/22, 22/25, 22/25, 30/33. The report shows these 8 runs as
  "hit off" matches. They are not in the doc's list of 7 disagreements.
- `cases.py:514`: PIXT and DRAV expectations come from a formula (base + 2 + ppop extra; cache-off =
  hit + hidden + 3). PIXT Rs,*Rd at PSIZE 1-8 (page 12-191, PDF 461) prints cache-off figures of ADD 11,
  SUB 12, SUBS 11 and MIN/MAX 10. The bench expects 10, 11, 12 and 11. These are not reported anywhere.
- DRAV ADD at PSIZE < 16 (12-56, PDF 326): the guide prints 7+(3),13. The bench expects 6+(3),12 and reports a
  match. The doc (line 60) says such figures are "reported as differences". For DRAV that is not true.
- Effect: "325/329 cache-hit, 302/319 cache-off" is partly a check of the model against the author's own
  rule. The bench should hold the printed guide value for every case. A rule-derived expectation should be
  marked as rule-derived, and every place where the two disagree should show in the report.
- Sure: confirmed against the page images and by reading the bench.

### F2. MMFM with SP not aligned is short by 2 states per register. Not covered by the bench.
- Guide 12-95: cache enabled `3 + 8n + (6)`, cache disabled `9 + 8(n+1)`. Table 8-5 (8-7) backs this up
  with the cache-disabled figures: MMFM SP,ALL 72/144 = time − 1 with n = 16 (9+64 = 73, 9+8·17 = 145).
- Core (my run): n=1: 9 states (guide 11); n=4: 27 (guide 35). Cache off: 15 / 33 (guide 25 / 49).
  The model reads each non-aligned register as one 3-word field (6 states). The guide says 8.
- MMTM not aligned (12-97: `2 + 10n + (8)`, `10(n+1)`): the core gives 6 / 36 (guide 12 / 42) with the cache
  on, and 20 / 50 with the cache off (matches). The guide's two MMTM figures don't agree with each other
  (2+10n+8+6 ≠ 10n+10). Table 8-5 (169 = 10·17 − 1) backs the cache-off one. Whatever the model's choice
  is, it is untested and undocumented.
- Code: `tms34010_core.sv:4590,4595` (MMFM 3, MMTM 6, no alignment term).
- Sure: confirmed by test and by two places in the guide.

### F3. Wait states are not whole machine states.
- Guide pin description of LRDY (Section 2, line "internal wait states in increments of one full LCLK1
  cycle") and 11.4.10: LRDY is sampled once per state, and every wait state is one whole local clock.
- `tms34010_bus_timer.sv:72`: `ack_o = active_q && ready && (bus_cnt_q <= 1)`. A late external ack ends
  the cycle in the clock it arrives, part way through a state.
- Test: the full bench with ACK_DELAY=37 (CPS=8) gives fractional instruction times, for example CALL cache-off
  19.25 states, MOVE Rs,*Rd A cache-off 12.25, CALL "last write ends" 25.50. For NARC (slow SDRAM
  bridge) this puts the bus off the state grid. That is exactly the case the hand-over says is modelled
  "as LRDY".
- Fix: a late ack should end the cycle at the next state boundary (round up to whole states).
- Also: 2.x says LRDY is ignored for internal cycles (I/O registers). The model still waits for the external ack on I/O
  cycles, so a slow bridge adds wait states to I/O register accesses. (Plausible from the bench's
  memory model, which acks I/O kinds through the external bus. Not separately tested.)
- Sure: confirmed by test and guide.

### F4. Accuracy needs CLKS_PER_STATE >= 8. Nothing says so and nothing checks it.
- At CPS=7, 23 cases lose cache-hit accuracy (MOVE Rs,*Rd and Rs,*Rd+ all alignments, MOVB Rs,*Rd,
  JRUC short taken, TRAP). At CPS=6, 93 cases fail. At CPS=1, every instruction takes ≥ 7 states.
- `docs/cycle_accuracy.md` ("Same-clock answers") says the core's fixed work fits inside one state, but
  gives no minimum. NARC's 48 MHz / 8 has no margin: one more pipeline clock in decode or fabric
  breaks timing silently.
- Fix: state the minimum, add an elaboration-time `$error` for CPS < 8, and run the bench at more than one CPS.
- Sure: confirmed by test.

### F5. Interrupt entry with SP not aligned takes 30 states. The guide says 28.
- Table 8-4 note 3 (8-6/8-7): the interrupt context switch is 16 states (SP aligned) and 28 states (SP not aligned).
- `tms34010_core.sv:4652`: interrupt entry uses TRAP's CPU states (4 / 6). This gives 16 / 30. TRAP is
  30 (12-230), but interrupt entry is 28. So this is a guide figure that settles part of C5.
- Interrupt recognition (1-2 states, Table 8-4) and the LINE interrupt figure (13.6.4, "20 machine
  states") are not modelled or tested either.
- Sure: guide confirmed. Model value from reading the code (the bench has no interrupt case).

### F6. The bench never checks hidden states, and its "last write ends" column is wrong for multi-instruction cases.
- `report.py` compares only total states. The hidden figure is printed and never compared.
- `tb_accuracy.sv:198`: `t_lastwr` records every data write or read until the end of the loop. So for the
  "M:" cases it includes later instructions' traffic. Examples: CALL aligned shows 18.75 where 3+(3) = 6,
  MMTM 4 shows 51.75 where it should be 20, and MMFM 1 shows 4.75 for a figure of 7+(2).
- Hidden states are checked only indirectly, through the cache-off totals. Where the author has
  overridden a cache-off figure (F1, the 7 listed entries), nothing checks them at all.
- Sure: confirmed.

### F7. The "guide disagrees with itself" entries are systematic, not one-off misprints.
- JRcc long (12-84) and JAcc (12-80): the page figures and the summary Table 12-7 (12-20) agree.
- The same pattern (cache-off counts +3 for the opcode only, or one word fewer than the rule) shows up in:
  Table 13-2 Rs,*Rd(Disp) and Rs,@Address (every alignment), MOVB Rs,@Address B (1+(3),7),
  Table 13-4 columns 6, 7, 8 and 9 for the indexed and absolute forms, and JRcc long / JAcc.
  That is more than 40 printed figures. So "misprint" is weak. More likely this is real behaviour of the chip
  that the 3-per-word rule does not capture. With the cache off the model is off by 3-6 states in all of these.
  (The guide says the cache is usually off only for debugging, so the impact is low.)
- The doc table's "10..18" for MOVE Rs,@Address is wrong. The rule gives 13..21 for @Address (3 words). The core
  gives 13..21 (my run). Rs,@Address has no bench case at all.
- PUSHST, SP not aligned (12-205): 2+(8),13 agrees with itself (2+8+3) and with Table 12-7. The data says the
  write starts in CPU state 1 when the SP is not aligned and in state 2 when it is aligned. Microcode can
  branch on alignment, so "no single write start gives both" is not a contradiction in the guide. A
  write start that depends on alignment would match the guide. Model now: 14, guide 13.
- MOVE @Address,Rd G cache-off 19 (rule 18), CMPXY 1,4 vs 3,6, DRAV ADD 7: these are real one-off
  disagreements. For DRAV, the page's own cache-off figure 13 agrees with 7+(3) (7+3+3), so "misprint"
  is no better supported than the printed value. CMPXY 1,4 confirmed on the page image (PDF 314).
- Table 13-4 column 12 (G to F): the cache-hit figures (5,6,6,7,7,7,9) look like misprints for +2. The cache-off
  figures fit hit+2. The core gives 7+(7),17 and so on, which matches every cache-off figure (my run).
  Worth adding to the doc's list.
- Sure: confirmed against the page images. The judgement about the cause is mine.

### F8. DIVS and MODS: the "result = >80000000" case is not modelled.
- 12-50 / 12-98: 41,44 if the result is >80000000. `tms34010_core.sv:4538-4541` has no such case.
- Test: DIVS A2,A0 with A0:A1 = 0:80000000 and A2 = −1 gives 40 / 43 (guide 41 / 44).
- The overflow and Rs=0 early exits are right (DIVS 7, DIVU 5, MODS 3, MODU 3: all confirmed by my
  runs). For DIVU "(Rs) < 0" the guide's wording is unclear and the model ignores it. I can't settle it.
- Sure: confirmed by test.

### F9. C6 (PIXT/DRAV with transparency or plane mask at PSIZE 16) is settled by the guide, and not in the model's favour.
- 13.3.2 "Selected Graphics Operations": plane masking, transparency and field insertion are done by
  the memory controller (read-modify-write, 2 states per word). The CPU does only the pixel processing.
- So the extra destination read belongs in the hidden write (like PSIZE < 16, (3)). It should not be 2
  visible CPU states, which is what the core does now. Plausible. No bench case.

### F10. Window-checking timings are not modelled.
- PIXT Rs,*Rd.XY (12-194): W=1 6,9; W=2 6,9; W=3 4,7. PIXT *Rs.XY,*Rd.XY (12-203): W=2 8,11; W=3 6,9.
  DRAV (12-56): 5,8 / 3,6 / 5,8. LINE Table 13-14: +5Q, +5 on violation.
- `g_pace` has no window term. For example, W=1 and W=2 PIXT XY would come out at 4. Plausible from the code. Not tested.

### F11. Smaller points
- CYCLE_ACCURATE=0 is not exactly upstream. The JRP, BTST K and "no interrupt during an open fetch" fixes
  (`fetch_open_q`, `CC_P`) apply in both modes. The hand-over says so. The doc's first paragraph says
  defaults behave "exactly as upstream". It should name the fixes.
- REFCNT (pre-existing, not this change): the guide (6-45, 11.x) says RINTVL/ROWADR count up ("ROWADR
  is incremented by 1"). `tms34010_refresh.sv` counts down. The refresh rate is the same, but software that reads
  REFCNT, and the row order, differ.
- Bench page citations are off by one in places (PIXT Rs,*Rd is on 12-191, not 12-190). Cosmetic.
- Figure 5-9 (5-29, PDF 91) is TI's own state-by-state timing diagram of a 5-instruction loop. It
  confirms two of the author's rules independently: the MOVE read occupies the instruction's last two states,
  and the PIXT write starts in its last CPU state with 1 hidden state. Its iteration is 12 states, while the Section
  12 figures add up to 11 (DSJS taken shows 3 states). Worth adding as a case, with that difference noted.

---

## What I checked and found correct

**Guide figures in cases.py (all compared with the page text; doubtful ones with the page image):**
- All 1-state general instructions (ABS ... ZEXT, REV, 45 cases), SETF F=1, BTST Rs, JUMP, EXGPC,
  CVXYL, SEXT, SLA K/Rs, DINT, EINT, PUTST, MOVI/ADDI/SUBI/CMPI IW and IL, ANDI/ORI/XORI, MPYS 20,23,
  MPYU 21,24, DIVS 40/39, DIVU 37, MODS 40, MODU 35.
- JRcc short 2,5 / 1,4; JRcc long 3,6 / 2,5; JAcc 3,6 / 4,7; DSJS 2,5 / 3,6; DSJ/DSJEQ/DSJNE 3,9 / 2,8.
- CALL, CALLA, CALLR, RETS, PUSHST, POPST, RETI and TRAP, aligned and not aligned; MMTM and MMFM aligned.
- Table 13-1 (all 8 rows) and Table 13-2 (all rows) transcribed correctly. Note 1 (+1 for sign extension).
- Table 13-4 entries the bench uses (cache-hit and hidden), on the page image.
- PIXT tables 12-191, 12-194, 12-198, 12-203, and the forms with no write (4,7 and 6,9): the cache-hit figures match the formula.
- FILL: Table 13-5 (FILL L 4), Table 13-6 long-row formulas, G = 2 (Table 13-7), alignment B/C as in
  the 13.3.3 example, +3 cache off.
- LINE: setup 4, (3+P)E, P = 2/4/5/6 (Table 13-15), and the 119-state example (13-35).

**Decomposition rules (doc):**
- Cache-off = hit + hidden + 3 per word holds for all Section 12 general instructions, Table 13-1, and
  Table 13-2 except the rows in F7. The 3 per word is stated in 5.4.7.
- Hidden = 2 × word cycles − 1, and the write starts in the last CPU state. A=1, B/C=2, D/E=3, F=4 and G=5 cycles
  agree with Figure 13-1 and with 6.2's "as many as five cycles" for G. Figure 5-9 confirms it.
- Reads = CPU states + 2 per word read (Table 13-1). Figure 5-9 confirms it.
- Miss penalty 8 + 1 (5.4.7). Tested: 4 NOPs where the next subsegment misses take 13 states with the cache on (my case).

**Instruction cache (5.4.1-5.4.6):** 4 × 8 × 4 organisation, SSA = bits 31-9, subsegment bits 8-6, word
bits 5-4. The LRU stack moves the used segment to the top on a hit, a subsegment miss and a segment miss. A segment miss takes the bottom
entry and clears its 8 P flags. The P flag is set after the fill. Only PC-addressed words use the cache. Writes don't update it. CF
clears to the reset state and bypasses while set. CD bypasses and keeps the contents. IAQ is set on fills. C2-C4 are not settled by
the guide. C3 is a fair reading of "numerical order (0-3)".

**Pacing / posted writes:**
- Read-after-write to the same memory word (16- and 32-bit, alignment G) and an I/O write followed by a read of the same
  register (16-bit, and 32-bit across two registers) all give the correct data. A PSIZE write followed at once
  by PIXT uses the new PSIZE. Checked at CPS 1 and 8, with ACK_DELAY 1 and 37, CA=1, and also CA=0.
- The whole bench with ACK_DELAY=37: no TIMEOUT, and the register/ST results are the same as with ACK_DELAY=1 in
  all 658 runs (no deadlock with a slow ack).
- The I/O commit two clocks later uses the held address and data (`io_access_addr_q` is frozen for the d1 clock). I found no
  hazard. io_regs has no read side effects, so the extra read strobes from cache-hit acks are harmless.
- One-deep queue (6.2: "only one field insertion request can be queued"): the fabric takes the next CPU
  request only when the posted one is done. Correct.
- CYCLE_ACCURATE=0 in the fabric: the capture/ack logic reduces to upstream's (posted_q stays 0). The bus
  timer and the cache are wires.

**Refresh prescaler:** RR=00 every 32 and RR=01 every 64 local clocks (6-9, 6-45). Counting once per
CLKS_PER_STATE clocks matches "local clock period". Its phase counter is aligned with the core's and the fabric's.

## Coverage the bench lacks (could hide errors)
- No interrupts, host-port accesses, HOLD, screen refresh or DRAM refresh (every case sets RR=11), and no
  wait states (ACK_DELAY=1 only, CPS=8 only).
- No cache misses, CD/CF toggling or LRU replacement order. Every measured pass runs from the cache.
- No MMTM/MMFM with SP not aligned, MOVE/MOVB Rs,@Address, MOVB @S,@D, Table 13-4 indices 5, 7, 8, 11 and 12, the
  divide special cases, window modes, PIXT/DRAV with T or PMASK, EMU, or LINE with window/interrupt.
- Hidden states are not compared (F6).
- My extra runs of the missing items (index 5, 7, 8, 11 and 12 cache-hit, divide exits, the miss penalty) passed except as listed
  in F2, F7 and F8.
