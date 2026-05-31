# CDC — Single-Bit Crossing

> Bundle version: 2026-05-19
> Pinned commits: FPGADesignElements `CDC_Bit_Synchronizer.v`, `CDC_Pulse_Synchronizer_2phase.v`, `CDC_Pulse_Synchronizer_4phase.v`, `CDC_Flag_Bit.v`, `cdc.html` (fpgacpu.ca) @ 2026-05-20; VerilogPro CDC Part 1 @ 2022-09-29 (post mod date in source); Cummings SNUG 2008 Boston CDC paper (live URL only, no local capture); Intel *Managing Metastability with the Quartus Prime Software* (Quartus Standard 18.1 design-recommendations, live URL only, no local capture); Intel Quartus Standard Timing Analyzer User Guide (live URL only, app-shell local).
> Load with: [11-clocking-resets-and-cyclone-v-clock-networks.md](11-clocking-resets-and-cyclone-v-clock-networks.md), [24-cdc-multi-bit.md](24-cdc-multi-bit.md), [16-resource-and-state-economy.md](16-resource-and-state-economy.md), [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md)
> Status mix: [C] ~45% (synchronizer chain rules, dedicated-module rule, false-path SDC, pulse-via-toggle rule — anchored in Cummings, Intel *Managing Metastability*, VerilogPro CDC Part 1, and FPGADesignElements `.v` sources); [V] ~15% (chain depth 2 vs 3, source-side register placement convention); [O] ~25% (FPGADesignElements 2-phase / 4-phase pulse synchronizers, `CDC_Flag_Bit`, VerilogPro feedback synchronizer — each labelled to its specific source); [I] ~15% (no-defensive-synchronizer same-clock rule; Cyclone V–specific MTBF / resolution-time constants deliberately not stated). **Several [C] rules cite live URLs only — Cummings SNUG 2008 Boston CDC PDF and Intel *Managing Metastability* are fetch-failure stubs / app-shells locally; Phase 4 cannot verify these citations from disk and should treat them as authoritative pointers, not verbatim-extractable sources.**
> Missing inputs: `references/raw/methodology/CummingsSNUG2008Boston_CDC_fetch_failed.html` and `..._sunburstdesign_fetch_failed.html` are fetch-failure stubs (live URL cited); `references/raw/intel/quartus_metastability_management.html`, `quartus_cdc_synchronizer_constraints.html`, and `quartus_standard_timing_analyzer.html` are 71-line app shells with no extractable body (live URLs cited).

## 1. Purpose & one-line summary

This doc is the contract for moving a **single bit** between two **asynchronously related clock domains** on Cyclone V without metastability hazards. The consuming agent must produce three artefacts per single-bit crossing: a dedicated-module 2FF (or pulse/toggle) synchronizer in the destination clock domain, an SDC `set_false_path` or `set_clock_groups -asynchronous` declaration so TimeQuest does not try to time the path, and a Quartus Metastability Analysis report check confirming the chain was recognized. Read [11](11-clocking-resets-and-cyclone-v-clock-networks.md) first for single-clock-domain default and clock-network primitives, then this doc; multi-bit crossings (async FIFO, MCP, Gray-coded counters) are deferred to [24](24-cdc-multi-bit.md), and the "don't insert defensive synchronizers within one clock domain" efficiency rule has its primary home in [16](16-resource-and-state-economy.md).

## 2. The contract (must-obey)

- [C] **Every signal that crosses from a source clock to an asynchronously related destination clock must pass through a synchronizer chain clocked by the destination clock before any logic in the destination domain samples it.** Without the chain the first destination flop's setup/hold window is violated whenever the source transition lands inside it, producing a metastable output that may propagate into the destination logic as a wrong Boolean value or an oscillating one. Cummings SNUG 2008 Boston *Clock Domain Crossing (CDC) Design & Verification Techniques Using SystemVerilog* — `http://www.sunburst-design.com/papers/CummingsSNUG2008Boston_CDC.pdf` (live URL, no local capture); Intel *Managing Metastability with the Quartus Prime Software* — `https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/managing-metastability-with-the-software-44819` (live URL, no local capture).
- [C] **A single-bit level synchronizer chain consists of at least two cascaded flops clocked by the destination clock, with no combinational logic between them.** Two flops give the first flop a full destination-clock period to resolve any metastable settling before the second flop samples. The verilog-axis async-FIFO doc-doc in this bundle (`22-fifos-synchronous-and-asynchronous.md`) shows the same 2FF chain applied to a Gray-coded pointer; the canonical structure appears in `references/projects/FPGADesignElements/CDC_Bit_Synchronizer.v:99-147 @ 2026-05-20`. Cummings SNUG 2008 Boston CDC (live URL above).
- [C] **The synchronizer chain must live in a dedicated module (or be tagged with the vendor synchronizer attribute) so the Quartus metastability analyzer can recognize it and report MTBF.** A two-flop chain scattered into a larger `always_ff` block is invisible to the pattern-matcher; the tools may also retime, replicate, or pack the flops in ways that defeat the chain. The FPGADesignElements canonical synchronizer wraps the chain in its own module and applies `(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION \"FORCED IF ASYNCHRONOUS\"" *)` plus `(* PRESERVE *)` and `(* useioff = 0 *)` to forbid IOE placement and merging (`references/projects/FPGADesignElements/CDC_Bit_Synchronizer.v:120-124 @ 2026-05-20`). Intel *Managing Metastability with the Quartus Prime Software* — `https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/managing-metastability-with-the-software-44819` (live URL only, no local capture; this is the Status-mix-flagged live-URL-only [C] citation).
- [C] **A CDC synchronizer must be fed directly from a register in the source clock domain, with no combinational logic between that register and the first synchronizer flop.** Combinational glitches at the synchronizer input increase the effective transition rate and so reduce MTBF; an unrelated destination clock edge that happens to sample a glitch will transform it into a real spurious pulse in the destination domain. FPGADesignElements: "You must feed a CDC Synchronizer directly from a register, with no logic between it and the synchronizer" (`references/projects/FPGADesignElements/CDC_Bit_Synchronizer.v:62-74 @ 2026-05-20`); VerilogPro CDC Part 1: "It is a generally good practice to register signals in the source clock domain before sending them across the clock domain crossing (CDC) into synchronizers. This eliminates combinational glitches, which can effectively increase the rate of data crossing the clock boundary, reducing MTBF of the synchronizer" (`references/raw/verilogpro/cdc_part1.html:295 @ 2022-09-29`).
- [C] **An event (single-cycle pulse) on the source clock cannot be reliably synchronized by feeding the pulse into a 2FF chain.** Depending on relative clock phase the destination may sample the pulse zero, one, or two times. To cross an event reliably, toggle a level register on the source side from the event, synchronize the toggle line through a 2FF chain, and edge-detect (any-edge) the synchronized toggle in the destination domain. VerilogPro CDC Part 1: "if a pulse on the fast signal is shorter than the period of the slow clock, then the pulse can disappear before being sampled by the slow clock" (`references/raw/verilogpro/cdc_part1.html:315 @ 2022-09-29`); the canonical toggle-based pulse synchronizer is `references/projects/FPGADesignElements/CDC_Pulse_Synchronizer_2phase.v:21-41,87-205 @ 2026-05-20`.
- [C] **Async CDC paths must be excluded from setup/hold timing analysis** with `set_false_path -from [get_clocks <src_clk>] -to [get_clocks <dst_clk>]` or, preferably for whole groups of unrelated clocks, by declaring the clocks asynchronous with `set_clock_groups -asynchronous -group { <src_clk> } -group { <dst_clk> }`. Without an SDC exception, TimeQuest will report negative slack across the inherently untimed path and a designer who "fixes" it by pipelining only adds latency without restoring deterministic timing. Intel Quartus Standard Timing Analyzer User Guide — `https://docs.altera.com/r/docs/683068/current` (live URL, app-shell local at `references/raw/intel/quartus_standard_timing_analyzer.html`); CDC-specific synchronizer-constraint guidance in Intel *Managing Metastability* (same live URL as the dedicated-module rule above).
- [C] **Only one bit at a time may cross a given clock-domain boundary using a 2FF synchronizer.** Two parallel 2FF synchronizers may not have the same latency cycle-by-cycle (see §4); a multi-bit value sampled mid-transition through parallel synchronizers may sample inconsistent combinations of "before" and "after" bits. Multi-bit values cross either as Gray-coded counters (one bit changes per increment) or via handshake-gated capture. FPGADesignElements: "**only one signal may be synchronized at each clock domain crossing**. Using multiple CDC Synchronizers in parallel is **not deterministic** as there is no guarantee they will all have the same latency" (`references/projects/FPGADesignElements/CDC_Bit_Synchronizer.v:46-60 @ 2026-05-20`); fpgacpu.ca CDC primer: "**only one bit at a time may ever be synchronized across a given clock domain crossing.**" (`references/raw/fpgacpu/cdc.html:112-119 @ 2026-05-20`). Multi-bit handling itself is deferred to [24](24-cdc-multi-bit.md).
- [V] **The synchronizer chain length is 2 flops by default; use 3 or more only when MTBF analysis at the target destination clock frequency shows 2 insufficient.** FPGADesignElements parameterises the chain length as `DEPTH = 2 + EXTRA_DEPTH` with `EXTRA_DEPTH` defaulting to 0 (`references/projects/FPGADesignElements/CDC_Bit_Synchronizer.v:91,99-103 @ 2026-05-20`); VerilogPro CDC Part 1: "The two flip-flop synchronizer is sufficient for many applications. Very high speed designs may require a three flip-flop synchronizer to give sufficient MTBF" (`references/raw/verilogpro/cdc_part1.html:287 @ 2022-09-29`). The Cyclone V–specific clock frequency at which 3FF becomes warranted is not stated in the captured material; consult the Intel Metastability Analysis report (see §8) and add a chain stage only when MTBF reads poorly.
- [V] **Power-up value of synchronizer flops should be a safe known state, typically 0.** FPGADesignElements seeds the array with an `initial` loop assigning `1'b0` to each stage (`references/projects/FPGADesignElements/CDC_Bit_Synchronizer.v:128-132 @ 2026-05-20`); on Cyclone V the FPGA's configuration-time power-up sequence supports this `initial`-block convention. Pair with the bundle's standard async-assert / sync-release reset for the source register; see [11](11-clocking-resets-and-cyclone-v-clock-networks.md).
- [I] **Do not insert a 2FF synchronizer on a signal that is already in the destination clock domain (no "defensive" same-clock-domain synchronizers).** Wastes two flops per signal, adds two cycles of latency, and can mask real intra-domain timing bugs by absorbing slack. No single archive source states this in one sentence; it follows from the [C] rule above (the chain's whole purpose is to manage *async* metastability — same-clock paths have none) combined with the bundle's resource-economy framing. Primary home: [16-resource-and-state-economy.md](16-resource-and-state-economy.md). The temptation is highest in CDC-aware code and is surfaced again as a §7 anti-pattern.

## 3. Constructs / signals / API reference

This section enumerates the three building blocks the consuming agent will instantiate per single-bit crossing — the 2FF level synchronizer, the toggle-based pulse synchronizer, and the SDC constraint — and the role each plays.

### 3.1 2FF level synchronizer (canonical module)

The destination-domain register chain. Two flops, no logic between them, in a dedicated module so Quartus pattern-matches it. The verbatim core of the FPGADesignElements canonical implementation:

```verilog
// references/projects/FPGADesignElements/CDC_Bit_Synchronizer.v:87-149 @ 2026-05-20
`default_nettype none

module CDC_Bit_Synchronizer
#(
    parameter EXTRA_DEPTH = 0 // Must be 0 or greater
)
(
    input   wire    receiving_clock,
    input   wire    bit_in,
    output  reg     bit_out
);

// The minimum valid synchronizer depth is 2. Add more stages if the design
// requires it. This usually happens near the highest operating frequencies.
// Consult your device datasheets.

    localparam DEPTH = 2 + EXTRA_DEPTH;

// For Vivado, we must specify that the synchronizer registers should be
// placed close together (see: UG912), and to show up as part of MTBF reports.

// For Quartus, specify that these register must not be optimized (e.g. moved
// into the input register of a DSP or BRAM) and to mark them as composing
// a synchronizer (and so be placed close together).

// In both cases, we also specify that the registers must not be placed in I/O
// register locations.

    // Vivado
    (* IOB = "false" *)
    (* ASYNC_REG = "TRUE" *)

    // Quartus
    (* useioff = 0 *)
    (* PRESERVE *)
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION \"FORCED IF ASYNCHRONOUS\"" *)

    reg sync_reg [DEPTH-1:0];

    integer i;

    initial begin
        for(i=0; i < DEPTH; i=i+1) begin
            sync_reg [i] = 1'b0;
        end
    end

// Pass the bit through DEPTH registers into the receiving clock domain.
// Peel out the first iteration to avoid a -1 index.

    always @(posedge receiving_clock) begin
        sync_reg [0] <= bit_in;

        for(i = 1; i < DEPTH; i = i+1) begin: cdc_stages
            sync_reg [i] <= sync_reg [i-1];
        end
    end

    always @(*) begin
        bit_out = sync_reg [DEPTH-1];
    end

endmodule
```

The Cyclone V–relevant attributes are `(* PRESERVE *)` (no merging or retiming), `(* useioff = 0 *)` (do not pack a synchronizer flop into an IOE — IOEs are too far from fabric for the chain's tight placement requirement), and `(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION \"FORCED IF ASYNCHRONOUS\"" *)` (instruct Quartus to mark and analyse these flops as a synchronizer chain even if its automatic detector would not). The Vivado attributes are inert on Quartus and may be left or stripped.

### 3.2 Toggle-based pulse synchronizer (2-phase handshake)

For a single-cycle event in the source domain that must produce a single-cycle event in the destination domain when relative clock frequencies are unknown. The verbatim 2-phase implementation core:

```verilog
// references/projects/FPGADesignElements/CDC_Pulse_Synchronizer_2phase.v:85-205 @ 2026-05-20
`default_nettype none

module CDC_Pulse_Synchronizer_2phase
#(
    parameter CDC_EXTRA_DEPTH   = 0
)
(
    input   wire    sending_clock,
    input   wire    sending_pulse_in,
    output  reg     sending_ready,

    input   wire    receiving_clock,
    output  wire    receiving_pulse_out
);

// ... source-side cleanup of the input pulse to single-cycle ...
    wire cleaned_pulse_in;
    Pulse_Generator pulse_cleaner ( /* posedge of sending_pulse_in */ );

// Use the single-cycle pulse to toggle a level register, signalling the
// start of a 2-phase asynchronous handshake.
    wire toggle_response;
    reg  enable_toggle = 1'b0;
    wire sending_toggle;
    Register_Toggle #(.WORD_WIDTH(1), .RESET_VALUE(1'b0)) start_handshake (
        .clock(sending_clock), .clock_enable(enable_toggle),
        .clear(1'b0), .toggle(cleaned_pulse_in),
        .data_in(sending_toggle), .data_out(sending_toggle));

// Toggle and its response equal => handshake complete, ready to toggle again.
    always @(*) begin
        enable_toggle = (sending_toggle == toggle_response);
        sending_ready = enable_toggle;
    end

// 2FF synchronize the toggle into the receiving clock domain
    wire receiving_toggle;
    CDC_Bit_Synchronizer #(.EXTRA_DEPTH(CDC_EXTRA_DEPTH)) to_receiving (
        .receiving_clock(receiving_clock),
        .bit_in(sending_toggle), .bit_out(receiving_toggle));

// 2FF synchronize the receiving toggle back to the sending domain
    CDC_Bit_Synchronizer #(.EXTRA_DEPTH(CDC_EXTRA_DEPTH)) to_sending (
        .receiving_clock(sending_clock),
        .bit_in(receiving_toggle), .bit_out(toggle_response));

// Edge-detect (any-edge) the synchronized toggle in the receiving domain
    Pulse_Generator receiving_toggle_to_pulse (
        .clock(receiving_clock), .level_in(receiving_toggle),
        .pulse_anyedge_out(receiving_pulse_out));

endmodule
```

Three things are load-bearing about this structure: (1) the level being synchronized is the **toggle**, never the original pulse — toggle transitions cannot be missed because the level holds until acknowledged; (2) both directions cross a 2FF synchronizer, so the "only one bit per crossing" rule from §2 holds per direction; (3) the source-side `sending_ready` deasserts while the round-trip handshake is in flight, naming the back-pressure window during which the source must not raise another pulse.

### 3.3 SDC fragment

Tell TimeQuest that the cross-domain paths are intentionally untimed. Two equivalent SDC patterns:

```tcl
# references/raw/intel/quartus_standard_timing_analyzer.html — live URL @ 2026-05-20
# https://docs.altera.com/r/docs/683068/current
#
# Pattern A: explicit per-direction false-path exception
set_false_path -from [get_clocks src_clk] -to [get_clocks dst_clk]
set_false_path -from [get_clocks dst_clk] -to [get_clocks src_clk]

# Pattern B: declare the two clocks asynchronous (covers all paths both ways)
set_clock_groups -asynchronous \
    -group { src_clk } \
    -group { dst_clk }
```

Pattern B is the bundle's preferred form because one statement covers every register-to-register path between the two groups (handshake return path included) and survives later additions of further crossings. Pattern A is useful when only specific synchronizer instances should be excluded — e.g. while leaving a known-related multi-cycle path on the same clock pair still timed. The full SDC essentials (`create_clock`, I/O delay, multicycle, recovery/removal) are deferred to [40-timing-closure-and-sdc.md](40-timing-closure-and-sdc.md).

### 3.4 Construct / signal reference

| Name | Type / width / direction | Meaning | Driven by | Drives |
|---|---|---|---|---|
| Source-side launch register | 1-bit flop in source clock domain | The "well-defined" launch point of the CDC path: a registered signal with no combinational logic between it and the synchronizer | source-domain logic | `bit_in` / `sending_pulse_in` of the synchronizer module |
| `CDC_Bit_Synchronizer` (level 2FF chain) | dedicated module, parameter `EXTRA_DEPTH` (default 0 → 2 flops) | 2-flop (or longer) chain clocked by `receiving_clock`, marked `PRESERVE` / `SYNCHRONIZER_IDENTIFICATION` / `useioff=0` | `bit_in` (source-domain level) | `bit_out` (destination-domain level, latency 1–3 dst cycles) |
| Source-side toggle FF | 1-bit flop in source domain, toggled on each source pulse | Converts the source event into a level transition that cannot be missed | source-domain `pulse_in` (with handshake-gated `clock_enable`) | input of the destination-bound 2FF chain |
| Destination-side edge detector | 1-bit any-edge detector in destination domain | Recovers a single-cycle destination pulse from the synchronized toggle | output of the destination-bound 2FF chain | destination-domain consumer logic |
| Handshake return 2FF | second `CDC_Bit_Synchronizer` instance | Tells the source side the toggle has been observed in the destination domain, re-enabling further source pulses | destination toggle level | source-side `enable_toggle` / `sending_ready` |
| `set_false_path` / `set_clock_groups -asynchronous` | SDC constraint | Excludes the inter-clock paths from setup/hold analysis | SDC file | TimeQuest analyser |
| MTBF / Synchronizer Chains report entry | Quartus Fitter report section | One row per recognized synchronizer; absence implies the chain was not recognized | Fitter's metastability analyzer | the human reading the report (and §8 of this doc) |

Latency cost summary: 1–3 destination clocks for a level 2FF crossing (see §4); add 1 source cycle for the source toggle and 3 destination + 3 source cycles round-trip handshake for the 2-phase pulse synchronizer; the 4-phase variant adds further latency (see §6).

## 4. Sequencing & timing

### 4.1 Level signal crossing through a 2FF synchronizer

A clean transition from 0 to 1 on a source-domain register, sampled into the destination domain. `meta` is the first synchronizer flop's output — possibly metastable for one destination cycle — and `stable` is the second flop's output, which the destination logic sees.

```
src_clk        __|""|__|""|__|""|__|""|__|""|__|""|__|""|__
signal_src   __________|"""""""""""""""""""""""""""""""""""
                       ^ source register loaded with 1

dst_clk        ____|""|__|""|__|""|__|""|__|""|__|""|__|""|
meta         ___________?????????________|"""""""""""""""""
                        ^ setup/hold violated; output may
                          wander before resolving high
stable       _________________?????????_________|""""""""""
                                       ^ destination logic
                                         sees the value
                                         after 2-3 dst cycles
```

The receiver may not see the transition for 1, 2, or 3 destination clock cycles depending on phase alignment and whether the first flop went metastable; fpgacpu.ca enumerates six distinct cases producing latencies in {1, 2, 3} destination cycles (`references/raw/fpgacpu/cdc.html:65-103 @ 2026-05-20`). The only invariants are (a) once `stable` resolves it is a clean Boolean — never indeterminate — and (b) repeated transitions on `signal_src` keep their order in `stable` but their *per-transition* destination-clock latency is independent of each other.

### 4.2 Pulse crossing via toggle synchronizer (2-phase handshake)

A single-cycle source pulse, the source toggle that captures it, the 2FF stage on the destination side, the destination single-cycle pulse recovered by edge-detection, and the round-trip back to source that re-enables further pulses:

```
src_clk         __|"|_|"|_|"|_|"|_|"|_|"|_|"|_|"|_|"|_|"|_|"|_|"|_
evt_src         _______|"|________________________________________
tog_src         _________|"""""""""""""""""""""""""""""""""""""""""
                         ^ toggle flips; further toggles disabled
sending_ready   """""""""|____________________________|"""""""""""
                         ^ deasserted during round-trip handshake

dst_clk         __|""|_|""|_|""|_|""|_|""|_|""|_|""|_|""|_|""|_|""
recv_2ff_out    ___________?????___|"""""""""""""""""""""""""""""""
                                ^ 2FF settles after 2-3 dst cycles
evt_dst         _________________________|"|________________________
                                         ^ any-edge detector emits
                                           single dst-cycle pulse

(round-trip back to src completes; sending_ready re-asserts)
```

Total round-trip latency under the 2-phase scheme — pulse-in to ready-again — is at minimum 1 source cycle (toggle) + worst-case 3 destination cycles (forward 2FF) + worst-case 3 source cycles (return 2FF) ≈ "every 4th source cycle at best" when the receiving clock is fast enough to be effectively infinite from the source's view (`references/projects/FPGADesignElements/CDC_Pulse_Synchronizer_2phase.v:56-83 @ 2026-05-20`). The destination-domain pulse itself is one destination clock wide.

### 4.3 The metastability mechanism, in one paragraph

If the first destination flop's input changes within its setup-or-hold window — which is guaranteed to happen sometimes when the two clocks are unrelated — the flop's internal bistable enters a metastable state, an indeterminate output voltage between logic 0 and logic 1. The flop then resolves to one of the two stable states within a bounded but stochastic time; the *probability* the flop is still metastable after time `t_r` falls exponentially with `t_r`. A second flop with one full destination clock period of additional settling time multiplies that exponential by another factor, reducing the failure probability per crossing to a very small per-edge number. Aggregated over many edges per second, this yields a Mean Time Between Failures (MTBF), reported by Quartus per recognized synchronizer (see §8). Cummings SNUG 2008 Boston CDC (live URL above) is the canonical write-up; specific MTBF formulas and Cyclone V–specific resolution-time constants are not stated in the captured material and are not asserted here ([I]).

Important caveat for downstream consumers: do not draw conclusions about *which* logic level the destination first sees on a transition through the chain. The synchronized value may be 0 for one more destination cycle than the source intended (a transition "missed" by one edge) or 1 one cycle earlier than naive expectation. Edge-aligned events on the destination side after the chain are the correct abstraction; cycle-aligned correspondence between source and destination is not.

## 5. Minimal working pattern

A minimum working single-bit CDC: a status bit `status_src` produced in the source clock domain, synchronized into the destination domain as `status_dst` for the destination domain's consumer logic. [I] composite — composed from the FPGADesignElements `CDC_Bit_Synchronizer` (the module body) and the bundle's SDC and instantiation idioms; the source-side register and SDC fragment are written here, the synchronizer module body is the verbatim §3.1 excerpt.

```systemverilog
// Synchronize a single status bit from src_clk to dst_clk.
// Composes:
//  - source-side register (no combinational logic into the synchronizer)
//  - the FPGADesignElements CDC_Bit_Synchronizer module (see section 3.1)
//  - the SDC false-path declaration (see section 3.3)

module status_cdc_example (
    input  logic src_clk,
    input  logic dst_clk,
    input  logic status_raw_src,    // produced by source-domain logic
    output logic status_dst         // for destination-domain logic
);
    // [C] source-side register: directly feeds the synchronizer, no logic
    logic status_src_q;
    always_ff @(posedge src_clk)
        status_src_q <= status_raw_src;

    // [C] 2FF level synchronizer, in its own (already-defined) module
    CDC_Bit_Synchronizer #(.EXTRA_DEPTH(0)) u_status_sync (
        .receiving_clock (dst_clk),
        .bit_in          (status_src_q),
        .bit_out         (status_dst)
    );
endmodule

// In the project SDC file:
//   set_clock_groups -asynchronous -group { src_clk } -group { dst_clk }
```

Quartus expectation after Fitter compile: open the Fitter report → **Synchronizer Statistics** / **Synchronizer Summary** node (sometimes labelled "Metastability Analysis" depending on Quartus revision). An entry for `u_status_sync` (or for the instance-resolved name of the synchronizer chain) should appear there with a reported MTBF. If the entry is missing, the chain was not recognized — check that the synchronizer is in its own module, that the `(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION ... " *)` attribute survived synthesis, and that the SDC declares the clocks asynchronous (recognition depends on the path being marked as crossing-async clocks). See §8.

## 6. Common variations across implementations

- [O] **FPGADesignElements 2-phase toggle pulse synchronizer** — minimum-latency pulse crossing, no back-pressure beyond the `sending_ready` flag that gates further input pulses. Uses two `CDC_Bit_Synchronizer` instances (forward toggle + return acknowledge). One source pulse per ≈ 4 source cycles maximum when the destination clock is effectively infinite (`references/projects/FPGADesignElements/CDC_Pulse_Synchronizer_2phase.v:56-83,134-203 @ 2026-05-20`).
- [O] **FPGADesignElements 4-phase pulse synchronizer** — explicit raise / wait-response / lower / wait-response handshake. Uses a level latch on the source side that must be cleared by the returned response. Roughly half the input-pulse rate of the 2-phase variant (≈ one input pulse every 9 source cycles at infinite destination clock) and slightly simpler hardware; the author explicitly recommends the 2-phase variant unless gate count is critical (`references/projects/FPGADesignElements/CDC_Pulse_Synchronizer_4phase.v:11-19,42-68 @ 2026-05-20`).
- [O] **FPGADesignElements `CDC_Flag_Bit`** — a flag bit set in one clock domain and cleared from another, built as two half-toggles (one per clock), each synchronized to the other domain. The flag's value is the XOR of the local half-toggle and the synchronized opposite-domain half-toggle (`references/projects/FPGADesignElements/CDC_Flag_Bit.v:60-141 @ 2026-05-20`). Useful when the source domain raises a sticky condition that the destination domain must observe and then acknowledge.
- [O] **VerilogPro single-bit feedback ("closed-loop level") synchronizer** — a 2FF carries the source level to the destination domain, and a second 2FF carries the destination's captured-OK acknowledge back; the source holds its level until the acknowledge arrives. Used when the source must know the bit has been latched in the destination before changing it again, especially under varying destination clock frequencies. VerilogPro CDC Part 1: "The source domain sends the signal to the destination clock domain through a two flip-flop synchronizer, then passes the synchronized signal back to the source clock domain through another two flip-flop synchronizer as a feedback acknowledgement" (`references/raw/verilogpro/cdc_part1.html:355-371 @ 2022-09-29`).
- [V] **3-flop chain at very high destination clocks.** Same `CDC_Bit_Synchronizer` module body with `EXTRA_DEPTH = 1`, or `2` for a 4-flop chain. Use only when the destination clock is high enough that 2FF MTBF reads poorly in the Quartus Metastability Analysis report. Cummings SNUG 2008 Boston CDC (live URL above); the canonical module body parameterises `DEPTH = 2 + EXTRA_DEPTH` (`references/projects/FPGADesignElements/CDC_Bit_Synchronizer.v:91,99-103 @ 2026-05-20`).

## 7. Anti-patterns (mistakes that compile but break)

### 7.1 One-flop synchronizer
- **Symptom:** Intermittent functional failures that pass in simulation but reproduce only occasionally on hardware, often correlated with temperature, voltage, or relative clock drift; bugs that "fix themselves" between debug attempts.
- **Cause:** A single destination-domain flop has no margin for the first flop's metastable settling time; the metastable output is sampled by downstream logic, which may interpret it as 0 or 1 and which may propagate the indeterminate state.
- **Fix:** Use the 2FF (or deeper) chain in §3.1 / §5. Place the chain in a dedicated module so Quartus recognizes and reports it (see 7.2).
- **Citation:** Cummings SNUG 2008 Boston CDC — `http://www.sunburst-design.com/papers/CummingsSNUG2008Boston_CDC.pdf` (live URL, no local capture); VerilogPro CDC Part 1: "If the input data changes very close to the receiving clock edge (within setup/hold time), the first flip-flop in the synchronizer may go metastable, but there is still a full clock for the signal to become stable before being sampled by the second flip-flop" (`references/raw/verilogpro/cdc_part1.html:283 @ 2022-09-29`).

### 7.2 Synchronizer not in a dedicated module
- **Symptom:** Quartus's Metastability Analysis (Synchronizer Statistics) report does not list the chain; no MTBF reported. Synthesis warnings about retiming, replication, or merging may appear. The chain "works in simulation" but field-tests show drift in the timing margin or wrong-value samples consistent with the chain being broken by optimisation.
- **Cause:** Surrounding the two flops with unrelated logic in the same `always_ff` block (or scattering them across modules) prevents the Quartus pattern-matcher from recognising them as a synchronizer. The tools may retime registers across the chain, replicate one of the flops for fanout, or pack a flop into a DSP/BRAM input register — any of which defeats the chain.
- **Fix:** Encapsulate every single-bit CDC in its own module (the `CDC_Bit_Synchronizer` of §3.1). Apply `(* PRESERVE *)`, `(* useioff = 0 *)`, and `(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION \"FORCED IF ASYNCHRONOUS\"" *)` to the chain register array.
- **Citation:** Intel *Managing Metastability with the Quartus Prime Software* — `https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/managing-metastability-with-the-software-44819` (live URL, no local capture; this is the Status-mix-flagged citation); the attribute pattern is `references/projects/FPGADesignElements/CDC_Bit_Synchronizer.v:115-124 @ 2026-05-20`.

### 7.3 Pulse fed into a level synchronizer
- **Symptom:** The destination domain occasionally misses the event entirely, or sees it twice in adjacent destination cycles. Event-counter mismatches between source and destination; lost interrupts; "stuck" handshakes that work most of the time.
- **Cause:** The source pulse is shorter than (or comparable to) the destination clock period, so depending on phase the 2FF chain may sample the pulse zero or one times; for a wider pulse it may sample it twice. The 2FF chain crosses *levels*, not edges.
- **Fix:** On the source side, toggle a level register from the source pulse (gated by the handshake-ready signal). 2FF the toggle into the destination domain. Edge-detect (any-edge) the synchronized toggle to recover a single-destination-cycle pulse. Use the `CDC_Pulse_Synchronizer_2phase` of §3.2.
- **Citation:** VerilogPro CDC Part 1: "if a pulse on the fast signal is shorter than the period of the slow clock, then the pulse can disappear before being sampled by the slow clock" (`references/raw/verilogpro/cdc_part1.html:315 @ 2022-09-29`); the canonical pulse-via-toggle pattern is `references/projects/FPGADesignElements/CDC_Pulse_Synchronizer_2phase.v:21-41 @ 2026-05-20`.

### 7.4 Synchronizer with no SDC declaration
- **Symptom:** Timing Analyzer reports large negative slack on register-to-register paths between the two clocks; a designer "fixes" it by inserting pipeline registers along the path that do not converge timing; project never closes timing across the CDC; or — worse — the placer/router shifts paths to meet a fictional timing requirement, distorting placement of unrelated logic.
- **Cause:** TimeQuest is trying to compute setup/hold across an inherently untimed path. No amount of pipelining helps because the destination capture edge has no fixed phase relationship to the source launch edge.
- **Fix:** Add `set_clock_groups -asynchronous -group { src_clk } -group { dst_clk }` (preferred) or `set_false_path -from [get_clocks src_clk] -to [get_clocks dst_clk]` (per-direction) to the project SDC. Confirm in the Inter-Clock Paths report that the path shows as a false path. See §3.3 and §8.
- **Citation:** Intel Quartus Standard Timing Analyzer User Guide — `https://docs.altera.com/r/docs/683068/current` (live URL, app-shell local); the same SDC-syntax body is referenced from Intel CDC synchronizer constraints under *Managing Metastability* (live URL above).

### 7.5 Combinational logic between the source register and the first synchronizer flop
- **Symptom:** MTBF reported by Quartus is much worse than the chain length predicts; spurious destination pulses appear on data-stable cycles; the chain "works for slow source-side activity and breaks under load."
- **Cause:** Combinational glitches at the synchronizer input (from multi-path convergence in the source-side combinational logic) increase the effective transition rate. An unrelated destination clock edge that happens to sample a glitch transforms it into a real spurious destination-domain pulse, even though no source-domain register actually changed.
- **Fix:** Place a register in the source clock domain immediately before the synchronizer module instance, with no logic between that register and the synchronizer's `bit_in` port. If the source-side path requires combinational logic, do it in the source domain *before* the launch register.
- **Citation:** FPGADesignElements: "You must feed a CDC Synchronizer directly from a register, with no logic between it and the synchronizer" (`references/projects/FPGADesignElements/CDC_Bit_Synchronizer.v:62-74 @ 2026-05-20`); VerilogPro CDC Part 1: "It is a generally good practice to register signals in the source clock domain before sending them across the clock domain crossing (CDC) into synchronizers. This eliminates combinational glitches, which can effectively increase the rate of data crossing the clock boundary, reducing MTBF of the synchronizer" (`references/raw/verilogpro/cdc_part1.html:295 @ 2022-09-29`).

### 7.6 2FF synchronizer on a same-clock-domain signal
*(Cross-reference; primary home is [16-resource-and-state-economy.md](16-resource-and-state-economy.md). Surfaced here because the temptation is highest in CDC-aware code, where copying CDC discipline onto same-clock signals feels "safe.")*
- **Symptom:** Two extra cycles of latency on a signal that did not need them; two extra flops per signal in the fabric; intra-domain timing bugs are masked because the synchronizer absorbs slack that should be diagnosed; harder-to-trace causation between source assertion and destination response.
- **Cause:** Applying CDC discipline ("synchronize everything") to signals whose source and destination are in the same clock domain. There is no metastability hazard on a same-clock path; the chain has no purpose.
- **Fix:** Only insert a synchronizer when the source and destination clocks are asynchronously related. For same-clock paths, use a direct register-to-register connection (with the usual one-driver-per-signal discipline of [13-registers-and-combinational-blocks.md](13-registers-and-combinational-blocks.md)). Primary efficiency framing: [16-resource-and-state-economy.md](16-resource-and-state-economy.md).
- **Citation:** [I] — synthesised from the [C] §2 rule that the synchronizer chain manages async metastability (Cummings SNUG 2008 Boston CDC live URL; Intel *Managing Metastability* live URL) combined with the bundle's resource-economy framing. No single archive source states it as a one-sentence anti-pattern.

## 8. Verification

1. **Quartus Metastability / Synchronizer Statistics report.** After Fitter, open the Fitter report and navigate to the **Synchronizer Statistics** / **Synchronizer Summary** node (the exact label depends on the Quartus revision; Quartus Standard 18.1 — this bundle's target — places it under the Fitter's analysis subnodes per Intel *Managing Metastability* — `https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/managing-metastability-with-the-software-44819`, live URL only). Each instance of every dedicated synchronizer module should appear as a recognized row with a reported MTBF. A row that is *missing* indicates a synchronizer that the tool did not recognize — most often because (a) the chain is not in its own module, (b) the `SYNCHRONIZER_IDENTIFICATION` attribute did not survive, or (c) the path is not declared async in the SDC and so Quartus does not consider it a CDC path.
2. **MTBF reading.** A "good" MTBF on a recognized synchronizer is decades or longer at the project's target operating conditions; days or hours indicates the chain length must be increased (`EXTRA_DEPTH > 0` in the module of §3.1) or the destination clock must be lowered. Cyclone V–specific resolution-time constants are not stated in the captured material; rely on the report's actual numbers rather than synthetic predictions. Intel *Managing Metastability* (live URL above).
3. **TimeQuest Inter-Clock Paths check.** Open the Timing Analyzer's Inter-Clock Paths report after Fitter. The cross-domain path should show as a **false path** (or be absent from the timed paths list because the clocks are declared asynchronous), not as a failing setup/hold path. If a CDC path appears with negative slack, the SDC declaration is missing or wrong — fix the SDC, not the RTL (anti-pattern 7.4).
4. **Simulation expectations and limits.** Behavioural simulation does not exhibit metastability; the destination-domain flop will always sample a deterministic 0 or 1, never an indeterminate state. **Do not rely on simulation to find missing or broken single-bit synchronizers.** Use the Quartus reports above as the primary verification artefact; supplement with a CDC linter (Spyglass-class or equivalent) if available. Light SVA assertions on the source-side handshake (e.g. "no new pulse while `sending_ready == 0`") catch source-side discipline errors; see [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md).
5. **Source-side launch register check.** Grep the RTL around every CDC instance: the signal feeding `bit_in` (or the toggle synchronizer's `sending_pulse_in`) must come from a flop in the source clock domain with no intervening combinational logic. This is anti-pattern 7.5; the lint is mechanical and worth doing.

## 9. Provenance footer

- `references/projects/FPGADesignElements/CDC_Bit_Synchronizer.v` @ 2026-05-20 — used for §2 (level-chain structure, dedicated-module attribute pattern, single-bit-per-crossing rule, source-register rule, default chain depth, power-up value, [V] chain depth), §3.1 (verbatim 2FF module), §3.4, §6 (3FF chain), §7.2 (attribute set), §7.5 (source-register rule).
- `references/projects/FPGADesignElements/CDC_Pulse_Synchronizer_2phase.v` @ 2026-05-20 — used for §2 (pulse-via-toggle rule), §3.2 (verbatim 2-phase toggle synchronizer body), §3.4, §4.2 (latency arithmetic), §6 (2-phase entry), §7.3 (fix reference).
- `references/projects/FPGADesignElements/CDC_Pulse_Synchronizer_4phase.v` @ 2026-05-20 — used for §6 (4-phase entry, recommendation to prefer 2-phase).
- `references/projects/FPGADesignElements/CDC_Flag_Bit.v` @ 2026-05-20 — used for §6 (`CDC_Flag_Bit` entry).
- `references/raw/fpgacpu/cdc.html` @ 2026-05-20 — used for §2 (single-bit-per-crossing rule, second citation), §4.1 (latency cases enumeration).
- `references/raw/verilogpro/cdc_part1.html` @ 2022-09-29 — used for §2 (source-register rule, second citation; pulse-via-2FF failure), §2 (chain depth 2 vs 3 [V] citation), §6 (feedback synchronizer entry), §7.1 (one-flop symptom), §7.3 (pulse-misses-edge citation), §7.5 (source-register rule, second citation).
- `https://www.sunburst-design.com/papers/CummingsSNUG2008Boston_CDC.pdf` — Cummings SNUG 2008 Boston *Clock Domain Crossing (CDC) Design & Verification Techniques Using SystemVerilog* — used for §2 (synchronizer-chain requirement, 2FF chain structure, chain-depth-2-default convention), §4.3 (mechanism reference), §6 ([V] 3FF chain entry), §7.1 (one-flop citation). **Live URL only; local capture is a fetch-failure stub at `references/raw/methodology/CummingsSNUG2008Boston_CDC_fetch_failed.html` and `..._sunburstdesign_fetch_failed.html`; Phase 4 cannot verify from disk.**
- `https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/managing-metastability-with-the-software-44819` — Intel *Managing Metastability with the Quartus Prime Software* (Quartus Standard 18.1 design-recommendations) — used for §2 (synchronizer-chain requirement, **dedicated-module rule [C]**, SDC-on-CDC-paths cross-reference), §7.2 (dedicated-module anti-pattern citation), §8 (Synchronizer Statistics report, MTBF reading). **Live URL only; local capture `references/raw/intel/quartus_metastability_management.html` is a 71-line app shell; the CDC-synchronizer-constraints sibling section `references/raw/intel/quartus_cdc_synchronizer_constraints.html` is the same live URL and also an app-shell. Phase 4 cannot verify from disk.**
- `https://docs.altera.com/r/docs/683068/current` — Intel Quartus Standard Timing Analyzer User Guide (`set_false_path` and `set_clock_groups -asynchronous` syntax) — used for §2 (SDC-exception rule), §3.3 (SDC fragment), §7.4 (citation), §8 (Inter-Clock Paths check). **Live URL primary; local capture `references/raw/intel/quartus_standard_timing_analyzer.html` is a 71-line app shell. Phase 4 cannot verify from disk.**
- `cyclone-v-hdl-bundle/01-glossary.md` @ 2026-05-19 — used for term references (`metastability`, `2FF synchronizer`, `MTBF`, `single-clock-domain design`).
- `cyclone-v-hdl-bundle/16-resource-and-state-economy.md` @ 2026-05-19 — cross-reference for §2 [I] same-clock-defensive rule and §7.6 (primary home).
- `cyclone-v-hdl-bundle/11-clocking-resets-and-cyclone-v-clock-networks.md` @ 2026-05-19 — cross-reference for §1 (load order) and §2 [V] reset convention.
- `cyclone-v-hdl-bundle/24-cdc-multi-bit.md` @ 2026-05-19 — cross-reference for multi-bit CDC (§1, §2 single-bit-per-crossing).
- `cyclone-v-hdl-bundle/40-timing-closure-and-sdc.md` @ 2026-05-19 — cross-reference for full SDC essentials (§3.3).
- `cyclone-v-hdl-bundle/41-quartus-reports-and-verification.md` @ 2026-05-19 — cross-reference for full Quartus report-reading discipline and SVA handshake assertions (§8).
