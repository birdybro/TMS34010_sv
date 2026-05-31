# Core Bringup Checklist (Sequential Gates)

> Bundle version: 2026-05-19
> Synthesized from §2 [C] (and operationally-hard [V]) claims across all 18 topic docs.
> Status mix: gates 1, 9, 10 lean on [V]/[I] review checks; gates 2–8 are [C]-dominant.

## Purpose

This is a sequential gate checklist: each gate must pass before the next is entered. Items are verifiable in the literal sense — a reviewer answers yes/no by reading the named source artifact (pre-RTL plan, RTL source, SDC file, Quartus Synthesis/Fitter/TimeQuest report, or testbench output). Items not invented at integration time; every check derives from a specific rule in a topic doc's §2 contract.

The checklist is the closing audit instrument for the bundle. Failing items are not waived silently — a written rationale next to the violation is the only acceptable disposition.

---

## Gate 1: Pre-RTL architecture plan complete

Build-order placement: before any RTL exists. All checks are reviewed against the written plan document (no synthesis output yet).

- [ ] A pre-RTL microarchitecture plan document exists for the module and predates any committed RTL (source: [10](10-hardware-mindset-and-microarchitecture.md) §2 [V]).
- [ ] Plan names every clock entering the module, expected frequency, and sync/async relationship (source: [10](10-hardware-mindset-and-microarchitecture.md) §2 [V] / §3.1).
- [ ] Plan names reset polarity, async-assert / sync-release expectation, and scope (source: [10](10-hardware-mindset-and-microarchitecture.md) §3.1, [11](11-clocking-resets-and-cyclone-v-clock-networks.md) §2).
- [ ] Plan names throughput target (e.g. 1 result/clk, 1 per N clk, bursty) and latency budget (source: [10](10-hardware-mindset-and-microarchitecture.md) §3.1).
- [ ] Plan declares datapath widths, signedness, and saturation/wrap/round policy for every datapath signal (source: [10](10-hardware-mindset-and-microarchitecture.md) §2 [V]).
- [ ] Plan declares resource strategy (parallel vs shared; flops vs MLAB vs M10K vs DSP) for every storage and arithmetic element (source: [10](10-hardware-mindset-and-microarchitecture.md) §2 [V]).
- [ ] Plan declares flow-control strategy (always-ready, ready/valid, FIFO, credit) at every module boundary (source: [10](10-hardware-mindset-and-microarchitecture.md) §3.1).
- [ ] If the design is an emulation core: original chip identity, datapath width, control style, bus structure, memory-port topology, and per-operation external cycle counts are all named in the plan (source: [17](17-era-faithful-microarchitecture.md) §2 pre-RTL plan addendum).

## Gate 2: Clocking and reset strategy defined

Build-order placement: at RTL skeleton, before any synthesizable always block is finalized. Checks are reviewed against the RTL source and the SDC file.

- [ ] Every flop in the design is clocked from a dedicated clock pin, a PLL output, or a recognized GCLK/RCLK/PCLK net — never from fabric combinational logic (source: [11](11-clocking-resets-and-cyclone-v-clock-networks.md) §2 [C]).
- [ ] No clock is produced by ANDing/ORing/XORing logic with a clock, by feeding a divider register's output to a downstream clock pin, or by MUXing two clocks through LUT logic (source: [11](11-clocking-resets-and-cyclone-v-clock-networks.md) §2 [C]).
- [ ] Every reset is either a synchronous clear in the destination clock or an async-asserted external reset that is re-synchronized to the destination clock for de-assertion (source: [11](11-clocking-resets-and-cyclone-v-clock-networks.md) §2 [C]).
- [ ] Reset polarity is consistent across the design; if any domain inverts, the inversion happens exactly once at the boundary and the inverted net is renamed (source: [11](11-clocking-resets-and-cyclone-v-clock-networks.md) §2 [C]).
- [ ] Clock-enable (`if (en) q <= d;`) is used wherever the original design "gated a clock"; no fabric clock gating is present (source: [11](11-clocking-resets-and-cyclone-v-clock-networks.md) §2 [V]).

## Gate 3: Coding subset compliance

Build-order placement: at every RTL commit. Reviewed against the RTL source and against the Synthesis report's latch/multi-driver warnings.

- [ ] Every source file begins with `` `default_nettype none `` (source: [12](12-synthesizable-sv-subset.md) §2 [V]).
- [ ] Every sequential block is `always_ff @(posedge clk ...)` with nonblocking (`<=`) assignments only (source: [12](12-synthesizable-sv-subset.md) §2 [C], [13](13-registers-and-combinational-blocks.md) §2 [C]).
- [ ] Every combinational block is `always_comb` with blocking (`=`) assignments only (source: [12](12-synthesizable-sv-subset.md) §2 [C], [13](13-registers-and-combinational-blocks.md) §2 [C]).
- [ ] No `always` block mixes blocking and nonblocking assignments (source: [13](13-registers-and-combinational-blocks.md) §2 [C]).
- [ ] Every signal has exactly one driver across all procedural and continuous assignments — confirmed by zero multi-driver errors at elaboration (source: [12](12-synthesizable-sv-subset.md) §2 [C], [13](13-registers-and-combinational-blocks.md) §2 [C]).
- [ ] Every signal declared inside an `always_comb` is assigned on every path (defaults at top of block + path-specific overrides); Synthesis report shows zero "latch inferred" warnings (source: [13](13-registers-and-combinational-blocks.md) §2 [C]).
- [ ] No combinational feedback loop is present; the output of a pure-combinational cone never appears in its own RHS (source: [13](13-registers-and-combinational-blocks.md) §2 [C]).
- [ ] All declared signals use `logic`, except `inout` pins which use `wire` (source: [12](12-synthesizable-sv-subset.md) §2 [C]).
- [ ] Every literal that is assigned, compared, or concatenated declares its width and base (e.g. `8'h00`, not `0`) (source: [12](12-synthesizable-sv-subset.md) §2 [C]).
- [ ] Signed arithmetic uses `logic signed` operands; mixed signed/unsigned uses an explicit cast (source: [12](12-synthesizable-sv-subset.md) §2 [C]).
- [ ] One logical concern per `always` block: reset, increment, load, sample, output-mux each get their own block — no monolithic always block (source: [13](13-registers-and-combinational-blocks.md) §2 [C]).
- [ ] State enumerations use `typedef enum logic [N-1:0] { ... }` with explicit storage type; no anonymous enums (source: [12](12-synthesizable-sv-subset.md) §2 [C]).

## Gate 4: FSM and pipeline structure justified

Build-order placement: at every RTL commit covering an FSM or pipelined block. Reviewed against RTL source plus the cycle-level schedule artifact for any pipelined block.

- [ ] Every FSM splits state-register `always_ff` from next-state/output `always_comb` (two-block partition) (source: [14](14-finite-state-machines.md) §2 [C]).
- [ ] Every FSM declares its state type with `typedef enum logic [N-1:0] { ... } <name>_e;` (source: [14](14-finite-state-machines.md) §2 [C]).
- [ ] Every FSM has a defined power-on / reset state whose value is one of the enumerated states (source: [14](14-finite-state-machines.md) §2 [C]).
- [ ] Every `case` over an FSM state has a `default:` arm (or a default-at-top assignment) that defines every output and `next_state` (source: [14](14-finite-state-machines.md) §2 [C]).
- [ ] No `casex` is used in FSM next-state logic; wildcard matching uses `case inside` or `casez` with mutually-exclusive items (source: [14](14-finite-state-machines.md) §2 [C]).
- [ ] No `// synopsys full_case` / `parallel_case` pragmas; SV `unique case` / `priority case` is used instead (source: [14](14-finite-state-machines.md) §2 [C]).
- [ ] Every pipelined data path carries a parallel `valid` bit latched by the same enable with the same depth (source: [15](15-pipelines-and-latency-thinking.md) §2 [C]).
- [ ] For any block wrapping a cycle-accurate external interface, internal pipelining changes no externally observable cycle count at the wrapped pin (source: [15](15-pipelines-and-latency-thinking.md) §2 [C], [17](17-era-faithful-microarchitecture.md) §2).
- [ ] Every pipeline register added is justified by a named critical path (TimeQuest report or known fmax target), not added "for safety" (source: [15](15-pipelines-and-latency-thinking.md) §2 [V]).
- [ ] A cycle-level schedule (stage × cycle table) exists alongside any pipelined block (source: [15](15-pipelines-and-latency-thinking.md) §2 [V]).

## Gate 5: Handshake and CDC contracts met

Build-order placement: at every RTL commit involving a handshake or domain crossing. Reviewed against RTL source, against SVA properties bound to producer modules, and (for CDC) against SDC exceptions.

- [ ] Every handshake producer holds `valid` continuously from first assertion until the handshake cycle (`valid && ready` both high) — no valid-drop (source: [20](20-ready-valid-handshakes.md) §2 [C]).
- [ ] Every handshake producer holds the payload bus stable bit-for-bit while `valid && !ready` (source: [20](20-ready-valid-handshakes.md) §2 [C]).
- [ ] Every handshake state advances only on the cycle where `valid && ready` are both asserted (source: [20](20-ready-valid-handshakes.md) §2 [C]).
- [ ] `valid` does not depend combinationally on `ready`; where the natural decision would, a skid buffer breaks the path (source: [20](20-ready-valid-handshakes.md) §2 [C], [21](21-skid-buffers-and-register-slices.md) §2 [C]).
- [ ] Every skid buffer holds exactly two storage registers (one in registered output, one in the skid register); `o_ready` is fed by a register, not a combinational chain from `i_ready` (source: [21](21-skid-buffers-and-register-slices.md) §2 [C]).
- [ ] Every FIFO instance preserves the §20 handshake rules on both its producer and consumer ports (source: [22](22-fifos-synchronous-and-asynchronous.md) §2 [C]).
- [ ] Every async FIFO crossing two clock domains uses Gray-coded read and write pointers, each through a 2-flop synchronizer chain in the opposite domain (source: [22](22-fifos-synchronous-and-asynchronous.md) §2 [C], [24](24-cdc-multi-bit.md) §2 [C]).
- [ ] In every async FIFO, `full` and `empty` are derived in their own clock domain from the local pointer and the synchronized opposite pointer — never from the raw opposite-domain pointer (source: [22](22-fifos-synchronous-and-asynchronous.md) §2 [C], [24](24-cdc-multi-bit.md) §2 [C]).
- [ ] Every async single-bit crossing passes through a dedicated 2-flop synchronizer module with no combinational logic between the two flops (source: [23](23-cdc-single-bit.md) §2 [C]).
- [ ] Every CDC synchronizer module is tagged with the vendor synchronizer attribute so the Quartus metastability analyzer recognizes it (source: [23](23-cdc-single-bit.md) §2 [C]).
- [ ] Every CDC synchronizer is fed directly from a source-domain register with no combinational logic between that register and the first synchronizer flop (source: [23](23-cdc-single-bit.md) §2 [C]).
- [ ] Every source-domain pulse that must cross to the destination domain is converted to a toggle, 2FF-synchronized, and edge-detected in the destination — never fed raw into a 2FF chain (source: [23](23-cdc-single-bit.md) §2 [C]).
- [ ] Only one bit at a time crosses any given async clock-domain boundary via 2FF synchronizers; multi-bit values cross as Gray-coded counters or via MCP/word-handshake (source: [23](23-cdc-single-bit.md) §2 [C], [24](24-cdc-multi-bit.md) §2 [C]).
- [ ] No async CDC path appears in setup/hold analysis without an SDC exception (`set_clock_groups -asynchronous` or `set_false_path`) (source: [23](23-cdc-single-bit.md) §2 [C]).

## Gate 6: Resource inference confirmed in reports

Build-order placement: after Analysis & Synthesis and Fitter pass on the design. Reviewed against the Synthesis report and the Fitter "Resource Utilization by Entity" report.

- [ ] Every inferred RAM appears in the Fitter "Resource Utilization by Entity" report on its intended primitive (M10K vs MLAB vs LUT-RAM), matching the pre-RTL plan (source: [30](30-memory-inference-cyclone-v.md) §2 [C], [41](41-quartus-reports-and-verification.md) §2 [C]).
- [ ] Every inferred memory uses the canonical Intel template form: a single `always @(posedge clk)` block, an unpacked `reg [W-1:0] mem [DEPTH-1:0]` declaration, write under an enable, and a registered read output (source: [30](30-memory-inference-cyclone-v.md) §2 [C]).
- [ ] Read-during-write mode for every inferred memory is explicit (blocking `=` for new-data RDW, nonblocking `<=` for old-data RDW) and matches the simulation expectation (source: [30](30-memory-inference-cyclone-v.md) §2 [C]).
- [ ] Every inferred multiplier appears in the Fitter report on a variable-precision DSP block (not on ALM-based soft multipliers), and includes at least one input register and one output register in RTL (source: [31](31-dsp-inference-cyclone-v.md) §2 [C], [41](41-quartus-reports-and-verification.md) §2 [C]).
- [ ] Every multiplier operand is declared `signed` (or wrapped with `$signed(...)`) where the value is signed; the Fitter report shows no mixed-signedness silent unsigned multiplies (source: [31](31-dsp-inference-cyclone-v.md) §2 [C]).
- [ ] No `/`, `%`, or variable-shift operator appears on the critical path; any such operator either uses a constant power-of-two operand or is reformulated / instantiated as IP (source: [32](32-arithmetic-patterns-and-operator-cost.md) §2 [C]).
- [ ] Every Synthesis-report "Removed registers" / "Merged registers" / "Stuck at 0/1" / "node has no driver" / "node has no fanout" / "latch inferred" entry is either fixed in source or annotated with a written waiver (source: [16](16-resource-and-state-economy.md) §2 [C], [41](41-quartus-reports-and-verification.md) §2 [C]).
- [ ] Every mod-N counter is `$clog2(N)` bits wide (plus an explicit wrap test if N is not a power of two); no counter has dead high bits in the Synthesis report (source: [16](16-resource-and-state-economy.md) §2 [C]).
- [ ] Every accumulator over K additions of W-bit values is at least `W + $clog2(K)` bits to be overflow-free; widths are sized in source, not by accident (source: [16](16-resource-and-state-economy.md) §2 [C]).
- [ ] Every variable assignment has matching bit widths; the Synthesis report shows zero width-mismatch warnings (source: [16](16-resource-and-state-economy.md) §2 [C]).

## Gate 7: Timing closes with positive slack

Build-order placement: after every Fitter run. Reviewed against the SDC file and the TimeQuest report.

- [ ] An SDC file is committed; `check_timing` (or the equivalent unconstrained-paths report) runs clean — no missing-clock, missing-IO-delay, or unreachable-register entries (source: [40](40-timing-closure-and-sdc.md) §2 [C]).
- [ ] Every primary clock entering the device has a `create_clock` constraint naming its period and source port (source: [40](40-timing-closure-and-sdc.md) §2 [C]).
- [ ] Every PLL output is picked up by `derive_pll_clocks` (or by an explicit `create_generated_clock` where the derivation is unrecognized) (source: [40](40-timing-closure-and-sdc.md) §2 [C]).
- [ ] Every synchronous input has a `set_input_delay -max` and `-min`; every synchronous output has a `set_output_delay -max` and `-min`, both relative to the launching clock (source: [40](40-timing-closure-and-sdc.md) §2 [C]).
- [ ] `derive_clock_uncertainty` is applied before slack numbers are read (source: [40](40-timing-closure-and-sdc.md) §2 [C]).
- [ ] TimeQuest worst-case setup slack and worst-case hold slack are both non-negative across every clock domain, or a written waiver naming the `set_false_path` / `set_multicycle_path` exception is in the SDC (source: [40](40-timing-closure-and-sdc.md) §2 [C], [41](41-quartus-reports-and-verification.md) §2 [C]).
- [ ] Recovery and removal slack for asynchronous resets is non-negative; any negative entry is fixed before integration (source: [41](41-quartus-reports-and-verification.md) §2 [C]).
- [ ] Every `set_false_path` and `set_multicycle_path` in the SDC has a one-line justification comment naming the source RTL guarantee that makes the exception sound (source: [40](40-timing-closure-and-sdc.md) §2 [V]).

## Gate 8: Verification minimum met

Build-order placement: before declaring the module integration-ready. Reviewed against testbench output, the metastability report, and the SVA assertion log.

- [ ] The TimeQuest `Report Metastability` output is opened; every recognized 2FF synchronizer chain has an MTBF estimate; any unsynchronized async-domain crossing is treated as a bug, not a warning (source: [41](41-quartus-reports-and-verification.md) §2 [C]).
- [ ] Every non-trivial module has a separate testbench module that drives a deterministic clock and reset sequence, applies stimulus, captures outputs, and ends with an `assert` against a reference model (source: [41](41-quartus-reports-and-verification.md) §2 [V]).
- [ ] Every handshake interface in the design has at least three concurrent SVA properties asserted (or assumed at the boundary): no-valid-drop, payload-stable, reset-clean (source: [41](41-quartus-reports-and-verification.md) §2 [V]).
- [ ] SVA properties live with the producer module (inline under `` `ifdef FORMAL `` or bound via `bind`); DUT properties are `assert`s, environment properties are `assume`s, never swapped (source: [41](41-quartus-reports-and-verification.md) §2 [V]).
- [ ] Every register in the design is observed in simulation at both its reset value and at a non-reset value before integration (source: [41](41-quartus-reports-and-verification.md) §2 [V]).
- [ ] No `X` literal is assigned in RTL to indicate "don't care"; invalid conditions are flagged with SVAs instead (source: [41](41-quartus-reports-and-verification.md) §2 [V]).

## Gate 9: Era-faithfulness review (emulation cores only)

Build-order placement: at integration review for any emulation core. Reviewed against the pre-RTL plan's emulation addendum (Gate 1) and the integrated RTL.

- [ ] The emulation core's datapath width matches the original chip's documented width (8-bit chip → 8-bit datapath); multi-byte ops use carry/borrow over multiple cycles as the original did (source: [17](17-era-faithful-microarchitecture.md) §2 [I]).
- [ ] Every external interface (memory read, memory write, IRQ ack, refresh, DMA, video timing) takes the same number of cycles at the pin as the original chip; internal pipelining is invisible at the boundary (source: [17](17-era-faithful-microarchitecture.md) §2 [I], [15](15-pipelines-and-latency-thinking.md) §2 [C]).
- [ ] No internal tristate buffers exist in the design; every shared internal bus uses a one-hot-select multiplexer instead (source: [17](17-era-faithful-microarchitecture.md) §2 [C]).
- [ ] If the original chip had one shared ALU / one 1-bit-per-cycle shifter / one shared bus, the RTL implements those as shared resources — not as N parallel copies or single-cycle barrel shifters (source: [17](17-era-faithful-microarchitecture.md) §2 [I]).
- [ ] If the original chip lacked a parallel multiplier, the multiply is modeled as iterative shift-add over the chip's documented cycle count — no DSP block is consumed for it (source: [31](31-dsp-inference-cyclone-v.md) §2 [I]).
- [ ] Control style matches the original chip: microcoded control becomes a ROM + sequencer + microinstruction register; hardwired control becomes a parameterized enum-typed FSM (source: [17](17-era-faithful-microarchitecture.md) §2 [V]).
- [ ] Memory hierarchy matches the original chip: small architectural register files (≤16 entries) map to flops, not MLAB/M10K (source: [17](17-era-faithful-microarchitecture.md) §2 [V], [30](30-memory-inference-cyclone-v.md) §2 [I]).

## Gate 10: Resource economy review

Build-order placement: final audit before integration. Reviewed against RTL source and the Synthesis/Fitter report.

- [ ] Every register in the design has an inline comment naming exactly one of the four justifications: (a) state across cycles, (b) breaks critical path, (c) crosses clock domain, (d) protocol pipeline stage (source: [16](16-resource-and-state-economy.md) §2 [I]).
- [ ] Every bit on every bus has a justification: consumed by a downstream module, required by a protocol field, or reserved with explicit forward-compatibility comment (source: [16](16-resource-and-state-economy.md) §2).
- [ ] No 2FF synchronizer appears on a signal already in the destination clock domain (no "defensive" same-clock synchronizers) (source: [23](23-cdc-single-bit.md) §2 [I]).
- [ ] No `signed` declaration appears on a quantity that is provably unsigned across its use (source: [16](16-resource-and-state-economy.md) §2 [V]).
- [ ] No FSM has two states with identical output assignments and identical next-state functions (they are the same state — merge them) (source: [16](16-resource-and-state-economy.md) §2 [V], [14](14-finite-state-machines.md) §7).
- [ ] No multiplexer wider than 8:1 is implemented as a single combinational stage; wide selections are pipelined or decomposed into a tree of smaller selections (source: [16](16-resource-and-state-economy.md) §2 [C]).
- [ ] No signal is mirrored as a register copy in two modules where one fanout from the source would suffice (source: [16](16-resource-and-state-economy.md) §2 [I]).
- [ ] No downstream consumer reads only bits `[M-1:0]` of an N-bit signal (M < N) without the source being narrowed or a `Width_Adjuster` inserted at the boundary (source: [16](16-resource-and-state-economy.md) §2 [I]).

---

## Notes on label mix

Gates 2–8 are dominated by [C] (Contract) rules — synthesis-mandatory or protocol-mandatory checks whose violation breaks correctness. Gates 1, 9, and 10 lean on [V] (Convention) and [I] (Inference) rules; this is by design — pre-RTL planning, era-faithfulness, and resource economy are review-stage disciplines that no single corpus source mandates verbatim, but each item still derives from a specific §2 rule in a topic doc and is verifiable yes/no against a named artifact.
