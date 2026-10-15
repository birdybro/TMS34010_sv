# Accuracy evidence

This page says what the `accuracy-dev` work claims, how each claim was tested, and how to repeat the tests.
The design itself is in `docs/cycle_accuracy.md`. Original core: Kevin Coleman (birdybro/TMS34010_sv, upstream
commit 94a258e). Accuracy work: Chris Watson.

## What is claimed, and what is not

1. **Upstream mode behaves as upstream.** `CYCLE_ACCURATE=0, CLKS_PER_STATE=1` give upstream's
   behaviour (these were the defaults up to the NARC FINAL; on the drop-in branch accurate mode is the default and
   upstream mode is kept as the test reference, `PLAN_DROPIN.md`), except for five behaviour fixes that apply in both modes (section 3). Upstream's README lists
   "exact instruction-cycle parity" and "the optional instruction cache" as explicit non-goals, so nothing
   here says upstream's timing is wrong. The timing work is an opt-in mode for a different goal.
2. **With `CYCLE_ACCURATE=1, CLKS_PER_STATE>=8`, every instruction takes the number of machine states printed
   in TI's TMS34010 User's Guide**, wherever the guide is consistent with itself. Where it is not, the
   difference is listed with the page and the reason (`docs/cycle_accuracy.md`, "Where the guide disagrees with
   itself").
3. **Not claimed:** that the core matches a real chip measured on a bench. No real TMS34010 was timed. The
   reference is TI's book.

## 1. The reference

- TMS34010 User's Guide, June 1988 revision, SPVU001A: `third_party/TMS34010_Info/docs/ti-official/
  1988_TI_TMS34010_Users_Guide.pdf`, md5 `31c7716145d20336a797cdcd4f54d58f`. It comes from upstream's own
  submodule (birdybro/TMS34010_Info). Page numbers below are its pages.
- The January 1986 first edition gives different figures for a few instructions (MPYS/MPYU, EMU, JRcc long,
  MMFM, some Table 13-1/13-2 entries, the REFCNT direction). The 1988 figures are used everywhere.
- Every expected figure in the bench is a figure printed in the guide, with its page. None is computed from a
  rule of ours. Table 13-4 (memory-to-memory moves) and the FILL/PIXBLT tables were read from the page
  images, not only from the OCR text.

## 2. Upstream mode is unchanged

| Check | Result |
|---|---|
| Upstream's regression (`scripts/regress.sh`: upstream's 159 testbenches plus one added, `tb_refresh_prescale`) | 160 / 160 pass |
| Registers A0-A3, B0, B2, B7, B10, ST and a checksum of memory after every bench run, accurate mode against upstream mode | identical in 2006 of 2006 runs |
| Verilator lint (`scripts/lint.sh`) | clean |
| `tms34010_system` ports | unchanged (two new parameters only) |

Seven of upstream's testbenches were changed, all visible in the patch:
`tb_btst` and `tb_jrcc_unsigned` expected the old BTST K encoding and condition code 0001, and now expect the
guide's (section 3); `tb_line_abort` now expects no pixels for LINE with W=1 (section 3);
`tb_field_sequencer`, `tb_bus_arbiter_rmw` and `tb_fpga_refresh_ratio` tie off the two new memory-controller
inputs (plane-mask keep and read-modify-write); `tb_illegal_opcode` lost one line that made Verilator 5.032 drop
a probe write (the core was already correct; review 3 confirmed it).

The second row means the timing mode changes *when* things happen, not *what* happens. The 2006 runs include
FILL and PIXBLT interrupted in the middle and resumed.

## 3. The five behaviour fixes (both modes)

These are the only places where the work says upstream does something the chip does not. Each was found
by a real program going wrong (Williams' NARC; the Hard Drivin' core's own copy of the CPU for the last one),
traced instruction by instruction against MAME or read, and checked against the guide.

| Fix | The guide | Independent check | How it showed up |
|---|---|---|---|
| JRcc/JAcc condition code `0001` is **P** (N=0 and Z=0); upstream tested the carry ("LO") | Table 12-8 (12-31): P = 0001. LO is an alternate name for C, which is 1000 (upstream already has C = 1000 correctly) | MAME maps opcode C1xx to `j_P` (`!N_FLAG() && !Z_FLAG()`) | NARC's line routine (CMP / JRP) took the wrong path: a runaway line through the whole address space |
| BTST K,Rd: the opcode holds the **one's complement** of K | 12-46: "the assembler 1s-complements the value of K before inserting it into the opcode" | MAME: `bit = 31 - PARAM_K(op)` | NARC's DMA wait loop (`BTST Fh,A7`) tested bit 16 and left early |
| No interrupt is taken while an opcode fetch is outstanding | 8.5 (8-6): an interrupt is accepted "at the end of the current instruction"; nothing allows abandoning a fetch that has started | - | NARC hung on hardware: the fetch's acknowledge retired the PC push, so RETI popped a stale PC (JTAG trace) |
| LINE with W=1 draws **no** pixels; upstream drew the ones outside the window | 12-101: "The instruction calculates points but no pixels are actually drawn"; 7.10.1 (7-26): "all pixel writes are inhibited, whether they address locations inside or outside the window" | - | review of the window modes; `tb_line_abort` updated |
| **Negative XY coordinates.** Window checks (FILL, PIXBLT, PIXT, DRAV, LINE) compare X and Y as **signed** 16-bit values; a W=3 clip of an array that starts left of X = 0 starts at the clipped corner's address. Upstream compared unsigned (-5 counted as 65531) and formed the clipped start from the unclipped corner's address, so shapes starting above or left of (0,0) were clipped wrongly, drawn whole under W=2, or not drawn | 4.3 (4-11): "The X and Y components are each treated as 16-bit signed integers ... the clipping window ... is restricted to positive X and Y ... pixels identified by negative X or Y coordinates must always lie outside the window"; CPW 12-56: WSTART and WEND "are also treated as signed" | MAME treats X and Y as signed. The address conversion itself keeps the guide's OR of a zero-extended X (4.3.1, Figure 4-11), as CVXYL shows to software; only the clipped start is formed as a sum, which equals the clipped corner's address | found by comparing with the copy of the core in the Hard Drivin' MiSTer core (its Task 0186 and signed compares for FILL/DRAV/LINE; PIXBLT and PIXT were still unsigned there). Its sign-extend-and-add for every address is not taken: it differs from the guide's conversion when X is negative. `sim/dropin/tb_negxy_sys.sv` (156 cases against the guide's rules, both modes) |

## 4. Timing: how it was measured

- **Bench:** `sim/accuracy/tb_accuracy.sv` runs each case from reset through `tms34010_system`. The memory
  answers every word cycle with no wait states (the guide's tables assume zero-wait memory). The case
  generator is `tools/accuracy/cases.py`, the report is `tools/accuracy/report.py`, and the numbers on this
  page come from `tools/accuracy/evidence.py`.
- **What is timed:** from the clock the instruction's opcode fetch completes to the clock the next opcode
  fetch completes. That is how the guide counts (cache-off = cache-hit + hidden + 3 per instruction word, which
  holds across Section 12). Each case runs twice, and the second pass is timed, so the instruction comes from
  the cache when the cache is on.
- **Both cache states** (cache-hit, CD=0; cache-off, CD=1) and the **hidden states** (the posted write's bus
  time after the next opcode fetch, the "(n)" figures in the guide) are compared.
- **Scope:** 1003 cases, each in both cache states. The instruction forms of Section 12; Tables 13-1, 13-2 and 13-4 (all field alignments); data-dependent figures (taken / not taken, Rd
  odd/even, divide early exits, FS1, stack alignment, window violations, pixel operations); FILL and every
  PIXBLT form over row lengths, alignments, pixel sizes, PBH/PBV, windows, transparency and plane mask.
- **Slower memory and other bus traffic** (drop-in work, from 8b483e8): the timing tables assume zero-wait
  memory, but a game core's memory may answer later, and host, HOLD and refresh cycles put bus cycles off the
  state grid. `scripts/accuracy_sweep.sh <revision>` runs the whole bench against another revision's RTL and
  compares every external bus cycle (kind, address, data, start clock) and every run's result, with the memory
  answering in 1 to 14 clocks, host reads (`+HOSTPER`), bus hold (`+HOLDPER`, `+HOLDLEN`) and DRAM refresh on
  (`cases.py <out> refresh`). It is the check for any change that should not move the bus.

## 5. Timing: results

| | Accurate mode | Upstream mode |
|---|---|---|
| Cache-hit figures equal to the printed figure | **874 / 1003** | 1 / 1003 |
| ... differ where the guide contradicts itself (listed, with page) | 129 | (168) |
| ... differ with no explanation | **0** | 834 |
| Hidden states equal to the printed figure | **422 / 426** (4 listed) | 175 / 426 |
| Cache-off figures equal to the printed figure | **834 / 992** (158 listed, 0 unexplained) | 7 / 992 |

Upstream mode is measured at 8 clocks per state. Upstream has no defined clocks-per-state, so that number
alone would be unfair to it. `evidence.py` therefore tries every ratio from 1 to 32 at three memory speeds:

| Memory acknowledge (clocks) | Best ratio | Cache-hit figures matched at that ratio |
|---|---|---|
| 1 | 11 | 51 / 1003 |
| 8 | 18 | 49 / 1003 |
| 16 | 26 | 48 / 1003 |

At no ratio does upstream match more than about 5% of the printed figures. The reason is relative cost:
upstream's instructions take a near-constant time. For example, at 8 clocks per state:

| Instruction | Guide (1988) | Accurate mode | Upstream mode |
|---|---|---|---|
| ADD A1,A0 (12-36) | 1 | 1 | 3.25 |
| MOVI IL (12-160) | 3 | 3 | 8.5 |
| MPYS, FS1=32 (12-165) | 21 | 21 | 3.375 |
| DIVS Rd even (12-63) | 40 | 40 | 7.5 |
| MODU (12-114) | 35 | 35 | 7.375 |
| TRAP, SP aligned (12-254) | 16 | 16 | 18.375 |

A divide takes about 2.3 ADDs upstream. In the guide it takes 40. The full per-case table is the report
written by `scripts/accuracy.sh 1 1` (`work/accuracy_report_1.md`).

### A second, independent source: MAME

MAME's TMS34010 (src/devices/cpu/tms34010, release 0282) was written independently and counts each
instruction in machine states. Its figures agree with the accurate mode wherever the two guide editions agree:

| Instruction | MAME | Guide 1988 | Accurate mode |
|---|---|---|---|
| ABS, ADD, ADDC, ADDK, AND, ANDN, BTST K, CMP, CPW, GETPC, GETST, LMO, MOVK, NEG, NEGB, NOT, OR, REV, SUB, SUBB, SUBK, XOR | 1 | 1 | 1 |
| MOVI IW / IL | 2 / 3 | 2 / 3 | 2 / 3 |
| EXGPC | 2 | 2 | 2 |
| PUTST | 3 | 3 | 3 |
| DIVS Rd odd / even | 39 / 40 | 39 / 40 | 39 / 40 |
| DIVU | 37 | 37 | 37 |
| MODS / MODU | 40 / 35 | 40 / 35 | 40 / 35 |
| DSJS taken / not taken | 2 / 3 | 2 / 3 | 2 / 3 |
| CALLR / CALLA (SP aligned) | 3 / 4 | 3 / 4 | 3 / 4 |
| RETS / RETI / TRAP (SP aligned) | 7 / 11 / 16 | 7 / 11 / 16 | 7 / 11 / 16 |
| PUSHST / POPST (SP aligned) | 2 / 8 | 2 / 8 | 2 / 8 |
| MPYS, FS1=32 | 20 | 21 (5 + FS1/2) | 21 |
| EMU | 6 | 8 | 8 |

The last two rows are 1986-to-1988 edition changes: MAME has the 1986 figures (MPYS 20, EMU 6).

## 6. Where the guide disagrees with itself

The 129 noted cache-hit differences come from 17 places where printed figures contradict the guide's own
general rules or its other tables, for example a figure that is smaller than the instruction's own fetch time,
or one row of a table that is shuffled against the rest. Each place is listed in `docs/cycle_accuracy.md`
with its page, the printed figure, what the rule gives and why. The model follows the rule; the bench
reports these as "differs (noted)", never as matches. Where the guide gives no figure, or can be read two
ways, the choice made is listed as an assumption (C1-C17), and the open ones are marked (C14-C16 affect
PIXBLT only).

## 7. Independent reviews

Each review was made by a reviewer who had not done the work, told to check against the guide and not to trust
this documentation. The reports are in `docs/reviews/` (REVIEW_ee26d33.md, REVIEW_2.md, REVIEW_3.md; for the
drop-in work REVIEW_4.md to REVIEW_7.md).

| Review | Main findings | Outcome |
|---|---|---|
| 1 (before the FILL/PIXBLT engines) | The bench took some expectations from the model's own rule, so a misreading could pass; wait states were not whole states; CLKS_PER_STATE < 8 unchecked; interrupt entry 30 instead of 28; hidden states not compared; window-check timing missing; DIVS 80000000h case missing | All fixed in 9419547: the bench now uses only printed figures, and the rest were modelled. The bench was moved from the 1986 to the 1988 edition at the same time |
| 2 (after the engines) | Long expand rows: a self-consistent reading of Table 13-12 differs from the text; D>=S / D<S with PBH=1 is ambiguous; an expand row could be interrupted inside a word (B10 differed); two comment and margin points | Interrupt point and margins fixed in 3bc34f5. The two readings are documented as C14/C15 |
| 3 (timing closure, before the final patch) | Nothing that changes behaviour. Both new SDC multicycle exceptions proved from the RTL. Every bench result identical before and after (2254 cases x 3 modes, 2000 random FILL/PIXBLT, interrupt resume). Out-of-spec misaligned FILL/PIXBLT hangs in accurate mode | Documented as C17 |
| 4 (drop-in survey and audit) | An IAQ change misread 11-24; tests to make stronger | IAQ change reverted; tests strengthened (84c96fb) |
| 5 (drop-in timing steps) | Two write-path timing steps took clocks out of the memory's time: slower PIXBLT/LINE with memory answering in 8-10 clocks, and with host traffic a write could move to the next state. The bench could not see it (zero-wait memory, no traffic) | Fixed in 8b483e8 (bus identical to before the steps, cycle by cycle); the sweep above added to the checks |
| 6 (the fix) | No RTL bug; the sweep could pass with nothing run; the late-data path was barely exercised; an old bug (PIXT into an I/O register with T/PMASK) | Sweep fixed (f134086); guards on every late write and take-clock T/PSIZE (236893c); the old bug fixed in 4c9fa61 |
| 7 (LINT per state, short PIXBLT check, I/O keep, two GSPs) | No RTL bug; the short PIXBLT source-word check proved equal to the old one (786k cases); regression and sweep clean. Docs: one bench failure explained for the wrong reason, two-GSP claim too wide (HEBLNK1 < 3 not supported; the VBLANK skew is the model's). Tests: the LINT bound one clock loose; the late keep into the I/O snapshot unchecked | Docs corrected, the Exterminator's own values added to the two-GSP bench, LINT bound tightened, the guard checks the keep too |

## 8. In a real game

NARC (Williams, 1988) uses this core on MiSTer. NARC's own simulation measured when the
high-score screen starts to scroll:

| Core | Frame the scroll starts |
|---|---|
| Upstream | ~336 |
| First accurate test (ddd3d5c, before the word FILL/PIXBLT engines) | ~298 |
| MAME | ~245 |

With the word engines (8b5b680), the scroll start and the box round the top score came within about 10% of
MAME's frame timing. MAME is not cycle-exact either, so this is a sanity check, not a proof. On hardware, NARC
builds t13 to t19 ran with the accurate core; the faults seen there were all traced to NARC's own video
bridge.

## 9. Limits

- The reference is the book, not silicon. The cases where the book contradicts itself are decided by its
  general rules and listed. A logic-analyser capture of a real board would settle them.
- Data-dependent costs are checked against the guide's formulas over many random shapes, but only against
  those formulas.
- `CLKS_PER_STATE` must be at least 8 (48 MHz core clock for a 6 MHz local clock); the core stops simulation
  with an error otherwise.

## 10. Repeat it

```
git checkout accuracy-dev        # RTL identical to the FINAL patch (73f44f4); this commit adds evidence.py
git submodule update --init third_party/TMS34010_Info
scripts/accuracy.sh 1 1         # accurate mode -> work/accuracy_1.log, work/accuracy_report_1.md
cp work/accuracy_1.log work/acc_1.log
for a in 16 1 8; do scripts/accuracy.sh $a 0; cp work/accuracy_0.log work/up_$a.log; done
#   (these upstream-mode runs use the bench's 8 clocks per state, so the bus timing compares with the
#    guide; upstream mode proper is 1 clock per state - same registers and memory, the timing differs)
python3 tools/accuracy/evidence.py work/acc_1.log work/up_16.log work/up_1.log work/up_8.log
scripts/regress.sh              # upstream's regression
scripts/accuracy_sweep.sh 84c96fb   # drop-in: bus cycle by cycle vs a revision, memory latency and traffic
```

Each bench run takes about 30 seconds with Verilator 5.032.
