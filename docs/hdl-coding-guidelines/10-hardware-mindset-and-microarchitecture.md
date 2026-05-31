# Hardware Mindset and Microarchitecture

> Bundle version: 2026-05-19
> Pinned commits:
> - `references/raw/fpgacpu/` snapshots — collected 2026-05-20 (per [references/MANIFEST.md](../references/MANIFEST.md))
> - `references/projects/FPGADesignElements/` @ commit `2450a54`
> - `references/projects/verilog-axis/` @ commit `48ff7a7`
> - `references/projects/lowrisc-style-guides/` @ commit `735d911`
> - `references/extracted_text/zipcpu/` from PDFs collected 2026-05-20
> - `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt` (Altera AN-662-1.3) @ 2016-11
> Load with: [11-clocking-resets-and-cyclone-v-clock-networks.md](11-clocking-resets-and-cyclone-v-clock-networks.md), [12-synthesizable-sv-subset.md](12-synthesizable-sv-subset.md), [13-registers-and-combinational-blocks.md](13-registers-and-combinational-blocks.md), [15-pipelines-and-latency-thinking.md](15-pipelines-and-latency-thinking.md), [16-resource-and-state-economy.md](16-resource-and-state-economy.md), [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md)
> Status mix: heavy on [V] (conventions distilled across the corpus) and [I] (inferences this doc owns explicitly). A small core of [C] anchors the doc — concurrency of `always`/assigns and loop elaboration. §6 carries three [O] entries against named implementations. Rough split: [C] ~15%, [V] ~40%, [O] ~15%, [I] ~30%.

## 1. Purpose & one-line summary

This doc establishes the mental model that distinguishes RTL design from software programming: Verilog describes hardware structure and clocked state transitions, not an algorithm that executes in time. It commits the consuming agent to produce a **pre-RTL microarchitecture plan** before any RTL is written, and — for emulation work — to treat the original chip's microarchitecture as the specification that plan must reverse-engineer. It does not cover the SystemVerilog subset, reset/clock primitives, `always` block discipline, FSM coding, pipeline construction, resource economy, or era-faithful mirroring rules — those are owned by the docs listed under `Load with:`.

## 2. The contract (must-obey)

- [C] Every continuous `assign`, every module instance, and every `always` block in synthesizable RTL is concurrent hardware that exists and updates simultaneously on each clock cycle; ordering between blocks is not implied by source order. Source: `references/raw/fpgacpu/verilog_coding_standard.html` §"Always Blocks" and §"Blocking and Non-Blocking Assignments" (lines 420–479) establishes the two-event synthesizable model and the consequence that independent always blocks have indeterminate scheduling between them.
- [C] Synthesizable `for` loops inside `always` blocks and `generate for` constructs elaborate to **parallel hardware** (combinational chains, repeated instances, or unrolled assignments); they do not iterate at runtime, and a loop without a static bound elaborates new hardware until the elaborator runs out of memory. Source: `references/extracted_text/zipcpu/class_verilog.txt:14258-14263` ("remember this is hardware. Yosys is elaborating new hardware circuits every time through the loop, and the loop doesn't have an end"); reinforced by `references/raw/fpgacpu/verilog_coding_standard.html:529-554` (generate-vs-for-loop scoping rules).
- [V] Before writing RTL, produce a pre-RTL microarchitecture plan. The plan names: clocks and reset assumptions, throughput target, latency budget, datapath widths/signedness/saturation, resource strategy (parallel vs shared, flops vs MLAB vs M10K vs DSP), flow-control strategy (always-ready, ready/valid, FIFO, credit), and where pipeline registers cut timing. Source: `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt` §"Design Specifications", Table 2 item 1, page 3 @ 2016-11 ("Specify the I/O interfaces for the FPGA. Identify the different clock domains. Include a block diagram of basic design functions"); reinforced by `library/topics/01_hardware_mindset_parallelism.md` §"Architecture Before Code".
- [V] Module hierarchy reflects hardware hierarchy — datapath / control / interface separation, with unrelated logic encapsulated into separate modules — not the call-graph of a software reference port. Source: `references/raw/fpgacpu/system_design_standard.html:93-100` ("move unrelated connections into separate modules") and `:118-122` ("Divide a sub-system into one module for functionality (processing and storage), one for control (the FSM), and one for interfacing to the rest of the system").
- [V] Use `localparam` for every named magic number, parameterize every width, and never hardcode a literal integer for a datapath width. Source: `references/raw/fpgacpu/verilog_coding_standard.html:146-152` ("Wherever possible, parameterize the width of your variables... Never use a hardcoded literal integer: name it with a localparam instead").
- [I] For emulation of a real silicon target, the original chip's microarchitecture **is** the specification, and the pre-RTL plan is the reverse-engineering output. Inference chain: Cyclone V `5CSEBA6U23I7` on the DE10-Nano provides ~110K ALMs, 5.6 Mbit M10K+MLAB, 112 variable-precision DSP blocks (per `references/raw/intel/cyclone_v_product_table_api.txt` and [01-glossary.md](01-glossary.md)) — a budget that almost always exceeds the original chip's transistor count, **so resource economy is not the constraint that disciplines the design.** What disciplines the design is cycle-accurate compatibility with software written for the original silicon; cycle accuracy is only verifiable against the original's bus/control schedule, which means the original chip's microarchitecture must be recovered first. The plan is therefore not invented; it is reconstructed. Full mirroring rules live in [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md).
- [I] When the problem statement reads like a software algorithm ("for each input x, compute y = f(x), then sum the results"), the consuming agent must **redo the planning step** before writing any RTL: identify what is parallel state, what work happens per cycle, what is sequential only because the original chip's controller serialized it. Inferred from the combination of FPGACPU's modularization principle and Intel AN-662's pre-design checklist.

## 3. Constructs / signals / API reference

This is a mindset doc; the "constructs" it introduces are the structural primitives of a microarchitecture plan, not RTL ports. Concrete RTL constructs (`logic`, `always_ff`, `always_comb`, etc.) live in [12-synthesizable-sv-subset.md](12-synthesizable-sv-subset.md) and [13-registers-and-combinational-blocks.md](13-registers-and-combinational-blocks.md).

### 3.1 Pre-RTL microarchitecture plan — required fields

[V] The plan exists before any RTL is written. A reviewer can answer all the following without reading the RTL.

| Field | Meaning |
|---|---|
| Clocks | Names of every clock entering the module; expected frequencies; relationship (sync/async). Defer to [11](11-clocking-resets-and-cyclone-v-clock-networks.md). |
| Reset | Polarity, async-assert/sync-release expectation, scope. Defer to [11](11-clocking-resets-and-cyclone-v-clock-networks.md). |
| Throughput | One result per clock, one per N clocks, bursty, or command/response. |
| Latency | Number of clocks from input event to output event; fixed, variable, or backpressured. |
| Datapath widths | Width per signal in the datapath; signedness; saturation/wrap/round policy. |
| Resource strategy | Parallel copies vs shared resource; flops vs MLAB vs M10K vs DSP block. Defer to [30](30-memory-inference-cyclone-v.md), [31](31-dsp-inference-cyclone-v.md). |
| Flow control | Always-ready, ready/valid, FIFO, credit, request/ack, local FSM. Defer to [20](20-ready-valid-handshakes.md). |
| Pipeline cuts | Where register stages break combinational paths to meet fmax. Defer to [15](15-pipelines-and-latency-thinking.md). |
| External interface (if emulation) | Pins, bus, timing of the original chip, cycle by cycle. Defer to [17](17-era-faithful-microarchitecture.md). |

### 3.2 The mental model: registers separated by combinational clouds

[V] The synthesizable subset of Verilog describes exactly two kinds of hardware: registers (state, updated on a clock edge) and combinational clouds (gates between registers, settling within one clock period). Every `always_ff` block becomes registers; every `always_comb` block, continuous `assign`, and module instance becomes either combinational logic or further registers.

[V] When reading or writing RTL, picture a schematic in which named wires are drawn between rectangular register blocks, and the logic that drives each wire is a cloud of gates. The clock period must accommodate the propagation delay of the slowest cloud (the critical path). This model is endorsed in `references/raw/fpgacpu/system_design_standard.html:69-83`, which recommends viewing the post-elaboration and post-synthesis schematics in the CAD tool to check that the code matches the intended hardware structure.

```
                              ┌─────────────────┐                              ┌─────────────────┐
   input ─── comb cloud ───── │ pipeline reg A  │ ─── comb cloud (work) ────── │ pipeline reg B  │ ─── output
                              │ (always_ff)     │                              │ (always_ff)     │
                              └─────────────────┘                              └─────────────────┘
                                      ↑                                                 ↑
                                     clk                                               clk
```

### 3.3 The concurrency property

[C] Consider three sample statements in a single module:

```systemverilog
assign sum  = a + b;                          // (1) continuous assign
always_comb result = sum & mask;               // (2) combinational block
always_ff @(posedge clk) reg_out <= result;    // (3) sequential block
```

All three describe hardware that exists every cycle. The continuous assign (1) and the combinational block (2) are gates between flops; they settle within one clock period. The flop in (3) samples its input at the rising edge. They do **not** execute in order: in the same clock period, (1) settles, (2) settles using (1)'s output, and (3) samples (2)'s output at the edge — all "simultaneously" in the sense that there is no procedural sequencing in the synthesized device.

### 3.4 Worked plan — 8-bit accumulator with ready/valid

[V] The brief asks the consuming agent to plan, not code. Given the specification "accept an 8-bit signed `increment_value` once per cycle when valid, accumulate, wrap on overflow, and expose `accumulated_value` continuously," the plan is:

| Field | Value |
|---|---|
| Clocks | one (`clk`); single-clock-domain default |
| Reset | sync-released `rst`; initial value 0 |
| Throughput | 1 increment per clock (always-accept) |
| Latency | 1 clock from `increment_valid && increment_ready` to updated `accumulated_value` |
| Datapath width | 8-bit signed; wrap (no saturation) |
| Resource strategy | one 8-bit adder; one 8-bit flop; no DSP, no memory |
| Flow control | ready/valid; ready is constant high (always accept) |
| Pipeline cuts | none — adder + flop is one stage |

[O] An RTL skeleton drops out of this plan in roughly ten lines. The minimal pattern in §5 is built from this same plan; see also `references/projects/FPGADesignElements/Accumulator_Binary.v:35-47` for the same pattern parameterized for additional pipeline stages inside the accumulator loop.

## 4. Sequencing & timing

This doc covers latency/throughput **thinking**, not protocol timing. Protocol timing (ready/valid, FIFO occupancy, CDC) is owned by [20](20-ready-valid-handshakes.md), [22](22-fifos-synchronous-and-asynchronous.md), [23](23-cdc-single-bit.md), [24](24-cdc-multi-bit.md). Pipeline construction is owned by [15](15-pipelines-and-latency-thinking.md).

### 4.1 Throughput targets

[V] Pick a throughput target before drawing any datapath. The choice determines whether resources are duplicated, shared, or pipelined.

| Target | Implication |
|---|---|
| 1 result/clock | Combinational work between flops must fit in one period at the target fmax. Each operation has its own hardware. |
| 1 result/N clocks | Resource sharing is on the table — one ALU per N opcodes, one multiplier per N MAC ops. State machine drives the sharing. |
| Bursty (M back-to-back, then idle) | Pipeline depth ≤ M typically OK; otherwise size an output FIFO. |
| Command/response (request, idle, eventual response) | Latency dominates; throughput target may be very low; resource sharing is the default. |

Source for the framing: `library/topics/01_hardware_mindset_parallelism.md` §"Dataflow and Pipelining", which distills the patterns from FPGACPU's elastic-pipeline part library (`references/raw/fpgacpu/index.html` §"Elastic Pipelines") and ZipCPU `references/extracted_text/zipcpu/pipeline_control.txt:191-265` (Pipeline Strategies: apply every clock / wait for CE / move on request).

### 4.2 Latency budget

[V] Three flavors:

- **Fixed latency.** Output N clocks after input, every time. Easy to verify; required for cycle-accurate emulation interfaces.
- **Variable latency.** Output appears when ready; producer must tolerate the wait. Pair with valid (and possibly ready) handshake.
- **Backpressured.** Latency is whatever it takes; the consumer asserts `ready` when it can accept. Composable, but requires every stage in the chain to respect backpressure. Defer to [20](20-ready-valid-handshakes.md), [21](21-skid-buffers-and-register-slices.md).

### 4.3 The cycle-level schedule

[V] The pre-RTL plan culminates in a cycle-by-cycle schedule for non-trivial modules — a table whose rows are clock cycles and whose columns are pipeline stages, register-file ports, bus owners, etc. The schedule reveals contention (two writers to one register, two readers of one memory port) before the RTL is written and the symptom is a Quartus warning.

For emulation specifically, the schedule must match the original chip's published bus timing (or what reverse engineering has recovered from it). Era-faithful schedule construction is owned by [17](17-era-faithful-microarchitecture.md).

## 5. Minimal working pattern

The minimal pattern that demonstrates the mindset is **a register**. The FPGADesignElements Register module is excerpted below — it exists as a standalone module specifically because separating data from control "at the most basic level" is the discipline this whole doc is teaching.

```verilog
// references/projects/FPGADesignElements/Register.v:1-10 @ 2450a54
//# A Synchronous Register to Store and Control Data

// It may seem silly to implement a register module rather than let the HDL
// infer it, but doing so separates data and control at the most basic level,
// including various kinds of resets, which are part of control. This
// separation of data and control allows us to simplify the control logic and
// reduce the need for some routing resources.
```

```verilog
// references/projects/FPGADesignElements/Register.v:39-75 @ 2450a54
`default_nettype none

module Register
#(
    parameter WORD_WIDTH  = 0,
    parameter RESET_VALUE = 0
)
(
    input   wire                        clock,
    input   wire                        clock_enable,
    input   wire                        clear,
    input   wire    [WORD_WIDTH-1:0]    data_in,
    output  reg     [WORD_WIDTH-1:0]    data_out
);

    initial begin
        data_out = RESET_VALUE;
    end

// Here, we use the  "last assignment wins" idiom (See
// [Resets](./verilog.html#resets)) to implement reset.  This is also one
// place where we cannot use ternary operators, else the last assignment for
// clear (e.g.: `data_out <= (clear == 1'b1) ? RESET_VALUE : data_out;`) would
// override any previous assignment with the current value of `data_out` if
// `clear` is not asserted!

    always @(posedge clock) begin
        if (clock_enable == 1'b1) begin
            data_out <= data_in;
        end

        if (clear == 1'b1) begin
            data_out <= RESET_VALUE;
        end
    end

endmodule
```

[I] Read this as: **the deliverable** is a parameterized hardware primitive — one clock, one enable, one clear, one input bus, one output register, two assignments to the same register where the later assignment (clear) wins. There is no algorithm here. There is no loop iterating "over inputs." A schematic of this module is literally one flip-flop with two muxes. Larger circuits in this style compose from such primitives — see [02-source-map.md](02-source-map.md) and the FPGADesignElements library for the catalog.

[V] Composite example for the 8-bit accumulator from §3.4 (built from the same Register primitive plus an adder):

```systemverilog
// [I] composite, sketched per the plan in §3.4;
// component pattern from references/projects/FPGADesignElements/Accumulator_Binary.v @ 2450a54
module accumulator_8 (
    input  wire             clk,
    input  wire             rst,
    input  wire             increment_valid,
    output wire             increment_ready,  // always 1
    input  wire signed [7:0] increment_value,
    output reg  signed [7:0] accumulated_value
);
    assign increment_ready = 1'b1;

    always_ff @(posedge clk) begin
        if (rst)                      accumulated_value <= 8'sd0;
        else if (increment_valid)     accumulated_value <= accumulated_value + increment_value;
    end
endmodule
```

The plan from §3.4 maps line-for-line: one clock, sync-released reset, 8-bit signed wrap, one adder, one flop, always-ready handshake. The RTL did not invent any structure; it transcribed the plan.

## 6. Common variations across implementations

These are **style** choices among production codebases — all three produce correct, synthesizable circuits in the contract above. Picking among them is a project-level decision, not a correctness one.

- [O] **FPGADesignElements** (`references/projects/FPGADesignElements/`, commit `2450a54`): Verilog-2001 with `default_nettype none`, all widths parameterized, fine-grained modules down to single-purpose primitives. Default parameter values are intentionally `0` so elaboration fails loudly if the user forgets to set them. See `Register.v:42-45` for the convention. See `verilog_coding_standard.html:269-273` for the rationale ("give all parameters a default value of zero or an empty string... make module elaboration fail if any of the parameters are not set at module instantiation").
- [O] **lowRISC SystemVerilog style guide** (`references/projects/lowrisc-style-guides/VerilogCodingStyle.md`, commit `735d911`): SystemVerilog with `logic` everywhere instead of `reg`/`wire`, explicit `always_ff` for state and `always_comb` for combinational, `begin`/`end` even for single statements when wrapped. See `VerilogCodingStyle.md:268-288` for the canonical `always_ff @(posedge clk) begin ... end` pattern. This bundle's prescribed subset (doc [12](12-synthesizable-sv-subset.md)) tracks the lowRISC conventions.
- [O] **verilog-axis** (`references/projects/verilog-axis/`, commit `48ff7a7`): Verilog-2001 with ready/valid (AXI-Stream) handshake at every module boundary; pipelines are composed of registered slices; back-pressure is universal. See `rtl/axis_adapter.v:63-77` for the canonical s_axis_t* / m_axis_t* port shape with `tvalid` / `tready` / `tdata` / `tlast`. The mindset implication: every module is independently testable in isolation because the protocol composes.

## 7. Anti-patterns (mistakes that compile but break)

This section enumerates mindset-level anti-patterns. Several anti-patterns in the bundle's master list (`90-anti-patterns.md`) have their primary treatment in other docs; those are introduced here with cross-references rather than duplicated.

### 7.1 No pre-RTL plan — coding begins immediately

- **Symptom:** repeated rewrites; CDC discovered late; pipeline depth changes break downstream alignment; fmax surprises in the first place-and-route.
- **Cause:** the consuming agent jumped from problem statement to `always_ff` without naming clocks, reset behavior, throughput, latency, or resource strategy. There is no document the reviewer can read except the RTL itself.
- **Fix:** stop. Write the plan per §3.1 (the field table). Do not resume coding until the plan exists and a reviewer can answer the throughput, latency, and resource questions without seeing the RTL.
- **Citation:** `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt` p2 §"Before You Begin" @ 2016-11 ("Use this document to help you plan the FPGA and system early in the design process, which is crucial for a successful design") and p3 Table 2 item 1 (the Design Specifications Checklist).

### 7.2 For-loop written as software iteration  *(anti-pattern #8 — primary home)*

- **Symptom:** the RTL "looks right" — a `for` loop reads as if it does N steps in sequence. Synthesis either: (a) produces an enormous combinational tree that misses fmax by an order of magnitude; (b) unrolls into thousands of repeated gates and overflows the device; or (c) — with a non-static loop bound — fails elaboration with an out-of-memory error.
- **Cause:** the author wrote the loop expecting it to **execute** at runtime, the way a C `for` loop does. In synthesizable RTL there is no runtime sequencing inside an `always` block: the loop is **unrolled at elaboration** into parallel hardware. A loop with no static end produces infinite hardware.
- **Fix:** decide what the loop is actually for.
  - If the work must happen **per cycle in parallel** (e.g. compute a parity over 32 bits): keep the `for` inside an `always_comb`, ensure the bound is a `localparam` or compile-time expression, and confirm by reading the elaboration report that the hardware count matches expectation.
  - If the work must happen **sequentially over many cycles** (e.g. iterate over 256 memory addresses): the loop is not a loop — it is a state machine with a counter. Rewrite as an FSM with a `count` register, a `count_done` predicate, and a per-cycle work step. See [14-finite-state-machines.md](14-finite-state-machines.md).
  - If the work must happen **on a pipeline** (e.g. apply f to a stream of inputs): the loop is a pipeline. See [15-pipelines-and-latency-thinking.md](15-pipelines-and-latency-thinking.md).
- **Citation:** `references/extracted_text/zipcpu/class_verilog.txt:14258-14263`, verbatim:

```text
// references/extracted_text/zipcpu/class_verilog.txt:14258-14263 @ 2026-05-20
The end condition will therefore elaborate to either NM or NS,
both of which are non-zero and therefore "true".
As for the out-of-memory error, remember this is hardware.
Yosys is elaborating new hardware circuits every time through
the loop, and the loop doesn't have an end.
```

Reinforced by `references/raw/fpgacpu/verilog_coding_standard.html:539-547` ("If you need to iteratively create assignments... you can use a for loop inside an always block. Doing it this way is also necessary sometimes if the logic may appear to cause conflicting updates to the same variables. Synthesis tools expect all such assignments to be inside the same always block").

### 7.3 Software-algorithm transliteration

- **Symptom:** the RTL is structured as deeply nested `if/else` chains, "do step X, then step Y, then step Z" comments, scratch variables that are written and read multiple times in the same block, monolithic `always_ff` that drives many unrelated outputs. fmax is poor; the schematic is a mess of random logic.
- **Cause:** the author started from a C/Python reference and translated it line-by-line, treating the `always` block as a function body.
- **Fix:** discard the transliteration. Redo §3.1. Identify what is parallel state, what work happens per cycle, where the original logic serialized things only because the reference machine had one ALU. Reshape the design as datapath + control + interface (per §2 [V] and `system_design_standard.html:118-122`).
- **Citation:** [I]. Synthesized from `references/raw/fpgacpu/system_design_standard.html:93-100` (the modularization principle: "move unrelated connections into separate modules") and `library/topics/01_hardware_mindset_parallelism.md` §"Avoid Software-Shaped RTL". No single source establishes this anti-pattern by name; this doc owns it.

### 7.4 Linear software state machine instead of mirroring the original chip's bus/control structure  *(anti-pattern #34 — brief treatment; full home in 17)*

- **Symptom:** in an emulation core, an FSM with states like `IDLE → FETCH_OPCODE → DECODE → EXEC_STEP_1 → EXEC_STEP_2 → WRITEBACK`, where each state was named after a phase of the algorithm in a programmer's manual. Behavior may approximate the original chip on simple tests, but fails on cycle-exact compatibility tests (timing-dependent demos, raster effects, bus-contention exploits).
- **Cause:** the author planned the FSM as if writing a software interpreter — one state per algorithmic step — rather than mirroring the original chip's actual bus phases (T1/T2/T3..., M1/M2/M3..., or whichever cycle-level skeleton that silicon used). The synthesized hardware does not produce the same bus transactions in the same cycles as the silicon.
- **Fix:** reverse-engineer the original chip's bus/control skeleton from datasheets, die shots, and behavioral references; let that skeleton **be** the FSM. Resource sharing patterns (one ALU across multiple subcycles; one register-file port for both source and destination) follow the era's silicon, not modern FPGA preferences. Full treatment, including the single-bus-architecture pattern and shared-ALU mirroring rules, is in [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md).
- **Citation:** [I]. Synthesized from the resource-budget vs cycle-accuracy inference in §2 of this doc and from the era-faithful microarchitecture brief; primary home is [17](17-era-faithful-microarchitecture.md).

### 7.5 Module hierarchy mirrors call-graph of a software port

- **Symptom:** top-level module is named `main`; submodules are named after C functions; signals are named like function arguments. Schematic shows long, linear chains; CDC boundaries cross module boundaries arbitrarily; reuse across cores is impossible.
- **Cause:** the author treated module instantiation as function call. Hardware hierarchy and software call hierarchy are different decompositions of the same problem.
- **Fix:** rebuild the hierarchy along hardware lines per `references/raw/fpgacpu/system_design_standard.html:93-100`: move unrelated connections into separate modules. Use the Core / Instance / Adapter / Shim layering described in `system_design_standard.html:144-201` — Core is application logic, Instance scales it to this FPGA, Adapter handles board-specific I/O, Shim handles PCB-specific pinout. For emulation, the Core mirrors the original chip; the Adapter wraps the framework (e.g. MiSTer); the Shim is the pin file.
- **Citation:** `references/raw/fpgacpu/system_design_standard.html:93-100, 144-201` @ 2026-05-20.

### 7.6 Monolithic always block  *(anti-pattern #1 — full treatment in 13)*

- **Symptom:** one `always_ff` block drives ten or more unrelated registers; the block is hundreds of lines long; one logical change requires reading the whole block to verify it does not break an unrelated output.
- **Cause:** failure to apply the rule "one logical concern per always block."
- **Fix:** split. The full rule (one-driver-per-signal, blocking-in-comb vs nonblocking-in-seq, one concern per block) is owned by [13-registers-and-combinational-blocks.md](13-registers-and-combinational-blocks.md).
- **Citation:** see [13](13-registers-and-combinational-blocks.md) §7; underlying source `references/raw/fpgacpu/verilog_coding_standard.html:481-506`.

## 8. Verification

This doc's verification artifact is the **pre-RTL plan itself**, not a testbench. Three checks:

1. **Pre-RTL gate.** Before any RTL is written for a non-trivial module, the plan exists per §3.1. A reviewer can answer the following without reading code: What are the clocks and reset assumptions? What is the throughput target? What is the latency? What is the resource strategy (parallel vs shared)? What is the flow-control mechanism? Where are the pipeline cuts? For emulation work: what is the original chip's bus skeleton being mirrored?
2. **Plan-vs-RTL trace.** After the first synthesizable cut, simulate one clock cycle and trace it: every event the plan says occurs that cycle (a register updates, a bus is driven, a handshake fires) must occur in the waveform. Any mismatch is a bug — either in the plan or in the RTL. Do not "fix" the plan to match the code; revisit which one was wrong.
3. **Schematic check.** Open the post-elaboration and post-synthesis schematic in Quartus and confirm that pipeline-stage count and the rough shape of the datapath match the plan. See `references/raw/fpgacpu/system_design_standard.html:69-83` for the rationale ("The post-elaboration schematic gives you a block diagram view of your source code, which allows you to more easily find missing connections and count pipeline stages"). Reading Quartus reports for resource and timing utilization is in [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md).

Substantive verification methodology (testbench style, SVA handshake assertions, reset/edge coverage) is owned by [41](41-quartus-reports-and-verification.md).

## 9. Provenance footer

- `references/raw/fpgacpu/verilog_coding_standard.html` @ 2026-05-20 (FPGACPU snapshot) — used for §2 [C] concurrency/loop framing, §2 [V] parameterization rule, §3, §6 (FPGADesignElements convention), §7.2 reinforcement, §7.6 citation.
- `references/raw/fpgacpu/system_design_standard.html` @ 2026-05-20 — used for §2 [V] modularization rule, §3.2 schematic check, §6 (Core/Instance/Adapter/Shim implied), §7.3 citation, §7.5 citation, §8 check 3.
- `references/raw/fpgacpu/index.html` @ 2026-05-20 — used for §4.1 (Elastic Pipelines part-library framing).
- `references/projects/FPGADesignElements/Register.v` @ commit `2450a54` — used for §5 (minimal pattern excerpt), §6 [O] (FPGADesignElements style).
- `references/projects/FPGADesignElements/Accumulator_Binary.v` @ commit `2450a54` — used for §3.4 and §5 (composite pattern reference).
- `references/projects/lowrisc-style-guides/VerilogCodingStyle.md` @ commit `735d911` — used for §6 [O] (lowRISC style).
- `references/projects/verilog-axis/rtl/axis_adapter.v` @ commit `48ff7a7` — used for §6 [O] (verilog-axis ready/valid-at-every-boundary style).
- `references/extracted_text/zipcpu/class_verilog.txt` @ 2026-05-20 (PDF text extraction) — used for §2 [C] for-loop-elaboration rule, §7.2 primary citation (verbatim excerpt).
- `references/extracted_text/zipcpu/pipeline_control.txt` @ 2026-05-20 (PDF text extraction) — used for §4.1 (Pipeline Strategies framing).
- `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt` (Altera AN-662-1.3) pp.2–3 §"Before You Begin", §"Design Specifications" @ 2016-11 — used for §2 [V] pre-RTL plan rule, §7.1 citation.
- `references/raw/intel/cyclone_v_product_table_api.txt` @ 2026-05-20 — used for §2 [I] Cyclone V resource-budget inference (110K ALMs, 5.6 Mbit memory, 112 DSP).
- `library/topics/01_hardware_mindset_parallelism.md` (rough notes) — referenced for structure only in §2 [V], §4.1 framing, §7.3 inference. Not cited as primary authority.
