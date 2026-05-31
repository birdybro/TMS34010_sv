# Resource and State Economy

> Bundle version: 2026-05-19
> Pinned commits: FPGADesignElements @ 2450a54; fpgacpu.ca standards @ 2026-05-20; Intel Quartus Prime Standard 18.1 (live `docs.altera.com`); zipcpu class_verilog @ 2026-05-20.
> Load with: [10-hardware-mindset-and-microarchitecture.md](10-hardware-mindset-and-microarchitecture.md), [13-registers-and-combinational-blocks.md](13-registers-and-combinational-blocks.md), [15-pipelines-and-latency-thinking.md](15-pipelines-and-latency-thinking.md), [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md), [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md), [31-dsp-inference-cyclone-v.md](31-dsp-inference-cyclone-v.md), [32-arithmetic-patterns-and-operator-cost.md](32-arithmetic-patterns-and-operator-cost.md), [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md)
> Status mix: [C] ~25% (Intel inference-driven facts plus FPGADesignElements width-arithmetic primitives), [V] ~20% (bundle-adopted conventions visible in fpgacpu.ca and lowRISC), [O] ~15% (per-project style differences), [I] ~40% (the load-bearing four-justifications rule itself is [I], plus most cross-doc-derived per-rule inferences).
> Missing inputs: `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt` and `references/raw/intel/cyclone_v_product_table_api.txt` are PDFs (22 pp. and 2 pp. respectively) whose page renderings exceed the Read tool's 256 KB cap; the live-URL `https://docs.altera.com/api/khub/documents/s60vJiu_kjIh2yag_Ea_yg/content` is cited instead for DE10-Nano resource numbers, cross-checked against this bundle's own glossary (`cyclone-v-hdl-bundle/01-glossary.md:20`). The three Intel `quartus_standard_*.html` files named in the brief are 2.6 KB app-shells with no extractable body content; report-string excerpts in §3 and §8 are attributed to the live `docs.altera.com/r/docs/683323/current` URL rather than to local capture.

## 1. Purpose & one-line summary

Economy is a contract, not a virtue: every register and every bus bit costs ALMs, fanout, fmax headroom, and reviewer attention, so every register and every bus bit must justify itself before commit and reappear justified in the Quartus reports after synthesis. This doc installs that discipline as a single load-bearing rule (the four-justifications block in §2) and trains the consuming agent to read the Quartus Synthesis and Fitter reports as the ground-truth check on it. Pre-RTL microarchitecture planning ([10](10-hardware-mindset-and-microarchitecture.md)), era-faithful resource sharing ([17](17-era-faithful-microarchitecture.md)), `always`-block discipline ([13](13-registers-and-combinational-blocks.md)), FSM-encoding mechanics ([14](14-finite-state-machines.md)), pipeline construction ([15](15-pipelines-and-latency-thinking.md)), per-operator cost ([32](32-arithmetic-patterns-and-operator-cost.md)), full Quartus-report mechanics ([41](41-quartus-reports-and-verification.md)), and CDC correctness for synchronizers ([23](23-cdc-single-bit.md)) are deferred to the docs named in `Load with:`.

## 2. The contract (must-obey)

The load-bearing rule (the doc's single most-important block; every anti-pattern in §7 derives from it):

> Every register must justify itself with exactly one of:
> (a) holds state across cycles, (b) breaks a critical combinational path, (c) crosses a clock domain, (d) implements a protocol pipeline stage. Otherwise delete it.
>
> Every bit on every bus must justify itself with exactly one of:
> (a) consumed by a downstream module, (b) required by a protocol field, (c) reserved with explicit forward-compatibility justification. Otherwise it's routing tax.

The block above is [I] — no single archive source mandates this exact four-of-each enumeration. Inference chain: Intel *Recommended HDL Coding Styles* establishes that synthesis eliminates unjustified registers and reports the elimination ([live URL](https://docs.altera.com/r/docs/683323/current) @ 2026-05-20); fpgacpu.ca's system-design and verilog-coding standards establish "minimize the number of warnings from the CAD tool" and the bit-width-matching discipline (`references/raw/fpgacpu/system_design_standard.html:184-188 @ 2026-05-20`, `references/raw/fpgacpu/verilog_coding_standard.html:198-205 @ 2026-05-20`); FPGADesignElements supplies the parameter-defaults-unusable primitive style (`references/projects/FPGADesignElements/Register.v:1-15 @ 2450a54`). The four-of-each enumeration is this bundle's distillation into a code-review check.

Per-rule consequences:

- [C] A signal driven but never consumed is removed by synthesis, and Quartus reports the removal in the Synthesis report's "Optimization Results" section under "Removed registers" (and the related "Merged registers" / "Stuck at 0/1" lines). Read these as ground-truth, not as nuisance warnings — every entry is either an intentional redundancy that must be documented or a violation of justification (a). Source: Intel *Recommended HDL Coding Styles*, [live URL](https://docs.altera.com/r/docs/683323/current) @ 2026-05-20 (local `references/raw/intel/quartus_standard_design_recommendations_index.html` is a 2.6 KB app-shell with no body).
- [C] A counter modulo N requires exactly `$clog2(N)` bits when `2**$clog2(N) == N` (i.e., N is a power of two); for non-power-of-two N, `$clog2(N)` bits plus an explicit wrap test (`if (count == N-1) count <= 0;`). Any wider counter carries dead bits — the high bits never toggle and synthesis will either fold them into `Stuck at 0` reports or carry them through the carry chain as dead segments. Source: FPGADesignElements `references/projects/FPGADesignElements/Counter_Binary.v:23-45 @ 2450a54` (the `WORD_WIDTH` parameter is the bit count; the module's contract is "wraps around if it goes below zero or above `(2^WORD_WIDTH)-1` and sets `overflow`," `Counter_Binary.v:8-9` — i.e., the module assumes the caller sized `WORD_WIDTH` to the caller's `N`).
- [C] An accumulator over K additions of W-bit values requires `W + $clog2(K)` bits to be overflow-free; narrower silently truncates (signed: rolls over and sets `accumulated_value_signed_overflow`); wider carries dead bits. Source: FPGADesignElements `references/projects/FPGADesignElements/Accumulator_Binary.v:27-33 @ 2450a54` ("If the accmulator increments past the max or min signed integer value it can hold, the accumulator will roll-over and set the `accumulated_value_signed_overflow` bit").
- [C] Bit widths of variable assignments must match; an unmatched assignment raises a CAD-tool warning even when the implicit zero/sign-extension is semantically correct, and the noise then hides genuinely significant warnings. Source: fpgacpu.ca *Verilog Coding Standard* `references/raw/fpgacpu/verilog_coding_standard.html:198-205 @ 2026-05-20` ("Always match bit widths of variable assignments… if the source and sink have different width, it will raise a pointless warning in the CAD tool, obscuring other more important warnings"). The synthesis-friendly tool for normalising widths is FPGADesignElements `Width_Adjuster` (see §3.4).
- [C] Multiplexers wider than 8:1 must be pipelined or decomposed; a 4:1 mux maps to one 6-LUT per output bit and registers for free, but anything wider stacks LUT layers and pushes the critical path. Source: fpgacpu.ca *Verilog Coding Standard* `references/raw/fpgacpu/verilog_coding_standard.html:665-670 @ 2026-05-20` ("be wary of multiplexers wider than 8:1, and avoid designing logic as a single large selection from many options: better to pipeline a sequence of smaller selections"). Operator cost mechanics defer to [32-arithmetic-patterns-and-operator-cost.md](32-arithmetic-patterns-and-operator-cost.md).
- [V] An unsigned quantity should not carry a sign bit. The fpgacpu.ca bit-width discipline (`references/raw/fpgacpu/verilog_coding_standard.html:198-205 @ 2026-05-20`) treats sign-extension as one of two distinct, explicit choices alongside zero-extension; carrying a sign bit through arithmetic on an unsigned quantity wastes one carry-chain position (and one register on every pipeline stage) without changing the result. Treat any `signed` declaration as a claim that must be justified the same way a register is. Mark [V] because the rule follows from the discipline but is not explicitly stated in those terms in the source.
- [V] Two FSM states with identical output assignments and identical next-state functions are the same state — merge them. Surfaced here as an economy violation only; the FSM-specific mechanics, the COTTC discipline that prevents the redundancy, and the Hopcroft minimization algorithm are owned by [14-finite-state-machines.md §7 #14](14-finite-state-machines.md). Source: FPGADesignElements `references/projects/FPGADesignElements/fsm.html @ 2026-05-20` (COTTC discipline); the broader claim is [I] consistent with doc 14's treatment.
- [I] When a downstream module reads only bits `[M-1:0]` of an N-bit signal (M < N), the upstream-to-downstream routing for bits `[N-1:M]` is dead — strip the source-side declaration so the producer carries only M bits, or insert an explicit `Width_Adjuster` so the narrowing is visible at the module boundary and survives review. Source: FPGADesignElements `references/projects/FPGADesignElements/Width_Adjuster.v:5-13 @ 2450a54` ("You would use this to normalize binary integers to the same *constant* width before doing arithmetic or Boolean operations upon them"). The "strip the source" choice over "insert `Width_Adjuster`" is engineering judgment — the latter is preferred when M and N are parameters and the relationship may change; the former when both are fixed by spec.
- [I] Every register declaration in source carries an inline comment naming which of the four justifications it claims (`// (a) state across cycles`, etc.). This is a bundle-introduced convention — no single archive source mandates inline justification comments — adopted so the four-justifications check survives code review without re-deriving the answer each time. See §5 for the comment shape.
- [I] A signal mirrored as a register copy in two modules where one fanout would suffice doubles the flop count and creates two independent timing paths from a shared source. Source: inference from the load-bearing rule's clause (a) — only one of the two copies "holds state across cycles" in a non-redundant sense, and the second is therefore a violation. Cross-ref to the Fitter "Report Fanout" check in §8.

## 3. Constructs / signals / API reference

### 3.1 The four-justifications check, as a code-review table

| Claim | What counts as evidence |
|---|---|
| **(reg-a)** Holds state across cycles | The value is read on a cycle later than it is written; there is no combinational path that reproduces it from current inputs. |
| **(reg-b)** Breaks a critical combinational path | TimeQuest's pre-pipelining slack report names this path; the register splits it into two paths of lower delay each. Cross-ref [15](15-pipelines-and-latency-thinking.md). |
| **(reg-c)** Crosses a clock domain | The signal's destination flop is in a different clock domain from its source; the register is part of a 2FF or async-FIFO synchronizer. Cross-ref [23](23-cdc-single-bit.md) / [24](24-cdc-multi-bit.md). |
| **(reg-d)** Implements a protocol pipeline stage | The register is one stage of a named protocol's required latency — e.g., AXI-Stream skid buffer ([21](21-skid-buffers-and-register-slices.md)) or DDR I/O register ([11](11-clocking-resets-and-cyclone-v-clock-networks.md)). |
| **(bit-a)** Consumed by a downstream module | A grep across instances of the module shows at least one consumer reading the bit. If the only reader is the producer itself, it's internal state and belongs in a `_q` not on a port. |
| **(bit-b)** Required by a protocol field | The bit's position and width are dictated by an external spec (AXI, AHB, I²S, a register-map document). |
| **(bit-c)** Reserved with explicit forward-compatibility justification | A code comment names the future use and the spec version that introduces it; absent the comment, the bit is routing tax. |

### 3.2 Width-arithmetic rules

| Pattern | Bits required | Failure mode if narrower | Failure mode if wider |
|---|---|---|---|
| Counter modulo N, N is power of two | `$clog2(N)` | Aliases (wraps inside the intended range) | Dead high bits; Synthesis reports them "Stuck at 0" or removes them; carry chain longer than needed |
| Counter modulo N, N is non-power-of-two | `$clog2(N)` + explicit wrap test on `count == N-1` | Aliases | Dead high bits as above |
| Accumulator: K additions of W-bit values | `W + $clog2(K)` | Silent truncation (unsigned) or rollover-with-overflow-flag (signed, per `Accumulator_Binary.v:27-33`) | Dead high bits |
| Address into a memory of D entries | `$clog2(D)` | Aliasing into other entries | Dead high address bits; Synthesis ties them off |
| FSM state register | `$clog2(N_states)` | Encoding collisions (compile error) | Dead high bits unless the encoding is one-hot ([14](14-finite-state-machines.md)) |
| Pipeline-stage data register | exactly the producer's declared width | Truncation | Dead bits, multiplied by the pipe depth |

The canonical SV idiom for sizing a counter or address is `logic [$clog2(N)-1:0] foo;`. The `$clog2` system function is "the canonical way to compute counter or address widths from a parameter" (`cyclone-v-hdl-bundle/01-glossary.md:32`). For run-time width computation across parameters, FPGADesignElements supplies a `max_function` (cited at `references/projects/FPGADesignElements/Width_Adjuster.v:11-13`).

### 3.3 Cyclone V resource budget for DE10-Nano `5CSEBA6U23I7`

What counts as expensive (use this table as a sanity-check on resource estimates before commit):

| Resource | Quantity | Unit cost framing | Expensive at |
|---|---|---|---|
| ALM | ~110 000 | One ALM ≈ 8 4-input LUTs equivalent + 2–4 flops + dedicated adder | Whole-design utilization >60% (routing congestion onset) |
| M10K block | enough for ~5.6 Mbit combined M10K+MLAB | 10 240 bits each, single or true-dual port | Per-block; budget one M10K per FIFO/line-buffer/tile-map ([30](30-memory-inference-cyclone-v.md)) |
| MLAB block | counted into the 5.6 Mbit M10K+MLAB total | 640 bits each, small distributed memory | ≤ 32 words: flops; 32–~few hundred words: MLAB; larger: M10K ([30](30-memory-inference-cyclone-v.md)) |
| DSP block | 112 variable-precision | 27×27, 18×18, or 9×9 signed multiply / multiply-add | Per-block; budget one DSP per multiplier in datapath ([31](31-dsp-inference-cyclone-v.md)) |
| Fractional PLL | small fixed pool | Each generates/divides/phase-shifts one or more derived clocks | Per-PLL; allocate at clock-tree planning ([11](11-clocking-resets-and-cyclone-v-clock-networks.md)) |
| GCLK network | small fixed pool | Low-skew clock spine | Per-network; one per top-level clock ([11](11-clocking-resets-and-cyclone-v-clock-networks.md)) |

Source for the headline numbers: bundle glossary `cyclone-v-hdl-bundle/01-glossary.md:20 @ 2026-05-19`, restating the Cyclone V product table for `5CSEBA6U23I7` (live URL `https://docs.altera.com/api/khub/documents/s60vJiu_kjIh2yag_Ea_yg/content @ 2026-05-20` — the local `references/raw/intel/cyclone_v_product_table_api.txt` is an unreadable 2-page PDF). Mark [C] for the bundle-internal restatement of the numbers.

### 3.4 The bus-narrowing primitive: `Width_Adjuster`

When N ≠ M and the relationship is parameterized or otherwise reviewer-visible, insert the FPGADesignElements `Width_Adjuster` rather than relying on Verilog's implicit zero/sign-extension. The primitive makes the narrowing or extension policy explicit in its instantiation parameters; the module elaborates to combinational logic (no register cost). [C]

```verilog
// references/projects/FPGADesignElements/Width_Adjuster.v:16-58 @ 2450a54
module Width_Adjuster
#(
    parameter WORD_WIDTH_IN     = 0,
    parameter SIGNED            = 0,
    parameter WORD_WIDTH_OUT    = 0
)
(
    // It's possible some input bits are truncated away
    // verilator lint_off UNUSED
    input   wire    [WORD_WIDTH_IN-1:0]     original_input,
    // verilator lint_on  UNUSED
    output  reg     [WORD_WIDTH_OUT-1:0]    adjusted_output
);

    localparam PAD_WIDTH = WORD_WIDTH_OUT - WORD_WIDTH_IN;

    generate
        if (PAD_WIDTH == 0) begin: zero
            always @(*) begin adjusted_output = original_input; end
        end
        if (PAD_WIDTH > 0) begin: sign_extend
            localparam PAD_ZERO = {PAD_WIDTH{1'b0}};
            localparam PAD_ONES = {PAD_WIDTH{1'b1}};
            always @(*) begin
                adjusted_output = ((SIGNED != 0) && (original_input[WORD_WIDTH_IN-1] == 1'b1))
                                  ? {PAD_ONES, original_input} : {PAD_ZERO, original_input};
            end
        end
        if (PAD_WIDTH < 0) begin: truncate
            always @(*) begin adjusted_output = original_input [WORD_WIDTH_OUT-1:0]; end
        end
    endgenerate
endmodule
```

The primitive's defaults are intentionally invalid (`WORD_WIDTH_IN = 0`, `WORD_WIDTH_OUT = 0`) so a forgotten parameter elaboration-fails rather than silently passing zero-width buses. This is the FPGADesignElements style: "defaults of zero or an empty string… make module elaboration fail if any of the parameters are not set at module instantiation" (`references/raw/fpgacpu/verilog_coding_standard.html:269-272 @ 2026-05-20`). [V]

### 3.5 The justification primitive: `Register` (defaults intentionally unusable)

```verilog
// references/projects/FPGADesignElements/Register.v:1-8 @ 2450a54
//# A Synchronous Register to Store and Control Data

// It may seem silly to implement a register module rather than let the HDL
// infer it, but doing so separates data and control at the most basic level,
// including various kinds of resets, which are part of control. This
// separation of data and control allows us to simplify the control logic and
// reduce the need for some routing resources.
```

The point is not to wrap every flop in a module instance; the point is that the primitive's existence as a separate module makes the consuming agent name the justification at every instantiation. The bundle's analog is the §5 justification-comment convention (one short comment per registered signal).

### 3.6 Quartus report-reading table

| Report | Row to read | What it indicates | Action |
|---|---|---|---|
| Synthesis → Optimization Results | "Removed registers" | A register had no consumer; synthesis deleted it (and its driving logic, if also dead). | Inspect each entry. Intentional? Document in `synth_notes.md`. Unintentional? The source register violates justification (reg-a)/(reg-d) — delete or wire the consumer. |
| Synthesis → Optimization Results | "Merged registers" | Two or more registers were identified as having the same next-state function and equivalent fanout; synthesis merged them. | Each entry is either an intentional redundancy (rare, document it) or a mirror-copy anti-pattern (#29) — delete one source. |
| Synthesis → Optimization Results | "Stuck at 0 / Stuck at 1" | A register's value was provably constant; synthesis replaced it with the constant. | Either the source is dead (violates reg-a/b/c/d) or the consumer is wrong; investigate both directions. |
| Synthesis → State Machines | (per-FSM encoding) | The FSM extractor's view of state count and encoding; flags any state Quartus could not extract. | Cross-check the state count against the source's enum count. Cross-ref [14 §8](14-finite-state-machines.md). |
| Fitter → Resource Utilization by Entity | ALMs per module | Anomalous ALM counts vs. budget. | A module 2× over budget without an explanation flags an economy regression — typically an unintended replication. |
| Fitter → Routing Usage Summary | High local-routing utilization | Routing congestion. | Correlates with mirror-copy (#29) and wide-bus (#28) violations. |
| TimeQuest → Report Fanout | Top-fanout signals | A signal whose fanout exceeds the expected consumer count by >2× is suspicious. | Either intentional (clock, reset, broadcast bus — document it) or a hidden replication. |
| Synthesis warnings | "removed because never used", "truncated" | Source-side declarations whose bits the synthesizer found unused. | Each is bit (bit-a) violation evidence; narrow the source or document the reservation per (bit-c). |

Canonical Quartus report-string phrases ("Removed registers", "Merged registers", "Stuck at 0/1") are documented at Intel *Recommended HDL Coding Styles* (live URL `https://docs.altera.com/r/docs/683323/current @ 2026-05-20`; local `references/raw/intel/quartus_standard_design_recommendations_index.html` is a 2.6 KB app-shell with no extractable body). Cross-ref [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md) for the full report-reading workflow.

### 3.7 Construct table

| Name | Type / width / direction | Meaning | Driven by | Drives |
|---|---|---|---|---|
| `Width_Adjuster` | combinational module | Bus narrow/widen with explicit pad/sign-extend policy | Upstream `WORD_WIDTH_IN`-wide producer | Downstream `WORD_WIDTH_OUT`-wide consumer |
| `Counter_Binary` | sequential module | Mod-`2**WORD_WIDTH` counter with explicit `WORD_WIDTH`, `INCREMENT`, `INITIAL_COUNT` | Clock + `run`/`load`/`clear` controls | `count` (the WORD_WIDTH-bit value to consume) |
| `Accumulator_Binary` | sequential module | K-add accumulator with overflow flag; pipelining configurable via `EXTRA_PIPE_STAGES` | Clock + `increment_*` / `load_*` / `clear_*` | `accumulated_value` (W-bit), `accumulated_value_signed_overflow` |
| `Word_Reducer` | combinational module | Combinational reduction of K W-bit words into one W-bit result | K concatenated W-bit producers | Downstream W-bit consumer |
| `Register` | sequential module | Justification primitive; defaults of zero force the caller to declare WORD_WIDTH and RESET_VALUE | Clock + `clock_enable` + `clear` | `data_out` (WORD_WIDTH-bit) |
| `$clog2(N)` | SV system function | Width-arithmetic: ceiling of log₂(N) | Compile-time N (parameter or constant) | Width fields of `logic [...-1:0]` declarations |

## 4. Sequencing & timing

The economy check is not a single-cycle event; it has a lifecycle across the design workflow. Each phase produces evidence the next phase consumes.

- **Pre-RTL.** Budget the registers and bus widths in the microarchitecture plan; every named state element gets a justification claim before any HDL is written. Cross-ref [10](10-hardware-mindset-and-microarchitecture.md).
- **During RTL.** Every register declaration carries an inline `// Justification: (X)` comment; every bus whose width is not derived from a single-source-of-truth parameter justifies the override. Apply width-arithmetic rules (§3.2) directly. Cross-ref [13](13-registers-and-combinational-blocks.md) for the always-block discipline that complements this.
- **Post-synthesis.** Read the Synthesis report's Optimization Results section. "Removed register" / "Merged register" / "Stuck at" entries are the synthesizer's view of justification-violation symptoms; each resolves to either intentional redundancy (document it in `synth_notes.md`) or an unintentional violation (delete the source or wire the consumer). Tooling: [41](41-quartus-reports-and-verification.md).
- **Post-fitter.** Fitter's Resource Utilization by Entity flags ALM counts that deviate from the pre-RTL budget; Routing Usage Summary flags congestion correlated with mirror-copy and wide-bus violations; TimeQuest's "Report Fanout" surfaces top-fanout signals — any signal whose fanout much exceeds expected consumer count is suspect.

For protocol-pipeline-stage registers (justification (reg-d)) the timing question is whether the register is in fact required by the protocol. Skid-buffer mechanics: [21](21-skid-buffers-and-register-slices.md). The wrong answer here is the source of anti-pattern #17 — see §7.

## 5. Minimal working pattern

A frame counter that counts NTSC video lines 0–524 (525 lines per frame, active plus blank). Specification: `mod 525`, then wrap. The intended consumer is a line-decoder that reads the count as an index into a 525-entry table; therefore exactly 10 bits are needed, no more, no less. The contrast between the wrong and right versions exists to make the report-evidence interpretable.

The justification-comment convention used here (bundle-introduced [I] convention, see §2):

```systemverilog
// Composed pattern. Width-arithmetic rule per §3.2; counter primitive
// per references/projects/FPGADesignElements/Counter_Binary.v:23-45 @ 2450a54.
// Justification: (reg-a) holds state across cycles — frame-counter index
// for the NTSC line table.
logic [$clog2(525)-1:0] line_idx_q;  // 10 bits; max line value 524 = 10'h20C
```

### The wrong version (illustrative)

```systemverilog
// Anti-pattern #30 illustration (NOT to be copied; for contrast with the right version below)
logic [15:0] line_idx_q;             // 16 bits — six dead high bits (15:10)

always_ff @(posedge clk) begin
  if (!rst_n) begin
    line_idx_q <= '0;
  end else if (line_tick) begin
    if (line_idx_q == 16'd524) line_idx_q <= '0;
    else                       line_idx_q <= line_idx_q + 16'd1;
  end
end
```

Quartus Synthesis report on the wrong version (expected entries, attributed to the canonical phrases at [live URL](https://docs.altera.com/r/docs/683323/current @ 2026-05-20)):

```
Optimization Results
  Removed registers:  line_idx_q[15..10]     (Stuck at 0)
```

The high six bits are reported as removed because the comparator `== 16'd524` (whose top bits are zero) plus the increment-from-zero path proves them constant. Every downstream consumer of `line_idx_q` carries six dead bits across every fanout until synthesis can prove the path is dead — and any reader that itself widens the value will silently propagate the dead bits further. The carry chain for the `+ 16'd1` increment is six positions longer than necessary.

### The right version

```systemverilog
// Composed pattern; conforms to:
//   §3.2 width-arithmetic rule (counter mod N, non-power-of-two: $clog2(N) + explicit wrap)
//   references/projects/FPGADesignElements/Counter_Binary.v:23-45 @ 2450a54 (structural pattern)
// Justification: (reg-a) holds state across cycles — frame-counter index for the NTSC line table.

localparam int unsigned LINES_PER_FRAME = 525;
localparam int unsigned LINE_IDX_W      = $clog2(LINES_PER_FRAME);  // 10

logic [LINE_IDX_W-1:0] line_idx_q;

always_ff @(posedge clk) begin
  if (!rst_n) begin
    line_idx_q <= '0;
  end else if (line_tick) begin
    if (line_idx_q == LINE_IDX_W'(LINES_PER_FRAME - 1)) line_idx_q <= '0;
    else                                                line_idx_q <= line_idx_q + 1'b1;
  end
end
```

The post-synth report on this version has no "Removed registers" entry for `line_idx_q` (every bit has a path to the comparator or the consumer), the carry chain is exactly 10 positions, and the fanout to consumers carries exactly 10 bits.

### Bus narrowing at a consumer mismatch

When an 8-bit producer feeds a consumer that reads only 4 bits, prefer source-side narrowing if both widths are spec-fixed; otherwise insert `Width_Adjuster`:

```systemverilog
// Composed pattern; cites references/projects/FPGADesignElements/Width_Adjuster.v:16-58 @ 2450a54.
// Justification (bit-a): only the low 4 bits are consumed by tile_index_q.
Width_Adjuster #(
  .WORD_WIDTH_IN  (8),
  .SIGNED         (0),
  .WORD_WIDTH_OUT (4)
) u_narrow (
  .original_input  (producer_byte),
  .adjusted_output (tile_index_d)
);
```

The Synthesis report's expected confirmation: a row in "Removed registers" naming the upstream producer's `[7:4]` bits as removed because never used, after the upstream module is rebuilt to drive only `[3:0]`. If `Width_Adjuster` is inserted without simultaneously narrowing the producer, the report will instead show `producer_byte[7:4]` removed at the producer side and the `Width_Adjuster.truncate` branch synthesizing as a wire — both correct, but the source still carries the wasted bus declaration through hierarchy and reviewers will flag it. Pick one.

### A "justification comment" snippet

What the convention looks like in practice:

```systemverilog
// Justification (reg-a): holds state across cycles — DMA byte counter.
logic [$clog2(BURST_LEN)-1:0] dma_byte_idx_q;

// Justification (reg-b): breaks critical path from address decoder to data mux.
logic [WIDTH-1:0]             dec_to_mux_q;

// Justification (reg-d): protocol pipeline stage — AXI-Stream skid buffer.
logic                         skid_valid_q;
```

This convention is [I] — no captured archive source mandates inline justification comments. The bundle adopts it so the four-justifications check survives code review without re-deriving the answer each time. See [13](13-registers-and-combinational-blocks.md) for the surrounding `always_ff` mechanics and `_q`/`_d` naming.

## 6. Common variations across implementations

- [O] **FPGADesignElements style**: width-parameterized primitives with defaults intentionally invalid (`parameter WORD_WIDTH = 0`) so elaboration fails on a missed parameter; bus widening/narrowing happens at one explicit primitive (`Width_Adjuster`). The justification discipline is enforced by the cost of instantiation — every module has WORD_WIDTH spelled out at the call site. Source: `references/projects/FPGADesignElements/Width_Adjuster.v:16-21 @ 2450a54`, `references/projects/FPGADesignElements/Register.v:42-45 @ 2450a54`, and the convention stated in `references/raw/fpgacpu/verilog_coding_standard.html:269-272 @ 2026-05-20`.
- [O] **verilog-axis / AXI-Stream-adapter style**: bus widths declared at module boundaries with explicit `WIDTH` parameters; mismatched widths get an explicit adapter module on the path. The discipline lives at the protocol layer rather than at the bit-counting layer. Source: bundle restatement; per-project archive sources not captured in this bundle.
- [O] **lowRISC SystemVerilog style**: SystemVerilog packed structs with named fields (`typedef struct packed {...} my_bus_t;`); economy is enforced at field-naming time rather than bit-counting time — each named field has a stated purpose, and a struct member nobody reads is reviewer-visible. Source: lowRISC SV style as cited in `cyclone-v-hdl-bundle/13-registers-and-combinational-blocks.md` (the `_q`/`_d` and packed-struct conventions established there).
- [V] **Bundle convention — inline justification comments**: every register declaration is preceded by `// Justification: (X) …`; every bus declaration whose width is not derived directly from a parameter justifies the override. The bundle adopts this; no upstream source uses it in this exact form. [I] for the convention itself; [V] in the sense that it is the bundle's chosen variation.

## 7. Anti-patterns (mistakes that compile but break)

### #17 Pipeline register inserted "for safety" with no critical path justifying it

- **Symptom:** Extra latency in the data path; extra flops in the Fitter's Resource Utilization by Entity that exceed the planned budget; no TimeQuest slack-report line shows the register being load-bearing (the path it sits on already has positive slack of more than one full clock period). Often visible as `*_q1`, `*_q2`, `*_q3` chains with no functional consumer of the intermediate values.
- **Cause:** The register fails all four of (reg-a)/(reg-b)/(reg-c)/(reg-d). It does not hold state (the value is reproducible from current inputs one cycle earlier), it does not break a critical path (slack was already positive), it does not cross a clock domain, and it is not a named pipeline stage of any protocol. The author inserted it from habit or "to be safe."
- **Fix:** Delete it. Re-synthesize and confirm slack is unchanged (or improved by routing freedom). For genuine deep pipelines the architectural construction belongs in [15-pipelines-and-latency-thinking.md](15-pipelines-and-latency-thinking.md); for retiming, see Quartus's `Perform register retiming` option there. The §2 load-bearing rule's clause (reg-b) "breaks a critical combinational path" must be backed by a TimeQuest path report naming the path, not by author judgment.
- **Citation:** [I] from the load-bearing rule of this doc; supporting Cyclone V pipeline-construction discipline at [15-pipelines-and-latency-thinking.md](15-pipelines-and-latency-thinking.md). The FPGADesignElements `Accumulator_Binary` module's `EXTRA_PIPE_STAGES` parameter (`references/projects/FPGADesignElements/Accumulator_Binary.v:35-47 @ 2450a54`) is the contrast — it makes pipeline-stage insertion an *explicit* parameter rather than a habit.

### #20 (efficiency angle) Defensive 2FF synchronizer on a same-clock-domain signal

- **Symptom:** Two extra flops per "synchronized" signal that the Fitter reports as part of the design's ALM count; no Quartus metastability-analyzer entry mentions the chain because the source and destination are already in the same clock domain. The Synthesis report does *not* flag the synchronizer (correctness-wise it is a no-op).
- **Cause:** Failure of (reg-c) "crosses a clock domain" — there is no clock domain crossing. The register chain is a habit copy from CDC code, not a CDC requirement.
- **Fix:** Delete the synchronizer. If the original code was driving a wire that crosses *one specific* boundary, gate the synchronizer to that boundary only — most signals in a single-clock-domain design need none. **Cross-ref [23-cdc-single-bit.md](23-cdc-single-bit.md) for CDC correctness; this anti-pattern entry treats only the wasted area, not whether your design actually has a CDC boundary.** That second question is owned by doc 23.
- **Citation:** [I] from the load-bearing rule's clause (reg-c). For when a 2FF *is* required, doc 23 owns the citation; for the wasted-area angle, the inference is direct.

### #27 Width-N register where consumer reads only bits `[M-1:0]`, M < N

- **Symptom:** Synthesis report lists `the_register[N-1:M]` under "Removed registers" or "Stuck at 0" because synthesis proved the high bits' fanout reduces to nothing. Until the source is fixed, every fanout of `the_register` carries `N - M` dead bits through hierarchy.
- **Cause:** Bit (bit-a) violation — the high bits have no consumer. The producer was sized to a generic width (often the architectural-spec width of the parent bus) without inspecting what downstream actually reads.
- **Fix:** Narrow the source declaration to M bits and re-derive any local width arithmetic. If the relationship between N and M is parameterized, insert `Width_Adjuster` at the narrowing point so the policy is reviewer-visible at the module boundary. The §5 minimal pattern shows the Synthesis report row that confirms the change took effect.
- **Citation:** `references/projects/FPGADesignElements/Width_Adjuster.v:5-13 @ 2450a54` (the primitive's stated purpose: normalize widths before arithmetic or Boolean operations). [I] for the "strip the source over insert adjuster" preference when both widths are fixed by spec.

### #28 Wide bus through hierarchy where leaves ignore most bits

- **Symptom:** Fitter's Routing Usage Summary shows high local-routing utilization in the modules carrying the bus. Synthesis warnings per leaf say "bits removed because never used" but the upstream producer still drives the full width. The bus appears at every hierarchical level even though no inner module reads more than a slice.
- **Cause:** Bit (bit-a) violation propagated through hierarchy. The producer was sized to its own internal natural width; the bus was passed through enclosing modules unchanged; only the leaf reader looks at a few bits. Every layer between carries dead wires.
- **Fix:** Choose one. (1) Narrow at the producer — recompute the source's width to match the union of all consumer widths. (2) Narrow at the boundary closest to the producer using `Width_Adjuster`, so the dead bits don't enter hierarchy at all. Avoid the third option (narrow at the leaf) because it leaves the dead bits routed through every enclosing module.
- **Citation:** [I] from clause (bit-a) of the load-bearing rule; supporting source `references/projects/FPGADesignElements/Word_Reducer.v:1-15 @ 2450a54` (the "trace consumers, strip unused bits" pattern lives at this level).

### #29 Mirror copy of a signal in two modules instead of fanout

- **Symptom:** Two registers in two modules with identical RHS expressions and identical reset values. Synthesis report's "Merged registers" lists them as merged into one. The Fitter's "Report Fanout" of the original source shows a fanout that exceeds the number of modules reading it, and TimeQuest's per-source path list shows two distinct destination clocks (the same value reaches both modules through duplicated paths).
- **Cause:** Failure of (reg-a) — only one of the two copies actually "holds state across cycles" in a non-redundant sense; the second is a duplicate of the first. The author replicated the value in two modules instead of routing the original signal as a fanout to both.
- **Fix:** Delete one register. Drive the consumer module from the surviving register via a port (or, if the value is genuinely shared across a clock-domain boundary, via a properly designed synchronizer — but check (reg-c) first). If the two copies served independent timing reasons (e.g., one is registered close to consumer A to break a path, one close to consumer B), then they are not mirror copies — they are two distinct (reg-b) justifications, and each is legitimate; document both.
- **Citation:** [I] from clause (reg-a) of the load-bearing rule. The Quartus "Merged registers" report-row is the synthesizer's own evidence — see §3.6 and §8. The yosys analog (`opt_merge -share_all`) and the way redundancy-elimination surfaces as a Yosys optimization pass is documented in `references/extracted_text/zipcpu/class_verilog.txt:2156, 4479-4515 @ 2026-05-20`; the principle ("the synthesis tool will tell you when you have redundancy") is the same on Quartus.

### #30 Counter wider than `$clog2(N)` for a mod-N counter

- **Symptom:** Synthesis report lists `counter[N-1:M]` under "Removed registers" (`M = $clog2(N)`) or "Stuck at 0" for the high bits. The carry chain is longer than necessary; the counter's fanout to consumers carries dead bits at every level.
- **Cause:** Bit (bit-a) and clause (reg-a) double violation — the high bits never toggle, and they have no consumer. The counter was declared with a power-of-two width chosen for software-style convenience (8-bit, 16-bit, 32-bit) instead of the spec width.
- **Fix:** Re-declare the counter with `logic [$clog2(N)-1:0] count_q;`. For non-power-of-two N, add an explicit wrap test `if (count_q == N-1) count_q <= '0;`. The §5 minimal pattern shows the exact construction; the Synthesis report's expected confirmation is "no Removed registers entry on this signal."
- **Citation:** `references/projects/FPGADesignElements/Counter_Binary.v:8-9, 23-45 @ 2450a54` (the module's WORD_WIDTH parameter is the bit count, and the contract is "wraps around if it goes below zero or above `(2^WORD_WIDTH)-1`"). The `$clog2` rule for width sizing is bundle convention per `cyclone-v-hdl-bundle/01-glossary.md:32 @ 2026-05-19`.

### #31 Sign bit carried where unsigned is provably sufficient

- **Symptom:** A signal declared `logic signed [W-1:0]` is consumed only by readers that compare against `0` or against another unsigned value; no arithmetic ever produces a negative result, and no downstream consumer interprets the sign bit. The carry chain on every `+` and every comparison is one position longer than necessary; the sign-extension in any width-adjustment elaborates as an extra mux.
- **Cause:** Failure of bit (bit-b) at the sign position — no protocol field requires sign, and no consumer reads it as sign. The author declared `signed` defensively or as a software-style habit.
- **Fix:** Re-declare the signal as unsigned. Audit the consumer side for any place that compared `signed_x < 0`; replace with a constant-false or a hand-written most-significant-bit check if some other interpretation was intended. If the carry chain saving is critical (deep pipeline, tight fmax), confirm in TimeQuest that the path delay drops by one carry-position; if not, the saving is bookkeeping but still worth doing because it removes a sign-related branch from every reader.
- **Citation:** `references/raw/fpgacpu/verilog_coding_standard.html:198-205 @ 2026-05-20` (the bit-width discipline treats sign-extension as a distinct choice, not a default) and `references/raw/fpgacpu/verilog_coding_standard.html:224-232 @ 2026-05-20` (the explicit sign-extension idiom — sign-extending is explicit work, not free). [V] downgrade for the prescriptive form; the source establishes the discipline but does not in those terms say "do not carry sign bits."

### #14 (surfaced, full treatment in doc 14) Redundant mergeable FSM states

- **Symptom:** State count is one or more larger than the minimum sufficient to encode the FSM. The state register uses one more bit of `$clog2(N)` encoding than necessary; the next-state decoder is wider than necessary; the design fails the economy review here.
- **Cause:** Multiple FSM states with identical output assignments and identical next-state functions; they are the same state by behavioral equivalence. Often introduced by incremental development without re-deriving the state-transition table.
- **Fix:** Tabulate the state-transition table, identify rows that are identical in every column, collapse them. Re-derive the encoding width with `$clog2(state_count)`. Full FSM-specific mechanics, the COTTC discipline that prevents the redundancy, and the Hopcroft minimization algorithm reference are in [14-finite-state-machines.md §7 #14](14-finite-state-machines.md).
- **Citation:** [I] from clause (reg-a). Surfaced here as an economy violation; full citation chain in `cyclone-v-hdl-bundle/14-finite-state-machines.md:374-379 @ 2026-05-19`, which cites `references/projects/FPGADesignElements/fsm.html:22-32 @ 2026-05-20` for the COTTC discipline.

## 8. Verification

The economy check is a code-review gate and a report-review gate. Both are mandatory; the source-side check catches what the reports cannot (the gap between an intentional bus reservation per (bit-c) and a forgotten dead bit), and the reports catch what review cannot (the synthesizer's mechanical detection of merged or removed registers).

### Pre-commit (code-review gate)

1. Every register declaration carries an inline justification comment per the §5 convention. A register without one fails review.
2. Every bus declaration whose width is not derived directly from a single-source-of-truth parameter justifies the override in a comment (typically a width-arithmetic derivation per §3.2 or a (bit-b)/(bit-c) protocol/reservation claim).
3. Every `signed` declaration justifies the sign claim (see anti-pattern #31).

### Post-synthesis (Quartus Synthesis report)

1. **Optimization Results → Removed registers.** Every entry resolves to either intentional (documented in a per-project `synth_notes.md`) or a violation of (reg-a)/(reg-d). Treat the report as authoritative — the synthesizer has proved unreachability of the consumer side.
2. **Optimization Results → Merged registers.** Every entry resolves to either intentional redundancy (rare; usually only for ECC or fault-tolerance work that explicitly replicates) or a mirror-copy anti-pattern (#29) — delete one source.
3. **Optimization Results → Stuck at 0/1.** Every entry resolves to either a dead source (delete) or a wrong consumer (the source is alive, but the consumer reads only constants from it — which means the bus declaration is too wide or the consumer's connection is wrong).
4. **State Machines list.** Every FSM declared in source appears with the expected state count. A missing FSM means Quartus did not extract it ([14 §8](14-finite-state-machines.md)). A state count higher than the source's enum count means encoding bloat (typically one-hot when the source declared binary, or a Quartus override of the source's encoding).

Canonical report-string phrases are documented at Intel *Recommended HDL Coding Styles* (live URL `https://docs.altera.com/r/docs/683323/current @ 2026-05-20`; local capture is an app-shell with no body). Full report-reading mechanics: [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md).

### Post-fitter (Quartus Fitter report)

1. **Resource Utilization by Entity.** ALM count per module is within ±20% of the pre-RTL budget. A module 2× over budget flags either an unintended replication or a budget that needed to grow — both demand explanation.
2. **Routing Usage Summary.** High local-routing utilization correlates with mirror-copy (#29) and wide-bus (#28) violations.
3. **TimeQuest → Report Fanout.** Top-fanout signals are inspected; the expected fanout is derivable from the design's module count. A signal with much greater fanout than expected is either an intentional broadcast (document it) or a hidden replication.

### Symptoms of economy violation in the field

- Fmax surprises in deep pipelines: the carry chain on a too-wide counter or accumulator is longer than its `$clog2(N)`-or-`W+$clog2(K)`-sized analog, and the extra carry positions become the critical path. See §3.2.
- High routing congestion on the Fitter report: traced backward to a mirror-copy (#29) or wide-bus (#28) violation.
- Synthesis "Merged register" reports that change between source revisions without a corresponding source change: instability in the source means redundancy in the source. A clean source produces a stable, near-empty Merged-registers list across revisions.
- Quartus warnings for "bits removed because never used" or "truncated" accumulating over revisions: every one is a hint at a (bit-a) violation upstream.

## 9. Provenance footer

- `references/projects/FPGADesignElements/Width_Adjuster.v @ 2450a54` — used for §2 (bus-narrowing rule), §3.4 (full verbatim primitive excerpt), §3.7 (construct table), §5 (bus-narrowing snippet), §6 (FPGADesignElements style citation), §7 anti-patterns #27 and #28.
- `references/projects/FPGADesignElements/Counter_Binary.v @ 2450a54` — used for §2 ($clog2(N)-sized counter rule), §3.2 (width-arithmetic table), §3.7, §5 (the wrong/right counter comparison and the right version), §7 anti-pattern #30.
- `references/projects/FPGADesignElements/Accumulator_Binary.v @ 2450a54` — used for §2 (W+$clog2(K) accumulator rule), §3.2, §3.7, §7 anti-pattern #17 (the `EXTRA_PIPE_STAGES` parameter as the contrast against habit-inserted pipelines).
- `references/projects/FPGADesignElements/Word_Reducer.v @ 2450a54` — used for §3.7 (construct table), §7 anti-pattern #28 (the trace-consumers pattern).
- `references/projects/FPGADesignElements/Register.v @ 2450a54` — used for §3.5 (the justification primitive whose defaults force the caller to declare WORD_WIDTH and RESET_VALUE).
- `references/projects/FPGADesignElements/fsm.html @ 2026-05-20` — used for §2 (state-merging consequence) and §7 anti-pattern #14 (cross-ref to doc 14 for the COTTC discipline citation).
- `references/raw/fpgacpu/verilog_coding_standard.html @ 2026-05-20` — used for §2 (bit-width-matching rule, multiplexer 8:1 rule, sign-bit discipline), §3.4 (the FPGADesignElements-style defaults-of-zero convention), §7 anti-pattern #31 (sign-extension as explicit work).
- `references/raw/fpgacpu/system_design_standard.html @ 2026-05-20` — used for §2 (minimize-warnings discipline, the inference chain for the load-bearing rule).
- `references/extracted_text/zipcpu/class_verilog.txt @ 2026-05-20` — used for §7 anti-pattern #29 (the Yosys `opt_merge -share_all` analog of Quartus's "Merged registers" reporting; "the synthesis tool will tell you when you have redundancy" principle).
- `cyclone-v-hdl-bundle/01-glossary.md @ 2026-05-19` — used for §2 ($clog2 definition), §3.3 (DE10-Nano `5CSEBA6U23I7` resource numbers — 110K ALMs, 5.6 Mbit M10K+MLAB, 112 DSP), §7 anti-pattern #30.
- `cyclone-v-hdl-bundle/14-finite-state-machines.md @ 2026-05-19` — used for §2 (FSM state-merging rule, cross-doc cite), §7 anti-pattern #14 (full treatment cross-ref).
- `https://docs.altera.com/r/docs/683323/current @ 2026-05-20` — used for §2 (per-rule consequence: removed/merged/stuck-at register reports), §3.6 (Quartus report-reading table — canonical phrases), §8 (Synthesis Optimization Results and State Machines list). Live URL only; the local `references/raw/intel/quartus_standard_design_recommendations_index.html`, `quartus_standard_general_coding_guidelines.html`, and `quartus_standard_register_latch_guidelines.html` are 2.6 KB app-shell stubs with no extractable body.
- `https://docs.altera.com/api/khub/documents/s60vJiu_kjIh2yag_Ea_yg/content @ 2026-05-20` — used for §3.3 (Cyclone V product table source for the DE10-Nano `5CSEBA6U23I7` resource numbers; the local `references/raw/intel/cyclone_v_product_table_api.txt` is a 2-page PDF whose page rendering exceeds the Read tool's 256 KB cap).
