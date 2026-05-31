# Era-Faithful Microarchitecture

> Bundle version: 2026-05-19
> Pinned commits: see [references/MANIFEST.md](../references/MANIFEST.md) — FPGADesignElements, fpgacpu coding/system standards, Cummings SNUG 1998, Intel Cyclone V product/handbook live URLs.
> Load with: [10-hardware-mindset-and-microarchitecture.md](10-hardware-mindset-and-microarchitecture.md), [14-finite-state-machines.md](14-finite-state-machines.md), [15-pipelines-and-latency-thinking.md](15-pipelines-and-latency-thinking.md), [16-resource-and-state-economy.md](16-resource-and-state-economy.md), [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md), [31-dsp-inference-cyclone-v.md](31-dsp-inference-cyclone-v.md), [32-arithmetic-patterns-and-operator-cost.md](32-arithmetic-patterns-and-operator-cost.md)
> Status mix: heavy [V] and [I]; few [C]. **No single corpus source mandates "match the era" — that is the bundle's contract, not Intel's.** Inferred claims derive from Cummings FSM (encoding/state-style mechanism), FPGADesignElements (arbiter / register-file / shifter primitives), FPGACPU verilog standard (tristate-to-mux substitution; mux-width caveats), Cyclone V handbook/product table (modern resource budget framing), and the bundle's existing rough notes in `library/topics/01_hardware_mindset_parallelism.md`. The one firm [C] is "tristates inside the FPGA fabric are not synthesizable on Cyclone V" (Quartus design recommendations, live URL).

## 1. Purpose & one-line summary

An emulation core's RTL **describes the original chip's microarchitecture**; it does not implement a software emulator's algorithm. The **pre-RTL plan** (see [10-hardware-mindset-and-microarchitecture.md](10-hardware-mindset-and-microarchitecture.md)) is the reverse-engineering output of the original chip's bus/control/datapath structure; the RTL is its faithful expression on Cyclone V. This doc establishes the **mirroring contract** and the **cycle-accuracy boundary**: external-interface cycle counts are locked to the original; internal pipelining is allowed if and only if every observable external cycle still matches.

This is the architecture-mirroring companion to [16-resource-and-state-economy.md](16-resource-and-state-economy.md). Where 16 enforces bit-level economy by inspection, 17 enforces era-faithful structural choice by mirroring.

This doc is unusual: no single corpus source establishes "match the era." The doc constructs its case from many sources, each contributing one piece, and most claims here are [V] or [I] rather than [C]. Reviewers are owed honesty about the inferential chain — every [I] in §2 names which sources support it.

Deliverables this doc produces in the consuming agent:

1. A **mirror-the-chip check** applied during the pre-RTL plan (§8).
2. A **cycle-accuracy boundary** distinguishing observable external timing (locked) from internal pipelining (free) (§2, §4).
3. A **checklist of era-violating modernizations** to avoid (§7 anti-patterns #32–#37, with cross-refs #25, #26).

What this doc does **not** cover (deferred via Load with):

- The pre-RTL planning framework and hardware-mindset thesis → [10](10-hardware-mindset-and-microarchitecture.md).
- Bit-level resource economy (every register/bus bit justifies itself) → [16](16-resource-and-state-economy.md).
- FSM coding patterns and state encoding mechanics → [14](14-finite-state-machines.md).
- Pipeline construction mechanics and valid-follows-data → [15](15-pipelines-and-latency-thinking.md).
- M10K-vs-MLAB-vs-flops decision (only the era angle surfaces here) → [30](30-memory-inference-cyclone-v.md).
- DSP-vs-iterative-shift-add decision (only the era angle surfaces here) → [31](31-dsp-inference-cyclone-v.md).
- Arithmetic operator cost on Cyclone V → [32](32-arithmetic-patterns-and-operator-cost.md).
- Clocking and reset strategy → [11](11-clocking-resets-and-cyclone-v-clock-networks.md).
- **The MiSTer framework wrapper (`sys_top.sv`, `hps_io`, status word, framework video/audio conventions) is explicitly out of bundle scope.** Era-faithful cores written under this discipline are integrated into MiSTer by the framework wrapper, but the wrapper itself is a separate concern handled outside this bundle.

**Resource budget framing.** The Cyclone V `5CSEBA6U23I7` on the DE10-Nano has ~110K ALMs, ~5.6 Mbit of M10K+MLAB embedded memory, and 112 variable-precision DSP blocks. You have plenty — **don't burn it on era-violating parallelism.** The actual mapping decisions belong to [16](16-resource-and-state-economy.md), [30](30-memory-inference-cyclone-v.md), [31](31-dsp-inference-cyclone-v.md), and [32](32-arithmetic-patterns-and-operator-cost.md).

## 2. The contract (must-obey)

Every rule below carries exactly one label. For every [I] rule, the inference chain is named in the same paragraph so reviewers can audit the argument.

- **[I] Mirroring contract.** An emulation core's RTL describes the original chip's microarchitecture: its datapath width, its bus structure, its control style, its memory port topology, and its external cycle counts. It does not implement a software emulator's main loop. *Inference chain:* no single source establishes this; it is the bundle's convention, supported by `library/topics/01_hardware_mindset_parallelism.md` ("Avoid Software-Shaped RTL" red-flag list) and by the FPGACPU `system_design_standard.html` framing that hierarchy should reflect structure (see §6).

- **[I] Cycle-accuracy boundary.** External-interface cycle counts (pin-level bus phases, memory read/write latency, IRQ-ack cycles, refresh timing) are **locked** to the original chip. Internal pipelining inside a single externally-observable operation is **allowed if and only if** every external observable still matches the original cycle-for-cycle at the pin. *Inference chain:* the locking rule is the bundle's mirroring contract (no source); the internal-pipelining mechanism is covered by [15-pipelines-and-latency-thinking.md](15-pipelines-and-latency-thinking.md) (valid-follows-data, registered slices). The boundary itself is [I].

- **[I] Resource sharing is the era's default.** One ALU multiplexed across opcode subcycles, not N parallel adders; one shifter operated over multiple cycles, not a single-cycle barrel; one bus with one driver per cycle, not multiple parallel datapaths. *Inference chain:* `library/topics/01_hardware_mindset_parallelism.md` ("Share hardware when … an expensive resource is scarce") + FPGADesignElements `Arbiter_Priority.v` for the arbitration mechanism that implements sharing on FPGA (see §3).

- **[I] Datapath width matches the original.** An 8-bit chip emulation has an 8-bit datapath; carries and borrows extend across multi-byte operations exactly as the original did. *Inference chain:* follows from the mirroring rule; no corpus source mandates it. Marked [I].

- **[V] Memory hierarchy matches the original chip.** Small architectural register files (≤ 16 entries) map to flops (cite FPGADesignElements `Register_Pipeline.v` as the flop-bank shape); intermediate register files (16 – ~64 entries) map to MLAB; large RAM maps to M10K. *Source:* [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md) owns the full decision; the era angle is that an original chip's register file was flops/latches, not a block RAM. Marked [V] because it is convention; the specific size thresholds are [V] in doc 30.

- **[V] Control style matches the original chip.** A chip that used a microcode ROM gets a microcoded controller (ROM + sequencer + microinstruction register + field decoder); a chip that used hardwired PLA control gets a hardwired FSM in the doc-14 sense. *Source:* the state-encoding mechanism is Cummings SNUG 1998 (one-hot / one-hot-with-zero-idle / binary, lines 140–177 of the extract). **The framing "microcoded vs hardwired" is the bundle's [I] above the encoding choice — Cummings does not use these terms.** Cite Cummings for the encoding piece only.

- **[V] Single-bus architectures use a one-hot-select mux, not literal tristates.** If the original chip has one internal data bus with multiple potential drivers (ALU output, memory-read latch, immediate field from instruction register, etc.), implement this on FPGA as a wide one-hot-select multiplexer driven by a one-hot grant signal. *Source:* FPGACPU `verilog_coding_standard.html` lines ~390–410 (tristate inference is restricted to top-level I/O pins; the substitution for internal buses is implicit in the doc's discouragement of internal tristates).

- **[V] External interface timing is locked; internal pipelining is free within that boundary.** The set of operations exposed at the pin (memory read, memory write, IRQ ack, DMA, refresh) must take the same number of cycles as the original. Inside a single externally-observable cycle, pipeline registers may be added if the externally-observable result is unchanged. *Source:* [15-pipelines-and-latency-thinking.md](15-pipelines-and-latency-thinking.md) for the mechanism; the locking discipline is [I] (bundle convention).

- **[C] Tristates inside the FPGA fabric are not synthesizable on Cyclone V; the one-hot mux substitution is required, not optional.** Tristate buffers exist only at I/O pins (IOE primitives); any internal tristate is illegal and must be rewritten as a multiplexer. *Source:* Quartus Standard design recommendations (live URL: <https://www.intel.com/content/www/us/en/programmable/documentation/mwh1409960181641.html> — captured locally as `references/raw/intel/quartus_standard_design_recommendations_index.html`, which is an app shell; the rule is also reflected in FPGACPU `verilog_coding_standard.html` lines ~390–410, where tristate inference is documented as a CAD-tool risk even for top-level pins).

**Pre-RTL plan addendum for emulation cores [I].** The plan (per doc 10) must additionally name for an emulation core:

1. The original chip's identity (part number, die revision if known, documented schematic/die-shot reference).
2. The chip's datapath width (8, 16, ...).
3. The chip's control style (microcode ROM, hardwired PLA, distributed control).
4. The chip's bus structure (single internal bus, multiple buses, dedicated paths).
5. The chip's memory port topology (single-port RAM + arbitration, multi-port RAM, register file in flops).
6. The chip's external cycle counts per operation type (memory read, memory write, IRQ ack, refresh, DMA, …).

*Inference chain:* no single corpus source defines this addendum; it is the bundle's convention to make the mirroring check auditable. Each item is what reviewers will look for at the post-RTL gate (§8).

## 3. Constructs / signals / API reference

This is an architectural-mindset doc, not a primitive catalog. §3 enumerates the era-mirroring decisions and the FPGA-side primitives that implement each. Every excerpt is preceded by a single-line citation comment.

### 3.1 Era-mirroring decision table

| Original-chip property | Era-faithful FPGA expression | Rationale | Label |
|---|---|---|---|
| 8-bit datapath | 8-bit registers, 8-bit ALU; multi-byte ops via carry over multiple cycles | Mirrors original silicon; software depending on flag-byte ordering still works | [I] |
| 1 shared ALU per opcode | One ALU instance + operation-select register driven by opcode decode | Era default; saves area; preserves opcode-subcycle timing | [I] |
| Single-port memory + bus arbitration | Single-port M10K + `Arbiter_Priority.v` granting one requester per cycle | Mirrors the era's bus arbitration sequencing | [V] (FPGADesignElements `Arbiter_Priority.v`) |
| 1-bit-per-cycle shifter inside a multi-cycle FSM | `Bit_Shifter.v` with `WORD_WIDTH=1`-style behavior, gated by a shift-count down-counter | The era used multi-cycle shifts because barrel shifters were expensive in silicon, not because shift-add is fast | [V] (FPGADesignElements `Bit_Shifter.v` + cross-ref [31](31-dsp-inference-cyclone-v.md)) |
| Microcoded control (ROM + microPC) | ROM (init from `.mif`) → microinstruction register → field-decoder fanout to datapath control | Mirrors the chip's control style; ROM contents are the chip's microcode | [I] (Cummings encoding only) |
| Hardwired control (PLA/random logic) | Parameterized `enum`-typed FSM per [14](14-finite-state-machines.md) | Cummings encoding choices apply directly | [V] (Cummings SNUG 1998) |
| Single internal data bus with N drivers | N-way one-hot-select mux | Synthesizable substitute for tristate bus | [V] (FPGACPU `verilog_coding_standard.html`) + [C] for the no-internal-tristate rule |
| Iterative shift-add multiply | Conditional-add multiplier built from `Bit_Shifter.v` + `Adder_Subtractor_Binary.v` over N cycles | The era did not have DSP blocks; mirroring preserves cycle count | [V] cross-ref [31](31-dsp-inference-cyclone-v.md) |

### 3.2 Single-bus + one-hot-select mux (the tristate substitute)

The FPGACPU verilog coding standard documents that tristate inference is restricted to top-level I/O pins, and that even at the top-level the CAD tool may convert it to ordinary logic if the module is not at the top of the hierarchy. The relevant excerpt:

```verilog
// references/raw/fpgacpu/verilog_coding_standard.html:402-410 @ snapshot 2026-05-19
localparam WORD_WIDTH       = 36;
localparam WORD_TRISTATE    = {WORD_WIDTH{1'bZ}};

reg  [WORD_WIDTH-1:0]   data_out;
reg                     output_enable;
wire [WORD_WIDTH-1:0]   tristate_bus;

assign tristate_bus = (output_enable == 1'b1) ? data_out : WORD_TRISTATE;
```

The above pattern is the **only** legal place for `1'bZ` on Cyclone V (a top-level pin via an IOE primitive). **Internal buses with multiple drivers must be rewritten as one-hot-select muxes [C]**. For a 3-driver internal bus carrying ALU output, memory-read latch, and instruction-register immediate field, the era-faithful FPGA shape is:

```verilog
// Bundle [I] composite — no single corpus source; idiom follows from
// FPGACPU verilog_coding_standard.html lines 402-410 (tristate-to-mux substitution)
// and FPGADesignElements Arbiter_Priority.v (one-hot grant generation, lines 58-126).
logic [7:0] alu_out, mem_rd_latch, ir_imm;
logic [2:0] grant_onehot;   // {alu_drives, mem_drives, imm_drives}; exactly one bit set per cycle
logic [7:0] internal_bus;

always_comb begin
    unique case (grant_onehot)
        3'b100:  internal_bus = alu_out;
        3'b010:  internal_bus = mem_rd_latch;
        3'b001:  internal_bus = ir_imm;
        default: internal_bus = 8'h00;   // illegal: no grant or multiple grants
    endcase
end
```

A 3:1 mux is 5 input terms per bit (3 data + 2 effective selectors after one-hot decoding), well within the 6-LUT mapping target documented in the FPGACPU verilog standard (lines ~660–670 — "A 4:1 mux has 6 inputs terms (4 input bits and 2 selector bits) and so maps exactly to one 6-LUT per result bit"). Beyond 8:1, pipeline the selection per the same source.

### 3.3 Shared-ALU + arbiter pattern

The arbiter primitive that implements era-default resource sharing:

```verilog
// references/projects/FPGADesignElements/Arbiter_Priority.v:1-15 @ pinned commit
//# A Priority Arbiter

// Returns a one-hot grant bitmask of the least-significant bit set in a word,
// where bit 0 can be viewed as having highest priority. *A grant is held
// until the request is released.*

// The requestors must raise and hold a `requests` bit and wait until the
// corresponding `grant` bit rises to begin their transaction. *Grants are
// calculated combinationally from the requests*, so pipeline as necessary.
```

`Arbiter_Round_Robin.v` is the fair variant; pick based on whether the original chip favored a fixed requester (priority) or rotated (round-robin). For a CPU emulation where the ALU is the dominant requester and DMA preemption is documented in the chip, `Arbiter_Priority.v` with the requester-priority order of the original is appropriate [V].

### 3.4 Microcoded controller skeleton

```verilog
// Bundle [I] composite skeleton — no single corpus source contains this exact shape.
// Encoding of the micro-state register follows Cummings SNUG 1998 (one-hot with
// zero-idle is documented in references/extracted_text/methodology/CummingsSNUG1998SJ_FSM.txt
// lines 157-166); the ROM-plus-fanout scaffolding is the era's standard layout.

module microcoded_controller #(
    parameter int UPC_WIDTH     = 8,
    parameter int UWORD_WIDTH   = 24
) (
    input  logic                    clk, rst_n,
    input  logic [7:0]              opcode,
    output logic [UWORD_WIDTH-1:0]  control_word
);
    logic [UPC_WIDTH-1:0]   upc;          // microprogram counter
    logic [UWORD_WIDTH-1:0] urom [0:(1<<UPC_WIDTH)-1];
    logic [UWORD_WIDTH-1:0] uir;          // microinstruction register

    initial $readmemh("microcode.hex", urom);   // ROM image is the chip's microcode

    always_ff @(posedge clk) begin
        if (!rst_n) upc <= '0;
        else        upc <= uir[UPC_WIDTH-1:0];  // next-uPC field
        uir <= urom[upc];
    end

    assign control_word = uir[UWORD_WIDTH-1:UPC_WIDTH];  // datapath control fanout
endmodule
```

The microinstruction layout (fields → datapath control signals) is the deliverable of reverse-engineering the original chip's microcode ROM and is captured in the pre-RTL plan (doc 10). The skeleton above is [I] — no single corpus source contains it.

### 3.5 Hardwired controller skeleton

For chips with hardwired PLA/random-logic control, use the parameterized `enum`-typed FSM in [14-finite-state-machines.md](14-finite-state-machines.md). The one-hot encoding choice (and the one-hot-with-zero-idle variant) is documented by Cummings:

```text
// references/extracted_text/methodology/CummingsSNUG1998SJ_FSM.txt:157-166 @ snapshot 2026-05-19
       parameter [4:1] // ERROR is 4'b0000
                         IDLE = 4'd1,
                           S1 = 4'd2,
                           S2 = 4'd3,
                           S3 = 4'd4;
                  Example 4 - Parameter definitions for one-hot with zero-idle encoding
The one-hot with zero-idle encoding can yield very efficient FSMs for state machines that have
many interconnections with complex equations, including a large number of connections to one
particular state. Frequently, multiple transitions are made either to an IDLE state or to another
common state (such as the ERROR-state in this example).
```

The bundle's framing of **microcoded vs hardwired as a higher-level choice [I]** sits above this encoding choice. Pick the higher-level choice from the chip's documented control style; pick the encoding per Cummings.

### 3.6 Named constructs/signals table

| Name | Type / width / direction | Meaning | Driven by | Drives |
|---|---|---|---|---|
| `grant_onehot` | `logic [N-1:0]` (output of arbiter) | One-hot bus-grant signal; exactly one bit set per cycle | `Arbiter_Priority.v` (or `_Round_Robin`) | Bus mux select |
| `internal_bus` | `logic [W-1:0]` (combinational) | Single-bus datapath wire after one-hot mux | Bus mux | All bus consumers |
| `upc` | `logic [UPC_WIDTH-1:0]` (register) | Microprogram counter | Next-uPC field of `uir`; reset | Microcode ROM address |
| `uir` | `logic [UWORD_WIDTH-1:0]` (register) | Microinstruction register | Microcode ROM read | Datapath control fanout, next-uPC |
| `control_word` | `logic [UWORD_WIDTH-1:0]` (output) | Decoded microinstruction fields to datapath | `uir` (subrange) | ALU op-select, register-file enables, memory R/W |
| `shift_count` | `logic [$clog2(W)-1:0]` (register) | Down-counter gating the 1-bit-per-cycle shifter | Initial load from opcode operand; decrement per cycle | FSM "done" condition |
| `opcode` | `logic [7:0]` (input) | Currently-executing instruction byte | Instruction register | Microcode dispatch / hardwired FSM next-state |

## 4. Sequencing & timing

The cycle-accuracy boundary is the central timing contract:

**External (locked).** Every pin-level cycle the original chip exposes — address-phase cycles, data-phase cycles, refresh phases, IRQ-ack phases, DMA hold cycles — must occur in the same cycle count in the FPGA implementation. Software depends on this.

**Internal (free).** Inside a single externally-observable cycle, pipeline registers may be added if and only if no external observable changes. If the original chip's memory read is 2 cycles (address phase + data phase), the FPGA implementation must also be 2 cycles at the pin, but the internal address-decode + RAM-fetch may be split into sub-stages if that helps timing closure on Cyclone V.

### 4.1 6502-style memory-read worked timing

A canonical 6502-style memory read presents an address in cycle 1 and latches data in cycle 2. The external observable is exactly 2 cycles. The FPGA may optionally split address-decode into two internal pipeline registers if needed for fmax, as long as the address bus still asserts in cycle 1 at the pin.

```text
Original chip (external observable, locked):

          cycle 1            cycle 2
          ----------------+ +----------------
clk      __|‾‾|__|‾‾|__|‾‾|‾|__|‾‾|__|‾‾|__
addr_bus  XXXX[  ADDR    ]X[  next ADDR  ]X
rw        XXXX‾‾‾‾‾‾‾‾‾‾‾‾XXXXXXXXXXXXXXXX   (high = read)
data_bus  ZZZZZZZZZZZZZZZZZ[  DATA      ]ZZ  (memory drives in cycle 2)

FPGA implementation (era-faithful):

          cycle 1            cycle 2
          ----------------+ +----------------
clk      __|‾‾|__|‾‾|__|‾‾|‾|__|‾‾|__|‾‾|__
addr_bus  XXXX[  ADDR    ]X[  next ADDR  ]X   <-- pin observable: same as original
rw        XXXX‾‾‾‾‾‾‾‾‾‾‾‾XXXXXXXXXXXXXXXX
data_bus  ZZZZZZZZZZZZZZZZZ[  DATA      ]ZZ   <-- pin observable: same as original

  internal (invisible at the pin):
    addr_decode_stage1_reg ----> addr_decode_stage2_reg ----> mem_array_read
    ^- pipeline cut here for fmax; pin-level addr_bus is unaffected.
```

The "invisible at the pin" pipeline register is allowed under the cycle-accuracy boundary [I]. The mechanism (valid-follows-data, registered slice) is in [15-pipelines-and-latency-thinking.md](15-pipelines-and-latency-thinking.md); the locking rule is the bundle's mirroring contract.

### 4.2 Bus-arbitration timing for a shared resource

For a single internal bus with three drivers (ALU, memory-read latch, instruction-register immediate), the era's bus-grant model maps to FPGA as one-hot-select-driven by the arbiter. Per `Arbiter_Priority.v`, grants are combinational from requests; the requester holds its request until the transaction completes, and the grant holds for as long as the request is held. This precisely matches the era's "I drive the bus this cycle" discipline.

## 5. Minimal working pattern

A short, complete worked example demonstrating shared-ALU + single-bus on an 8-bit accumulator machine with operations {ADD, SUB, AND, OR}.

### 5.1 Wrong version (era-violating)

```systemverilog
// Bundle [I] composite, intentionally wrong shape for contrast.
// Era violation: four parallel functional units, 4:1 mux at output.
// The original 8-bit chip had ONE ALU; this implementation has four.

module alu_era_violating (
    input  logic [7:0] a, b,
    input  logic [1:0] op,        // 00=ADD 01=SUB 10=AND 11=OR
    output logic [7:0] y
);
    logic [7:0] add_y = a + b;
    logic [7:0] sub_y = a - b;
    logic [7:0] and_y = a & b;
    logic [7:0] or_y  = a | b;

    always_comb begin
        unique case (op)
            2'b00: y = add_y;     // four parallel adders/and/or run every cycle
            2'b01: y = sub_y;     // three of the four results are thrown away
            2'b10: y = and_y;     // <-- ERA VIOLATION
            2'b11: y = or_y;
        endcase
    end
endmodule
```

The version above produces correct results, closes timing easily, and uses ~3× the combinational adder/and/or area of the original. **The original chip had one ALU.** Mirroring requires the era-faithful shape below.

### 5.2 Right version (era-faithful)

```systemverilog
// Bundle [I] composite. ALU primitive references:
//   references/projects/FPGADesignElements/Adder_Subtractor_Binary.v (cite via 32-arithmetic).
// Operation-select register driven by opcode decode; one ALU instance.
// Cycle count matches the original chip's 2-cycle ALU-op timing (issue + result).

module alu_era_faithful (
    input  logic       clk, rst_n,
    input  logic       op_valid,      // issue strobe from decoder
    input  logic [7:0] a, b,
    input  logic [1:0] op,
    output logic [7:0] y,
    output logic       y_valid        // asserts cycle after op_valid
);
    logic [1:0] op_r;
    logic [7:0] a_r, b_r;

    // Cycle 1: latch operands and op (mirrors the original chip's
    // "operands onto the bus" cycle).
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            op_r    <= '0;  a_r <= '0;  b_r <= '0;  y_valid <= 1'b0;
        end else begin
            y_valid <= op_valid;
            if (op_valid) begin
                op_r <= op;  a_r <= a;  b_r <= b;
            end
        end
    end

    // Cycle 2: one shared ALU computes the selected op (mirrors the chip's
    // "ALU drives bus" cycle). Single 8-bit adder/sub plus single AND/OR gate.
    logic [7:0] addsub_y;
    assign addsub_y = (op_r == 2'b01) ? (a_r - b_r) : (a_r + b_r);

    always_comb begin
        unique case (op_r)
            2'b00, 2'b01: y = addsub_y;       // shared adder/subtractor
            2'b10:        y = a_r & b_r;      // shared AND/OR (1 LUT/bit either way;
            2'b11:        y = a_r | b_r;      // separate gates only because no shared mux saves anything for 1-LUT ops)
            default:      y = 8'h00;
        endcase
    end
endmodule
```

**Cost vs parallel:** +1 cycle of latency per ALU op (operand-latch then result), which matches the original chip's documented 2-cycle ALU timing.

**Save vs parallel:** ~3× the combinational adder/and/or area is reclaimed. One shared 8-bit add/sub unit vs four parallel functional units; the saved ALMs are available for the rest of the core. On Cyclone V's `5CSEBA6U23I7`, this is a small fraction of total ALMs, but the discipline scales: a CPU emulation has dozens of arithmetic operations and the per-op area discipline compounds.

**Cycle-accuracy:** the external pin-level behavior matches the original chip — `y_valid` asserts on the cycle the original chip would have driven its result onto the bus. This is the contract that makes the area cost acceptable; software written for the original chip continues to work.

The single-bus three-driver mux pattern shown in §3.2 composes with the above ALU to form a complete accumulator-machine datapath. A full worked-example datapath is deferred to a future revision (or to a `library/topics/` reference design); the contract is what this doc owns.

## 6. Common variations across implementations

- **[O] FPGADesignElements style:** explicit shared-resource primitives — `Arbiter_Priority.v`, `Arbiter_Round_Robin.v`, single-port RAM primitives, `Bit_Shifter.v`. The building blocks the era's chips were composed of, packaged as parameterized SystemVerilog modules. *Source:* `references/projects/FPGADesignElements/`. This is the bundle's preferred starting point for era-faithful cores because each primitive corresponds to one die-block of an original chip.

- **[O] verilog-axis style:** shared resources behind ready/valid handshakes — the modern stream-arbitration shape. *Source:* `references/projects/verilog-axis/`. **Era contrast:** the original chips' bus-grant model does not have ready/valid — control is via fixed-timing bus phases or microcode sequencing. Era-faithful cores adopt the bus-grant shape inside the chip-boundary and may use ready/valid only at the host-FPGA boundary (e.g., where the emulation core meets the framework wrapper). Mixing the two inside the core is an era violation.

- **[O] lowRISC / Ibex style:** SystemVerilog packed structs for microinstruction fields, parameterized FSMs, ASIC-oriented coding conventions. *Source:* `references/projects/lowrisc-ibex/` (and equivalent ASIC-style designs). Maps cleanly to a microcoded controller's microinstruction layout: declare a packed struct per microinstruction with named fields, store as `[$bits(microinstr_t)-1:0]` words in the ROM, and assign field-by-field to datapath controls.

- **[V] Documented vs undocumented chip conventions.** When the original chip's microarchitecture is well-documented (e.g., the 6502 via Visual6502 die-shots, the Z80 via Sean Riddle's reverse-engineering work), cite the documented die-shot or schematic and treat it as the spec. When the chip is undocumented, the pre-RTL plan reverses from observed behavior (software-driven cycle-trace observation of real silicon) and marks each architectural inference as [I]. *Source:* bundle convention; no single corpus source mandates this distinction.

## 7. Anti-patterns (mistakes that compile but break)

This doc owns the primary treatment of **#32, #33, #34, #35, #36, #37**, and reinforces from the era angle **#25** and **#26** (primary homes in [30](30-memory-inference-cyclone-v.md) and [31](31-dsp-inference-cyclone-v.md) respectively).

### #32 — Replaced a shared resource with N parallel copies when shared closed timing

**Symptom:** synthesis report shows N adders / shifters / AND-OR units where the chip's documented schematic shows one; ALM area is several × the era-faithful baseline; fmax is comfortably above target but software that depends on per-cycle bus contention (e.g., DMA stalling the CPU) behaves wrong.
**Cause:** "shared closed timing, but I un-shared it for area/fmax headroom and the tests still passed." The era-mirroring rule was violated: closing timing is not a license to violate the era. The shared resource implies bus-arbitration timing that the chip's software depends on.
**Fix:** revert to shared + arbiter (`Arbiter_Priority.v` or `Arbiter_Round_Robin.v`). If fmax is the real problem, add an internal pipeline stage inside the shared-resource operation **without changing the external cycle count** (§4.1). If timing still does not close, the original chip's frequency target is lower than the FPGA clock — divide the FPGA clock or run the era-faithful core on a slower derived clock.
**Citation:** FPGADesignElements `Arbiter_Priority.v` (mechanism); [I] for the era-faithfulness rule itself.

### #33 — Added pipeline stages that change observable cycle counts at the chip's external interface

**Symptom:** simulation traces of pin-level signals (address bus, data bus, R/W, IRQ ack, refresh) show the FPGA implementation taking N+1 cycles where the original chip took N. Software that depends on cycle-exact timing — raster split-screen demos, DPCM audio, copy-protection routines, DMA — fails or glitches.
**Cause:** internal pipelining leaked across the external-interface boundary. The cycle-accuracy boundary (§2, §4) was violated: the pin-level cycle count is locked, internal pipelining is free **only if** the external observable is unchanged.
**Fix:** identify the pipeline register that delays the external observable; either move it inside an existing externally-observable cycle (so it does not add a cycle at the pin) or remove it and find timing closure another way (operand pre-decode, narrower comparators, registered I/O via QSF instead of RTL). Re-run the cycle-trace verification (§8).
**Citation:** [15-pipelines-and-latency-thinking.md](15-pipelines-and-latency-thinking.md) for the internal-pipelining mechanism; [I] for the locking rule.

### #34 — Linear "software" state machine instead of mirroring the chip's bus/control structure

**Symptom:** the RTL contains one large FSM with state names like `FETCH`, `DECODE_OPCODE`, `EXECUTE_ADD`, `EXECUTE_SUB`, ..., `WRITEBACK`, each transitioning linearly to the next — a transliteration of a software emulator's main loop. There is no separately identifiable ALU, register file, bus, or memory controller; control and datapath are fused into one `case` statement. Modules do not correspond to die-blocks of the original chip.
**Cause:** the pre-RTL plan was built from the software emulator's main loop rather than from the original chip's bus/control structure. The "Avoid Software-Shaped RTL" red-flag list in `library/topics/01_hardware_mindset_parallelism.md` (lines 58–67) and the FPGACPU `system_design_standard.html` modularity discipline ("a block diagram view of your source code") were both violated.
**Fix:** rebuild the pre-RTL plan from the original chip's documented bus/control structure: identify the microcode ROM (or PLA), the ALU, the register file, the bus(es), the memory controller, the address decoder, each as a separate module. Each module's top comment cites the original-chip subsystem it mirrors (§8). The control style choice (microcoded vs hardwired) follows the chip; FSM mechanics follow [14](14-finite-state-machines.md). **Primary home for this anti-pattern is this doc; introduce in [10](10-hardware-mindset-and-microarchitecture.md) as a mindset anti-pattern with a pointer here.**
**Citation:** `library/topics/01_hardware_mindset_parallelism.md` (red-flag list); FPGACPU `system_design_standard.html` (modularity); [I] for the era-faithfulness rule itself.

### #35 — 16/32-bit datapath in an 8-bit chip emulation

**Symptom:** the synthesis report shows 16- or 32-bit-wide ALU and bus inside a core that emulates an 8-bit chip; multi-byte operations complete in one FPGA cycle instead of being carried across multiple chip cycles; flag-byte behavior at the pin is wrong (e.g., overflow flag computed from a 16-bit result rather than from the 8-bit byte the chip actually saw).
**Cause:** the datapath width was widened "for convenience" or "to avoid manual carry handling." The mirroring rule was violated: an 8-bit chip's datapath is 8 bits.
**Fix:** narrow the datapath to the chip's documented width. Carry, borrow, overflow, and sign flags must be computed exactly as the chip computed them — over multi-byte operations, do the operation byte-by-byte over multiple cycles with explicit carry registers. The cycle count of multi-byte operations matches the original.
**Citation:** bundle convention; no single corpus source. [I].

### #36 — Multi-port memory where the original had single-port memory + bus arbitration

**Symptom:** the synthesis report shows a true-dual-port M10K (or worse, multi-read-port-from-flops) where the original chip had a single-port DRAM/SRAM with explicit bus arbitration; two operations that on the original chip would have collided on the bus (e.g., CPU fetch racing video controller refresh) instead complete simultaneously in the FPGA.
**Cause:** the FPGA's convenient dual-port M10K was used because it was easy; the era's bus arbitration sequencing was discarded.
**Fix:** instantiate single-port M10K (or single-port + simple-dual-port depending on the original chip's actual port topology — see [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md) for the M10K mode catalog), and add a bus arbiter (`Arbiter_Priority.v` or `Arbiter_Round_Robin.v`) that mirrors the original chip's grant priority. The arbiter's grant signal one-hot-selects the active requester; non-granted requesters wait, exactly as the original chip's software experienced.
**Citation:** Intel Cyclone V Device Handbook Vol 1, embedded memory section (live URL <https://docs.altera.com/r/docs/683375/current/cyclone-v-device-handbook-volume-1-device-interfaces-and-integration>, no local capture beyond app shell `references/raw/intel/cyclone_v_embedded_memory_modes.html`); FPGADesignElements `Arbiter_Priority.v`; [I] for the era-faithfulness rule.

### #37 — Parallel barrel shifter where original used a 1-bit shifter over multiple cycles

**Symptom:** the synthesis report shows a wide multiplexer-tree barrel shifter (or worse, a DSP-block-based variable shift) completing a shift-by-N in one cycle; the original chip's documented shift-by-N took N cycles; software whose timing depends on shift-instruction latency (audio mixers, CRC loops, hand-tuned graphics routines) runs faster than the original and breaks.
**Cause:** the era used 1-bit-per-cycle shifters because barrel shifters were expensive in silicon, not because shift-add is fast. Mirroring requires the era's cycle count.
**Fix:** instantiate a 1-bit shifter inside an FSM that gates the shift count. The shifter is `Bit_Shifter.v` with `WORD_WIDTH=1`-style behavior; a down-counter loaded from the opcode's shift-amount field gates the FSM's "done" condition. The shift completes in exactly N cycles, matching the original. Cross-ref [31-dsp-inference-cyclone-v.md](31-dsp-inference-cyclone-v.md) for the era-faithful contrast on the DSP-vs-iterative axis.
**Citation:** FPGADesignElements `Bit_Shifter.v` (mechanism); cross-ref [31](31-dsp-inference-cyclone-v.md); [I] for the era-faithfulness rule.

### #25 — Inferred M10K where a small register file (≤16 entries) belongs in flops (era-angle cross-reference)

**Symptom:** an architectural register file with 8 or 16 entries is inferred into an M10K block instead of into flops; read latency is 1 cycle where the original chip read its register file combinationally; multi-port reads require workarounds (read-during-write modes, port duplication).
**Cause:** the synthesizer pattern matched "small RAM" and selected M10K; the mirroring rule (small register files map to flops) was violated by an unconstrained `(* ramstyle = "auto" *)` or by a wide-enough address inference.
**Fix:** force flops with `(* ramstyle = "logic" *)`, or use `Register_Pipeline.v` with `parallel_load`/`parallel_out` tied for a bank of named flop registers. **Primary home is [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md);** reinforced here from the era angle: an original chip's small register file was flops or latches, not block RAM. The era did not have M10K-style blocks for ≤16-entry register files.
**Citation:** [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md) (primary); FPGADesignElements `Register_Pipeline.v` (mechanism); [I] for the era-faithfulness reinforcement.

### #26 — Used a DSP block where the original chip used iterative shift-add (era-angle cross-reference)

**Symptom:** synthesis report shows the variable-precision DSP block performing a multiply in one cycle where the original chip took N cycles of conditional add + shift; software that depends on multiply latency (game-physics timing, audio synthesis envelopes) runs too fast and breaks.
**Cause:** the multiply was written as `a * b` and the synthesizer mapped it to a DSP block. The mirroring rule was violated: the era did not have DSP blocks; the chip's multiply was iterative.
**Fix:** rewrite as an explicit shift-and-add loop using `Bit_Shifter.v` + `Adder_Subtractor_Binary.v` (or `Register_Pipeline.v` for the shift-register), gated by a cycle counter that matches the original chip's documented multiply latency. **Primary home is [31-dsp-inference-cyclone-v.md](31-dsp-inference-cyclone-v.md);** reinforced here: the era used shift-add not because shift-add is fast, but because the era did not have DSP blocks.
**Citation:** [31-dsp-inference-cyclone-v.md](31-dsp-inference-cyclone-v.md) (primary); Intel Cyclone V variable-precision DSP documentation (live URL <https://docs.altera.com/r/docs/683375/current/cyclone-v-device-handbook-volume-1-device-interfaces-and-integration> — app-shell local capture `references/raw/intel/cyclone_v_variable_precision_dsp.html`); [I] for the era-faithfulness reinforcement.

## 8. Verification

The mirroring check is a code-review gate. "Passes self-test" is **not** sufficient evidence of era-faithfulness; only **pin-level cycle-accurate trace comparison** is.

### 8.1 Pre-RTL gate

The pre-RTL plan (per doc 10, extended per §2 of this doc) must name, for each module-to-be-written, which original-chip structure it mirrors. Reviewers reject a plan that fuses unrelated chip subsystems into one module or that omits the chip-identity / datapath-width / control-style / bus-structure / memory-port-topology / external-cycle-count items.

### 8.2 Post-RTL gate

Every module's top comment cites the original-chip subsystem it mirrors. Example:

```systemverilog
// Module: alu_8bit
// Mirrors: original chip's ALU die-block (see <reference>, page <n>, schematic <id>).
// Datapath width: 8 bits.
// Cycle count per op: 2 (operand-latch + result-drive), matching original.
// Control source: microcoded controller's `alu_op` field (3 bits).
```

A separate **module-to-die-block map** is maintained per emulation core: a short markdown file listing each RTL module against the original chip's die-shot block or schematic page. Reviewers cross-check this map; absence is a red flag.

### 8.3 Cycle-trace gate (the most damning test)

A cycle-by-cycle trace of the FPGA implementation's externally observable signals must match a reference trace from the original chip (real silicon, Visual6502, MAME's cycle-accurate cores, or equivalent).

Format: a CSV or VCD with one row per chip cycle, columns being the chip's pin-level signals (address bus, data bus, R/W, IRQ ack, refresh, DMA grant, …). Compare **line-for-line** against the reference. Any mismatch in cycle count, signal phasing, or bus contents is a cycle-accuracy violation; track down which anti-pattern (#33 typically; sometimes #36 or #37) caused it.

### 8.4 Cycle-stress regression suites

Software known to depend on exact cycle behavior (raster split-screen demos, DPCM audio playback, copy-protection routines, hand-tuned graphics) must pass. **Behavioral-only passing is insufficient.** A core that runs games but fails the demoscene is not era-faithful.

### 8.5 Bug symptoms expected when era is violated

- **Cycle-count mismatches at the pin** (the most damning symptom; usually #33).
- **Behaviorally-correct-but-acycle results** from "optimized" parallel paths (#32, #37).
- **Software that runs but depends on cycle-exact timing** fails: DMA glitches, raster effects break, audio chip drivers desync, copy protection refuses (#32–#37 in various combinations).
- **Flag-byte mismatches** at multi-byte arithmetic (#35).

## 9. Provenance footer

Phase 3 reads this footer to build `02-source-map.md`. Sources are listed once, with the §s they support and (for inferred claims) which inference chain they participate in.

- `references/projects/FPGADesignElements/Arbiter_Priority.v` @ pinned commit — used for §2 (resource-sharing inference chain), §3.3 (excerpt), §6 ([O] FPGADesignElements style), §7 (#32, #36 mechanism).
- `references/projects/FPGADesignElements/Arbiter_Round_Robin.v` @ pinned commit — used for §3.3 (round-robin variant), §7 (#32, #36 mechanism).
- `references/projects/FPGADesignElements/Bit_Shifter.v` @ pinned commit — used for §3.1 (era-faithful shifter row), §3.6 table, §7 (#37 mechanism).
- `references/projects/FPGADesignElements/Register_Pipeline.v` @ pinned commit — used for §2 (memory-hierarchy inference chain), §3.1 (small-register-file row), §7 (#25 mechanism).
- `references/projects/FPGADesignElements/Adder_Subtractor_Binary.v` @ pinned commit — used for §5.2 (shared adder/subtractor in era-faithful ALU), §7 (#26 iterative-multiply mechanism).
- `references/extracted_text/methodology/CummingsSNUG1998SJ_FSM.txt` @ snapshot 2026-05-19 — used for §2 (control-style inference chain; encoding choice only), §3.5 (one-hot-with-zero-idle excerpt, lines 157–166). **Cummings does not use the term "microcoded vs hardwired"; the bundle's [I] framing sits above Cummings's encoding mechanism.**
- `references/raw/fpgacpu/verilog_coding_standard.html` @ snapshot 2026-05-19 — used for §2 (single-bus → mux substitution), §3.2 (tristate excerpt lines 402–410), §3.6 mux-width caveat (lines ~660–670), §7 (#34 modularity); local capture is real HTML, not an app shell.
- `references/raw/fpgacpu/system_design_standard.html` @ snapshot 2026-05-19 — used for §2 (mirroring inference chain — hierarchy should reflect structure), §6 ([O] FPGADesignElements style framing), §7 (#34 modularity discipline).
- `references/raw/intel/cyclone_v_embedded_memory_modes.html` @ snapshot 2026-05-19 — local capture is an **app shell**, no content; cite via live URL <https://docs.altera.com/r/docs/683375/current/cyclone-v-device-handbook-volume-1-device-interfaces-and-integration> — used for §2 (memory-hierarchy [V] rule), §7 (#36 M10K port modes).
- `references/raw/intel/cyclone_v_variable_precision_dsp.html` @ snapshot 2026-05-19 — local capture is an **app shell**, no content; cite via live URL <https://docs.altera.com/r/docs/683375/current/cyclone-v-device-handbook-volume-1-device-interfaces-and-integration> — used for §7 (#26 DSP single-cycle behavior).
- `references/raw/intel/cyclone_v_product_table_api.txt` @ snapshot 2026-05-19 — image-heavy PDF; cite via live URL <https://docs.altera.com/api/khub/documents/s60vJiu_kjIh2yag_Ea_yg/content> for DE10-Nano `5CSEBA6U23I7` budget (~110K ALMs, ~5.6 Mbit M10K+MLAB, 112 DSP blocks) — used for §1 (resource budget framing).
- `references/raw/intel/quartus_standard_design_recommendations_index.html` @ snapshot 2026-05-19 — local capture is an **app shell**, no content; cite via live URL <https://www.intel.com/content/www/us/en/programmable/documentation/mwh1409960181641.html> — used for §2 ([C] no-internal-tristate rule).
- `library/topics/01_hardware_mindset_parallelism.md` (in-repo rough notes; cited as the bundle's existing internal source for the "Avoid Software-Shaped RTL" red-flag list, lines 58–67, and the "Share hardware when … an expensive resource is scarce" framing, lines 46–55) — used for §1 (deliverables list framing), §2 (mirroring + resource-sharing inference chains), §7 (#34 cause statement).

**Inferential chains visible.** The [I] claims in §2 — mirroring contract, cycle-accuracy boundary, resource sharing as the era's default, datapath width, microcoded-vs-hardwired framing, and the pre-RTL plan addendum — are each supported by **two or more** sources above, none of which alone establishes the claim. This is the bundle's contract; reviewers may challenge any link in the chain. Cummings does not say "microcoded vs hardwired"; FPGADesignElements does not say "match the era"; Cyclone V documents do not say "mirror the original chip." This doc says all three, and labels them [I] accordingly.
