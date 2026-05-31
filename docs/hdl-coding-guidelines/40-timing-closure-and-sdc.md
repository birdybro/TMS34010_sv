# 40 — Timing Closure & SDC

> Bundle version: 2026-05-19
> Pinned commits: see [references/MANIFEST.md](../references/MANIFEST.md); pinned items relevant here are `intel/arria_v_cyclone_v_design_guidelines_api.txt` (PDF, dated November 2016), `fpgacpu/verilog_coding_standard.html`, `fpgacpu/system_design_standard.html`, `zipcpu/pipeline_control.txt`, and `projects/verilog-axis/syn/quartus/*.sdc`.
> Load with: [11-clocking-resets-and-cyclone-v-clock-networks.md](11-clocking-resets-and-cyclone-v-clock-networks.md), [15-pipelines-and-latency-thinking.md](15-pipelines-and-latency-thinking.md), [16-resource-and-state-economy.md](16-resource-and-state-economy.md), [21-skid-buffers-and-register-slices.md](21-skid-buffers-and-register-slices.md), [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md)
> Status mix: [C] heavy in §2/§3 (SDC commands are vendor-required to get meaningful timing reports), [V] for registered-I/O conventions, [O] in §6 for variation patterns, [I] for pipelining-as-architectural-remedy and for QSF assignment names whose exact spelling lives in the Quartus reference (app-shell, no local capture).

## 1. Purpose & one-line summary

`fmax` is the single most important number a Cyclone V design produces, and it is set by the longest combinational path between two registers (or between an I/O pad and a register); the design's job is to keep that path shorter than the target clock period. This doc teaches an agent to (a) think in terms of that path, (b) write a minimal correct Synopsys Design Constraints (SDC) file for a typical single-clock DE10-Nano (`5CSEBA6U23I7`) design — one PLL-derived clock, one async reset, one I/O bank — and (c) justify every `set_false_path` and `set_multicycle_path` line it writes. Pipelining mechanics, report-reading mechanics, and CDC-specific SDC are out of scope (deferred to `15`, `41`, `22`/`23`/`24`).

## 2. The contract (must-obey)

- [C] Every design must ship with an SDC file; without one Quartus assumes no clock period and reports no useful slack, so timing-closure cannot be claimed. Cite Intel Quartus Standard Timing Analyzer User Guide — live URL `https://docs.altera.com/r/docs/683068/current` (live URL, no local capture); corroborated by Intel design guidelines `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt:866` (Table 14 item 1: "accurate timing constraints allow timing-driven synthesis... critical to ensure designs meet their timing requirements").
- [C] Every primary clock entering the device must have a `create_clock` constraint naming its period and source port; PLL outputs must be picked up by `derive_pll_clocks` (or by an explicit `create_generated_clock` when the derivation is unrecognized). Cite `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt:885-887` ("Use create_clock and create_generated_clock to specify the frequencies and relationships for all clocks... Use derive_pll_clocks to create generated clocks for all PLL outputs").
- [C] Every synchronous input must have a `set_input_delay` and every synchronous output must have a `set_output_delay`, both relative to the launching clock and specifying `-max` and `-min`. Cite `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt:886-887` ("Use set_input_delay and set_output_delay to specify the external device or board timing parameters"); see also Quartus Standard Timing Analyzer User Guide (live URL `https://docs.altera.com/r/docs/683068/current`, live URL, no local capture).
- [C] Clock uncertainty must be applied with `derive_clock_uncertainty` before slack numbers are trusted; without it the inter- and intra-clock jitter and PLL-induced uncertainty are zero in the report, and slack is optimistic. Cite `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt:888` ("Use derive_clock_uncertainty to automatically apply inter-clock, intra-clock, and I/O interface uncertainties").
- [C] `check_timing` (or equivalent unconstrained-paths report) must be clean: every primary clock declared, every I/O constrained, every register reachable from a clock. Cite `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt:888` ("Use check_timing to generate a report on any problem with the design or applied constraints, including missing constraints").
- [V] Module and I/O boundaries are registered by default; combinational outputs at a boundary are an exception and must be justified (e.g. a `ready` whose return path is shorter than one clock by construction; see [21-skid-buffers-and-register-slices.md](21-skid-buffers-and-register-slices.md)). Cite `references/raw/fpgacpu/verilog_coding_standard.html:117-120` ("All signals are registers except where a wire is mandatory: module input ports, connecting module ports together, and inferring tri-state I/O").
- [V] Pin-adjacent input and output registers are placed in the I/O element (IOE) so that input setup and output clock-to-pad collapse to the IOE's fixed, minimum-delay path; the placement is forced via QSF `set_instance_assignment` (the exact assignment names — `FAST_INPUT_REGISTER`, `FAST_OUTPUT_REGISTER`, `FAST_OUTPUT_ENABLE_REGISTER` — come from the Quartus Standard User Guide, app-shell, no local capture). Cite `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt:592` ("Programmable input/output element (IOE) delays--helps read and time margins by minimizing the uncertainties between signals in the bus") plus Quartus Standard Timing Analyzer User Guide live URL `https://docs.altera.com/r/docs/683068/current` (live URL, no local capture).
- [V] `set_false_path` is reserved for paths that are genuinely independent in time: async-reset deassertion through a 2FF synchronizer, static-configuration registers, and post-synchronizer CDC endpoints (the latter is the subject of [23-cdc-single-bit.md](23-cdc-single-bit.md) and not duplicated here). Cite Quartus Standard Timing Analyzer User Guide live URL (live URL, no local capture); corroborated by the real-world idiom in `references/projects/verilog-axis/syn/quartus/sync_reset.sdc:27` (`set_false_path -from * -to [get_registers "$inst|sync_reg[*]"]`).
- [V] `set_multicycle_path` is reserved for paths where the RTL — a write-enable, an FSM gate, or a sample counter — guarantees the source register is stable for N source-clock periods before the destination samples; a setup multicycle of N requires a matching hold multicycle of N-1 to keep hold analysis sane. Cite Quartus Standard Timing Analyzer User Guide live URL `https://docs.altera.com/r/docs/683068/current` (live URL, no local capture).
- [I] Pipelining (adding a register stage to split a long combinational cone) is the primary remedy when a path fails fmax; widening the period is a retreat, and operator-level tricks (`KEEP`, `MAXFAN`, manual retiming pragmas) are last-resort because they fight, rather than rearchitect, the path. Inferential chain: ZipCPU teaches pipelining as the structural answer to clock-period pressure (`references/extracted_text/zipcpu/pipeline_control.txt:191-218`, the "Pipeline Strategies" lesson treats pipeline-with-CE as the default architectural shape); Intel's timing-closure checklist treats pipelining as a fitter-level fact to be analysed, not a workaround (`references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt:866`, "designs must meet their timing requirements which represent actual design requirements"); FPGACPU's register-everything default (`references/raw/fpgacpu/verilog_coding_standard.html:117-120`) makes pipeline-stage registers the unit of architectural composition. See [15-pipelines-and-latency-thinking.md](15-pipelines-and-latency-thinking.md) for the construction details.

## 3. Constructs / SDC reference

Verbatim source for the Intel-recommended SDC command set:

```
// references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt:885-888 @ 2016-11
// (Arria V and Cyclone V Design Guidelines, Table 14 item 5)
//  Use create_clock and create_generated_clock to specify the frequencies and
//  relationships for all clocks in your design.
//  Use set_input_delay and set_output_delay to specify the external device or
//  board timing parameters.
//  Use derive_pll_clocks to create generated clocks for all PLL outputs, according
//  to the settings in the PLL megafunctions.
//  Use derive_clock_uncertainty to automatically apply inter-clock, intra-clock,
//  and I/O interface uncertainties.
//  Use check_timing to generate a report on any problem with the design or
//  applied constraints, including missing constraints.
```

Cite Quartus Standard Timing Analyzer User Guide live URL `https://docs.altera.com/r/docs/683068/current` (live URL, no local capture) for command syntax. Each command below is the documented Quartus-accepted form.

```tcl
# [C] Primary clock declaration. 50.000 MHz from the DE10-Nano FPGA_CLK1_50 pin.
create_clock -period 20.000 -name clk_50 [get_ports {FPGA_CLK1_50}]

# [C] PLL-derived clocks: preferred form is to let Quartus extract every PLL
# output from the netlist. -create_base_clocks asks Quartus to also create
# default base clocks for primary input ports that lack create_clock entries.
derive_pll_clocks -create_base_clocks
derive_clock_uncertainty

# [V] Naming a generated clock explicitly. Use only when derive_pll_clocks
# cannot see the relationship (rare: typically a fabric divider).
create_generated_clock -name clk_sys \
    -source [get_pins {u_pll|altpll_component|auto_generated|pll1|inclk[0]}] \
    -divide_by 1 -multiply_by 2 \
    [get_pins  {u_pll|altpll_component|auto_generated|pll1|clk[0]}]

# [C] Input / output delays for one I/O bank synchronous to clk_sys.
# -max sets the worst-case external launch delay (data arrives late);
# -min sets the best-case external launch delay (data arrives early -> hold).
set_input_delay  -clock clk_sys -max 4.0 [get_ports {data_in[*]}]
set_input_delay  -clock clk_sys -min 1.0 [get_ports {data_in[*]}]
set_output_delay -clock clk_sys -max 4.0 [get_ports {data_out[*]}]
set_output_delay -clock clk_sys -min 1.0 [get_ports {data_out[*]}]

# [V] False paths. Form 1: cut everything fanning out from the async-reset
# port (broad; correct when the entire fanout is asynchronous-by-design).
set_false_path -from [get_ports {RESET_N}]

# [V] False paths. Form 2: cut into the synchronizer-flop endpoints only
# (narrow; the form actually emitted by reusable IP — see
# references/projects/verilog-axis/syn/quartus/sync_reset.sdc:27).
set_false_path -to [get_registers {u_rst_sync|sync_reg[*]}]

# [V] Multicycle path. The RTL must prove the source is stable for two
# clk_sys periods (e.g. a divide-by-two enable or a wait-state FSM).
# Setup is relaxed by one cycle; hold is correspondingly relaxed by one
# less, otherwise the hold check stays tight against the original edge.
set_multicycle_path -setup -end -from [get_registers {u_dpath|slow_src*}] \
                                -to   [get_registers {u_dpath|slow_dst*}] 2
set_multicycle_path -hold  -end -from [get_registers {u_dpath|slow_src*}] \
                                -to   [get_registers {u_dpath|slow_dst*}] 1
```

### 3.1 SDC command summary table

| SDC command | What it tells Quartus | When to write it |
|---|---|---|
| `create_clock` | Period and source pin of a primary clock | [C] Once per primary input clock |
| `derive_pll_clocks` | Generate constraints for every PLL output in the netlist | [C] Once, after `create_clock`s |
| `create_generated_clock` | A derived clock not produced by a PLL (e.g. fabric divider) | [V] Rare; only when `derive_pll_clocks` cannot see the relationship |
| `derive_clock_uncertainty` | Apply inter/intra-clock and I/O uncertainty per the device model | [C] Once, after `derive_pll_clocks` |
| `set_input_delay` | External-board launch delay from external clock to FPGA input pad | [C] Every synchronous input, `-max` and `-min` |
| `set_output_delay` | External-device setup/hold window at the output pad | [C] Every synchronous output, `-max` and `-min` |
| `set_false_path` | "Do not time this path" — asynchronous by construction | [V] Async-reset deassert, static config, post-synchronizer endpoints |
| `set_multicycle_path` | "This path is given N source-clock periods to settle" | [V] Only when the RTL holds the source stable for N cycles |
| `check_timing` | Report missing constraints | [C] Run after every SDC change |

Citation: every row above is established by `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt:880-888` plus Quartus Standard Timing Analyzer User Guide (live URL `https://docs.altera.com/r/docs/683068/current`, live URL, no local capture).

### 3.2 QSF assignments for IOE register placement

| QSF assignment (exact name from Quartus Standard reference) | Effect | When to apply |
|---|---|---|
| `set_instance_assignment -name FAST_INPUT_REGISTER ON -to <pin>` | Force the input register driven by `<pin>` to land in the IOE | [V] Every input pin whose register is synchronous to the chip clock |
| `set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to <pin>` | Force the output register driving `<pin>` to land in the IOE | [V] Every output pin whose driver is registered |
| `set_instance_assignment -name FAST_OUTPUT_ENABLE_REGISTER ON -to <pin>` | Force the output-enable register for tri-state `<pin>` to land in the IOE | [V] Every tri-state pin whose enable is registered |

Citation for the existence and effect of programmable IOE register placement: `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt:592` ("Programmable input/output element (IOE) delays--helps read and time margins by minimizing the uncertainties between signals in the bus"). [I] for the *exact* QSF assignment names: the Quartus Standard User Guide (live URL `https://docs.altera.com/r/docs/683323/current`, live URL, no local capture) is the canonical reference for the assignment spelling; the in-corpus design-guidelines PDF establishes that IOE placement is a Quartus-managed optimization but does not enumerate the QSF assignment names.

## 4. Sequencing & timing

**Setup.** The amount of time data must be stable *before* the clock edge for the destination flop to capture correctly. The fitter's job, given a `create_clock` period, is to make every data path shorter than period − setup − clock-uncertainty − margin. Cite Quartus Standard Timing Analyzer User Guide live URL `https://docs.altera.com/r/docs/683068/current` (live URL, no local capture).

**Hold.** The amount of time data must remain stable *after* the clock edge. Hold violations are independent of clock period; you cannot fix a hold violation by lowering frequency. The fitter normally fixes hold automatically by adding routing delay on too-short paths; an unfixable hold violation is a structural problem (e.g. an unintended combinational short) or a missing `set_input_delay -min` / `set_output_delay -min`. Same citation.

**Recovery / removal.** Async-reset analogs of setup / hold for the reset signal: recovery is the time the reset must be deasserted *before* the active clock edge; removal is the time it must remain stable *after*. Quartus analyses both automatically once `create_clock` is in place and the reset port is constrained (or false-pathed, see §3). Same citation.

**Slack.** The margin by which a path meets its requirement: positive = passing, negative = failing. `fmax` is the largest clock frequency that yields non-negative setup slack on the critical path. Same citation.

**Input-delay model.** External clock → board trace + driver delay → FPGA pad → input register. `set_input_delay -max` is the worst-case (slowest) external launch; `-min` is the best-case (fastest, possibly negative if the external driver leads the clock). The path Quartus then times is `(external clock + max input delay) + (pad-to-register) ≤ destination clock − setup − uncertainty`. Placing the input register in the IOE collapses the pad-to-register term to the IOE's fixed, minimum delay. Cite `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt:592` + Quartus Standard Timing Analyzer User Guide (live URL, no local capture).

**Output-delay model.** Symmetric. Source register → IOE → pad → board trace → external-device setup window. `set_output_delay -max` declares the external device's required setup; `set_output_delay -min` declares its required hold. Placing the output register in the IOE collapses the FPGA-side clock-to-pad time to the IOE's fixed, minimum value; that minimum is reproducible across compiles (the same pad, the same IOE flop, the same delay), where a fabric-located register's clock-to-pad depends on placement luck. Same citation.

**Why the `set_false_path -from RESET_N` form differs from `set_false_path -to [get_registers {sync_reg[*]}]`.** The `-from` form cuts every path leaving the reset port, including the deassertion path through the synchronizer; the `-to` form cuts only the paths *terminating* on the synchronizer flops, leaving the synchronizer's own internal output path timed normally. The `-to` form is the form a reusable synchronizer module emits (see `references/projects/verilog-axis/syn/quartus/sync_reset.sdc:27`), because it does not assume the reset port itself has no other (non-async) load. Pick the `-from` form when the port has exactly one load (the synchronizer), the `-to` form otherwise.

**Why simulation cannot verify timing closure.** Timing is a synthesis-and-fitter result derived from device delay models against a constraint set. A passing simulation tells you about logical correctness, not about whether a 200 MHz target actually meets setup on the 5CSEBA6U23I7's -I7 speed grade.

## 5. Minimal working pattern

Below is a complete, syntactically valid SDC file for a typical DE10-Nano-style design: one primary 50 MHz clock from `FPGA_CLK1_50`, one PLL synthesizing a system clock (`clk_sys`), one async reset (`RESET_N`) deasserted through a 2FF synchronizer named `u_rst_sync`, one I/O bank carrying `data_in[7:0]` and `data_out[7:0]` synchronous to the PLL output. [I] composite: composed from the patterns cited in `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt:880-888` and `references/projects/verilog-axis/syn/quartus/sync_reset.sdc:27`.

```tcl
# de10_nano.sdc — minimal timing constraints for a single-clock DE10-Nano design
# Target: Cyclone V SoC 5CSEBA6U23I7.

# --- Primary clock ----------------------------------------------------------
# 50 MHz from the DE10-Nano on-board oscillator routed to FPGA_CLK1_50.
create_clock -period 20.000 -name clk_50 [get_ports {FPGA_CLK1_50}]

# --- PLL-derived clocks and uncertainty -------------------------------------
# derive_pll_clocks creates a generated-clock for every PLL output (clk_sys);
# -create_base_clocks also fills in any primary input lacking a create_clock.
derive_pll_clocks -create_base_clocks
derive_clock_uncertainty

# --- I/O delays on the data bus (relative to clk_sys, the PLL output) -------
# 4.0/1.0 ns are illustrative; replace with values derived from the external
# device datasheet and the board trace model.
set_input_delay  -clock clk_sys -max 4.0 [get_ports {data_in[*]}]
set_input_delay  -clock clk_sys -min 1.0 [get_ports {data_in[*]}]
set_output_delay -clock clk_sys -max 4.0 [get_ports {data_out[*]}]
set_output_delay -clock clk_sys -min 1.0 [get_ports {data_out[*]}]

# --- Async reset ------------------------------------------------------------
# RESET_N is asserted asynchronously and deasserted into clk_sys through a
# 2FF synchronizer in module u_rst_sync. The deassertion path is async by
# construction; the synchronizer establishes timing. Cut into the sync flops.
set_false_path -from [get_ports {RESET_N}]
set_false_path -to   [get_registers {u_rst_sync|sync_reg[*]}]
```

Paired QSF snippet for IOE register placement on the same I/O bank ([V]; cite `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt:592` for IOE placement effect; Quartus Standard User Guide live URL `https://docs.altera.com/r/docs/683323/current` (live URL, no local capture) for the exact assignment spelling):

```tcl
# de10_nano.qsf (excerpts) — force IOE register placement on the data bus.
set_instance_assignment -name FAST_INPUT_REGISTER  ON -to data_in[*]
set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to data_out[*]
```

Pre-commit check: each Tcl line above uses only documented Quartus SDC primitives (`create_clock`, `derive_pll_clocks`, `derive_clock_uncertainty`, `set_input_delay`, `set_output_delay`, `set_false_path`) and `set_instance_assignment` in QSF; the file is ≤30 non-comment lines and parses as standalone Tcl.

## 6. Common variations across implementations

- [O] **Single global clock with `derive_pll_clocks` only.** The DE10-Nano typical pattern: `create_clock` on `FPGA_CLK1_50`, `derive_pll_clocks -create_base_clocks`, `derive_clock_uncertainty`, and per-bank `set_input_delay` / `set_output_delay`. No explicit `create_generated_clock`, no `set_clock_groups`. This is the structure §5 implements; the structural recommendation comes from `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt:885-888` and is consistent with the §5 file.
- [O] **Multiple clocks with explicit `set_clock_groups -asynchronous`.** When two PLL-derived domains (or a PLL clock and an externally-launched source-synchronous clock) are unrelated by phase, both are declared with `create_clock` / `derive_pll_clocks` and then declared mutually asynchronous so the analyzer does not report cross-domain transfer paths. Quartus Standard Timing Analyzer User Guide (live URL `https://docs.altera.com/r/docs/683068/current`, live URL, no local capture) defines `set_clock_groups`. The CDC SDC for individual transfers (synchronizer-endpoint `set_false_path` or bounded-delay `set_max_delay`) lives in [23-cdc-single-bit.md](23-cdc-single-bit.md); a real-world example of the per-transfer form is `references/projects/verilog-axis/syn/quartus/axis_async_fifo.sdc:27-50` (`set_false_path` on the reset-sync flops, `set_max_delay 8.000` on pointer-Gray transfers).
- [O] **Source-synchronous I/O with a virtual clock.** When the external device launches both data and its own clock into the FPGA (typical for parallel ADCs and SDR-mode pipelined buses), a virtual clock declared with `create_clock` (no `-source`) carries the external launch reference; `set_input_delay` / `set_output_delay` then reference the virtual clock rather than a fabric clock. Cite Quartus Standard Timing Analyzer User Guide (live URL `https://docs.altera.com/r/docs/683068/current`, live URL, no local capture); no specific in-corpus implementation captures this idiom, so the variation is [O] anchored to the Quartus reference, not to a project SDC.

## 7. Anti-patterns (mistakes that compile but break)

> Spec §9 has no numbered home for these three; this doc introduces them and they should be picked up by `90-anti-patterns.md` (spec §9 addendum).

- **SDC not written; design runs unconstrained.** (spec §9 addendum)
  - **Symptom:** Quartus reports a long "Unconstrained Paths" section; fmax report is empty or shows a meaningless astronomical number; the design works at low external clock rates and fails silently when the board clock is raised, with no warning at compile time.
  - **Cause:** The agent treated the SDC as a deployment-time chore rather than as part of the design. Without `create_clock` Quartus has no period to compare against; without `set_input_delay` / `set_output_delay` the I/O paths are not in the report at all.
  - **Fix:** Write a minimal SDC (§5) from day one of bringup, even for a single-clock blinky. Re-run `check_timing` after every SDC edit and confirm no items remain on the "no clock" / "missing input/output delays" lists.
  - **Citation:** `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt:866` ("accurate timing constraints allow timing-driven synthesis and place-and-route software to obtain optimal results... critical to ensure designs meet their timing requirements"); Quartus Standard Timing Analyzer User Guide (live URL `https://docs.altera.com/r/docs/683068/current`, live URL, no local capture).

- **Pipeline added "for safety" with no critical path actually failing fmax.** (spec §9 addendum; cross-ref to spec §9 #17)
  - **Symptom:** A pipeline stage is inserted at a module boundary or inside a datapath; the failing-paths report did not list that path before the change; latency grows by one cycle; fmax is unchanged or worse (more registers compete for routing, and the new stage's clock-skew can pull the critical path elsewhere). Downstream handshake-pipeline alignment breaks because `valid` was not also delayed by one cycle.
  - **Cause:** The agent pipelined defensively, without reading the post-fit Timing Analyzer report to identify the actual critical path. Pipelining the wrong path consumes registers and latency without improving slack.
  - **Fix:** Read the failing-paths report first; pipeline only the path the report identifies as critical. Cross-ref [16-resource-and-state-economy.md](16-resource-and-state-economy.md) for the "every register must justify itself" angle and [15-pipelines-and-latency-thinking.md](15-pipelines-and-latency-thinking.md) for the construction (valid-follows-data must be preserved).
  - **Citation:** `references/extracted_text/zipcpu/pipeline_control.txt:191-218` (Pipeline Strategies — pipelining is a structural choice tied to a specific stall/CE strategy, not a sprinkle-on remedy); `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt:866` (timing requirements are evidence-driven, derived from the actual reports).

- **I/O register not placed in IOE; large clock-to-pad delay.** (spec §9 addendum)
  - **Symptom:** Setup slack on input pins or hold slack on output pins is marginal or negative despite small fabric utilization; the failing path in the Timing Analyzer report shows the source or destination register at a fabric LAB rather than at the I/O column; fmax is limited by I/O, not internal, paths.
  - **Cause:** The register adjacent to the pin was placed by the fitter in fabric (a LAB ALM) instead of in the IOE. With no `FAST_INPUT_REGISTER` / `FAST_OUTPUT_REGISTER` assignment, the fitter is free to place the register wherever it routes best, which is usually not the IOE.
  - **Fix:** Add the QSF `set_instance_assignment -name FAST_INPUT_REGISTER ON -to <pin>` (and `FAST_OUTPUT_REGISTER` for outputs, `FAST_OUTPUT_ENABLE_REGISTER` for tri-state enables); after recompile, check the Fitter report's I/O section for the assignment landing in the IOE (see [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md)).
  - **Citation:** `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt:592` ("Programmable input/output element (IOE) delays--helps read and time margins by minimizing the uncertainties between signals in the bus"); Quartus Standard User Guide for the exact QSF assignment spelling (live URL `https://docs.altera.com/r/docs/683323/current`, live URL, no local capture).

- **`set_false_path` used to make a real critical path "go away."** [I] (additional entry, supported by the brief's pre-commitment and by the Intel emphasis on constraints reflecting *actual design requirements*.)
  - **Symptom:** Timing Analyzer shows a clean (or suspiciously clean) report; the design fails intermittently in hardware, especially under temperature or voltage stress; the failure correlates with the activity on the false-pathed signal.
  - **Cause:** A `set_false_path` was applied to a path the designer found inconvenient to time, not to a path that is truly asynchronous. A false path is a *correctness claim* (no functional data is ever captured here, or the path is covered by a synchronizer); used as a timing fix it silently corrupts data.
  - **Fix:** Remove the constraint and either pipeline the path (preferred) or, if it truly is a CDC, route it through a documented synchronizer module ([23-cdc-single-bit.md](23-cdc-single-bit.md)) and cut into the *synchronizer's* endpoints with the `-to` form (see `references/projects/verilog-axis/syn/quartus/sync_reset.sdc:27`).
  - **Citation:** `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt:866` (constraints represent "actual design requirements that must be met for the device to operate correctly"); Quartus Standard Timing Analyzer User Guide (live URL `https://docs.altera.com/r/docs/683068/current`, live URL, no local capture).

- **`set_multicycle_path` written without RTL evidence that the data is stable for N clocks.** [I] (additional entry, supported by brief pre-commitment.)
  - **Symptom:** Random functional failures correlated with data-traffic patterns, particularly bursts; failures vanish at low frequency; Timing Analyzer reports clean setup slack because the path was given N times the period to settle.
  - **Cause:** A multicycle constraint was applied because the path was long, with no FSM, counter, or clock-enable in the RTL proving the source register cannot change for N source-clock periods. The setup constraint is relaxed but the hardware still samples every cycle.
  - **Fix:** Either prove (by inspection of the source HDL and ideally an SVA cover/assert in the testbench) that the source register holds stable for the N cycles claimed, or remove the multicycle and pipeline the path. Always write both `set_multicycle_path -setup` and a matching `set_multicycle_path -hold` (typically `N` and `N-1` respectively) so hold analysis stays correct.
  - **Citation:** `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt:888` (the Intel checklist treats multicycle as a deliberate, evidence-backed annotation); Quartus Standard Timing Analyzer User Guide (live URL `https://docs.altera.com/r/docs/683068/current`, live URL, no local capture).

## 8. Verification

Checklist (Gate-7 bringup; see [91-core-bringup-checklist.md](91-core-bringup-checklist.md)):

- **SDC exists and constrains every primary clock.** Confirm `create_clock` for every entry on the chip's clock-input pin list; confirm `derive_pll_clocks -create_base_clocks` is called once; confirm `derive_clock_uncertainty` follows it. Run `check_timing` and require zero items in the "no clock" / "missing input/output delays" / "loops" categories.
- **Every primary I/O has `set_input_delay` or `set_output_delay`** with both `-max` and `-min`. The `Report Unconstrained Paths` Timing Analyzer view must be empty; any remaining entry is either constrained or justified in a comment in the SDC.
- **Worst-case setup slack ≥ 0 and worst-case hold slack ≥ 0** on every clock domain, reported via `Report Setup` and `Report Hold`. A negative slack number is a failure to close timing for the target period; either raise the period (last resort) or pipeline the critical path (see [15-pipelines-and-latency-thinking.md](15-pipelines-and-latency-thinking.md)).
- **IOE placement confirmed.** Open the Fitter report → I/O / Input-Output sections, spot-check that pins targeted by `FAST_INPUT_REGISTER` / `FAST_OUTPUT_REGISTER` show the register landing in the IOE. Details and report navigation are in [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md).
- **`derive_clock_uncertainty` has been called before reading slack numbers.** Otherwise inter- and intra-clock uncertainty is zero in the reports and slack is optimistic (see §2 [C]).
- **Note:** Simulation does not verify timing closure. A simulation pass is necessary for logical correctness; timing closure is a synthesis-and-fitter result against the SDC and the device speed-grade model only.

## 9. Provenance footer

- `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt` @ 2016-11 (PDF, 22 pages; the file's `.txt` extension is misleading — it is the binary PDF of the Arria V and Cyclone V Design Guidelines, November 2016) — used for §2 (all [C] SDC rules; IOE-placement [V]), §3 (verbatim Table 14 excerpt and §3.2 IOE citation), §4 (input/output delay model anchoring), §6 (single-global-clock structure), §7 (SDC-not-written, pipeline-without-critical-path, IOE-misplacement citations), §8 (verification checklist anchoring).
- `https://docs.altera.com/r/docs/683068/current` — Intel Quartus Prime Standard Edition User Guide, Timing Analyzer (live URL, no local capture; the local file `references/raw/intel/quartus_standard_timing_analyzer.html` is an app-shell with no body content) — used for §2 (all [C] SDC syntax and semantics rules), §3 (command syntax for `create_clock`, `derive_pll_clocks`, `derive_clock_uncertainty`, `set_input_delay`, `set_output_delay`, `set_false_path`, `set_multicycle_path`, `set_clock_groups`), §4 (setup/hold/recovery/removal/slack definitions), §6 (virtual-clock and `set_clock_groups -asynchronous` references), §7 (false-path and multicycle-path discipline).
- `https://docs.altera.com/r/docs/683323/current` — Intel Quartus Prime Standard Edition User Guide: Design Recommendations (live URL, no local capture; local file `references/raw/intel/quartus_standard_design_recommendations_index.html` is an app-shell) — used for §3.2 (exact `FAST_INPUT_REGISTER` / `FAST_OUTPUT_REGISTER` / `FAST_OUTPUT_ENABLE_REGISTER` QSF assignment names), §5 (QSF snippet citation), §7 (IOE-misplacement citation).
- `https://docs.altera.com/r/docs/683375/current` — Cyclone V Device Handbook Volume 1, Clock Networks and PLLs (live URL, no local capture; local file `references/raw/intel/cyclone_v_clock_networks.html` is an app-shell) — referenced in §1 / §2 for clock-network context, with full treatment deferred to [11-clocking-resets-and-cyclone-v-clock-networks.md](11-clocking-resets-and-cyclone-v-clock-networks.md).
- `references/raw/fpgacpu/verilog_coding_standard.html` @ archive snapshot — used for §2 (registered-by-default [V]) and §7 (pipeline-without-critical-path reference, by way of the register-everything default that frames pipelining as the architectural unit).
- `references/raw/fpgacpu/system_design_standard.html` @ archive snapshot — used for §2 (timing-constraints-as-design discipline, lines 245-247: "Timing constraints, where you define the incoming clocks, their synchronous/asynchronous relationships, any false paths, and external I/O delays").
- `references/extracted_text/zipcpu/pipeline_control.txt` @ archive snapshot — used for §2 ([I] pipelining-as-architectural-remedy) and §7 (pipeline-without-critical-path citation; the Pipeline Strategies lesson at lines 191-218 establishes pipelining as a deliberate structural choice).
- `references/projects/verilog-axis/syn/quartus/sync_reset.sdc` @ archive snapshot (2020 Alex Forencich) — used for §3 ([V] `set_false_path -to` form on synchronizer endpoints), §4 (reset-synchronizer false-path form rationale), §7 (false-path misuse fix).
- `references/projects/verilog-axis/syn/quartus/axis_async_fifo.sdc` @ archive snapshot (2020-2023 Alex Forencich) — used for §6 ([O] multi-clock CDC with `set_false_path` on sync flops and `set_max_delay 8.000` on Gray-coded pointer transfers).
