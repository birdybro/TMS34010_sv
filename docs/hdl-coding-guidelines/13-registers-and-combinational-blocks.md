# Registers and Combinational Blocks

> Bundle version: 2026-05-19
> Pinned commits: lowrisc-style-guides @ 735d911, FPGADesignElements @ 2450a54, references/MANIFEST.md collected 2026-05-20
> Load with: [12-synthesizable-sv-subset.md](12-synthesizable-sv-subset.md), [14-finite-state-machines.md](14-finite-state-machines.md), [15-pipelines-and-latency-thinking.md](15-pipelines-and-latency-thinking.md), [16-resource-and-state-economy.md](16-resource-and-state-economy.md)
> Status mix: heavy [C] (synthesis-mandated discipline: single-driver, NBA-in-seq / blocking-in-comb, latch avoidance), some [V] (style choices: reset-first ordering, secondary-control pattern shape, `_q`/`_d` naming), a few [O] (lowRISC vs FPGADesignElements vs Cummings layout differences), one [I] (the monolithic counterexample in §3.4 / §7 is synthesized for illustration).

## 1. Purpose & one-line summary

Every `always` block describes one logical concern; the block kind (`always_ff` vs `always_comb`) and the assignment kind (`<=` vs `=`) together determine the hardware. This doc supplies the register and combinational-block discipline rules an agent applies to every block it writes for the Cyclone V (`5CSEBA6U23I7`) target: one driver per signal, blocking-in-comb / nonblocking-in-seq, defaults to prevent latches, secondary control signals shaped so Quartus infers the flop's full feature set, and — load-bearing — one logical concern per block. Reset construction (async-assert/sync-release), FSM coding patterns, pipeline-register discipline, and Quartus report mechanics are deferred to the docs named in `Load with:`.

## 2. The contract (must-obey)

- [C] Every signal has exactly one driver across all `always` blocks and continuous assignments; a wire driven by two sources synthesizes to a multi-driver error or `X` in simulation. Source: FPGACPU verilog coding standard "Initialization and Logic Values" (`references/raw/fpgacpu/verilog_coding_standard.html:136-143`) and Cummings, *Nonblocking Assignments in Verilog Synthesis* (`http://www.sunburst-design.com/papers/CummingsSNUG2000SJ_NBA.pdf`, live URL — no local capture).
- [C] Inside `always_ff` (or `always @(posedge clk ...)`), every assignment is nonblocking (`<=`). Source: Cummings FSM `references/extracted_text/methodology/CummingsSNUG1998SJ_FSM.txt:192-197` ("Sequential Always Block — Guideline: only use Verilog nonblocking assignments in the sequential always block") and lowRISC SV style `references/raw/style/lowrisc_systemverilog_style.md:1772-1780`.
- [C] Inside `always_comb` (or `always @*`), every assignment is blocking (`=`). Source: Cummings FSM `references/extracted_text/methodology/CummingsSNUG1998SJ_FSM.txt:247` ("Guideline: only use Verilog blocking assignments in combinational always blocks") and lowRISC SV style `references/raw/style/lowrisc_systemverilog_style.md:2150`.
- [C] Never mix blocking and nonblocking assignments in the same `always` block. Source: lowRISC SV style `references/raw/style/lowrisc_systemverilog_style.md:1775` and FPGACPU verilog coding standard `references/raw/fpgacpu/verilog_coding_standard.html:470-472`.
- [C] Every signal assigned inside an `always_comb` block is assigned on every possible execution path; otherwise a latch is inferred. Source: lowRISC SV style `references/raw/style/lowrisc_systemverilog_style.md:2189-2197` ("a `default:` statement is always included in order to avoid accidental inference of latches"); Intel *Register and Latch Coding Guidelines* (`https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/register-and-latch-coding-guidelines`, live URL — app-shell local capture).
- [C] Combinational outputs are produced from defaults at the top of the block plus path-specific overrides; defaults appear immediately after `begin`. Source: lowRISC SV style `references/raw/style/lowrisc_systemverilog_style.md:2208-2233` and Intel *Recommended HDL Coding Styles* (`https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/recommended-hdl-coding-styles`, live URL).
- [C] One logical concern per `always` block. A block holds one state element (or one tightly coupled set driving a single FSM/datapath substructure); reset, increment, load, sample, and output-mux concerns each get their own block. Source: lowRISC SV style `references/raw/style/lowrisc_systemverilog_style.md:1897-1901` and Cummings FSM `references/extracted_text/methodology/CummingsSNUG1998SJ_FSM.txt:181-247` (two-always-block partition).
- [C] Combinational loops are forbidden in synthesizable RTL; the output of a pure-combinational cone may not appear in its own RHS. Source: Intel *Recommended HDL Coding Styles* (`https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/recommended-hdl-coding-styles`, live URL) and FPGACPU verilog coding standard `references/raw/fpgacpu/verilog_coding_standard.html:438-439`.
- [V] Secondary control signals (clock enable, synchronous clear, asynchronous clear, synchronous load) are expressed using the canonical `if (...) q <= ...;` patterns that Intel inference recognises so the Cyclone V flop's built-in features are engaged rather than synthesised as extra LUT logic. Source: Intel *Register and Latch Coding Guidelines* (`https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/register-and-latch-coding-guidelines`, live URL).
- [V] The reset (or reset-like) assignment is the first conditional inside the `always_ff` block — the canonical `if (!rst_n) q <= RESET; else q <= ...;` shape — so that priority is structural rather than implicit. Source: lowRISC SV style `references/raw/style/lowrisc_systemverilog_style.md:1830-1836` and FPGADesignElements `references/projects/FPGADesignElements/Register_areset.v:89-101`.
- [V] Sequential blocks ideally contain only a register instantiation with at most a load enable or an increment; complex next-state work belongs in a separate `always_comb` block. Source: lowRISC SV style `references/raw/style/lowrisc_systemverilog_style.md:1897-1901`.

## 3. Constructs / signals / API reference

### 3.1 The canonical `always_ff` block

The canonical synchronous-reset (or async-assert) sequential block: reset-first conditional, NBA-only body, one register's worth of state per block. The verbatim Verilog-2001 reference is FPGADesignElements `Register.v` (synchronous-clear flavour); the SV reframing follows lowRISC's `_q`/`_d` naming. (Reset *construction* — sync-release synchroniser, polarity, fanout — is doc 11.)

```verilog
// references/projects/FPGADesignElements/Register.v:65-73 @ commit 2450a54
    always @(posedge clock) begin
        if (clock_enable == 1'b1) begin
            data_out <= data_in;
        end

        if (clear == 1'b1) begin
            data_out <= RESET_VALUE;
        end
    end
```

The above relies on the "last-assignment-wins" idiom for synchronous clear: both `if` statements may fire in the same edge, and the standard guarantees the second NBA supersedes the first on the bit it touches. The async-reset flavour cannot use that idiom — it requires the structural `if (areset) ... else ...` priority:

```verilog
// references/projects/FPGADesignElements/Register_areset.v:89-102 @ commit 2450a54
    always @(posedge clock, posedge areset) begin
        if (areset == 1'b1) begin
            data_out <= RESET_VALUE;
        end
        else begin
            if (clock_enable == 1'b1) begin
                data_out <= data_in;
            end

            if (clear == 1'b1) begin
                data_out <= RESET_VALUE;
            end
        end
    end
```

Reframed in the SV subset (active-low async reset, `_q`/`_d` naming) the same shape is the lowRISC canonical form:

```systemverilog
// references/raw/style/lowrisc_systemverilog_style.md:1830-1836 @ commit 735d911
always_ff @(posedge clk or negedge rst_ni) begin
  if (!rst_ni) begin
    foo_q <= 8'hab;
  end else if (foo_en) begin
    foo_q <= foo_d;
  end
end
```

The sync-reset SV form drops the second event term:

```systemverilog
// constructed from lowrisc_systemverilog_style.md sync-reset pattern @ 2026-05-19
always_ff @(posedge clk) begin
  if (rst) begin
    foo_q <= 8'hab;
  end else if (foo_en) begin
    foo_q <= foo_d;
  end
end
```

| Construct | Type | Meaning | Driven by | Drives |
|---|---|---|---|---|
| `always_ff @(posedge clk)` | SV procedural block | Synchronous-reset sequential block. Body executes on rising `clk` only. | Source clock | Registers assigned via `<=` |
| `always_ff @(posedge clk or negedge rst_ni)` | SV procedural block | Async-assert / async-release flop (or async-assert sync-release with external reset synchroniser per doc 11). | Source clock, reset deassertion | Same |
| `<=` (nonblocking) | Assignment | Schedules RHS-read-now, LHS-update-end-of-step. The only legal assignment inside `always_ff`. | RHS expression at edge | LHS register at end of delta cycle |
| `_q` suffix (lowRISC) | Naming convention | Current/registered value of a flop. | The flop | Downstream logic |
| `_d` suffix (lowRISC) | Naming convention | Next-state input feeding the flop. | Upstream `always_comb` | The flop's `<=` RHS |
| `RESET_VALUE` | localparam | Value the register assumes on reset. | Module parameter | Initial/reset assignment |

### 3.2 The canonical `always_comb` block

Combinational blocks assign defaults at the top, then override per path. The "every output assigned on every path" property is enforced either by exhaustive `if`/`case` arms (each writing every output) or by the cheaper top-of-block default-assignment idiom shown below.

```systemverilog
// references/raw/style/lowrisc_systemverilog_style.md:2208-2234 @ commit 735d911
always_comb begin
  // common default assignments
  state_d = state_q;
  outa = 1'b0;
  outb = 1'b0;
  outc = 1'b0;

  unique case (state_q)
    Idle: begin
      state_d = Work;
      outa = in0;
    end
    Work: begin
      state_d = Wait;
      outb = in1;
    end
    Wait: begin
      state_d = Idle;
      outc = in2;
    end
    // always include a default case
    // empty default permissible due to defaults before case block
    default: ;
  endcase
end
```

The defaults appearing once at the top mean each `case` arm only mentions the outputs it changes; nothing the arm omits floats, so no latch is inferred. `unique case` adds a simulation-time assertion that the cases are mutually exclusive without changing synthesis behaviour. Compared to plain Verilog `always @*`, `always_comb` adds three guarantees the synthesis-mandated discipline depends on:

```html
<!-- references/raw/verilogpro/systemverilog_always_comb_always_ff.html:Update: always_comb @ 2022-04 -->
- always_comb automatically executes once at time zero
- Variables on the left-hand side of assignments within an always_comb procedure
  cannot be written to by any other processes
- Statements in an always_comb cannot include those that block, have blocking
  timing or event controls, or fork-join statements
```

The middle bullet is how SV enforces the single-driver rule inside the procedural construct: writing the same `_d` from two `always_comb` blocks is a compile-time error rather than a silent multi-driver that simulators tolerate differently.

| Construct | Type | Meaning | Driven by | Drives |
|---|---|---|---|---|
| `always_comb` | SV procedural block | Combinational logic. Implicit sensitivity = RHS signals. Tool warns on latch inference. | RHS signal changes | Combinational outputs assigned via `=` |
| `=` (blocking) | Assignment | Executes immediately; later statements see the new value. The only legal assignment inside `always_comb`. | RHS expression | LHS net or var |
| Default assignment | Statement at top of `always_comb` | Establishes a baseline value for every output the block can write. Prevents latch inference if a branch omits an output. | n/a | Combinational outputs |
| `unique case` | SV case-modifier | Asserts (sim) that at most one case-item matches. Does not change synthesis. | n/a | n/a |
| `default:` (in case) | Case arm | Catch-all that prevents latch inference when no defaults precede the case. | n/a | Combinational outputs |

### 3.3 Secondary control signals (Intel inference hooks)

A Cyclone V Adaptive Logic Module (ALM) flop has built-in support for clock enable, synchronous clear, asynchronous clear, and synchronous load. To engage these on-cell features instead of building them out of LUT fabric, write the canonical RTL pattern Intel's inference recognises. The patterns below are the ones Intel's *Register and Latch Coding Guidelines* names, restated in the SV subset.

| Feature | Canonical SV pattern | Effect on inferred flop |
|---|---|---|
| Clock enable | `if (en) q <= d;` | Engages the ALM flop's CE input — no extra LUT mux. |
| Synchronous clear | `if (clr_s) q <= '0; else q <= d;` | Engages the flop's SCLR input — combined with CE if both are present. |
| Asynchronous clear | `always_ff @(posedge clk or posedge clr_a) if (clr_a) q <= '0; else q <= d;` | Engages the flop's ACLR input — exclusive of certain other secondaries; see Intel guidance. |
| Synchronous load | `if (load) q <= d_in; else q <= q_next;` | Engages the flop's SLOAD path — preserves CE/SCLR availability when patterned cleanly. |

Source for the patterns and the inference behaviour: Intel *Register and Latch Coding Guidelines* (`https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/register-and-latch-coding-guidelines`, live URL — local capture is an app-shell). [V] for the patterns themselves; the Cyclone V ALM cell features they engage are documented in the Cyclone V Device Handbook.

Mixing more than one *asynchronous* secondary control on the same flop (e.g., async preset and async clear together) typically defeats inference and forces fabric build-out; polarity, fanout, and the async-assert / sync-release combination are doc 11's concern.

### 3.4 One-concern-per-block discipline

The rule: write one `always_ff` per register (or per tightly coupled register group representing a single state element), one `always_comb` per combinational concern (next-state, output decode, address generation, etc.). The lowRISC style guide states it directly:

```markdown
// references/raw/style/lowrisc_systemverilog_style.md:1897-1901 @ commit 735d911
Keep work in sequential blocks simple. If a sequential block becomes
sufficiently complicated, consider splitting the combinational logic into a
separate combinational (`always_comb`) block. Ideally, sequential blocks should
contain only a register instantiation, with perhaps a load enable or an
increment.
```

A counterexample (the monolithic pattern this rule prohibits — see §7 #1 for the full Symptom→Cause→Fix treatment):

```systemverilog
// [I] synthesized for illustration; not from any corpus source — 2026-05-19
// BAD: one always block, every concern bundled
always_ff @(posedge clk) begin
  if (rst) begin
    counter_q <= '0;
    accum_q   <= '0;
    state_q   <= S_IDLE;
    out_q     <= '0;
  end else begin
    // counter concern
    if (count_en) counter_q <= counter_q + 1'b1;
    // accumulator concern
    if (sample_v) accum_q <= accum_q + sample_d;
    // FSM next-state concern
    case (state_q)
      S_IDLE: if (start) state_q <= S_RUN;
      S_RUN:  if (counter_q == LIMIT) state_q <= S_DONE;
      S_DONE: state_q <= S_IDLE;
      default: state_q <= S_IDLE;
    endcase
    // output mux concern
    case (sel)
      2'd0: out_q <= counter_q[7:0];
      2'd1: out_q <= accum_q[7:0];
      2'd2: out_q <= {6'd0, state_q};
      default: out_q <= '0;
    endcase
  end
end
```

The refactor: one `always_ff` per concern, with `always_comb` blocks computing the per-cycle decisions:

```systemverilog
// [I] synthesized for illustration; the refactor of the block above — 2026-05-19
// GOOD: one block per logical concern
always_ff @(posedge clk) begin
  if (rst)              counter_q <= '0;
  else if (count_en)    counter_q <= counter_q + 1'b1;
end

always_ff @(posedge clk) begin
  if (rst)              accum_q <= '0;
  else if (sample_v)    accum_q <= accum_q + sample_d;
end

always_ff @(posedge clk) begin
  if (rst) state_q <= S_IDLE;
  else     state_q <= state_d;
end

always_comb begin
  state_d = state_q;
  unique case (state_q)
    S_IDLE: if (start) state_d = S_RUN;
    S_RUN:  if (counter_q == LIMIT) state_d = S_DONE;
    S_DONE: state_d = S_IDLE;
    default: state_d = S_IDLE;
  endcase
end

always_comb begin
  out_d = '0;
  unique case (sel)
    2'd0: out_d = counter_q[7:0];
    2'd1: out_d = accum_q[7:0];
    2'd2: out_d = {6'd0, state_q};
    default: out_d = '0;
  endcase
end

always_ff @(posedge clk) begin
  if (rst) out_q <= '0;
  else     out_q <= out_d;
end
```

| Pattern | Counts as one concern? | Notes |
|---|---|---|
| Single register + its enable/clear/load | Yes | Canonical `always_ff` shape; §3.1. |
| FSM state register | Yes | One `always_ff` for the state vector; partner `always_comb` for next-state (§3.2). |
| Pipeline stage (multiple flops, same valid) | Yes (per stage) | Per doc 15; valid-follows-data lives at the stage boundary. |
| "Every register in the module" | No | This is the monolithic pattern §7 #1 prohibits. |
| "FSM + datapath + output mux" | No | Three concerns at least; split each. |

## 4. Sequencing & timing

The discipline rules exist because of two specific scheduling semantics:

- `always_ff` evaluates all RHS expressions at the active clock edge, then schedules NBA updates that take effect after all RHS reads in the same delta cycle. In Cummings's "two-region" model, the RHS-read region for every clocked block in the design runs before any LHS-update region. This is *why* nonblocking-in-seq is mandatory: it produces the register-swap semantics (`a <= b; b <= a;` swaps cleanly in hardware) that match a real flop. Source: Cummings, *Nonblocking Assignments in Verilog Synthesis* (`http://www.sunburst-design.com/papers/CummingsSNUG2000SJ_NBA.pdf`, live URL — no local capture).
- `always_comb` re-evaluates whenever any RHS signal changes; statements run in source order with blocking assignments so each subsequent line sees the latest value of variables written above it. The result is still combinational: there is no clock, no edge, no stored state — but the body reads as straight-line dependency order. This is *why* blocking-in-comb is mandatory: blocking matches the data-flow semantics the synthesised LUT cone implements. Source: VerilogPro *Verilog Always Block* (`references/raw/verilogpro/verilog_always_block.html:Modeling Combinational Logic @ 2022-04`).

The NBA register-swap sequence, for the canonical `a <= b; b <= a;` example:

```
                t = T (clk rising edge)
                |
RHS reads:      a_rhs = a   b_rhs = b      (all blocks' RHS computed)
                |
LHS updates:    a <= b_rhs  b <= a_rhs     (all blocks' NBA scheduled, then applied)
                |
                t = T + delta : a == old_b, b == old_a   (clean swap)
```

If `=` were used instead, the first line would update `a` to `b` immediately, and the second line would then write the *new* `a` (i.e. `b`) into `b`, losing the swap. That is the simulation race the discipline prevents.

Per-cycle / per-protocol timing diagrams for the secondary control signals (CE / SCLR / ACLR / SLOAD) and for reset deassertion windows belong to doc 11 (reset/clock) and doc 41 (Quartus reports / setup-hold).

## 5. Minimal working pattern

An 8-bit register with clock enable, synchronous clear, and synchronous load, written as one `always_ff` block in the canonical SV subset. The structure follows FPGADesignElements `Register.v` (`references/projects/FPGADesignElements/Register.v:65-73 @ commit 2450a54`) reframed with explicit priority (reset → clear → load → enable):

```systemverilog
// [I] composite: structure from FPGADesignElements Register.v:65-73 @ 2450a54
//                 reframed in SV subset per lowrisc_systemverilog_style.md:1830-1836 @ 735d911
module register_8b (
  input  logic       clk,
  input  logic       rst,        // synchronous reset
  input  logic       clear,      // synchronous clear to zero
  input  logic       load,       // synchronous parallel load
  input  logic       enable,     // clock enable
  input  logic [7:0] load_data,
  input  logic [7:0] next_data,
  output logic [7:0] q
);

  always_ff @(posedge clk) begin
    if (rst)        q <= 8'h00;          // priority 1: reset
    else if (clear) q <= 8'h00;          // priority 2: sync clear
    else if (load)  q <= load_data;      // priority 3: sync load
    else if (enable) q <= next_data;     // priority 4: clock enable
    // implicit else: q holds (last-assignment-wins / no-write hold)
  end

endmodule
```

This is the working pattern. Note: it is one `always_ff` block, holding one register, with the reset-first conditional and only NBA assignments — every rule from §2 visible in seventeen lines.

## 6. Common variations across implementations

- [O] **lowRISC SV style** (`references/raw/style/lowrisc_systemverilog_style.md:1830-1836, 2839-2885 @ commit 735d911`): `always_ff @(posedge clk or negedge rst_ni)` with active-low async reset; sequential and combinational blocks always separated; `_q`/`_d` suffix convention; states declared as `typedef enum`; FSM is always two blocks (one `always_comb` for next-state-plus-outputs, one `always_ff` for the state register).
- [O] **FPGADesignElements style** (`references/projects/FPGADesignElements/Register.v:39-75 @ commit 2450a54`, `Register_areset.v:51-104 @ commit 2450a54`): Verilog-2001 with synchronous reset as the default *and a separate module* (`Register_areset`) for async-reset cases; one `always` block per primitive; `data_out`/`data_in` naming; relies on the "last-assignment-wins" idiom for sync clear (two `if` blocks at the same level, second wins on overlap); `initial` block sets power-on value; `` `default_nettype none `` at top of every file.
- [O] **Cummings FSM-paper two-block idiom** (`references/extracted_text/methodology/CummingsSNUG1998SJ_FSM.txt:181-265`): one sequential `always @(posedge clk or posedge rst)` for the state register (only `state <= next;` on the non-reset path), and one combinational `always @(state or ...)` for next-state assignment with a default `next = 3'bx;` (or `next = state;`) at the top. The block-discipline split is the relevant detail here; full FSM coding patterns are doc 14.
- [O] **VerilogPro classic Verilog-2001** (`references/raw/verilogpro/verilog_always_block.html:349-353 @ 2022-04`): minimal flop pattern `always @(posedge clk or negedge rst_n) if (!rst_n) q <= 1'b0; else q <= d;` with the reset on the sensitivity list; two separate flop blocks preferred over one combined block when no shared logic exists.

Not used in this bundle: verbose one-hot encoded state vectors with `// synopsys full_case parallel_case` pragmas (Cummings FSM PDF discusses; lowRISC explicitly forbids `full_case`/`parallel_case` — see `references/raw/style/lowrisc_systemverilog_style.md:2163-2164`).

## 7. Anti-patterns (mistakes that compile but break)

### #1 Monolithic `always` block

- **Symptom:** A single `always @(posedge clk)` block of 50–500 lines bundles reset, every register update, FSM next-state, and one or more output muxes into one cascade. Bugs are correlated — a typo in one branch corrupts an unrelated register. fmax becomes opaque because the synthesiser's hands are tied around the whole construct. Code review degenerates into reverse-engineering a state diagram from nested `if`/`case`. Adding a sixth concern to a five-concern block reliably introduces a regression in one of the existing five.
- **Cause:** Writing the design as if it were one sequential program. The block "feels" like `main()` and accretes responsibilities. A second contributing cause: starting from a textbook two-line flop pattern, growing it concern by concern, and never pausing to refactor when the third concern arrives.
- **Fix:** Refactor into one block per logical concern. Concretely: one `always_ff` per register (or per tightly coupled register group representing a single state element — e.g., the in-flight valid bits of a pipeline stage); one `always_comb` per next-state decoder, output decoder, address generator, or shared combinational computation. Use `_q`/`_d` naming to make the wire between the combinational decision and the register storage explicit. The refactor is mechanical: list the registers in the monolith, give each its own `always_ff`, then lift each `case`/`if` cascade that was computing a next-value into its own `always_comb` driving the matching `_d`. The transformation is shown in §3.4 (counterexample and refactor); the minimum-working register lives in §5; the FSM-specific application of the same rule is doc 14.
- **Citation:**
  - lowRISC SV style: `references/raw/style/lowrisc_systemverilog_style.md:1897-1901 @ commit 735d911` ("Keep work in sequential blocks simple. If a sequential block becomes sufficiently complicated, consider splitting the combinational logic into a separate combinational (`always_comb`) block. Ideally, sequential blocks should contain only a register instantiation, with perhaps a load enable or an increment.")
  - lowRISC SV style: `references/raw/style/lowrisc_systemverilog_style.md:2838-2885 @ commit 735d911` (FSMs "be implemented with two process blocks: a combinational block and a clocked block"; "No logic except for reset should be performed in this process").
  - Cummings, *State Machine Coding Styles for Synthesis*: `references/extracted_text/methodology/CummingsSNUG1998SJ_FSM.txt:181-247` — "Two-Always Block State Machine" section, separately specifying the sequential always block (NBA-only state register) and the combinational always block (default next-state assignment + `case`).
  - FPGACPU verilog coding standard: `references/raw/fpgacpu/verilog_coding_standard.html:678-707` — "Separate your FSM from your data processing… don't place the state and data processing logic together into a single large `case` statement, with one case per FSM state, and nested if/else statements inside each case to handle the input/output control signals."

The counterexample / refactor pair in §3.4 is constructed for illustration ([I]); the citations above establish the *rule* the counterexample violates, but neither lowRISC nor Cummings published a verbatim monolithic block to quote.

### #2 Mixed blocking and nonblocking assignments in one block

- **Symptom:** Simulation race conditions visible as run-to-run nondeterminism on the same testbench; sim/synth mismatch where a register appears to advance two states in one cycle in simulation but only one in hardware (or vice versa); signals "jumping" registers between simulator runs.
- **Cause:** Using `=` and `<=` in the same `always` block. The simulator may interpret some of the blocking assignments as taking effect in a different simulation event than the nonblocking assignments; what looks like a single delta cycle in source becomes two scheduled regions. lowRISC summarises this as "potentially leading to total protonic reversal. That's bad."
- **Fix:** `always_ff` uses only `<=`; `always_comb` uses only `=`. If you need to compute something with the sequential ordering of blocking assignments before registering it, put the blocking sequence in an `always_comb` block writing `_d` signals, and register the result in an `always_ff` block doing only `q <= d`.
- **Citation:**
  - Cummings, *Nonblocking Assignments in Verilog Synthesis, Coding Styles That Kill!*: `http://www.sunburst-design.com/papers/CummingsSNUG2000SJ_NBA.pdf` (live URL — no local capture; local file is a fetch-failure stub; Phase-4 verification will mark this UNREADABLE).
  - lowRISC SV style: `references/raw/style/lowrisc_systemverilog_style.md:1812-1816 @ commit 735d911` ("Designs that mix blocking and non-blocking assignments for registers simulate incorrectly because some simulators process some of the blocking assignments in an always block as occurring in a separate simulation event as the non-blocking assignment.")
  - FPGACPU verilog coding standard: `references/raw/fpgacpu/verilog_coding_standard.html:470-472 @ 2026-05-20` ("Do not mix blocking and non-blocking assignments within an always block.").

### #3 Combinational feedback loop

- **Symptom:** Quartus Synthesis report logs `combinational loop` on the offending node. If the tool tolerates the loop (some pure-comb paths self-stabilise), the output glitches at simulation time and settles to an unintended value in hardware, with timing analysis reporting `(loop)` on the worst path so no real fmax number is produced. In `always_comb` form, the LRM-mandated single-driver rule may produce a compile error rather than a warning.
- **Cause:** A pure-combinational signal appears in its own RHS cone — either directly (`assign x = x | y;`) or through a chain of combinational logic that closes back on itself. Common sub-cases: a default assignment that omits a self-update so the LHS appears on the RHS of a downstream expression; an output of an `always_comb` block fed back into the same block; a wire chain assembled across modules where the loop crosses a hierarchy boundary.
- **Fix:** Insert a register on the feedback path (i.e., move the loop closure through a flop, making the path register-bounded so the timing analyser can constrain it) or re-derive the signal so it no longer appears in its own cone. Detection: search the Quartus Synthesis report for `combinational loop`; doc 41 covers report mechanics.
- **Citation:**
  - Intel *Recommended HDL Coding Styles* (`https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/recommended-hdl-coding-styles`, live URL — local capture is an app-shell).
  - FPGACPU verilog coding standard: `references/raw/fpgacpu/verilog_coding_standard.html:487-494 @ 2026-05-20` ("if you find you have a backwards dependency between blocking assignments… either re-order the assignments, or split one assignment off into its own `always()` block. Otherwise, the simulation and synthesis will still be correct, but they may not match anymore.")

### #4 Latch inferred from incomplete combinational coverage

- **Symptom:** Quartus Synthesis report contains `inferred latch` for a signal that was meant to be a wire; gate count is unexpectedly large or includes latches in the resource summary; behaviour in hardware differs from RTL simulation, particularly around reset, because the latch retains a value rather than evaluating combinationally. In SystemVerilog with `always_comb`, the tool typically also raises a "latch implied" warning.
- **Cause:** An `always_comb` block whose output is not assigned on every execution path: an `if` without `else`, an `if`/`elseif` chain missing the trailing `else`, or a `case` statement missing `default` (with the case selector taking an unenumerated value, or simulating to `X`).
- **Fix:** Two equivalent disciplines, both acceptable:
  1. **Top-of-block defaults.** Assign every output its baseline value as the first statements after `begin`, then override per branch (the §3.2 pattern). Each `case` arm only mentions the outputs it changes; nothing the arm omits floats.
  2. **Exhaustive arms.** Every `if`/`elseif` chain ends with `else`; every `case` statement ends with `default:`; every arm writes every output. Less compact than #1, sometimes necessary when the defaults would be misleading.

  For SV `case` statements, `unique`/`priority` adds a simulation assertion that catches an unintended overlap or unenumerated value before it becomes a runtime latch — but does *not* substitute for a `default` arm. Always include `default:`.
- **Citation:**
  - Intel *Register and Latch Coding Guidelines* (`https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/register-and-latch-coding-guidelines`, live URL — local capture is an app-shell).
  - lowRISC SV style: `references/raw/style/lowrisc_systemverilog_style.md:2189-2197 @ commit 735d911` ("a `default:` statement is **always** included in order to avoid accidental inference of latches, even if all cases are covered… any variables assigned in one case item must be assigned in all case items, including the `default:`. Failing to do this can lead to a simulation/synthesis mismatch.")
  - VerilogPro *SystemVerilog always_comb, always_ff*: `references/raw/verilogpro/systemverilog_always_comb_always_ff.html:Update: always_comb @ 2022-04` (the SV-specific guarantees that make this enforceable at compile time rather than only via lint).

## 8. Verification

Quartus Synthesis-report strings to grep for after every compile (full report-reading mechanics deferred to doc 41):

- `inferred latch` — a signal that should have been combinational is being held; cross-check against the §7 #4 fix.
- `combinational loop` — feedback path missing a register; cross-check against §7 #3.
- `multi-driver` (and the related `net has multiple drivers`) — the single-driver rule (§2) was violated; find the second driver and remove it.
- `Latch.* inferred` / `Implicit latch` (vendor-tool warning class for SV `always_comb`) — same root cause as `inferred latch`; SV gives an earlier, sharper warning.

Lint expectations:

- `always_comb` triggers a tool warning when the block's sensitivity (i.e., the implicit RHS list) is incomplete — usually because of a blocking-in-blocking back-reference (the VerilogPro "watch out for" example in §3.2).
- `always_ff` triggers a warning if any path writes the LHS using a blocking (`=`) assignment, exactly matching the §2 [C] rule.

Simulation discipline:

- Unit test that asserts the post-reset value of every register named in the module. Two assertions per register: one at `t=0` after reset is released, one after a known-good stimulus sequence. This is the cheapest way to catch a missing `else` in an `always_ff` and the cheapest way to catch a latch inferred for what was meant to be a `_d` wire.
- For combinational blocks, a sweep stimulus across all input combinations within reason (≤16-bit inputs are tractable) catches latches that survived synthesis by exposing the "held" value on a transition that should have re-evaluated.

SVA handshake assertions and broader verification methodology live in doc 41.

## 9. Provenance footer

- `references/extracted_text/methodology/CummingsSNUG1998SJ_FSM.txt @ Rev 1.1 (SNUG 1998)` — used for §2 (blocking/nonblocking [C] rules, one-concern-per-block [C]), §6 (two-block FSM style [O]), §7 #1 (citation in the monolithic-always entry).
- `references/raw/methodology/CummingsSNUG1998SJ_FSM.pdf @ Rev 1.1 (SNUG 1998)` — companion PDF for the same paper (cited via the extracted text).
- `references/raw/style/lowrisc_systemverilog_style.md @ commit 735d911` — used for §2 (blocking/nonblocking [C], no-mix [C], default/case latch [C], one-concern [C], reset-first [V]), §3.1 (canonical `_q`/`_d` register), §3.2 (canonical `always_comb` with defaults), §3.4 (one-concern-per-block citation), §6 (lowRISC variation [O]), §7 #1, #2, #4.
- `references/raw/fpgacpu/verilog_coding_standard.html @ collected 2026-05-20` — used for §2 (single-driver [C], no-mix [C], combinational-loop [C]), §6 (FPGADesignElements style [O]), §7 #2, #3.
- `references/projects/FPGADesignElements/Register.v @ commit 2450a54` — used for §3.1 (Verilog-2001 canonical sync-reset register), §5 (minimal working pattern composite source), §6 (FPGADesignElements style [O]).
- `references/projects/FPGADesignElements/Register_areset.v @ commit 2450a54` — used for §2 (reset-first [V] structural priority), §3.1 (async-reset register), §6 (FPGADesignElements style [O]).
- `references/raw/verilogpro/verilog_always_block.html @ 2022-04` — used for §4 (combinational scheduling), §6 (VerilogPro variation [O]).
- `references/raw/verilogpro/systemverilog_always_comb_always_ff.html @ 2022-04` — used for §3.2 (`always_comb` guarantees), §7 #4.
- `http://www.sunburst-design.com/papers/CummingsSNUG2000SJ_NBA.pdf` — live URL, no local capture (local file is `references/raw/methodology/CummingsSNUG2000SJ_NBA_fetch_failed.html`, a fetch-failure stub; do not cite local). Used for §2 (single-driver [C], NBA-in-seq [C], no-mix [C]), §4 (two-region NBA model), §7 #2 (primary citation).
- `https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/register-and-latch-coding-guidelines` — live URL, local capture is an app-shell (`references/raw/intel/quartus_standard_register_latch_guidelines.html`). Used for §2 (latch-coverage [C], secondary-control [V]), §3.3 (secondary control patterns), §7 #4.
- `https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/recommended-hdl-coding-styles` — live URL, local capture is an app-shell. Used for §2 (default-assignment [C], combinational-loop [C]), §7 #3.
