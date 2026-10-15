# B1: size and speed, measured

Phase B1 of `PLAN_DROPIN.md`: measure before changing anything. The tree is 0d8379c (the NARC FINAL RTL plus docs);
nothing in `rtl/` was changed for this.

## How

- Quartus Prime Lite 17.0.2, Cyclone V 5CSEBA6U23I7 (the MiSTer DE10-nano part), seed 1, "high performance effort".
- Top: `tms34010_system` alone in a wrapper (`b1_top.sv`, made with the project by `tools/dropin/mk_b1.sh`). **Every port is a
  virtual pin, the host interface included**, so nothing is optimised away for lack of a pin, and no I/O timing gets
  in the way.
- `clk` constrained at **50 MHz** (20 ns): the fastest board clock in the survey (T-unit, W-unit, Terminator 2,
  Skimaxx, Rapid Fire, the Hard Drivin' MSP). `vclk` 50 MHz, asynchronous to `clk`.
- Timing exceptions: exactly the core ones from `fpga/tms34010_cyclone_v.sdc` (opcode -> decode, decode ->
  register file / PC / multiplier product, graphics setup false paths, memory state and MMTM mask -> register file).
  Nothing added.
- Two builds: `CYCLE_ACCURATE=0, CLKS_PER_STATE=1` (upstream behaviour) and `CYCLE_ACCURATE=1,
  CLKS_PER_STATE=8` (the accurate model).

A first pair of builds had one hold exception missing from my copy of the SDC (MMTM mask -> register file), which
made the fitter pad routing for hold and gave a meaningless 30 MHz. Those results were discarded; the numbers below
are from the corrected SDC (identical core exceptions to upstream's file).

## Results

| | Upstream mode | Accurate mode |
|---|---|---|
| ALMs | 11,750 (28 %) | 13,921 (33 %) |
| Registers | 5,751 | 6,475 |
| Block memory bits | 0 | 2,048 (the 5.4 instruction cache) |
| DSP blocks | 6 | 6 |
| Fmax, slow 100 C model | 46.55 MHz | 45.66 MHz |
| Worst setup slack at 50 MHz, worst corner (slow -40 C) | -1.621 ns | -1.987 ns |
| Hold | met (+0.142 ns worst) | met (+0.122 ns worst) |

Size by module (ALMs; the number in brackets is the module's own logic, without children):

| Module | Upstream mode | Accurate mode |
|---|---|---|
| `tms34010_core` | 11,062 (7,838) | 13,004 (9,593) |
| `tms34010_regfile` | 1,083 | 1,053 |
| `tms34010_io_regs` (with video, host, refresh) | 1,026 (589) | 1,121 (642) |
| `tms34010_memory_fabric` | 578 | (in the accurate build, with the bus timer) |
| `tms34010_shifter` | 376 | 338 |
| `tms34010_video_subsystem` | 270 | 316 |
| `tms34010_alu` | 213 | 210 |
| `tms34010_decode` | 195 | 201 |
| `tms34010_divider` | 171 | 181 |
| `tms34010_host_if` | 154 | 149 |
| `tms34010_icache` | - | 143 |
| `tms34010_pc` | 114 | 112 |

The graphics engines (FILL, PIXBLT, LINE, PIXT, DRAV and the XY arithmetic) are not separate modules: they are
part of `tms34010_core`'s own 7.8k/9.6k ALMs. B1 therefore cannot say how much a `GRAPHICS_INSTR=0` build would save;
that needs a trial build once the option exists (B2).

## Where the time goes

Grouping the worst 1,000 setup paths by source and destination:

| Paths | Upstream mode | Accurate mode |
|---|---|---|
| MMTM/MMFM register mask (`mm_mask_q`) -> multiplier product (`mpy_product_q`) | 642 | 757 |
| core state (`state_q`, mostly the PIXT/DRAV/LINE window setup states) -> multiplier product | 296 | 191 |
| status register -> multiplier product | 25 | - |
| decoded instruction class -> I/O read data (memory fabric) | 37 | - |
| I/O register -> CPU write data (memory fabric) | - | 52 |

The worst path in both modes (accurate mode shown, 21.3 ns of data path):
`mm_mask_q` -> MMTM/MMFM register index -> register-file read select (fan-out 257) -> `rs1_data` -> the multiplier
operand select -> the DSP multiplier -> adder chain -> `mpy_product_q`.

So the multiplier's operands come straight from the register-file read port, whose read index is chosen
combinationally by whichever instruction or engine owns the port that clock (MMTM's mask scan, the window setup
states). The product register loads only in CORE_EXECUTE, but an enable doesn't remove a path: Quartus has to time every one of those index sources through
the multiplier, though only MPYS/MPYU use the product. The existing exception decode -> `mpy_product_q` (proved in
REVIEW_3) covers the instruction decode only, not the other index sources.

## What this means for B3 (at least 55 MHz)

- Needed: about 3.7 ns off the worst path at 55 MHz (18.18 ns) in accurate mode, about 3.3 ns in upstream mode.
- The obvious change is to give the multiplier registered operands, captured from the read port when an MPY
  dispatches, so the DSP path starts at a register and nothing else's read index reaches it. Whether that can be done
  with every bench result (registers, memory, every state in both modes) unchanged is the B3 question. MPYS/MPYU
  spend many states (the guide's 20/21), so there should be room, but it has to be shown, not assumed.
- The next groups (I/O register -> fabric write data in accurate mode; decoded -> I/O read data in upstream mode) are
  1-2 ns behind and get looked at once the multiplier path is gone.
- An exception (a multicycle from `mm_mask_q`/`state_q` to `mpy_product_q`) would also close it on paper, but it
  needs a proof that the product loaded in those clocks is never used. A registered operand is simpler to trust.

## B3, first step: registered multiplier operands

`tms34010_core.sv` now registers the MPYS/MPYU operands (Rd, and the FS1-extracted Rs field) at the end of
CORE_DISPATCH and multiplies those. An MPY always goes from CORE_DISPATCH straight to CORE_EXECUTE (no immediate),
and nothing writes the register file or ST in CORE_DISPATCH (every writer is qualified to WRITEBACK, MEMORY, INT_DONE
or a graphics write-back state), so the operands are the values the read ports give in CORE_EXECUTE: the product is
the same, in the same clock.

Checked:
- A temporary simulation check (not committed) stopped the simulation if, in any CORE_EXECUTE clock of an MPY, the
  registered operands differed from the read ports. It never fired in: the timing bench in both modes (2,254 runs),
  2,000 random MPY/DIV/MOD cases in both modes, and `tb_mpy`, `tb_mpy_flags`, `tb_mpy_fs1`.
- Timing bench: every line (registers, memory hash, state counts) identical to 0d8379c in both modes.
- The 2,000 random cases against the guide's definitions: all 641 MPYS/MPYU correct in both modes (the only
  differences are MODS N: the core leaves N unaffected as the MODS page's status table says (`status_audit.md`), while my reference model took N from the page's examples; known since the earlier arithmetic checks).
- Upstream regression 160/160; strict lint clean.

| | Upstream mode | Accurate mode |
|---|---|---|
| Fmax before (slow 100 C) | 46.55 MHz | 45.66 MHz |
| Fmax after | **47.1 MHz** | **48.9 MHz** |
| Worst slack at 50 MHz, before / after | -1.621 / -1.231 ns | -1.987 / -0.449 ns |
| ALMs after | 11,813 | 13,965 |

The multiplier no longer appears in the failing paths. What limits each mode now (worst 1,000 setup paths):

| Paths | Upstream mode | Accurate mode |
|---|---|---|
| decoded instruction class -> fabric CPU write data (`cpu_request_wdata_q`) | 744 | - |
| decoded instruction class -> fabric I/O read data | 148 | - |
| LINE address -> fabric write data | 81 | - |
| PSIZE (I/O register 21) -> PIXBLT word engine -> fabric keep mask (`cpu_request_keep_q`) | - | 990 |

The accurate-mode path is about 20 ns of logic: PSIZE -> XY-to-address shift -> add -> shift -> pixel operation ->
compare -> selects -> the word engine's keep mask -> the fabric's request register. Shadowing PSIZE alone would save
about 1 ns; reaching 55 MHz needs that engine split across two clocks (or an exception proved safe because the
inputs are stable for the whole word step). That is the next B3 job, with a fresh review.

## B3, second step: the PIXBLT word engine's write path

*Superseded by the fifth step (REVIEW_5.md finding A): raising the write 2 clocks later took those clocks out of the
memory's time. Kept as the record of what was measured. Corrections (REVIEW_5): "same state, so the bus cycles
are unchanged" held only with memory answering in one clock and bus cycles on the state grid; "sub-step 2 starts
no later than a state's third clock" is false with host cycles (seen at the sixth); and the guide does define
interrupt timing below a state - LINT1/LINT2 are sampled once per state at LCLK1's fall (8.3), which the model did
not do then. Mid-state edges differed as "taken or not taken" within the bench's 8-state pulse, not just at
another opportunity.*

In sub-step 2 (the write) of a word step, `pbw_result` and `pbw_keep` are now registered over two clocks and the
write is presented on the third (accurate mode only; the word engines don't exist in upstream mode). Their inputs
hold through sub-step 2, which starts no later than a state's third clock, so the write is raised in the same state.

Checked: a temporary simulation check compared the registered values with the live ones on every presented write
and never fired; timing bench identical in both modes, every line (states included); pixel matrix 2,598 cases
identical to before; 160/160; lint clean.

**One difference, below the level of states.** Accurate-mode writes are posted, so the core moves on when the
fabric takes the write; presenting it 2 clocks later moves the following steps 2 clocks later inside the state,
including the checkpoint where a PIXBLT can be interrupted. The bench's interrupt mode (INT1 pulled for 8 states at
a chosen clock in every FILL/PIXBLT case) was run at 48 points against 0d8379c: with the interrupt edge on a state
boundary, 0 of 24 points differ; with the edge mid-state, all 24 do (which interrupt opportunity catches it). The
guide times interrupts in states; the model samples INT1 every FPGA clock, before and after this change, so the
mid-state outcome was never defined by the guide. Noted for anyone comparing against NARC's FINAL.

**Result:** the PIXBLT path left the failing list, but Fmax came out 47.6 MHz (was 48.9): the next family,
`decoded.iclass` -> the fabric's request registers (write data, keep mask) and the pacing counters, is now worst
(-1.01 ns), the same family NARC's full build reported. Placement varies by about 0.5 ns between builds, so this
step's own gain can't be read off until that family is dealt with.

## B3, third step: registered register-file read addresses

The worst paths after the PIXBLT step all began at the decoded instruction: `decoded.iclass` -> the read-port index
mux (about 5.5 ns) -> the register file -> ALU -> address -> the fabric's request registers or the pacing counters.
The three read ports' addresses (file and index) depend only on the state, the decoded instruction, the MMTM/MMFM
mask and ST.PBX. The port logic is now a function of those four (`rf_addr_fn`, its body the earlier logic
unchanged), registered from their next values: `state_d`, the decode capture (`decoded_comb` on the clock leaving
DECODE_WAIT), `mm_mask_d` (the mask register's update split into a next value and the register, equivalent) and
the ST write. The registered addresses therefore equal the function of the current values on every clock; a
Verilator-only check in the RTL compares the two on every clock and stops the simulation on any difference. It is
kept in the source, so every bench and regression run re-proves the equivalence. Both modes use it.

Checked: the guard never fired in the timing bench (both modes), the 2,598-case pixel matrix (both modes), the
160-test regression or the host bench (both modes); bench and matrix identical to before, line for line; lint
clean. The new register is deliberately not named `decoded*`, so the existing decode multicycle exceptions do not
reach it.

| | Upstream mode | Accurate mode |
|---|---|---|
| Fmax (slow 100 C), before / after | 47.1 / **50.09 MHz** | 47.6 / **50.25 MHz** |
| Worst slack at 50 MHz, worst corner | +0.035 ns | +0.101 ns |
| ALMs | 11,864 | 14,206 |

Both modes now meet 50 MHz on their own, with almost no margin. Next limits: in upstream mode, LINE's address
register (`line_daddr_q`) -> the fabric's write data; in accurate mode, the I/O registers -> the fabric's write
data and the I/O write register. A full game-core build loses some speed (NARC: about 2 MHz), so a 50 MHz board
still wants several more nanoseconds of margin.

## B3, fourth step: the single-pixel write path (PIXT, DRAV, LINE)

*Superseded by the fifth step (REVIEW_5.md findings A and B): raising the write a clock later took that clock out of
the memory's time, and with bus cycles off the state grid it could move the write into the next state. Kept as the
record of what was measured. Correction (REVIEW_5): the interrupt evidence quoted below (24 state-aligned
points) came from FILL/PIXBLT variants, which don't use the single-pixel path; LINE/PIXT/DRAV variants were run
later (no difference then, and none against 84c96fb after the fifth step).*

Accurate mode's worst path was then PSIZE -> XY conversion -> pixel position -> the pixel operation (add, MAX/MIN
compare) -> transparency -> merge -> the fabric's write data, all in the clock a single-pixel write was raised. In
accurate mode such a write is now raised on the second clock of its write step: the first registers the pixel
operation's result and the merge's operands, and the merged data and keep mask come from those registers. As with
PIXBLT, the write is raised in the same state, so the bus cycle starts in the same state. Upstream mode is unchanged
(it keeps the live path). A Verilator-only guard in the RTL checks on every raised pixel write that the registered
path gives exactly what the live path gives.

Checked: bench and pixel matrix identical in both modes; interrupts at 24 state-aligned points identical to
0d8379c; 160/160 regression and the host bench pass; no guard fired anywhere; lint clean.

| Accurate mode | Before | After |
|---|---|---|
| Fmax (slow 100 C) | 50.25 MHz | **55.41 MHz** |
| Worst slack at 50 MHz (worst corner) | +0.101 ns | **+1.781 ns** |
| ALMs | 14,206 | 13,843 |

**The 55 MHz target is met in accurate mode.** Next limits, for the record: the I/O registers -> register file
(an I/O register read), and the registered read addresses -> PC. Upstream mode stays at 50.09 MHz; it is a test
reference now (PLAN_DROPIN.md, direction), so it gets no timing target of its own.

## B3, fifth step: write requests back on their own clock, data a clock later

REVIEW_5.md showed what the second and fourth steps cost. The bus timer times a CPU cycle from the start of the
state in which the core raised it, and the memory must answer by the last clock of the cycle's second state. A
request raised 1-2 clocks later inside the state leaves the memory 1-2 clocks less: with the memory answering in
8-10 core clocks, 248-564 of the 2,254 bench runs took whole states longer (finding A). And when an earlier cycle
had ended off the state grid (host cycles), the later raise could land in the next state (finding B). The bench
used memory that answers in one clock and no host traffic, so it could not see either.

Now the core raises these writes (PIXBLT word writes, PIXT/DRAV/LINE pixel writes; accurate mode only) on the same
clock as before the second step, with a flag, `mem_late`. Their data and keep mask come from registers loaded in
the write step and are given on `mem_late_wdata`/`mem_late_keep` the clock after the memory fabric takes the
request. That clock is the first in which anything reads a request's data: the field sequencer is idle (a new
request is only taken once the previous one has finished) and takes the field then, and an I/O cycle is presented
from it; both take the late values, and the fabric's request registers and the core's I/O write register are
updated with them. No word of the write has started before that, so the external cycle sees the same data at the
same clock as with the live path. The keep mask's transparency term now comes from the registered result in the
same clock (the earlier version gave it its own clock). A Verilator-only guard keeps the live data and keep mask
of every late write in the clock it is taken and stops the simulation if the late values differ.

Checked, against 84c96fb (the last version before the second step), cycle by cycle on the external bus
(`scripts/accuracy_sweep.sh 84c96fb`: each run's RUN line, every external cycle's kind, address, data and start
clock):

- memory answering in 1 to 14 clocks (ACK_DELAY 1-14), all 2,254 runs: identical;
- host reads of HSTDATA every 211, 207 and 37 clocks (ACK_DELAY 1): identical;
- interrupt variants (INT1 pulled for 8 states) of every FILL/PIXBLT case and every LINE/PIXT/DRAV case at 16
  points, state-aligned and mid-state: identical;
- pixel matrix (2,598 cases) in accurate mode, and the bench and the matrix in upstream mode (1 and 8 clocks per
  state): identical; accurate and upstream mode give the same registers and memory on the matrix;
- the tool does see a difference where there is one: 72f17ab against 84c96fb at ACK_DELAY 9 gives the 564 runs
  REVIEW_5 found;
- mutations: with the fabric ignoring the late data, 463 runs end with different results; with a wrong late keep
  mask the guard stops the simulation.

So at the state level and below, this version's bus is 84c96fb's; only the paths inside the FPGA changed.

| Accurate mode | 72f17ab | This step |
|---|---|---|
| Fmax (slow 100 C), seed 1 / seed 2 | 55.41 / 53.82 MHz | 52.15 / 52.93 MHz |
| ALMs (seed 2) | 13,899 | 13,895 |

72f17ab's 55.41 MHz was partly a good seed: with seed 2 it gives 53.82. Over the two seeds this step costs about
2 MHz, and still leaves about +1 ns of slack at 50 MHz. The worst paths are the same family in both, untouched by this
step: PSIZE -> the PIXBLT source-word check (`pbw_src_ready`, whether the next source word must be read) -> the
sub-step 0 read request -> its acknowledge -> the next state, the register-file write data and the registered read
addresses. That family is the next B3 limit; 55 MHz is not met with margin at either version.

## Could the FPGA run slower, with fewer clocks per state?

A third way to reach 50 MHz boards would be to run the core at, say, 25 MHz with 4 clocks per state: the 34010
would see the same states and timing would be easy. The model requires `CLKS_PER_STATE >= 8`; to see whether that is
a hard limit, the full timing bench was run at 8, 7, 6, 5 and 4 clocks per state (scratch copy with the check
disabled, nothing committed):

| Clocks per state | Cache-hit cases off the guide (of 1,003) | Registers and memory | What goes wrong |
|---|---|---|---|
| 8 | 0 | - | nothing |
| 7 | 19 | identical | MOVE/MOVB stores, TRAP, short JRUC |
| 6 | 94 | identical | one-state instructions (ADD, MOVE Rs,Rd, shifts, AND, ...) take two states |
| 5 | 94 | identical | as at 6 |
| 4 | 120 | identical | as above, plus PIXBLT setup |

The function holds at every ratio; the timing doesn't. Every instruction walks at least six core steps (FETCH,
DECODE, DECODE_WAIT, DISPATCH, EXECUTE, WRITEBACK, one clock each) and the fabric registers the request in another;
a one-state instruction has to fit all of that inside one state. Going below 8 would mean rebuilding that sequence
(merging steps that exist only to meet timing at the higher clock), which touches every instruction. That is a
much larger and riskier change than fixing the one long path, so it is not the way to 50 MHz.

## B3, sixth step: the PIXBLT source-word check (0d0cff4)

The worst path after the fifth step ran from PSIZE through the step's source start and end addresses (a 32-bit add)
into a 28-bit word compare (`pbw_spans2`: does this step's source cross a word boundary?), then the read request,
its acknowledge and the next state. The answer only depends on the 4 low address bits: start offset
s = a[3:0] - (backwards ? source bits : 0), end e = s + step bits - 1, crossing iff s[7:4] != e[7:4] (8-bit signed).
This equals the word compare for every address (exhaustive check over the low bits, bit counts 0-63, both
directions, wrap; repeated independently over 786k cases in REVIEW_7), and a Verilator guard compares the two on
every clock.

| Accurate mode | 72f17ab | 8b483e8 | 0d0cff4 | d67fc17 | 0226164 |
|---|---|---|---|---|---|
| Fmax (slow 100 C), seed 1 / seed 2 | 55.41 / 53.82 MHz | 52.15 / 52.93 MHz | **57.59 / 56.32 MHz** | 55.56 MHz / - | 55.69 MHz / - |
| ALMs | | | about 14,260 | 14,292 | 14,351 |

d67fc17 (LINT once per state, the I/O keep mask, docs) gives +2.0 ns of slack at 50 MHz on seed 1; its worst paths
run from PSIZE into the register-file family. The spread between 0d0cff4 and d67fc17 is within what one seed to the
next gives (72f17ab differed by 1.6 MHz between seeds). Bus cycle by cycle, 0d0cff4 is identical to 829daa1 (ACK 1
and 9, host, HOLD, refresh, pixel matrix, interrupts). 0226164 (signed window checks, the W=3 clipped start as a sum)
keeps the speed: its two extra adders sit in the array setup states.

## Repeat

```
tools/dropin/mk_b1.sh b1_ca0 0 1     # projects go to work/<dir>
tools/dropin/mk_b1.sh b1_ca1 1 8
work/b1_ca0/build.sh; work/b1_ca1/build.sh   # ~20 min each; DONE, fmax.rpt, worst_setup.rpt, worst_paths.rpt
scripts/accuracy_sweep.sh 84c96fb            # bus cycle by cycle vs a revision, ACK_DELAY 1-14 + host traffic
```
