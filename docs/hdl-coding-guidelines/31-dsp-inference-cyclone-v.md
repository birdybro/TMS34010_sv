# DSP Inference on Cyclone V

> Bundle version: 2026-05-19
> Pinned commits: see [references/MANIFEST.md](../references/MANIFEST.md) — Intel "Inferring Multipliers and DSP Functions" (Quartus Standard 18.1, live URL — local capture is an app-shell with no body), Cyclone V Device Handbook Vol 1 "Variable-Precision DSP Blocks" / "Operational Modes" (live URLs — local captures are app-shells), Cyclone V product table (`references/raw/intel/cyclone_v_product_table_api.txt`, binary PDF — the 112-DSP figure is independently surfaced in [01-glossary.md](01-glossary.md)), FPGADesignElements (`Multiplier_Binary_Parallel.v`, `Adder_Subtractor_Binary.v`, `Bit_Shifter.v`, `Register_Pipeline_Simple.v`), FPGACPU `verilog_coding_standard.html`.
> Load with: [15-pipelines-and-latency-thinking.md](15-pipelines-and-latency-thinking.md), [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md), [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md), [32-arithmetic-patterns-and-operator-cost.md](32-arithmetic-patterns-and-operator-cost.md), [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md)
> Status mix: a few firm [C] (registered-template requirement, signedness discipline, the 27×27 / 18×19 / 9×9 precision set), several [V] (multiply-add / multiply-accumulate inference patterns, IP-instantiation guidance, constant-operand strength reduction), and one load-bearing [I] (era-faithfulness: when the original chip lacked a parallel multiplier, do not use the DSP block). The era-faithful rule is the bundle's, not Intel's.

## 1. Purpose & one-line summary

Cyclone V variable-precision DSP blocks accept registered multiply, multiply-add, and multiply-accumulate patterns from generic HDL; the consuming agent must write the template Quartus recognizes, and must **NOT** use a DSP block when emulating a chip that lacked one. The deliverable this doc produces in the consuming agent is an explicit **DSP-vs-fabric-vs-iterative decision for every `*` operator in the design**, with a registered-input/registered-output template confirmed by the Fitter Resource Section.

The target part is the Terasic DE10-Nano's Cyclone V SoC `5CSEBA6U23I7`. It has **112 variable-precision DSP blocks** (see [01-glossary.md](01-glossary.md) entry for `5CSEBA6U23I7`); if a design's multiply count exceeds that budget, the design is wrong or needs decomposition, not more DSPs.

What this doc does **not** cover (deferred via Load with):

- Era-faithful microarchitecture more broadly (resource sharing, single-bus, cycle accuracy) → [17](17-era-faithful-microarchitecture.md).
- Memory inference (RAM/ROM) on M10K/MLAB → [30](30-memory-inference-cyclone-v.md).
- Non-multiply arithmetic cost (adders, comparators, dividers, shifters, variable shifts) → [32](32-arithmetic-patterns-and-operator-cost.md).
- Pipelining patterns and latency thinking in general; this doc only treats the DSP-required registers → [15](15-pipelines-and-latency-thinking.md).
- Quartus report-reading mechanics → [41](41-quartus-reports-and-verification.md).
- Signed/unsigned discipline in the SystemVerilog subset more broadly → [12](12-synthesizable-sv-subset.md).

## 2. The contract (must-obey)

Every rule below carries exactly one label. Where a label is [I], the inference chain is named in the same paragraph.

- **[C] Registered multiply for DSP inference.** To infer a Cyclone V variable-precision DSP block at full fmax, the multiply RTL **must** include at least one input register **and** one output register on the multiply operation. Quartus's recommended HDL template uses input registers, optional pipeline registers, and an output register; without registers, inference drops to soft-logic multipliers or fails. *Source:* Intel *Inferring Multipliers and DSP Functions* (Quartus Standard 18.1, live URL `https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/inferring-multipliers-and-dsp-functions` @ 2026-05-20 — the page states "to obtain high performance in DSP designs, use register pipelining and avoid unregistered DSP functions"). See §3 for the verbatim signed-multiplier template.

- **[C] Signedness must be explicit.** Use `$signed(...)` or declare operands as `logic signed [N-1:0]` / `reg signed [N-1:0]`. Mixed signedness without an explicit cast resolves to unsigned multiplication in Verilog-2001 / SystemVerilog and produces silently wrong results for negative operands. *Source:* Intel *Inferring Multipliers* (live URL above) — the signed-multiplier template is presented with explicit `signed` on every relevant declaration; the page calls `signed` "a feature of the Verilog 2001 Standard." Also FPGADesignElements `Multiplier_Binary_Parallel.v` lines 98-100 (the inline comment "These **MUST** be declared as `signed`, else the multiplication will be inferred as unsigned and calculate the wrong results when given negative integers").

- **[C] Cyclone V variable-precision DSP precision set.** The block supports 27×27, 18×19 (two independent multipliers per block in the dual-18×19 configuration), and 9×9 signed multiplies, and a multiply-adder / multiply-accumulate mode internal to the block. Operands wider than the largest mode require multi-DSP composition plus an alignment-and-summation adder tree. *Source:* [01-glossary.md](01-glossary.md) entry for "DSP block" (which states 27×27 / 18×18 / 9×9 plus dual 18×19); Intel Cyclone V Device Handbook Vol 1, Variable-Precision DSP Blocks section (live URL `https://docs.altera.com/r/docs/683375/current/cyclone-v-device-handbook-volume-1-device-interfaces-and-integration` @ 2026-05-20 — local capture is the 71-line app shell `references/raw/intel/cyclone_v_variable_precision_dsp.html`, no body content). The dual-18×19 mode is the variable-precision feature Cyclone V advertises.

- **[V] Multiply-add and multiply-accumulate inference templates.** For `(a*b) + (c*d)` and `acc <= acc + (a*b)`, write a single `always` block with registered inputs, a registered product (or two registered products), and a registered sum/accumulate output. The synthesizer infers the multiply-adder or multiply-accumulator atom of one DSP block. *Source:* Intel *Inferring Multiply-Accumulator and Multiply-Adder Functions* (live URL `https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/inferring-multiply-accumulator-and-multiply-adder-functions` @ 2026-05-20) — the page describes the multiplier-adder pattern as "two to four multipliers feeding one or two levels of addition, subtraction, or addition/subtraction operators. Addition is always the second-level operator, if it is used." See §3 for the verbatim template.

- **[V] When inference will not reach, instantiate Intel IP.** Complex multiply, pre-adder, very-high-speed pipelined multiplier, or a specific DSP-block mode Quartus does not pattern-match — instantiate via the Quartus IP Catalog (`altera_mult_add`, `LPM_MULT`, or the Intel FPGA Floating-Point IP) rather than fight inference with `(* keep *)` and synthesis pragmas. *Source:* Intel *Inferring Multiply-Accumulator and Multiply-Adder Functions* (live URL above) — the page notes that the inference covers a defined pattern set and that "some device families offer additional advanced multiply-adder and accumulator functions" reachable only via IP instantiation. The IP catalog itself is outside this bundle's scope; instantiation form is mentioned briefly in §6.

- **[V] Constant-operand multiplies should not consume a DSP block.** When one operand of `*` is a synthesis-time constant, the synthesizer's strength reduction is reliable and converts the multiply to shifts and adds in fabric; if the design still consumes a DSP block for a constant-operand multiply, it was written in a way that defeated strength reduction (e.g., the constant flowed through a register that the synthesizer did not see as constant) and must be rewritten. *Source:* [32-arithmetic-patterns-and-operator-cost.md](32-arithmetic-patterns-and-operator-cost.md) (cross-ref — the operator-cost framing lives there); Intel *Inferring Multipliers* (live URL above) for the inference-vs-fabric distinction. Marked [V] because nothing forbids the DSP block here; it is wasteful, not incorrect.

- **[I] Era-faithfulness: do not use the DSP block when the original chip lacked one.** For emulation cores whose original silicon had no parallel multiplier (MOS 6502, Z80, most pre-1985 8-bit chips, many 16-bit MPUs that used iterative-multiply microcode), the multiply **must** be modeled as iterative shift-add over the chip's documented cycle count. Using a DSP block here is not a synthesis error — it is an era-faithfulness violation that changes the chip's externally observable timing and breaks software that depends on multiply latency. *Inference chain:* [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md) §2 establishes the cycle-accuracy boundary and the mirroring contract; this doc inherits that rule and applies it to the multiply operation specifically. The era-faithful pattern is composed from FPGADesignElements primitives (see §5 and §6); the rule itself is the bundle's [I], not Intel's. See §7 anti-pattern #26.

## 3. Constructs / signals / API reference

This section is the doc's centerpiece. It contains two verbatim Intel templates — one for a registered signed multiplier, one for the multiply-add (two multipliers feeding one adder) — and a table summarizing the inference patterns and their DSP-block consumption.

The Intel page is the primary source for both templates. The local HTML capture at `references/raw/intel/quartus_standard_design_recommendations_index.html` is an app-shell with no body (71 lines of bootstrap chrome only); both excerpts cite the live URL at `docs.altera.com`. The excerpts preserve exact identifier names, signal declarations, whitespace, and ordering from the published source so the consuming agent can paste either template into a module and have Quartus infer the intended DSP block without modification.

### 3.1 Verbatim Intel template — registered signed multiplier (single DSP block, independent-multiplier mode)

The simplest pattern the Cyclone V DSP block recognizes: registered operands, a combinational multiply, and a registered output. Quartus infers one DSP block in independent-multiplier mode; the input and output flops pack into the DSP block's internal pipeline registers.

```verilog
// https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/inferring-multipliers:Signed-Multiplier @ 2026-05-20
module signed_mult (out, clk, a, b);
   output [15:0] out;
   input clk;
   input signed [7:0] a;
   input signed [7:0] b;

   reg signed [7:0] a_reg;
   reg signed [7:0] b_reg;
   reg signed [15:0] out;
   wire signed [15:0] mult_out;

   assign mult_out = a_reg * b_reg;

   always @ (posedge clk)
   begin
      a_reg <= a;
      b_reg <= b;
      out <= mult_out;
   end
endmodule
```

**Key features of this template** (preserved verbatim from the source):

- Every multiplier-touching declaration carries `signed`. The intermediate `mult_out` net is `wire signed`; the output `out` is `reg signed`. Drop any one of these and the multiplication resolves to unsigned, with incorrect results on negative operands. This is the [C] signedness rule in §2 made concrete.
- One `always @ (posedge clk)` block. Both input registers and the output register are in the same block; the multiply itself is a continuous `assign` between them. Quartus's register-packing algorithm is what folds these into the DSP block's input and output pipeline stages.
- No reset. Power-on state is x's in simulation, fitter-chosen (typically 0) in hardware. Adding a synchronous clear to this template is common and does not break inference; an asynchronous clear is acceptable for the DSP block too (see the multiply-add template in §3.2).
- 8×8 multiply producing 16-bit output. The same shape scales to 9×9, 18×19, and 27×27 — the precision modes the variable-precision DSP block exposes (§2 [C] precision-set rule). Operand declarations widen; the inference template's structure does not change.

### 3.2 Verbatim Intel template — multiply-adder (two products summed, one DSP block in multiplier-adder mode)

This is the hard requirement of §3: a verbatim Intel multiply-add template. Quartus infers one DSP block in multiplier-adder mode; the two multiplies and the final sum land inside the DSP block's internal adder stage.

```verilog
// https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/inferring-multiply-accumulator-and-multiply-adder-functions:Multiplier-Adder @ 2026-05-20
module sig_altmult_add (dataa, datab, datac, datad, clock, aclr, result);
   input signed [15:0] dataa, datab, datac, datad;
   input clock, aclr;
   output reg signed [32:0] result;

   reg signed [15:0] dataa_reg, datab_reg, datac_reg, datad_reg;
   reg signed [31:0] mult0_result, mult1_result;

   always @ (posedge clock or posedge aclr) begin
       if (aclr) begin
           dataa_reg <= 16'b0;
           datab_reg <= 16'b0;
           datac_reg <= 16'b0;
           datad_reg <= 16'b0;
           mult0_result <= 32'b0;
           mult1_result <= 32'b0;
           result <= 33'b0;
        end
        else begin
           dataa_reg <= dataa;
           datab_reg <= datab;
           datac_reg <= datac;
           datad_reg <= datad;
           mult0_result <= dataa_reg * datab_reg;
           mult1_result <= datac_reg * datad_reg;
           result <= mult0_result + mult1_result;
       end
   end
endmodule
```

**Key features of this template** (preserved verbatim from the source):

- **Three register stages.** Input registers (`dataa_reg` … `datad_reg`), product registers (`mult0_result`, `mult1_result`), and the output sum (`result`). Quartus packs all three stages into the DSP block's internal input / pipeline / output flops. Latency from input to output is **3 cycles** in this template (one per registered stage). A leaner two-stage template — input registers + registered sum, with combinational products — is also recognized, but the three-stage form is what the page presents and is the form that closes timing at the highest fmax.
- **Asynchronous clear (`aclr`).** This template demonstrates Intel's `posedge clock or posedge aclr` form. The bundle's own clocking convention is async-assert / sync-release reset ([11](11-clocking-resets-and-cyclone-v-clock-networks.md)); when adapting this template, the `posedge aclr` is replaced by a synchronous clear inside the `else` branch. The DSP block's accumulator/product registers support synchronous clear directly and do not require an async-clear path for correct inference.
- **15×15 → 31-bit products → 33-bit sum.** The output sum is one bit wider than either product to hold the carry from `mult0_result + mult1_result` without overflow. This width discipline is the model for any multiply-adder: product width is `WA + WB`; sum width is `max(product widths) + 1`.
- **One `always` block holding the whole pattern.** This is the same rule as in §3.1: register-packing into the DSP block requires that the registers around the multiply belong to the inferred DSP block, not to a separate module hierarchy the synthesizer cannot collapse. The page's template shows the canonical form.

The two-multiplier-feeding-one-adder structure is what Intel describes as "two to four multipliers feeding one or two levels of addition, subtraction, or addition/subtraction operators. Addition is always the second-level operator, if it is used" (Intel *Inferring Multiply-Accumulator and Multiply-Adder Functions*, live URL above @ 2026-05-20). Extending the template to three or four multiplies summed in pairs follows the same shape.

### 3.3 Pattern → resource table

Columns: Pattern (the RTL shape) | Inferred resource | Pipeline cycles (from input edge to output edge in the registered template) | DSP mode (the Cyclone V Device Handbook Vol 1 operational mode the Fitter reports) | Notes.

| Pattern | Inferred resource | Pipeline cycles | DSP mode | Notes |
|---|---|---|---|---|
| Registered multiply, operand widths ≤ 27 bits each. | 1 DSP block. | 2 (input reg + output reg). | Independent multiplier. | The §3.1 template scales here. For ≤9×9 or ≤18×19 pairs, the block packs two multiplies. [V] |
| Two registered multiplies summed (multiply-adder), operands ≤ 18 bits each. | 1 DSP block. | 3 (input + product + sum) as in §3.2 template, or 2 (input + sum) for the leaner form. | Multiplier-adder. | §3.2 template. [V] |
| Multiply-accumulate `acc <= acc + (a*b)`, operands ≤ 18 bits each. | 1 DSP block. | 2 (input + acc). | Multiply-accumulate (MAC). | Acc-register is internal to the DSP block; clear is synchronous. [V] |
| Registered multiply with operand width > 27 bits (e.g., 36×36, 32×32). | Multiple DSP blocks + an ALM-fabric adder tree for the cross-term sums. | 2 (multi-DSP composition retains the inference template's latency) + tree depth. | Compose: multiple independent-multipliers + alignment fabric. | Quartus does this automatically when the template uses the wider type; if timing closes poorly, instantiate the multiplier IP instead. [V] |
| Constant-operand multiply (`a * 7'd13` or `a * PARAM_CONST`). | 0 DSP blocks. ALMs + dedicated-add chains in fabric. | 1 (single registered result; the strength-reduced shift-add chain is combinational). | (none — no DSP block) | Strength reduction. If the Fitter consumes a DSP block here, the constant was not visible to the synthesizer; rewrite. [V] |
| Iterative shift-add multiply (era-faithful) — explicit FSM + shifter + adder, no `*`. | 0 DSP blocks. ALMs for the FSM, shift register, accumulator, and adder. | N cycles for N-bit operands (matches the original chip's documented multiply latency). | (none — no DSP block) | §5 + §6.2 patterns. Cite [17](17-era-faithful-microarchitecture.md). [I] |

The DSP-mode names ("independent multiplier", "multiplier-adder", "multiply-accumulate") follow the Cyclone V Device Handbook Vol 1 operational-mode taxonomy (live URL `https://docs.altera.com/r/docs/683375/current/cyclone-v-device-handbook-volume-1-device-interfaces-and-integration` — DSP Operational Modes section; local capture `references/raw/intel/cyclone_v_dsp_operational_modes.html` is the 71-line app shell, no body content). The Fitter Resource Section identifies each DSP block by its mode using these same names.

## 4. Sequencing & timing

### 4.1 Pipeline-register diagram for the §3.1 registered multiply

```
                   +-----------+        +---------------+        +-----------+
        a -->[a_reg]----+
                                        |               |
                                        |  combinational|
                                        |   multiply    |        +-----------+
        b -->[b_reg]----+--------------->   (a_reg *    |------->|  out      |---> result
                                        |    b_reg)     |        +-----------+
                                        +---------------+
        ^                                                              ^
        |                                                              |
        +--- registered inside DSP block ---+   +--- combinational ----+   +-- registered inside DSP block --+
        clk-edge N                              N→N+1 (multiply)              clk-edge N+1
```

- Latency: **2 cycles** from a stable input on `a, b` to a corresponding `out`.
- Throughput: **1 result per cycle** when fully pipelined (each cycle accepts new `a, b` and emits the previous cycle's product).
- The registers around the multiply belong **inside** the inferred DSP block; do not place them in a separate module hierarchy that the synthesizer cannot collapse. (Source: Intel *Inferring Multipliers* live URL above — the template uses one `always` block enclosing both input and output registers.)

### 4.2 Pipeline-register diagram for the §3.2 multiply-adder

```
   dataa -->[dataa_reg]----+
                            \
   datab -->[datab_reg]------>--- combinational mult0 --->[mult0_result]----+
                                                                             \
                                                                              \
                                                                               +--- combinational sum --->[result]---> out
                                                                              /
                                                                             /
   datac -->[datac_reg]----+ /
                            \/
   datad -->[datad_reg]------>--- combinational mult1 --->[mult1_result]----+

   clk-edge N      |  clk-edge N+1 (products)  |  clk-edge N+2 (sum)
```

- Latency: **3 cycles** from a stable input on `dataa, datab, datac, datad` to a corresponding `result`, using the §3.2 template's three register stages.
- The DSP block's internal adder is the second-level operator; Intel's wording is "Addition is always the second-level operator, if it is used" (live URL above @ 2026-05-20).
- Throughput: **1 sum per cycle**.

### 4.3 Multiply-accumulate timing

The MAC pattern (`acc <= acc + (a*b)`) lives in the DSP block's internal accumulator register. Clearing the accumulator uses a synchronous clear signal in the inference template, not an asynchronous reset: the DSP block supports a synchronous-clear pin on the accumulator stage. Adding `if (acc_clr) acc <= '0;` inside the `always @(posedge clk)` block is the form Quartus recognizes; an `if (rst_n == 0) acc <= '0;` async-mixed branch can still infer the DSP block on Cyclone V but is style-discouraged here (see [11](11-clocking-resets-and-cyclone-v-clock-networks.md) for the bundle's reset convention).

### 4.4 Iterative shift-add timing (era-faithful path)

The multiply takes **N cycles** for N-bit operands. The control FSM must match the original chip's documented cycle count, not the minimum-cycle implementation. A 6502 emulation does not have a multiply; a chip whose documented multiply latency is 16 cycles must take 16 cycles in the FPGA implementation, even if a shorter shift-add chain would fit. The cycle count is the externally observable behavior, not just an internal choice. (See [17](17-era-faithful-microarchitecture.md) for the cycle-accuracy boundary that owns this rule.)

## 5. Minimal working pattern

The smallest correct usage that consumes exactly one Cyclone V DSP block in independent-multiplier mode is the §3.1 template adapted to 18×18 (so the result is 36 bits, exactly the variable-precision block's most common single-multiplier configuration on Cyclone V). The adaptation is mechanical: widen the operand declarations from `[7:0]` to `[17:0]` and the result declarations from `[15:0]` to `[35:0]`.

```verilog
// references/projects/FPGADesignElements/Multiplier_Binary_Parallel.v:67-87 + Intel signed-multiplier template (composed) @ 2026-05-20
// 18x18 signed registered multiplier — one DSP block in independent multiplier mode.
module mult_18x18_signed (
    input  wire                clk,
    input  wire signed [17:0]  a,
    input  wire signed [17:0]  b,
    output reg  signed [35:0]  p
);
    reg signed [17:0] a_reg, b_reg;

    always @(posedge clk) begin
        a_reg <= a;
        b_reg <= b;
        p     <= a_reg * b_reg;
    end
endmodule
```

**Expected Fitter Resource Section line:**

```
DSP Block Usage: 1 / 112 ( < 1 % )
  Mode: independent multiplier (one 18×19 / 18×18 signed)
```

If the Fitter reports `0` DSPs or reports the multiply landed in ALMs, see §7 anti-pattern #23 — the registered-template requirement was violated. If the Fitter reports more than one DSP block, the operand widths exceeded the single-block precision (anti-pattern in §7 "multiply wider than DSP without alignment logic").

This minimal pattern is an [I] composite: it borrows the parameter and port-declaration shape from FPGADesignElements `Multiplier_Binary_Parallel.v` lines 67-87 (which uses `*` and lets the CAD tool infer; that file's `INPUT_PIPE_DEPTH = 1, OUTPUT_PIPE_DEPTH = 0` configuration produces this same pattern), and the registered-template discipline from the Intel signed-multiplier template (§3.1). No single source carries the exact lines above; the composition is honest about what is borrowed from where.

## 6. Common variations across implementations

Each variation is labeled [O] with a specific source. The iterative shift-add variation (§6.2) receives roughly equal weight to the parallel-DSP variation (§6.1) — it is this doc's distinguishing contribution for emulation work.

### 6.1 Parallel DSP variation — Intel canonical inference template

The Intel-recommended inference template is the registered-input / registered-output form shown verbatim in §3.1 and §3.2. The synthesizer packs the surrounding registers into the DSP block's internal flops; latency is 2 cycles for a simple multiply, 2-3 cycles for a multiply-adder. Throughput is one result per cycle. Resource cost is one DSP block per registered multiply within the variable-precision block's modes (27×27, 18×19, 9×9; two 18×19 per block in dual mode).

[O] Source: Intel *Inferring Multipliers and DSP Functions* and *Inferring Multiply-Accumulator and Multiply-Adder Functions*, Quartus Standard 18.1 (live URLs in §2 and §3 citations) @ 2026-05-20. The §3.1 and §3.2 templates are the canonical evidence; verbatim excerpts shown there.

### 6.2 Iterative shift-add variation — era-faithful FSM-driven multiplier

When the original chip had no parallel multiplier, the multiply is a control FSM + a shifter + an accumulator that performs one conditional-add and one shift per cycle. The pattern is composed from FPGADesignElements primitives:

- `Bit_Shifter.v` (combinational left/right shift over a parameterized count) for the operand shift.
- `Adder_Subtractor_Binary.v` (parameterized signed/unsigned add or subtract) for the conditional accumulate step.
- `Register_Pipeline_Simple.v` (parameterized delay pipeline) or a plain `reg` array for the shift-register holding the work-in-progress partial product.
- A small FSM (per [14](14-finite-state-machines.md)) gating the shift / conditional-add for the chip's documented multiply latency (typically 8-32 cycles).

The FSM produces a `done` strobe after exactly N cycles, where N is the original chip's documented multiply latency. The accumulator holds the final product. No `*` operator appears in the RTL; no DSP block is consumed; the Fitter reports `0 DSP blocks` for the multiply path. **This is the only correct shape for an emulation core whose original chip lacked a parallel multiplier.**

[O] Sources (this is a composite — no single FPGADesignElements file is itself an iterative shift-add multiplier; the brief was honest about pointing at primitives):
- `references/projects/FPGADesignElements/Adder_Subtractor_Binary.v` — the conditional accumulate step (signed-add primitive).
- `references/projects/FPGADesignElements/Bit_Shifter.v` — the per-cycle shift primitive.
- `references/projects/FPGADesignElements/Register_Pipeline_Simple.v` — the shift-register / pipeline primitive.
- FSM mechanics per [14-finite-state-machines.md](14-finite-state-machines.md).
- The era-faithful rule itself is [I] and lives in [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md).

### 6.3 FPGADesignElements parallel-multiplier wrapper with parameterized I/O pipelining

`Multiplier_Binary_Parallel.v` is a parameterized signed multiplier whose `INPUT_PIPE_DEPTH` and `OUTPUT_PIPE_DEPTH` parameters control how many pipeline stages surround the `*` operator. It is **not** itself an iterative shift-add multiplier (the brief's wording can be read to suggest that; on inspection of the file it is an inferred-multiplier wrapper). What this module gives over a hand-written §3.1 template is parameterized pipe depth, which is useful when wide multipliers need multi-DSP composition plus retiming-friendly extra stages.

The file's own comments call out the inference-friendly form explicitly: lines 30-46 describe writing the inputs, pipelines, and `*` "all together in a single clocked always block to match the recommended HDL style for multiplier inference (UG901, *Vivado Design Suite User Guide: Synthesis*). This code also works under Intel Quartus Prime as its HDL coding guidelines for inferring multipliers are the same (UG-20131, *Intel Quartus Prime Pro Edition User Guide: Design Recommendations*)." Lines 98-100 reiterate the [C] signedness rule: declare every pipeline register `signed` else the multiply infers unsigned.

[O] Source: `references/projects/FPGADesignElements/Multiplier_Binary_Parallel.v` lines 30-46 (inference-style framing) and lines 98-100 (signedness must-do) @ MANIFEST snapshot.

### 6.4 Intel IP instantiation — when inference cannot reach

For complex multiply (full Re/Im decomposition into four real multiplies and two adds), pre-adder use (`(a+b) * c` in the same DSP cycle), very-high-speed multiply requiring more pipeline stages than `Multiplier_Binary_Parallel.v` exposes, or floating-point multiply — instantiate the Intel IP via the Quartus IP Catalog (`altera_mult_add`, `LPM_MULT`, `Intel FPGA Floating-Point IP`) rather than wrestle with inference. The form is a vendor-IP instantiation; the bundle does not go deeper than naming the option here.

[O] Source: Intel *Inferring Multiply-Accumulator and Multiply-Adder Functions* (live URL above) @ 2026-05-20 — the page notes that the inference pattern set is defined and that "some device families offer additional advanced multiply-adder and accumulator functions" reachable via IP instantiation only. Specific IP user-guide deep-dive is outside this bundle's scope.

## 7. Anti-patterns (mistakes that compile but break)

This doc owns the primary treatment of pre-committed anti-patterns **#23** and **#26**. Both are presented in full Symptom → Cause → Fix → Citation form below, followed by three additional entries that the brief calls out and the source material supports.

### #23 — Multiply not registered for DSP inference

**Symptom:** Quartus's Fitter Resource Section reports zero DSP blocks consumed despite multiplies present in RTL. The Synthesis report (and sometimes a Warning in Analysis & Synthesis) shows the multiply mapped to soft logic instead of a DSP block. The affected hierarchy shows large ALM usage on the multiply path — a 16×16 multiply in fabric costs hundreds of ALMs where one DSP block would do. Timing closes poorly on the multiply path or not at all; the critical path runs through a soft-logic multiplier tree at the FPGA's slow internal-routing speed instead of through the DSP block's dedicated, fast multiplier.

**Cause:** the multiply was written as a combinational assignment (`assign c = a * b;`) or inside an `always_comb` block without surrounding registers. Quartus's inference template requires at least an input register and an output register surrounding the `*` operator (the §3.1 template); without them, the synthesizer cannot match the DSP-block inference pattern and falls back to soft-logic multiplier synthesis. A common variant is registering only the output (`always_ff @(posedge clk) c <= a * b;` with `a` and `b` arriving as wires) — this fails to pack the input registers into the DSP block and may also infer soft logic depending on the upstream's register placement.

**Fix:** wrap the multiply in `always @(posedge clk)` with both input registers and an output register, matching the §3.1 template structure (registered `a_reg`, `b_reg`, combinational `mult_out = a_reg * b_reg`, registered `out`). Place the entire pattern in a single `always` block; do not factor the input registers into a separate sub-module that the synthesizer cannot fold back in. After re-compile, confirm the Fitter Resource Section shows one DSP block per multiply (the exact "Mode" line names the inferred mode — independent multiplier, multiplier-adder, or MAC). For an audit pattern: every `*` operator in the design should land in a deliberate place — DSP block (registered), strength-reduced (constant operand), or iterative (era-faithful). See §8.5.

**Citation:** Intel *Inferring Multipliers and DSP Functions* (live URL `https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/inferring-multipliers-and-dsp-functions` @ 2026-05-20) — the page mandates "to obtain high performance in DSP designs, use register pipelining and avoid unregistered DSP functions" and presents the registered template (§3.1) as the canonical inference shape. Local capture is the 71-line app shell `references/raw/intel/quartus_standard_design_recommendations_index.html`; live URL is the authority. FPGADesignElements `Multiplier_Binary_Parallel.v` lines 30-46 also documents the same single-`always`-block requirement under the Vivado UG901 / Quartus UG-20131 framing.

### #26 — Used DSP block where original chip used iterative shift-add (era-faithfulness)

**Primary home for this anti-pattern is this doc.** [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md) carries a shorter cross-reference entry from the era angle; the detailed treatment lives here.

**Symptom:** the emulation core's multiply completes in 1-2 cycles where the original chip took 8-32 cycles. Software that relied on multiply timing breaks in characteristic ways: delay loops measured against multiply runs run faster than expected; interleaved bus activity (e.g., a CPU multiply concurrent with a video controller's memory access) no longer overlaps the way it did on real silicon; benchmark code and timing-tuned game routines (audio synthesis envelope steps, scrolling effects, copy-protection cycle traps) differ measurably from the reference hardware. A cycle-by-cycle pin-level trace comparison against original-silicon or a cycle-accurate emulator (Visual6502, MAME) reveals the divergence at the cycle the original chip's multiply would have been mid-shift.

**Cause:** the multiply was written as `c <= a * b;` because it works and synthesizes. The mirroring rule (an emulation core's RTL describes the original chip's microarchitecture — [17-era-faithful-microarchitecture.md §2](17-era-faithful-microarchitecture.md)) was violated: the original chip's microarchitecture did not contain a parallel multiplier, so the FPGA implementation must not contain one either. The DSP block is the wrong primitive for this multiply, not because it produces wrong values but because it produces them in the wrong number of cycles. The writer either did not check what the original chip did, or treated multiply-latency as an internal implementation detail rather than as externally observable behavior.

**Fix:** replace the parallel multiply with an iterative shift-add multiplier (§6.2 pattern) whose FSM cycle count exactly matches the original chip's documented multiply latency. The shift-add core is composed from `Bit_Shifter.v` + `Adder_Subtractor_Binary.v` + a shift-register (`Register_Pipeline_Simple.v` or a plain `reg` array) gated by a down-counter loaded with the operand width. Confirm zero DSP blocks consumed for this multiply path in the Fitter Resource Section. Add a testbench assertion that the multiply takes exactly N cycles, where N is the original chip's documented latency (see §8.3). Cross-reference [17](17-era-faithful-microarchitecture.md) for the era-faithful framing and the cycle-accuracy boundary that owns this rule.

**Citation:** the era-faithful rule itself is [I] (the bundle's, not Intel's) and is established in [17-era-faithful-microarchitecture.md §2](17-era-faithful-microarchitecture.md). The mechanism primitives are `references/projects/FPGADesignElements/Bit_Shifter.v`, `references/projects/FPGADesignElements/Adder_Subtractor_Binary.v`, and `references/projects/FPGADesignElements/Register_Pipeline_Simple.v`. The Cyclone V variable-precision DSP block is the resource the consuming agent must **not** use here — Cyclone V Device Handbook Vol 1, Variable-Precision DSP Blocks section (live URL `https://docs.altera.com/r/docs/683375/current/cyclone-v-device-handbook-volume-1-device-interfaces-and-integration` @ 2026-05-20; local capture is the app-shell `references/raw/intel/cyclone_v_variable_precision_dsp.html`, no body content). The reader needs to know what the DSP block IS in order to see why avoiding it is the rule's content.

### Mixed-signedness multiply

**Symptom:** the multiplier produces wrong values on negative operands. Sign flips at boundaries (-1×-1 producing a large positive instead of 1) or 2× factors on MSB-set values (-128×-128 in an 8-bit multiply producing 32768 with the wrong width). Simulation may pass for small-positive operands and fail only at boundary cases.

**Cause:** one operand was declared `signed` and the other was declared without `signed`. Verilog-2001 / SystemVerilog resolve mixed-signed arithmetic as **unsigned** — the moment any operand in the expression is unsigned, the whole expression is unsigned. Intermediate `wire` / `reg` declarations for the multiply result also matter; even with both inputs `signed`, declaring `wire mult_out` (no `signed`) drops sign in the assignment.

**Fix:** declare every multiplier-touching declaration `signed` end-to-end — inputs, intermediate `wire`, output `reg`. The §3.1 template shows the discipline. If one operand is genuinely unsigned, zero-extend it by one bit to a `signed` form: `wire signed [WIDTH:0] u_extended = {1'b0, unsigned_op};`, then multiply with both operands `signed`.

**Citation:** Intel *Inferring Multipliers and DSP Functions* (live URL above) — the signed-multiplier template carries explicit `signed` on every declaration; the page calls `signed` "a feature of the Verilog 2001 Standard." FPGADesignElements `Multiplier_Binary_Parallel.v` lines 98-100 reinforce: "These **MUST** be declared as `signed`, else the multiplication will be inferred as unsigned and calculate the wrong results when given negative integers." Cross-ref [12-synthesizable-sv-subset.md](12-synthesizable-sv-subset.md).

### Constant-operand multiply consumes a DSP block

**Symptom:** the Fitter Resource Section consumes a DSP block for a multiply where one operand is a synthesis-time constant (e.g., `pixel <= rgb * 7'd13;` or `index * STRIDE` where `STRIDE` is a `localparam`). Strength reduction should have produced shifts-and-adds in fabric (`x * 13 == (x<<3) + (x<<2) + x`). With 112 DSPs on the DE10-Nano, wasted blocks become a budget problem.

**Cause:** the constant was hidden from the synthesizer — flowed through a flop the synthesizer cannot prove is constant, passed through a module port that blocks constant propagation, or assembled at runtime from values not resolvable at compile time.

**Fix:** convert to explicit shifts and adds, or rewrite to expose the constant: use the `localparam` directly in the `*` expression rather than routing through a register; flatten the module hierarchy; mark ports `parameter` rather than runtime input. Verify zero DSP blocks for the affected logic.

**Citation:** [32-arithmetic-patterns-and-operator-cost.md](32-arithmetic-patterns-and-operator-cost.md) — operator cost and constant-multiply strength reduction live there. Intel *Inferring Multipliers* (live URL above) names the inference-vs-fabric distinction.

### Multiply wider than the DSP block without alignment logic

**Symptom:** a multiply with operand widths exceeding the variable-precision DSP block's largest mode (36×36 or 32×32, where the block tops out at 27×27 on Cyclone V) generates a multi-DSP composition plus a wide ALM-fabric adder tree for cross-term sums. The adder tree runs at fabric speed; timing closes poorly with the critical path through the alignment logic, not the DSPs.

**Cause:** the writer assumed one DSP can hold any width or did not check the variable-precision modes (§2 [C] precision-set rule). Quartus's multi-block composition is correct, but without explicit pipelining the unbalanced alignment tree limits fmax.

**Fix:** either split the multiply explicitly into 18×18 sub-products with register stages between adder-tree levels (matching the §3.2 three-stage discipline) so the cross-term adders pipeline cleanly, or instantiate the Intel multiplier IP (`altera_mult_add` / `LPM_MULT`) configured for the target width — the IP carries its own pipeline-depth parameter and a balanced adder tree. For ≥36×36, the IP route is typically right.

**Citation:** Intel *Inferring Multipliers and DSP Functions* (live URL above) — the page's inference covers single-block precision modes; multi-block compositions are mentioned but wider multiplies are steered to the IP catalog. Cyclone V Device Handbook Vol 1, Variable-Precision DSP Blocks (live URL `https://docs.altera.com/r/docs/683375/current/cyclone-v-device-handbook-volume-1-device-interfaces-and-integration` @ 2026-05-20) for the precision modes.

## 8. Verification

### 8.1 Fitter Resource Section — DSP block usage

After Quartus compile, open the Fitter report (`output_files/<project>.fit.rpt`) and navigate to the **Resource Section → DSP Block Usage** subsection. The report enumerates each DSP block consumed and its mode (independent multiplier, multiplier-adder, multiply-accumulate). For every `*` operator in the design, confirm the expected DSP-block consumption:

- Registered multiply within 27×27 / 18×19 / 9×9 → exactly one DSP block in independent-multiplier mode.
- Multiply-add per §3.2 → exactly one DSP block in multiplier-adder mode.
- Multiply-accumulate per §4.3 → exactly one DSP block in multiply-accumulate mode.
- Constant-operand multiply → zero DSP blocks.
- Iterative shift-add (era-faithful) → zero DSP blocks.
- Multiply wider than a single block → multiple DSP blocks + alignment fabric (or one DSP-block IP instance if instantiated via IP Catalog).

For each multiply path that disagrees with the expected count or mode, the corresponding §7 anti-pattern is the diagnostic: #23 for missing DSP; #26 for unwanted DSP in era-faithful code; multi-block over-consumption for the over-wide-without-alignment pattern.

### 8.2 Functional simulation — golden vectors

Drive each multiplier with a golden-vector testbench covering: zero on each side; identity (`a*1`, `1*b`); all-ones / `-1` on each side; max-positive × max-positive; max-positive × min-negative (asymmetric signed boundary); min-negative × min-negative (exposes mixed-signedness — should produce a large positive); MSB-set operands at boundary widths; plus a random N×N sample compared to a software-computed reference. Any signed-boundary mismatch is the mixed-signedness anti-pattern.

### 8.3 Iterative-multiplier cycle-count assertion (era-faithful)

For iterative shift-add multipliers, write a testbench assertion that the multiply takes exactly N cycles, where N is the original chip's documented multiply latency. The form:

```systemverilog
// SVA: when the multiply starts (start_strobe asserted for one cycle), the done
// strobe must assert exactly N cycles later. N is the original chip's documented
// multiply latency (per chip's reference manual).
property p_mult_latency;
    @(posedge clk) disable iff (!rst_n)
    start_strobe |-> ##(LATENCY_N) done_strobe;
endproperty
assert property (p_mult_latency);
```

`LATENCY_N` is a `localparam` whose value is the chip's documented cycle count — not the minimum-cycle implementation. Behavioral correctness alone does not establish era-faithfulness; the cycle count must match.

### 8.4 TimeQuest — multiply-path slack

Open TimeQuest after compile. For each multiply path that targets a DSP block (per §8.1), confirm the setup slack is positive at the design's target clock period. The registered template (§3.1) should close at or near the DSP block's documented fmax for the chosen precision (Cyclone V's DSP block can run at several hundred MHz in the smallest modes; the specific fmax for the chosen mode is in the Cyclone V Device Handbook Vol 1, live URL above). If slack is negative on a multiply path:

- The registers may have escaped the DSP block — check the Fitter Resource Section's per-block detail to see whether the input/output flops packed in.
- A multi-DSP composition without an alignment-pipeline stage may be the issue (§7 "multiply wider than DSP without alignment logic").
- The multiply may be in a clock domain whose period is below the DSP block's achievable fmax for that precision.

### 8.5 Inference-vs-fabric audit — every `*` is a deliberate choice

Scan the design (`grep -n ' \* ' *.sv` plus a visual review) for every `*` operator. For each, confirm a deliberate choice:

- DSP block, registered (independent / multiplier-adder / MAC mode) — §3 templates.
- Strength-reduced because one operand is constant (shift-add in fabric, no DSP) — §7 entry for the constant-operand pattern.
- Iterative shift-add for era-faithfulness (no `*` in the RTL at all; the `*` should not appear in this code path) — §6.2 pattern.

No `*` should be left in a configuration that surprises the designer. A comment near each `*` operator stating the intended fitter outcome (e.g., `// expect: 1 DSP, independent multiplier`) is the bundle-recommended discipline.

### 8.6 Era-faithfulness audit — for emulation cores

For emulation cores, confirm §8.3 against a documented reference: the original chip's reference manual cycle-count tables or a cycle-accurate emulator's trace. **Behavioral-only passing is insufficient** — a core that produces the right products in the wrong number of cycles is not era-faithful (§7 #26). The cycle-trace gate from [17 §8.3](17-era-faithful-microarchitecture.md) applies: pin-level cycle-by-cycle comparison against a reference is the only damning evidence of era-faithfulness.

## 9. Provenance footer

Sources actually cited in this doc, one entry per source, with the §s each supports. App-shell local captures are annotated `live URL, no local capture`.

- `https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/inferring-multipliers-and-dsp-functions` @ 2026-05-20 — §2 (registered-template requirement, signedness, fitter framing), §3.1 (verbatim signed-multiplier template), §7 (#23, signedness, wider-than-DSP), §8.1. Live URL, no local capture (`references/raw/intel/quartus_standard_design_recommendations_index.html` is an app shell, 71 lines, no body).
- `https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/inferring-multiply-accumulator-and-multiply-adder-functions` @ 2026-05-20 — §2 (multiply-add / MAC patterns, IP guidance), §3.2 (verbatim multiply-adder template), §4.2 ("addition is always the second-level operator"), §6.1, §6.4. Live URL, no local capture.
- `https://docs.altera.com/r/docs/683375/current/cyclone-v-device-handbook-volume-1-device-interfaces-and-integration` @ 2026-05-20 — §2 (precision set), §3.3 (DSP-mode names — Variable-Precision DSP Blocks + DSP Operational Modes sections), §7 (#26, wider-than-DSP), §8.4. Live URL, no local capture (`references/raw/intel/cyclone_v_variable_precision_dsp.html` and `references/raw/intel/cyclone_v_dsp_operational_modes.html` are app shells, 71 lines each, no body).
- `references/raw/intel/cyclone_v_product_table_api.txt` @ 2026-05-20 — §1 (112-DSP resource budget on `5CSEBA6U23I7`). Binary PDF in archive, not text-extracted; the 112-DSP figure is surfaced via [01-glossary.md](01-glossary.md).
- `references/projects/FPGADesignElements/Multiplier_Binary_Parallel.v` @ MANIFEST snapshot — §2 (signedness must-do, lines 98-100), §5 (composite port-shape, lines 67-87), §6.3 (parameterized I/O pipelining; inference framing lines 30-46), §7 (signedness anti-pattern).
- `references/projects/FPGADesignElements/Adder_Subtractor_Binary.v` @ MANIFEST snapshot — §6.2, §7 #26 (the iterative-multiplier add primitive).
- `references/projects/FPGADesignElements/Bit_Shifter.v` @ MANIFEST snapshot — §6.2, §7 #26 (the per-cycle shift primitive).
- `references/projects/FPGADesignElements/Register_Pipeline_Simple.v` @ MANIFEST snapshot — §6.2, §7 #26 (the shift-register / pipeline primitive).
- `references/raw/fpgacpu/verilog_coding_standard.html` @ MANIFEST snapshot — §2 (register-input/output discipline framing).
- `references/MANIFEST.md` @ 2026-05-20 — archive snapshot pin for the above local entries.
- [01-glossary.md](01-glossary.md) @ 2026-05-19 — §1 (resource budget), §2 (DSP-block precision set).
- [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md) @ 2026-05-19 — §2 [I] (era-faithfulness rule, cycle-accuracy boundary), §6.2, §7 #26, §8.6.
- [11-clocking-resets-and-cyclone-v-clock-networks.md](11-clocking-resets-and-cyclone-v-clock-networks.md) @ 2026-05-19 — §3.2, §4.3 (async-clear adaptation note).
- [12-synthesizable-sv-subset.md](12-synthesizable-sv-subset.md) @ 2026-05-19 — §7 signedness cross-ref.
- [14-finite-state-machines.md](14-finite-state-machines.md) @ 2026-05-19 — §6.2 (FSM gating).
- [15-pipelines-and-latency-thinking.md](15-pipelines-and-latency-thinking.md) @ 2026-05-19 — §4 (pipeline-register diagrams).
- [32-arithmetic-patterns-and-operator-cost.md](32-arithmetic-patterns-and-operator-cost.md) @ 2026-05-19 — §2 [V], §7 (constant-operand cross-ref).
