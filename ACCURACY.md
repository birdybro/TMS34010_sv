# TMS34010_sv, cycle-accurate version

This builds on [TMS34010_sv](https://github.com/birdybro/TMS34010_sv) by Kevin Coleman, a complete, synthesizable
SystemVerilog TMS34010. `README.md` is the original release's own description and is left unchanged; this file
describes what this version adds. The original release remains available from the original repository.

This version adds **cycle accuracy**: with the defaults, every instruction takes the number of machine states the
TMS34010 User's Guide (June 1988, SPVU001A) gives, the memory bus runs the chip's cycles at the chip's times, and
graphics instructions, the instruction cache, interrupts and posted writes are timed as on the chip. The aim is a
drop-in CPU for arcade cores, not just NARC: the work is ranked by a survey of 57 TMS34010s in MAME's
drivers (`docs/game_survey.md`).

## Using it

`tms34010_system` is the block to use:

```systemverilog
tms34010_system #(
  .CYCLE_ACCURATE (1),   // default: cycle-accurate
  .CLKS_PER_STATE (8)    // default: core clocks per machine state
) u_gsp ( ... );
```

- **Clock.** Clock the core at the chip's CLKIN rate. One machine state (one local clock, LCLK1) is
  `CLKS_PER_STATE` core clocks, as on the chip, which divides CLKIN by 8 (48 MHz core = 6 MHz local clock).
  At least 8 is needed (`docs/cycle_accuracy.md`, "Minimum clock ratio"); the core stops a simulation with an
  error below that.
- **Memory.** Each local-memory cycle (`cycle_req_o`, `cycle_kind_o`, ...) takes two states. `cycle_ack_i` works
  like the LRDY pin: give it as soon as the data is there; acknowledging later than the cycle's two states adds
  whole wait states, as LRDY does. A memory that answers within the two states needs no timing of its own.
- **Original-timing mode.** `CYCLE_ACCURATE=0, CLKS_PER_STATE=1` keeps the original release's timing (plus the five
  fixes below). It is kept as a test reference: the equality checks and the original test benches rest on it. It
  has no timing targets. Some docs call it "upstream mode".
- **Pin level.** `tms34010_pin_system` (the original-pin wrapper) works in accurate mode, but its bus timing does
  not survive the wrapper's clock-domain bridge (cycles come out 4 states apart instead of 2). In accurate mode use
  `tms34010_system`; game cores do. Its own default stays original-timing mode. Details: `docs/dropin_audit.md`.

- **One clock (optional).** With `VCLK_CEN=1` on `tms34010_system`, `vclk_i` is not a clock but an enable on `clk`:
  a one-clock pulse per VCLK period, high in the `clk` cycle that ends where VCLK would rise. The video logic
  then runs on `clk` and the design has a single clock. Every video register advances only on that pulse, so the
  picture timing is the same as with a VCLK of that rate; `vclk_rst_i` still resets the video logic. Checked
  against a divided VCLK (`tools/dropin/vclk_cen_sys.sh`): sync and blank pins and every bus cycle identical,
  except that a CPU write to a video register landing in the very clock of a VCLK edge takes effect one VCLK
  later, as any crossing between two clocks may. The default (`VCLK_CEN=0`) is the two-clock design as before.
- **Timing constraints.** The CPU's own multicycle and false paths are in `fpga/tms34010_core.sdc`. Read it from
  the project's SDC after creating the clocks (`source <repo>/fpga/tms34010_core.sdc`); it only names registers
  inside the CPU, behind a leading wildcard, so it works wherever the CPU sits in the hierarchy.

Size and speed (Cyclone V, timing-only project, accurate mode): about 14,300 ALMs, 55-57 MHz depending on the fitter
seed (`docs/dropin_measure.md`).

## What is modelled

From the guide, part by part (`docs/cycle_accuracy.md` has the detail and the page numbers):

- the machine-state grid and two-state local-memory cycles, with wait states from a late acknowledge;
- posted writes (the memory controller finishes a write while the CPU carries on: the guide's hidden states);
- the instruction cache (4 segments x 8 subsegments x 4 words, LRU, P flags, CD/CF) and its fill timing;
- each instruction's CPU states (Section 12 and Section 13 tables), interrupt and TRAP entry;
- FILL, PIXBLT, PIXT, DRAV and LINE with the guide's setup and per-word transfer timing, writing whole words, with
  plane masking and transparency done inside the write as the memory controller does;
- LINT1/LINT2 sampled once per state at LCLK1's fall (8.3);
- DRAM refresh, screen refresh, host cycles and bus HOLD competing for the bus.

Five behaviour fixes apply in both modes: window checks treat X and Y as signed, as the guide says, so shapes
that start above or left of (0,0) are clipped correctly; JRP tests "P" (N=0 and Z=0); BTST K complements the encoded K; no
interrupt is taken while an opcode fetch is outstanding; LINE with W=1 draws no pixels.

## Evidence

- `docs/accuracy_evidence.md`: the timing bench (every instruction form and case against the guide's figures: 874
  of 1,003 cache-hit figures equal; the other 129 are where the guide contradicts itself, each listed with its
  page), a cross-check against MAME, a real game (NARC), and the independent reviews.
- `docs/dropin_audit.md`: chapter by chapter, what each part of the chip is checked by, in which mode, and what is
  left. Includes the pixel-operation matrix (2,598 cases, identical registers and memory in both modes), the host
  interface at system level, and two GSPs in external sync (the Exterminator's arrangement).
- `docs/game_survey.md`: what the 57 surveyed CPUs use, so the open items can be weighed.
- `docs/dropin_measure.md`: size and speed, and how the timing was kept while it was made faster.
- Bus-level identity: `scripts/accuracy_sweep.sh` compares every external bus cycle (kind, address, data, start
  clock) against an earlier reference version, at memory latencies 1-14 and with host, HOLD, DRAM-refresh and
  screen-refresh traffic.

## Checks to run

| What | How |
|---|---|
| The original test benches plus the new ones | `REGRESS_JOBS=2 scripts/regress.sh` |
| Instruction timing against the guide | `scripts/accuracy.sh 1 1` (report in `work/accuracy_report_1.md`) |
| Bus cycles against a reference version | `scripts/accuracy_sweep.sh <ref> [acks]` |
| Host interface at system level | `tools/dropin/host_sys.sh 1` (or `0`) |
| Two GSPs in external sync, system level | `tools/dropin/two_gsp_sys.sh 1` (or `0`) |
| Negative XY and window clipping against the guide's rules | `tools/dropin/negxy_sys.sh 1` (or `0`) |

Verilator 5.032 was used. Simulation-only checks (`ifdef VERILATOR`) stop a run if an internal invariant breaks.

## Known limits

- **C15**: PIXBLT expand rows longer than 32 pixels (Table 13-12). The guide's table can't be read consistently
  in either edition; the model follows the text. It changes only how long such a row takes (3-5 states), not the
  picture. The Atari driving games use it. Settling it needs TI's Applications Guide (SPVA007) or a timing run on
  a real chip.
- **C17**: a linear FILL or PIXBLT to a destination that is not pixel-aligned hangs in accurate mode. The guide
  requires aligned addresses, and no surveyed game does it.
- **Pin level**: see "Using it".
- **Two GSPs in external sync** with horizontal blanking ending less than 3 clocks into the line (HEBLNK1 < 3) are
  not supported by the video block. No surveyed game does it.
- Places where the guide is silent or contradicts itself are listed as assumptions C1-C16 in
  `docs/cycle_accuracy.md`, with the choice made.

Not modelled: the TMS34020, electrical (AC) timing, first-silicon modes.

## Credit

Built on Kevin Coleman's TMS34010_sv (MIT licence, `LICENSE`). Cycle-accuracy work by Chris Watson.
