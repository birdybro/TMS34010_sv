# Pipelines and Latency Thinking

> Bundle version: 2026-05-19
> Pinned commits: see [references/MANIFEST.md](../references/MANIFEST.md) — FPGADesignElements (Register_Pipeline_Simple, Pipeline_FIFO_Buffer, Pipeline_Half_Buffer, Pipeline_Handshake_Multiplier), ZipCPU pipeline_control + class_verilog, verilog-axis axis_pipeline_register, Intel Quartus HDL design / general coding guidelines (live URLs).
> Load with: [10-hardware-mindset-and-microarchitecture.md](10-hardware-mindset-and-microarchitecture.md), [13-registers-and-combinational-blocks.md](13-registers-and-combinational-blocks.md), [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md), [20-ready-valid-handshakes.md](20-ready-valid-handshakes.md), [21-skid-buffers-and-register-slices.md](21-skid-buffers-and-register-slices.md), [40-timing-closure-and-sdc.md](40-timing-closure-and-sdc.md)
> Status mix: [V] and [O] dominate; [I] anchors the cycle-accuracy boundary and the retiming framing; only two firm [C] rules (valid-follows-data; cycle-accuracy preservation when wrapping a cycle-accurate external interface). Pipeline patterns are convention, not synthesis contract.

## 1. Purpose & one-line summary

A pipeline register is a deliberate tradeoff: more latency in exchange for a higher achievable fmax, paid for by added registers and the discipline of carrying a `valid` bit alongside every data stage. This doc establishes the rules for that tradeoff on Cyclone V (`5CSEBA6U23I7`, DE10-Nano), names the deliverable a pipelined block must produce — a **cycle-level schedule** (a stage-by-stage / cycle-by-cycle table of where each datum lives) — and foregrounds the bundle's central insight for emulation work: **an externally cycle-accurate interface may be wrapped around internal pipelining, but only if the externally observable cycle counts at the chip boundary do not change**. The era-faithfulness side of that rule lives in [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md); the pipeline mechanism for executing it lives here.

What this doc does **not** cover (deferred via Load with):

- Era-faithful mirroring rules and the full cycle-accuracy discussion → [17](17-era-faithful-microarchitecture.md).
- Ready/valid protocol rules (no-valid-drop, payload-stable-while-not-ready, transfer on `valid && ready`) → [20](20-ready-valid-handshakes.md).
- Skid buffers and register slices that break long combinational `ready` paths → [21](21-skid-buffers-and-register-slices.md).
- Sync/async FIFOs and Gray-pointer construction → [22-fifos-synchronous-and-asynchronous.md](22-fifos-synchronous-and-asynchronous.md).
- Resource-economy framing of "pipeline register added for no measured reason" → [16-resource-and-state-economy.md](16-resource-and-state-economy.md).
- `always_ff` discipline, blocking-vs-nonblocking, default assignments → [13](13-registers-and-combinational-blocks.md).
- SDC, multicycle/false paths, registered I/O assignments → [40](40-timing-closure-and-sdc.md).

## 2. The contract (must-obey)

Every rule below carries exactly one label. For every [I] rule, the inference chain is named in the same paragraph so reviewers can audit.

- **[C] Valid follows data.** Every pipeline stage that carries data must carry the corresponding `valid` bit in parallel, latched by the same enable, with the same depth. A pipelined data path without a pipelined `valid` is incorrect by construction: the consumer cannot distinguish a bubble cycle from a live datum. *Source:* FPGADesignElements `Pipeline_FIFO_Buffer.v` lines 326-341 — the `output_data_valid` `Register` instance is explicitly clocked with the same `clock_enable(load_output_register == 1'b1)` as the buffer-output read, so the valid bit and the data move together (see §3 excerpt). Same pattern is structural in `Pipeline_Half_Buffer.v` (the `empty_full` bit moves in lockstep with the `half_buffer` data register).

- **[C] Cycle-accurate-interface preservation.** When wrapping a cycle-accurate external interface — i.e., the chip's pin-level bus phases, memory read/write latency, IRQ-ack cycles, refresh timing, video horizontal/vertical timing — **internal pipelining is permitted only if the externally observable cycle counts on the wrapped interface do not change**. A pipeline stage that shifts the boundary's read or write timing by even one cycle is forbidden in this context. *Cross-ref:* [17-era-faithful-microarchitecture.md §2](17-era-faithful-microarchitecture.md) owns the era-faithfulness side; doc 17 names this as the "cycle-accuracy boundary" and points back here for the pipelining mechanism. This is the bundle's contract, not Intel's; marked [C] because violating it breaks compatibility with software that exploits the original chip's timing.

- **[V] A pipeline register is added because a specific critical path was identified, not "for safety."** The decision to insert a pipeline stage must be backed by a TimeQuest report or a known fmax target the current source cannot meet. Adding "just one more flop" without that justification is a resource-economy violation and is treated as anti-pattern #17, whose primary home is [16-resource-and-state-economy.md](16-resource-and-state-economy.md). *Source:* Intel general HDL design guidance on registering paths to close timing (live URL: <https://www.intel.com/content/www/us/en/docs/programmable/683082/current/hdl-design-guidelines.html> @ 2026-05-20) — the guidance's framing is that registers are inserted in response to a measured path, not preemptively.

- **[V] The deliverable of a pipelined design is a cycle-level schedule.** For any pipelined block, the consuming agent maintains a stage-by-stage / cycle-by-cycle table alongside the RTL: at cycle T, stage K holds which datum (and its valid). This is the artifact, not a comment. *Source:* ZipCPU pipeline_control slides 9-11 (`references/extracted_text/zipcpu/pipeline_control.txt` lines 191-265) — the three "Pipeline Strategies" (run every clock / advance on CE / advance on request-when-!busy) each make the per-cycle advance condition explicit, which is precisely the schedule's job: state at each cycle what each stage does and why.

- **[V] Data and control delays through a pipeline must be balanced.** A control signal that gates stage N's output but is itself one cycle behind the data is a bug; the control must be pipelined the same depth as the data it gates. The same applies to `valid`: if data takes N stages, `valid` must take N stages with the same enables. *Source:* FPGADesignElements `Pipeline_FIFO_Buffer.v` lines 326-341 (output-valid registered to match the buffer-output read latency) + `Pipeline_Half_Buffer.v` lines 88-106 (empty/full bit register paired with the data register).

- **[V] Backpressure freezes every stage in lockstep.** When a stall propagates upstream, all stages downstream of the stall point hold their `(data, valid)` pairs frozen until the stall releases. A stage that freezes data but lets `valid` advance, or vice versa, loses data or fabricates bubbles. *Source:* ZipCPU pipeline_control slides 9-11 (the CE-gated and request-gated pipeline strategies show all stage updates predicated on the same single condition) + FPGADesignElements `Pipeline_FIFO_Buffer.v` `load_output_register` driving both the buffer read and the valid flop. The full ready-path mechanism is owned by [21](21-skid-buffers-and-register-slices.md).

- **[I] Quartus retiming can balance unequal pipeline stages, but cannot create stages that don't exist in source.** Retiming (Fitter option in Quartus, sometimes called register balancing) moves existing registers across combinational boundaries to equalize stage delays; it does **not** insert new flops the RTL never declared. If your source has one long combinational stage between two flops, retiming cannot magically split that into two stages — you must add the second flop in RTL. *Inference chain:* Intel HDL design guidance documents the register-balancing / retiming option (live URL: <https://www.intel.com/content/www/us/en/docs/programmable/683082/current/hdl-design-guidelines.html> @ 2026-05-20; local capture is an app shell) + the structural fact that retiming is a register-movement transform, not a register-insertion transform. The local Intel HDL-guidelines HTML at `references/raw/intel/quartus_standard_hdl_design_guidelines.html` is an app shell (verified — 71 lines of bootstrap chrome, no content), so this rule cites the live URL only; the inference is the bundle's, marked [I].

## 3. Constructs / signals / API reference

This doc's "constructs" are the *concepts* a pipelined design composes — not a catalog of every parameterized pipeline module. The full module catalog (forks, joins, merges, credit gates, branches) belongs in [20](20-ready-valid-handshakes.md) and [21](21-skid-buffers-and-register-slices.md).

| Construct | Meaning | Owned here? |
|---|---|---|
| Pipeline register | A flop (or bank of flops) inserted between two combinational regions to break a critical path. Stage's data is registered; the same `clock_enable` (if any) gates the stage. | Yes |
| `(data, valid)` pair | Two flops in the same stage: one holds the payload, the other holds whether the payload is meaningful this cycle. **Identical enable on both.** | Yes |
| Cycle-level schedule | The artifact: stage × cycle table of where each datum lives and whether its valid is set. Lives alongside the RTL. | Yes |
| Backpressure freeze | A stall on stage K freezes stages K-1, K-2, … upstream; `(data, valid)` freeze together. | Yes (mechanism owned by [21](21-skid-buffers-and-register-slices.md)) |
| Skid buffer / register slice | Registers a `ready` path. Cross-ref one-line. | No — see [21](21-skid-buffers-and-register-slices.md) |
| FWFT (First-Word Fall-Through) FIFO | Pipeline buffer whose first word is presented without an explicit read. Cross-ref one-line. | No — see [22](22-fifos-synchronous-and-asynchronous.md) |
| Pipeline fork / join / merge / branch | Composition patterns over ready/valid pipelines. Cross-ref one-line. | No — see [20](20-ready-valid-handshakes.md) |

### 3.1 The `(data, valid)` pair — canonical evidence

The single strongest in-corpus citation for "valid follows data" is `Pipeline_FIFO_Buffer.v`. The buffer's read-from-RAM is registered; the corresponding `output_valid` is registered on the **same enable** as the read, so the two move together:

```verilog
// references/projects/FPGADesignElements/Pipeline_FIFO_Buffer.v:326-341 @ MANIFEST snapshot
// `output_valid` must be registered to match the latency of the buffer output
// register.

    Register
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    output_data_valid
    (
        .clock          (clock),
        .clock_enable   (load_output_register == 1'b1),
        .clear          (clear),
        .data_in        (stored_items_zero == 1'b0),
        .data_out       (output_valid)
    );
```

The discipline visible here is: **whatever enable advances the data also advances the valid.** [V] — citing the module above.

For a pure delay-only pipeline (data-only; no valid), `Register_Pipeline_Simple.v` is the canonical parameterized template. **It does not show the `valid` partner**, because in a delay-pipeline context the caller is expected to instantiate a second identical pipeline for `valid` with the same `clock_enable`. The data half looks like this:

```verilog
// references/projects/FPGADesignElements/Register_Pipeline_Simple.v:55-89 @ MANIFEST snapshot
            wire [WORD_WIDTH-1:0] pipe [PIPE_DEPTH-1:0];

            Register
            #(
                .WORD_WIDTH     (WORD_WIDTH),
                .RESET_VALUE    (WORD_ZERO)
            )
            input_stage
            (
                .clock          (clock),
                .clock_enable   (clock_enable),
                .clear          (clear),
                .data_in        (pipe_in),
                .data_out       (pipe[0])
            );

            for (i=1; i < PIPE_DEPTH; i=i+1) begin: pipe_stages
                Register
                #(
                    .WORD_WIDTH     (WORD_WIDTH),
                    .RESET_VALUE    (WORD_ZERO)
                )
                pipe_stage
                (
                    .clock          (clock),
                    .clock_enable   (clock_enable),
                    .clear          (clear),
                    .data_in        (pipe[i-1]),
                    .data_out       (pipe[i])
                );
            end
```

To make this honest for the valid-follows-data rule, you instantiate **a second** `Register_Pipeline_Simple` with `WORD_WIDTH=1` for the `valid` bit, with the **same** `clock_enable` and `clear` as the data instance. The pair is the legal pattern; the data-only template alone is not. [O] — `Register_Pipeline_Simple.v` is the structural shape; pairing it with a width-1 valid copy is the bundle's prescribed use.

### 3.2 A worked cycle-level schedule

Consider a 3-stage pipeline that computes `result = (a * b) + c`. Stage 1 latches the inputs and computes nothing; stage 2 performs the multiply; stage 3 adds `c` (which has been delay-matched through a width-of-c shadow pipeline) to the multiplier output.

The cycle-level schedule is a table. Inputs `(a_i, b_i, c_i)` and their valid `v_i` arrive at cycle `T_i`.

| Cycle | Stage 1 (`a`, `b`, `c`, `valid`) | Stage 2 (`a*b`, `c_delayed`, `valid`) | Stage 3 (`(a*b)+c_delayed`, `valid`) |
|---|---|---|---|
| 0 | (a0, b0, c0, 1) | (–, –, 0) | (–, 0) |
| 1 | (a1, b1, c1, 1) | (a0\*b0, c0, 1) | (–, 0) |
| 2 | (–, –, –, 0) bubble | (a1\*b1, c1, 1) | ((a0\*b0)+c0, 1) |
| 3 | (a3, b3, c3, 1) | (–, –, 0) bubble | ((a1\*b1)+c1, 1) |
| 4 | (–, –, –, 0) bubble | (a3\*b3, c3, 1) | (–, 0) bubble |
| 5 | (–, –, –, 0) bubble | (–, –, 0) bubble | ((a3\*b3)+c3, 1) |

Read this table as the deliverable: the second column is the **content of stage K's registers at the start of that cycle** (after the previous edge). The `valid` column tells the next stage whether to trust the data. A bubble cycle (`valid = 0`) is **not** ignored by the next stage's flop — the flop still clocks; what changes is that the downstream consumer treats the bubble as nothing happened. This table is an [I] composite: no single corpus source carries this exact table, but it composes the shift-register skeleton of `Register_Pipeline_Simple.v` with the `(data, valid)` pair discipline from `Pipeline_FIFO_Buffer.v`.

### 3.3 Retiming note

Quartus's Fitter can perform retiming / register balancing — moving existing flops across combinational logic — to even out stage delays after fitting. This helps when a 3-stage pipeline has stage delays of (4 ns, 2 ns, 1 ns) and could be (2.5, 2.5, 2): retiming may move a flop earlier to redistribute. **What retiming cannot do is create a stage that does not exist in source.** If you have one 7 ns combinational chain between two flops, retiming cannot split it; the second flop must be added in RTL. [I] — see §2 inference chain for the retiming claim's source.

## 4. Sequencing & timing

### 4.1 The "valid travels with data" sequence

A single transfer through a 3-stage pipeline, no stalls:

```
cycle      :     T      T+1    T+2    T+3
data_in    :  [D0]   [- ]   [- ]   [- ]
valid_in   :   1      0      0      0

stage1_data:   -    [D0]   [- ]   [- ]
stage1_v   :   0     1      0      0

stage2_data:   -      -    [D0]   [- ]
stage2_v   :   0      0     1      0

stage3_data:   -      -      -    [D0]
stage3_v   :   0      0      0     1
```

At each rising edge, every stage's `(data, valid)` snaps from the previous stage's output. The valid bit is what tells stage 3 that its data is real on cycle T+3.

### 4.2 The cycle-accurate-boundary sequence

Suppose the original chip drives a memory-read bus with the following pin-level cycle pattern (`ADDR`, `RD#`, `DATA` from external memory, sampled on falling edge):

```
External (locked) cycle counts — original chip:
cycle      :   0    1    2    3    4    5    6    7
ADDR_out   :  --   A    A    A    A    A    --   --
RD#_out    :  --   0    0    0    0    0    --   --
DATA_in    :  ??   ??   ??   ??   ??   D    --   --
```

Five cycles of `ADDR`/`RD#` assertion; data captured on cycle 5. **This number — five — is locked**, no matter what we do internally.

Now suppose computing the next-instruction prefetch fanout (which combinationally drives `ADDR_out`) is the critical path; we want to break it with an internal pipeline register. The wrapped boundary, internally pipelined, keeps the external observable identical:

```
Internal (free) — one pipeline register added:
cycle      :   0    1    2    3    4    5    6    7
ADDR_out   :  --   A    A    A    A    A    --   --   <-- still 5 cycles, locked
RD#_out    :  --   0    0    0    0    0    --   --   <-- locked
DATA_in    :  ??   ??   ??   ??   ??   D    --   --   <-- locked

internal_ADDR_pre :  A    A    A    A    A    --   --   --   <-- shifted one cycle EARLIER
internal_ADDR_reg :  --   A    A    A    A    A    --   --   <-- the new flop's output == ADDR_out
```

The new flop is fed by combinational logic one cycle earlier; its output **is** `ADDR_out` and matches the original cycle-for-cycle. The pipelining is invisible at the pin. [I] composite — the locking rule is the bundle's [C] from §2; the pipelining mechanism is [V] from §3; the sequence diagram is the bundle's.

**Cross-ref:** [17-era-faithful-microarchitecture.md §4](17-era-faithful-microarchitecture.md) for the era-faithfulness boundary, which names this same diagram from the chip-identity side.

### 4.3 Backpressure interaction

When stage K's downstream consumer drops `ready` (or otherwise stalls), stages K-1, K-2, … all hold. Their `(data, valid)` freeze **together** — same enable on the data flop and the valid flop, same enable across stages within the stalled region. The full ready-path mechanism (skid buffer / register slice) lives in [21](21-skid-buffers-and-register-slices.md); what lives here is the rule that data and valid freeze in lockstep, never separately.

## 5. Minimal working pattern

Smallest correct three-stage data+valid pipeline with a single stage enable. Composes the `Register_Pipeline_Simple.v` shift skeleton (§3.1) with the explicit valid partner from `Pipeline_FIFO_Buffer.v` (§3.1). Marked [I] composite — see §3.2 for the citation chain.

```verilog
// [I] Composite — composes Register_Pipeline_Simple.v shift skeleton with
//                Pipeline_FIFO_Buffer.v `(data, valid)` pair discipline.
// Bundle's prescribed minimal pattern; not verbatim from a single source.

`default_nettype none

module Pipe3 #(parameter W = 8) (
    input  wire          clock,
    input  wire          clear,
    input  wire          ce,           // SINGLE enable gates EVERY (data, valid) flop

    input  wire [W-1:0]  data_in,
    input  wire          valid_in,

    output reg  [W-1:0]  data_out,
    output reg           valid_out
);
    reg [W-1:0] data_s1, data_s2;
    reg         valid_s1, valid_s2;

    always @(posedge clock) begin
        if (clear) begin
            data_s1   <= '0;  data_s2   <= '0;  data_out  <= '0;
            valid_s1  <= 1'b0; valid_s2 <= 1'b0; valid_out <= 1'b0;
        end else if (ce) begin
            // (data, valid) flops in stage 1
            data_s1   <= data_in;       valid_s1  <= valid_in;
            // (data, valid) flops in stage 2
            data_s2   <= data_s1;       valid_s2  <= valid_s1;
            // (data, valid) flops in stage 3 / output
            data_out  <= data_s2;       valid_out <= valid_s2;
        end
        // !ce: freeze BOTH data and valid for every stage simultaneously.
    end
endmodule

`default_nettype wire
```

Cycle-level schedule for `Pipe3` with `(D0, 1)` injected at cycle T, no stalls:

| Cycle | (data_in, valid_in) | (data_s1, valid_s1) | (data_s2, valid_s2) | (data_out, valid_out) |
|---|---|---|---|---|
| T   | (D0, 1)        | (–, 0)        | (–, 0)        | (–, 0)        |
| T+1 | (–, 0) bubble  | (D0, 1)       | (–, 0)        | (–, 0)        |
| T+2 | (–, 0) bubble  | (–, 0)        | (D0, 1)       | (–, 0)        |
| T+3 | (–, 0) bubble  | (–, 0)        | (–, 0)        | (D0, 1)       |

**Cross-refs:** [17](17-era-faithful-microarchitecture.md) for the surrounding cycle-accuracy contract if this pipe is wrapped inside a cycle-accurate boundary; [20](20-ready-valid-handshakes.md) for the full ready/valid handshake if `Pipe3` sits between two backpressured endpoints rather than running freely on `ce`.

## 6. Common variations across implementations

Every variation labeled with [O] or [V] plus a specific source. Useful for distinguishing *style* from *correctness*.

- **[O] FPGADesignElements `Register_Pipeline_Simple.v` / `Register_Pipeline.v` style.** A parameterized shift-register module with `WORD_WIDTH` and `PIPE_DEPTH`. `Register_Pipeline_Simple` (lines 20-99) supports depth zero (passthrough) and ≥ 1; `Register_Pipeline.v` (lines 47-66) adds parallel-load and per-stage reset values. Both are Verilog-2001, both shift data only — the valid partner is a separate instance. *Source:* `references/projects/FPGADesignElements/Register_Pipeline_Simple.v`, `Register_Pipeline.v`.

- **[O] FPGADesignElements `Pipeline_Half_Buffer.v` style.** A single-stage `(data, valid)` register packaged as one composable module with `input_valid` / `input_ready` / `output_valid` / `output_ready` ports (lines 50-66). The empty/full bit serves the role of the valid for the buffered word; the data register and the bit register share the same load condition. Half the throughput of a skid buffer (must read out before writing again) but no combinational path between input and output handshakes. *Source:* `references/projects/FPGADesignElements/Pipeline_Half_Buffer.v` lines 50-122.

- **[O] FPGADesignElements `Pipeline_FIFO_Buffer.v` style.** A multi-entry pipeline buffer backed by dual-port memory, with the canonical `output_valid` flop matched to the read-data latency (lines 326-341 — see §3.1 excerpt). The `RAMSTYLE` parameter steers M10K / MLAB / register inference on Cyclone V (full M10K-vs-MLAB-vs-flops decision in [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md)). *Source:* `references/projects/FPGADesignElements/Pipeline_FIFO_Buffer.v` lines 49-343.

- **[O] verilog-axis `axis_pipeline_register.v` style.** An AXI-Stream-flavored register-slice with a `LENGTH` parameter that chains `LENGTH` instances of an underlying register stage. `REG_TYPE` parameter selects bypass / simple-buffer / skid-buffer behavior. The pipeline-of-skid-buffers pattern is what production AXI stacks (verilog-axis, Alex Forencich, 2018) actually ship. *Source:* `references/projects/verilog-axis/rtl/axis_pipeline_register.v` lines 34-89, 118-120. **The skid-buffer behavior itself is owned by [21](21-skid-buffers-and-register-slices.md); cited here only for the chained-pipeline style.**

- **[V] ZipCPU "pipeline strategies" framing.** Three legitimate ways to advance a pipeline stage: (1) on every clock unconditionally; (2) on a clock-enable (CE) signal; (3) on a request that is gated by a `!busy` / `!stall` from the receiver. *Source:* `references/extracted_text/zipcpu/pipeline_control.txt` lines 191-265. The third pattern is the stb/stall handshake that becomes Wishbone B4 pipelined-mode in the rest of the lesson; that is the same "valid gated by ready" shape this bundle codifies in [20](20-ready-valid-handshakes.md).

- **[O] Quartus Fitter retiming / register balancing.** A way to balance unequal pipeline stages without rewriting RTL. Documented in Intel HDL design guidance. *Source:* live URL <https://www.intel.com/content/www/us/en/docs/programmable/683082/current/hdl-design-guidelines.html> @ 2026-05-20 (local capture `references/raw/intel/quartus_standard_hdl_design_guidelines.html` is an app shell — verified, 71 lines of bootstrap chrome, no content). See §2 for the limit: retiming moves existing flops, it does not create new ones.

## 7. Anti-patterns (mistakes that compile but break)

This doc OWNS the primary §7 Symptom→Cause→Fix→Citation treatment of #15 and #16. #17 (safety pipeline) and #18 (long ready comb chain) are one-line cross-refs only; their full treatment lives in 16 and 21 respectively.

### #15 Pipeline data without a parallel `valid` pipeline.

- **Symptom:** Downstream consumer treats bubble cycles as live data; results are corrupted at arbitrary points in the output stream. Simulation appears correct for steady back-to-back input streams but fails the instant inputs are sparse, gated, or interleaved with stalls. The bug is timing-shaped: it disappears when the testbench drives a contiguous stream and reappears under realistic traffic.
- **Cause:** A data flop was added per stage (cleanly, with reset and width plumbed through) but the corresponding `valid` was either (a) left as a single combinational expression that no longer matches the data's delay, or (b) omitted entirely on the assumption that the consumer "knows" when to look.
- **Fix:** Every data flop in a pipeline stage has a sibling `valid` flop with the **same enable** and the **same clear/reset**. If the data takes N stages, `valid` takes N stages. See §5 for the minimal pattern; the rule is established in §2 [C] and the canonical evidence is the `output_data_valid` register in §3.1.
- **Citation:** `references/projects/FPGADesignElements/Pipeline_FIFO_Buffer.v` lines 326-341 (the `output_data_valid` register, explicitly clocked with the same enable as the read-data path); ZipCPU pipeline_control slides 9-11 (`references/extracted_text/zipcpu/pipeline_control.txt` lines 191-265) for the request-gated advance pattern that makes valid-vs-data discipline explicit.

### #16 Long ternary/case nest treated as one combinational stage.

- **Symptom:** TimeQuest reports the critical path through a long chain of nested conditionals (a 12-deep ternary or a 64-way `case` with computed selectors) as the worst path; fmax falls below the target; the Fitter's resource report shows the chain mapped into many ALM levels because the synthesizer cannot fold the chain into a balanced mux tree when the selector depends on prior conditional outputs.
- **Cause:** A logically-sequential conditional selection was coded as one expression (often grown organically over revisions). The synthesizer has no freedom to retime across the chain because there is only one combinational stage; the chain is already a single path from input to flop.
- **Fix:** Identify the natural cycle boundary in the conditional chain — usually the point where the next selector becomes data-dependent on a prior result. Split into two or more pipeline stages with `(data, valid)` pairs (see §5). Where the selector is already known one cycle ahead, convert to a **one-hot mux with a pre-registered select**: encode the choice as a one-hot vector latched in stage K-1, then in stage K the mux fans the one-hot bits across the data inputs and ORs the results — this is a balanced tree the synthesizer can map cleanly.
- **Citation:** [I] — no single corpus source explicitly covers "long ternary nest is one stage." Inference chain: Intel HDL design guidance on registering at natural pipeline boundaries to improve fmax (live URL: <https://www.intel.com/content/www/us/en/docs/programmable/683082/current/hdl-design-guidelines.html> @ 2026-05-20) + the structural argument that synthesis cannot insert registers the RTL does not name (see §2 [I] retiming rule). The "one-hot mux with pre-registered select" mitigation is the same pattern FPGADesignElements names `Pipeline_Merge_One_Hot` / `Pipeline_Branch_One_Hot`; the full treatment of those modules belongs in [20](20-ready-valid-handshakes.md).

### #19 Data freezes on stall but `valid` keeps advancing (or vice versa).

- **Symptom:** Under backpressure, the downstream stage's input data is stale (last valid datum repeated) but `valid` is high; the consumer accepts and processes the stale word as if it were a new transfer. Or: data advances but `valid` froze, so the consumer drops live data on the floor.
- **Cause:** The stall logic was applied to one of the pair but not the other. Often happens when `(data, valid)` are written by two separate `always_ff` blocks with subtly different enable expressions.
- **Fix:** Put `(data, valid)` updates in the same `always_ff` block and gate both with the same enable expression. The §5 pattern shows this — `ce` gates **both** `data_*` and `valid_*` assignments in the same block.
- **Citation:** Derived from FPGADesignElements `Pipeline_FIFO_Buffer.v` lines 326-341 (the `output_data_valid` register's `clock_enable` is the same `load_output_register` signal as the buffer-read enable — by construction, data and valid cannot drift). Marked [V] — convention enforced by source structure rather than [C] from a synthesis rule.

### Cross-ref only (one-line pointers):

- **#17 Pipeline register inserted "for safety" with no critical path justifying it.** Primary home is [16-resource-and-state-economy.md](16-resource-and-state-economy.md). Inserting a pipeline register without a measured critical path is a resource-economy violation; see [16](16-resource-and-state-economy.md) for the full Symptom→Cause→Fix→Citation entry.

- **#18 Ready-path combinational chain longer than one LAB.** Primary home is [21-skid-buffers-and-register-slices.md](21-skid-buffers-and-register-slices.md). Long combinational `ready` paths are a skid-buffer problem; see [21](21-skid-buffers-and-register-slices.md) for the full entry and the canonical register-slice break.

## 8. Verification

A pipelined block's correctness is verified at three levels: simulation correctness, schedule conformance, and post-fit timing. The list below is a checklist.

- **Simulation under sparse input.** Drive a stream where `valid_in` rises at irregular, sparse cycles (e.g., cycles 1, 5, 13, 37, 38, 39, 100). Confirm that `valid_out` rises at exactly `cycle_in + PIPE_DEPTH` for each input, and that `data_out` on those cycles equals the expected per-datum function of the corresponding input. Bubble cycles (`valid_in == 0`) must produce **no** spurious output (`valid_out` must stay low). This is the primary test for anti-pattern #15.

- **Cycle-level schedule walk.** Take the §3.2/§5 schedule table and walk the first ~20 cycles after reset release by hand. Confirm the simulation waveforms match the table cell-by-cell. If they diverge, the schedule (or the RTL) is wrong; the schedule is the source of truth.

- **Bubble-injection test.** Drive a stall on the downstream side at unpredictable cycles. Confirm every stage's `(data, valid)` pair freezes together — read both registers in waveform, confirm neither moves while stall is asserted, and both move together on the cycle the stall releases. This is the primary test for anti-pattern #19.

- **TimeQuest critical-path confirmation.** After fit, open the Report Top Failing Paths / Worst-Case Slack tab in TimeQuest. Confirm: (a) the previously-known critical path (the one the pipeline was added to break) is no longer in the top failing set; (b) the new critical path is shorter than the pipeline-stage budget at the target fmax; (c) the new path does not run *through* the pipeline registers (if it does, the wrong stage was registered). Resource cost: confirm Fitter report shows the added flops where you placed them. See [40](40-timing-closure-and-sdc.md) and [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md) for the report-reading discipline.

- **Cycle-accuracy assertion for wrapped boundaries.** When this pipeline sits inside a wrapped cycle-accurate interface (per §2 [C] cycle-accuracy rule and [17](17-era-faithful-microarchitecture.md)), assert in simulation that every externally observable boundary signal's edge occurs at exactly the same cycle relative to a boundary input edge **before and after** the internal pipelining is added. A light SVA property of the form `boundary_signal_edges_at_cycles == expected_cycles` is sufficient; the full SVA discipline is owned by [41](41-quartus-reports-and-verification.md).

- **Reset/release coverage.** Confirm that on reset release, every stage's `valid` is 0 (no spurious live datum at any stage). This is a §13-style register-reset confirmation; the rule lives in [13](13-registers-and-combinational-blocks.md), but pipelines amplify the cost of getting it wrong — a spurious `valid_out` on the first cycle after reset is a real bug.

## 9. Provenance footer

Every cited source listed once, with the §s it supports.

- `references/projects/FPGADesignElements/Pipeline_FIFO_Buffer.v` @ MANIFEST snapshot — used for §2 (valid-follows-data [C], delay-balance [V]), §3.1 (verbatim excerpt of `output_data_valid` register), §3 table, §6 (variation), §7 #15 citation, §7 #19 citation.
- `references/projects/FPGADesignElements/Register_Pipeline_Simple.v` @ MANIFEST snapshot — used for §3.1 (verbatim excerpt of shift-register skeleton), §5 (composite minimal pattern), §6 (variation).
- `references/projects/FPGADesignElements/Register_Pipeline.v` @ MANIFEST snapshot — used for §6 (variation; parallel-load extension).
- `references/projects/FPGADesignElements/Pipeline_Half_Buffer.v` @ MANIFEST snapshot — used for §2 (delay-balance [V] supporting evidence), §6 (variation).
- `references/projects/verilog-axis/rtl/axis_pipeline_register.v` @ MANIFEST snapshot (Forencich 2018) — used for §6 (variation; production AXI-Stream chained register-slice pattern).
- `references/extracted_text/zipcpu/pipeline_control.txt` lines 191-265 @ MANIFEST snapshot — used for §2 (cycle-level schedule [V] deliverable; backpressure-freeze [V]), §6 (ZipCPU three-strategies framing), §7 #15 supporting citation.
- <https://www.intel.com/content/www/us/en/docs/programmable/683082/current/hdl-design-guidelines.html> @ 2026-05-20 (live URL; local capture `references/raw/intel/quartus_standard_hdl_design_guidelines.html` is an app shell — verified, 71 lines of bootstrap chrome, no content) — used for §2 (pipeline-register justification [V]; retiming inference [I] chain), §6 (Quartus retiming variation), §7 #16 citation.
- Cross-ref only (no excerpt cited here): [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md) §2 for the cycle-accuracy boundary's era-faithfulness side.
