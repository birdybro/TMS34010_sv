# Glossary

> Refined in Phase 3 after topic docs surfaced additional terms. The MCP entry was split into its two distinct senses (SDC `set_multicycle_path` vs. CDC "multi-cycle pulse" handshake) and the FWFT / `5CSEBA6U23I7` / pulse-synchronizer entries were sharpened. New entries (Phase 3) are flagged inline where they replace or extend an earlier guess.

Terms grouped by category. When a term's definition is contested or vendor-specific, the entry says so.

## Cyclone V hardware

- **ALM** — Adaptive Logic Module. The Cyclone V LUT-and-FF cell; one ALM contains the equivalent of ~8 4-input LUTs (configurable as smaller LUTs) plus dedicated adder logic and 2–4 registers.
- **LAB** — Logic Array Block. A column-row group of ten ALMs sharing control signals (clock, sync clear, enable). Routing locality matters; a register and its driving logic placed in the same LAB cost less in delay than one straddling LABs.
- **MLAB** — Memory Logic Array Block. A LAB whose ALMs are configured as 640-bit distributed memory. Single-port or simple dual-port. Used for small, frequently-accessed memories (≤ 32 words is the typical economic threshold versus flops; up to a few hundred words is the threshold versus M10K).
- **M10K** — A 10 240-bit embedded memory block. Single, simple-dual, or true-dual port. Used for FIFOs, frame buffers, line buffers, tile maps, and any memory too large for MLAB efficiency.
- **DSP block** — Variable-precision DSP block. Configurable as 27×27, 18×18, or 9×9 signed multiply, multiply-add, multiply-accumulate, or two independent 18×19 multiplies. Has internal pipeline registers used for inference.
- **Variable-precision DSP modes** — The configurations of the Cyclone V DSP block: 27×27, dual 18×19, or 9×9 signed multiply, plus multiplier-adder and multiplier-accumulator atoms; wider products need multi-DSP composition with an alignment-adder tree.
- **Carry chain** — The dedicated arithmetic interconnect inside a column of ALMs that propagates carries between adder bits at high speed. `+` and `-` (and the subtraction at the heart of `==`/`<`/etc.) map onto it; one bit of width costs roughly one ALM along the chain.
- **GCLK** — Global Clock network. Low-skew, high-fanout clock distribution spine; the right place for system clocks. The `5CSEBA6U23I7` has 16 GCLKs.
- **RCLK** — Regional Clock network. Lower skew within a quadrant but limited reach.
- **PCLK** — Periphery Clock. Used for I/O-region clocking; higher skew than GCLK/RCLK.
- **PLL (fractional)** — Phase-Locked Loop. Cyclone V has fractional PLLs that generate, divide, and phase-shift clocks. The synthesizable way to derive a related clock from a board oscillator; the `5CSEBA6U23I7` has 6 FPGA-side PLLs.
- **ALTPLL / IOPLL** — The Intel PLL IP variants reachable from the Quartus IP Catalog; the user-RTL boundary is the PLL output clock and the `locked` signal. Do not substitute a fabric register-divider for the PLL.
- **`ALTCLKCTRL` / `clkena`** — The dedicated Cyclone V clock-control block. The only sanctioned way to MUX, gate, or power-down a clock; fabric-built clock multiplexers are forbidden by Intel's design recommendations.
- **IOE** — I/O Element. The pin's input/output register and tri-state control. Registers placed "in the IOE" minimize input-setup and output-clock-to-pad time; tri-state is supported only at the IOE, never in fabric.
- **HPS** — Hard Processor System. The ARM Cortex-A9 subsystem on Cyclone V SoC variants. Out of scope for this bundle.
- **5CSEBA6U23I7** — The Cyclone V SoC part on the Terasic DE10-Nano. ~110K ALMs (~41K LEs equivalent), 5.6 Mbit M10K+MLAB embedded memory, 112 variable-precision DSP blocks, 16 GCLKs, 6 FPGA-side PLLs. The DE10-Nano *board* additionally carries 1 GB DDR3 attached to the HPS side; that DRAM is not on-die.
- **Constant-zero power-up** — Cyclone V flops power up to 0 from the configuration bitstream. `initial reg q = 1'b1;` does not power up high in Cyclone V silicon; any flop whose post-power-up value matters must be reset.
- **NOT-gate push-back** — A Quartus inference optimization that absorbs an inverter at a flop's input/output to obtain the source's intended `initial` value despite constant-zero power-up.

## SystemVerilog and HDL constructs

- **`logic`** — SV scalar/vector type that replaces `reg`/`wire`. Use everywhere in the bundle's prescribed subset except at `inout` pins, where `wire` is mandatory.
- **`always_ff`** — SV procedural block intended for sequential logic. Tools warn if it implies anything other than registers. Use with nonblocking (`<=`) assignments only.
- **`always_comb`** — SV procedural block intended for combinational logic. Executes once at time zero, infers its sensitivity list from RHS reads (including signals inside called functions), and tools warn if any branch leaves an output undriven. Use with blocking (`=`) assignments only.
- **`always_latch`** — SV procedural block explicitly declaring a latch. Almost never appropriate in synthesizable FPGA RTL.
- **`typedef`** — SV named type. Use for enum-typed FSM states and for packed struct payloads.
- **`enum`** — SV enumerated type. Use for FSM state encodings; pair with `typedef` and an explicit storage type (`typedef enum logic [N-1:0] {...}`); anonymous enums are forbidden in this subset.
- **Packed array** — Bit-aligned dimensions to the left of the name; treated as a single multi-bit value. Use for hardware-shaped data.
- **Unpacked array** — Element-aligned dimensions to the right of the name; treated as a collection. Use for memory arrays.
- **Packed struct** — A typedef'd, bit-aligned aggregate. Synthesizes as a wide vector; field access is legal; the one-driver-per-signal rule still applies field by field, so drive whole structs from one block.
- **`$clog2(N)`** — Ceiling of log₂(N). The canonical way to compute counter or address widths from a parameter.
- **`$bits(x)`** — Width in bits of a signal or type. Useful for parameterized assignments and ROM word widths.
- **`$readmemh` / `$readmemb`** — Elaboration-time loaders for memory initialization from hex/binary text files. The recognized way to seed an unpacked-array ROM/RAM; pairs with `INIT_FILE` attribute conventions and `.mif`/`.hex` files.
- **Blocking assignment (`=`)** — Within a block, executes immediately. Use in `always_comb`.
- **Nonblocking assignment (`<=`)** — Schedules the update for the end of the time step. Use in `always_ff`. Produces the register-swap semantics (`a <= b; b <= a;` cleanly swaps).
- **`` `default_nettype none ``** — Disables implicit wire creation. Use at the top of every file to catch typos as elaboration errors.
- **`localparam`** — A compile-time constant scoped to a module. Use for derived constants and named magic numbers; not settable at instantiation (use `parameter` for that).
- **`signed'(...)` / `unsigned'(...)` cast** — Explicit signedness conversion at a signed/unsigned boundary. Mixing signed and unsigned without an explicit cast silently promotes the whole expression to unsigned; the cast is mandatory at every such crossing.
- **`unique case` / `priority case`** — SV case modifiers that add simulation-time assertions about case-item exclusivity (`unique`) or first-match priority (`priority`) without changing synthesis. Do **not** replace the mandatory `default:` arm.
- **`case inside`** — SV-2017 case form whose case items match against ranges/wildcards but **do not** treat `'x`/`'z` in the case expression as wildcards. Preferred over `casez` and forbidden `casex`.
- **`casez`** — Verilog-2001 wildcard case; `?` (never `z`) marks don't-care bits. Acceptable when SV `case inside` is unavailable, only if items are mutually exclusive.
- **`casex`** — Symmetric wildcard case; matches `'x` in either expression or item. **Forbidden** in this subset (silent misses, sim/synth divergence).
- **`generate` / `for ... generate`** — Elaboration-time replication. Always name the generated block; never use the `generate`/`endgenerate` keywords explicitly in the bundle's subset.
- **`function automatic`** — Combinational helper returning a packed `logic`-derived type with explicit storage types on all args and no static state. Tasks are forbidden in synthesizable RTL.
- **`_q` / `_d` suffix (lowRISC)** — Naming convention: `_q` is the current (registered) value of a flop; `_d` is the next-state combinational input that feeds it. Pairs with the two-block `always_ff` + `always_comb` split.
- **`_i` / `_o` / `_ni` suffix (lowRISC)** — Naming convention: `_i` for module inputs, `_o` for outputs, `_ni` for active-low (typically reset). Port direction is visible at the call site without re-reading the module header.
- **Last-assignment-wins idiom** — Inside one `always_ff` block, two `if` branches at the same level may both fire on an edge; the last NBA scheduled on a signal supersedes earlier ones. The FPGADesignElements `Register.v` sync-clear pattern relies on this; the async-reset flavor cannot use it and must use structural `if (reset) ... else ...` priority instead.

## Reset, clock, and CDC

- **Metastability** — When a flop's input changes within the setup/hold window, its output may oscillate for a random time before settling to 0 or 1. Cannot be eliminated; can be made vanishingly improbable via synchronizer chains.
- **2FF synchronizer** — Two cascaded flops in the destination clock domain. The standard mitigation for single-bit level CDC. Quartus recognizes the structure and reports MTBF.
- **MTBF (Mean Time Between Failures)** — The metastability-related expected time between sync-chain settling failures. Quartus reports this per recognized synchronizer.
- **Gray code** — An encoding where successive values differ in exactly one bit. Used for CDC pointers in async FIFOs so a multi-bit sample is never mid-transition.
- **Gray converter (`bin2gray` / `gray2bin`)** — The combinational primitives that convert between binary and reflected-binary Gray: `bin2gray(b) = b ^ (b >> 1)`; `gray2bin` is a per-bit XOR-reduction of the shifted value. The Gray conversion is collapsed into the register that crosses the clock boundary, not applied on the destination side.
- **Async FIFO** — A FIFO with separate read and write clocks, Gray-coded pointers (each pointer crossing through a 2FF synchronizer chain), and dual-port memory. The right way to cross a multi-bit datapath between clock domains for bursts or sustained streams.
- **Multicycle path (SDC `set_multicycle_path`)** — _Refined Phase 3 — was previously conflated with the CDC "MCP handshake."_ An SDC exception telling the timing analyzer that a path is allowed N source-clock periods (N > 1) for setup. Used when the RTL guarantees the source register is stable for N cycles (or sampled only every N cycles); a setup multicycle of N normally requires a matching hold multicycle of N-1.
- **MCP handshake (multi-cycle pulse) / word synchronizer** — _New Phase 3 — split out from the previous combined MCP entry._ A CDC pattern for occasional multi-bit transfers: the payload bus crosses **unsynchronized** while a single `req`/load-toggle bit is 2FF-synchronized into the destination and an `ack`/return-toggle is 2FF-synchronized back. The producer must hold the payload stable from before `req` flips until after `ack` returns. Used when an async FIFO would be wasteful (rare transfers, wide payload).
- **Payload-stable hold** — The contract that during an MCP exchange the payload register must not change from the cycle the request toggle leaves the source to the cycle the acknowledgement toggle returns. This is what makes the unsynchronized data crossing safe.
- **Pulse synchronizer / toggle synchronizer** — A CDC pattern for single-cycle *events* across asynchronous clocks. The source toggles a level on the event; the destination 2FF-syncs the level and edge-detects it. FPGADesignElements ships both the 2-phase variant (handshake-completion gated; throughput ≈ one pulse every 5–8 cycles) and the 4-phase variant.
- **Async-assert sync-release reset** — Reset asserts asynchronously (immediate response from any state), de-asserts synchronously to the destination clock through a per-domain 2-flop release synchronizer (avoids release-time hazard).
- **`arst_n` / `rst_n` / `rst_ni`** — Bundle naming: `arst_n` is the raw external asynchronous active-low reset pin; `rst_n` (or `rst_ni` in lowRISC suffix style) is the per-domain synchronized released reset that downstream `always_ff` blocks consume.
- **`pll_locked`** — PLL `locked` indicator. ANDed with `arst_n` into the sync-release input so downstream flops do not clock from an unstable PLL output during lock acquisition.
- **Single-clock-domain design** — Having one clock through as much of the design as possible. Reduces CDC complexity to a small number of well-defined boundaries; adding a domain pays for itself in synchronizers, async FIFOs, and verification effort.
- **Defensive synchronizer (anti-pattern)** — Inserting a 2FF chain on a signal already in the destination clock domain. Wastes two flops and two cycles of latency, can mask real intra-domain timing bugs by absorbing slack; primary home is doc 16.
- **`SYNCHRONIZER_IDENTIFICATION` (Quartus attribute)** — `altera_attribute -name SYNCHRONIZER_IDENTIFICATION "FORCED IF ASYNCHRONOUS"` on a synchronizer chain forces Quartus to recognize and analyze the flops as a synchronizer and report MTBF even when its automatic detector would not.
- **`(* preserve *)`** — Quartus attribute that forbids merging, retiming, or removing the tagged register. Used on each flop of a synchronizer chain so the tools cannot pack the chain into a shift-register primitive or otherwise destroy the structure.
- **`useioff = 0`** — Quartus attribute that prevents the tagged register from being packed into an IOE; required on synchronizer-chain flops because IOEs are too far from fabric for the chain's tight placement requirement.
- **`SHREG_EXTRACT = "NO"`** — Vivado attribute (verilog-axis style) that keeps a synchronizer chain from being packed into a shift-register primitive. Inert on Quartus but harmless; the Quartus equivalents are `(* preserve *)` and the `SYNCHRONIZER_IDENTIFICATION` attribute above.

## Handshakes, FIFOs, and pipelining

- **valid / ready handshake** — A two-wire transfer protocol. The producer drives `valid` and payload; the consumer drives `ready`. A transfer happens on the cycle where both are asserted.
- **`valid`** — Producer-side wire: "I have a payload word to transfer this cycle."
- **`ready`** — Consumer-side wire: "I can accept a payload word this cycle."
- **Payload** — The data bus carried alongside the handshake.
- **No-valid-drop rule** — Once `valid` is asserted, the producer must hold it (and the payload) until a cycle in which `valid && ready` are both high; only then may `valid` deassert.
- **Payload-stable rule** — While `valid` is asserted and `ready` is not, every bit of the payload must remain stable cycle-for-cycle until the handshake completes.
- **Skid buffer** — A 2-deep register-slice buffer inserted on a handshake path to break a combinational dependency from downstream `ready` to upstream `ready` (and to register the downstream outputs). Allows `o_ready` to be registered without dropping throughput. Anything deeper than 2 with the same backpressure semantics is a FIFO, not a skid buffer.
- **Register slice** — Synonym for skid buffer when the framing emphasizes timing-closure intent (rather than flow-control intent). The verilog-axis "register" / wb2axip "skidbuffer" / FPGADesignElements `Pipeline_Skid_Buffer` are the same pattern.
- **FWFT (First-Word Fall-Through)** — _Refined Phase 3 (relationship was previously backwards)._ A FIFO output mode where the first word is presented at the output without an explicit read pulse. A skid buffer is the **smallest** FWFT pipeline buffer (depth 2) — i.e. a depth-2 FWFT FIFO with backpressure is functionally a skid buffer; deeper FWFT FIFOs are general buffers and live in doc 22.
- **Backpressure** — The consumer's ability to delay a transfer by de-asserting `ready`. Required for composability.
- **Backpressure freeze** — When stage K's downstream stalls, every upstream stage's `(data, valid)` pair must freeze **together** under a single shared enable; freezing data while letting `valid` advance (or vice versa) loses data or fabricates bubbles.
- **`(data, valid)` pair** — Two flops in the same pipeline stage: one holds the payload, the other holds whether the payload is meaningful this cycle. Identical enable, identical reset, identical depth across the pipeline.
- **Pipeline register** — A flop (or bank of flops) inserted between two combinational regions to break a critical path. Added only when a measured TimeQuest path requires it (resource-economy rule); always paired with a `valid` partner flop.
- **Cycle-level schedule** — The deliverable for any pipelined block: a stage × cycle table naming which datum lives in each stage at each cycle (and whether its `valid` is set). The schedule is the source of truth; mismatches with simulation indicate a bug in one or the other.
- **Retiming / register balancing** — A Fitter transformation that moves *existing* flops across combinational logic to equalize stage delays. Cannot create stages that don't exist in source; if you need a new pipeline stage, add it in RTL.
- **AXI-Stream sideband (`tdata` / `tvalid` / `tready` / `tlast` / `tkeep` / `tid` / `tdest` / `tuser`)** — The verilog-axis port shape; `s_axis_*` prefixes denote the slave (sink) side, `m_axis_*` the master (source) side. `tlast` marks end-of-packet; `tkeep` is per-byte valid; the rest are protocol sideband that obey the same payload-stability rule as `tdata`.

## Timing and SDC

- **fmax** — The maximum clock frequency at which all paths meet setup. Reported by TimeQuest after fitting.
- **Setup time** — The time before a clock edge by which an input must be stable.
- **Hold time** — The time after a clock edge during which an input must remain stable.
- **Slack** — The margin by which a path meets a timing requirement. Positive = OK; negative = violation.
- **Critical path** — The path with the worst (smallest or most negative) slack. fmax is set by the critical path's delay.
- **SDC (Synopsys Design Constraints)** — The constraint language Quartus uses for clocks, I/O delays, and exception paths.
- **TimeQuest / Timing Analyzer** — Quartus's static timing analyzer (rebranded "Timing Analyzer" in newer versions; same tool). Reports setup, hold, recovery, removal, and MTBF.
- **`create_clock`** — SDC command defining a clock and its period at a source pin. Required for every clock entering the design.
- **`create_generated_clock`** — SDC command for a derived clock that `derive_pll_clocks` cannot see (rare; typically a fabric divider — which itself is discouraged).
- **`derive_pll_clocks`** — SDC command that automatically creates generated-clock constraints for every PLL output in the netlist. The recommended form for PLL-fed clocks.
- **`derive_clock_uncertainty`** — SDC command that applies the device-model inter-/intra-clock and I/O uncertainties; without it, slack numbers are optimistic.
- **`set_input_delay` / `set_output_delay`** — SDC commands telling the timing analyzer about board-level launch/capture delays at I/O pins; both require `-max` and `-min`.
- **`set_clock_groups -asynchronous`** — SDC command declaring two (or more) clock domains as mutually asynchronous, so the analyzer does not time paths between them. The preferred form for whole groups of unrelated clocks.
- **`set_false_path`** — SDC exception telling the analyzer a path is never timing-critical. Used for static configuration paths and for asynchronous reset deassertion; cut into the synchronizer-flop endpoints (`-to`) rather than from the reset port (`-from`) when the port has other loads.
- **`check_timing`** — SDC/TimeQuest command that reports unconstrained-path issues: missing clocks, missing I/O delays, registers unreachable from a clock. Must be clean before claiming closure.
- **Virtual clock** — A `create_clock` with no `-source`; used to describe an external launch reference for source-synchronous I/O when the launching clock doesn't enter the FPGA on a pin.
- **Recovery / removal** — Async-deassertion analogs of setup/hold for reset and async-clear signals.
- **Registered I/O** — Placing the input or output register physically in the IOE. Improves input-setup and output-clock-to-pad timing; constrained via Quartus QSF assignments (`FAST_INPUT_REGISTER`, `FAST_OUTPUT_REGISTER`, `FAST_OUTPUT_ENABLE_REGISTER`), not RTL.

## FSMs and control

- **One-block FSM** — Entire FSM (state register, next-state, outputs) in a single `always_ff`. Compact but harder to constrain output timing and to maintain.
- **Two-block FSM** — `always_ff` for the state register; `always_comb` for next-state and outputs combined. The bundle's default.
- **Three-block FSM** — `always_ff` for state register; one `always_comb` for next-state; another `always_comb` (or a second `always_ff` for registered outputs) for the output decoder.
- **One-hot encoding** — N states use N flops; exactly one bit is set per state. Cheap mux outputs, more registers, fewer logic levels. Cummings's "one-hot with zero-idle" variant uses the all-zero codepoint as the reset/idle state.
- **Binary encoding** — N states use `$clog2(N)` flops. Fewer registers, more decoding logic.
- **Gray-encoded FSM** — Successive states differ in one bit. Used historically for low-power; rarely needed on FPGA.
- **`STATE_MACHINE_PROCESSING` (QSF)** — Project-wide Quartus assignment that controls how the FSM extractor encodes states (`Auto`, `One-Hot`, `Minimal Bits`, `User-Encoded`, ...). Set to `User-Encoded` when the source enum values must survive into the Fitter report (era-faithful work).
- **`state_machine_encoding` attribute** — Per-entity Quartus attribute that pins the encoding for one state register without affecting the rest of the project.
- **Microcoded control** — Control implemented as a ROM addressed by a microPC, with output bits driving datapath control. The ROM word splits into `{next_state, control_word}`; the synchronous ROM read inserts one extra cycle of next-state latency compared to a hardwired decoder. Used in era-faithful emulations of chips with microcoded silicon.
- **Hardwired control** — Control implemented as case-statement FSMs (PLA/random-logic equivalent). The default on FPGA and for emulations of chips with hardwired silicon.
- **`upc` (microprogram counter)** — The state-register equivalent in a microcoded controller; addresses the microcode ROM.
- **`uir` (microinstruction register)** — Holds the latched ROM read; partitioned into the next-`upc` field and the datapath-control field.

## Cyclone V memory inference

- **Read-during-write (RDW)** — The behavior a synchronous RAM exhibits when one port reads the same address another port is writing on the same cycle. Two modes Quartus infers from the template form:
  - **Old-data RDW** — The read returns the pre-write value. Inferred from **nonblocking** assignments in the canonical single-clock RAM template. Default for FIFO bodies, line buffers, frame buffers.
  - **New-data RDW (write-forwarding)** — The read returns the just-written value via inferred forwarding logic. Inferred from **blocking** assignments in the canonical template.
- **Simple-dual-port (SDP)** — One write port + one read port (independent addresses). Cheaper than true-dual-port; Quartus packs two SDP memories per M10K in some configurations.
- **True-dual-port (TDP)** — Two ports that each can read or write. Required only when both ports actually write; otherwise SDP suffices.
- **Byte enable** — Per-byte conditional writes inside the canonical `always @(posedge clk)` block (one `if (byteena[i]) mem[addr][8*i +: 8] <= d[8*i +: 8];` per byte). Supported on M10K.
- **`ramstyle` attribute** — Quartus attribute on a storage declaration that overrides the inference target: `"M10K"`, `"MLAB"`, `"logic"`, or `"no_rw_check"` (relax read-during-write checks; influences MLAB vs M10K selection).
- **`.mif` / `.hex` init file** — Memory-initialization files referenced by `INIT_FILE` attribute or `$readmemh` / `$readmemb` at elaboration time. The synthesis-recognized way to ship ROM contents.

## DSP and arithmetic patterns

- **Multiply-add** — `(a*b) + (c*d)` (or a single `(a*b)+c`) written with registered inputs and a registered sum. Inferred by Quartus into one DSP block's multiplier-adder atom.
- **Multiply-accumulate (MAC)** — `acc <= acc + (a*b)`. Inferred into the DSP block's accumulator atom; registers around the multiply and the accumulator are mandatory for full-rate inference.
- **Strength reduction** — Synthesizer rewriting of `*`, `/`, or `%` by a synthesis-time constant into shifts and adds (or, for non-power-of-two constant divisors, the multiply-by-reciprocal pattern). Reliable when the constant is visible at elaboration; defeated when the constant flows through an unrecognized register.
- **Barrel shifter** — A wide multiplexer network implementing variable `<<` or `>>`. Synthesizes to LUT logic; cost is significant at width ≥ 8 and grows with operand width and shift-amount width. Constant shifts reduce to rewiring (zero cost).
- **Restoring divider** — The iterative implementation Quartus infers for `/` and `%` with a non-constant divisor: a chain of conditional-subtract steps over multiprecision adder/subtractors, latency `≈ WORD_WIDTH / STEP_WORD_WIDTH` cycles per bit. **Forbidden on the critical path**; reformulate or use Intel Divider IP.
- **Saturation / wrap** — Explicit overflow policy on accumulators. Saturating addition clamps to `[limit_min, limit_max]` instead of wrapping; the saturating-adder pattern wraps a normal carry-chain adder with two signed limit comparisons.
- **One-hot mux (Annul-then-OR)** — N-input multiplexer built by ANDing each input word with its one-hot selector bit (Annul) and OR-reducing across inputs (Word_Reducer). Avoids the binary-mux decoder layer; preferred for N > 16 inputs.
- **Wide comparator** — `==` / `!=` / `<` / `<=` / `>` / `>=` on operands ≥ 16 bits. Derived from a single subtraction's `difference`/`carry_out`/`overflow` flags; pipelining advised on the critical path because the delay equals a wide adder.

## Verification

- **Testbench** — Non-synthesizable module that drives a DUT and checks outputs. Lives in a `tb/` directory adjacent to the RTL.
- **Scoreboard** — A pair of queues (stimulus + reference-model output) plus a final compare; the canonical verification artifact for handshake-based modules.
- **Reference model** — A behavioral implementation of the DUT's expected output stream, computed independently from the same stimulus and compared against the captured DUT outputs.
- **SVA (SystemVerilog Assertions)** — Concurrent and immediate assertion language built into SV. Used for handshake invariants in this bundle.
- **assert / assume / cover** — SVA directives. `assert` checks a property; `assume` declares a property as input to formal (or as a stimulus constraint in simulation); `cover` measures whether a property ever holds. Never swap `assert` and `assume` — a swapped `assume` passes vacuously.
- **Immediate assertion** — `assert(condition)` inside an `always` block; checks at the moment of execution.
- **Concurrent assertion** — `assert property (sequence)` outside a block; checks across cycles. Preferred form for `bind`-able properties.
- **`bind`** — SV directive that inserts an assertion-only module instance into every instance of a target module, with the same name resolution as if it were textually inside. Keeps assertions out of synthesizable RTL.
- **`$past` / `$stable` / `$rose` / `$fell`** — SVA sampled-value system functions: `$past(x)` is x at the previous clocking event; `$stable(x)` is `x == $past(x)`; `$rose` / `$fell` detect 0→1 / 1→0 transitions across the clocking event.
- **`disable iff (expr)`** — SVA clause that suppresses a property whenever `expr` is true; standard idiom is `disable iff (!aresetn)` to silence properties during reset.
- **`|->` / `|=>`** — Overlapped vs. non-overlapped implication. `|->` ends the antecedent on the same cycle the consequent starts; `|=>` ends it one cycle earlier (consequent describes next cycle).
- **No-valid-drop / payload-stable / reset-clean (the three handshake SVAs)** — The bundle's required SVA triple per handshake interface: `valid` does not drop without a transfer; payload is `$stable` while `valid && !ready`; `valid` is low for at least one cycle after reset deasserts.
- **Reset coverage** — Confirmation in simulation that every register has been observed at its reset value and at a non-reset value before integration.
- **cocotb** — Python testbench framework driving RTL through ModelSim or Verilator. A valid alternative to native-SV testbenches but **outside the Quartus 18.1 toolchain**; adopt only if the project maintains a separate Python verification environment.

## Quartus tooling and reports

- **Quartus Prime Standard / Lite** — The Intel FPGA toolchain. Standard and Lite differ in IP availability and capacity, not in HDL coding recommendations.
- **Analysis & Synthesis** — First stage of Quartus compile; converts RTL to a vendor-neutral netlist.
- **Fitter** — Quartus's place-and-route. Places ALMs, DSP blocks, M10Ks into the device and routes between them.
- **TimeQuest** — Quartus's static timing analyzer (rebranded "Timing Analyzer"; same tool).
- **QSF (Quartus Settings File)** — Holds project-level settings, pin assignments, instance assignments, and synthesis attributes.
- **Synthesis report (`.map.rpt`)** — Output of Analysis & Synthesis; tells you how RAM/DSP inference resolved, what registers were merged/removed, what warnings were raised about coding style, and which FSMs were extracted with what encoding.
- **Fitter report (`.fit.rpt`)** — Output of place-and-route; tells you final resource utilization per entity, IOE placement, clock-network usage, routing congestion.
- **Resource Utilization by Entity** — The Fitter section that names ALM / M10K / MLAB / DSP counts per module. The ground-truth check that inference targeted the intended primitive.
- **State Machine list** — Synthesis-report section enumerating extracted FSMs with state count and encoding. A missing FSM means Quartus did not extract it (coding-style violation).
- **Removed registers** — Synthesis-report optimization line: a register whose consumers were all unreachable was deleted. Either intentional (document it) or a justification-(reg-a) violation.
- **Merged registers** — Synthesis-report line: two or more registers with identical next-state and equivalent fanout were combined. Usually a mirror-copy anti-pattern (#29); rarely intentional redundancy.
- **Stuck at 0 / Stuck at 1** — Synthesis-report line: a register's value was provably constant; synthesis replaced it with the constant. Indicates a dead source or a wrong consumer.
- **Inferred latch** — Synthesis warning when an `always_comb` left an output undriven on some path; the bundle's defaults-at-top + mandatory `default:` discipline makes this warning a bug, not an acceptable side effect.
- **Combinational loop** — Synthesis warning when a pure-combinational signal appears in its own RHS cone; the design's timing model breaks until a register is inserted on the loop.
- **Report Metastability** — TimeQuest report listing every recognized synchronizer chain with an MTBF estimate. A multi-clock-domain signal that does *not* appear here is an un-synchronized crossing — investigate immediately.
- **Report Setup / Report Hold / Report Recovery / Report Removal / Report Fanout** — The canonical TimeQuest sub-reports for worst-case setup slack, worst-case hold slack, async-reset-deassert recovery/removal, and top-fanout signal listings.
- **`FAST_INPUT_REGISTER` / `FAST_OUTPUT_REGISTER` / `FAST_OUTPUT_ENABLE_REGISTER`** — QSF instance assignments that force the named pin's input/output/output-enable register into the IOE, collapsing pad-to-register delay to the IOE's fixed minimum.

## Era-faithful microarchitecture

- **Cycle accuracy** — The property that an emulation core's externally observable behavior at each clock matches the original silicon, cycle-for-cycle at the pin. Required for compatibility with software that exploits the original chip's timing.
- **Cycle-accuracy boundary** — The bundle's [I] contract distinguishing locked external observables (pin-level bus phases, memory read/write latency, IRQ-ack cycles, refresh, video timing) from free internal pipelining. Internal pipeline registers are allowed if and only if every externally observable cycle still matches the original; pipelining that shifts the pin schedule is forbidden.
- **Mirror-the-chip check** — The pre-RTL gate for emulation cores: the plan must name the chip's part number, datapath width, control style (microcoded vs hardwired), bus structure, memory port topology, and external cycle counts per operation. Every RTL module's top comment cites the original-chip subsystem it mirrors.
- **Single-bus architecture** — An internal datapath where multiple sources drive one shared bus through a one-hot-select mux (the synthesizable equivalent of a tri-state bus — which is forbidden in Cyclone V fabric). The grant signal is one-hot; non-granted requesters wait, exactly as the original chip's software experienced.
- **Register file** — A small array of architectural registers in the original chip. Typically inferred to flops (≤ 16 entries with multi-port read), MLAB (16–~64 entries), or M10K (larger) based on size and port count. Era-faithful emulation usually keeps small files in flops to preserve parallel reads.
- **ALU sharing** — Using one ALU across multiple opcode subcycles instead of replicating it. The era's default; preserved in faithful emulation even when fmax headroom would tolerate parallelism.
- **Era-violating modernization** — Any of: replacing a shared resource with N parallel copies, adding a parallel barrel shifter where the original used iterative shift-add, using a DSP block where the original lacked one, widening the datapath beyond the original chip's width, or using a multi-port M10K where the original had single-port + bus arbitration. See doc 17 §7 for the named anti-patterns (#32–#37).

## Bundle conventions (cross-doc)

- **Pre-RTL microarchitecture plan** — The document an agent must produce before any RTL: names clocks, reset behavior, throughput target, latency budget, datapath widths/signedness/saturation, resource strategy, flow-control mechanism, pipeline cuts, and (for emulation) the original-chip's external interface. A reviewer can answer those questions without reading code.
- **Four-justifications check** — The resource-economy rule (doc 16): every register must claim one of (a) holds state across cycles, (b) breaks a critical combinational path, (c) crosses a clock domain, (d) implements a protocol pipeline stage; every bus bit must claim (a) consumed downstream, (b) required by a protocol field, (c) reserved with explicit forward-compatibility comment.
- **Justification comment** — A short inline `// Justification: (reg-a/b/c/d) …` above every register declaration; bundle convention introduced so the four-justifications check survives code review.
- **Claim labels [C] / [V] / [O] / [I]** — Every load-bearing factual sentence in §2/§3/§6 of each topic doc carries one of: **Contract** (strictly required by upstream framework/protocol/synthesis), **Convention** (common pattern not strictly required), **Observed** (present in a specific named implementation at a specific revision), **Inference** (synthesized from multiple sources, no single citation establishes it).

---

_Entry count this snapshot: 165 across all categories (up from ~60 at the initial cut). Phase 3 added ~105 terms surfaced by topic-doc usage and split the conflated MCP entry into two distinct senses. Existing entries left intact except for the three flagged inline as refined: MCP (split) / FWFT (relationship clarified) / `5CSEBA6U23I7` (DDR3 location sharpened)._
