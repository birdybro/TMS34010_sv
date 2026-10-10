# REVIEW_2 - independent review of accuracy-dev ee26d33..55d71ab

Authority: SPVU001A (June 1988), page images read where it mattered (13-5, 13-6, 13-11, 13-12, 13-20, 13-32).
Code: my own detached worktree `<scratch>/tms34010_sv_review2` at 55d71ab. Nothing in the dev worktrees was touched.
My scripts and logs: scratchpad `review2/` (xgen.py/xan.py expand long rows, tgen.py/tgen2.py random timing,
gen.py random CA=1 vs CA=0, iogen.py partial I/O writes).

Short version: no functional bug found in the word engines, C6, or 55d71ab. Every random FILL / PIXBLT shape
I tried gives the printed Table 13-6 / 13-9 / 13-12 (short and medium) figure, apart from the documented notes.
The real open points are readings of the guide, where the bench cannot catch a mistake because it uses the
same function as the RTL.

## Findings (most serious first)

### 1. Table 13-12 long rows: there is a consistent reading, and the model is 3 states per row over it (alignment A)
- Guide: Table 13-12 (13-32) and 13.5.2.3/13.5.2.4 (13-34, 13-35).
- The key defines Y ("remaining destination words after the S sets"). The D row uses `YG`. The A row prints `NG`.
  Read `NG` as `YG`, and read S's odd rule ("an even number of sets: S = DX/32 - 1") as "DX an exact multiple
  of 32" (the last full set then plays the part of the remaining segment). With that, the A formula is
  self-consistent: full sets cost 3+2R+2GP each, the last segment costs 2V+YG, plus 3.
- Test: 250 random B,L rows with DX 33..140, all pixel sizes, any source offset, 1-3 rows (`xgen.py`,
  `xan.py`). For every alignment-A row (67 runs) the core gives exactly **that formula + 3 states per row**,
  at every pixel size, DX a multiple of 32 or not. (With the "floor" reading, S = DX/32 and V = Y = 0, the
  multiple-of-32 rows match exactly; rows with a remainder are still +3.) Alignment B rows (leading edge
  aligned, trailing partial; 13.5.2.3 says long A and B time the same) come out +3 or +5 per row: the
  trailing read-modify-write is charged on top.
- So the model charges the last (partial) segment the same 3-state overhead as a full set. The prose
  ("a series of 32-pixel medium cases followed by a short case", and the short case has its 3) supports the
  model; the formula doesn't. It is one more place the guide disagrees with itself, but it is a cleaner and
  more specific statement than the note `expand-long` makes ("NG counts every destination word again ...").
- Long rows with the leading edge not aligned (C, D): the model does not fit the printed D formula under any
  reading I tried. Per-row differences range from -15 to +5 states and depend on G, P, S and the source
  offset. So for C/D long rows the model's timing is the model's own construction, checked against nothing.
- `cases.py` `pblt_expand_cases` uses `sets % 2 == 0` (the literal "even") and then still computes V and Y from
  the full `sets`, so for DX = 64 one set is dropped from the figure entirely. All these cases carry the note,
  so the bench never fails on them; it also never checks them.
- Suggest: rewrite the `expand-long` note with the YG / exact-multiple reading and the "+3 for the last
  segment" difference, and say plainly that C/D long rows are unverified.
- Sure: the +3/row is confirmed by test; which side TI meant is open.

### 2. D >= S / D < S with PBH=1 (C14): the model uses the reverse of the guide's literal rule
- Guide 13.4.2.4 (13-23) defines the cases by address bits: "D>=S: the four LSBs of the destination address are
  greater than the four LSBs of the source address", then explains it as "whether one or two words are
  required from the source array to fully write the first word of the destination array".
- For PBH=0 the model's rule (`pbt_two_src` in tms34010_core.sv ~line 4937, `pblt_two_src` in cases.py:807)
  is the same as the literal rule whenever it matters (they differ only for short rows, where Table 13-9
  prints the same figure for both). Checked by hand.
- For PBH=1 the model asks whether the first word written (the high-address end) needs two source words:
  D<S when (source end bits in its word) < (destination end bits). Applied to the pointers software supplies
  for L,L with PBH=1 (one past the row end, 12-189), the literal rule says D<S when destination LSBs < source
  LSBs - the opposite. The physical reading (the model's) looks more likely, but the guide never says.
- Effect if the literal reading is right: PBH=1 medium and long rows off by 1-2 states per row (Table 13-9
  PBH=1 D<S vs D>=S constants).
- The bench cannot detect this: the expectation uses the same classification function as the RTL. This is
  exactly the "same misreading in both" risk. Only a real chip (or a trusted trace) can settle it.
- Related: note `pblt-short-ds` (PBH=1 short rows that need two source words run 1-2 states long). For PBH=0
  the model absorbs the extra source read in the row constant (2 -> 0); for PBH=1 it has no states left to
  absorb it. That asymmetry is a hint that the PBH=1 short-row decomposition, not the guide, may be off.
- Sure: guide text confirmed; which reading is right is open.

### 3. Expand (B,L / B,XY) long rows can be interrupted inside a destination word; final B10 differs from upstream
- Guide: 13.5.4 (13-40) and 7.2.3: interrupts at a destination word boundary (or row end).
- `pblt_checkpoint_due` (tms34010_core.sv ~line 1387) is true after every word-mode step. For expand, a step
  also ends at a 32-pixel segment end, which can fall inside a destination word. So the interrupt point (and
  the checkpointed B10) can be mid-word.
- Seen in tests: with CYCLE_ACCURATE=1 vs 0, B,L / B,XY rows longer than 32 pixels end with a different B10
  (e.g. 0x00020020 vs 0x0002001b; 19 of 1500 random runs, all expand with DX > 32; the other 2
  differences in that set are the documented overlapping moves). Memory and the other
  compared registers are equal. With an interrupt taken (slow ack, +INTAT=1700) one run ends with a different
  B10 from the same run uninterrupted (segment boundaries move after a resume, since the next read is
  min(rest of row, 32) from the resume point).
- B10 is a reserved register, so this is not architectural, and resume is correct in every run. But the
  claim "registers identical to upstream in every run" does not hold for long expand rows, and interrupt
  points differ from the guide's description.
- Sure: confirmed by test. Severity low.

### 4. `fill_rem_q` / `pblt_rem_q`: the comment's reason is wrong for the W=3 path (safe for another reason)
- tms34010_core.sv ~line 602 (`fill_rem_q`) and ~line 1026 (`pblt_rem_q`): "CORE_FILL is entered at least a
  clock after fill_x_q / fill_dx_q change". Not true after W=3 preclipping: `CORE_FILL_SETUP_WIN` writes
  `fill_dx_q` and goes straight to `CORE_FILL`; `CORE_PBLT_WIN_APPLY` writes `pblt_dx_q` and goes straight to
  `CORE_PBLT`. In that first clock the registered remainder is the unclipped DX.
- It is harmless today only because the first access is held by the setup states (`pace_write_hold`,
  `pace_fill_hold`, at least 9 states for a W=3 FILL XY / PIXBLT), and CLKS_PER_STATE >= 8 is enforced.
  If the first request were ever let out in that clock, FILL would write a too-long first step (outside the
  window) and `fill_row_end` (x + step == dx) could be missed, so the row would never end.
- Suggest: fix the comment, or register dx one clock earlier on that path. Sure: confirmed by reading.

### 5. 55d71ab: posted I/O write merge has one clock of margin
- tms34010_core.sv ~lines 3755-3810. A partial-field I/O write merges into the read view
  (`io_rdata_words_q`). That view is now captured the clock after the request (`io_rd_late_q`). If the write is
  accepted in the first clock of its request (normal in accurate mode), the merge at the end of that clock+1
  uses an older view, and it is redone at clock+2 only if `io_is_io_q` is still 1. `io_is_io_q` is updated on
  any `fsm_mem_req`, so a non-I/O request in the clock right after the write's acceptance would leave a stale
  merge, committed by `io_post_d3_q`.
- Tested: partial-field writes (FS 1, 4, 5, 8, 12 at bit offsets 0..10 of PMASK, 0-8 NOPs before, 4 different
  following instructions), CA=1 ack 1, CA=1 ack 37 and CA=0: all read back correct and identical. A trace shows
  the next request comes two clocks after the acceptance (MEMORY -> state 7 -> FETCH), so the margin is
  exactly one clock.
- Plausible only, not reproduced. Worth a comment or an assertion so a future FSM shortcut doesn't break it.
- Side note: the fabric's `cpu_request_io_rdata_q` (driven onto `cycle_io_rdata_o`) is sampled through the
  core's registered address, which is frozen for two clocks after any accepted write; it only feeds the
  external cycle-bus view, not the core.

### 6. Expand colours are plane-masked before processing (pre-existing upstream behaviour, both modes)
- `pbx_src` (~line 1084) and upstream's `pblt_src_eff` AND COLOR0/COLOR1 with ~PMASK before PPOP. 7.6 (7-13)
  says register sources are not masked ("Source pixels that originate from registers are not affected by the
  plane mask") but its list of such instructions doesn't name PIXBLT B. Only matters for arithmetic PPOPs
  (carries from masked bits). Not a regression; noted because the word engine copies it.

## Checked and found correct

- Transcriptions: Table 13-5, 13-6, 13-7, 13-8, 13-9 (every cell, page image), 13-10, 13-11, 13-12 (as
  printed), 13-13, Table 13-1 MOVE rows and Table 13-2 (page images) match cases.py.
- Alignment classes: Figure 13-5 / 13-9 and the 13-15 example (C = leading edge partial, trailing aligned).
- Expand "medium" = source row <= 32 pixels with N > 1 (13.5.2.3), as the bench uses; A,C and B,D equal.
- Table 13-9 misprint claims (`pblt-misprint`): confirmed plausible. With (2+G)N and 4+(2+G)N, every long
  entry equals its medium entry at N=2 minus 2 (PBH=0) or minus 1 (PBH=1), in all 16 cells; with the printed
  2G and 2+(4+G)N it breaks. The core gives the corrected figure exactly (60 + 45 random noted cases).
- `short-d-adjust`: -4 per row for a one-word D row would make a read-modify-write row faster than a plain
  aligned write; -2 is the only physical reading.
- Doc per-row tables (FILL and PIXBLT) are the same as the RTL (`fill_row_states`, `pblt_row_states`).
- Random timing against the printed tables (new binaries, 55d71ab): FILL L and PIXBLT L,L 400 shapes
  (all pixel sizes, offsets, 1-4 rows, PBH/PBV, G 2..8 with T/PMASK): all match or noted; PIXBLT B,L dx<=32
  300 shapes: all match or `short-d-adjust`; XY forms 369 shapes (FILL XY, L,XY, XY,L, XY,XY, B,XY; W=0 with
  all four corners, W=3 fits/start/dimension/both with alignment changed by the clip): all match or noted.
  The noted `pblt-misprint` cases equal the corrected formula exactly.
- Setup: Table 13-5, 13-8 (including +3/+10/+6/+14 and corner +1/+2/+4 added together, 13-18 example 26+1),
  13-11 (+3/+11/+6/+15 for B,XY) in the pace logic.
- Functional, CA=1 vs CA=0 (upstream engines), 1500 + 300 + 600 + 500 random cases (all forms, all pixel
  sizes, PPOP incl. arithmetic, T, PMASK, W=0/1/2/3, PBH/PBV, overlapping source/destination): identical
  memory and registers except the documented overlap cases (2) and B10 on long expand rows (finding 3).
- Slow ack (ACK_DELAY 37, CA=1): identical to ack 1 in all 1500 random runs.
- Interrupt resume: 400 random interrupt variants, +INTAT 60/411/997 (ack 1) and 1700 (ack 37), 52-319
  interrupts taken mid-instruction: identical to the uninterrupted run except finding 3's B10.
- Plane mask / transparency order (7.5, 7.6, Figure 7-5): destination (and memory source) read through the
  mask, PPOP, transparency on the masked result, masked bits kept. FILL COLOR1 not masked. Same in both modes.
- C6: field sequencer keep/rmw paths are gated so CA=0 is unchanged (`fsm_mem_keep`/`fsm_mem_rmw` only set
  under CYCLE_ACCURATE; sequencer keep = 0 and rmw = 0 then). The icache passes keep combinationally.
- LINE W=1 draws nothing: 12-101 ("calculates points but no pixels are actually drawn") and 7.10.1 ("all pixel
  writes are inhibited"). C10 timing reading of Table 12-10 is reasonable (W=1 total is 5 per pixel either way).
- 1988 re-base spot checks: MPYS 5+FS1/2; MPYU +1 with Rs negative; EMU 8,11; JRcc long and JAcc 3,6 / 4,7;
  MMFM 3+4n+(2) / 3+6n+(4); MMTM 2+4n+(2) / 2+10n+(8) vs 10(n+1). All as the bench has them.
- 55d71ab with CA=0: `io_rd_addr`, `io_is_io`, the snapshot condition and `io_rdata_words_q` reduce to the old
  logic (d1/d2 are always 0).
- Full accuracy bench rerun at 55d71ab: 873 match / 129 noted / 0 unexplained (cache hit), same as STATUS.

## Coverage gaps (what the bench does not test)

- The bench prints and compares only A0-A3, B0, B2, B7, B10, ST and a memory checksum. B1, B3, B8, B9, B11-B14
  (pitches and reserved registers after a FILL/PIXBLT, W=1 results apart from B2/B7) are never compared.
- D>=S / D<S classification is computed by the same function in bench and RTL (finding 2).
- Long expand rows: no printed figure is checked (all noted), and C/D long rows match nothing (finding 1).
- Only CLKS_PER_STATE = 8. No refresh, HOLD, host or video cycles during a word FILL/PIXBLT (the new
  `field_rmw_q` path in the sequencer's HOLD restart is only covered by the unit tbs).
- No partial-field I/O writes in the bench (I added some; they pass).
- Interrupt timing (latency, resume overhead) is not compared with anything; the guide gives only "20 states"
  worst case recognition.
- FILL with DPTCH not a multiple of 16 (1-pixel-wide fills, alignment varying per row) is not tested.
