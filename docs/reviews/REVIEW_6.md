# REVIEW_6 - independent review of 8b483e8 (dropin-dev)

Commit: 8b483e8 "Drop-in B3: write requests back on their own clock, data a clock later" (parent 72f17ab).
Reference for behaviour: 84c96fb. Review copies: <scratch>/tms34010_sv_review6 (8b483e8) and
<scratch>/tms34010_sv_review6_base (84c96fb). Scratch, builds and logs: <scratch>/r6out/.
The dropin worktree was not touched. No Quartus builds. The Sim slot was held by NARC for the whole review,
so I did not run the full 14-latency sweep; I ran single bench passes (about 45 s each) instead.

Short answer: the RTL change is correct as far as I can find. Every bench comparison I made against 84c96fb
is identical, including conditions the commit did not test (HOLD, host writes, slow memory with host traffic,
10 and 16 clocks per state, PIXT into I/O registers). The findings are about the test script and test
coverage, plus two small pre-existing or theoretical points.

## Findings

### 1. The sweep script can say IDENTICAL when nothing ran (CONFIRMED, medium for the evidence, no RTL impact)

- What: `scripts/accuracy_sweep.sh` prints "sweep: IDENTICAL" and exits 0 when the builds or the simulations fail.
- Where: scripts/accuracy_sweep.sh lines 39-40 (`build ... & build ... & wait`) and 28-30 (the two runs in the
  background, then `wait`); tools/accuracy/buscmp.py `main()` (no check that any run was loaded).
- Why: `wait` with no arguments returns 0 whatever the background jobs returned, so `set -e` never sees a failed
  build. If both logs have no RUN lines, buscmp.py loads two empty dicts, the key sets are equal, and it prints
  "runs 0: ... differs 0" and returns 0.
- Evidence: I ran the script in my copy with Verilator missing from PATH:
  `env PATH=<dir without verilator> scripts/accuracy_sweep.sh 84c96fb "1" ""` -> four "runs 0" lines,
  "sweep: IDENTICAL", exit 0. Also `buscmp.py /dev/null /dev/null` returns 0.
- Does it matter: not for this commit. I re-checked the author's logs in work/sweep with buscmp.py: all 17 have
  2,254 runs and are identical, and they were built from the committed core.sv and fabric (same size and mtime
  18:27, unmodified in the worktree). But a later use (for example a reference revision whose RTL does not build
  with today's bench) would pass silently.
- Fix direction: wait for each PID and check its status; make buscmp.py fail when a log has 0 runs or fewer
  runs than the case file. Small extra: an empty third argument (`""`) cannot switch the host runs off, because
  `${3:-...}` treats empty as unset.

### 2. The late-data path is mostly tested only where it makes no difference (CONFIRMED, low)

- What: the late data matters only when the write is taken in the first clock of its write step (then the
  registered value on fsm_mem_wdata is still the previous write's). In the whole bench this happens only for
  LINE. PIXT and DRAV pixel writes, and every late write into I/O space, are always taken a clock or more into
  the step (pacing holds them), when the stale and the late value are already equal.
- Where: consumers of the late value: rtl/memory/tms34010_memory_fabric.sv:241-245 (req_wdata/req_keep) and 211-214;
  rtl/core/tms34010_core.sv:4003-4006 (`if (late_taken_q) io_request_wdata_q <= mem_late_wdata;`).
- Evidence (monitor copy <scratch>/r6out/mon, prints every late take and whether fsm_mem_wdata/keep at the
  take differ from the live values):
  - full bench, ACK 1: 1,456 pixel takes, 15 with stale data, all LINE (runs 890-906 "LINE 0 ... E23", 1066);
    47,008 PIXBLT word takes, 9,406 stale.
  - the same 15 at ACK 1, 9 and 25, with host reads every 37 or 207 clocks.
  - my 216 PIXT-into-I/O-register cases: 432 late takes into I/O, 0 stale.
  - Mutation: deleting the core's `io_request_wdata_q <= mem_late_wdata` line passes the whole bench and the
    216 I/O cases with identical bus logs. (The fabric mutation in the commit message is real: making
    cpu_late_q always 0 gives 463 differing runs, which I reproduced.)
- Why it is still probably fine: I traced the paths by hand (see "Checked" below) and they are right. The
  Verilator guard also checks every late value, stale or not.
- Does it matter: low today. The I/O late update and the PIXT/DRAV first-clock case are code that no test can
  break. If pacing ever lets a PIXT/DRAV write go in the first clock of its step (a pacing change, a new memory
  bridge), nothing has shown that the late data reaches the bus there.
- How to confirm / improve: a directed bench that forces a first-clock take for PIXT, DRAV and a PIXT into an
  I/O register (or a small fabric-level bench driving cpu_field_late_i with different live and late data), and
  a Verilator check in the fabric that the sequencer's field_wdata_q/field_keep_q after a late capture equal
  the late inputs.

### 3. Pre-existing: PIXT with T or PMASK into an I/O register differs between modes (CONFIRMED, low, not from this commit)

- What: in accurate mode, a PIXT store or PIXT *Rs,*Rd into an I/O register with transparency or a plane mask
  writes the unmasked value. Upstream mode merges as expected.
- Evidence: my cases <scratch>/r6out/iocases.txt (generator gen/iocases.py; HTOTAL at C0000030 holding
  5A3C, PMASK 0F0F, psize 8). PIXT A0=ABCD with PMASK reads back 5ACD in accurate mode, 5ACC in upstream mode;
  with T and A0=0, 5A00 vs 5A3C. 8b483e8 and 84c96fb are identical in both modes, so this commit did not cause it.
- Likely why (not traced to the line): in accurate mode the merge is left to the memory controller through the
  keep mask, and the I/O path (fabric and the core's io_field_wdata) ignores the keep mask.
- Does it matter: almost certainly not for a game. Noted so it is not mistaken for a regression later.

### 4. The keep mask given late reads CONTROL.T and PSIZE a clock after the take (PLAUSIBLE, very low)

- What: mem_late_keep at C+1 (and the PIXBLT pbw_keep) is computed from registers loaded at C plus the live
  pixel_transp_en_q and io_psize. 84c96fb used their values at C.
- Where: rtl/core/tms34010_core.sv:1192-1197 (pbw_keep), 2566-2573 (pix_wr_transp, pixel_wr_keep), 5064-5068.
- Scenario: a host-indirect write to CONTROL or PSIZE commits on its own physical-cycle acknowledge
  (rtl/io/tms34010_io_regs.sv:247-262), independent of the CPU. If it lands exactly between the take and the next
  clock, the keep mask differs from 84c96fb. The guard would stop a simulation that hit it.
- Does it matter: a host changing PSIZE or CONTROL during a pixel write is not a sensible program; the result
  would be undefined on the chip too. 72f17ab had the same exposure. Registering those two terms with the rest
  would close it if wanted.

### 5. Stale data still drives the request registers for a clock (CONFIRMED, informational)

- For late writes, fsm_mem_wdata/fsm_mem_keep in the take clock are the previous write's registered values
  (core.sv:4485-4487, 4518-4520, 4862-4864, 4941-4943, 4672-4673). They are stored in cpu_request_wdata_q/keep_q
  and io_request_wdata_q and overwritten a clock later. Nothing reads them in between today (checked), but any
  future consumer of cpu_request_wdata_q that does not go through req_wdata would get the wrong data in C+1.
  A comment at cpu_request_wdata_q saying "valid from C+2; use req_wdata" would prevent that.

## Checked and correct

- "The clock after the take is the first clock anything reads the data" - true:
  - Field sequencer: latches field_wdata_q/field_keep_q only in FIELD_IDLE with field_req_i
    (tms34010_field_sequencer.sv:186-199). A capture needs the fabric idle or a posted request finishing in that
    clock (fabric:146-149); a finishing request is in FIELD_RESPONSE at C, so the sequencer is IDLE at C+1 and
    latches req_wdata/req_keep, which are the late inputs then (cpu_late_q). It uses only the latched copies
    afterwards (HOLD restart included).
  - Fabric I/O path: selected_cpu_req is cpu_request_active_q, which rises at C+1; its data is req_wdata
    (late at C+1, the updated cpu_request_wdata_q after).
  - The update of cpu_request_wdata_q/keep_q at C+1 sits in the "active and not capturing" branch; a second
    capture at C+1 cannot happen (the request just taken cannot be done at C+1).
  - No other reader of cpu_field_wdata/keep or cpu_request_wdata/keep (grep of rtl/).
  - Core I/O write: at C+1 io_write_data_q is loaded from the stale io_request_wdata_q, but it is loaded again at
    C+2 from the late value (io_post_d2_q) with the read view loaded at C+1 (io_rd_late_q), and the commit at C+3
    uses that. Correct. Two posted writes cannot be taken within 3 clocks (I/O cycles last at least two states),
    so the unconditional late overwrite cannot hit an earlier write's snapshot.
- Late registers at C+1 hold the values of the take clock in every path: pbw_* and pix_* registers load in every
  clock of the step, so after any number of held clocks they show the take clock's inputs. pbw_late_q and
  pix_plain_sel_q select the right source; a write step that follows at C+1 only reloads at the end of C+1.
- mem_late is raised only in write branches (DRAV substep 1, LINE substep 1 with !line_skip, PIXT store,
  PIXT memory-to-memory write step, PIXBLT substep 2 with pbw_word). Every user of pixel_wr_data or pbw_result_q
  on fsm_mem_wdata has mem_late. FILL and non-word paths keep live data. All late writes have mem_we_int=1, so
  they are posted and fsm_mem_ack equals the fabric's capture clock; the core (late_taken_q) and the fabric
  (cpu_late_q) agree on the take clock. Pacing gates c_req, not mem_late, but without m_req there is no capture,
  so a raised mem_late without a take does nothing. Icache fills only happen in fetch states.
- The guard's live expressions match 84c96fb's write data and keep (g_pbw_keep is 84c96fb's pbw_keep
  verbatim; pixel_ppop_merged / mv_store_data_q / pixel_keep as before). A wrong late keep makes it fire
  (my mutation: PIXBLT keep forced to 0 -> "LATE WR MISMATCH", $fatal). It cannot see fabric or core-I/O
  mistakes (finding 2).
- Upstream mode: every new term is gated by CYCLE_ACCURATE (mem_late, pbw_wr_step, cpu_late_q, late_taken_q);
  pbw_word is 0 there. Bench identical to 84c96fb at 8 clocks/state and at 1 clock/state with host reads every
  53 clocks; matrix identical.
- Only tms34010_system instantiates the core and the fabric (rtl/), and NARC uses tms34010_system
  (cores/narc/hdl/jtnarc_gsp.sv), so the new port is wired everywhere it is needed. Core-level benches set
  CYCLE_ACCURATE=0.
- Lint (scripts/lint.sh, Verilator 5.032): clean.
- Commit claims:
  - ACK 1-14 and host 211/207/37 identical: author's logs in work/sweep re-checked, all identical. I re-ran ACK
    1, 8, 9, 10 and 25 myself: identical.
  - 72f17ab vs 84c96fb at ACK 9 gives 564 differing runs: reproduced (564 RUN lines, 584 with bus timing
    differences).
  - Fabric mutation gives 463 runs: reproduced.
  - Pixel matrix identical, and both modes give the same registers and memory: reproduced at ACK 1, and at ACK 9
    with host reads.
  - Interrupt variants: I ran LINE/PIXT/DRAV at INTAT 43, 85, 166, 1003 and FILL/PIXBLT at 85 and 404, at ACK 9
    with host reads (not what the author ran): identical.
  - Fmax 52.15 / 52.93 MHz: the reports exist (work/b3e_ca1, work/b3e_s2). "About +1 ns of slack at 50 MHz" is
    0.8 ns for seed 1 and 1.1 ns for seed 2.
- Conditions the commit did not test, all identical to 84c96fb (full bench, 2,254 runs, bus cycle by cycle):
  HOLD pulses (11 clocks every 97) at ACK 1 and ACK 9; host writes every 211 clocks; host reads every 207 at
  ACK 9; 10 and 16 clocks per state with host reads every 131 (ACK 3); ACK 25; 216 PIXT-into-I/O cases at ACK 1,
  ACK 9 and in upstream mode. HOLD and host traffic did change timing against the plain runs (660 and 2,254 runs),
  so they were active. DRAM refresh is on in the bench (CONTROL.RR default; refresh cycles appear in the bus logs).
  Screen refresh was not exercised.

## Ranked summary

1. Sweep script false pass on failed builds/runs (finding 1) - fix the script; evidence for this commit is fine.
2. Late data untested where it matters for PIXT, DRAV and I/O (finding 2) - add a directed test or a fabric check.
3. Pre-existing accurate-mode difference for PIXT with T/PMASK into I/O registers (finding 3) - not from this commit.
4. Late keep reads CONTROL.T/PSIZE one clock late (finding 4) - theoretical.
5. Stale values in the request registers for one clock (finding 5) - comment.

Verdict: the change does what it says. On every bench condition I could think of, the external bus of
8b483e8 is cycle-for-cycle the same as 84c96fb's, so REVIEW_5 findings A and B are fixed. Fix the sweep script
before relying on it again, and add a test for the late path in the cases the bench never reaches.

## Files left for inspection

- <scratch>/tms34010_sv_review6 (worktree at 8b483e8; work/sweep has my failed-build demonstration)
- <scratch>/tms34010_sv_review6_base (worktree at 84c96fb)
- <scratch>/r6out/: tb/tb_accuracy.sv (bench with +HOSTWR, +HOLDPER/+HOLDLEN), build.sh, cmp.sh,
  gen/iocases.py, iocases.txt, sub_*.txt, int_*.txt, matrix.txt, logs/; mutants mut1 (no core I/O late update),
  mut2 (fabric ignores late data), mut3 (wrong late keep); mon (late-take monitor); r72 (72f17ab rtl).
