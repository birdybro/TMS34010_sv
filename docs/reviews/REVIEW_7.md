# REVIEW_7: TMS34010_sv dropin-dev, d5ab06b..d67fc17 (6 commits)

Independent review. Worktree reviewed: <scratch>/tms34010_sv_review7 (detached at d67fc17).
Evidence: 1988 TI TMS34010 User's Guide (UG), 1986 first edition for cross-checks. Project type: other
(standalone SystemVerilog CPU core); judged against the repo's own style.

What I ran:
- scripts/regress.sh at d67fc17 (6 jobs, third_party linked read-only from the dropin worktree): 162/162 PASS.
- scripts/accuracy_sweep.sh 84c96fb "1 9" (all host, HOLD, refresh and the new screen runs): IDENTICAL,
  44 compares, 2254 runs each, no run failed (so no Verilator guard fired).
- Mutation runs on tb_lint_state, tb_two_gsp_sync and the iocases cases (details below).
- Exhaustive model of the new PIXBLT spans2 check.

## Findings (most important first)

### 1. The audit's "slow, not wrong" verdict for tb_addk_subk has the wrong reason (CONFIRMED, low, docs only)

- What: docs/dropin_audit.md:39 says tb_addk_subk fails in accurate mode at x16/x64 because the program is not
  finished ("last instruction not reached"), and passes at x128/x256.
- Why it is wrong: the program ends long before the check. In accurate mode (CLKS_PER_STATE 8) the last word
  (PC 0x1F0) executes at about clock 460. The bench has no halt loop. Its memory model has 64 words and aliases
  (sim_memory_model "bounded backing-store alias"), so the core runs into zeros and then re-runs the program
  every 0x400 bits. The check at 300 x N clocks lands somewhere in that loop.
- Evidence: my trace (<scratch>/r7out/b_addk_pc/run.log). At clock ~4800 (x16) the PC is 0x1570 = word 23 of the
  program: B2 has been loaded by MOVI but ADDK 16 has not run, which is exactly the reported failure (B2 = 0x100).
  At clock ~19200 (x64) the PC is 0x55B0 = word 27: A5 = FFFFFFF0 from MOVI, ADDK 32 not yet run (the reported
  "A5 = -16"). x128 and x256 land in the zero area, so they pass.
- Does it matter: the conclusion (not a core bug) still holds; the explanation does not. "Slow" also suggests
  accurate mode is 64x slower than upstream on this program, which is false (about 460 clocks vs under 300).
- How to confirm: <scratch>/r7out/m_addk_pc.sv (accurate mode, PC trace).

### 2. Two-GSP bench: it does not cover short horizontal blanking, and the model cannot do the guide's example (CONFIRMED, medium for the claim, pre-existing RTL)

- What: tb_two_gsp_sync tests only HEBLNK1 = 6 and 20 (sim/tb/tb_two_gsp_sync.sv:99-100). Table 9-1 gives
  HEBLNK2 = HEBLNK1 - 3, which goes below zero when HEBLNK1 < 3. The guide's own worked example (9.9.1) is that
  case: HSBLNK1 = HTOTAL1-4, HEBLNK1 = 1.
- Why it fails: rtl/video/tms34010_video.sv:222 computes `hblank = (hcount <= heblnk) || (hcount > hsblnk)`, a
  window compare. The UG (p. 9-6, "The internal HBLNK signal is driven active low after HCOUNT=HSBLNK; it is driven
  inactive high after HCOUNT=HEBLNK") describes set/reset on equality. With a wrapped HEBLNK2 (HEBLNK2 > HSBLNK2)
  the window compare blanks GSP #2's whole line. This happens with offset 3 (Table 9-1, wrapped: HTOTAL1-1) and
  with offset 4 (the example: HTOTAL1-2). Lines 222-223 also do the same for HSYNC and VBLANK.
- Evidence: <scratch>/r7out/m_gsp_short.sv adds a run with the guide's example values (HTOTAL1 64, HSBLNK1 60,
  HEBLNK1 1, HEBLNK2 wrapped to 63): BLANK differs in 5672 of 6240 clocks; GSP #2's HBLANK never goes inactive
  (trace in <scratch>/r7out/b_gsp_s2/run.log). The VBLANK skew also falls outside horizontal blanking there.
- Second point: the bench header and docs/dropin_audit.md:107-114 say the internal VBLANK flags "legitimately"
  differ for 3 clocks. The UG VEBLNK page (6-49) says that in external sync (DXV=0, HSD=0) vertical blanking ends at
  "VCOUNT = VEBLNK and the leading edge of the external horizontal sync pulse is detected", i.e. at detection,
  not when HCOUNT2 is cleared 3 clocks later. So the 3-clock skew is this model's, not the chip's. It is harmless
  only while HEBLNK1 >= 3 hides it inside horizontal blanking.
- Does it matter: only for a game that runs two GSPs (Exterminator) with horizontal blanking ending within 3
  VCLKs of the line start. Unlikely, but the docs (dropin_audit.md:90, game_survey.md:137) now say external sync
  is "checked"; that is true only for HEBLNK1 >= 3.
- The offset-3 claim itself: confirmed. Table 9-1 and "HCOUNT2 is cleared three full VCLK periods later" both say
  3; the worked example (HSBLNK2 = HTOTAL1-8, HEBLNK2 = HTOTAL1-2) implies 4. The 1986 edition has the same text.
- How to confirm: run <scratch>/r7out/m_gsp_short.sv; check Exterminator's HEBLNK values if two-GSP matters.

### 3. tb_lint_state accepts 16 clocks; a one-clock-early sample point passes (CONFIRMED, low)

- What: sim/tb/tb_lint_state.sv:146 fails only when `d > 2 * CPS` (16). The design and docs say 8 to 15.
- Evidence: mutation S1 = CPS/2 + 1 (samples the pin one clock before LCLK1 falls) passes the bench as written.
  With the bound changed to `2 * CPS - 1` the original RTL still passes and the mutation fails (12 checks).
  Mutation S1 = CPS/2 + 3 fails (12 checks); CYCLE_ACCURATE=0 fails (184 checks, as the commit says).
- Does it matter: test strength only. Fix: tighten the bound to 15.

### 4. The late keep-mask path into the I/O snapshot is untested (CONFIRMED, low)

- What: rtl/core/tms34010_core.sv:4045 (`io_request_keep_q <= mem_late_keep` on late_taken_q).
- Evidence: deleting that line changes nothing in the 216 iocases cases at ACK 1, nor with +HOSTPER 37/211 or
  +HOLDPER 97x20 / 389x3. The Verilator guard at core.sv:5139-5144 compares io_request_wdata_q only, not
  io_request_keep_q. So if the late keep ever differed from the take-clock keep, nothing would notice.
- Does it matter: the line is right by reading (same rule as the data line above it). It is just not exercised.
  Adding io_request_keep_q to the LATE IO guard is a one-line fix.

### 5. tb_system_fabric in accurate mode also fails an IAQ check the audit row does not list (CONFIRMED, very low, docs)

- What: docs/dropin_audit.md:44 lists only the screen-refresh address for tb_system_fabric.
- Evidence: <scratch>/r7out/m_sysfab_acc.sv (CLKS_PER_STATE 8, CYCLE_ACCURATE 1, waits x64) prints both
  "screen payload expected=0120 ... actual=011f" and "IAQ did not distinguish opcode/immediate words". The IAQ one
  is the same class the audit settles for tb_pixel_srt/tb_pin_system (UG 11-24), so only the row is incomplete.
- The screen part of the row: confirmed. The bench programs HTOTAL 7, VTOTAL 3; the first refresh is 0120, then
  011F every time (ORG=1, so DUDATE decrements). My log matches the explanation.

## Checked and correct

- LINT timing (829daa1). The two per-state stages sample the pin as it was at phase CPS/2 (2 clocks of input
  synchroniser allowed) and change X1P/X2P in the clock where phase = CPS/2. Measured delay 8..15 clocks, one change
  clock per state, both pins, both edges (bench, and my tightened bench). Matches UG 8.3 ("samples ... at each
  high-to-low transition of LCLK1 ... one to two states"). The phase counter is reset-aligned like the core's
  g_pace and the fabric's phase counters, and the project's local_bus has LCLK1 high for Q1-Q2, so "fall at
  CPS/2" is consistent with the repo. Upstream mode and CPS=1 use g_lint_clk, which is exactly the old wiring.
  The only consumer of the pin is intpend_value, so nothing bypasses the stages.
- Missed or doubled interrupts: a pulse shorter than a state can be missed; the UG says the pin must be held until
  serviced, so that is chip-like. X1P/X2P are read-only levels, so an INTPEND write cannot clear them, and IE/INTENB
  writes do not interact with the stages. An INTAT sweep (FILL INT case, INTAT 100-220) gives results that change
  exactly once every 8 clocks, at the same phase, before and after the change; no double changes.
- PIXBLT spans2 (0d0cff4): exactly equivalent. Proof: start = (A - a) + s with A - a a multiple of 16, so the
  word compare is floor(s/16) != floor(e/16); s is in [-63, 15] and e in [-64, 77], inside 8-bit signed range, and
  their word indices differ by less than 16, so comparing bits [7:4] is exact. Python check over 786,432 cases
  (6 high-address patterns incl. 0, 0x7FFFFFF0, 0xFFFFFFF0; a = 0..15; both directions; source and step bits 0..63
  independently): 0 mismatches. The Verilator guard runs every clock out of reset; it never fired in the regression
  or the 44-compare sweep. (The 57.59/56.32 MHz figures need Quartus; not checked.)
- I/O keep (4c9fa61): keep = 1 means "keep the old bit", the same sense as field_keep_i in the field sequencer and
  pixel_wr_keep (plane mask 1 = protected, UG 7.6). Keep and data are both right-justified, and the register is
  shifted by addr[3:0] the same way io_field_rdata is. Non-pixel writes (MOVE, MMTM, etc.) get fsm_mem_keep = 0
  (default at core.sv:4248; only PIXT/DRAV/LINE/FILL/PIXBLT set it, all under CYCLE_ACCURATE). With
  CYCLE_ACCURATE=0 keep is always 0 and mem_late never fires, so io_request_kept = io_request_wdata_q: upstream
  unchanged. The read view is taken from io_access_addr_q (registered), and posted writes freeze the snapshot, so
  late_taken_q cannot overwrite a newer request. iocases: accurate equals upstream in all 216 cases; removing the
  keep merge breaks 46, removing the shift breaks 16. Real chip: the UG says plane mask and transparency apply to
  every pixel access of PIXT/DRAV/LINE/FILL/PIXBLT and says nothing special about I/O addresses; the reference
  here is upstream mode's merge, which is a reasonable reading but not direct evidence.
- Screen mode (8b0cd5a): the default and refresh case files are byte-identical to d5ab06b's. The register values
  match the UG (DPYCTL bit 12 SRE, 13 DXV, 14 NIL, DUDATE bit 2; ENV=0 does not gate screen refresh in the RTL),
  and a screen-mode run really has screen-refresh cycles (10 kind-2 cycles in case 5, none in default mode).
- Audit claims (b433a03): case 120 of the MAME graphics replay is transparent_zero (PIXT, transparency) as stated.
  tb_system_fabric: HTOTAL 7 / VTOTAL 3 and the 0120-then-011F sequence confirmed. tb_addk_subk: see finding 1.
- tb_two_gsp_sync detects broken sync: offset 4 fails (192 and 384 clocks), HSYNC not connected fails, VSYNC not
  connected fails.
- Regression 162/162; sweep IDENTICAL against 84c96fb at ACK 1 and 9 with host, HOLD, refresh and screen.

## Ranked summary

1. tb_addk_subk audit reason wrong (the program loops through aliased memory; not slowness). Docs only.
2. Two-GSP: short horizontal blanking (the guide's own example) not covered and not possible with the RTL's
   window compares; the VBLANK skew is the model's, not the chip's. Claim scope, pre-existing RTL.
3. tb_lint_state bound 16 should be 15; a one-clock-early sample mutation passes.
4. Late keep into the I/O snapshot untested; guard checks data only.
5. tb_system_fabric audit row misses its IAQ failure.

Verdict: the RTL changes are correct. LINT sampling matches UG 8.3 and leaves upstream mode alone; the spans2
rewrite is exactly equivalent; the I/O keep merge is right and only active in accurate mode. The open points are
in tests and docs: tighten tb_lint_state, add the keep to the late guard, narrow the two-GSP claim (or fix the
blanking compares if a two-GSP game needs short blanking), and correct the tb_addk_subk explanation.

## Files left for inspection

- <scratch>/tms34010_sv_review7 (worktree at d67fc17; third_party/TMS34010_Info is a symlink to the dropin worktree's
  submodule; work/regression and work/sweep have the logs)
- <scratch>/r7out: spans2.py (exhaustive check), mrun.sh / abuild.sh (build helpers), m_*.sv (mutated or adapted
  benches), mut_*/rtl (mutated RTL copies), b_*/ and a_*/ (build outputs and run logs), io_*.log/regs (iocases),
  ifp*_*.txt (INTAT sweeps), regress.log, sweep.log, base/ (d5ab06b rtl), ug88.txt / ug86.txt (guide text)
