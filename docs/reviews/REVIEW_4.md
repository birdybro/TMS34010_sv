# Review 4 - commits 0d8379c..4a1d17a (dropin-dev)

Independent review. Reference: TI TMS34010 User's Guide, 1988 (SPVU001A).
Scratch copy: <scratch>/tms34010_sv_review4 (detached at 4a1d17a). Nothing in
tms34010_sv_dropin was changed.

Written as I go. Findings first, in the order found; summary at the end.

## Item 1 - multiplier operands registered in CORE_DISPATCH (8e9656e)

Checked, and I found nothing wrong. Details:

- CORE_DISPATCH lasts exactly one clock. `state_q <= state_d` every clock
  (tms34010_core.sv:337-343) and every branch of CORE_DISPATCH (4163-4177) sets
  state_d. There is no pacing hold in DISPATCH (pace_hold is only used in
  CORE_FETCH). So CLKS_PER_STATE 1 or 8 does not stretch DISPATCH or EXECUTE;
  EXECUTE also always sets state_d (4230-4258).
- Only two kinds of state enter CORE_EXECUTE: DISPATCH (4175) and the four
  CORE_FETCH_IMM_* states (4190, 4202, 4226). MPYS/MPYU set no needs_imm flag
  (tms34010_decode.sv:879-900), and in any case the immediate states write
  neither the register file nor ST. Interrupts, NMI and host halt are only
  taken in CORE_FETCH (4086-4097); the illegal-opcode trap leaves DISPATCH for
  CORE_INT_PUSH_PC, not EXECUTE; EMU and reset do not pass through EXECUTE with
  a stale MPY. So DISPATCH -> EXECUTE is direct for every MPY.
- Register-file writers (rf_wr_en, 2689-2700): WRITEBACK term; mmfm_pop_wr,
  mv_load_ptr_wr, m2m_src_wr (all CORE_MEMORY, 2268/2288/2607); graphics_wb
  (FILL_WB, PBLT_WB/WB2, FILL/PBLT_WIN_HIT, *_W1_DYDX, ARRAY_CKPT_*, LINE_WB_*,
  LINE_CKPT_*); int_sp_wb (CORE_INT_DONE). None can be true in DISPATCH. The
  regfile module has only this one write port (tms34010_regfile.sv:122).
- ST writers: st_flag_update_en (WRITEBACK, or fill_win_flag_wb whose terms are
  FILL/PBLT_WIN_MISS and FILL_WB/PBLT_WB2), st_write_en (WRITEBACK, INT_DONE,
  array_pbx_complete = FILL_WB/PBLT_WB2). None in DISPATCH. The status-register
  module has only these two ports.
- Read-port index in DISPATCH: decoded is captured at the end of
  CORE_DECODE_WAIT (382-388) so it is valid in DISPATCH. For an MPY, is_fill,
  is_pblt, is_drav, is_line, is_mmtm are all false and no special state is
  active, so rf_rs1 = (decoded.rd_file, decoded.rs_idx) and rf_rs2 =
  (decoded.rd_file, decoded.rd_idx) (2155-2207). These do not depend on the
  state for an MPY, so DISPATCH and EXECUTE select the same registers. The
  regfile reads are combinational (tms34010_regfile.sv:89-118), so no read
  latency differs.
- FS1 (mpy_fs1 from st_value) is also unchanged between DISPATCH and EXECUTE
  for the same reason. The CYCLE_ACCURATE pacing block still reads FS1 and
  rf_rs1_data in EXECUTE (5428-5432); same values, so no mismatch.
- mpy_product_q loads only in `state_q == CORE_EXECUTE && is_mpy` (3007).
  The flags (3992-3995) and writeback (3161-3162) use mpy_product_q only.
- Even Rd second write-back pass (Rd+1) reads mpy_product_q, not the operand
  registers, so the first pass writing Rd does not matter.
- SDC note (not a bug): fpga/tms34010_cyclone_v.sdc:75-82 gives decoded ->
  mpy_product_q two periods. The new mpy_*_op_q registers are not in that set,
  so decoded -> regfile read -> op_q is a normal one-period path, which is
  correct (DISPATCH is one period after the decoded edge). The 32x32 multiply
  itself is now op_q -> product_q, one period; before it was regfile -> product,
  also one period. So the gain is only removing the index mux from the path.
  Confidence: high. Confirmed by reading; the regression run below also passes
  (see Regression).

## Item 2 - IAQ for immediate words (842edee)

### Finding 2.1 (behaviour, medium): IAQ high on extension words is wrong when the cache is off

What: CORE_FETCH_IMM_LO/HI/EXT_LO/EXT_HI now drive fsm_mem_iaq = 1
(tms34010_core.sv:4186, 4199, 4211, 4223).

Why it is wrong: the commit quotes only half of the paragraph on 1988 UG page
11-24. The same paragraph ends: "When the cache is disabled, IAQ is active high
only when the first word of an instruction is fetched; in the case of a
multiple-word instruction, IAQ is inactive while the additional words are
fetched." The sentence quoted ("instruction fetch includes not only reads of
opcodes, but also immediate data...") is about cache subsegment loads: "IAQ is
active high when words are fetched from memory to load the instruction cache...
the block may contain data as well as instruction words (opcodes, immediate
addresses, immediate data...)".

Effect per mode:
- Accurate mode (icache present, tms34010_icache.sv): with the cache enabled,
  extension words reach the bus only in a subsegment fill, and the fill drives
  m_iaq = 1 itself (icache.sv:257), ignoring c_iaq. So the change has no effect
  there. c_iaq passes to the pins only in bypass (icache.sv:122, 237:
  bypass = CD || CF || !ifetch). Bypass with ifetch means CONTROL.CD=1 or
  HSTCTL.CF=1, i.e. the cache disabled. That is exactly the case where 11-24
  says IAQ must be LOW on extension words. So in accurate mode the commit
  changes the only case it reaches, and changes it to the wrong value.
- Upstream mode (no cache model, every word fetched one at a time - the
  cache-disabled bus pattern): the old behaviour (IAQ on the first word only)
  matched the cache-disabled text word for word. The new behaviour gives a bus
  pattern the real chip never makes: single-word fetches with IAQ on extension
  words. One could argue a game with the cache on sees IAQ on all fetched
  words, but on the real chip those are 4-word fills, which upstream mode does
  not make anyway. I think the old behaviour was the defensible one.

What else it touches: IAQ is consumed only as LAD15 in the column address
(tms34010_local_bus.sv:173) and passed through the arbiter (bus_arbiter.sv:305,
forced low for I/O and SRT). Nothing inside the chip changes behaviour, so the
commit's "nothing in the core reads IAQ" is right; the effect is on the
LAD15/IAQ pin only (board logic that decodes IAQ, e.g. a logic analyser or
external cache/debug hardware).

Suggested fix: revert 842edee (and its three testbench edits), or make the
extension-word IAQ = !(CD || CF) in upstream mode only if you want to mimic the
cache-on case; in accurate mode it must be 0 in bypass.

Confidence: high on the guide text (11-24, last paragraph of the IAQ bullet,
read in the text extraction at the "IAQ bit is output on LAD15" bullet; check
the PDF page 11-24). Medium on how much it matters (pin only).

Chapter 2 pin text (LAD0-LAD15, page 2-x): "IAQ is active high during a read
cycle in which the TMS34010 fetches an instruction word from the local memory."
It does not settle the extension-word question; 11-24 does.

### Testbenches changed in 842edee

- tb_pin_system.sv (283-289, 493-501), tb_pixel_srt.sv:278-280,
  tb_system_fabric.sv:263-265 all run CYCLE_ACCURATE=0 (default) and now
  require IAQ high on extension words. They were changed consistently with the
  RTL change and still check that IAQ is carried through the fabric and pins,
  but they now lock in the misreading of 11-24 above. The old assertions
  ("extension word must drive IAQ low") were the guide's cache-disabled
  behaviour. Also, flag names now say the opposite of what they record
  (`immediate_noniaq_seen_q` is set when IAQ is HIGH; `first_immediate_data_seen_q`
  likewise) - cosmetic.
- tb_pin_system now requires immediate_word_count == 0: that is, no program word
  ever has data status. That removes the only check that a data read through
  the PC is distinguished at all.
- No bench tests IAQ in accurate mode with CD=1 or CF=1, which is the only case
  where the change is visible in that mode.

### Finding 2.2 (docs, medium): dropin_audit.md misquotes 11-24

docs/dropin_audit.md, paragraph "IAQ, settled by the guide, and fixed", says
"Both modes drove IAQ low for immediate words the core fetched itself
(upstream mode always; accurate mode with the cache off)" and calls that wrong.
Accurate mode with the cache off is the one case the guide spells out, and the
old behaviour was right there (11-24, last sentence of the IAQ bullet, quoted
in 2.1). The checklist row for chapter 2 ("IAQ settled (11-24) and fixed") and
the table row for tb_pixel_srt/tb_pin_system ("the accurate model was right and
upstream's expectation wrong") repeat it. Confirmed in a fresh pdftotext of
third_party/.../1988_TI_TMS34010_Users_Guide.pdf (line "When the cache is
disabled, IAQ is active high only when the first word of an instruction is
fetched"). Confidence: high.

## Item 3 - system-level host bench (sim/dropin/tb_host_sys.sv)

Ran both modes in the scratch copy. Both print TEST_RESULT: PASS. Numbers:

| | accurate (CA=1, CPS=8, ACK 1) | upstream (CA=0, CPS=1, ACK 16) |
|---|---|---|
| halt latency | 1-24 clocks = 0.12-3.00 states | 1-120 clocks |
| posted write after halt (as the bench measures it) | 9 trials, latest 19 clocks = 2.38 states | none |
| host read busy, running | 2.12-5.75 states | 32-61 clocks |
| host write busy, running | 2.12-6.00 states | 18-62 clocks |
| CF, odd steps before flush | 19 of 40 (old code from cache) | 0 (no cache) |

Checked and correct: vector addresses (NMI FFFFFEE0 trap 8, HI FFFFFEC0
trap 9, Table 8-x around guide line "NMI Nonmaskable 8 FFFFFEE0h"); INTENB HIE
bit 9; HSTCTL bit positions (NMI 8, NMIM 9, INCW 11, INCR 12, LBL 13, CF 14,
HLT 15, INTIN 3, INTOUT 7; 6-32 to 6-37); INTIN set by host / cleared by the
34010, INTOUT set by the 34010 / cleared by the host (6-37); ADDK 2,A0 = 0x1040;
the cache really is not snooped on memory writes (5.4, "contents of cache are
not modified, and the internal control logic does not attempt to detect this")
so the CF test is a fair test of 5.4.5; NMIM=1 saves nothing (8-x, 6-33).

### Finding 3.1 (measurement, medium): the posted-write check sees only half the write

The loop runs with SETF 32 and does `MOVE A0,*A1,0`: a 32-bit store, two word
cycles (0x200000 then 0x200010). The bench watches only the word at 0x200000
(tb_host_sys.sv:209-221). The high word is always 0 (the counter never reaches
65536 in the run), so its write after the halt cannot be seen. I added a probe
in a scratch copy (work/tb_host_sys_probe.sv) that logs every write
acknowledge after CORE_HOST_HALT: the high word lands up to 35 clocks = 4.38
states after the halt (19 trials), not 2.38. So:
- "a write posted by the halted instruction completes within 2.4 states"
  (dropin_audit.md, chapter 10 row) is wrong; it is 4.4 states in this run.
- dropin_audit.md, row 5.5, says "<= 0.38 states": that disagrees with the
  same document's chapter 10 row (2.4) and with the bench (2.38). Stale.
- The bench's "memory must stay still while halted" check (221) also only
  covers the low word.
- The bound "6 states = own 2-state cycle + DRAM refresh + screen refresh" is
  for one word. A 32-bit store is two cycles, and a host-indirect cycle also
  outranks the CPU (Table 11-1, priority 4 vs 5), so the bound as reasoned
  would be at least 8 states plus host cycles. It is not a guide figure:
  Table 10-2's "six machine states" is the worst halt latency (recognition 2 +
  DRAM refresh 2 + screen refresh 2), not a limit on posted writes. Citing
  Table 10-2 for it is a stretch.
Nothing here shows wrong RTL behaviour (4.4 states is plausible for two
posted word writes), only that the measurement and the doc are off.
Confidence: high (probe output). Confirm: run work/probe.sh 1 in
<scratch>/tms34010_sv_review4.

### Finding 3.2 (model, low): halt can be faster than the guide's minimum

Accurate mode halts 1 clock (0.12 state) after the host's HSTCTL write is
accepted. Table 10-2 gives halt recognition a minimum of 1 state and maximum 2
("In the best case, the halt latency is only one machine state", 10-19). The
docs say the halt times are "inside 10.3.4": the maximum is, the minimum is
not. The measurement starts at host acceptance, not at the HRDY edge the guide
uses, so part of the difference may be where the clock starts; but the model
has no 1-2 state synchroniser between the HLT bit and the fetch decision.
Probably harmless for games. Confidence: medium.

### Finding 3.3 (test strength, low): the LBL=1 test cannot fail on LBL

Step 10 (tb_host_sys.sv:326-336) writes HSTADRL then HSTADRH with LBL=1 and
word-wide accesses. With LBL=1 the read prefetch starts on the HSTADRL write
(10-21). Here HSTADRH already holds 0x0040 from the write pass, so the
prefetch from {old ADRH, new ADRL} and a prefetch on the ADRH write (as with
LBL=0) give the same address. The check passes whether LBL is honoured or
ignored. To make it bite: change HSTADRH before the read pass (e.g. read from
a different 64K page), and with LBL=1 write ADRH first, then ADRL; or check
that an ADRL-only write starts a read. The doc's "done in the host bench:
LBL=1 word accesses" overstates what is tested. Confidence: high (by reading).

### Finding 3.4 (claims, low): "both modes" timing claims

Upstream mode has no machine states (CPS=1, ACK 16), so its "states" columns
are clocks. The audit's "halt and indirect-cycle times inside 10.3.4/10.5"
only means something for accurate mode. Also, nothing in the bench forces the
worst cases the guide describes (RMW in progress, screen refresh plus DRAM
refresh at the same edge): the program has no RMW and the bench never
programs the video timing, so screen-refresh cycles likely never happen. The
max values are "what happened", not worst cases. 10.5's running worst case is
(9+4N)T = 9 states; measured max 6.0 states, so "inside" holds, but weakly.

Other points on the bench (no action needed):
- Step 11 leaves NMIM=1 with NMI=0, which 6-33 lists as "Undefined"; the bench
  then writes HLT only, so it does not matter.
- The NMIM=1 handler's RETI pops garbage; the bench halts straight after the
  check, so the run ends safely.

## Item 5 - docs (dropin_measure.md, game_survey.md, dropin_audit.md)

### Finding 5.1 (docs, low): stale or inconsistent statements

- dropin_audit.md row 5.5: "posted write finish <= 0.38 states after a halt";
  chapter 10 row: "within 2.4 states"; the bench gives 2.38 for the low word
  and my probe 4.38 for the whole 32-bit store (Finding 3.1).
- game_survey.md 0.3 item 2: "Still to add: LBL=1 byte order, CF, INTOUT/HINT,
  NMIM=1 through the system" - the audit (and commit fa6662b) say these are
  done. One of the two is stale. (LBL is in fact not discriminated, 3.3.)
- dropin_audit.md says the pixel matrix is 2,352 cases in three places; the
  tool now writes 2,598 (2,352 + 246 misaligned-source cases from 4a1d17a).
  game_survey.md has the 246. Not wrong, just not updated.
- dropin_measure.md "The product register is loaded every clock, so Quartus
  has to time every one of those index sources": before 8e9656e mpy_product_q
  was already enable-gated (`state_q == CORE_EXECUTE && is_mpy`,
  tms34010_core.sv:3007). The conclusion is still right (static timing times
  the data path whatever the enable), but the reason given is not.
- dropin_measure.md "MPYS/MPYU spend many states (the guide's 20/21)": matches
  the guide's instruction summary (MPYS 20,23; MPYU 21,24). Fine.
- dropin_measure.md fmax figures are consistent with the slacks given
  (1/(20+0.449) ns = 48.9 MHz; 1/(20+1.231) = 47.1 MHz). I did not run Quartus.
- dropin_audit.md chapter 10 row: "halt and indirect-cycle times inside
  10.3.4/10.5" - see 3.2 (min halt below the guide's 1-state minimum) and 3.4
  (upstream mode has no states; worst cases not driven).
- dropin_audit.md, IAQ paragraph and chapter 2 row - see 2.2.

The survey facts (which games use what) come from MAME runs I did not repeat;
I only checked the documents agree with each other.

## Item 4 - pixel-processing matrix (tools/dropin/ppop_matrix.py)

Re-ran it in the scratch copy: 2,598 cases each mode (ACK 1 accurate, ACK 16
upstream), no timeouts, every RUN line's registers and MEM hash identical.
So the reported equality is reproduced.

What is compared: A0-A3, B0, B2, B7, B10, ST and data_sum()
(sim/accuracy/tb_accuracy.sv:230-241): an FNV hash of the address and value of
every non-zero word outside the code area 0x100000-0x1FFFFF (and outside the
stack area only when no_stack). Unwritten words read 0, so "not written" and
"written 0" hash the same, which is correct. Destinations (0x200000 up) and
sources are inside the hashed area. That covers the memory that matters and
the registers these instructions change (B0/B2 final addresses, A2 for DRAV,
A0/A1 for PIXT). Good.

### Finding 4.1 (test strength, medium): each case runs the instruction twice, which blinds the XOR-type cells

tools/accuracy/cases.py Case.program (lines ~318-343): "MOVK 2, A12 ... LOOP:
... setup ... T: <test> ... E: DSJ A12, LOOP". The memory patterns are written
once ("; pre"), the register setup is redone every pass, and the instruction
under test runs twice on the same pixels. For PPOP 5 (S XNOR D), 6 (NOT D)
and 10 (S XOR D) a second pass undoes the first: (D xor X) xor X = D for ANY
X, so a wrong source, wrong colour, wrong pixel position or wrong plane-mask
handling that is the same on both passes leaves no trace in memory.

Measured on my run: in 315 of the 360 cases with PPOP 05/06/0A, the MEM hash
equals that of the matching PPOP 09 (D, a no-op) case. Those 315 cases check
registers only. (The 45 that differ are where transparency makes the two
passes unequal.) Everything else (Replace, AND, OR, MAX, MIN, arithmetic) is
idempotent or cumulative, so it is still checked, but the result is that of
two passes, not one.

Fix: run the test once in the matrix (A12 = 1, or refresh the patterns in the
loop), or compare after the first pass. Confidence: high (measured).

### Finding 4.2 (argument, low-medium): "equality carries upstream's proof to the accurate model" is weaker than stated

- The Boolean/arithmetic function itself is one shared function
  (ppop_apply, tms34010_core.sv:147) in both modes, so equality cannot catch an
  error in it; only upstream's independent model can, and it can.
- tb_graphics_ppop_matrix proves upstream mode correct on ITS cases (core
  level, its own geometry: fixed XY/linear addresses, four-pixel binary
  sources, its own PMASK/transparency patterns). The new matrix uses other
  geometry (one pixel into a word, past two word boundaries, 2 rows, 3 source
  patterns). Upstream mode being right on the new inputs is an inference, not
  a proof. It is a fair inference for the shared per-pixel code; less so for
  the word engines, which differ between modes (accurate mode writes whole
  words, 13.3.2), where equality is real evidence that the two engines agree,
  not that either is right.
- The 246 misaligned-source cases (4a1d17a) have no independent reference at
  all; upstream's matrix has no misaligned source. Equality there only shows
  the two engines agree.
- Shared-bug risk is therefore in: ppop_apply; anything both modes share in
  pixel addressing (XY-to-linear, the PIXT/DRAV per-pixel path); and the
  hash/bench itself (4.1). The C6 path (plane mask and transparency in the
  fabric) is genuinely independent of upstream's, which is what the matrix was
  built to check, and for that it is good evidence (outside the 4.1 cells).
- So "equality proves the accurate model matches upstream mode" is true for
  these inputs (bar 4.1). "...which upstream's bench proves against an
  independent model" holds for the per-pixel function, not for every input in
  this matrix.

## Runs (scratch copies, outputs under <scratch>/tms34010_sv_review4/work)

- Regression at 4a1d17a: `regress.sh: 160/160 PASS` (2 jobs).
- Timing bench (`scripts/accuracy.sh 1 1` and `16 0`) at 0d8379c (worktree
  <scratch>/tms34010_sv_review4_base) and at 4a1d17a: all 2,254 RUN lines
  are identical in both modes (registers, memory hash, state counts, hidden
  states), cache-on and cache-off runs included. This backs the "no behaviour
  change" claims for 8e9656e and shows 842edee changes nothing the bench sees.
  (The bench cannot see IAQ on the pins, which is where 2.1 shows.)
- Host bench both modes: PASS (numbers in item 3). Probe variant:
  work/tb_host_sys_probe.sv, work/probe.sh, output work/probe1.out.
- Pixel matrix both modes: 2,598 cases, identical (item 4). Script work/mx.sh,
  logs work/mx_1.log, work/mx_0.log.

## Summary

Findings by severity (behaviour first):

1. **2.1 (behaviour, medium) - IAQ on extension words (842edee) is wrong when
   the cache is off.** 1988 UG 11-24, same paragraph the commit quotes: "When
   the cache is disabled, IAQ is active high only when the first word of an
   instruction is fetched; ... IAQ is inactive while the additional words are
   fetched." In accurate mode the change only reaches the pins in cache bypass
   (CD=1 or CF=1), exactly the case the guide says must be low; with the cache
   on, fills already drive IAQ high. In upstream mode (word-at-a-time fetches)
   the old behaviour matched the guide's cache-off text. Pin-only (LAD15); no
   internal effect. Recommend reverting 842edee and its three testbench edits.
2. **2.2 (docs, medium)** - dropin_audit.md presents the IAQ change as "settled
   by the guide" and says the cache-off behaviour was wrong; it misquotes 11-24
   by leaving out the cache-disabled sentence.
3. **4.1 (test strength, medium)** - the pixel matrix runs each instruction
   twice, so PPOP 5/6/10 (XNOR, NOT D, XOR) undo themselves: 315 of 360 such
   cases end with the same memory as the no-op PPOP. Those cases check
   registers only.
4. **3.1 (measurement, medium)** - the host bench's posted-write-after-halt
   check watches only the low word of a 32-bit store; the high word lands up to
   4.38 states after the halt (probe), not 2.38. Docs give 0.38 in one place
   and 2.4 in another. The 6-state bound is not a guide figure (Table 10-2's 6
   is halt latency) and ignores the second word and host-indirect cycles.
5. **4.2 (argument, low-medium)** - "equality carries upstream's independent
   proof to the accurate model" holds for the shared per-pixel function, not
   for every input in the matrix; the 246 misaligned-source cases have no
   independent reference at all.
6. **3.2 (model, low)** - halt reached 0.12 state after the host write; Table
   10-2 minimum is 1 state (no 1-2 state synchroniser modelled). Docs say
   "inside 10.3.4".
7. **3.3 (test strength, low)** - the LBL=1 step passes whether LBL is honoured
   or not (HSTADRH already holds the right page).
8. **3.4, 5.1 (docs, low)** - "both modes" timing claims are only meaningful in
   accurate mode; worst cases are not driven; stale/inconsistent figures
   (2,352 vs 2,598; game_survey "still to add" list; "loaded every clock").

Checked and found correct: **8e9656e (registered multiplier operands)**.
CORE_DISPATCH is always exactly one clock and an MPY always goes straight to
CORE_EXECUTE; no register-file or ST writer can fire in DISPATCH (every term
checked); the read-port indices for an MPY do not depend on the state; the
product register loads only in EXECUTE; same in both modes and for
CLKS_PER_STATE 1 and 8. Timing bench identical to 0d8379c in both modes; 160/160.
The SDC still makes sense for the new registers.

Verdict: the multiplier change is sound and can stay; the IAQ change should be
reverted (or limited to the cache-on case), and the host-bench and matrix
evidence is weaker than the docs say, but shows no wrong RTL behaviour.
