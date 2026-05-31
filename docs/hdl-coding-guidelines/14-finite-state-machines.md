# Finite State Machines

> Bundle version: 2026-05-19
> Pinned commits: archive captures dated `2026-05-20` per [references/MANIFEST.md](../references/MANIFEST.md); Intel HDL guidance is Quartus Standard Edition 18.1 (live docs).
> Load with: [13-registers-and-combinational-blocks.md](13-registers-and-combinational-blocks.md), [12-synthesizable-sv-subset.md](12-synthesizable-sv-subset.md), [15-pipelines-and-latency-thinking.md](15-pipelines-and-latency-thinking.md), [16-resource-and-state-economy.md](16-resource-and-state-economy.md)
> Status mix: [C] ~40%, [V] ~30%, [O] ~20%, [I] ~10%. [C] dominates §2 (default/reset/case rules); [V] covers block-split conventions; [O] covers per-source variation styles; [I] covers the microcoded ROM-driven pattern and Cyclone V encoding-cost claims that no captured primary source establishes directly.

## 1. Purpose & one-line summary

An FSM is a state register, a next-state decoder, and an output decoder; the synthesis tool recognizes this when the code makes those three parts obvious. This doc gives the consuming agent a small catalogue of FSM templates — one-block, two-block, three-block, and microcoded — and the rules (default state, safe defaults, encoding choice, case discipline) that keep each template synthesizable and recoverable. Reset construction, latch-avoidance mechanics, pipeline-control patterns, state-count justification, encoding cost in ALMs, and ROM-inference templates are deferred to the docs listed in `Load with:`.

## 2. The contract (must-obey)

- [C] State is held in a flop array driven by a single `always_ff` block; next-state logic lives in a separate combinational block (`always_comb` in SV). The two-block split corresponds to Cummings's partitioning into "clocked present state logic, next state combinational logic and output combinational logic" (Cummings 1998, p. 5). lowRISC mandates the same partitioning ("a combinational process block… a clocked process block that updates state from next state"; `references/raw/style/lowrisc_systemverilog_style.md:2841-2846`).
- [C] The state type is declared with `typedef enum logic [N-1:0] { ... } <name>_e;`. The storage type *must* be specified (`references/raw/style/lowrisc_systemverilog_style.md:1212-1215`); anonymous enums are forbidden (same source, lines 1261-1264).
- [C] Every FSM has a defined power-on / reset state, and the reset value of the state register is one of the enumerated states. The Verilog/SV idiom is `if (!rst_n) state_q <= StIdle;` (`references/raw/style/lowrisc_systemverilog_style.md:2925-2932`); Cummings shows the same with active-high reset and binary encoding (`references/extracted_text/methodology/CummingsSNUG1998SJ_FSM.txt:212-215`). Reset construction itself (async-assert/sync-release) is deferred to [11-clocking-resets-and-cyclone-v-clock-networks.md](11-clocking-resets-and-cyclone-v-clock-networks.md).
- [C] Every `case` over the FSM state has a `default:` arm; either every output and `next_state` is given a default assignment *before* the `case` (so an empty `default: ;` is permissible), or the `default:` arm itself assigns a defined value to every output and `next_state`. Source: lowRISC `references/raw/style/lowrisc_systemverilog_style.md:2187-2233` and Cummings (default-at-top pattern, p. 6, `references/extracted_text/methodology/CummingsSNUG1998SJ_FSM.txt:251-268`). The live Intel HDL Coding Styles guide (Quartus 18.1) gives the same prescription for case-based FSMs.
- [C] `casex` is prohibited inside FSM next-state logic; if wildcard matching is needed, use `case inside` (preferred) or `casez` (Verilog-2001 compatible) and write case items with `?` wildcards so they are mutually exclusive (`references/raw/style/lowrisc_systemverilog_style.md:2236-2252`).
- [C] Do not use the `// synopsys full_case` or `// synopsys parallel_case` pragmas. They cause sim/synth mismatches and they are a Synopsys-only mechanism that Quartus 18.1 does not respect uniformly (`references/raw/style/lowrisc_systemverilog_style.md:2158-2164`). Prefer SV's `unique case` / `priority case` instead — these are language-level, not pragma.
- [V] The two-block FSM (one `always_ff` for the state register, one `always_comb` for next-state and outputs) is the default layout for medium-size FSMs. Cummings calls it "the easiest method to understand and implement" (`references/extracted_text/methodology/CummingsSNUG1998SJ_FSM.txt:181-189`); lowRISC's mandatory style is two-block (`references/raw/style/lowrisc_systemverilog_style.md:2838-2846`).
- [V] The three-block FSM (state register `always_ff`, next-state `always_comb`, output decoder either `always_comb` or a second `always_ff`) is used when outputs must be registered to make external timing or to add a pipeline stage. Cummings discusses registered outputs as either a one-always-block FSM or a "second sequential always block… added to the design" (`references/extracted_text/methodology/CummingsSNUG1998SJ_FSM.txt:490-492`).
- [V] The one-block FSM (state and outputs computed and registered inside a single `always_ff`) is "more simulation-efficient" but "more difficult to modify and debug" (`references/extracted_text/methodology/CummingsSNUG1998SJ_FSM.txt:497-505`); use it only when outputs are inherently registered and the FSM is small enough that the convenience does not become a maintenance liability. Cummings names no state-count threshold; treat any specific cutoff as engineering judgment.
- [O] State encoding choice (binary, one-hot, Gray) is declared by the enum's storage values, but Quartus may re-encode by default during Analysis & Synthesis; pin the encoding either with the per-entity `state_machine_encoding` attribute on the state register or with the project-wide `STATE_MACHINE_PROCESSING` QSF assignment. Source: Intel Quartus Prime Standard 18.1 *Recommended HDL Coding Styles*, [live docs](https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/recommended-hdl-coding-styles).
- [I] Microcoded FSMs (next-state and outputs read from a ROM addressed by `{state, input_strobes}`) are a synthesizable and era-faithful pattern on Cyclone V. Inference chain: Cummings's general FSM structure (state register + next-state decoder + output decoder) plus Cyclone V's M10K / MLAB ROM inference (see [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md)) implies that a ROM read can replace the combinational next-state decoder while preserving the contract above. Cummings 1998 does not use the term "microcoded" and does not directly cover the pattern; the brief in [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md) supplies the selection criterion.

## 3. Constructs / signals / API reference

### 3.1 State declaration

lowRISC's prescription: an enum type with an explicit storage type, named with the `_e` suffix; states named in `UpperCamelCase` with `Idle` or `StIdle` as the canonical reset state.

```systemverilog
// references/raw/style/lowrisc_systemverilog_style.md:2895-2933 @ 2026-05-20
// Define the states
typedef enum {
  StIdle, StFrameStart, StDynInstrRead, StBandCorr, StAccStoreWrite, StBandEnd
} alcor_state_e;

alcor_state_e alcor_state_d, alcor_state_q;
```

Note: this excerpt omits the explicit storage type (`logic [2:0]`) that lowRISC's prose mandates at `references/raw/style/lowrisc_systemverilog_style.md:2212-2215`. The example is conformant to lowRISC's *naming* and *typedef* rules but relies on the enum's default storage; for this bundle, prefer the more conservative form `typedef enum logic [$clog2(N)-1:0] { ... } state_e;` because Quartus's FSM extractor recognizes the encoding only when the storage type is explicit.

Cummings's older parameter-based pattern (Verilog-2001) is equivalent in synthesis intent; it shows the same explicit-width discipline:

```verilog
// references/extracted_text/methodology/CummingsSNUG1998SJ_FSM.txt:131-136 @ 2026-05-20
parameter [2:0] // synopsys enum code
                IDLE = 3'd0,
                  S1 = 3'd1,
                  S2 = 3'd2,
                  S3 = 3'd3,
               ERROR = 3'd4;
```

**Encoding patterns:**

| Encoding | Bit count | When to choose | Cyclone V notes |
|---|---|---|---|
| Binary | `$clog2(N)` | Default; minimum flop count; reasonable for any N | Decoder is a wide `case`; ALM cost grows with N. See [32-arithmetic-patterns-and-operator-cost.md](32-arithmetic-patterns-and-operator-cost.md). |
| One-hot | `N` | Small-to-medium FSMs where next-state decode collapses to a few wide ORs; can register-pack into ALMs cleanly | More flops, often shorter logic depth; era-faithful only when the original chip used one-hot |
| Gray | `$clog2(N)` | Historically low-power; useful when the state crosses clock domains as a counter (rare for FSMs) | See [24-cdc-multi-bit.md](24-cdc-multi-bit.md) for Gray on CDC pointers |
| Quartus-chosen | tool-decided | Fallback when no era constraint pins encoding | Recorded in the Synthesis report's State Machine list; see §8 |

The fmax/ALM-cost ranking among encodings is design-dependent; for hard numbers on Cyclone V, defer to [32-arithmetic-patterns-and-operator-cost.md](32-arithmetic-patterns-and-operator-cost.md). [I]

### 3.2 Two-block FSM template

The default layout. One `always_comb` block holds defaults-at-top, then a `unique case (state_q)` body that overrides them. A separate `always_ff` block latches `state_d` into `state_q` on the clock edge.

```systemverilog
// references/raw/style/lowrisc_systemverilog_style.md:2208-2233 @ 2026-05-20
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

Paired state register:

```systemverilog
// references/raw/style/lowrisc_systemverilog_style.md:1866-1873 @ 2026-05-20
always_ff @(posedge clk or negedge rst_ni) begin
  if (!rst_ni) begin
    state_q <= StIdle;
  end else begin
    state_q <= state_d;
  end
end
```

### 3.3 Three-block FSM template

Used when one or more outputs must be registered for external timing or to add a pipeline stage. Two `always_ff` blocks (one for state, one for outputs) and one `always_comb` for next-state. Cummings:

```
// references/extracted_text/methodology/CummingsSNUG1998SJ_FSM.txt:490-492 @ 2026-05-20
Registered outputs may be added to the Verilog code making assignments to an
output using nonblocking assignments in a sequential always block. The FSM can
be coded as one sequential always block or a second sequential always block can
be added to the design.
```

Structure (composed pattern, conforms to lowRISC blocks discipline and Cummings's three-part partitioning; marked [I] composite because no single archive source presents it as a single block):

```systemverilog
// Composed three-block pattern; conforms to:
//   lowRISC FSM section (state register + comb decoder)
//   Cummings 1998 p.9 (registered outputs)
// always_ff state register
always_ff @(posedge clk or negedge rst_ni) begin
  if (!rst_ni) state_q <= StIdle;
  else         state_q <= state_d;
end

// always_comb next-state decoder
always_comb begin
  state_d = state_q;
  unique case (state_q)
    StIdle: if (start) state_d = StRun;
    StRun:  if (done)  state_d = StDone;
    StDone:            state_d = StIdle;
    default: ;
  endcase
end

// always_ff registered output decoder
always_ff @(posedge clk or negedge rst_ni) begin
  if (!rst_ni) begin
    valid_q <= 1'b0;
  end else begin
    valid_q <= (state_d == StDone);
  end
end
```

### 3.4 One-block FSM template

Narrow applicability: small FSMs where every output is inherently registered and the maintenance cost is acceptable. Per Cummings (p. 11):

```
// references/extracted_text/methodology/CummingsSNUG1998SJ_FSM.txt:497-505 @ 2026-05-20
In general, the one-always block state machine is slightly more simulation-
efficient than the two-always block state machine since the inputs are only
examined on clock changes; however, this state machine can be more difficult to
modify and debug.

When placing output assignments inside the always block of a one-always block
state machine, one must consider the following:

Placing output assignments inside of the always block will infer output flip-
flops. It must also be remembered that output assignments placed inside of the
always block are "next output" assignments which can be more error-prone to
code.
```

Use the two-block template by default; reach for the one-block form only when the convenience of co-locating state update and output flops outweighs the readability loss.

### 3.5 Default state and safe defaults

The canonical pattern (the foundation of anti-pattern #13's fix in §7):

1. The first line inside the `always_comb` next-state block assigns `state_d = state_q;` (default: stay in current state). This is lowRISC's prescription: "The default value for the 'next state' variable should be the current state" (`references/raw/style/lowrisc_systemverilog_style.md:2876`).
2. Every output signal is assigned a defined default value (typically the inactive level) immediately after the `state_d` default.
3. The `case (state_q)` body overrides defaults only where transitions or active outputs occur.
4. A `default:` arm is always present. If defaults-at-top were given, `default: ;` is permissible; otherwise the `default:` arm must assign `state_d` and every output (`references/raw/style/lowrisc_systemverilog_style.md:2187-2197`).

Cummings names three alternatives for the default next-state assignment (p. 6):

```
// references/extracted_text/methodology/CummingsSNUG1998SJ_FSM.txt:251-267 @ 2026-05-20
Place a default next state assignment on the line immediately following the
always block sensitivity list. This default assignment is updated by next-state
assignments inside the case statement. There are three types of default
next-state assignments that are commonly used: (1) next is set to all x's, (2)
next is set to a predetermined recovery state such as IDLE, or (3) next is just
set to the value of the state register.
```

This bundle picks option (3) — `state_d = state_q;` — for two reasons. First, it matches lowRISC's mandatory default. Second, lowRISC explicitly forbids the option-(1) `'x` assignment in synthesizable RTL ("RTL must not assert `X` to indicate 'don't care' to synthesis in any case"; `references/raw/style/lowrisc_systemverilog_style.md:1905-1909`) because of the sim/synth-mismatch risk. The Intel HDL Coding Styles guide (Quartus 18.1, [live URL](https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/recommended-hdl-coding-styles)) recommends a defined default to avoid latch inference; defining `state_d` and every output before the `case` is sufficient.

### 3.6 Microcoded FSM table [I]

A microcoded FSM replaces the combinational next-state decoder with a ROM lookup. The ROM is addressed by `{state, input_strobes}` and the data word is partitioned into `{next_state, output_word}`. Inference chain (no captured archive source covers this directly; this is [I]):

- Cummings's general FSM partition (`references/extracted_text/methodology/CummingsSNUG1998SJ_FSM.txt:181-189`) treats the next-state decoder as a black-box combinational function; replacing the case-statement decoder with a ROM lookup preserves the contract.
- The Cyclone V ROM substrate (M10K or MLAB) is inferred from a Quartus-recognized template; see [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md) for the inference rules. The lowest-level building block is a single-ported synchronous-read RAM/ROM such as:

```verilog
// references/projects/FPGADesignElements/RAM_Single_Port.v:51-69 @ 2026-05-20
module RAM_Single_Port
#(
    parameter                       WORD_WIDTH          = 0,
    parameter                       ADDR_WIDTH          = 0,
    parameter                       DEPTH               = 0,
    parameter                       RAMSTYLE            = "",
    parameter                       READ_NEW_DATA       = 0,
    parameter                       RW_ADDR_COLLISION   = "",
    parameter                       USE_INIT_FILE       = 0,
    parameter                       INIT_FILE           = "",
    parameter   [WORD_WIDTH-1:0]    INIT_VALUE          = 0
)
(
    input  wire                         clock,
    input  wire                         wren,
    input  wire     [ADDR_WIDTH-1:0]    addr,
    input  wire     [WORD_WIDTH-1:0]    write_data,
    output reg      [WORD_WIDTH-1:0]    read_data
);
```

For a microcoded FSM with N states and K input strobes, the ROM is `2**(N_state_bits + K)` words deep and `(N_state_bits + W_outputs)` bits wide. Use `READ_NEW_DATA = 0` (returns OLD data on coincident write/read) and `wren = 1'b0` for a pure ROM; tie `write_data` to `'0`. Initialize the ROM via `INIT_FILE` (`$readmemh` on Cyclone V) or `INIT_VALUE` per `RAM_Single_Port.v:146-160`.

Skeleton wiring:

```systemverilog
// Composed microcoded-FSM skeleton; [I] composite:
//   substrate: references/projects/FPGADesignElements/RAM_Single_Port.v
//   structure: Cummings 1998 FSM partition
logic [STATE_BITS-1:0] state_q;
logic [STATE_BITS-1:0] next_state;
logic [OUT_BITS-1:0]   output_word;
logic [STATE_BITS+IN_BITS-1:0] ucode_addr;
logic [STATE_BITS+OUT_BITS-1:0] ucode_data;

assign ucode_addr = {state_q, input_strobes};
RAM_Single_Port #(
  .WORD_WIDTH (STATE_BITS + OUT_BITS),
  .ADDR_WIDTH (STATE_BITS + IN_BITS),
  .DEPTH      (1 << (STATE_BITS + IN_BITS)),
  .RAMSTYLE   ("M10K"),
  .USE_INIT_FILE (1),
  .INIT_FILE  ("ucode.mif")
) u_ucode (
  .clock      (clk),
  .wren       (1'b0),
  .addr       (ucode_addr),
  .write_data ('0),
  .read_data  (ucode_data)
);

assign {next_state, output_word} = ucode_data;

always_ff @(posedge clk or negedge rst_ni) begin
  if (!rst_ni) state_q <= '0;          // ROM word at address 0 must encode the reset entry
  else         state_q <= next_state;
end
```

Note: because the ROM read is synchronous (one cycle), the microcoded FSM has one extra cycle of next-state latency compared with the hardwired form. This matters for cycle-accurate emulation; see [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md) for whether the era's original chip exhibits the same delay (microcoded control units of the late 1970s and early 1980s typically did) and [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md) for the MLAB vs M10K decision on the ROM size.

### 3.7 Construct table

| Name | Type / width | Meaning | Driven by | Drives |
|---|---|---|---|---|
| `state_q` | `enum logic [N-1:0]` | Registered current state | `always_ff` from `state_d` (or `next_state` from ROM read) | Next-state decoder; output decoder |
| `state_d` / `next_state` | `enum logic [N-1:0]` | Combinational next-state value (or ROM read output) | `always_comb` from `state_q` and inputs; or ROM `read_data[STATE_BITS-1:0]` | `state_q` via `always_ff` |
| `output_word` | `logic [W-1:0]` | Combinational or registered output bus | `always_comb` decoder; or ROM `read_data[STATE_BITS+W-1:STATE_BITS]` | Downstream datapath |
| `clk` | `wire` | Clock for state register | Clock network (GCLK) | `always_ff` blocks |
| `rst_n` / `rst_ni` | `wire` | Async-assert sync-release reset | Reset network | `always_ff` resets `state_q` to `StIdle` |
| `ucode_addr` | `logic [STATE_BITS+IN_BITS-1:0]` | Microcode ROM address | `{state_q, input_strobes}` | ROM `addr` port |
| `ucode_data` | `logic [STATE_BITS+OUT_BITS-1:0]` | Microcode ROM data word | ROM `read_data` | `{next_state, output_word}` split |

## 4. Sequencing & timing

On each rising clock edge, `state_q` latches `state_d` from the next-state decoder. Between edges, the next-state decoder re-evaluates `state_d` from the new `state_q` plus any input signals that changed; outputs computed in the same `always_comb` propagate combinationally.

```
                  +--clk
                  |        |        |        |        |
   state_q:    StIdle ----X StRun ----X StDone --X StIdle --
                  |        |        |        |
   state_d:    StRun ------X StDone --X StIdle --X StRun (waits on start)
                  |        |        |        |
   start:    __/-----X______________________________________
   done:    _______________X---X____________________________
   valid:   ______________________/---X____________________   (combinational)
   valid_q: ____________________________/---X______________   (registered, three-block)
```

Output timing:

- **Two-block (combinational outputs):** output transitions occur in the same cycle as the state transition. Acceptable for outputs read by other combinational logic in the same module; not acceptable across a registered module boundary without a downstream sampling register.
- **Three-block (registered outputs):** outputs change one cycle *after* the state transition. Clean for external timing. Cummings calls this out only obliquely ("Registered outputs may be added… as a second sequential always block"; `references/extracted_text/methodology/CummingsSNUG1998SJ_FSM.txt:490-492`).
- **Microcoded (ROM-driven):** the ROM's synchronous read inserts one cycle of latency between `{state_q, input_strobes}` changing and the new `next_state` / `output_word` being valid. The state register samples `next_state` on the *next* clock edge after the ROM read, so a transition that the hardwired form completes in one cycle takes two cycles in the microcoded form unless the ROM is wrapped in feedback to compensate.

TimeQuest path analysis on the next-state decoder is deferred to [40-timing-closure-and-sdc.md](40-timing-closure-and-sdc.md).

## 5. Minimal working pattern

A 3-state FSM controlling a single `valid` handshake with a downstream sink. Composed from the lowRISC two-block template; [I] composite (states named `Idle`/`Run`/`Done` rather than lowRISC's `Idle`/`Work`/`Wait` to match the doc-level example).

```systemverilog
// Composed pattern; conforms to:
//   references/raw/style/lowrisc_systemverilog_style.md:2208-2232 @ 2026-05-20
//   references/raw/style/lowrisc_systemverilog_style.md:2925-2932 @ 2026-05-20
typedef enum logic [1:0] {
  StIdle = 2'd0,
  StRun  = 2'd1,
  StDone = 2'd2
} handshake_state_e;

handshake_state_e state_q, state_d;
logic             valid;

always_comb begin
  state_d = state_q;
  valid   = 1'b0;
  unique case (state_q)
    StIdle:  if (start)   state_d = StRun;
    StRun:   if (in_done) state_d = StDone;
    StDone:  begin
      valid = 1'b1;
      if (sink_ready) state_d = StIdle;
    end
    default: ;
  endcase
end

always_ff @(posedge clk or negedge rst_ni) begin
  if (!rst_ni) state_q <= StIdle;
  else         state_q <= state_d;
end
```

This pattern exhibits the four contractual properties from §2: explicit enum with storage type, single `always_ff` for the state register with a named reset state, defaults at the top of the `always_comb`, and a `default: ;` arm.

## 6. Common variations across implementations

- [O] **Hardwired, two-block, binary-encoded** (lowRISC). The default for medium FSMs. Source: `references/raw/style/lowrisc_systemverilog_style.md:2836-2933`. The `state_d`/`state_q` naming and `Idle`/`Work`/`Wait` example are the lowRISC contribution.
- [O] **Hardwired, two-block, one-hot-encoded** (Cummings 1998 "verbose one-hot," Figure 11). Source: `references/extracted_text/methodology/CummingsSNUG1998SJ_FSM.txt:856-915`. One flop per state; the next-state decoder degenerates to a few wide ORs because each branch only sets one state bit. Cummings notes that the simplified one-hot form (`case (1'b1)` with bit indices) "permits comparison of single bits as opposed to comparing against the entire state vector" (`references/extracted_text/methodology/CummingsSNUG1998SJ_FSM.txt:153-155`). Fmax/ALM-cost claims for one-hot on Cyclone V specifically are [I] (Cummings predates Cyclone V) — see [32-arithmetic-patterns-and-operator-cost.md](32-arithmetic-patterns-and-operator-cost.md) for the actual cost numbers.
- [O] **Hardwired, three-block, registered outputs** (Cummings 1998). Source: `references/extracted_text/methodology/CummingsSNUG1998SJ_FSM.txt:478-492`. Use when outputs must be registered for external timing; pay one cycle of latency.
- [O] **Hardwired, FPGADesignElements one-hot with parallel "checker" modules**. Source: `references/projects/FPGADesignElements/fsm.html:54-62`. Each state is one flop; each transition is a "checker" module asserting that flop's set or clear input. Useful as an alternative when the toolchain's automatic one-hot extraction does not produce the desired structure.
- [I] **Microcoded, ROM-driven**. Inference composite of Cummings's FSM partition and the FPGADesignElements `RAM_Single_Port.v` substrate; see §3.6 above. ROM holds `{next_state, control_word}` keyed by `{state, input_strobes}`. Era-faithful pattern for emulating microcoded control units; selection criterion is in [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md), ROM substrate in [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md).
- [O] **Quartus-encoded automatic** (Intel HDL Coding Styles, [live URL](https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/recommended-hdl-coding-styles)). Let Quartus pick the encoding via the project-wide `STATE_MACHINE_PROCESSING` QSF setting (`Auto`, `One-Hot`, `Minimal Bits`, etc.). Acceptable fallback for non-era-faithful designs. For era-faithful work, pin the encoding explicitly with the source-level enum values and the `state_machine_encoding` attribute so the chosen encoding survives in the Fitter report.

## 7. Anti-patterns (mistakes that compile but break)

### #13 FSM without `default` state / safe default

- **Symptom:** The FSM hangs after a glitch or power-up corruption; reset doesn't recover. Outputs go to `'x` in simulation or become unrecoverable in hardware. The Quartus Synthesis report's State Machine list may show the FSM extracted, but transitions to undefined codepoints have no fallback.
- **Cause:** Any of (a) the `case (state_q)` body has no `default:` arm — in simulation a state value equal to `'x` or an unenumerated code falls through to no branch, latches the previous combinational output, and inferred outputs become latches per the `always_comb` linter; (b) the `always_comb` block omits the defaults-at-top pattern, so some output is undriven on at least one case path and the synthesis tool infers a latch; (c) the state register has no reset (or resets to `'x` / an unenumerated value), so power-up state is undefined; (d) the encoding leaves unreachable codepoints (e.g., 5 named states in a 3-bit register leaves 3 codepoints unreachable) and none of them has a transition back to `StIdle`.
- **Fix:** Apply all four of the §3.5 rules together — defaults-at-top for `state_d` and every output, explicit `default:` arm (empty if defaults-at-top covers everything), `always_ff` reset to a named state, and either an exhaustive encoding (binary with `2**$clog2(N) == N`) or a `default:` arm whose action transitions back to `StIdle`. See the §5 minimal pattern. The deeper lowRISC philosophy is "RTL must not assert `X`… designs should fully define all signal values" (`references/raw/style/lowrisc_systemverilog_style.md:1905-1909`).
- **Citation:** `references/raw/style/lowrisc_systemverilog_style.md:2187-2233` and `:2876-2878` (default-to-current-state rule). Cummings's three-option discussion at `references/extracted_text/methodology/CummingsSNUG1998SJ_FSM.txt:251-267` — but note this bundle rejects Cummings's option (1) (`next = 3'bx`) because of lowRISC's no-X rule. Intel Quartus Register and Latch Coding Guidelines (Quartus 18.1, [live URL](https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/register-and-latch-coding-guidelines)) for the latch-inference consequence of leaving outputs undriven inside `always_comb`.

### #7 `casex` / `casez` with overlapping patterns

- **Symptom:** Sim/synth mismatch. The simulator evaluates case items in source order with wildcard matching (so the first matching item wins); the synthesis tool may flatten the structure into parallel comparators, in which case overlapping items produce a logic OR rather than a priority encode. Outputs disagree between the simulator and the post-fit netlist on inputs that match more than one case item. Worse with `casex` because `'x` in either the case expression *or* a case item silently widens the match — and `'x` can leak into the case expression from any upstream undriven signal.
- **Cause:** Using `casex` at all, or using `casez` with case items whose `?` wildcards make two items match the same input pattern. The Verilog standard's wildcard match is symmetric for `casex` (an `'x` on *either* side matches), which is almost never the designer's intent and is invisible in source review.
- **Fix:** (1) Prefer `case inside { ... }` (SV-2017), which does not treat `'x` or `'z` in the case expression as a wildcard at all. (2) If Verilog-2001 compatibility is required, use `casez` only, write wildcards with `?` (never `z`), and ensure case items are mutually exclusive. (3) Prefix with `unique case` (or `unique casez`) so the simulator asserts no two items overlap. (4) Never write the `// synopsys full_case parallel_case` pragmas — they are a Synopsys directive that pre-dates SV `unique`/`priority`, they do not affect Quartus's correctness checking, and they actively hide overlap (`references/raw/style/lowrisc_systemverilog_style.md:2158-2164`).
- **Citation:** `references/raw/style/lowrisc_systemverilog_style.md:2236-2252` (the `casex` prohibition and the `case inside` / `casez` preference order). Same file `:2158-2164` for the full_case/parallel_case prohibition. lowRISC cross-references Cummings's separate "Evil Twins" paper (1999) for the deeper analysis; that paper is not in this bundle's archive. Cummings 1998 (this doc's primary Cummings source) does *not* directly cover casex/casez overlap — it covers the related but distinct full_case/parallel_case pragmas at `references/extracted_text/methodology/CummingsSNUG1998SJ_FSM.txt:508-557`.

### #14 Redundant states that can be merged

- **Symptom:** State count is one or more larger than the minimum sufficient to encode the FSM's behavior. The state register uses one more bit of encoding than necessary; the next-state decoder is wider than necessary; the design fails the resource-economy review in [16-resource-and-state-economy.md](16-resource-and-state-economy.md). Synthesized example: two states `StFetch1` and `StFetch2` whose outgoing transitions and output assignments are identical conditioned on the same inputs — they are the same state by definition. [I]
- **Cause:** States added one-per-action during incremental development without re-deriving the state-transition table. Often visible as `StPrepX` immediately followed by `StX` where `StPrepX` only forwards inputs without modifying outputs differently from `StX`. The COTTC-style construction at `references/projects/FPGADesignElements/fsm.html:22-32` lays out a discipline that prevents this — define operations and transformations *before* states — but ad-hoc state addition during debug routinely reintroduces redundancy.
- **Fix:** Tabulate the state-transition table explicitly (rows = states, columns = input combinations, cells = `(next_state, output_word)`). Two rows are mergeable iff they are identical for every column; collapse the merged state into one. Re-derive the encoding width with `$clog2(state_count)`. For systematic minimization beyond visual inspection, the classic algorithm is Hopcroft's partition refinement (covered in Kohavi's *Switching and Finite Automata Theory*, which Cummings cites at `references/extracted_text/methodology/CummingsSNUG1998SJ_FSM.txt:751-752` but does not reproduce). Cross-ref [16-resource-and-state-economy.md](16-resource-and-state-economy.md) for the principle ("every register must justify itself") that motivates the discipline; doc 14 here owns the FSM-specific mechanics.
- **Citation:** No direct Cummings 1998 citation — the paper refers state minimization out to Kohavi [2] (`references/extracted_text/methodology/CummingsSNUG1998SJ_FSM.txt:751-752`) and does not cover it itself. Mark [I] inference; the supporting source is `references/projects/FPGADesignElements/fsm.html:22-32` for the COTTC discipline that prevents the redundancy in the first place, plus the general DFA equivalence argument at `references/projects/FPGADesignElements/fsm.html:64-75`.

### #15 (supporting) Output decoder uses combinational `always` but downstream consumer assumes registered

- **Symptom:** Glitches on the FSM's output drive a downstream flop's data input as the next-state decoder transitions. The downstream flop captures the wrong value on the next edge if its setup is barely met.
- **Cause:** Two-block FSM emits combinational outputs (correct, by design); downstream module declares its input port as if it were already registered.
- **Fix:** Either move to a three-block FSM with registered outputs (§3.3) or register the outputs at the downstream module boundary. Document the FSM's output timing in the module header.
- **Citation:** Cummings 1998 distinguishes the cases at `references/extracted_text/methodology/CummingsSNUG1998SJ_FSM.txt:478-505`. [I] for the consumer-side discipline.

## 8. Verification

1. **Quartus Synthesis report — State Machine list.** After Analysis & Synthesis, the report should contain a State Machine entry per FSM, with state names matching the source enum and an encoding column. If the FSM does *not* appear, Quartus did not extract it — likely a coding-style violation (mixed enum and non-enum drivers of `state_q`, state register driven by more than one `always_ff`, or the enum's storage type missing). Refactor before chasing other issues.

2. **Quartus encoding override.** If the source pins the encoding (binary via enum values) but the project setting selects one-hot, Quartus will re-encode. For era-faithful work, set `STATE_MACHINE_PROCESSING` to `User-Encoded` in the QSF and re-check the State Machine report; the encoding column must equal the source enum's bit pattern. The QSF assignment is documented in Intel Quartus Prime Standard 18.1 *Recommended HDL Coding Styles* ([live URL](https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/recommended-hdl-coding-styles)).

3. **Simulation — transition coverage.** Stimulate every transition explicitly in the testbench. Also force-set `state_q` to an unenumerated code (e.g., for a 3-bit register with 5 named states, force `state_q = 3'b111`) and confirm the FSM transitions back to `StIdle` within one cycle via the `default:` arm. Reset coverage (every register seen at reset and at not-reset) is the broader practice in [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md).

4. **SVA.** A minimal known-state assertion catches `'x` poisoning:

   ```systemverilog
   // Defer SVA mechanics to doc 41
   `ASSERT_KNOWN(StateKnown_A, state_q, clk, !rst_ni)
   ```

   For overlap-checking on `casez` decoders, prefer `unique case` (the simulator asserts non-overlap natively) over an extra SVA. Full SVA style is in [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md).

5. **TimeQuest slack on the next-state decoder.** The decoder is often the FSM's critical path. If slack is marginal, either re-encode to one-hot (shorter decoder logic depth, more flops) or split off a registered output stage (three-block form). The actual fmax improvement is design-dependent — see [40-timing-closure-and-sdc.md](40-timing-closure-and-sdc.md).

6. **For microcoded FSMs.** Confirm in the Synthesis report that the microcode ROM was inferred to M10K (or MLAB, depending on size — `references/projects/FPGADesignElements/RAM_Single_Port.v:75-80` shows the `ramstyle` attribute that pins this). Confirm via simulation that the one-cycle ROM read latency matches the era-faithful timing if cycle accuracy is required.

## 9. Provenance footer

- `references/extracted_text/methodology/CummingsSNUG1998SJ_FSM.txt @ 2026-05-20` — used for §2 (block-split, default-state options, registered outputs, one-block tradeoffs), §3.1, §3.3, §3.4, §3.5, §6 (one-hot variation, three-block variation), §7 anti-patterns #13 (option enumeration only — option (1) `'x` is explicitly rejected by this bundle) and #14 (acknowledgement that Cummings refers out to Kohavi).
- `references/raw/methodology/CummingsSNUG1998SJ_FSM.pdf @ 2026-05-20` — same content; cite the PDF for authority where line-level granularity in the extracted text is not needed.
- `references/raw/style/lowrisc_systemverilog_style.md @ 2026-05-20` — used for §2 (enum declaration with explicit storage type, two-block mandate, default state, `unique case`, `casex` prohibition, full_case/parallel_case prohibition), §3.1, §3.2, §3.5, §5, §6 (binary-encoded two-block variation), §7 anti-patterns #7 and #13.
- `references/projects/FPGADesignElements/fsm.html @ 2026-05-20` — used for §6 (parallel-checker one-hot variation), §7 anti-pattern #14 (COTTC discipline and DFA equivalence argument).
- `references/projects/FPGADesignElements/RAM_Single_Port.v @ 2026-05-20` — used for §3.6 (microcoded FSM ROM substrate), §6 (microcoded variation), §8 (ramstyle attribute for inferred-memory pinning).
- `https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/recommended-hdl-coding-styles` — used for §2 (encoding override via `state_machine_encoding` and `STATE_MACHINE_PROCESSING`), §6 (Quartus-encoded automatic variation), §8 (Synthesis report State Machine list, encoding override workflow). Live URL only; the local `references/raw/intel/quartus_standard_hdl_design_guidelines.html` is an app-shell.
- `https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/register-and-latch-coding-guidelines` — used for §7 anti-pattern #13 (latch inference from undriven outputs inside `always_comb`). Live URL only; the local `references/raw/intel/quartus_standard_register_latch_guidelines.html` is an app-shell.
