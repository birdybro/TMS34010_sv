# Arithmetic Patterns and Operator Cost (Cyclone V)

> Bundle version: 2026-05-19
> Pinned commits: FPGADesignElements @ 2450a54; fpgacpu.ca standards @ 2026-05-20; Intel Quartus Prime Standard 18.1 (live `docs.altera.com`) @ 2026-05-20.
> Load with: [15-pipelines-and-latency-thinking.md](15-pipelines-and-latency-thinking.md), [16-resource-and-state-economy.md](16-resource-and-state-economy.md), [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md), [31-dsp-inference-cyclone-v.md](31-dsp-inference-cyclone-v.md), [40-timing-closure-and-sdc.md](40-timing-closure-and-sdc.md)
> Status mix: [C] ~30% (operator-class facts from FPGADesignElements module prose plus the Cyclone V ALM carry chain); [V] ~15% (width/signed/saturation discipline from fpgacpu.ca and bundle convention); [O] ~15% (FPGADesignElements / Intel-natural / lowRISC / fpgacpu styles); [I] ~40% (every ALM-per-bit number and every mux-cost rule of thumb is an inference).
> Missing inputs: All four Intel pages named in the brief are 2.6 KB Fluid Topics app-shells with no extractable body; every Intel citation here points to a live `docs.altera.com` URL `@ 2026-05-20` and carries the note `live URL, no local capture` in §9. The Cyclone V Device Handbook PDF (`references/raw/intel/try_683375_fetch_failed.html`) is a fetch-failed stub; the ALM carry-chain claim falls back to the live URL and is cross-checked against `cyclone-v-hdl-bundle/01-glossary.md:9-11`.

## 1. Purpose & one-line summary

Every Verilog operator has a Cyclone V cost; the consuming agent must consult the per-operator cost table in §3 before writing any arithmetic expression — especially before placing `/`, `%`, a variable shift, or a variable bit-select on the critical path, because the synthesizer there will infer a restoring divider, a barrel shifter, or a wide mux and timing will not close. The deliverable is an explicit cost estimate (ALMs / DSP blocks / cycles) per operator, plus the operator-discipline contract in §2 and the two anti-patterns (#22, #39) owned here. DSP-inference templates defer to [31](31-dsp-inference-cyclone-v.md); pipeline construction to [15](15-pipelines-and-latency-thinking.md); counter/accumulator widths to [16](16-resource-and-state-economy.md); SDC and closure to [40](40-timing-closure-and-sdc.md).

## 2. The contract (must-obey)

The DE10-Nano part is `5CSEBA6U23I7` with ~110K ALMs (`cyclone-v-hdl-bundle/01-glossary.md:20`). The "ALMs per bit" numbers below are intuitions for budgeting against that 110K; the table in §3 names the source for each row.

- [C] `/` and `%` with a non-constant divisor are NOT a single-cycle operation on Cyclone V: they infer an iterative divider taking on the order of `WORD_WIDTH / STEP_WORD_WIDTH` cycles per bit (plus pipeline-sync overhead) and consuming ALMs proportional to `WORD_WIDTH × (WORD_WIDTH / STEP_WORD_WIDTH)` — built as a chain of conditional-subtract steps over multiprecision adder/subtractors. Forbidden on the critical path; instantiate Intel's Divider IP or reformulate. Source: `references/projects/FPGADesignElements/Divider_Integer_Signed.v:62-66 @ 2450a54` (latency formula); construction at `Divider_Integer_Signed.v:36-47 @ 2450a54` ("each division step addition/subtraction is done using a Multiprecision Adder/Subtractor to avoid excessive area and carry-chain critical paths"); Intel general coding guidelines, `https://docs.altera.com/r/docs/683323/current @ 2026-05-20` (live URL, no local capture). Anti-pattern #22.
- [C] Variable bit-select with a non-constant index (`a[idx]` or `a[idx +: K]` where `idx` is a signal) synthesizes to a mux of `WORD_WIDTH` inputs (or `WORD_WIDTH - K + 1` for a slice), not a wire. The mux cost is proportional to the operand width, not constant; on wide operands this is expensive logic and a deep critical path. Source: FPGADesignElements `references/projects/FPGADesignElements/Multiplexer_Binary_Behavioural.v:73-94 @ 2450a54` — the module's body is literally `word_out = words_in[(selector * WORD_WIDTH) +: WORD_WIDTH];`, which is the canonical hardware shape for variable-index part-select. Anti-pattern #39.
- [C] `<<` and `>>` with a non-constant shift amount synthesize to a barrel shifter, not a wire: the module's own comment is that it "synthesizes to LUT logic and can be quite large if not specialized to a particular situation" (`references/projects/FPGADesignElements/Bit_Shifter.v:1-7 @ 2450a54`). For widths W ≥ 8 the LUT cost grows quickly and the path becomes timing-critical; Intel's standard remedy is to pipeline it (`Bit_Shifter_Pipelined.v` exists for exactly that purpose). Anti-pattern #22.
- [C] `<<` and `>>` with a *constant* shift amount reduce to rewiring (zero ALMs, zero delay): "When the shift values are constant, the shifter reduces to simple rewiring" (`references/projects/FPGADesignElements/Bit_Shifter.v:46-47 @ 2450a54`). Always prefer a constant shift where possible.
- [C] `+` and `-` map to the Cyclone V ALM dedicated arithmetic / carry chain when written using `+` / `-` directly: "you are much better off letting the CAD tool infer the add/subtract circuitry from the `+` or `-` operator itself… mapped to the fast, dedicated ripple-carry hardware" (`references/projects/FPGADesignElements/Adder_Subtractor_Binary.v:14-20 @ 2450a54`). The ALM contains "dedicated adder logic and 2-4 registers" (`cyclone-v-hdl-bundle/01-glossary.md:9 @ 2026-05-19`); carry-chain reference at `https://docs.altera.com/r/docs/683375/current @ 2026-05-20` (live URL, no local capture).
- [I] `+` and `-` cost roughly one ALM per bit and add one carry-chain delay end-to-end for widths fitting in a single LAB; wider adders cross LAB boundaries and pay a small jump in delay per LAB cross. The "~1 ALM per bit" rule of thumb is an inference from the ALM's "dedicated adder logic" (one adder per ALM, `cyclone-v-hdl-bundle/01-glossary.md:9 @ 2026-05-20`) and is the budgeting baseline for the §3 table. Not a stated number in any single archive source; treat as guidance.
- [V] Width and signedness on every assignment, declaration, and operator must be explicit. The fpgacpu.ca discipline: "Always match bit widths of variable assignments. Even with correct implicit zero/sign-extension, if the source and sink have different width, it will raise a pointless warning in the CAD tool, obscuring other more important warnings. And if the extension is incorrect, it will cause subtle bugs" (`references/raw/fpgacpu/verilog_coding_standard.html:198-205 @ 2026-05-20`). Cross-ref [12](12-synthesizable-sv-subset.md).
- [V] Saturation/wrap behaviour on accumulators must be explicit. Carry overflow into an unintended MSB is a silent data-corruption bug. Use the saturating-adder pattern (`references/projects/FPGADesignElements/Adder_Subtractor_Binary_Saturating.v:1-40 @ 2450a54`) or write an explicit min/max clamp. Cross-ref [16](16-resource-and-state-economy.md) for accumulator-width sizing.
- [V] Wide comparators (`==`, `!=`, `<`, `<=`, `>`, `>=`) on operands ≥ 16 bits should be pipelined when on the critical path. The `Arithmetic_Predicates_Binary` module derives every comparison from a single subtraction (`references/projects/FPGADesignElements/Arithmetic_Predicates_Binary.v:51-73 @ 2450a54`), so a wide comparator pays the carry-chain delay of a subtractor of the same width plus one extra layer of post-subtract logic — i.e. is at least as long as a wide adder critical path.
- [V] Wide priority encoders (input width > 8) should be pipelined when on the critical path. The encoder's combinational depth is set by the rightmost-1 isolator (`references/projects/FPGADesignElements/Priority_Encoder.v:42-54 @ 2450a54`) plus the log-of-power-of-two stage; both grow with input width.
- [I] Binary-encoded select for an N-input mux pays a `$clog2(N)`-bit decoder layer; one-hot select skips that layer at the cost of `N` selector bits. fpgacpu.ca's rule of thumb is "be wary of multiplexers wider than 8:1… better to pipeline a sequence of smaller selections" (`references/raw/fpgacpu/verilog_coding_standard.html:665-670 @ 2026-05-20`); the bundle's binary-vs-one-hot crossover (N ≤ 8 binary, N ≥ 16 one-hot) is inferred from that plus the Annul-then-OR shape at `references/projects/FPGADesignElements/Multiplexer_One_Hot.v:38-77 @ 2450a54`.
- [I] Counter widths should match `$clog2(N)` for a mod-N counter; extra bits cost ALMs. Owned by [16](16-resource-and-state-economy.md); restated so the §3 "~1 ALM per bit" baseline is not applied to over-wide counters.

## 3. Constructs / signals / API reference

This section is the centerpiece of the doc. The cost table is split into two tables for rendering width (arithmetic operators in §3.1, select / bit-manipulation operators in §3.2); the row set is complete. After the tables, §3.3 collects the patterns: binary vs one-hot select, saturation, signed/unsigned discipline, wide-comparator and priority-encoder pipelining.

Every cost number that is not directly quoted from a module's own prose is marked [I] in the table's "Notes" column. Sources cited as `live URL` have no local capture (Intel app-shells); see §9.

### 3.1 Per-operator cost table — arithmetic

| Operator | Operand form | Cyclone V cost | Critical-path safe? | Notes / citation |
|---|---|---|---|---|
| `+` / `-` | Two signals, width ≤ 32 b | ~1 ALM/bit on dedicated carry chain; one carry-chain delay end-to-end | Yes for widths fitting in a single LAB | [C] for the carry-chain mapping: `references/projects/FPGADesignElements/Adder_Subtractor_Binary.v:14-20 @ 2450a54` ("you are much better off letting the CAD tool infer the add/subtract circuitry from the `+` or `-` operator itself… mapped to the fast, dedicated ripple-carry hardware"). [I] for the "~1 ALM/bit" number (inference from glossary ALM definition `cyclone-v-hdl-bundle/01-glossary.md:9 @ 2026-05-20`). |
| `+` / `-` | Wide (> 32 b) | Carry chain spans multiple LABs; delay grows with one small jump per LAB cross | Pipeline if on critical path | [V] Pipelining advice from `references/projects/FPGADesignElements/Adder_Subtractor_Binary_Saturating.v:32-40 @ 2450a54` ("the carry-chain of arithmetic logic is often a limiting factor in timing closure"); also Intel HDL design guidelines, `https://docs.altera.com/r/docs/683323/current @ 2026-05-20` (live URL, no local capture). |
| `*` | Constant operand × signal | Strength-reduces to shifts + adds; zero DSP blocks for power-of-two constants, a few adders for sums of shifted constants | Yes | [C] for the strength-reduction principle: `references/projects/FPGADesignElements/Bit_Shifter.v:38-47 @ 2450a54` worked examples: `3N = N + 2¹N`, `10N = 2³N + 2¹N`, `5N/4 = N + 2⁻²N`, and "When the shift values are constant, the shifter reduces to simple rewiring, which in turn reduces the above examples to an adder or two each." |
| `*` | Two signals, fits in one DSP mode (e.g. ≤ 27×27 b signed) | 1 DSP block; ~2-cycle latency when input/output registers are inferred | Yes when registered | [I] — multiplier-cost details belong to [31](31-dsp-inference-cyclone-v.md). The cost shape is corroborated by `references/projects/FPGADesignElements/Multiplier_Binary_Parallel.v:48-62 @ 2450a54` ("single input and output pipeline registers will get packed into the input and output registers of the DSP blocks"). |
| `*` | Two signals, wider than one DSP mode | Multi-DSP partial-product tree plus alignment-adder fabric; needs pipeline registers in the adder tree | Pipeline; expect difficulty | [I] cross-ref [31](31-dsp-inference-cyclone-v.md). Background at `references/projects/FPGADesignElements/Multiplier_Binary_Parallel.v:52-62 @ 2450a54` ("for wider multipliers, the inferred adder tree which merges the partial products from multiple DSP blocks may need an output pipeline to meet timing"). |
| `*` | Two signals, no DSP available (shift-add) | ~N cycles for N-bit operands; uses adder + shifter per step; ~one ALM per bit per stage | Pipelined by construction | [I] — shift-add multiplier shape from `references/projects/FPGADesignElements/Bit_Shifter.v:56-59 @ 2450a54` ("part of the construction of a conditional-add multiplier, which multiplies two N-bit words in N cycles, giving a 2N-bit result"). DSP-inference details deferred to [31](31-dsp-inference-cyclone-v.md). |
| `/`, `%` | Variable divisor | Iterative restoring divider; latency `≈ WORD_WIDTH / STEP_WORD_WIDTH` cycles per bit + sync overhead; area roughly `WORD_WIDTH × (WORD_WIDTH / STEP_WORD_WIDTH)` ALMs from the multiprecision adder/subtractor chain | NO — FORBIDDEN on the critical path | [C] `references/projects/FPGADesignElements/Divider_Integer_Signed.v:62-66 @ 2450a54` (latency formula in the module's own words); construction at `Divider_Integer_Signed.v:24-47 @ 2450a54`. Quotient and remainder are split into two parallel modules: `references/projects/FPGADesignElements/Quotient_Integer_Signed.v @ 2450a54` and `references/projects/FPGADesignElements/Remainder_Integer_Signed.v @ 2450a54`. Anti-pattern #22 — see §7. |
| `/`, `%` | Constant divisor, power of two | Wiring (`>>` for `/`) plus a small bitmask (for `%`); zero ALMs for unsigned operands | Yes | [C] `references/projects/FPGADesignElements/Divider_Integer_Signed_by_Powers_of_Two.v:1-22 @ 2450a54` (the module documents the signed-correction step — even the "free" case is not strictly free for signed operands; see §3.3 Saturation/wrap discipline). |
| `/`, `%` | Constant non-power-of-two divisor | Multiply-by-reciprocal trick (Hacker's-Delight Chapter 10); ~2 multiplies + a shift + a fix-up; bounded area, single-cycle if a DSP is available | Yes if precomputed | [I] — pattern named in `references/projects/FPGADesignElements/Divider_Integer_Signed_by_Powers_of_Two.v:12-15 @ 2450a54` ("The implementation is based on the PowerPC method, as described in Hacker's Delight, Section 10-1"). Detail deferred to the referenced text; the cost shape is the multiply rows above plus one constant add. |
| `<<` / `>>` | Constant shift amount | Wiring; zero ALMs, zero delay | Yes | [C] `references/projects/FPGADesignElements/Bit_Shifter.v:46-47 @ 2450a54` ("the shifter reduces to simple rewiring"). |
| `<<` / `>>` | Variable shift amount, width W | Barrel shifter; LUT-based mux network with depth `~log₂(W)` mux layers and width proportional to operand width × W; explicitly large at W ≥ 8 | Costly at W ≥ 8; pipeline if needed | [C] for "synthesizes to LUT logic and can be quite large": `references/projects/FPGADesignElements/Bit_Shifter.v:1-7 @ 2450a54`. [I] for the depth/width numbers (rule of thumb; not a stated number in any source). Pipelined version at `references/projects/FPGADesignElements/Bit_Shifter_Pipelined.v:1-7 @ 2450a54`. Anti-pattern #22 — see §7. |
| `==`, `!=` | Narrow (≤ 16 b) | XOR per bit then OR-reduce tree; a few ALMs (~W/4 plus a small reduction tree) | Yes | [I] for the ALM count. The XOR-OR-reduce shape is the textbook equality circuit; in FPGADesignElements, equality is derived from a subtraction-then-zero-check (`references/projects/FPGADesignElements/Arithmetic_Predicates_Binary.v:84-87 @ 2450a54`: `A_eq_B = (difference == ZERO);`), which also fits on the carry chain. |
| `==`, `!=` | Wide (> 16 b) | XOR-reduce tree of depth `~log₂(W)`; routes through more LUT layers | Pipeline if on critical path | [V] pipelining advice from §3.3 and `references/raw/fpgacpu/verilog_coding_standard.html:655-664 @ 2026-05-20` ("If you construct your logic as series of expressions of 6 or fewer terms with registers in between, then you minimize the logic and interconnect delay"). |
| `<`, `<=`, `>`, `>=` | Narrow | Subtract on carry chain + sign-check; one ALM per bit plus one final comparison stage | Yes | [C] for the "subtract then check" shape: `references/projects/FPGADesignElements/Arithmetic_Predicates_Binary.v:51-73 @ 2450a54` (every predicate is computed from a single `A-B` subtraction's `difference`, `carry_out`, and `overflow_signed`). [I] for the ALM count. |
| `<`, `<=`, `>`, `>=` | Wide (≥ 32 b) | Long carry chain; same delay as a wide adder of equal width | Pipeline if needed | [I] — implied by the construction at the preceding row's citation; the carry-chain delay is the dominant term. |

### 3.2 Per-operator cost table — bit-select, slice, mux, priority encode

| Operator / construct | Operand form | Cyclone V cost | Critical-path safe? | Notes / citation |
|---|---|---|---|---|
| Bit-select `a[i]` | Constant `i` | Wiring; zero ALMs, zero delay | Yes | [C] (trivial). |
| Bit-select `a[i]` | Variable `i`, operand width W | W-input 1-bit mux; cost proportional to W; one extra LUT layer per doubling of W | Costly at W ≥ 16; pipeline | [C] `references/projects/FPGADesignElements/Multiplexer_Binary_Behavioural.v:73-94 @ 2450a54` (the module's body is the canonical hardware shape: `word_out = words_in[(selector * WORD_WIDTH) +: WORD_WIDTH];`). Anti-pattern #39 — see §7. |
| Slice `a[i +: K]` | Constant `i` | Wiring; zero ALMs | Yes | [C] (trivial). |
| Slice `a[i +: K]` | Variable `i`, operand width W | K parallel W-input muxes; cost roughly `K × W` mux fabric | Very costly; reformulate | [C] same citation as the variable bit-select row; the structural shape is the same with `K` instead of 1 output bits. Anti-pattern #39. |
| `casez` / `if/else` priority cascade | Wide one-hot or priority over W inputs | Priority encoder: rightmost-1 isolator + log-of-power-of-two; combinational depth grows with W | Pipeline at W > 8 | [V] `references/projects/FPGADesignElements/Priority_Encoder.v:42-54 @ 2450a54` (rightmost-1 isolator then logarithm — both grow with W). Pipelining advice in §3.3. |
| Mux, binary-select | N inputs of W bits | Each output bit is an N-input mux; one `$clog2(N)`-bit decoder layer; for N ≤ 4 fits in one 6-LUT per output bit and registers for free | Yes for N ≤ 8 | [V] for the N ≤ 8 threshold: `references/raw/fpgacpu/verilog_coding_standard.html:665-670 @ 2026-05-20` ("A 4:1 mux has 6 inputs terms (4 input bits and 2 selector bits) and so maps exactly to one 6-LUT per result bit, and can be registered 'for free'. If you want to maximize speed, be wary of multiplexers wider than 8:1"). [I] for the "~one ALM per 4 bits per input" cost shape. |
| Mux, one-hot select | N inputs of W bits | Annul-then-OR per input; no decoder layer; selector cost is N bits instead of `$clog2(N)` | Yes; preferred for N > 16 | [O] structural shape from `references/projects/FPGADesignElements/Multiplexer_One_Hot.v:38-77 @ 2450a54` (per-input `Annuller`, then `Word_Reducer` OR-tree). [I] for the N > 16 crossover threshold (inference from the fpgacpu.ca 8:1 binary-mux warning above plus the absence of a decoder layer here). |
| Address decoder, behavioural `==` | Range hit, addresses sparse | One wide `==` per range; sums of-products into the hit signal; cost grows with number of distinct ranges | Yes for a few ranges | [O] `references/projects/FPGADesignElements/Address_Decoder_Behavioural.v @ 2450a54` (let synthesis fold to range checks; minimal hand-coded structure). |
| Address decoder, arithmetic | Range hit, contiguous range | Two comparators (`addr >= BASE` and `addr <= BOUND`) AND-ed; uses the carry chain twice | Yes | [O] `references/projects/FPGADesignElements/Address_Decoder_Arithmetic.v @ 2450a54`. The cost is "two `Arithmetic_Predicates_Binary` plus an AND," i.e. two carry-chain subtractions of `ADDR_WIDTH`. |
| Address decoder, static | Range hit, computed at elaboration | Up to `2^ADDR_WIDTH` per-address compares OR-reduced; unusable past ~20 bits | Only for very small fixed ranges | [O] `references/projects/FPGADesignElements/Address_Decoder_Static.v:11-22 @ 2450a54` ("Elaborating and optimizing this logic can take a *very* long time… this decoder will be likley unusable for address ranges more than 20 bits wide"). Includes its own "I do not recommend this implementation" warning at line 23. |

### 3.3 Patterns

#### Binary vs one-hot select

The fpgacpu.ca rule (`references/raw/fpgacpu/verilog_coding_standard.html:665-670 @ 2026-05-20`) gives the binary side: a 4:1 mux maps to one 6-LUT per output bit and registers "for free"; an 8:1 mux is the warning threshold; wider than 8:1 should be pipelined or restructured. The bundle's binary-vs-one-hot crossover is:

- **N ≤ 4:** binary select; mapping is one 6-LUT/bit, the cheap case.
- **N = 5 to 8:** binary select; still maps reasonably but with one extra LUT layer.
- **N = 9 to 16:** either; binary needs a `$clog2(N)`-bit decoder layer that increases routing pressure, one-hot pays N selector bits but avoids the decoder. Choose based on which selector is cheaper to generate.
- **N > 16:** one-hot select; the missing decoder layer matters more than the extra selector bits. Construction: `references/projects/FPGADesignElements/Multiplexer_One_Hot.v:38-77 @ 2450a54` (Annul-then-Word_Reducer OR).

[I] — the N-threshold numbers above are this bundle's distillation; no single archive source mandates them. Cross-ref [16](16-resource-and-state-economy.md) for the broader "every bus bit must justify itself" framing.

#### Saturation / wrap discipline

The saturating-adder pattern wraps a normal carry-chain adder with two signed comparisons at the limits and clamps before truncation. The module's structure (`references/projects/FPGADesignElements/Adder_Subtractor_Binary_Saturating.v:1-40 @ 2450a54`) is: extend operands by one bit, add as unsigned, compare against `limit_max` and `limit_min` using `Arithmetic_Predicates_Binary`, then clip and truncate. Note the module's own warning at lines 32-40 that the chained adder + comparator is "twice as long as expected, plus 2 more bits to avoid overflow" — pipeline the *inputs* of any saturating adder placed on the critical path.

Carry overflow into an unintended MSB is a silent data-corruption bug. The fpgacpu.ca discipline says width-mismatched assignments raise CAD-tool warnings that "obscure other more important warnings" (`references/raw/fpgacpu/verilog_coding_standard.html:198-205 @ 2026-05-20`); the bundle convention is to either size the destination to `W + $clog2(K)` for K additions of W-bit values (cross-ref [16](16-resource-and-state-economy.md)) or to use the saturating-adder pattern explicitly.

#### Signed / unsigned discipline

The sign-extension trap is real: Verilog's expression-evaluation rule is that "all terms of an expression must be declared signed else the expression is silently evaluated as unsigned" (`references/projects/FPGADesignElements/Adder_Subtractor_Binary.v:21-26 @ 2450a54`). One concrete consequence:

```verilog
// SILENTLY UNSIGNED: A is signed, but B is not
reg signed [WORD_WIDTH-1:0] A;
reg        [WORD_WIDTH-1:0] B;
wire signed [WORD_WIDTH:0]  diff;
assign diff = A - B;   // B forces the expression unsigned;
                       // sign-bit of A is treated as MSB, not sign
```

Fix: declare both operands `signed`, or normalize widths explicitly using `Width_Adjuster` (the FPGADesignElements idiom for sign-aware width changes — cross-ref [16](16-resource-and-state-economy.md) §3.4). The pattern in `Adder_Subtractor_Binary.v:101-118` of doing the arithmetic on `{1'b0, A} + {1'b0, B_selected} + …` — i.e. all-unsigned with explicit zero prepends — sidesteps the sign-bit trap entirely.

#### Wide-comparator pipelining

A 64-bit `==` placed in one combinational cycle pays a 64-bit XOR-reduce (or equivalently a 64-bit subtraction's `difference == 0` check) on the carry chain. The fpgacpu.ca rule (`references/raw/fpgacpu/verilog_coding_standard.html:655-664 @ 2026-05-20`) is "expressions of 6 or fewer terms with registers in between." The bundle pattern for a wide `==`:

```verilog
// Split 64-bit == into two 32-bit halves with a register between
always_ff @(posedge clk) begin
    eq_lo_q <= (A[31:0]  == B[31:0]);
    eq_hi_q <= (A[63:32] == B[63:32]);
    eq_q    <= eq_lo_q & eq_hi_q;   // one cycle later
end
```

Two-cycle latency, but each cycle is one 32-bit equality (carry-chain comfortable) plus one AND. Cross-ref [15](15-pipelines-and-latency-thinking.md) for the parallel-valid pipeline shape.

#### Priority-encoder pipelining

A wide priority encoder pays a rightmost-1 isolator plus a logarithm stage (`references/projects/FPGADesignElements/Priority_Encoder.v:42-70 @ 2450a54`); both grow with input width. The bundle pattern for a > 8-bit priority encoder is to register the encode after every 8 input bits and combine downstream:

```verilog
// 32-bit priority encoder, registered every 8 bits
always_ff @(posedge clk) begin
    valid_0 <= |req[ 7: 0];  enc_0 <= encode8(req[ 7: 0]);
    valid_1 <= |req[15: 8];  enc_1 <= encode8(req[15: 8]);
    valid_2 <= |req[23:16];  enc_2 <= encode8(req[23:16]);
    valid_3 <= |req[31:24];  enc_3 <= encode8(req[31:24]);
end
// Next cycle: combine four 3-bit encodes with their valids
```

[I] composite. Cross-ref [15](15-pipelines-and-latency-thinking.md).

### 3.4 Named constructs introduced in this doc

| Name | Type | Meaning | Driven by | Drives |
|---|---|---|---|---|
| `Adder_Subtractor_Binary` | parameterized module | carry-chain add/subtract with carry-in, carry-out, per-bit carries, overflow | enclosing module's operands | downstream arithmetic or comparator |
| `Adder_Subtractor_Binary_Saturating` | parameterized module | add/subtract that clamps to `[limit_min, limit_max]` instead of wrapping | enclosing module's operands and limits | downstream accumulator or datapath |
| `Arithmetic_Predicates_Binary` | parameterized module | all signed/unsigned comparison flags from a single subtraction | two operands of equal width | one or more of the 9 comparison flags |
| `Bit_Shifter` | parameterized module | variable left/right shift with triple-wide carry-out tabs | input word, shift amount, direction | shifted word + left/right tabs |
| `Bit_Shifter_Pipelined` | parameterized module | same with input/output skid buffers and internal pipeline | handshake-valid input | handshake-valid output |
| `Divider_Integer_Signed` | parameterized module | signed integer division by iterated conditional subtraction | dividend, divisor, valid/ready | quotient, remainder, divide-by-zero |
| `Divider_Integer_Signed_by_Powers_of_Two` | parameterized module | signed truncating division by `2^exponent_of_two` with negative-number correction | signed numerator, unsigned exponent | quotient, remainder |
| `Multiplexer_Binary_Behavioural` | parameterized module | N-input mux as `words_in[(selector × WORD_WIDTH) +: WORD_WIDTH]` | selector, packed words | one selected word |
| `Multiplexer_One_Hot` | parameterized module | one-hot mux as Annul-then-Word_Reducer (OR / AND / NOR…) | one-hot selectors, packed words | one combined word |
| `Multiplier_Binary_Parallel` | parameterized module | inferred multiplier with input/output pipeline registers | two operands | product (sum of operand widths) |
| `Priority_Encoder` | parameterized module | rightmost-1 isolator + log-of-power-of-two | one input word | encoded index + valid |
| `Address_Decoder_Behavioural` / `_Arithmetic` / `_Static` | parameterized modules | three styles of range decoder (let synthesis fold; explicit `>=` + `<=`; per-address compares) | address bus | hit signal |

## 4. Sequencing & timing

ALM carry-chain delay characterization: each ALM delivers one bit at high speed through the dedicated carry chain (`cyclone-v-hdl-bundle/01-glossary.md:9 @ 2026-05-20`); a register and its driving logic placed in the same LAB cost less in delay than one straddling LABs (`cyclone-v-hdl-bundle/01-glossary.md:10 @ 2026-05-20`). Wide adders cross LAB boundaries (a LAB is 10 ALMs) with one small jump in delay per cross. For most cores at the bundle's fmax targets, a 32-bit adder fits inside a single LAB-region and pays one carry-chain delay end-to-end; a 64-bit adder pays roughly twice that plus one LAB-cross delay. Detail-level closure mechanics live in [40](40-timing-closure-and-sdc.md).

DSP cycle latency: a single-DSP-block multiply registered at input and output is a 2-cycle pipeline (Multiplier_Binary_Parallel comment block, `references/projects/FPGADesignElements/Multiplier_Binary_Parallel.v:48-62 @ 2450a54`). Full DSP details (modes, register placement, multiply-add) in [31](31-dsp-inference-cyclone-v.md).

Divider iteration count: `≈ WORD_WIDTH / STEP_WORD_WIDTH` cycles per bit of result, plus `PIPELINE_STAGES_SYNC` cycles per bit, plus one cycle each for the input and output handshakes (`references/projects/FPGADesignElements/Divider_Integer_Signed.v:62-67 @ 2450a54`). A 32-bit divider with `STEP_WORD_WIDTH = 8` and `PIPELINE_STAGES_SYNC = 1` has latency `(32/8 + 1) × 32 + 2 = 162` cycles — illustrative of why `/` is forbidden on the critical path of any time-critical datapath.

Barrel-shifter combinational depth: the variable-shifter mux network has depth `~log₂(W)` mux layers when implemented as the standard log-shifter (one mux stage per shift-amount bit). [I]: not a stated number in any archive source; the canonical barrel-shifter construction.

Comparator delay: a wide comparator delay is essentially a wide-adder delay plus one final-stage gate (the `==`/`<`/`>` post-subtract logic in `Arithmetic_Predicates_Binary.v:84-97 @ 2450a54`). Use the same pipelining threshold as for wide adders.

ASCII pipeline schedule for the wide-`==` and priority-encoder patterns appears in §3.3.

## 5. Minimal working pattern

The minimal working pattern is an unsigned saturating accumulator built from `Adder_Subtractor_Binary_Saturating`. It demonstrates the §2 saturation rule and is the smallest correct pattern that uses every contract item: width-explicit, signedness-explicit, saturation-explicit, single carry-chain.

```verilog
// references/projects/FPGADesignElements/Adder_Subtractor_Binary_Saturating.v:42-62 @ 2450a54
//   instantiated below; this is the bundle's minimal usage example.

`default_nettype none

module Saturating_Accumulator_Example
#(
    parameter WORD_WIDTH = 16
)
(
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       inc_valid,
    input  wire [WORD_WIDTH-1:0]      inc_value,
    output reg  [WORD_WIDTH-1:0]      acc,
    output wire                       at_max,
    output wire                       at_min
);
    // Width-explicit limits.
    localparam [WORD_WIDTH-1:0] LIMIT_MAX = {1'b0, {WORD_WIDTH-1{1'b1}}};  // +max signed
    localparam [WORD_WIDTH-1:0] LIMIT_MIN = {1'b1, {WORD_WIDTH-1{1'b0}}};  // -max signed

    wire [WORD_WIDTH-1:0] next_acc;
    wire                  over_max, under_min;

    Adder_Subtractor_Binary_Saturating
    #(.WORD_WIDTH (WORD_WIDTH))
    sat_add
    (
        .limit_max       (LIMIT_MAX),
        .limit_min       (LIMIT_MIN),
        .add_sub         (1'b0),          // add
        .carry_in        (1'b0),
        .A               (acc),
        .B               (inc_value),
        .sum             (next_acc),
        .carry_out       (),
        .carries         (),
        .at_limit_max    (at_max),
        .over_limit_max  (over_max),
        .at_limit_min    (at_min),
        .under_limit_min (under_min)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)            acc <= '0;
        else if (inc_valid)    acc <= next_acc;       // clamped to limits inside sat_add
    end
endmodule
```

[I] composite — written for this bundle. The instantiated module is verbatim from `references/projects/FPGADesignElements/Adder_Subtractor_Binary_Saturating.v:42-62 @ 2450a54` (the module's port list, parameter, and saturation semantics); the wrapper around it is the bundle's idiom for "single-cycle saturating accumulator with explicit signed-symmetric limits."

The example uses `+` only (the cheap operator), uses constants for limits (so the comparator widths are visible at elaboration), declares every literal at WORD_WIDTH, and explicitly resets `acc` to zero — every §2 rule is exercised.

## 6. Common variations across implementations

- [O] **FPGADesignElements style** (`references/projects/FPGADesignElements/Adder_Subtractor_Binary.v:1-118 @ 2450a54`): parameterized Verilog-2001 modules with explicit `Width_Adjuster` calls before every assignment that changes width, unsigned-arithmetic-with-explicit-carries (`{1'b0, A} + {1'b0, B} + …` to avoid silently-unsigned expression trap), and "let the CAD tool infer the carry chain from the operator." Every primitive is wrapped in its own module so the inference template is reused identically.
- [O] **Intel-recommended style** (live URL: `https://docs.altera.com/r/docs/683323/current @ 2026-05-20`; live URL, no local capture): write the natural expression (`assign sum = a + b;`) and let Quartus match it to the carry chain / DSP block / barrel shifter. Cited verbatim by the FPGADesignElements adder module: "you are much better off letting the CAD tool infer the add/subtract circuitry from the `+` or `-` operator itself" (`references/projects/FPGADesignElements/Adder_Subtractor_Binary.v:14-20 @ 2450a54`). The two styles are compatible: FPGADesignElements wraps the natural expression in a module; Intel's recommendation is the same expression unwrapped.
- [O] **lowRISC style** (style guide at `https://github.com/lowrisc/style-guides`; local capture under `references/projects/lowrisc-style-guides/` if present): signed/unsigned distinguished by suffix in names (`*_s`, `*_u`), explicit width on every literal (`16'd0` rather than `0`), and a hard rule against mixed-width assignments without a cast. The bundle's §2 width-and-signedness rule generalizes this without requiring the suffix convention.
- [O] **FPGACPU coding-standard style** (`references/raw/fpgacpu/verilog_coding_standard.html:198-205, 655-670 @ 2026-05-20`): rule-based rather than primitive-based; the operator costs are stated as design-time-of-thought guidance ("series of expressions of 6 or fewer terms with registers in between… be wary of multiplexers wider than 8:1") and discipline rules ("Always match bit widths of variable assignments") rather than as a per-operator table. The bundle's §3 table makes the implicit cost surface of these rules explicit.

## 7. Anti-patterns (mistakes that compile but break)

### #22 — `/`, `%`, or variable shift on the critical path (primary home; full treatment)

- **Symptom:** Quartus reports a huge ALM count in the affected hierarchy (often hundreds or thousands of ALMs for a single expression); the synthesis report's "RTL Component Statistics" lists a "divider" or "shifter" entry; TimeQuest's worst-slack path is the divide / shift path with combinational delay measured in hundreds of nanoseconds; the design will not close timing at any plausible fmax.
- **Cause:** the writer treated `/`, `%`, or `<<`/`>>` (with a non-constant operand) as a single-cycle operation, the way it would behave in C. The Cyclone V hardware has no single-cycle divider and no single-cycle barrel shifter; the synthesizer inferred a restoring divider (for `/`/`%`) or a barrel shifter (for variable shift). Both are combinational structures that grow with operand width.
- **Fix — three concrete options, applied in order of preference:**
  1. **Reformulate.** *Constant divisor by power of two:* replace `x / 8` with `x >>> 3` (signed) or `x >> 3` (unsigned); replace `x % 8` with `x & 3'b111`. Cost goes from "iterative divider" to "wiring + a bitmask." See `references/projects/FPGADesignElements/Divider_Integer_Signed_by_Powers_of_Two.v:1-22 @ 2450a54`, which also shows the negative-number correction step for signed truncating division. *Constant non-power-of-two divisor:* replace `x / 10` with a multiply-by-reciprocal (Hacker's Delight Section 10-1) — typically two multiplies and a shift and a fix-up, all bounded; see the construction principle quoted at `references/projects/FPGADesignElements/Divider_Integer_Signed_by_Powers_of_Two.v:12-15 @ 2450a54`. *Variable shift:* if the shift amount is known one cycle earlier, register it and use it as a constant within the current cycle (e.g. inside an FSM, the shift amount is settled in the previous state); the operator then reduces to wiring per case.
  2. **Move off the critical path.** Add pipeline stages so the operation has multiple cycles to complete. For variable shift, the pipelined variant `references/projects/FPGADesignElements/Bit_Shifter_Pipelined.v:1-50 @ 2450a54` exists for exactly this purpose; for division, the `Divider_Integer_Signed` module is built around the input/output handshake — drive it from a ready/valid producer and route the consumer's `ready` through the handshake. Cross-ref [20](20-ready-valid-handshakes.md) and [15](15-pipelines-and-latency-thinking.md).
  3. **Instantiate IP.** Use Intel's Divider IP for variable division when the design needs a black-box block with documented latency/area. The IP is parameterizable for latency-vs-area trade and gives a bounded answer; FPGADesignElements `Divider_Integer_Signed.v` is the open-source equivalent of the same shape (iterative restoring divider with parameterizable step width). Either is acceptable; do not write `/` directly on a non-constant denominator.
- **Citation:** `references/projects/FPGADesignElements/Divider_Integer_Signed.v:24-66 @ 2450a54` (construction + latency), `references/projects/FPGADesignElements/Bit_Shifter.v:1-7 @ 2450a54` ("synthesizes to LUT logic and can be quite large"), `references/projects/FPGADesignElements/Bit_Shifter_Pipelined.v:1-50 @ 2450a54` (pipelined remedy); Intel general coding guidelines, `https://docs.altera.com/r/docs/683323/current @ 2026-05-20` (live URL, no local capture).

### #39 — Variable bit-select with non-constant index (primary home; full treatment)

- **Symptom:** the design contains `a[idx]` or `a[idx +: K]` where `idx` is a signal (not a constant); Quartus's synthesis report shows an unexpectedly large mux in the affected hierarchy; TimeQuest reports the bit-select path as the critical path on a wide operand; the design fails timing or fits worse than budgeted.
- **Cause:** the writer treated bit-indexing like a software array index, with O(1) cost. In hardware, `a[idx]` is a `WORD_WIDTH`-input mux; `a[idx +: K]` is K parallel `WORD_WIDTH`-input muxes. Cost scales with operand width, not constant. The canonical hardware shape is literally `words_in[(selector * WORD_WIDTH) +: WORD_WIDTH]` (`references/projects/FPGADesignElements/Multiplexer_Binary_Behavioural.v:92-94 @ 2450a54`).
- **Fix:**
  - **Make the index a constant where possible.** If the index is set by an FSM state, unroll the FSM's case branches so each branch references a constant slice — the mux is then absorbed into the FSM's existing case decoder.
  - **Register the index, pipeline the mux.** If the index must be a signal, register `idx` and the mux output so the wide-mux delay falls between two flops rather than across other combinational logic; cross-ref [15](15-pipelines-and-latency-thinking.md).
  - **Use one-hot select when the index is generated by a one-hot encoder anyway.** Replace `a[idx]` with `Multiplexer_One_Hot` driven by the one-hot selector (`references/projects/FPGADesignElements/Multiplexer_One_Hot.v:38-77 @ 2450a54`) and avoid the binary-to-one-hot decoder layer entirely.
  - **Restructure the datapath.** If the operand is very wide (≥ 64 bits) and the index ranges over the whole word, the design may be hiding a shift register or a FIFO that should be made explicit; the variable bit-select is then a symptom of a missing structural element.
- **Citation:** `references/projects/FPGADesignElements/Multiplexer_Binary_Behavioural.v:1-104 @ 2450a54` (canonical mux shape and the simulation-vs-synthesis warning at lines 5-43); Intel general coding guidelines, `https://docs.altera.com/r/docs/683323/current @ 2026-05-20` (live URL, no local capture).

### Silent overflow on accumulator

- **Symptom:** a counter or accumulator wraps unexpectedly mid-computation; downstream data is corrupted; in simulation, the result is "almost right except for the high-magnitude inputs."
- **Cause:** the accumulator was declared at width W but receives K additions of W-bit values, so any sequence whose sum exceeds `2^W - 1` (unsigned) or rolls past `2^(W-1)` (signed) wraps silently. There is no saturation, and no carry-out check.
- **Fix:** either size the accumulator to `W + $clog2(K)` bits (cross-ref [16](16-resource-and-state-economy.md) for the width-justification rule), or use the saturating-adder pattern from §5 explicitly. The saturating module clamps to `[limit_min, limit_max]` and raises the `at_limit_max` / `over_limit_max` / `at_limit_min` / `under_limit_min` flags so downstream logic can detect the clamp event.
- **Citation:** `references/projects/FPGADesignElements/Adder_Subtractor_Binary_Saturating.v:1-40 @ 2450a54`; cross-ref `references/projects/FPGADesignElements/Accumulator_Binary_Saturating.v:27-35 @ 2450a54` for the full accumulator.

### Wide combinational mux on the critical path

- **Symptom:** a large `case` or a chain of `?:` ternaries selects one of many wide payloads in a single combinational cycle; TimeQuest reports the case-selector-to-payload path as the worst-slack path; fmax falls below target.
- **Cause:** the writer treated the entire selection as one combinational stage. For N > 8 inputs, the mux logic cannot fit in one 6-LUT per output bit (fpgacpu.ca: a 4:1 mux is the "free" case; an 8:1 mux is the warning threshold), so the synthesizer stacks LUT layers.
- **Fix:** pipeline the case-statement into a sequence of smaller selections (see fpgacpu.ca rule: "better to pipeline a sequence of smaller selections," `references/raw/fpgacpu/verilog_coding_standard.html:665-670 @ 2026-05-20`); or, if a one-hot selector is naturally available, restructure as `Multiplexer_One_Hot` (`references/projects/FPGADesignElements/Multiplexer_One_Hot.v @ 2450a54`) and drop the decoder layer. For multi-stage muxing inside a single combinational expression, also cross-ref [15](15-pipelines-and-latency-thinking.md) and the related anti-pattern #16 in [15-pipelines-and-latency-thinking.md](15-pipelines-and-latency-thinking.md) §7 (long ternary/case nest treated as one combinational stage).
- **Citation:** `references/raw/fpgacpu/verilog_coding_standard.html:665-670 @ 2026-05-20`; `references/projects/FPGADesignElements/Multiplexer_One_Hot.v:38-77 @ 2450a54`.

### Mixed-width arithmetic

- **Symptom:** results are truncated or sign-extended in unexpected ways; simulation gives "wrong by powers of two" answers; the CAD tool emits dozens of width-mismatch warnings.
- **Cause:** an N-bit expression is assigned to an M-bit target without explicit width, or operands of different widths are mixed in one expression. Verilog's implicit extension rules (LRM, Section 4.4) handle this silently and not always the way the writer expected — and any `signed` declaration is contagious: one unsigned operand in a chain forces the whole expression unsigned (`references/projects/FPGADesignElements/Adder_Subtractor_Binary.v:21-26 @ 2450a54`).
- **Fix:** declare widths on every assignment; use `Width_Adjuster` (or `{N{1'b0}, x}` / `{ {N{x[W-1]}}, x }`) to normalize widths before arithmetic; treat every CAD-tool width-mismatch warning as a defect, not noise. "Always match bit widths of variable assignments… concatenation and replication can avoid this problem, and then any bit width mismatch warnings become significant" (`references/raw/fpgacpu/verilog_coding_standard.html:198-205 @ 2026-05-20`).
- **Citation:** `references/raw/fpgacpu/verilog_coding_standard.html:198-205 @ 2026-05-20`; cross-ref the bundle's signedness-discipline cross-ref in [12](12-synthesizable-sv-subset.md).

## 8. Verification

- **Resource sanity check.** Open the Quartus Fitter Resource Section after compile. For any module that performs arithmetic, confirm the ALM count is within the §3 cost-table estimate. A 32-bit adder should report ~32 ALMs; a 32-bit `Adder_Subtractor_Binary_Saturating` ~70 ALMs (the extra-bit carry chain plus two `Arithmetic_Predicates_Binary` plus the clip). Outliers reveal accidental dividers, accidental wide muxes, or accidental barrel shifters. Cross-ref [41](41-quartus-reports-and-verification.md).
- **Critical-path check.** Open TimeQuest's worst-slack report. If the failing path traverses `/`, `%`, a variable shift, or a variable bit-select, treat as anti-pattern #22 or #39 and refactor by the §7 fix steps before any other optimization.
- **Functional simulation.** For each arithmetic operator the design uses, cover sign-boundary inputs (max, min, -1, 0, 1) and overflow at width boundaries. For variable shifts, cover shift-by-0, shift-by-W-1, and shift-by-W. For variable bit-selects, cover index = 0, index = W-1, and one mid-range index. For comparators, cover `A == B`, `A == B+1`, `A == B-1`, and the sign-boundary pairs.
- **Saturation cases.** For saturating adders/accumulators, include testbench cases that drive the sum past `limit_max` and below `limit_min`; confirm `acc` clamps at the limit, the `over_limit_max` / `under_limit_min` flag asserts in the same cycle, and the accumulator does not wrap.
- **Width-mismatch warnings.** Compile with all CAD-tool warnings on; treat every width-mismatch warning as a defect to fix at source (not via warning suppression). See fpgacpu.ca rule cited in §7 "Mixed-width arithmetic."
- **DSP-inference confirmation.** When `*` should map to a DSP block, check the Fitter resource report's DSP block count; if a multiply did not infer a DSP, the synthesis report's "RTL Component Statistics" will list it as a "multiplier" in LUT logic instead — usually a hint that the multiplier-pipeline-register convention was not followed. Detail in [31](31-dsp-inference-cyclone-v.md).

## 9. Provenance footer

- `references/projects/FPGADesignElements/Adder_Subtractor_Binary.v @ 2450a54` — used for §2, §3.1, §3.3 (signed/unsigned discipline), §6 (FPGADesignElements style)
- `references/projects/FPGADesignElements/Adder_Subtractor_Binary_Saturating.v @ 2450a54` — used for §2 (saturation rule), §3.1, §3.3 (saturation pattern), §5 (minimal working pattern), §7 (silent overflow anti-pattern), §8
- `references/projects/FPGADesignElements/Accumulator_Binary_Saturating.v @ 2450a54` — used for §7 (silent overflow anti-pattern cross-reference)
- `references/projects/FPGADesignElements/Arithmetic_Predicates_Binary.v @ 2450a54` — used for §2, §3.1, §3.3 (wide-comparator pipelining), §4
- `references/projects/FPGADesignElements/Bit_Shifter.v @ 2450a54` — used for §2 (variable shift contract), §3.1 (constant- and variable-shift rows; strength-reduction principle for `*` by constant), §7 (#22)
- `references/projects/FPGADesignElements/Bit_Shifter_Pipelined.v @ 2450a54` — used for §3.1, §7 (#22 fix)
- `references/projects/FPGADesignElements/Divider_Integer_Signed.v @ 2450a54` — used for §2 (`/`/`%` contract), §3.1, §4 (divider iteration count), §7 (#22)
- `references/projects/FPGADesignElements/Divider_Integer_Signed_by_Powers_of_Two.v @ 2450a54` — used for §3.1, §7 (#22 reformulation)
- `references/projects/FPGADesignElements/Quotient_Integer_Signed.v @ 2450a54` — used for §3.1 (split formulation reference)
- `references/projects/FPGADesignElements/Remainder_Integer_Signed.v @ 2450a54` — used for §3.1 (split formulation reference)
- `references/projects/FPGADesignElements/Multiplexer_Binary_Behavioural.v @ 2450a54` — used for §2 (variable bit-select), §3.2, §7 (#39)
- `references/projects/FPGADesignElements/Multiplexer_One_Hot.v @ 2450a54` — used for §2 (binary vs one-hot), §3.2, §3.3, §7 (wide-mux anti-pattern, #39 fix)
- `references/projects/FPGADesignElements/Multiplier_Binary_Parallel.v @ 2450a54` — used for §3.1 (DSP-multiply rows), §4 (DSP cycle latency)
- `references/projects/FPGADesignElements/Priority_Encoder.v @ 2450a54` — used for §2 (priority-encoder pipelining), §3.2, §3.3
- `references/projects/FPGADesignElements/Address_Decoder_Behavioural.v @ 2450a54` — used for §3.2
- `references/projects/FPGADesignElements/Address_Decoder_Arithmetic.v @ 2450a54` — used for §3.2
- `references/projects/FPGADesignElements/Address_Decoder_Static.v @ 2450a54` — used for §3.2
- `references/raw/fpgacpu/verilog_coding_standard.html @ 2026-05-20` — used for §2 (width/signedness), §3.1 (wide-comparator), §3.2 (mux 8:1 threshold), §3.3, §6 (FPGACPU style), §7 (wide-mux and mixed-width anti-patterns), §8
- `cyclone-v-hdl-bundle/01-glossary.md @ 2026-05-19` — used for §2 (ALM/LAB/DE10-Nano counts), §3.1 (ALM-per-bit anchor), §4
- `https://docs.altera.com/r/docs/683323/current @ 2026-05-20` — used for §2 (general operator-cost framing, `/` and `%` warning, variable bit-select), §3.1 (wide adder pipelining), §6 (Intel-natural style), §7 (#22, #39) — live URL, no local capture (local file `references/raw/intel/quartus_standard_general_coding_guidelines.html` is a 2.6 KB Fluid Topics app-shell)
- `https://docs.altera.com/r/docs/683375/current @ 2026-05-20` — used for §2 (ALM carry-chain claim) — live URL, no local capture (local file `references/raw/intel/cyclone_v_device_handbook_v1_index.html` is a 2.6 KB app-shell; `references/raw/intel/try_683375_fetch_failed.html` is a fetch-failed stub)
