# 41 — Quartus Reports & Verification

> Bundle version: 2026-05-19
> Pinned commits: see [references/MANIFEST.md](../references/MANIFEST.md) — `references/projects/wb2axip/` (skidbuffer.v, bench/formal/faxis_master.v), `references/raw/zipcpu/axi_rules.html`, `references/raw/zipcpu/formal_index.html`, `references/projects/verilog-axis/tb/axis_register/test_axis_register.py`, `references/raw/style/lowrisc_systemverilog_style.md`.
> Load with: [11-clocking-resets-and-cyclone-v-clock-networks.md](11-clocking-resets-and-cyclone-v-clock-networks.md), [13-registers-and-combinational-blocks.md](13-registers-and-combinational-blocks.md), [20-ready-valid-handshakes.md](20-ready-valid-handshakes.md), [22-fifos-synchronous-and-asynchronous.md](22-fifos-synchronous-and-asynchronous.md), [40-timing-closure-and-sdc.md](40-timing-closure-and-sdc.md)
> Status mix: heavy [C] for report-reading and resource-confirmation rules; [V] for testbench-and-SVA conventions; [O] for variant flows; one [I] mindset rule. Roughly 5 × [C], 6 × [V], 4 × [O], 2 × [I].
> Missing inputs: the Intel HTML pages in `references/raw/intel/` (`quartus_standard_design_recommendations_index.html`, `quartus_standard_register_latch_guidelines.html`, `quartus_metastability_management.html`, `quartus_standard_timing_analyzer.html`) are app-shells with no body content. They are cited as live URLs only; no verbatim excerpts are possible. The `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt` text capture contains no report-section text matching `synthesis`, `report`, or `warning` and is not cited here.

---

## 1. Purpose & one-line summary

Three artifacts decide whether RTL is correct on a Cyclone V: Quartus synthesis and Fitter reports prove that the textual RTL became the intended circuit (RAM landed in M10K, multiplier in a DSP block, no register was silently removed or merged); TimeQuest proves the circuit closes timing; and a scoreboarded testbench plus a handful of SystemVerilog Assertions (SVA) on each handshake prove the circuit is functionally correct. This doc tells the consuming agent which report sections to open after every compile, how to write a deterministic testbench with a reference-model scoreboard, and how to write the three handshake SVA properties (no-valid-drop, payload-stable-while-stalled, post-reset-clean) that catch bugs simulation alone would miss. **Deep formal verification — SymbiYosys, k-induction, full property suites — is OUT OF SCOPE for this bundle**; if you need to prove a master, slave, or protocol bridge correct under all inputs, see `references/projects/wb2axip/bench/formal/` and the SymbiYosys flow ZipCPU documents at `references/raw/zipcpu/formal_index.html`. SDC syntax (`create_clock`, `set_input_delay`, false/multicycle paths) is deferred to [40-timing-closure-and-sdc.md](40-timing-closure-and-sdc.md); ready/valid protocol rules to [20-ready-valid-handshakes.md](20-ready-valid-handshakes.md); reset and clock-domain construction to [11-clocking-resets-and-cyclone-v-clock-networks.md](11-clocking-resets-and-cyclone-v-clock-networks.md).

Deliverables this doc produces:

- A post-compile report-reading checklist (§4 and §8).
- A copy-pasteable scoreboarded testbench skeleton (§5, Pattern A).
- A copy-pasteable bound SVA module with three handshake properties (§5, Pattern B; §3 has the property definitions).

---

## 2. The contract (must-obey)

- [C] After every Quartus Analysis & Synthesis run, the synthesis report is read and every latch-inferred, register-removed, register-merged, node-has-no-driver, and node-has-no-fanout warning is investigated and either fixed or annotated with a written waiver in the project — never silently passed over. Cite Intel Quartus Standard Edition User Guide: Design Recommendations (live URL <https://docs.altera.com/r/docs/683323/current>; app-shell, no local capture).
- [C] Every inferred RAM and every inferred multiplier is confirmed in the Fitter "Resource Utilization by Entity" report to have landed on the intended primitive: M10K vs MLAB vs LUT-RAM for memory; variable-precision DSP block vs ALM-based multiplier for arithmetic. Cross-ref [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md) and [31-dsp-inference-cyclone-v.md](31-dsp-inference-cyclone-v.md). Cite Intel Design Recommendations, "Inferring RAM Functions" and "Inferring Multipliers" sections (live URL <https://docs.altera.com/r/docs/683323/current>; app-shell, no local capture). [C]
- [C] TimeQuest worst-case setup slack and worst-case hold slack are read and recorded after every Fitter run; any negative slack is either fixed before integration or explicitly waived with a written rationale (typically a `set_false_path` or `set_multicycle_path` exception in SDC). Cite Intel Quartus Standard Edition Timing Analyzer User Guide (live URL <https://docs.altera.com/r/docs/683068/current>; app-shell, no local capture). [C]
- [C] The Quartus metastability report (`Report Metastability` in TimeQuest) is opened on every compile; every recognized 2FF synchronizer chain has an MTBF estimate, and any unsynchronized signal crossing between asynchronous clock domains is treated as a bug, not a warning. Cite Intel Managing Metastability documentation (live URL <https://docs.altera.com/r/docs/683323/current>; app-shell, no local capture). [C]
- [C] Recovery and removal slack for asynchronous resets are read alongside setup/hold; negative recovery/removal is a release-time hazard that must be fixed before integration. Cite Intel Timing Analyzer User Guide (live URL <https://docs.altera.com/r/docs/683068/current>; app-shell, no local capture). [C]
- [V] Every non-trivial module has a separate testbench module in a `tb/` directory; the testbench instantiates the DUT, drives a deterministic clock (e.g. `always #5 clk = ~clk;`), drives a deterministic reset sequence, applies stimulus from a queue, captures outputs into a second queue, and ends with an `assert` that compares the output queue against a reference-model queue. Cite `references/projects/verilog-axis/tb/axis_register/test_axis_register.py:99-107` (cocotb-style send/recv-and-compare scoreboard; treat as [O] template translated to native SV for self-containment). [V]
- [V] Every handshake interface is protected by at least three concurrent SVA properties: (1) `valid` does not drop unless a transfer occurred (no-valid-drop); (2) payload is stable while `valid && !ready` (payload-stable); (3) `valid` is low for at least one cycle after reset deassert (reset-clean). Cite `references/projects/wb2axip/rtl/skidbuffer.v:277-289` for the concurrent-property form and `references/raw/zipcpu/axi_rules.html:419-468` for the underlying invariants. [V]
- [V] SVA properties live with the producer module — either inline under `` `ifdef FORMAL `` or in a separate module bound via `bind` — so the property text and the RTL it constrains live together and can never drift out of sync. Cite `references/projects/wb2axip/rtl/skidbuffer.v:244-291` for the `` `ifdef FORMAL `` placement convention. [V]
- [V] In a simulation flow (no formal solver), properties about the DUT are `assert`s and properties about the *environment* (stimulus shape, upstream behavior) are `assume`s; never swap them, because an `assume` silently constrains stimulus and a swapped `assume` will pass vacuously. Cite `references/raw/zipcpu/axi_rules.html:412-414` (the `assume(!ARESETN)` example demonstrates `assume` as environment constraint, paired with `assert` for DUT property). [V]
- [V] Every register is observed in simulation at both its reset value and at a non-reset value before integration; "reset coverage" is the convention name. Cite `references/raw/style/lowrisc_systemverilog_style.md:1908-1928` (extensive-use-of-SVAs and reset-discipline rationale). [V]
- [V] `X` literals are not assigned in RTL to indicate "don't care"; invalid conditions are flagged with SVAs (`` `ASSERT_KNOWN `` style) instead. Cite `references/raw/style/lowrisc_systemverilog_style.md:1905-1909`. [V]
- [O] cocotb (Python testbenches driving the RTL through ModelSim or Verilator) is a valid alternative to a native-SV testbench but is **not part of the Quartus 18.1 toolchain**; adopt it only if the project commits to maintaining a separate Python verification environment. Cite `references/projects/verilog-axis/tb/axis_register/test_axis_register.py:31-39` (cocotb import surface and TB class). [O]
- [I] An SVA property whose body re-implements the RTL it is checking is worthless — the assertion logic itself contains the design under test, so any bug in the RTL is reproduced in the assertion and the assertion passes vacuously. Properties must express *invariants* (orderings, stabilities, conservation laws), never recomputations. Inferred from the ZipCPU formal mindset across `references/raw/zipcpu/formal_index.html` (multiple posts emphasizing invariant-vs-recomputation) and the stability-only character of `references/projects/wb2axip/rtl/skidbuffer.v:277-289`. [I]

---

## 3. Constructs / SVA reference

The §2 contract names three properties every handshake must carry: no-valid-drop, payload-stable, reset-clean. This section gives them in concurrent-property form (parseable by ModelSim / Questa Intel FPGA Edition in the Quartus 18.1-era flow), anchored to verbatim source.

**Verbatim anchor — concurrent property form (from wb2axip skidbuffer):**

```systemverilog
// references/projects/wb2axip/rtl/skidbuffer.v:276-290 @ 2024-snapshot
    // Reset properties
    property RESET_CLEARS_IVALID;
        @(posedge i_clk) i_reset |=> !i_valid;
    endproperty

    property IDATA_HELD_WHEN_NOT_READY;
        @(posedge i_clk) disable iff (i_reset)
        i_valid && !o_ready |=> i_valid && $stable(i_data);
    endproperty

`ifdef    SKIDBUFFER
    assume    property (IDATA_HELD_WHEN_NOT_READY);
`else
    assert    property (IDATA_HELD_WHEN_NOT_READY);
`endif
```

`RESET_CLEARS_IVALID` is the reset-clean property. `IDATA_HELD_WHEN_NOT_READY` is the payload-stable-and-no-valid-drop property combined (it asserts both `i_valid` remains true and `$stable(i_data)` holds whenever the previous cycle had `i_valid && !o_ready`). The `` `ifdef SKIDBUFFER `` switch lets the same file act as either the DUT (where the property is an `assert` on its own behavior) or the environment of a peer skidbuffer (where the property is an `assume` constraining the stimulus).

**Verbatim anchor — immediate-assertion form (from ZipCPU axi_rules):**

```systemverilog
// references/raw/zipcpu/axi_rules.html:465-468 @ retrieved-2026
    end else if ($past(M_AXIS_TVALID && !M_AXIS_TREADY))
    begin
        assert(M_AXIS_TVALID);
        assert($stable(M_AXIS_TDATA));
```

This is the same invariant expressed as immediate assertions inside an `always @(posedge ACLK)` block — equivalent semantics, different style. Note that `axi_rules.html` favors the immediate form throughout; `skidbuffer.v` uses the concurrent form under a `` `ifdef VERIFIC `` guard. Either is acceptable. The concurrent form is preferred when binding into an external assertion module (§5, Pattern B). [V]

**Three named properties for a generic ready/valid stream (concurrent form):**

```systemverilog
// Derived from references/raw/zipcpu/axi_rules.html:460-468 and
// references/projects/wb2axip/rtl/skidbuffer.v:277-289 — recast into named
// concurrent properties suitable for `bind`-ing onto any handshake interface.

// Property 1: no-valid-drop. If the previous cycle had valid && !ready, then
// the producer must still be asserting valid this cycle.
property p_valid_no_drop;
    @(posedge aclk) disable iff (!aresetn)
    $past(valid && !ready) |-> valid;
endproperty
a_valid_no_drop: assert property (p_valid_no_drop);

// Property 2: payload-stable. If the previous cycle had valid && !ready, then
// the payload is unchanged this cycle.
property p_payload_stable;
    @(posedge aclk) disable iff (!aresetn)
    $past(valid && !ready) |-> $stable(payload);
endproperty
a_payload_stable: assert property (p_payload_stable);

// Property 3: reset-clean. While reset is active, valid must be low; on the
// cycle reset deasserts, valid must still be low.
property p_reset_clears_valid;
    @(posedge aclk) !aresetn |=> !valid;
endproperty
a_reset_clears_valid: assert property (p_reset_clears_valid);
```

These three are semantically distinct — (1) catches a producer that drops `valid` mid-stall, (2) catches a producer that wiggles `payload` mid-stall, (3) catches a producer whose `valid` flop is uninitialized or escapes reset early. Together they enforce the [20-ready-valid-handshakes.md](20-ready-valid-handshakes.md) protocol on any interface they are bound to. [V]

**Construct reference table:**

| Construct | What it asserts | Where it lives |
|---|---|---|
| `assert property (...)` (concurrent) | Temporal invariant over multiple clocks (sampled at the clocking event). | In the producer module under `` `ifdef FORMAL ``, or in a separate module bound via `bind`. |
| `assume property (...)` | Constraint on the *environment* feeding the DUT (used by formal solvers; in simulation it constrains random stimulus but otherwise behaves like `assert`). | Only at module boundaries where the input is treated as adversarial; never on internal DUT signals. |
| `cover property (...)` | Asks the simulator/solver to record whether the property was ever satisfied — used to measure reachability of interesting states. | Alongside `assert`s; useful for scoreboard reset-coverage gates. |
| `$past(signal)` | Value of `signal` at the previous clocking event. | Only inside concurrent properties or inside an `always @(posedge ...)` block. |
| `$past(signal, N)` | Value of `signal` N clocks ago. | Same; rarely needed for handshake invariants. |
| `$stable(signal)` | `signal == $past(signal)` at this clocking event. | Same. |
| `$rose(signal)` | Signal transitioned 0→1 since the previous clocking event. | Same; used for edge-coverage properties. |
| `$fell(signal)` | Signal transitioned 1→0 since the previous clocking event. | Same. |
| `disable iff (expr)` | Suppresses the property whenever `expr` is true (typically `(!aresetn)` to silence properties during reset). | At the head of every reset-sensitive concurrent property. |
| `\|->` (overlapped implication) | LHS sequence ends on the same cycle the RHS starts. | Between antecedent and consequent of an implication property. |
| `\|=>` (non-overlapped implication) | LHS sequence ends one cycle before the RHS starts. | Same; used when the RHS describes the *next* cycle's behavior. |
| `bind <target> <module> <inst> (.*);` | Inserts an instance of an assertion-only module into every instance of the target module, with the same name resolution as if the bound module were textually inside the target. | In the testbench or in a separate `bind` file; never inside the synthesizable RTL. |
| ModelSim `+sva` / `vlog -sv -assertdebug` | Enable concurrent-assertion checking at sim time. | In the simulation Makefile; document the flag explicitly. |

Cite `references/projects/wb2axip/rtl/skidbuffer.v:244-291` for `` `ifdef FORMAL `` placement and concurrent-property syntax. [V]
Cite `references/raw/zipcpu/axi_rules.html:404-468` for the `f_past_valid` initialization idiom and immediate-assertion style. [V]
The `bind` directive is standard SystemVerilog (IEEE 1800-2017 §23.11); not corpus-cited, marked [I].

---

## 4. Sequencing & report navigation

After every `quartus_sh --flow compile` invocation, the agent walks four reports in this fixed order:

**4.1 Analysis & Synthesis report (`output_files/<project>.map.rpt`)**

Open in this section order:

- **Resource Usage Summary.** Coarse totals — number of registers, number of LUTs, number of RAM blocks, number of DSP blocks. Use as a sanity check against expected module size.
- **Inferred Memory Blocks** (or "RAM Summary"). Every inferred memory appears here with: instance name, requested attributes, inferred port mode, and recognized primitive (M10K, MLAB, LUT-RAM). If an `(* ramstyle = "M10K" *)` attribute was specified and the inferred row says "MLAB" or "logic", Quartus did not honor the request — investigate why before the Fitter runs. (Cross-ref [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md).)
- **Inferred Multipliers / DSP Blocks.** Every multiplier appears here; the recognized form (`a*b`, `a*b+c`, etc.) and the target DSP-block configuration are listed. Multipliers that didn't infer to a DSP block appear in the ALM area; this is sometimes intentional (small widths, no pipeline registers) and sometimes a bug. Cross-ref [31-dsp-inference-cyclone-v.md](31-dsp-inference-cyclone-v.md).
- **Register Statistics.** Counts of registers by clock, by enable, by sync/async clear. Useful to spot unexpected register collapse.
- **Warnings panel.** Filter for these strings and investigate every match:
  - "inferred latch" / "latch inferred" — a combinational block left an output undriven on some branch ([13-registers-and-combinational-blocks.md](13-registers-and-combinational-blocks.md) §7).
  - "removed register" / "register removed" — Quartus eliminated a flop because it was constant, never read, or merged with another. Sometimes intentional (parameter-controlled feature off); always worth confirming.
  - "merged register" — two flops with identical drivers were combined. Usually harmless; review if the two flops were intended to have different reset values or different physical placement.
  - "node has no driver" / "stuck at GND" / "stuck at VCC" — a signal was declared but never assigned, or was assigned to a constant after optimization.
  - "node has no fanout" — a signal was driven but never read. Common after refactoring; either delete the declaration or wire it somewhere.

Cite Intel Quartus Standard Edition User Guide: Design Recommendations (live URL <https://docs.altera.com/r/docs/683323/current>; app-shell, no local capture) for the canonical warning strings and recommended responses.

**4.2 Fitter report (`output_files/<project>.fit.rpt`)**

- **Resource Utilization by Entity.** Walk down the module hierarchy: for every module that should contain an M10K, MLAB, or DSP block, confirm the count under the appropriate column. If a module specifying `(* ramstyle = "M10K" *)` shows zero "M10K Blocks" but non-zero "MLAB Memory Bits", the synthesis attribute was overridden — usually because the port configuration (true-dual-port with mismatched widths, or read-during-write mode set incorrectly) was incompatible with M10K and Quartus silently fell back. Investigate; do not accept the fallback. (Cross-ref [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md).)
- **Pin-Out File** (`<project>.pin`) and **I/O Bank** summary. Confirm every signal landed on the intended pin and bank; an unplaced or wrong-bank pin will not break compile but will silently fail on the board.
- **Floorplan view** (Chip Planner in the GUI). Spot-check that critical-path modules are not pathologically scattered.
- **Incremental Compile / Design Partitions** (if used). Confirm partition boundaries match the project plan.

Cite Intel Quartus Standard Edition User Guide: Design Recommendations (live URL <https://docs.altera.com/r/docs/683323/current>; app-shell, no local capture).

**4.3 TimeQuest (`output_files/<project>.sta.rpt`, or the GUI Timing Analyzer)**

- `Report Clocks` — confirm every clock has been declared with `create_clock` or `create_generated_clock` and that the periods match the design intent.
- `Report Setup` — read worst-case setup slack across every clock. The slack must be ≥ 0; the worst path appears at the top with "Data Path" detail showing the source register, the combinational logic between them, and the destination register.
- `Report Hold` — same procedure for hold slack. Hold violations cannot be fixed by lowering fmax; they require RTL-level pipelining or SDC `set_min_delay` exceptions.
- `Report Recovery` and `Report Removal` — async-deassertion slack for reset and async-clear nets. Negative recovery means the reset deassertion arrives too close to the next active clock edge for safe release.
- `Report Metastability` — every 2FF synchronizer Quartus recognized appears here with an MTBF estimate. A signal that crosses clock domains and *doesn't* appear in this report is an un-synchronized crossing — investigate immediately. (Cross-ref [23-cdc-single-bit.md](23-cdc-single-bit.md).)

Cite Intel Quartus Standard Edition Timing Analyzer User Guide (live URL <https://docs.altera.com/r/docs/683068/current>; app-shell, no local capture) for the canonical report names and their fields. Cite Intel Managing Metastability documentation (live URL <https://docs.altera.com/r/docs/683323/current>; app-shell, no local capture) for `Report Metastability` semantics.

**4.4 Simulation log**

- ModelSim / Questa Intel FPGA Edition is invoked with `+sva` (or `vlog -sv -assertdebug`) so concurrent properties are checked.
- Every `assert` failure is fatal; the testbench `$finish`es on first failure and the log file is grepped for `# **`-prefixed error lines.
- The scoreboard's final compare is the last thing the testbench does before `$finish` — a green run means stimulus completed and outputs matched the reference model.

---

## 5. Minimal working pattern

Two minimal patterns. Both are intended to be copy-pasted into a fresh project and adapted.

### Pattern A — Testbench skeleton with reference-model scoreboard

This is composite RTL [I], translated into native SystemVerilog from the cocotb send/recv pattern in `references/projects/verilog-axis/tb/axis_register/test_axis_register.py:74-110`. The verilog-axis test uses `tb.source.send(test_frame)` and `tb.sink.recv()` to push and pop the scoreboard queues; the SV translation below uses native SV queues and a `fork`/`join_none` driver/monitor pair to match.

```systemverilog
// Composite [I] — derived from references/projects/verilog-axis/tb/axis_register/test_axis_register.py:74-110
// Pattern: drive stimulus from queue; capture outputs to queue; final-compare against reference model.
`timescale 1ns/1ps
module tb_my_dut;
    logic        clk = 0;
    logic        rst_n = 0;
    logic        s_valid, s_ready;
    logic [7:0]  s_data;
    logic        m_valid, m_ready = 1'b1;
    logic [7:0]  m_data;

    // Clock and reset
    always #5 clk = ~clk;                       // 100 MHz
    initial begin
        rst_n = 1'b0;
        @(posedge clk); @(posedge clk);
        rst_n = 1'b1;
    end

    // DUT
    my_dut dut (.clk(clk), .rst_n(rst_n),
                .s_valid(s_valid), .s_ready(s_ready), .s_data(s_data),
                .m_valid(m_valid), .m_ready(m_ready), .m_data(m_data));

    // Scoreboard queues
    byte stimulus_q[$];
    byte expected_q[$];   // reference model output
    byte captured_q[$];

    // Reference model: identity (replace with the actual transform under test)
    function automatic byte ref_model(input byte x); return x; endfunction

    // Driver: pop stimulus, drive s_valid/s_data, observe s_ready
    initial begin : driver
        s_valid = 1'b0; s_data = '0;
        wait (rst_n);
        forever begin
            @(posedge clk);
            if (stimulus_q.size() == 0) begin
                s_valid <= 1'b0;
            end else if (!s_valid || s_ready) begin
                s_data  <= stimulus_q[0];
                s_valid <= 1'b1;
                if (s_valid && s_ready) stimulus_q.pop_front();
            end
        end
    end

    // Monitor: capture m_data on every (m_valid && m_ready)
    initial begin : monitor
        wait (rst_n);
        forever begin
            @(posedge clk);
            if (m_valid && m_ready) captured_q.push_back(m_data);
        end
    end

    // Test body
    initial begin : test
        for (int i = 0; i < 32; i++) begin
            byte x = $urandom_range(0, 255);
            stimulus_q.push_back(x);
            expected_q.push_back(ref_model(x));
        end
        wait (stimulus_q.size() == 0);
        repeat (16) @(posedge clk);             // drain
        if (captured_q.size() != expected_q.size())
            $fatal(1, "scoreboard size mismatch: got %0d, expected %0d",
                   captured_q.size(), expected_q.size());
        foreach (expected_q[i])
            assert (captured_q[i] == expected_q[i])
                else $fatal(1, "scoreboard mismatch at %0d: got 0x%02h, expected 0x%02h",
                            i, captured_q[i], expected_q[i]);
        $display("PASS");
        $finish;
    end
endmodule
```

The structure mirrors the cocotb test: deterministic clock and reset, a stimulus queue, a captured-output queue, a reference-model queue, and a final element-by-element compare. The `$fatal` calls make any mismatch immediately fatal. A regression is then just "rerun and look for `PASS`".

### Pattern B — Bind-style SVA module for a ready/valid stream

This is the canonical place to put the §3 properties. The properties are written once in a small `handshake_props` module; the testbench (or a top-level `bind` file) attaches one instance per handshake to be checked.

```systemverilog
// Pattern derived from references/projects/wb2axip/rtl/skidbuffer.v:244-291
// (the `ifdef FORMAL block) and from the named-properties form in §3.
module handshake_props #(parameter int W = 8) (
    input  logic           aclk,
    input  logic           aresetn,
    input  logic           valid,
    input  logic           ready,
    input  logic [W-1:0]   payload
);
    // Property 1: no-valid-drop while stalled.
    property p_valid_no_drop;
        @(posedge aclk) disable iff (!aresetn)
        $past(valid && !ready) |-> valid;
    endproperty
    a_valid_no_drop: assert property (p_valid_no_drop)
        else $error("valid dropped while stalled");

    // Property 2: payload stable while stalled.
    property p_payload_stable;
        @(posedge aclk) disable iff (!aresetn)
        $past(valid && !ready) |-> $stable(payload);
    endproperty
    a_payload_stable: assert property (p_payload_stable)
        else $error("payload changed while stalled");

    // Property 3: valid low for the cycle after reset deassert.
    property p_reset_clears_valid;
        @(posedge aclk) !aresetn |=> !valid;
    endproperty
    a_reset_clears_valid: assert property (p_reset_clears_valid)
        else $error("valid not cleared after reset");
endmodule
```

To attach this to a DUT's input or output handshake, add this `bind` in the testbench:

```systemverilog
// Bind one assertion instance per handshake on the DUT under test.
bind my_dut handshake_props #(.W(8)) u_props_in (
    .aclk    (clk),
    .aresetn (rst_n),
    .valid   (s_valid),
    .ready   (s_ready),
    .payload (s_data)
);
bind my_dut handshake_props #(.W(8)) u_props_out (
    .aclk    (clk),
    .aresetn (rst_n),
    .valid   (m_valid),
    .ready   (m_ready),
    .payload (m_data)
);
```

The bound module sees the DUT's net names as if it were textually inside the DUT, so its assertions execute under the DUT's elaboration context. This is the standard "assertion module bound to the RTL it constrains" idiom; `references/projects/wb2axip/bench/formal/faxis_master.v:103-138` does the same job for AXI-Stream masters (using assumes in the slave-facing direction and asserts in the master-facing direction).

**Self-check:** every concurrent property above uses `@(posedge ...) disable iff (...) ... |-> ...` or `|=> ...` correctly; every property body is a parseable SVA sequence; `$past` and `$stable` are used inside concurrent properties only.

---

## 6. Common variations across implementations

- [O] **Inline assertions inside the RTL module, gated by `` `ifdef FORMAL ``.** The properties live in the same `.v` / `.sv` file as the RTL they constrain, after the `endmodule` of the synthesizable code or near the end inside a guarded block. Easiest to maintain (the properties move with the RTL when the file moves) but mixes verification text into the production file. Cite `references/projects/wb2axip/rtl/skidbuffer.v:244-291` (the `` `ifdef FORMAL `` block at the bottom of the file).
- [O] **Bound assertion module separate from the RTL.** A standalone `_props.sv` module holds the properties; a `bind` directive in the testbench attaches an instance to every DUT. Cleaner separation; the production RTL stays free of verification text. Cite `references/projects/wb2axip/bench/formal/faxis_master.v:103-164` (a complete master-side bind module for AXI-Stream, using `SLAVE_ASSUME` / `SLAVE_ASSERT` macros that resolve to `assume` or `assert` depending on which side of the interface is under proof).
- [O] **cocotb testbench in Python driving the RTL through ModelSim or Verilator.** Stimulus and scoreboard live in Python; the RTL is driven through cocotb's HDL bridge. Powerful for protocol verification (cocotbext-axi provides off-the-shelf AXI source/sink models) but **not part of the Quartus 18.1 toolchain** — adopt only if the project commits to maintaining the Python environment alongside the Quartus flow. Cite `references/projects/verilog-axis/tb/axis_register/test_axis_register.py:42-110`.
- [O] **Hybrid: minimal handshake SVA in RTL `` `ifdef FORMAL `` + scoreboarded native-SV testbench in `tb/`.** The handshake properties live with the producer (so they cannot drift); the functional scoreboard lives in the testbench. This is the recommended default for this bundle. Composed from `references/projects/wb2axip/rtl/skidbuffer.v:244-291` (inline properties) and `references/projects/verilog-axis/tb/axis_register/test_axis_register.py:74-110` (scoreboard pattern); marked [O] as the bundle's preferred composition.

**Out of scope — deep formal verification.** SymbiYosys-driven k-induction proofs, bounded model checking, full property suites that prove a master or slave conforms to a protocol under all inputs — these are **explicitly out of scope for this bundle**. The pointer for that work is `references/projects/wb2axip/bench/formal/` (in particular `faxis_master.v`, `faxis_slave.v`, `faxil_master.v`, `faxil_slave.v`) plus the SymbiYosys flow ZipCPU documents across `references/raw/zipcpu/formal_index.html`. The properties in §3 and §5 are *handshake invariants* runnable in any SVA-aware simulator; they are not a formal proof. [O]

---

## 7. Anti-patterns (mistakes that compile but break)

These four entries are pre-committed by the spec; this doc is their primary home. None has a numbered slot in spec §9 — flag each as "spec §9 addendum" so Phase 3 surfaces them in [90-anti-patterns.md](90-anti-patterns.md) under the verification family.

- **Synthesis warnings ignored.** *(spec §9 addendum)*
  - **Symptom:** Design compiles cleanly. Behavior on the DE10-Nano disagrees with simulation. Adding a `$display` "fixes" it.
  - **Cause:** One of: a `latch inferred` warning in a combinational block whose output is undriven on some branch ([13-registers-and-combinational-blocks.md](13-registers-and-combinational-blocks.md) §7); a `register removed: no fanout` warning that says the register the agent thought it was writing was eliminated; a `node has no driver` warning on a signal that the agent thought was wired up but typo'd.
  - **Fix:** Every Analysis & Synthesis warning is read after every compile (§4.1). Each warning is either fixed in RTL or annotated in the project with a written justification. The default position is "the warning is right and the RTL is wrong" — pursue the warning until you can explain why.
  - **Citation:** Intel Quartus Standard Edition User Guide: Design Recommendations (live URL <https://docs.altera.com/r/docs/683323/current>; app-shell, no local capture).

- **Inferred resource not confirmed in Fitter report.** *(spec §9 addendum)*
  - **Symptom:** Design instantiated a `(* ramstyle = "M10K" *)` RAM, but on the DE10-Nano the timing closes 30 MHz lower than expected and the M10K block count in the project summary is suspiciously low. Or: a multiplier intended for the DSP block runs but consumes hundreds of ALMs and misses timing on long-period operations.
  - **Cause:** Synthesis honored the inference *request* but the Fitter dropped the resource into the wrong primitive because of a port-mode or read-during-write incompatibility. The agent didn't check, so the misplacement only surfaced as a timing or area symptom.
  - **Fix:** Open the Fitter "Resource Utilization by Entity" (§4.2). For every module that should contain an M10K, MLAB, or DSP block, confirm the count under the appropriate column. Cross-ref to [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md) for memory inference requirements (single-vs-dual port, read-during-write modes, initialization-file constraints) and [31-dsp-inference-cyclone-v.md](31-dsp-inference-cyclone-v.md) for DSP-block inference requirements (pipeline-register depth, signed-vs-unsigned, operand widths).
  - **Citation:** Intel Quartus Standard Edition User Guide: Design Recommendations, "Inferring RAM Functions" and "Inferring Multipliers" sections (live URL <https://docs.altera.com/r/docs/683323/current>; app-shell, no local capture).

- **Testbench has no scoreboard; manual waveform inspection only.** *(spec §9 addendum)*
  - **Symptom:** Tests "pass" because the engineer looked at a waveform and it "seemed right". Regression reintroduces an already-fixed bug because no automated check would have caught it.
  - **Cause:** The testbench drives stimulus and prints outputs, but never compares outputs to an expected reference. The pass/fail decision lives in the engineer's head, not in the test.
  - **Fix:** Every testbench has (1) a stimulus queue, (2) a reference-model queue holding the expected output for each stimulus, (3) a captured-output queue populated by a monitor on the DUT outputs, and (4) a final element-by-element compare with `$fatal` on mismatch. See §5 Pattern A.
  - **Citation:** `references/projects/verilog-axis/tb/axis_register/test_axis_register.py:99-107` — the send-then-recv-then-compare pattern.

- **SVA assertion writes the bug (assertion logic itself contains the design under test).** *(spec §9 addendum)*
  - **Symptom:** All assertions pass in simulation. The hardware misbehaves. On inspection, the failing condition is one the agent wrote a property to catch — but the property body re-implements the same buggy computation, so the bug and its check agree.
  - **Cause:** The property was written as a *recomputation* ("`y` should equal `a + b`") rather than an *invariant* ("if `valid_in && ready_in`, then on the next cycle `count_out` is one greater than the previous `count_out`"). The recomputation reproduces the bug; the invariant catches it.
  - **Fix:** Properties express orderings, stabilities, conservation laws — never re-implementations. Stability: "while `valid && !ready`, payload is unchanged" (§3 Property 2). Ordering: "after reset, `valid` is low" (§3 Property 3). Conservation: "the number of transfers observed at the output equals the number observed at the input, modulo drops the protocol allows."
  - **Citation:** Inferred from the ZipCPU formal mindset across `references/raw/zipcpu/formal_index.html` (multiple posts on what a property should and should not encode); the structural form is exemplified by the stability-only properties in `references/projects/wb2axip/rtl/skidbuffer.v:277-289` (no arithmetic recomputation; only `$stable` and implication). [I]

Additional entries that fall in this doc's family but reinforce numbered spec §9 entries elsewhere:

- **`assume` used where `assert` was meant.** In a simulation flow, `assume` silently constrains random stimulus; a property that should test the DUT but was written as `assume` will pass vacuously because the simulator simply never generates a counterexample stimulus. Fix: in non-formal simulation, every property *about the DUT* is an `assert`; every property *about the environment* (only meaningful when a formal solver is generating stimulus) is an `assume`. Cite `references/raw/zipcpu/axi_rules.html:412-414` (the `assume(!ARESETN)` pattern — `assume` is reserved for environment constraints, never DUT behavior). [V]
- **Latch inferred from incomplete combinational coverage.** Detection happens in the §4.1 Analysis & Synthesis warnings panel. The coding fix lives in [13-registers-and-combinational-blocks.md](13-registers-and-combinational-blocks.md). Cite Intel Quartus Standard Edition User Guide: Register and Latch Coding Guidelines (live URL <https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/register-and-latch-coding-guidelines>; app-shell, no local capture).
- **Read-during-write mode assumed without explicit setting.** Detection happens when a Fitter resource mismatch is investigated (§4.2; M10K request dropped to MLAB or to logic). The coding fix lives in [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md).

---

## 8. Verification

This doc *is* the verification chapter; the gates it produces feed [91-core-bringup-checklist.md](91-core-bringup-checklist.md).

- **Gate 6a — Synthesis warnings reviewed.** No latch-inferred, register-removed, register-merged, node-has-no-driver, or node-has-no-fanout warning is left unannotated. Evidence: a `compile_warnings.txt` artifact listing each warning and either "fixed in commit X" or "waived because Y".
- **Gate 6b — Inferred RAMs confirmed at M10K / MLAB.** For every `(* ramstyle = ... *)` attribute, the Fitter Resource Utilization by Entity shows the requested primitive. Cross-ref [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md).
- **Gate 6c — Inferred multipliers confirmed at DSP block.** For every inferred multiplier intended for a DSP block, the Fitter resource report confirms placement in `Variable-Precision DSP Blocks`. Cross-ref [31-dsp-inference-cyclone-v.md](31-dsp-inference-cyclone-v.md).
- **Gate 7 — TimeQuest closed across all clocks.** Worst-case setup, hold, recovery, and removal slack ≥ 0; `Report Metastability` lists every CDC chain in the design with an MTBF; no signal crosses clock domains without appearing in that report.
- **Gate 8a — Every module has a scoreboarded testbench.** Evidence: a `tb/` directory containing a `tb_<module>.sv` for every non-trivial module; each testbench prints `PASS` on a green run via the §5 Pattern A structure.
- **Gate 8b — Every handshake interface has at least three SVA properties enabled in simulation.** Evidence: a bound `handshake_props` instance (or inline `` `ifdef FORMAL `` block) for every ready/valid interface; ModelSim invoked with `+sva` (or equivalent Questa flag) so the properties actually execute.
- **Gate 8c — Every register observed at reset and non-reset value.** Evidence: a reset-coverage report from the simulator showing every register flipped at least once during the test suite.

These gates translate into Phase 3 `91-core-bringup-checklist.md` Gate 6 (resource confirmation), Gate 7 (timing closure), and Gate 8 (verification minimum).

---

## 9. Provenance footer

Archive citations:

- `references/projects/wb2axip/rtl/skidbuffer.v` @ 2024-snapshot — used for §2 [V] SVA placement rule, §3 verbatim concurrent-property anchor (lines 276-290), §3 `` `ifdef FORMAL `` placement (lines 244-291), §5 Pattern B derivation, §6 [O] inline-assertion variation, §7 "SVA writes the bug" structural counter-example.
- `references/projects/wb2axip/bench/formal/faxis_master.v` @ 2024-snapshot — used for §5 Pattern B `bind` discussion (lines 103-164), §6 [O] bound-module variation, deep-formal pointer in §1 and §6.
- `references/raw/zipcpu/axi_rules.html` @ retrieved-2026 — used for §2 [V] three-properties rule, §2 [V] assume-vs-assert discipline (lines 412-414), §3 immediate-assertion anchor (lines 465-468), §3 `f_past_valid` discussion (lines 404-414), §7 assume-vs-assert anti-pattern.
- `references/raw/zipcpu/formal_index.html` @ retrieved-2026 — used for §1 deep-formal out-of-scope pointer, §2 [I] invariant-vs-recomputation rule, §6 deep-formal pointer, §7 "SVA writes the bug" mindset citation.
- `references/projects/verilog-axis/tb/axis_register/test_axis_register.py` @ 2021-snapshot — used for §2 [V] scoreboard-testbench rule (lines 99-107), §2 [O] cocotb caveat (lines 31-39), §5 Pattern A composite derivation (lines 74-110), §6 [O] cocotb variation, §7 "no scoreboard" citation.
- `references/raw/style/lowrisc_systemverilog_style.md` @ retrieved-2026 — used for §2 [V] reset-coverage rule and §2 [V] no-`X`-in-RTL rule (lines 1905-1928).

Live-URL citations (Intel Quartus 18.1 documentation; app-shells, no local capture):

- <https://docs.altera.com/r/docs/683323/current> — Intel Quartus Prime Standard Edition User Guide: Design Recommendations. Used for §2 [C] synthesis-warning rule, §2 [C] inferred-resource-confirmation rule, §2 [C] metastability-report rule, §4.1 warning string catalog, §4.2 Fitter resource confirmation, §4.3 metastability report, §7 "Synthesis warnings ignored" and "Inferred resource not confirmed" citations.
- <https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/register-and-latch-coding-guidelines> — Intel Quartus Prime Standard Edition User Guide: Register and Latch Coding Guidelines. Used for §7 "latch inferred" pointer and §4.1 latch-warning discussion.
- <https://docs.altera.com/r/docs/683068/current> — Intel Quartus Prime Standard Edition Timing Analyzer User Guide. Used for §2 [C] setup/hold/recovery/removal rules, §4.3 TimeQuest report navigation, §8 Gate 7 evidence.

IEEE standard (not in archive):

- IEEE 1800-2017 §16 (SystemVerilog Assertions) and §23.11 (`bind`) — used for §3 construct table semantics (`$past`, `$stable`, `disable iff`, `|->`, `|=>`, `bind`). Standard reference; no archive capture.
