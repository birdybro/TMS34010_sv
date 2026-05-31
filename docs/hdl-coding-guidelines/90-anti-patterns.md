# Anti-Patterns (Consolidated)

> Bundle version: 2026-05-19. Synthesized from §7 of all 18 topic docs.

## Purpose

This document is the bundle's single source of truth for HDL anti-patterns that compile but break. Each entry follows Symptom → Cause → Fix → Citation, with a back-link to the topic doc that owns the deep treatment. Use as a review checklist; follow primary-home links for context and code excerpts.

## Pre-committed checklist (spec §9 coverage)

Spec §9 pre-committed 39 anti-patterns. All 39 surface below.

| Spec §9 # | Name | This file # | Primary home doc |
|---|---|---|---|
| #1 | Monolithic always block | 1 | [13-registers-and-combinational-blocks.md](13-registers-and-combinational-blocks.md) |
| #2 | Mixed blocking/nonblocking assignments in one block | 2 | [13-registers-and-combinational-blocks.md](13-registers-and-combinational-blocks.md) |
| #3 | Combinational feedback loop | 3 | [13-registers-and-combinational-blocks.md](13-registers-and-combinational-blocks.md) |
| #4 | Latch from incomplete combinational coverage | 4 | [13-registers-and-combinational-blocks.md](13-registers-and-combinational-blocks.md) |
| #5 | Width/signedness mismatch on assignment | 5 | [12-synthesizable-sv-subset.md](12-synthesizable-sv-subset.md) |
| #6 | Implicit width truncation in concatenation | 6 | [12-synthesizable-sv-subset.md](12-synthesizable-sv-subset.md) |
| #7 | `casex`/`casez` with overlapping patterns | 7 | [14-finite-state-machines.md](14-finite-state-machines.md) |
| #8 | For-loop written as software iteration | 8 | [10-hardware-mindset-and-microarchitecture.md](10-hardware-mindset-and-microarchitecture.md) |
| #9 | Gated or fabric-derived clock | 9 | [11-clocking-resets-and-cyclone-v-clock-networks.md](11-clocking-resets-and-cyclone-v-clock-networks.md) |
| #10 | Async reset without sync release | 10 | [11-clocking-resets-and-cyclone-v-clock-networks.md](11-clocking-resets-and-cyclone-v-clock-networks.md) |
| #11 | Reset polarity inconsistency across modules | 11 | [11-clocking-resets-and-cyclone-v-clock-networks.md](11-clocking-resets-and-cyclone-v-clock-networks.md) |
| #12 | Reset network with no analysis of fanout | 12 | [11-clocking-resets-and-cyclone-v-clock-networks.md](11-clocking-resets-and-cyclone-v-clock-networks.md) |
| #13 | FSM without `default` state / safe default | 13 | [14-finite-state-machines.md](14-finite-state-machines.md) |
| #14 | Redundant FSM states that can be merged | 14 | [14-finite-state-machines.md](14-finite-state-machines.md) |
| #15 | Pipeline data without parallel `valid` pipeline | 15 | [15-pipelines-and-latency-thinking.md](15-pipelines-and-latency-thinking.md) |
| #16 | Long ternary/case nest treated as one combinational stage | 16 | [15-pipelines-and-latency-thinking.md](15-pipelines-and-latency-thinking.md) |
| #17 | Pipeline register inserted "for safety" with no critical path | 17 | [16-resource-and-state-economy.md](16-resource-and-state-economy.md) |
| #18 | Ready-path comb chain longer than one LAB | 18 | [21-skid-buffers-and-register-slices.md](21-skid-buffers-and-register-slices.md) |
| #19 | Bit-by-bit multi-bit CDC | 19 | [24-cdc-multi-bit.md](24-cdc-multi-bit.md) |
| #20 | 2FF synchronizer on a same-clock-domain signal | 20 | [16-resource-and-state-economy.md](16-resource-and-state-economy.md) |
| #21 | Hand-rolled binary counter as CDC pointer (must be Gray) | 21 | [24-cdc-multi-bit.md](24-cdc-multi-bit.md) |
| #22 | `/`, `%`, or variable shift on critical path | 22 | [32-arithmetic-patterns-and-operator-cost.md](32-arithmetic-patterns-and-operator-cost.md) |
| #23 | Multiply not registered for DSP inference | 23 | [31-dsp-inference-cyclone-v.md](31-dsp-inference-cyclone-v.md) |
| #24 | Read-during-write mode assumed without explicit setting | 24 | [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md) |
| #25 | Inferred M10K where a ≤16-entry register file belongs in flops | 25 | [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md) |
| #26 | Used DSP block where original chip used iterative shift-add | 26 | [31-dsp-inference-cyclone-v.md](31-dsp-inference-cyclone-v.md) |
| #27 | Width-N register where consumer reads only bits `[M-1:0]`, M < N | 27 | [16-resource-and-state-economy.md](16-resource-and-state-economy.md) |
| #28 | Wide bus through hierarchy where leaves ignore most bits | 28 | [16-resource-and-state-economy.md](16-resource-and-state-economy.md) |
| #29 | Mirror copy of a signal in two modules instead of fanout | 29 | [16-resource-and-state-economy.md](16-resource-and-state-economy.md) |
| #30 | Counter wider than `$clog2(N)` for a mod-N counter | 30 | [16-resource-and-state-economy.md](16-resource-and-state-economy.md) |
| #31 | Sign bit carried where unsigned is provably sufficient | 31 | [16-resource-and-state-economy.md](16-resource-and-state-economy.md) |
| #32 | Replaced shared resource with N parallel copies | 32 | [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md) |
| #33 | Added pipeline stages that change observable cycle counts | 33 | [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md) |
| #34 | Linear "software" state machine instead of mirroring chip bus | 34 | [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md) |
| #35 | 16/32-bit datapath in an 8-bit chip emulation | 35 | [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md) |
| #36 | Multi-port memory where original had single-port + arbitration | 36 | [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md) |
| #37 | Parallel barrel shifter where original used 1-bit shifter | 37 | [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md) |
| #38 | FIFO without producer-side backpressure | 38 | [22-fifos-synchronous-and-asynchronous.md](22-fifos-synchronous-and-asynchronous.md) |
| #39 | Variable bit-select with non-constant index | 39 | [32-arithmetic-patterns-and-operator-cost.md](32-arithmetic-patterns-and-operator-cost.md) |


## Spec §9 addendum anti-patterns (introduced by topic docs)

Topic docs introduced these beyond spec §9. Each adds a distinct mistake that compiles but breaks.

| This file # | Name | Primary home doc |
|---|---|---|
| 40 | No pre-RTL plan — coding begins immediately | [10-hardware-mindset-and-microarchitecture.md](10-hardware-mindset-and-microarchitecture.md) |
| 41 | Software-algorithm transliteration | [10-hardware-mindset-and-microarchitecture.md](10-hardware-mindset-and-microarchitecture.md) |
| 42 | Module hierarchy mirrors call-graph of a software port | [10-hardware-mindset-and-microarchitecture.md](10-hardware-mindset-and-microarchitecture.md) |
| 43 | Reset asserted by a glitching combinational signal | [11-clocking-resets-and-cyclone-v-clock-networks.md](11-clocking-resets-and-cyclone-v-clock-networks.md) |
| 44 | `always_comb` with self-referential variable read | [12-synthesizable-sv-subset.md](12-synthesizable-sv-subset.md) |
| 45 | FSM output decoder combinational but consumer assumes registered | [14-finite-state-machines.md](14-finite-state-machines.md) |
| 46 | Data freezes on stall but `valid` keeps advancing (or vice versa) | [15-pipelines-and-latency-thinking.md](15-pipelines-and-latency-thinking.md) |
| 47 | Valid drops before transfer | [20-ready-valid-handshakes.md](20-ready-valid-handshakes.md) |
| 48 | Payload changes while `valid && !ready` | [20-ready-valid-handshakes.md](20-ready-valid-handshakes.md) |
| 49 | `valid` depending combinationally on `ready` without skid buffer | [20-ready-valid-handshakes.md](20-ready-valid-handshakes.md) |
| 50 | `ready` driven by producer, or `valid` driven by consumer | [20-ready-valid-handshakes.md](20-ready-valid-handshakes.md) |
| 51 | Skid buffer registers forward path only, not `ready` | [21-skid-buffers-and-register-slices.md](21-skid-buffers-and-register-slices.md) |
| 52 | Depth-greater-than-2 storage used as a skid buffer | [21-skid-buffers-and-register-slices.md](21-skid-buffers-and-register-slices.md) |
| 53 | Under-sized FIFO depth for worst-case burst | [22-fifos-synchronous-and-asynchronous.md](22-fifos-synchronous-and-asynchronous.md) |
| 54 | Over-sized FIFO depth "to be safe" | [22-fifos-synchronous-and-asynchronous.md](22-fifos-synchronous-and-asynchronous.md) |
| 55 | One-flop synchronizer | [23-cdc-single-bit.md](23-cdc-single-bit.md) |
| 56 | Synchronizer not in a dedicated module | [23-cdc-single-bit.md](23-cdc-single-bit.md) |
| 57 | Pulse fed into a level synchronizer | [23-cdc-single-bit.md](23-cdc-single-bit.md) |
| 58 | Synchronizer with no SDC declaration | [23-cdc-single-bit.md](23-cdc-single-bit.md) |
| 59 | Combinational logic between source register and synchronizer | [23-cdc-single-bit.md](23-cdc-single-bit.md) |
| 60 | MCP without payload-stable hold | [24-cdc-multi-bit.md](24-cdc-multi-bit.md) |
| 61 | MCP used for high-rate data | [24-cdc-multi-bit.md](24-cdc-multi-bit.md) |
| 62 | Async FIFO empty/full computed against un-Gray-coded pointer | [24-cdc-multi-bit.md](24-cdc-multi-bit.md) |
| 63 | Async read inferred as area blowup instead of M10K | [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md) |
| 64 | Init file missing at synthesis (works in sim, zeros on hardware) | [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md) |
| 65 | True-dual-port used where simple-dual-port would suffice | [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md) |
| 66 | Mixed-signedness multiply | [31-dsp-inference-cyclone-v.md](31-dsp-inference-cyclone-v.md) |
| 67 | Constant-operand multiply consumes a DSP block | [31-dsp-inference-cyclone-v.md](31-dsp-inference-cyclone-v.md) |
| 68 | Multiply wider than DSP block without alignment logic | [31-dsp-inference-cyclone-v.md](31-dsp-inference-cyclone-v.md) |
| 69 | Silent overflow on accumulator | [32-arithmetic-patterns-and-operator-cost.md](32-arithmetic-patterns-and-operator-cost.md) |
| 70 | Wide combinational mux on the critical path | [32-arithmetic-patterns-and-operator-cost.md](32-arithmetic-patterns-and-operator-cost.md) |
| 71 | Mixed-width arithmetic | [32-arithmetic-patterns-and-operator-cost.md](32-arithmetic-patterns-and-operator-cost.md) |
| 72 | SDC not written; design runs unconstrained | [40-timing-closure-and-sdc.md](40-timing-closure-and-sdc.md) |
| 73 | I/O register not placed in IOE; large clock-to-pad delay | [40-timing-closure-and-sdc.md](40-timing-closure-and-sdc.md) |
| 74 | `set_false_path` used to make a real critical path "go away" | [40-timing-closure-and-sdc.md](40-timing-closure-and-sdc.md) |
| 75 | `set_multicycle_path` without RTL evidence of stability | [40-timing-closure-and-sdc.md](40-timing-closure-and-sdc.md) |
| 76 | Synthesis warnings ignored | [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md) |
| 77 | Inferred resource not confirmed in Fitter report | [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md) |
| 78 | Testbench has no scoreboard; manual waveform inspection only | [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md) |
| 79 | SVA assertion writes the bug (assertion re-implements the DUT) | [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md) |
| 80 | `assume` used where `assert` was meant | [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md) |

**Duplicates flagged as bugs:** 0. (Doc 40's "Pipeline added for safety" entry self-declares as cross-ref to spec §9 #17 in doc 16; primary home is doc 16, kept as #17.)

## Entries

### Coding discipline

#### 1. Monolithic always block

- **Symptom:** One 50–500-line `always @(posedge clk)` bundles reset, register updates, FSM next-state, and output muxes. Bugs correlate across unrelated branches; fmax opaque; adding a concern regresses existing ones.
- **Cause:** Writing RTL as one sequential program; the block "feels" like `main()` and accretes responsibilities.
- **Fix:** One `always_ff` per register (or tightly coupled group); one `always_comb` per next-state decoder, output decoder, address generator, or shared computation. Use `_q`/`_d` naming.
- **Citation:** lowRISC `references/raw/style/lowrisc_systemverilog_style.md:1897-1901, 2838-2885 @ 735d911`; reinforced by Cummings FSM `:181-247` and FPGACPU `verilog_coding_standard.html:678-707`.
- **Primary home:** [13-registers-and-combinational-blocks.md](13-registers-and-combinational-blocks.md)

#### 2. Mixed blocking and nonblocking assignments in one block

- **Symptom:** Run-to-run sim nondeterminism; sim/synth mismatch where a register appears to advance two states in one cycle in simulation but only one in hardware.
- **Cause:** Using `=` and `<=` in the same `always` block. The simulator may interpret blocking and nonblocking as separate scheduled regions.
- **Fix:** `always_ff` uses only `<=`; `always_comb` uses only `=`. If you need sequential ordering before registering, do blocking in `always_comb` writing `_d` signals and register with `q <= d`.
- **Citation:** Cummings *Nonblocking Assignments in Verilog Synthesis* (live URL); lowRISC `:1812-1816 @ 735d911`; FPGACPU `verilog_coding_standard.html:470-472`.
- **Primary home:** [13-registers-and-combinational-blocks.md](13-registers-and-combinational-blocks.md)

#### 3. Combinational feedback loop

- **Symptom:** Quartus Synthesis report logs `combinational loop`. Outputs glitch and settle to an unintended value; timing analysis reports `(loop)` on the worst path so no real fmax is produced. With `always_comb`, may produce a compile error.
- **Cause:** A pure-combinational signal appears in its own RHS cone — directly (`assign x = x | y;`) or through a chain that closes back on itself, possibly across hierarchy.
- **Fix:** Insert a register on the feedback path (move the loop closure through a flop) or re-derive the signal so it no longer appears in its own cone.
- **Citation:** Intel *Recommended HDL Coding Styles* (live URL); FPGACPU `verilog_coding_standard.html:487-494`.
- **Primary home:** [13-registers-and-combinational-blocks.md](13-registers-and-combinational-blocks.md)

#### 4. Latch inferred from incomplete combinational coverage / missing `else`

- **Symptom:** Quartus Synthesis logs `inferred latch` for a signal meant to be a wire; SV `always_comb` raises "latch implied"; hardware diverges from RTL sim around reset.
- **Cause:** `always_comb` output not assigned on every path: `if` without `else`, `if`/`elseif` missing trailing `else`, or `case` missing `default:`.
- **Fix:** Either (1) defaults-at-top — assign baseline first, override per branch; or (2) exhaustive arms — every `if`/`elseif` ends with `else`, every `case` ends with `default:`. `unique`/`priority` catches overlap but does **not** substitute for `default:`.
- **Citation:** Intel *Register and Latch Coding Guidelines* (live URL); reinforced by lowRISC `:2189-2197 @ 735d911` and VerilogPro `systemverilog_always_comb_always_ff.html` §"Update: always_comb" @ 2022-04.
- **Primary home:** [13-registers-and-combinational-blocks.md](13-registers-and-combinational-blocks.md)

#### 5. Width/signedness mismatch on assignment

- **Symptom:** Sim matches synth but silently wrong on negative operands or operands near target width. Canonical: adding 1-bit unsigned `incr` to signed `[7:0] a` gives `+129` instead of `-127`.
- **Cause:** Wider expression assigned narrower, or `signed` mixed with plain `logic` without cast (Verilog implicitly unsigns), or unsized literals.
- **Fix:** Explicit width+base on every literal (`8'h00`); declare signed-arithmetic as `logic signed [W-1:0]`; cast on every signed↔unsigned crossing. Document expected carry: `4'(cnt_q + 4'h1)`.
- **Citation:** lowRISC `references/raw/style/lowrisc_systemverilog_style.md:1626-1656, 2304-2334`; FPGACPU `verilog_coding_standard.html:198-233`.
- **Primary home:** [12-synthesizable-sv-subset.md](12-synthesizable-sv-subset.md)

#### 6. Implicit width truncation in concatenation

- **Symptom:** `{a, b, c}` not matching the target's summed width silently drops/zero-extends bits. Sim matches synth (both truncate); bug looks like a logic error downstream.
- **Cause:** Concatenation returns an unsigned vector of summed widths. Unsized literals interact with integer-promotion to produce 32-bit phantom fields.
- **Fix:** Size every operand explicitly (`{4'd0, sixteen_bit_word}` for 20-bit). Match source-to-target widths exactly at port connections; do not rely on implicit zero-extension.
- **Citation:** lowRISC `references/raw/style/lowrisc_systemverilog_style.md:1658-1677, 1721-1745, 1747-1768`; FPGACPU `verilog_coding_standard.html:235-263`.
- **Primary home:** [12-synthesizable-sv-subset.md](12-synthesizable-sv-subset.md)

#### 7. `casex` / `casez` with overlapping patterns

- **Symptom:** Sim/synth mismatch. Sim evaluates case items in source order (first match wins); synth may flatten into parallel comparators where overlapping items produce a logic OR rather than priority encode. Worse with `casex` (`'x` on either side widens the match).
- **Cause:** Using `casex` at all, or `casez` with `?` wildcards making two items match the same pattern.
- **Fix:** (1) Prefer `case inside { ... }` (SV-2017). (2) For V-2001, use `casez` with `?` (never `z`) and mutually exclusive items. (3) Prefix with `unique case` to assert no overlap. (4) Never use `// synopsys full_case parallel_case`.
- **Citation:** lowRISC `references/raw/style/lowrisc_systemverilog_style.md:2236-2252, 2158-2164`; Cummings FSM `:508-557`.
- **Primary home:** [14-finite-state-machines.md](14-finite-state-machines.md)

#### 8. For-loop written as software iteration

- **Symptom:** `for` loop reads as N sequential steps. Synthesis (a) produces enormous combinational tree missing fmax by an order of magnitude; (b) unrolls into thousands of gates overflowing the device; (c) with non-static bound, fails elaboration OOM.
- **Cause:** Author expected runtime execution. In synthesizable RTL the loop is **unrolled at elaboration** into parallel hardware.
- **Fix:** Decide what the loop is for. Parallel per-cycle: keep `for` in `always_comb` with `localparam` bound. Sequential many-cycles: it's an FSM with a counter. Pipelined stream: it's a pipeline — see doc 15.
- **Citation:** `references/extracted_text/zipcpu/class_verilog.txt:14258-14263 @ 2026-05-20`; reinforced by FPGACPU `verilog_coding_standard.html:539-547`.
- **Primary home:** [10-hardware-mindset-and-microarchitecture.md](10-hardware-mindset-and-microarchitecture.md)

### Clocking & reset

#### 9. Gated or fabric-derived clock

- **Symptom:** TimeQuest reports a `derived_clock` from a non-clock-network source; Fitter warns about non-global routing; registers downstream intermittently drop edges or glitch.
- **Cause:** Clock generated in fabric — AND-gating an enable, using a divider flop's output as next-stage clock, or MUX'ing clocks through LUTs. Violates the synchronous-design contract.
- **Fix:** Derive new frequencies from a PLL output on a clock network. For "stop the clock," use a clock-enable inside `always_ff`. For clock MUX/gate that cannot be PLL-sourced, use `ALTCLKCTRL` with `clkena` on a GCLK/RCLK.
- **Citation:** Intel *Arria V and Cyclone V Design Guidelines* p. 30, item 2 (`references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt`); Cyclone V Handbook "Clock Networks and PLLs" (live URL).
- **Primary home:** [11-clocking-resets-and-cyclone-v-clock-networks.md](11-clocking-resets-and-cyclone-v-clock-networks.md)

#### 10. Async reset without sync release

- **Symptom:** Sim passes; on hardware flops come out on wrong clock edges, settle wrong, or hang in metastable behavior. Failures cluster around external-reset release or `nSTATUS` settle.
- **Cause:** External reset wired straight to every flop's async-clear without a per-domain synchronizer. Async assertion is fine; the async release lands within setup/hold of some flops, propagating metastable values.
- **Fix:** Insert a 2-flop (3-flop where MTBF demands) sync-release synchronizer per clock domain: async-clear sees the external reset, data-in tied high, second output drives per-domain `rst_n`.
- **Citation:** Intel *Arria V and Cyclone V Design Guidelines* p. 33, item 9 (`references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt`); reinforced by FPGACPU `verilog_coding_standard.html:720-725, 856-860`.
- **Primary home:** [11-clocking-resets-and-cyclone-v-clock-networks.md](11-clocking-resets-and-cyclone-v-clock-networks.md)

#### 11. Reset polarity inconsistency across modules

- **Symptom:** Sim behavior depends on module load order; some submodules stay in reset. Canonical: top uses `rst_n` but a leaf uses `rst` and the two are wired together.
- **Cause:** Modules sharing a reset net disagree on polarity. Verilog connectivity is legal; the semantic mismatch silently flips reset condition.
- **Fix:** Pick one polarity per project (bundle uses active-low async `rst_n`). If a sub-block needs the opposite, invert exactly once at the instantiation boundary and name the inverted local wire.
- **Citation:** lowRISC `references/raw/style/lowrisc_systemverilog_style.md:1372-1394, 2935-2947`.
- **Primary home:** [11-clocking-resets-and-cyclone-v-clock-networks.md](11-clocking-resets-and-cyclone-v-clock-networks.md)

#### 12. Reset network with no analysis of fanout

- **Symptom:** Small builds close timing; as design grows, released-reset net shows recovery/removal violations or unexplained skew. Fitter splits the load across resources with different delays.
- **Cause:** `rst_n` treated as fan-out-free and wired everywhere. With enough endpoints, no single low-skew network covers it.
- **Fix:** Re-synchronize the released reset *per region* — drive the global async `arst_n` into a sync-release per clock region rather than fanning out a single chip-wide `rst_n`. Confirm in Fitter clock-network/high-fanout reports.
- **Citation:** [I] from Intel design-entry items 8–9 (`references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt` pp. 32–33) and 5CSEBA6U23I7 16-GCLK budget (`references/raw/intel/cyclone_v_product_table_api.txt`).
- **Primary home:** [11-clocking-resets-and-cyclone-v-clock-networks.md](11-clocking-resets-and-cyclone-v-clock-networks.md)

### FSMs

#### 13. FSM without `default` state / safe default

- **Symptom:** FSM hangs after glitch or power-up corruption; reset doesn't recover. Outputs `'x` in sim or unrecoverable in hardware.
- **Cause:** Any of (a) no `default:` arm; (b) `always_comb` omits defaults-at-top; (c) state register no reset or resets to `'x`; (d) unreachable codepoints with no transition back to `StIdle`.
- **Fix:** All four together: defaults-at-top for `state_d` and outputs; explicit `default:` arm; `always_ff` reset to a named state; exhaustive encoding (`2**$clog2(N) == N`) or `default:` transitioning to `StIdle`.
- **Citation:** lowRISC `:2187-2233, 2876-2878`; Cummings FSM `:251-267` (bundle rejects Cummings's `next = 3'bx`); Intel *Register and Latch Coding Guidelines* (live URL).
- **Primary home:** [14-finite-state-machines.md](14-finite-state-machines.md)

#### 14. Redundant FSM states that can be merged

- **Symptom:** State count exceeds minimum. Two states have identical outgoing transitions and outputs conditioned on the same inputs.
- **Cause:** States added one-per-action without re-deriving the state-transition table. Often visible as `StPrepX` followed by `StX` where `StPrepX` only forwards inputs.
- **Fix:** Tabulate the state-transition table. Mergeable iff rows identical in every column; collapse and re-derive `$clog2(state_count)`. For systematic minimization, Hopcroft's partition refinement (Kohavi).
- **Citation:** [I]. `references/projects/FPGADesignElements/fsm.html:22-32 @ 2026-05-20`; Cummings FSM `:751-752`.
- **Primary home:** [14-finite-state-machines.md](14-finite-state-machines.md)

### Datapath & pipelining

#### 15. Pipeline data without a parallel `valid` pipeline

- **Symptom:** Downstream treats bubble cycles as live data; results corrupted. Sim correct for steady streams but fails the instant inputs are sparse, gated, or interleaved with stalls.
- **Cause:** Data flops added per stage but the corresponding `valid` was left as a comb expression not matching the data's delay, or omitted entirely.
- **Fix:** Every data flop has a sibling `valid` flop with the **same enable** and **same clear/reset**. If data takes N stages, `valid` takes N stages.
- **Citation:** `references/projects/FPGADesignElements/Pipeline_FIFO_Buffer.v:326-341`; reinforced by ZipCPU `pipeline_control.txt:191-265`.
- **Primary home:** [15-pipelines-and-latency-thinking.md](15-pipelines-and-latency-thinking.md)

#### 16. Long ternary/case nest treated as one combinational stage

- **Symptom:** TimeQuest critical path through nested conditionals (12-deep ternary or 64-way `case` with computed selectors); fmax below target; chain maps into many ALM levels.
- **Cause:** Logically-sequential selection coded as one expression. Synthesizer cannot retime across the chain because there is only one combinational stage.
- **Fix:** Identify the natural cycle boundary (where the next selector becomes data-dependent on a prior result). Split into pipeline stages with `(data, valid)` pairs. If the selector is known one cycle ahead, convert to a **one-hot mux with pre-registered select**.
- **Citation:** [I] from Intel HDL design guidance (live URL `https://www.intel.com/content/www/us/en/docs/programmable/683082/current/hdl-design-guidelines.html`). Mitigation matches FPGADesignElements `Pipeline_Merge_One_Hot` / `Pipeline_Branch_One_Hot`.
- **Primary home:** [15-pipelines-and-latency-thinking.md](15-pipelines-and-latency-thinking.md)

#### 17. Pipeline register inserted "for safety" with no critical path justifying it

- **Symptom:** Extra latency and flops exceed budget; no TimeQuest slack line shows the register being load-bearing. Often `*_q1, *_q2, *_q3` chains with no functional consumer.
- **Cause:** Register fails all four justifications: holds no state, doesn't break a critical path (slack already positive), doesn't cross a clock domain, isn't a named pipeline stage. Inserted from habit.
- **Fix:** Delete it. Re-synth and confirm slack unchanged. Pipeline insertion must be backed by a TimeQuest path report. (Doc 40 surfaces this under the timing-closure framing.)
- **Citation:** [I] from doc 16's load-bearing rule. Contrast: FPGADesignElements `Accumulator_Binary.v:35-47 @ 2450a54` makes pipeline insertion an explicit parameter.
- **Primary home:** [16-resource-and-state-economy.md](16-resource-and-state-economy.md)

#### 18. Ready-path combinational chain longer than one LAB

- **Symptom:** TimeQuest worst-case setup path traverses N modules along `ready`; fmax falls inversely with N as design scales; failing path is "Combinational path delay" dominated by `&&` / mux logic.
- **Cause:** Each consumer's `ready` combinationally derived from its downstream's `ready`. With 3+ chained modules the chain crosses LAB boundaries; inter-LAB routing dominates.
- **Fix:** Insert a canonical skid buffer to flop `o_ready` (`o_ready = !r_valid`). Each slice breaks the chain. Chain multiple slices only after timing analysis confirms the first moved the path.
- **Citation:** ZipCPU `references/raw/zipcpu/axi_rules.html:152-161`; wb2axip `references/projects/wb2axip/rtl/skidbuffer.v:9-14, 160 @ df8e764`.
- **Primary home:** [21-skid-buffers-and-register-slices.md](21-skid-buffers-and-register-slices.md)

### CDC

#### 19. Bit-by-bit 2FF synchronization of a changing multi-bit bus

- **Symptom:** Destination observes a multi-bit value the source never emitted — counter skips backwards, encoded state appears undefined, control word loads wrong configuration. Failure scales with bus toggle rate and clock ratio. Sim passes.
- **Cause:** N independent 2FF chains, one per bit. Each bit's metastability resolves on its own timeline; the combination forms a phantom word never present on the source.
- **Fix:** Pick one: (a) **async FIFO** for bursty changes; (b) **MCP/word synchronizer** for occasional changes held stable across the round-trip; (c) **Gray-coded counter** when sampling a count without handshake. Never independent 2FF chains on data bits.
- **Citation:** Cummings SNUG2008 CDC (live URL `http://www.sunburst-design.com/papers/CummingsSNUG2008Boston_CDC.pdf`); verilogpro CDC part 2 (`references/raw/verilogpro/cdc_part2.html @ 2026-05-20`).
- **Primary home:** [24-cdc-multi-bit.md](24-cdc-multi-bit.md)

#### 20. Defensive 2FF synchronizer on a same-clock-domain signal

- **Symptom:** Two extra flops per "synchronized" signal in the ALM count; no Quartus metastability-analyzer entry because source and destination are already in the same clock domain. Correctness-wise a no-op.
- **Cause:** No clock domain crossing exists. The register chain is a habit copy from CDC code.
- **Fix:** Delete it. If the original code drove a signal crossing a specific boundary, gate the synchronizer to that boundary only. Most signals in single-clock designs need none. Cross-ref doc 23 for CDC correctness.
- **Citation:** [I] from doc 16's load-bearing rule.
- **Primary home:** [16-resource-and-state-economy.md](16-resource-and-state-economy.md)

#### 21. Hand-rolled binary counter used as an async FIFO pointer

- **Symptom:** Custom async FIFO loses/duplicates entries; empty/full spuriously toggle; bug appears at high clocks or specific clock ratios and disappears under single-step debug. Functional sim often passes.
- **Cause:** Plain binary counter crosses through a per-bit 2FF chain. When an increment flips multiple bits, chains settle independently and the synchronized pointer takes on phantom intermediates.
- **Fix:** **Gray-code the pointer** before the source-side register: `wr_ptr_gray = wr_ptr_bin ^ (wr_ptr_bin >> 1)`. The destination 2FF then sees ≤1 bit transitioning per increment. Compare empty/full Gray-against-Gray. For non-power-of-two depth, use the FPGADesignElements MCP `CDC_FIFO_Buffer.v`.
- **Citation:** Cummings SNUG 2002 SJ (live URL `http://www.sunburst-design.com/papers/CummingsSNUG2002SJ_FIFO1.pdf`); `references/projects/verilog-axis/rtl/axis_async_fifo.v:195-227,263-267 @ 48ff7a7`.
- **Primary home:** [24-cdc-multi-bit.md](24-cdc-multi-bit.md)

### Resource inference (Cyclone V)

#### 22. `/`, `%`, or variable shift on the critical path

- **Symptom:** Thousands of ALMs for a single expression; RTL Component Statistics lists "divider"/"shifter"; TimeQuest worst-slack delay in hundreds of nanoseconds; design will not close.
- **Cause:** `/`, `%`, or variable `<<`/`>>` treated as single-cycle. Cyclone V has no single-cycle divider or barrel shifter; synthesizer inferred a restoring divider or barrel shifter that grows with operand width.
- **Fix (preference order):** (1) **Reformulate.** `x / 8` → `x >>> 3`; `x % 8` → `x & 3'b111`. Non-PoT constant: multiply-by-reciprocal. Variable shift: register the amount one cycle ahead. (2) **Pipeline.** `Bit_Shifter_Pipelined.v` or handshake-based `Divider_Integer_Signed`. (3) **IP.** Intel Divider IP.
- **Citation:** `references/projects/FPGADesignElements/Divider_Integer_Signed.v:24-66, Bit_Shifter.v:1-7, Bit_Shifter_Pipelined.v:1-50 @ 2450a54`; Intel coding guidelines (live URL).
- **Primary home:** [32-arithmetic-patterns-and-operator-cost.md](32-arithmetic-patterns-and-operator-cost.md)

#### 23. Multiply not registered for DSP inference

- **Symptom:** Fitter Resource Section reports zero DSP blocks despite multiplies in RTL; multiply mapped to soft logic; hundreds of ALMs where one DSP would do; timing closes poorly.
- **Cause:** `assign c = a * b;` or `always_comb` without surrounding registers. Quartus's template requires both input and output registers around `*`. Registering only the output won't pack input registers into the DSP.
- **Fix:** Wrap in `always @(posedge clk)` with input registers (`a_reg`, `b_reg`), combinational `mult_out = a_reg * b_reg`, and registered `out`, all in one `always` block. Confirm one DSP per multiply in the Fitter Resource Section.
- **Citation:** Intel *Inferring Multipliers and DSP Functions* (live URL); FPGADesignElements `Multiplier_Binary_Parallel.v:30-46`.
- **Primary home:** [31-dsp-inference-cyclone-v.md](31-dsp-inference-cyclone-v.md)

#### 24. Read-during-write mode assumed without explicit setting

- **Symptom:** Sim passes; post-PnR sim diverges or behavior changes between Quartus versions. At `we=1 && write_address == read_address`, read output is old or new unpredictably. Intermittent corruption when adjacent stages share an address.
- **Cause:** RTL didn't match either canonical RDW form (blocking/new-data or nonblocking/old-data). Mixed blocking/NBA, separate `always_comb` for read, or split write/read across `always` blocks. Quartus picks a default or refuses M10K/MLAB.
- **Fix:** Rewrite using exactly one canonical RDW template. Mode by architecture: new-data if consumer reads next cycle; old-data if consumer can wait. Verify the mode in Fitter memory summary; confirm RTL sim and post-PnR sim agree at collisions.
- **Citation:** Intel *Inferring Memory Functions* RDW subsections (live URLs); FPGADesignElements `RAM_Single_Port.v:11-29, 33-40 @ 2450a54`.
- **Primary home:** [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md)

#### 25. Inferred M10K where a small register file (≤16 entries) belongs in flops

- **Symptom:** Fitter shows one M10K for a 16-entry register file. Downstream wants parallel reads (CPU `rd`/`rs`/`rt`); M10K provides only 1-2 read ports, forcing stall/replicate workarounds.
- **Cause:** Simple-dual-port template chosen out of habit. The "memory → M10K" heuristic is wrong for tiny multi-read arrays — the correct primitive is flops with LUT-mux fan-out.
- **Fix:** `reg [W-1:0] regs [0:N-1];` with `always @(posedge clk)` and combinational reads per port. Confirm zero memory blocks. Era-faithful angle: original CPU had no M10K equivalent.
- **Citation:** `references/projects/FPGADesignElements/RAM_Multiported_LE.v:1-15 @ 2450a54`; Cyclone V Device Handbook Vol. 1 embedded-memory-modes (live URL).
- **Primary home:** [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md)

#### 26. Used DSP block where original chip used iterative shift-add

- **Symptom:** Emulation multiply takes 1-2 cycles where the chip took 8-32. Timing-dependent software breaks: delay loops faster; bus interleaving wrong; pin-level trace against silicon (Visual6502, MAME) diverges mid-shift.
- **Cause:** `c <= a * b;` synthesizes but violates the era-mirroring rule: the original microarchitecture had no parallel multiplier. The DSP produces correct values in the wrong cycle count.
- **Fix:** Iterative shift-add FSM whose cycle count matches the chip's documented latency. Compose from `Bit_Shifter.v` + `Adder_Subtractor_Binary.v` + shift-register gated by a down-counter. Confirm zero DSPs; add an exact-N-cycle assertion.
- **Citation:** [I] from doc 17 §2. Mechanism: FPGADesignElements `Bit_Shifter.v`, `Adder_Subtractor_Binary.v`, `Register_Pipeline_Simple.v`. Cyclone V variable-precision DSP (live URL).
- **Primary home:** [31-dsp-inference-cyclone-v.md](31-dsp-inference-cyclone-v.md)

### Resource economy

#### 27. Width-N register where consumer reads only bits `[M-1:0]`, M < N

- **Symptom:** Synthesis lists `the_register[N-1:M]` under "Removed registers"/"Stuck at 0"; fanouts carry `N-M` dead bits.
- **Cause:** High bits have no consumer. Producer sized to a generic spec width.
- **Fix:** Narrow the source to M bits. If parameterized, insert `Width_Adjuster` at the narrowing point.
- **Citation:** `references/projects/FPGADesignElements/Width_Adjuster.v:5-13 @ 2450a54`. [I].
- **Primary home:** [16-resource-and-state-economy.md](16-resource-and-state-economy.md)

#### 28. Wide bus through hierarchy where leaves ignore most bits

- **Symptom:** Fitter Routing Usage Summary shows high local-routing in modules carrying the bus; per-leaf "bits removed" warnings while producer still drives the full width.
- **Cause:** Bit-justification violation propagated through hierarchy. Producer sized to its own natural width; bus passes through unchanged.
- **Fix:** Narrow at the producer (union of consumer widths) or at the boundary closest to the producer with `Width_Adjuster`. Avoid narrowing at the leaf.
- **Citation:** [I]; `references/projects/FPGADesignElements/Word_Reducer.v:1-15 @ 2450a54`.
- **Primary home:** [16-resource-and-state-economy.md](16-resource-and-state-economy.md)

#### 29. Mirror copy of a signal in two modules instead of fanout

- **Symptom:** Two registers with identical RHS and reset values. Synthesis "Merged registers" lists them merged; Fitter Report Fanout exceeds the number of consumers.
- **Cause:** Only one copy holds state non-redundantly. Author replicated rather than routing as fanout.
- **Fix:** Delete one; drive the consumer via a port from the survivor. If the two copies break distinct critical paths (close-to-A vs close-to-B), they are not mirrors — both legitimate.
- **Citation:** [I]; Quartus "Merged registers" report. Yosys analog `references/extracted_text/zipcpu/class_verilog.txt:2156, 4479-4515 @ 2026-05-20`.
- **Primary home:** [16-resource-and-state-economy.md](16-resource-and-state-economy.md)

#### 30. Counter wider than `$clog2(N)` for a mod-N counter

- **Symptom:** Synthesis lists `counter[N-1:M]` (`M=$clog2(N)`) under "Removed registers"; carry chain longer than needed; fanout carries dead bits.
- **Cause:** High bits never toggle. Counter declared at a power-of-two convenience width.
- **Fix:** `logic [$clog2(N)-1:0] count_q;`. For non-PoT N, add `if (count_q == N-1) count_q <= '0;`.
- **Citation:** `references/projects/FPGADesignElements/Counter_Binary.v:8-9, 23-45 @ 2450a54`.
- **Primary home:** [16-resource-and-state-economy.md](16-resource-and-state-economy.md)

#### 31. Sign bit carried where unsigned is provably sufficient

- **Symptom:** A `logic signed [W-1:0]` consumed only by readers comparing against `0` or another unsigned value; no arithmetic produces negative results. Carry chain one position longer than needed.
- **Cause:** No protocol field requires sign, no consumer reads it as sign. Author declared `signed` defensively or as a software-style habit.
- **Fix:** Re-declare unsigned. Audit consumers for `signed_x < 0`. If carry chain matters, confirm in TimeQuest the delay drops by one carry-position.
- **Citation:** `references/raw/fpgacpu/verilog_coding_standard.html:198-205, 224-232 @ 2026-05-20`. [V].
- **Primary home:** [16-resource-and-state-economy.md](16-resource-and-state-economy.md)

### Era faithfulness

#### 32. Replaced a shared resource with N parallel copies when shared closed timing

- **Symptom:** Synthesis shows N adders/shifters where the chip's schematic shows one; ALM area several × baseline; fmax comfortable but software depending on per-cycle bus contention (DMA stalling CPU) behaves wrong.
- **Cause:** "Shared closed timing, but I un-shared it for area headroom." Shared resource implies bus-arbitration timing the chip's software depends on.
- **Fix:** Revert to shared + arbiter (`Arbiter_Priority.v` / `Arbiter_Round_Robin.v`). If fmax is the issue, add an internal pipeline stage **without changing external cycle counts**. If timing still doesn't close, divide the FPGA clock or use a slower derived clock.
- **Citation:** FPGADesignElements `Arbiter_Priority.v`; [I].
- **Primary home:** [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md)

#### 33. Added pipeline stages that change observable cycle counts at the external interface

- **Symptom:** Pin-level traces show FPGA taking N+1 cycles where the chip took N. Cycle-exact software (raster demos, DPCM audio, copy-protection, DMA) fails.
- **Cause:** Internal pipelining leaked across the external-interface boundary. Pin-level cycle count is locked; internal pipelining is free **only if** the external observable is unchanged.
- **Fix:** Identify the pipeline register delaying the observable; move it inside an existing externally-observable cycle, or close timing another way (operand pre-decode, narrower comparators, QSF registered I/O). Re-run cycle-trace.
- **Citation:** [15-pipelines-and-latency-thinking.md](15-pipelines-and-latency-thinking.md); [I].
- **Primary home:** [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md)

#### 34. Linear "software" state machine instead of mirroring the chip's bus/control structure

- **Symptom:** One large FSM with linear `FETCH→DECODE→EXECUTE_*→WRITEBACK` states — a transliteration of an emulator's main loop. No separately identifiable ALU, register file, bus; control and datapath fused into one `case`. Modules don't correspond to die-blocks.
- **Cause:** Pre-RTL plan built from the emulator's main loop rather than the chip's bus/control structure.
- **Fix:** Rebuild the plan from documented bus/control structure: microcode ROM/PLA, ALU, register file, bus(es), memory controller, address decoder, each a separate module. Each module's top comment cites the chip subsystem it mirrors. Control style (microcoded vs hardwired) follows the chip.
- **Citation:** `library/topics/01_hardware_mindset_parallelism.md` (red-flag list); FPGACPU `system_design_standard.html`; [I].
- **Primary home:** [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md)

#### 35. 16/32-bit datapath in an 8-bit chip emulation

- **Symptom:** Synthesis shows a 16/32-bit ALU and bus in an 8-bit chip's core; multi-byte operations complete in one FPGA cycle instead of multiple chip cycles; flags at the pin are wrong (overflow computed from a 16-bit result, not the 8-bit byte the chip saw).
- **Cause:** Datapath widened "for convenience." An 8-bit chip's datapath is 8 bits.
- **Fix:** Narrow to the chip's documented width. Compute carry/borrow/overflow/sign exactly as the chip did — byte-by-byte over multiple cycles with explicit carry registers; multi-byte cycle counts match the original.
- **Citation:** Bundle convention; [I].
- **Primary home:** [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md)

#### 36. Multi-port memory where the original had single-port + bus arbitration

- **Symptom:** Synthesis shows true-dual-port M10K where original had single-port + arbitration. Operations that would have collided (CPU fetch racing video refresh) complete simultaneously.
- **Cause:** Dual-port M10K used because easy; era's bus arbitration discarded.
- **Fix:** Single-port M10K (or single-port + simple-DP per the chip's topology, see doc 30) + bus arbiter (`Arbiter_Priority.v` / `Arbiter_Round_Robin.v`) mirroring the chip's grant priority.
- **Citation:** Intel Cyclone V Device Handbook Vol 1 embedded memory (live URL); FPGADesignElements `Arbiter_Priority.v`; [I].
- **Primary home:** [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md)

#### 37. Parallel barrel shifter where original used a 1-bit shifter over multiple cycles

- **Symptom:** Synthesis shows wide barrel shifter (or DSP variable shift) completing shift-by-N in one cycle; chip's shift-by-N took N cycles; timing-dependent software runs faster and breaks.
- **Cause:** Era used 1-bit-per-cycle shifters; barrel shifters were expensive in silicon. Mirroring requires the era's cycle count.
- **Fix:** 1-bit shifter inside an FSM gated by a down-counter loaded from the opcode's shift-amount; completes in exactly N cycles.
- **Citation:** FPGADesignElements `Bit_Shifter.v`; cross-ref doc 31; [I].
- **Primary home:** [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md)

### Handshake / FIFO

#### 38. FIFO without producer-side backpressure

- **Symptom:** FIFO overflows under burst load; producer drops values silently; "works in sim, fails on hardware" because the TB producer never bursts at the actual upstream rate.
- **Cause:** Producer not wired to honor `s_axis_tready` (or `!full`): unconnected, tied `1'b1`, missing stall-logic, or elided "FIFO is deep enough."
- **Fix:** Route `s_axis_tready` back to the producer; obey handshake rules (payload-stable while `!ready`, work on `valid && ready`, no valid-drop). If producer cannot stall (fixed-rate ADC), size FIFO never to fill **and** export an overflow flag.
- **Citation:** `references/projects/verilog-axis/rtl/axis_fifo.v:217 @ 48ff7a7` (`s_axis_tready` from `!full`); cross-ref doc 20.
- **Primary home:** [22-fifos-synchronous-and-asynchronous.md](22-fifos-synchronous-and-asynchronous.md)

#### 39. Variable bit-select with non-constant index

- **Symptom:** `a[idx]` or `a[idx +: K]` with signal `idx`; unexpectedly large mux; TimeQuest reports bit-select as critical path on a wide operand.
- **Cause:** Bit-indexing treated as O(1). In hardware, `a[idx]` is a `WORD_WIDTH`-input mux; `a[idx +: K]` is K parallel muxes; cost scales with operand width.
- **Fix:** **Constant index** when possible — unroll FSM case branches so each references a constant slice. **Register the index, pipeline the mux** otherwise. **One-hot select** when the index comes from a one-hot encoder (`Multiplexer_One_Hot`). **Restructure** — wide operands may hide a missing shift register.
- **Citation:** `references/projects/FPGADesignElements/Multiplexer_Binary_Behavioural.v:1-104 @ 2450a54`; Intel coding guidelines (live URL).
- **Primary home:** [32-arithmetic-patterns-and-operator-cost.md](32-arithmetic-patterns-and-operator-cost.md)

### Spec §9 addendum — Coding discipline

#### 40. No pre-RTL plan — coding begins immediately

- **Symptom:** Repeated rewrites; CDC discovered late; pipeline depth changes break downstream; fmax surprises at first P&R.
- **Cause:** Jumped to `always_ff` without naming clocks, reset, throughput, latency, or resource strategy.
- **Fix:** Stop. Write the plan per doc 10 §3.1. Resume only when a reviewer can answer throughput/latency/resource questions without seeing the RTL.
- **Citation:** `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt` p2 "Before You Begin" @ 2016-11; p3 Table 2 item 1.
- **Primary home:** [10-hardware-mindset-and-microarchitecture.md](10-hardware-mindset-and-microarchitecture.md)

#### 41. Software-algorithm transliteration

- **Symptom:** Nested `if/else`, "do step X, then Y" comments, scratch variables read multiple times, monolithic `always_ff` driving unrelated outputs. Poor fmax; messy schematic.
- **Cause:** Author translated a C/Python reference line-by-line, treating `always` as a function body.
- **Fix:** Discard. Redo the pre-RTL plan: parallel state, per-cycle work, where the reference serialized only because it had one ALU. Reshape as datapath + control + interface.
- **Citation:** [I] from FPGACPU `system_design_standard.html:93-100`; `library/topics/01_hardware_mindset_parallelism.md` §"Avoid Software-Shaped RTL".
- **Primary home:** [10-hardware-mindset-and-microarchitecture.md](10-hardware-mindset-and-microarchitecture.md)

#### 42. Module hierarchy mirrors call-graph of a software port

- **Symptom:** Top module `main`; submodules named after C functions; signals like function arguments. Linear chains; arbitrary CDC boundaries; no reuse.
- **Cause:** Author treated module instantiation as function call.
- **Fix:** Rebuild along hardware lines: Core (logic) / Instance (this FPGA) / Adapter (board I/O) / Shim (pinout). For emulation: Core mirrors the chip; Adapter wraps the framework; Shim is the pin file.
- **Citation:** `references/raw/fpgacpu/system_design_standard.html:93-100, 144-201 @ 2026-05-20`.
- **Primary home:** [10-hardware-mindset-and-microarchitecture.md](10-hardware-mindset-and-microarchitecture.md)

#### 43. Reset asserted by a glitching combinational signal

- **Symptom:** Sporadic mid-operation resets in hardware never reproducing in sim; logic appears to reset itself at random.
- **Cause:** The async-reset input is driven by combinational logic that can glitch (AND of unrelated status bits, comparator output). A combinational glitch on the async-clear pin asserts reset immediately, no clock edge needed.
- **Fix:** Register the reset source. A registered output cannot glitch intra-cycle.
- **Citation:** FPGACPU `references/raw/fpgacpu/verilog_coding_standard.html:856-860`. [V].
- **Primary home:** [11-clocking-resets-and-cyclone-v-clock-networks.md](11-clocking-resets-and-cyclone-v-clock-networks.md)

#### 44. `always_comb` with self-referential variable read

- **Symptom:** Tool passes, but a re-read of a variable inside the same `always_comb` produces stale values. Behaviour differs between simulators (both LRM-compliant).
- **Cause:** SystemVerilog excludes LHS-assigned names from `always_comb`'s implicit sensitivity list. `c = b; b = a;` does NOT propagate `a → b → c` in the same time step; `c` gets the *previous* `b`.
- **Fix:** Write top-down so any RHS reference appears before the LHS assignment of that name. Use `_d`/`_q` discipline so an assigned `_d` is never the same name as a read `_q`.
- **Citation:** VerilogPro `systemverilog_always_comb_always_ff.html:302-330`.
- **Primary home:** [12-synthesizable-sv-subset.md](12-synthesizable-sv-subset.md)

### Spec §9 addendum — FSMs

#### 45. FSM output decoder combinational but downstream consumer assumes registered

- **Symptom:** Glitches on FSM outputs drive a downstream flop's data input as the next-state decoder transitions; flop captures the wrong value on the next edge if setup is barely met.
- **Cause:** Two-block FSM emits combinational outputs by design; downstream module declares its input port as if registered.
- **Fix:** Move to a three-block FSM with registered outputs, or register at the downstream boundary. Document output timing in the module header.
- **Citation:** Cummings FSM `:478-505`; [I] for the consumer-side discipline.
- **Primary home:** [14-finite-state-machines.md](14-finite-state-machines.md)

### Spec §9 addendum — Datapath & pipelining

#### 46. Data freezes on stall but `valid` keeps advancing (or vice versa)

- **Symptom:** Under backpressure, downstream's input data is stale but `valid` is high; consumer processes the stale word as new. Or: data advances but `valid` froze, dropping live data.
- **Cause:** Stall logic applied to one of the pair but not the other. Often `(data, valid)` written by two `always_ff` blocks with subtly different enable expressions.
- **Fix:** Put `(data, valid)` in the same `always_ff` gated by the same `ce` enable.
- **Citation:** FPGADesignElements `Pipeline_FIFO_Buffer.v:326-341` (same clock_enable across data and valid). [V].
- **Primary home:** [15-pipelines-and-latency-thinking.md](15-pipelines-and-latency-thinking.md)

### Spec §9 addendum — Handshake

#### 47. Valid drops before transfer

- **Symptom:** Simulator-only "transfer" that never reaches the consumer. Property `valid && !ready |=> valid` fires when the consumer happens to stall on the same cycle the producer's `valid` source briefly drops.
- **Cause:** `valid` is a combinational function of producer-internal state changing independently of whether a handshake completed. Canonical form: `valid = (count != 0)` with `count` advanced every cycle rather than only on `valid && ready`.
- **Fix:** Gate every state transition affecting the handshake on `handshake_complete = valid && ready`. The producer template: `valid` and payload register change only when `!valid || ready`.
- **Citation:** FPGACPU `references/raw/fpgacpu/handshake.html:159-198`; ZipCPU `references/raw/zipcpu/axi_rules.html:146-151` (rule 4).
- **Primary home:** [20-ready-valid-handshakes.md](20-ready-valid-handshakes.md)

#### 48. Payload changes while `valid && !ready`

- **Symptom:** Corrupted datum on a delayed transfer. Consumer's payload register holds a value never bit-for-bit coherent with the `valid` it acknowledged. Property `valid && !ready |=> $stable(payload)` fires.
- **Cause:** Producer treats `valid` as a one-cycle pulse and advances payload-source state every clock, regardless of consumer accept. Symmetric to AP #47 but on payload instead of valid.
- **Fix:** Hold the payload register on the same gate as `valid` — follow the producer template, or insert a skid buffer at the producer's output to absorb stalls.
- **Citation:** FPGACPU `handshake.html:130-134`; ZipCPU `axi_rules.html:461-486`; wb2axip `skidbuffer.v:281-284 @ df8e764` (`IDATA_HELD_WHEN_NOT_READY` property).
- **Primary home:** [20-ready-valid-handshakes.md](20-ready-valid-handshakes.md)

#### 49. `valid` depending combinationally on `ready` without a skid buffer

- **Symptom:** Quartus reports a combinational loop in Analysis & Synthesis, or — if the loop is broken by inferred latch / tool transform — the no-valid-drop rule fires intermittently when `ready` momentarily lowers.
- **Cause:** Producer asserts `valid = have_data && ready;` — intuitive but wrong; places the `valid` decision combinationally downstream of `ready`, violating the directional rule.
- **Fix:** Insert a skid buffer between the producer's internal logic and external `valid`/payload outputs. This is the canonical reason skid buffers exist on FPGAs.
- **Citation:** ZipCPU `axi_rules.html:152-162` (rule 5: "xREADY must be registered. Use a skidbuffer if necessary"); FPGACPU `handshake.html:59-72`.
- **Primary home:** [20-ready-valid-handshakes.md](20-ready-valid-handshakes.md)

#### 50. `ready` driven by the producer, or `valid` driven by the consumer

- **Symptom:** Quartus reports multiple drivers on the handshake wire, or the design "works" forward but back-pressure produces nonsense the consumer interprets as data.
- **Cause:** Mixed naming conventions in one project — `i_`/`o_` (direction) substituted for `s_`/`m_` (role) at a module boundary inverts drive direction.
- **Fix:** Pick ONE naming style per project and apply uniformly. `valid` and payload always source→destination; `ready` always returns.
- **Citation:** [I] from FPGACPU `handshake.html:51-57`.
- **Primary home:** [20-ready-valid-handshakes.md](20-ready-valid-handshakes.md)

#### 51. Skid buffer registers forward path only, not `ready`

- **Symptom:** Writer pipes `valid` and `data` through a register but leaves the consumer-side `ready` driving the producer-side `ready` through a wire. Sim shows one extra cycle of latency, but ready-path critical delay is identical.
- **Cause:** Misunderstanding that a skid buffer must register **both** directions — payload outputs **and** upstream `ready`. Registering only forward adds latency without timing benefit.
- **Fix:** Use the canonical module. The three load-bearing lines from `skidbuffer.v`: `r_valid` flop, `r_data` flop, and `assign o_ready = !r_valid;`. Verify in TimeQuest the ready-path critical chain now starts at `r_valid`.
- **Citation:** `references/projects/wb2axip/rtl/skidbuffer.v:9-14, 134-141, 147-153, 160 @ df8e764`.
- **Primary home:** [21-skid-buffers-and-register-slices.md](21-skid-buffers-and-register-slices.md)

#### 52. Depth-greater-than-2 storage inserted as a "skid buffer"

- **Symptom:** A 4-, 8-, or 16-deep FIFO is dropped in because "the ready path was failing timing"; another FIFO is added downstream later, doubling area and latency without confirming where the comb chain actually breaks.
- **Cause:** Conflation of skid buffer with FIFO. Depth-2 with `o_ready = !r_valid` is the smallest correct timing fix; depth > 2 with the same backpressure semantics is a FIFO for rate decoupling, not breaking comb chains.
- **Fix:** Use the 2-deep skid buffer first. Confirm in TimeQuest the chain moved. Escalate to deeper FIFO only if rate decoupling is also needed.
- **Citation:** [I] from wb2axip `skidbuffer.v:98, 129 @ df8e764` and FPGADesignElements `Pipeline_Skid_Buffer.v:8-9 @ 2450a54`.
- **Primary home:** [21-skid-buffers-and-register-slices.md](21-skid-buffers-and-register-slices.md)

#### 53. Under-sized FIFO depth for worst-case burst

- **Symptom:** FIFO stalls the producer in steady state; throughput target missed under measured worst-case input rates even though individual modules meet local timing. Discovered late in system testing.
- **Cause:** Depth was guessed ("power of two, looks fine") rather than computed from producer worst-case burst × consumer worst-case stall window.
- **Fix:** Re-derive from the design plan. Minimum depth = `producer_rate × consumer_worst_stall_window`; add margin. Confirm depth × width fits the MLAB/M10K budget.
- **Citation:** [I] from doc 22's depth-from-backpressure rule.
- **Primary home:** [22-fifos-synchronous-and-asynchronous.md](22-fifos-synchronous-and-asynchronous.md)

#### 54. Over-sized FIFO depth "to be safe"

- **Symptom:** Deep FIFOs never approaching full in any observed workload; M10K utilisation 70%+ with FIFOs holding orders of magnitude more depth than used.
- **Cause:** FIFO treated as defensive plumbing — "more is safer" — rather than a sized buffer between a producer with known worst-case burst and a consumer with known worst-case stall.
- **Fix:** Size to worst-case burst + measurement margin (typically <2×, not 10× or 100×). When the worst case fits in flops or MLAB, use that primitive instead of M10K.
- **Citation:** [I]; cross-ref doc 16's four-justifications check.
- **Primary home:** [22-fifos-synchronous-and-asynchronous.md](22-fifos-synchronous-and-asynchronous.md)

### Spec §9 addendum — CDC

#### 55. One-flop synchronizer

- **Symptom:** Intermittent hardware failures correlated with temperature, voltage, or clock drift that pass in sim; bugs that "fix themselves" between attempts.
- **Cause:** A single destination flop has no margin for the first flop's metastable settling. Downstream logic samples the metastable output and propagates indeterminate state.
- **Fix:** Use the 2FF (or deeper) chain in a dedicated module so Quartus recognizes and reports it.
- **Citation:** Cummings SNUG 2008 CDC (live URL `http://www.sunburst-design.com/papers/CummingsSNUG2008Boston_CDC.pdf`); VerilogPro CDC Part 1 `references/raw/verilogpro/cdc_part1.html:283 @ 2022-09-29`.
- **Primary home:** [23-cdc-single-bit.md](23-cdc-single-bit.md)

#### 56. Synchronizer not in a dedicated module

- **Symptom:** Quartus Metastability Analysis doesn't list the chain; no MTBF reported. Tools warn about retiming/replication/merging. The chain works in sim but field-tests show drift consistent with it being broken by optimisation.
- **Cause:** Two flops mixed with unrelated logic (or scattered across modules) prevents the Quartus pattern-matcher from recognising the synchronizer. Tools may retime, replicate one flop for fanout, or pack a flop into a DSP/BRAM input register.
- **Fix:** Encapsulate every single-bit CDC in `CDC_Bit_Synchronizer`. Apply `(* PRESERVE *)`, `(* useioff = 0 *)`, and `(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION \"FORCED IF ASYNCHRONOUS\"" *)`.
- **Citation:** Intel *Managing Metastability with the Quartus Prime Software* (live URL); attribute pattern `references/projects/FPGADesignElements/CDC_Bit_Synchronizer.v:115-124 @ 2026-05-20`.
- **Primary home:** [23-cdc-single-bit.md](23-cdc-single-bit.md)

#### 57. Pulse fed into a level synchronizer

- **Symptom:** Destination misses events or sees them twice; counter mismatches, lost interrupts, "stuck" handshakes that work most of the time.
- **Cause:** Source pulse shorter than (or comparable to) destination clock period; the 2FF chain may sample the pulse 0, 1, or 2 times depending on phase. The 2FF chain crosses *levels*, not edges.
- **Fix:** On the source side, toggle a level register from the source pulse. 2FF the toggle. Any-edge detect the synchronized toggle to recover a single-cycle pulse. Use `CDC_Pulse_Synchronizer_2phase`.
- **Citation:** VerilogPro CDC Part 1 `references/raw/verilogpro/cdc_part1.html:315 @ 2022-09-29`; pattern `references/projects/FPGADesignElements/CDC_Pulse_Synchronizer_2phase.v:21-41 @ 2026-05-20`.
- **Primary home:** [23-cdc-single-bit.md](23-cdc-single-bit.md)

#### 58. Synchronizer with no SDC declaration

- **Symptom:** Timing Analyzer reports large negative slack between two clocks; designers insert pipeline registers that never converge timing; placer distorts unrelated placement to meet a fictional requirement.
- **Cause:** TimeQuest computing setup/hold across an inherently untimed path. The destination capture edge has no fixed phase relationship to the source launch edge.
- **Fix:** Add `set_clock_groups -asynchronous -group { src_clk } -group { dst_clk }` (preferred) or `set_false_path -from [get_clocks src_clk] -to [get_clocks dst_clk]`. Confirm in the Inter-Clock Paths report.
- **Citation:** Intel Quartus Standard Timing Analyzer User Guide (live URL `https://docs.altera.com/r/docs/683068/current`); SDC syntax in Intel *Managing Metastability*.
- **Primary home:** [23-cdc-single-bit.md](23-cdc-single-bit.md)

#### 59. Combinational logic between source register and first synchronizer flop

- **Symptom:** Quartus MTBF much worse than chain length predicts; spurious destination pulses on data-stable cycles; chain works under slow source activity, breaks under load.
- **Cause:** Combinational glitches at the synchronizer input (multi-path convergence in source-side logic) increase effective transition rate. A destination edge sampling a glitch becomes a real spurious destination pulse.
- **Fix:** Place a register in the source domain immediately before the synchronizer module, with no logic between that register and `bit_in`. Combinational logic happens *before* the launch register.
- **Citation:** FPGADesignElements `CDC_Bit_Synchronizer.v:62-74 @ 2026-05-20`; VerilogPro CDC Part 1 `references/raw/verilogpro/cdc_part1.html:295 @ 2022-09-29`.
- **Primary home:** [23-cdc-single-bit.md](23-cdc-single-bit.md)

#### 60. MCP without payload-stable hold

- **Symptom:** Destination intermittently captures the *next* payload one transfer late, or a partially-updated payload mixing bits from two consecutive writes.
- **Cause:** Producer modifies the payload register before destination capture — before the source's `ack`/return-toggle has been observed. The unsynchronized payload bus changes mid-capture.
- **Fix:** Hold the payload stable from before the load-toggle reaches the destination synchronizer until after the return-toggle settles in the source domain. FPGADesignElements `CDC_Word_Synchronizer` enforces this structurally by latching `sending_data` on `sending_handshake_complete` and releasing only on `accept_next_word`.
- **Citation:** verilogpro CDC part 2 `references/raw/verilogpro/cdc_part2.html @ 2026-05-20`; `references/projects/FPGADesignElements/CDC_Word_Synchronizer.v:152-176, 300-315 @ 2026-05-20`.
- **Primary home:** [24-cdc-multi-bit.md](24-cdc-multi-bit.md)

#### 61. MCP used for high-rate data

- **Symptom:** Producer stalls more than it transmits; throughput collapses to ≈ one transfer every 5–8 sending clock cycles. Profiling shows the producer `ready`-blocked most of the time.
- **Cause:** MCP round-trip latency is structurally bounded by 2-phase 2FF synchronization in each direction. For occasional words invisible; for streaming, the bottleneck.
- **Fix:** Use a **dual-clock async FIFO** instead — after the initial pointer-sync latency, sustains one transfer per destination cycle. MCP is correct only when transfer rate is well below the round-trip rate.
- **Citation:** verilogpro CDC part 2 `@ 2026-05-20`; FPGADesignElements `CDC_Word_Synchronizer.v:58-91 @ 2026-05-20`.
- **Primary home:** [24-cdc-multi-bit.md](24-cdc-multi-bit.md)

#### 62. Async FIFO with empty/full computed against un-Gray-coded synchronized pointer

- **Symptom:** FIFO works at low throughput and fails (overflow, underflow, false empty/full) under sustained throughput or specific clock ratios.
- **Cause:** Pointer correctly Gray-coded and synchronized, but empty/full comparator written as if synchronized pointer were binary, or local pointer is binary while remote is Gray.
- **Fix:** Keep the synchronized opposite-domain pointer in Gray and compare Gray against Gray. Full: `wr_ptr_gray_reg == (rd_ptr_gray_sync2_reg ^ {2'b11, {ADDR_WIDTH-1{1'b0}}})` (two top bits flipped — Gray equivalent of "binary MSB different, rest same"). Derive any local binary from the local binary counter, not Gray→binary conversion.
- **Citation:** Cummings SNUG 2002 SJ (live URL); `references/projects/verilog-axis/rtl/axis_async_fifo.v:263-267 @ 48ff7a7`.
- **Primary home:** [24-cdc-multi-bit.md](24-cdc-multi-bit.md)

### Spec §9 addendum — Resource inference (Cyclone V)

#### 63. Async read inferred as area blowup, not as M10K

- **Symptom:** Combinational read; Fitter shows zero M10K consumed and unexpectedly large LUT count (sometimes 100× registered-read). Storage that should be one M10K is thousands of LUTs as a wide combinational mux.
- **Cause:** M10K and MLAB **require registered read** for inference. `assign data_out = mem[address];` does not match the template — Quartus uses distributed LUT RAM (`DEPTH × WIDTH` area).
- **Fix:** Register the read inside `always @(posedge clk)` as `q <= mem[read_address];`. Cost is one cycle of read latency, absorbed via the pipeline-around-RAM rule.
- **Citation:** Intel *Inferring Memory Functions* §3.1, §3.2 templates @ 2026-05-20. Note: FPGADesignElements `RAM_Multiported_LE.v` uses combinational reads intentionally as a flop-based pattern.
- **Primary home:** [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md)

#### 64. Init file missing at synthesis (works in sim, all zeros on hardware)

- **Symptom:** Sim works; hardware ROM reads all zeros. Boot ROM never branches; palette black; LUT returns garbage. "The file is there" but Quartus didn't find it.
- **Cause:** `$readmemh` path not relative to the Quartus project directory, or file not in the project source list. Sim works because the simulator resolves the path against its own working directory.
- **Fix:** Use a project-relative path (`"rom_contents.hex"`, not `"/abs/path/…"` or `"../sim/…"`). Add to the source list. Verify the Fitter log "Memory initialization data loaded from …" line.
- **Citation:** Intel *Specifying Initial Memory Contents at Power-Up* @ 2026-05-20 (live URL).
- **Primary home:** [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md)

#### 65. True-dual-port used where simple-dual-port would suffice

- **Symptom:** Fitter shows higher M10K count than expected (two M10Ks where one would fit). May show routing congestion.
- **Cause:** True-dual-port instantiated for 1W1R. True-DP costs both M10K write slots; for 1W1R, simple-DP packs two such memories into one M10K.
- **Fix:** Switch to simple-dual-port. Re-check the plan — are there really two writers, or is one a refresh path muxable onto the single write side?
- **Citation:** Cyclone V Device Handbook Vol. 1 embedded-memory-modes (live URL); FPGADesignElements `RAM_Simple_Dual_Port.v` vs `RAM_True_Dual_Port.v @ 2450a54`.
- **Primary home:** [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md)

#### 66. Mixed-signedness multiply

- **Symptom:** Wrong values on negative operands. Sign flips at boundaries (-1×-1 → large positive); 2× factors on MSB-set values. Sim passes for small-positive, fails at boundaries.
- **Cause:** One operand `signed`, the other not. Verilog resolves mixed-signed as unsigned. Even with both inputs `signed`, `wire mult_out` (no `signed`) drops sign.
- **Fix:** `signed` end-to-end — inputs, intermediate `wire`, output `reg`. If one is genuinely unsigned, zero-extend: `wire signed [WIDTH:0] u_ext = {1'b0, unsigned_op};`.
- **Citation:** Intel *Inferring Multipliers and DSP Functions* (live URL); FPGADesignElements `Multiplier_Binary_Parallel.v:98-100`.
- **Primary home:** [31-dsp-inference-cyclone-v.md](31-dsp-inference-cyclone-v.md)

#### 67. Constant-operand multiply consumes a DSP block

- **Symptom:** Fitter consumes a DSP block for a multiply where one operand is a synthesis-time constant (`rgb * 7'd13;` or `index * STRIDE` where `STRIDE` is a `localparam`). Strength reduction should have produced shifts-and-adds in fabric.
- **Cause:** Constant hidden from the synthesizer — flowed through a flop, blocked by a port crossing, or assembled at runtime.
- **Fix:** Convert to explicit shifts/adds, or expose the constant: use `localparam` directly in `*`, flatten hierarchy, or mark ports `parameter`. Verify zero DSP blocks.
- **Citation:** Cross-ref doc 32; Intel *Inferring Multipliers* (live URL above).
- **Primary home:** [31-dsp-inference-cyclone-v.md](31-dsp-inference-cyclone-v.md)

#### 68. Multiply wider than the DSP block without alignment logic

- **Symptom:** A multiply exceeding the variable-precision DSP block's largest mode (27×27 on Cyclone V) generates a multi-DSP composition plus a wide ALM-fabric adder tree. The adder tree runs at fabric speed; critical path runs through the alignment logic.
- **Cause:** Writer assumed one DSP can hold any width. Multi-block composition is correct, but without explicit pipelining the unbalanced alignment tree limits fmax.
- **Fix:** Split into 18×18 sub-products with register stages between adder-tree levels, or instantiate Intel multiplier IP (`altera_mult_add` / `LPM_MULT`). For ≥36×36, IP is typically right.
- **Citation:** Intel *Inferring Multipliers* (live URL above); Cyclone V Device Handbook Variable-Precision DSP (live URL).
- **Primary home:** [31-dsp-inference-cyclone-v.md](31-dsp-inference-cyclone-v.md)

### Spec §9 addendum — Datapath arithmetic

#### 69. Silent overflow on accumulator

- **Symptom:** Counter/accumulator wraps mid-computation; data corrupted; sim "almost right except for high-magnitude inputs."
- **Cause:** Accumulator at width W receives K additions of W-bit values; sums exceeding `2^W - 1` (unsigned) or `2^(W-1)` (signed) wrap silently. No saturation, no carry-out check.
- **Fix:** Size to `W + $clog2(K)` (cross-ref doc 16 for width-justification), or use the saturating-adder pattern clamping to `[limit_min, limit_max]` with `at_limit_*`/`over_limit_*` flags.
- **Citation:** `references/projects/FPGADesignElements/Adder_Subtractor_Binary_Saturating.v:1-40, Accumulator_Binary_Saturating.v:27-35 @ 2450a54`.
- **Primary home:** [32-arithmetic-patterns-and-operator-cost.md](32-arithmetic-patterns-and-operator-cost.md)

#### 70. Wide combinational mux on the critical path

- **Symptom:** Large `case` / chain of `?:` selects one of many wide payloads in a single combinational cycle; TimeQuest reports the case-selector-to-payload as worst-slack; fmax below target.
- **Cause:** Treated as one combinational stage. For N > 8 inputs, mux logic cannot fit in one 6-LUT per output bit (4:1 is "free", 8:1 is warning), so the synthesizer stacks LUT layers.
- **Fix:** Pipeline into smaller selections; or restructure as `Multiplexer_One_Hot` when a one-hot selector is naturally available. Cross-ref doc 15 and AP #16.
- **Citation:** `references/raw/fpgacpu/verilog_coding_standard.html:665-670 @ 2026-05-20`; `references/projects/FPGADesignElements/Multiplexer_One_Hot.v:38-77 @ 2450a54`.
- **Primary home:** [32-arithmetic-patterns-and-operator-cost.md](32-arithmetic-patterns-and-operator-cost.md)

#### 71. Mixed-width arithmetic

- **Symptom:** Results truncated or sign-extended unexpectedly; sim gives "wrong by powers of two"; CAD tool emits dozens of width-mismatch warnings.
- **Cause:** N-bit expression assigned to M-bit target without explicit width, or different-width operands mixed. Verilog's implicit extension is silent and not always what the writer expected. `signed` is contagious: one unsigned operand forces the whole expression unsigned.
- **Fix:** Declare widths on every assignment; use `Width_Adjuster` (or `{N{1'b0}, x}` / `{ {N{x[W-1]}}, x }`) before arithmetic; treat every width-mismatch warning as a defect.
- **Citation:** `references/raw/fpgacpu/verilog_coding_standard.html:198-205 @ 2026-05-20`; `references/projects/FPGADesignElements/Adder_Subtractor_Binary.v:21-26 @ 2450a54`; cross-ref doc 12.
- **Primary home:** [32-arithmetic-patterns-and-operator-cost.md](32-arithmetic-patterns-and-operator-cost.md)

### Timing closure & verification (Phase 2 addendums, docs 40/41)

#### 72. SDC not written; design runs unconstrained

- **Symptom:** Quartus reports a long "Unconstrained Paths" section; fmax empty or astronomical; design works at low external clock rates and fails silently when raised, with no compile-time warning.
- **Cause:** SDC treated as deployment chore rather than part of the design. No `create_clock` → no period to compare against; no `set_input_delay`/`set_output_delay` → I/O paths not in the report.
- **Fix:** Write a minimal SDC from day one. Re-run `check_timing` after every edit; confirm no "no clock" / "missing input/output delays" items remain.
- **Citation:** `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt:866`; Quartus Standard Timing Analyzer User Guide (live URL `https://docs.altera.com/r/docs/683068/current`).
- **Primary home:** [40-timing-closure-and-sdc.md](40-timing-closure-and-sdc.md)

#### 73. I/O register not placed in IOE; large clock-to-pad delay

- **Symptom:** Setup slack on input pins or hold slack on output pins marginal/negative despite low fabric utilization; failing path shows the register at a fabric LAB rather than I/O column.
- **Cause:** Without `FAST_INPUT_REGISTER`/`FAST_OUTPUT_REGISTER`, the fitter places the register wherever it routes best — usually not the IOE.
- **Fix:** Add `set_instance_assignment -name FAST_INPUT_REGISTER ON -to <pin>` (and `FAST_OUTPUT_REGISTER`/`FAST_OUTPUT_ENABLE_REGISTER`); check the Fitter I/O section for IOE placement.
- **Citation:** `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt:592`; Quartus Standard User Guide (live URL).
- **Primary home:** [40-timing-closure-and-sdc.md](40-timing-closure-and-sdc.md)

#### 74. `set_false_path` used to make a real critical path "go away"

- **Symptom:** Timing Analyzer clean; design fails intermittently in hardware under temperature/voltage stress, correlated with the false-pathed signal.
- **Cause:** `set_false_path` applied to an inconvenient path, not a truly asynchronous one. A false path is a *correctness claim*; used as a timing fix it silently corrupts data.
- **Fix:** Remove the constraint and pipeline the path; or, if it is truly a CDC, route through a documented synchronizer and cut at the synchronizer's endpoints with `-to` (`references/projects/verilog-axis/syn/quartus/sync_reset.sdc:27`).
- **Citation:** `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt:866`; Quartus Timing Analyzer User Guide (live URL).
- **Primary home:** [40-timing-closure-and-sdc.md](40-timing-closure-and-sdc.md)

#### 75. `set_multicycle_path` written without RTL evidence that data is stable for N clocks

- **Symptom:** Random failures correlated with traffic bursts; failures vanish at low frequency; Timing Analyzer reports clean setup because given N× the period to settle.
- **Cause:** Multicycle applied because the path was long, with no FSM, counter, or clock-enable proving the source register cannot change for N source-clock periods. Setup relaxed but hardware still samples every cycle.
- **Fix:** Either prove (HDL inspection plus SVA cover/assert) the source holds stable for N cycles, or remove the multicycle and pipeline. Always pair `-setup` with `-hold` (typically `N`/`N-1`) so hold analysis stays correct.
- **Citation:** `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt:888`; Quartus Timing Analyzer User Guide (live URL).
- **Primary home:** [40-timing-closure-and-sdc.md](40-timing-closure-and-sdc.md)

#### 76. Synthesis warnings ignored

- **Symptom:** Compiles cleanly. Hardware disagrees with sim. Adding `$display` "fixes" it.
- **Cause:** Ignored `latch inferred`, `register removed: no fanout`, or `node has no driver` warnings on signals the agent thought were correctly written.
- **Fix:** Read every Analysis & Synthesis warning after every compile. Each one is either fixed or annotated with a written justification. Default position: the warning is right.
- **Citation:** Intel Quartus Standard Edition User Guide: Design Recommendations (live URL).
- **Primary home:** [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md)

#### 77. Inferred resource not confirmed in Fitter report

- **Symptom:** `(* ramstyle = "M10K" *)` RAM, but timing closes 30 MHz lower than expected and M10K count is suspiciously low. Or: a DSP-intended multiplier consumes hundreds of ALMs.
- **Cause:** Synthesis honored the *request* but the Fitter dropped the resource into the wrong primitive (port-mode or RDW incompatibility). The agent didn't check.
- **Fix:** Open Fitter "Resource Utilization by Entity"; for every module expecting M10K/MLAB/DSP, confirm the count. Cross-ref docs 30 and 31.
- **Citation:** Intel Quartus Standard Edition User Guide: Design Recommendations, "Inferring RAM Functions" / "Inferring Multipliers" (live URL).
- **Primary home:** [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md)

#### 78. Testbench has no scoreboard; manual waveform inspection only

- **Symptom:** Tests "pass" because the engineer looked at the waveform. Regression reintroduces fixed bugs.
- **Cause:** Testbench drives stimulus and prints outputs but never compares to a reference. The pass/fail decision lives in the engineer's head.
- **Fix:** Every TB has (1) stimulus queue, (2) reference-model expected-output queue, (3) captured-output queue from a DUT monitor, (4) final element-by-element compare with `$fatal` on mismatch.
- **Citation:** `references/projects/verilog-axis/tb/axis_register/test_axis_register.py:99-107` (send-then-recv-then-compare pattern).
- **Primary home:** [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md)

#### 79. SVA assertion writes the bug (assertion re-implements the DUT)

- **Symptom:** All assertions pass; hardware misbehaves. The property body re-implements the same buggy computation, so the bug and check agree.
- **Cause:** Property written as recomputation ("`y` should equal `a + b`") rather than invariant ("if `valid_in && ready_in`, next cycle `count_out` is one greater"). Recomputation reproduces the bug; invariant catches it.
- **Fix:** Properties express orderings, stabilities, conservation laws — never re-implementations. Stability: "while `valid && !ready`, payload unchanged". Ordering: "after reset, `valid` low". Conservation: input-transfer count equals output-transfer count.
- **Citation:** `references/raw/zipcpu/formal_index.html`; structural form `references/projects/wb2axip/rtl/skidbuffer.v:277-289 @ df8e764`. [I].
- **Primary home:** [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md)

#### 80. `assume` used where `assert` was meant

- **Symptom:** Sim property always passes; the bug slips through. `assume` silently constrains random stimulus, so a DUT-property-as-`assume` passes vacuously.
- **Cause:** Confusion between `assume` (environment constraint limiting the formal solver) and `assert` (a property the DUT must satisfy). In simulation, `assume` against the DUT is a no-op.
- **Fix:** In non-formal sim, every DUT property is `assert`; every environment property (only meaningful under a formal solver) is `assume`.
- **Citation:** `references/raw/zipcpu/axi_rules.html:412-414` (`assume(!ARESETN)` reserved for environment, never DUT behavior). [V].
- **Primary home:** [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md)
