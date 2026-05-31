# Synthesizable SystemVerilog Subset for Cyclone V

> Bundle version: 2026-05-19
> Pinned commits: `references/raw/style/lowrisc_systemverilog_style.md` (collected 2026-05-20 per `references/MANIFEST.md`); `references/raw/verilogpro/*.html` (collected 2026-05-20); `references/raw/fpgacpu/verilog_coding_standard.html` (collected 2026-05-20); `references/projects/FPGADesignElements/Register.v` (cloned 2026-05-20); `references/projects/verilog-axis/rtl/arbiter.v` (cloned 2026-05-20)
> Load with: [13-registers-and-combinational-blocks.md](13-registers-and-combinational-blocks.md), [14-finite-state-machines.md](14-finite-state-machines.md), [10-hardware-mindset-and-microarchitecture.md](10-hardware-mindset-and-microarchitecture.md)
> Status mix: heavy [V] (Table B forbidden-construct rows + bundle style conventions); substantial [C] (synthesis rules anchored in lowRISC + tool semantics); 4 [O] in §6 (lowRISC, FPGADesignElements, verilog-axis, Intel HDL coding styles); 8 [I] in Table B forbidden-construct rows that rest on chains from lowRISC's positive constraints + community consensus rather than a single direct citation. Target part: `5CSEBA6U23I7`, Quartus Standard/Lite 18.1.

## 1. Purpose & one-line summary

This doc defines the canonical synthesis-safe SystemVerilog subset every other doc in the bundle writes against: these SV constructs synthesize predictably on Quartus 18.1 for Cyclone V; these do not. The subset is deliberately narrower than full IEEE 1800-2017 — pick from the allowed list in §3 Table A; never reach for anything in Table B. Reset construction, block-discipline mechanics, FSM patterns, memory inference, and operator cost are handled by the neighbor docs listed in `Load with:`.

## 2. The contract (must-obey)

- [C] Sequential logic uses `always_ff @(posedge clk ...)` with nonblocking assignments (`<=`) only. (lowRISC §"Sequential Logic (Registers)" lines 1805–1837; VerilogPro `systemverilog_always_comb_always_ff.html` §"SystemVerilog always_ff".)
- [C] Combinational logic uses `always_comb` with blocking assignments (`=`) only. (lowRISC §"Blocking and Non-blocking Assignments" lines 1770–1783 and §"Combinational Logic" lines 2132–2156; VerilogPro §"SystemVerilog always_comb".)
- [C] Each signal has exactly one driver across all procedural and continuous assignments — one `always` block or one `assign` per signal, full stop. (lowRISC §"Sequential Logic (Registers)" lines 1839–1858; FPGACPU `verilog_coding_standard.html` §"Initialization and Logic Values" lines 136–143.)
- [C] All declared signals use `logic` (not `reg`/`wire`) except at `inout` pins, where `wire` is mandatory. (lowRISC §"Use `logic` for synthesis" lines 2678–2725.)
- [C] User-defined types use `typedef`; declare once at package or module scope. (lowRISC §"Enumerations" lines 1207–1265; §"Functions and Tasks" lines 2455–2466.)
- [C] State enumerations use `typedef enum logic [N-1:0] { ... }` — explicit `logic` storage type, explicit width. Anonymous `enum` is forbidden. (lowRISC §"Enumerations" lines 1212–1216, lines 1231–1265.)
- [C] Every literal that is assigned, compared, or concatenated declares its width and base (`8'h00`, not `0`, not `'0` when the target width is not obvious from a parameterized expression). (lowRISC §"Always be explicit about the widths of number literals" lines 1626–1656.)
- [C] Signed arithmetic uses `logic signed` on operands; mixing signed and unsigned without an explicit `signed'(...)` / `unsigned'(...)` cast is forbidden. (lowRISC §"Signed Arithmetic" lines 2304–2334.)
- [V] Packed structs and packed arrays are the synthesis-legal aggregate types; unpacked dynamic arrays (`[]`), queues (`[$]`), associative arrays (`[*]`), `class`/`new`/`extends`, and `real`/`shortreal` are not used in synthesizable RTL. ([I] — lowRISC mandates 4-state `logic`-derived storage in synthesizable RTL (lines 2410–2412, 2682–2700), excluding these constructs by construction; no source in the corpus lists each banned class individually for Quartus 18.1, so this rule chains from lowRISC's positive constraint to community/tool consensus.)
- [V] Module-scope constants use `parameter` (user-overridable) or `localparam` (derived/internal). `defparam` is forbidden. (lowRISC §"Module Instantiation" line 1587 — *"Do not use `defparam`"*; §"Constants" lines 1593–1624.)
- [V] One module per file; the module name matches the filename. (lowRISC §"File Extensions" / §"Basic Template"; FPGACPU §"Language Subset" — *"Prefer one module per file for reusable blocks."*)
- [V] Every source file begins with `` `default_nettype none `` so a missing declaration is an elaboration error, not a silent 1-bit wire. (FPGACPU `verilog_coding_standard.html` §"Defaults" lines 94–111.)
- [V] In synthesizable RTL, functions are `function automatic`, return a packed `logic`-derived type, take only `input`s, and use an explicit `return`. Tasks are not used in RTL. (lowRISC §"Functions and Tasks" lines 2392–2495.)

## 3. Constructs / signals / API reference

This section is the body of the doc. Two tables — Allowed and Forbidden — plus a width-and-signedness subsection. Tables A and B together define the subset. Every entry in the bundle outside this doc draws only from Table A.

### 3.1 Verbatim references

The canonical `always_ff` / `always_comb` separation pattern, as published by lowRISC:

```systemverilog
// references/raw/style/lowrisc_systemverilog_style.md:1866-1895 @ 2026-05-20
always_ff @(posedge clk or negedge rst_ni) begin
  if (!rst_ni) begin
    state_q <= StIdle;
  end else begin
    state_q <= state_d;
  end
end

always_comb begin
  state_d = state_q;    // default assignment next state is present state
  unique case (state_q)
    StIdle: state_d = StInit;       // Idle State move to Init
    StInit: begin                   // Initialize calculation
      if (conditional) begin
        state_d = StIdle;
      end else begin
        state_d = StCalc;
      end
    end
    StCalc: begin                   // Perform calculation
      if (conditional) begin
        state_d = StResult;
      end
    end
    StResult: state_d = Idle;
    default: ;
  endcase
end
```

The canonical packed-struct + typedef pattern (function body trimmed to the type declarations the subset cares about):

```systemverilog
// references/raw/style/lowrisc_systemverilog_style.md:2455-2466 @ 2026-05-20
typedef logic [2:0] bar_t;

typedef struct packed {
  logic [2:0] field;
} baz_t;

function automatic logic [2:0] foo(bar_t a, baz_t b);
  return a + b.field;
endfunction
```

The canonical `typedef enum logic [N-1:0]` FSM-state declaration with explicit storage width:

```systemverilog
// references/raw/style/lowrisc_systemverilog_style.md:1241-1247 @ 2026-05-20
typedef enum logic [1:0] {  // A 2-bit enumerated type
  ACC_WRITE,
  ACC_READ,
  ACC_PAUSE
} access_e; // new named type is created
access_e req_access, resp_access;
```

### 3.2 Table A — Allowed constructs

| Construct | Synthesis semantics | Canonical example | Cited source |
|---|---|---|---|
| `logic` declaration | 4-state net/variable; replaces `reg` and `wire` for all internal signals. `wire` only at `inout` pins. | `logic [7:0] data_q;` | lowRISC §"Use `logic` for synthesis" lines 2678–2725 — [C] |
| `always_ff @(posedge clk)` | Strict synthesis promise of a flop bank; tool warns on anything that isn't a flop. NBAs only. | `always_ff @(posedge clk) q <= d;` | lowRISC §"Sequential Logic (Registers)" lines 1805–1837; VerilogPro §"SystemVerilog always_ff" — [C] |
| `always_ff @(posedge clk or negedge rst_ni)` | Async-asserted reset on a flop. Use for the assert edge only — sync-release wrapper construction is in doc 11. | `always_ff @(posedge clk or negedge rst_ni) if (!rst_ni) q <= '0; else q <= d;` | lowRISC §"Sequential Logic (Registers)" lines 1826–1837; lowRISC §"Signal Naming" lines 1166–1205 — [C] |
| `always_comb` | Compile-time check that all RHS signals are in the inferred sensitivity list; tool warns if any branch leaves an output undriven (latch). Blocking assignments only. | `always_comb begin y = a ^ b; end` | lowRISC §"Combinational Logic" lines 2132–2156; VerilogPro §"SystemVerilog always_comb" — [C] |
| `assign` (continuous) | Combinational. One driver per LHS. Prefer over a one-line `always_comb` where practical. | `assign final_value = sel ? a : b;` | lowRISC §"Combinational Logic" lines 2140–2146 — [V] |
| `typedef logic [W-1:0] name_t;` | Named packed vector type; reusable across module/package scope. Suffix `_t`. | `typedef logic [7:0] byte_t;` | lowRISC §"Use `logic` for synthesis" line 2693; §"Suffixes" line 1151 — [C] |
| `typedef enum logic [N-1:0] { ... } name_e;` | FSM-state encoding with explicit storage width and base type. Suffix `_e`. Anonymous enums forbidden. | `typedef enum logic [1:0] { ACC_WRITE, ACC_READ, ACC_PAUSE } access_e;` | lowRISC §"Enumerations" lines 1212–1247 — [C] |
| `typedef struct packed { ... } name_t;` | Bit-aligned aggregate; synthesizes as a wide vector. Field-by-field access is legal; one driver per field still applies. | See §3.1 `baz_t` excerpt. | lowRISC §"Functions and Tasks" lines 2455–2466 — [V] |
| Packed array | Bit-aligned dimension to the left of the name; treated as one multi-bit value. Little-endian (`[MSB:LSB]`). | `logic [31:0] word;` | lowRISC §"Packed Ordering" lines 2799–2817 — [C] |
| Unpacked array (memory) | Element-aligned dimension to the right of the name; treated as a collection. Big-endian (`[0:N-1]` or `[N]`). Used for memory arrays. | `logic [7:0] mem [0:255];` or `byte_t arr[256];` | lowRISC §"Unpacked Ordering" lines 2820–2834 — [V] |
| `parameter` (port-list scope) | Compile-time constant settable at instantiation. Defaults required. | `module foo #( parameter int unsigned Width = 8 ) ( ... );` | lowRISC §"Module Declaration" lines 1470–1482 — [V] |
| `localparam` (module scope) | Compile-time constant derived from other parameters or fixed in the module. Not settable at instantiation. | `localparam int unsigned ADDR_W = $clog2(DEPTH);` | lowRISC §"Constants" lines 1593–1624 — [V] |
| `$clog2(N)` / `$bits(x)` | Elaboration-time integer functions for width math. Use for derived widths. | `localparam int W = $clog2(DEPTH);` | lowRISC §"Functions and Tasks" implicit use; bundle glossary entries — [V] |
| `generate` / `for ... generate` | Elaboration-time replication. Always-name the generated block. Generate regions (`generate`/`endgenerate`) are not used. | `for (genvar ii = 0; ii < N; ii++) begin : my_inst ... end` | lowRISC §"Generate Constructs" lines 2266–2302 — [V] |
| `function automatic` | Combinational helper returning a packed `logic`-derived type. Explicit storage types on all args. `automatic` (no static state). Explicit `return`. | See §3.1 `foo` excerpt. | lowRISC §"Functions and Tasks" lines 2392–2495 — [V] |
| `unique case` with `default:` | Case statement with elaboration/simulation overlap check. `default:` is mandatory even if all values appear covered. | See §3.1 first excerpt. | lowRISC §"Case Statements" lines 2158–2234 — [V] |
| `signed'(...)` / `unsigned'(...)` cast | Explicit signedness conversion when crossing the boundary. Use instead of relying on implicit promotion. | `sum2 = a + signed'({1'b0, incr});` | lowRISC §"Signed Arithmetic" lines 2304–2334 — [C] |
| `` `default_nettype none `` | File-level directive: undeclared signals become elaboration errors. Place at top of every source file. | `` `default_nettype none `` | FPGACPU §"Defaults" lines 94–111 — [V] |

> Full treatment of `case`/`casez`/`case inside` discipline (including the `casex` ban and overlap-prevention rules) lives in [14-finite-state-machines.md](14-finite-state-machines.md); §7 of this doc gives a 2-sentence pointer. Memory-inference templates that use the unpacked-array row above belong to [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md).

### 3.3 Table B — Forbidden constructs

| Construct | Why forbidden | Where it might tempt the agent | Label |
|---|---|---|---|
| SystemVerilog `interface` with `modport` | Synthesis support is uneven on Quartus 18.1; muddles port-direction analysis; cannot reliably round-trip through Analysis & Synthesis. No corpus source documents a working Cyclone V flow. | Wide module port lists. Use packed structs in ordinary ports instead. | [I] — inference: corpus carries no Intel/lowRISC example using `interface` in synthesizable Cyclone V flow; lowRISC's positive examples (port-list style, line 1438+) use ordinary directional ports. |
| `class`, `new`, `extends`, virtual methods | Object-oriented constructs are not synthesizable. Storage allocation has no hardware analog. | Reuse via parameterized classes. Use parameterized modules + packed structs. | [I] — inference: lowRISC §"Functions and Tasks" lines 2410–2412 mandates 4-state `logic`-derived storage in synthesizable RTL; class objects do not qualify. |
| Dynamic arrays `[]`, queues `[$]`, associative arrays `[*]` | Not synthesizable — no static hardware footprint. | "Resizable" buffers. Use a fixed-depth packed array + valid pointer; size at parameter time. | [I] — inference: same chain as above (lowRISC mandates 4-state packed types in RTL). |
| `randomize()`, constraint blocks, `std::randomize`, `$random`, `$urandom` | Simulation-only. | Test stimulus accidentally bleeding into RTL. | [I] — inference: these constructs have no synthesis semantics; lowRISC §"Functions and Tasks" restricts synthesizable RTL to deterministic, statically-typed expressions (lines 2392–2495). |
| `fork ... join`, `fork ... join_any`, `fork ... join_none` | Simulation-only concurrency model. | Testbench-style multi-process modeling in RTL. | [V] — lowRISC §"SystemVerilog always_comb" gotcha (VerilogPro lines 294) explicitly notes statements that *block, have blocking timing or event controls, or fork-join* are not permitted inside `always_comb`. By chain: forbidden in every synthesizable procedural block. |
| `wait`, `#delay` (including `#0`), event controls inside synthesizable blocks | Simulation-only. Synthesis ignores `#delay`. | Sequential modeling using `#` between statements. | [C] — lowRISC §"Delay Modeling" lines 1785–1794 — *"Do not use `#delay` in synthesizable design modules."* |
| `always_latch` | A latch is almost never the right answer on Cyclone V — flop it. lowRISC discourages, the bundle forbids for synthesizable RTL targeting Cyclone V (the LUT-feedback latch implementation costs an ALM and breaks setup/hold analysis cleanly). | Combinational block with incomplete branch coverage. The correct response is to add a default assignment, not to add `always_latch`. | [V] — lowRISC §"Sequential Logic (Latches)" lines 1796–1803 *"The use of latches is discouraged"*; bundle hardens to forbid for Cyclone V (inference: no documented Cyclone V workflow requires it). |
| Real numbers (`real`, `shortreal`, `realtime`) | Not synthesizable. | Coefficient tables expressed in floating-point. Pre-compute to fixed-point at elaboration. | [V] — lowRISC §"Use `logic` for synthesis" lines 2696–2700 explicitly rejects non-`logic` storage types for RTL. |
| 2-state types in RTL (`bit`, `int`, `shortint`, `byte`, `longint`) | RTL must be 4-state to model X-propagation faithfully and avoid sim/synth mismatch on uninitialized state. | Concise loop counters in `genvar`-style usage. Use `logic`-derived types and explicit widths. | [V] — lowRISC §"Use `logic` for synthesis" lines 2682–2700 — *"all signals in synthesizable RTL must be implemented in terms of 4-state data types"*. (Exception: `genvar` for elaboration-time loops; `int unsigned` for `parameter` declarations is permitted by lowRISC, line 1474.) |
| `defparam` | Order-dependent and brittle across tool versions; cross-hierarchy parameter override defeats local reasoning. | Cross-hierarchy parameter override. Use named parameter passing at instantiation. | [V] — lowRISC §"Module Instantiation" line 1587 — *"Do not use `defparam`."* |
| Unsized literals (`'1`, `'0`, bare integer constants assigned to wider vectors) | Implicit width truncation or extension — silent at compile time, wrong at runtime. See anti-pattern #6. Exception per lowRISC: `'0` for a parameter-width zero, and `1'b1`-style increments. | Concise constant assignment. | [C] — lowRISC §"Always be explicit about the widths of number literals" lines 1630–1656; FPGACPU §"Parameterization" lines 154–161. |
| Field-by-field `assign` to packed-struct members across multiple drivers | Risks splitting the struct across drivers (one-driver-per-signal rule); some tools flag, some don't. Force whole-struct assignment from one driver. | Updating one field of a struct over time. Drive the whole struct from one block; compose the new value combinationally. | [I] — inference: lowRISC's one-driver-per-signal/bit rule (lines 1839–1858) applied to struct members. |
| Tri-state internal nets (`Z` inside fabric) | Cyclone V fabric has no internal tri-state. Synthesis builds an OR/mux tree behind your back. | "Bus" emulation. Use a one-hot select mux instead. | [V] — lowRISC §"Combinational Logic" lines 2152–2153 — *"Do not use three-state logic (`Z` state) to accomplish on-chip logic such as muxing."*; FPGACPU §"Initialization and Logic Values" lines 126–128. |
| `X` literals as "don't care" in RTL assignments | Causes sim/synth mismatch and propagation surprises. Fully define every signal value. | "Optimization hint" to the synthesizer. Use SVA instead to flag invalid conditions. | [V] — lowRISC §"Don't Cares (`X`'s)" lines 1903–1937. |
| Hierarchical references in synthesizable RTL (`u_sub.internal_signal`) | Not portable across tools; tightly couples siblings; some tools fail to elaborate. | Quick debug taps. Add an explicit output port. | [V] — lowRISC §"Hierarchical references" lines 2619–2657. |
| `full_case` / `parallel_case` pragmas | Causes simulation/synthesis mismatch. Use `unique case` with a `default:` arm. | Forcing parallel-mux inference. | [V] — lowRISC §"Case Statements" lines 2160–2164 — *"Never use either the `full_case` or `parallel_case` pragmas."* |
| `tasks` in synthesizable RTL | Tasks may consume time; not equivalent to combinational helpers. | Reusing a procedural sequence. Use `function automatic` returning a packed type. | [V] — lowRISC §"Functions and Tasks" lines 2397–2398 — *"In synthesizable RTL the use of functions is allowed, provided they are declared `automatic`. Tasks should not be used."* |
| `casex` | Symmetric wildcard matches `X` in either expression or item, producing silent misses. | Quick "wildcard" decode. Use `case inside` (preferred) or `casez` (Verilog-2001 compat). | [V] — lowRISC §"Wildcards in case items" lines 2236–2253 — *"`casex` should not be used."* |
| `$display`, `$finish`, `$dumpvars`, `initial` blocks (except FPGA power-on register init) | Simulation-only. `initial` is partially supported by Quartus for memory init and register init values, but bundle uses explicit reset-handled init only. | Debug RTL. Move to testbench. | [V] — lowRISC §"Delay Modeling" / general convention; FPGACPU §"Initialization and Logic Values" lines 130–134 covers power-on register init exception. |

### 3.4 Width and signedness — non-negotiable discipline

Width discipline lives here because anti-patterns #5 and #6 (§7 below) originate here.

**Rule W-1.** [C] Every literal carries an explicit width and base. lowRISC publishes the rule directly:

```systemverilog
// references/raw/style/lowrisc_systemverilog_style.md:1634-1646 @ 2026-05-20
// good:
localparam logic [3:0] bar = 4'd4;

assign foo = 8'd2;

// bad:
localparam logic [3:0] bar = 4;

assign foo = 2;
```

Permitted exceptions (lowRISC, same section, lines 1648–1656): `1'b1` for an increment expression, `'0` for an automatically-correctly-sized zero, and integer literals assigned to integer-type variables (`int`, `byte`, etc. — which the bundle uses only at `parameter` scope, not in datapath).

**Rule W-2.** [C] Concatenation `{a, b, c}` is **unsigned** and has width equal to the sum of operand widths. If the target is narrower, the high bits are silently dropped. If the target is wider, the implicit zero-extension may not be what you want. Size each operand explicitly so the sum matches the target width. (See §7 anti-pattern #6.)

**Rule W-3.** [C] Signed arithmetic requires `logic signed` on every operand. Mixing one unsigned operand into a signed expression promotes the whole expression to unsigned and silently breaks negative-value handling. The cure is the `signed'(...)` cast:

```systemverilog
// references/raw/style/lowrisc_systemverilog_style.md:2319-2330 @ 2026-05-20
logic signed [7:0]  a;
logic               incr;
logic signed [15:0] sum1, sum2, sum3;
initial begin
  a = 8'sh80;                        // a = -128
  incr = 1'b1;
  sum1 = a + incr;                   // bad:  sum1 = 16'h0081 ( 129)
  sum2 = a + signed'({1'b0, incr});  // good: sum2 = 16'hFF81 (-127)
  sum3 = a + 8'sh01;                 // good: sum3 = sum2 (more straightforward)
end
```

**Rule W-4.** [V] Carry on addition/negation may be silently dropped on assignment to a same-width target, or made explicit with a size cast. lowRISC documents this as an allowable exception to width matching:

```systemverilog
// references/raw/style/lowrisc_systemverilog_style.md:1759-1768 @ 2026-05-20
logic [3:0] cnt_d, cnt_q;
assign cnt_d = cnt_q + 4'h1;

// Or you may explicitly express dropping the carry by using size casting.
assign cnt_d = 4'(cnt_q + 4'h1);
```

**Rule W-5.** [C] Do not slice the full width of a vector (`a[7:0]` of an 8-bit `a`). The redundant slice masks legitimate width-mismatch warnings the parser would otherwise emit. Partial-bit assignments (`a[7:1] = 7'd5;`) are fine; whole-width self-slices are not. (lowRISC §"Bit Slicing" lines 1729–1744.)

## 4. Sequencing & timing

The subset is mostly static; sequencing is owned by the neighbor docs. Three points specific to *why the subset chose `always_ff` and `always_comb`*:

**4.1 `always_ff` is a strict synthesis promise.** A generic `always @(posedge clk)` is a procedural block that *happens* to imply flops because of the edge sensitivity; the tool will accept any RHS expression including ones that would imply combinational fan-out or a latch. `always_ff` declares the intent: "this block infers flops; warn me if anything I write implies otherwise." Quartus and every modern simulator enforce that intent — multiple-driver violations and accidental latches inside an `always_ff` are flagged. (VerilogPro `systemverilog_always_comb_always_ff.html` §"SystemVerilog always_ff": *"variables written on the left-hand side of assignments within `always_ff`, including variables from contents of a called function, cannot be written by other processes. Also, it is recommended that software tools perform additional checks to ensure code within the procedure models flip-flop behaviour."*)

**4.2 `always_comb` adds a compile-time sensitivity-list check that `always @*` lacks.** `always @*` does not infer sensitivity for signals referenced inside a function called from the block — only the function's arguments. `always_comb` does. `always_comb` also executes once at time zero, forbids multiple processes writing the same LHS, and forbids blocking timing controls (`#`, `wait`, `fork...join`). The bundle uses `always_comb` to make these checks the synthesizer's, not the reviewer's. (VerilogPro `systemverilog_always_comb_always_ff.html` §"SystemVerilog always_comb" — bullet list at lines 290–294.)

**4.3 Inside an `always_comb`, blocking-assigned variables can be re-read in the same block** — that's how you decompose complex combinational logic into named intermediate values without inferring storage. But the *order* matters and matches sequential reading top-to-bottom; VerilogPro shows a sim/spec gotcha where re-reading a variable assigned later in the block gives the *previous* value because the LHS-assigned name is excluded from the implicit sensitivity list (lines 318–322, 326–330). The bundle's discipline: write blocking assignments top-down in a `_d`-style "next-value first" form, do not reuse a name as both LHS and later RHS in the same block unless the intent is the conventional default-then-override pattern (lowRISC §"Case Statements" lines 2199–2234). Full block-discipline mechanics live in [13-registers-and-combinational-blocks.md](13-registers-and-combinational-blocks.md).

## 5. Minimal working pattern

A registered counter with synchronous clear and enable, written in the bundle's canonical subset. Composed: FPGADesignElements `Register.v` provides the parameterized-width clock-enable-and-clear shape (`clock_enable`, `clear`, `WORD_WIDTH`, "last-assignment-wins" reset idiom); lowRISC SV style supplies `logic`, `always_ff`/`always_comb` separation, `typedef enum logic`, `_d`/`_q`/`_i` suffixes, explicit-width literals, and named parameters.

```systemverilog
// composite [I] — patterns drawn from:
//   references/projects/FPGADesignElements/Register.v:39-75 @ 2026-05-20
//   references/raw/style/lowrisc_systemverilog_style.md:1190-1205 @ 2026-05-20 (ports, suffixes)
//   references/raw/style/lowrisc_systemverilog_style.md:1241-1247 @ 2026-05-20 (typedef enum)
//   references/raw/style/lowrisc_systemverilog_style.md:1759-1768 @ 2026-05-20 (width-matched increment)
`default_nettype none

module counter_with_clear #(
  parameter int unsigned Width = 8
) (
  input  logic              clk_i,
  input  logic              rst_ni,
  input  logic              clear_i,
  input  logic              enable_i,
  output logic [Width-1:0]  count_o
);

  typedef enum logic [0:0] { MODE_HOLD, MODE_COUNT } mode_e;

  logic [Width-1:0] count_d, count_q;
  mode_e            mode;

  always_comb begin
    mode    = enable_i ? MODE_COUNT : MODE_HOLD;
    count_d = count_q;
    unique case (mode)
      MODE_COUNT: count_d = count_q + {{(Width-1){1'b0}}, 1'b1};
      MODE_HOLD:  count_d = count_q;
      default:    count_d = '0;
    endcase
    if (clear_i) count_d = {Width{1'b0}};
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) count_q <= {Width{1'b0}};
    else         count_q <= count_d;
  end

  assign count_o = count_q;

endmodule
```

The example uses every required subset feature: `logic` declarations everywhere, `typedef enum logic [N-1:0]` for the mode signal, paired `always_comb`/`always_ff` blocks, NBA in the sequential block and blocking in the combinational block, `parameter` width, explicit-width literals (`{Width{1'b0}}`, `1'b1`, `'0`), and `_i`/`_o`/`_ni`/`_d`/`_q` suffixes from lowRISC §"Suffixes" (lines 1148–1156). Async-asserted, sync-released reset wrapper construction is in [11-clocking-resets-and-cyclone-v-clock-networks.md](11-clocking-resets-and-cyclone-v-clock-networks.md).

## 6. Common variations across implementations

- **[O] lowRISC Comportable SV style** — strict `logic` + `always_ff`/`always_comb` separation, `_i`/`_o` port suffixes, `_ni` suffix for active-low reset, `_d`/`_q` for register input/output, named-port instantiation with `.port` shorthand, `unique case` with mandatory `default:`. This is the bundle's prescribed style. Canonical reset/pipeline shape:
  ```systemverilog
  // references/raw/style/lowrisc_systemverilog_style.md:1190-1200 @ 2026-05-20
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      valid_q  <= '0;
      valid_q2 <= '0;
    end else begin
      valid_q  <= valid_d;
      valid_q2 <= valid_q;
    end
  end
  ```

- **[O] FPGADesignElements style** (FPGACPU) — Verilog-2001, `reg`/`wire` rather than `logic`, single `always @(posedge clock)` with the "last-assignment-wins" reset idiom, no `_i`/`_o` suffixes, power-on `initial` for register init, no async reset (the project's `Register.v` argues async reset blocks retiming). Bundle reframes such examples in the canonical SV subset when cited elsewhere; the underlying rules (one driver per signal, blocking-in-comb / NBA-in-seq) transfer directly even though the keywords differ. Mark cross-cites of FPGADesignElements code as [V] in the bundle's voice. Canonical register-body shape:
  ```verilog
  // references/projects/FPGADesignElements/Register.v:65-73 @ 2026-05-20
  always @(posedge clock) begin
      if (clock_enable == 1'b1) begin
          data_out <= data_in;
      end
      if (clear == 1'b1) begin
          data_out <= RESET_VALUE;
      end
  end
  ```

- **[O] Alex Forencich verilog-axis style** — Verilog-2001, `reg`/`wire`, explicit synchronous active-high reset (`rst`, not `rst_n`), module-per-file convention, `$clog2` for derived widths, `_reg`/`_next` suffixes (separate combinational `_next` from registered `_reg`). Demonstrates the same single-driver / split-comb-and-seq discipline applied through a different naming convention. Header shape:
  ```verilog
  // references/projects/verilog-axis/rtl/arbiter.v:27-60 @ 2026-05-20
  `default_nettype none

  module arbiter #
  ( parameter PORTS = 4, /* ... */ )
  (
      input  wire                     clk,
      input  wire                     rst,
      input  wire [PORTS-1:0]         request,
      output wire [PORTS-1:0]         grant,
      output wire [$clog2(PORTS)-1:0] grant_encoded
  );

  reg [PORTS-1:0] grant_reg = 0, grant_next;
  reg [$clog2(PORTS)-1:0] grant_encoded_reg = 0, grant_encoded_next;
  ```

- **[O] Intel Recommended HDL Coding Styles (Quartus 18.1)** — Intel's own guide endorses `always_ff @(posedge clk)` and `always_comb` forms and recommends synchronous reset for Cyclone V. The local Quartus 18.1 HTML capture is an app-shell, so the live URL is the only usable cite: `https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/recommended-hdl-coding-styles`. Live URL only; no local capture worth excerpting.

## 7. Anti-patterns (mistakes that compile but break)

This doc owns the **full Symptom→Cause→Fix→Citation** treatment for anti-patterns **#5 (width/signedness mismatch on assignment)** and **#6 (implicit width truncation in concatenation)**. Mixed blocking/NBA (#2) is surfaced briefly and pointed to doc 13. `casex`/`casez` overlapping (#7) is referenced; doc 14 owns it.

### #5 — Width/signedness mismatch on assignment

- **Symptom:** Simulation matches synthesis on most inputs but produces silently wrong results for negative operands, large operands near the target width, or any case where one operand was unintentionally treated as unsigned. RTL lint emits "width mismatch" warnings (often hundreds, drowning the signal in noise); the bug surfaces only when negative inputs hit. In the canonical case, adding a 1-bit unsigned `incr` to a signed `[7:0] a` gives `+129` where you wanted `-127`.
- **Cause:** Either (a) assigning a wider expression to a narrower target so high bits drop, (b) mixing a `logic signed` operand with a plain `logic` operand without an explicit `signed'(...)` cast — Verilog implicitly casts the whole expression to unsigned, or (c) using an unsized literal (`0`, `'0`, `1`) where the target width is not parameter-determined.
- **Fix:** Declare every literal with explicit width and base (`8'h00`, not `0`); declare every signal that participates in signed arithmetic as `logic signed [W-1:0]`; on every crossing of signed↔unsigned use `signed'(...)` or `unsigned'(...)`. See §3.4 rules W-1 and W-3 and the lowRISC `signed'` example excerpted there. Where carry on addition is expected and acceptable, document it with a size cast: `assign cnt_d = 4'(cnt_q + 4'h1);`
- **Citation:** lowRISC §"Always be explicit about the widths of number literals" lines 1626–1656 (`references/raw/style/lowrisc_systemverilog_style.md`) and §"Signed Arithmetic" lines 2304–2334 (same file). Reinforced by FPGACPU §"Bit Widths" lines 198–233 (`references/raw/fpgacpu/verilog_coding_standard.html`).

### #6 — Implicit width truncation in concatenation

- **Symptom:** `{a, b, c}` assigned to a target that doesn't match the sum of operand widths silently drops or zero-extends bits. Simulation may match synthesis (both truncate the same way), so the bug looks like a "logic error" further downstream when the missing bits change the meaning of a header field, opcode, or pointer.
- **Cause:** The concatenation operator returns an unsigned vector whose width equals the sum of operand widths. lowRISC: *"It is recommended to use explicit widths, rather than relying on Verilog's implicit zero-extension and truncation operations, whenever practical."* (lines 1660–1661) Unsized literals embedded in concatenations (`{1'b0, foo, 0}`) interact with this rule and produce 32-bit-wide phantom fields per Verilog's integer-promotion rules.
- **Fix:** Size every concatenation operand explicitly (`{4'd0, sixteen_bit_word}` to fill a 20-bit target). Match the source-side width to the target width *exactly*; do not rely on implicit zero-extension at port connections either. lowRISC example:
  ```systemverilog
  // references/raw/style/lowrisc_systemverilog_style.md:1666-1677 @ 2026-05-20
  // good:
  my_module i_module (
    .thirty_two_bit_input({16'd0, sixteen_bit_word})
  );

  // bad:
  my_module i_module (
    // Incorrectly implicitly extends from 16 bit to 32 bit
    .thirty_two_bit_input(sixteen_bit_word)
  );
  ```
  When the natural width matches a power-of-two pad-up convenience (e.g., a 12-bit decode in a 16-bit mux index), express the pad explicitly (`{4'b0000, 12'b1010_1111_0000}`) — see the lowRISC pad-to-power-of-two example (`references/raw/style/lowrisc_systemverilog_style.md:2110-2118 @ 2026-05-20`).
- **Citation:** lowRISC §"Port connections on module instances must always match widths correctly" lines 1658–1677; lowRISC §"Bit Slicing" lines 1721–1745; lowRISC §"Handling Width Overflow" lines 1747–1768 — all in `references/raw/style/lowrisc_systemverilog_style.md`. Reinforced by FPGACPU §"Concatenations" lines 235–263 (`references/raw/fpgacpu/verilog_coding_standard.html`).

### #2 — Mixed blocking and nonblocking assignments (briefly; full treatment in doc 13)

- **Symptom:** Sim/synth mismatch where some simulators schedule blocking and nonblocking assignments in the same block differently from what synthesis produces.
- **Rule (one-liner):** `always_ff` → NBA (`<=`) only; `always_comb` → blocking (`=`) only. Never mix.
- **Citation:** lowRISC §"Blocking and Non-blocking Assignments" lines 1770–1783.
- **Defer to:** [13-registers-and-combinational-blocks.md](13-registers-and-combinational-blocks.md) for the full Symptom→Cause→Fix→Citation treatment, including the "blocking-assigned later, registered separately" decomposition pattern and the Quartus warning class that catches it.

### #7 — `casex`/`casez` overlapping (briefly; full treatment in doc 14)

`case` and `unique case` appear in Table A. `casex` is in Table B (banned). `casez` is permitted but its wildcard semantics make overlapping case-item patterns dangerous (the first textual match wins, which is rarely what you want for one-hot decoders). Full FSM-level treatment in [14-finite-state-machines.md](14-finite-state-machines.md). lowRISC §"Wildcards in case items" lines 2236–2253 establishes the preference order: `case` > `case inside` > `casez` > (never) `casex`.

### Additional subset-specific anti-pattern

### #12-A — `always_comb` with self-referential variable read

- **Symptom:** Code review and tool both pass, but a re-read of a variable inside the same `always_comb` block produces stale values. Behaviour differs between simulators (some re-trigger, some do not — both LRM-compliant).
- **Cause:** SystemVerilog excludes LHS-assigned names inside an `always_comb` block from its own implicit sensitivity list. Writing `c = b; b = a;` does **not** propagate `a → b → c` in the same time step; `c` gets the *previous* value of `b`.
- **Fix:** Inside `always_comb`, write top-down so any RHS reference appears before the LHS assignment of that name. Use the explicit `_d`/`_q` discipline so a signal that is assigned in a comb block (`_d`) is never the same name as one read inside that block from a prior cycle (`_q`).
- **Citation:** VerilogPro `systemverilog_always_comb_always_ff.html` §"Update: always_comb coding style to watch out for" lines 302–330.

## 8. Verification

The subset's main verification surface is the synthesis tool itself. The bundle expects Quartus warnings of the following classes to be treated as errors (detailed report-reading lives in [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md)):

- **Implicit latch inference** — Quartus emits an "inferred latch" warning when an `always_comb` (or `always @*`) leaves an output undriven on some path. The bundle's `always_comb` discipline (default assignments at the top of the block, mandatory `default:` arm in every `case`) makes this warning impossible in correct code; if it appears, the block has missing coverage. lowRISC §"Case Statements" lines 2188–2197 names the mechanism.
- **Multiple drivers** — Quartus errors at synthesis time if two `always` blocks or two `assign` statements write the same signal. The bundle's one-driver-per-signal rule (§2) makes this a hard stop.
- **Width-mismatch warnings** — Quartus emits "Verilog HDL or VHDL warning ... signal will be truncated" or "...zero-extended" when source and sink widths differ on an assignment. Per §3.4 W-1 and W-2, every such warning is a real bug; the bundle requires zero of them.
- **`always_ff` non-flop inference** — if any RHS expression inside an `always_ff` implies non-register behavior, Quartus emits a synthesis violation. The bundle uses this to catch accidental combinational assignments slipped into a sequential block.

There is no separate lint tool prescribed in the corpus for this doc beyond the synthesizer's checks; do not invent one.

## 9. Provenance footer

- `references/raw/style/lowrisc_systemverilog_style.md @ 2026-05-20` — used for §2 (every contract rule); §3 Table A (every row's citation); §3 Table B (`defparam`, `always_latch`, unsized literals, `casex`, `full_case`/`parallel_case`, tasks, X-literals, hierarchical refs, tri-state, struct examples); §3 verbatim excerpts (3.1, 3.4); §5 minimal pattern (composed); §6 (lowRISC variant); §7 anti-patterns #5, #6, #2 brief, #7 brief; §8 latch-inference mechanism.
- `references/raw/verilogpro/systemverilog_always_comb_always_ff.html @ 2026-05-20` — used for §2 (`always_ff`/`always_comb` semantics rationale); §3 Table A (`always_ff` / `always_comb` rows); §4 (sensitivity-list and sim/spec gotcha); §7 anti-pattern #12-A.
- `references/raw/verilogpro/verilog_always_block.html @ 2026-05-20` — referenced for legacy-Verilog contrast in §4 framing (Verilog-2001 `always @(posedge clk)` baseline against which `always_ff` is the strict synthesis promise).
- `references/raw/fpgacpu/verilog_coding_standard.html @ 2026-05-20` — used for §2 (one-driver-per-signal, `` `default_nettype none ``); §3 Table A (`assign`, `` `default_nettype none `` rows); §3 Table B (unsized-literal reinforcement, tri-state reinforcement, `initial`-as-register-init exception); §7 anti-patterns #5 and #6 reinforcement.
- `references/projects/FPGADesignElements/Register.v @ 2026-05-20` — used for §5 (composite minimal pattern: parameterized-width clock-enable-and-clear register shape, "last-assignment-wins" reset idiom); §6 (FPGADesignElements [O] variant).
- `references/projects/verilog-axis/rtl/arbiter.v @ 2026-05-20` — used for §6 (verilog-axis [O] variant: Verilog-2001 with synchronous reset, `_reg`/`_next` naming).
- `https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/recommended-hdl-coding-styles` — used for §6 (Intel Recommended HDL Coding Styles [O] variant). **Live URL, no local capture.** The local file `references/raw/intel/quartus_standard_hdl_design_guidelines.html` is an app-shell (71 lines, no body) per `references/MANIFEST.md`; not excerptable.
- `https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/register-and-latch-coding-guidelines` — referenced for "what Quartus actually infers" framing only; full register/latch coding mechanics belong to [13-registers-and-combinational-blocks.md](13-registers-and-combinational-blocks.md). **Live URL, no local capture.** The local file `references/raw/intel/quartus_standard_register_latch_guidelines.html` is an app-shell per MANIFEST.
