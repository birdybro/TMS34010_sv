# Clocking, Resets, and Cyclone V Clock Networks

> Bundle version: 2026-05-19
> Pinned commits: `references/MANIFEST.md` 2026-05-20 capture (Intel/Altera, FPGACPU.ca, lowRISC, ZipCPU)
> Load with: [10-hardware-mindset-and-microarchitecture.md](10-hardware-mindset-and-microarchitecture.md), [12-synthesizable-sv-subset.md](12-synthesizable-sv-subset.md), [13-registers-and-combinational-blocks.md](13-registers-and-combinational-blocks.md), [23-cdc-single-bit.md](23-cdc-single-bit.md), [24-cdc-multi-bit.md](24-cdc-multi-bit.md), [40-timing-closure-and-sdc.md](40-timing-closure-and-sdc.md), [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md)
> Status mix: [C]-heavy (Intel-mandated synthesis rules dominate the contract); a small handful of [V] (single-clock default, polarity convention, IP-vs-RTL choice), a few [O] (specific implementation patterns), and a few [I] (network-tier choice and reset-fanout judgment with no direct source mandate).

## 1. Purpose & one-line summary

This doc establishes the Cyclone V clocking-and-reset contract: design synchronously around a single clock domain by default, drive every flop from a clock network (never from fabric logic), and reset with the async-assert / sync-release pattern through a per-domain synchronizer. It names the Cyclone V clock-network primitives (GCLK / RCLK / PCLK / fractional PLL / clock-control block) and bounds the choice. The doc's deliverable into the consuming agent's pre-RTL plan (see [10-hardware-mindset-and-microarchitecture.md](10-hardware-mindset-and-microarchitecture.md)) is a clock list (each clock named and sourced from a PLL or pin), a declared reset polarity, a named sync-release plan per domain, and an explicit rejection of any fabric-derived clock. CDC mechanics (synchronizer chains, MTBF, multi-bit crossings) are deferred to [23-cdc-single-bit.md](23-cdc-single-bit.md) and [24-cdc-multi-bit.md](24-cdc-multi-bit.md); SDC writing is deferred to [40-timing-closure-and-sdc.md](40-timing-closure-and-sdc.md).

## 2. The contract (must-obey)

- [C] Every flop in synthesizable RTL is clocked from a clock network (a dedicated clock pin, a PLL output, or a recognized internally driven GCLK/RCLK/PCLK), not from combinational fabric logic. "In a synchronous design, a clock signal triggers all events" — Intel *Arria V and Cyclone V Design Guidelines*, Design Entry checklist item 1 (`references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt` p. 30, Nov 2016).

- [C] Clocks are not generated in fabric: do not AND/OR/XOR a clock with logic to "gate" it, do not feed a divider register's output to a downstream flop's clock pin, do not MUX two clocks through LUT logic. Intel mandates the dedicated clock control block or the PLL clock-switchover feature for any clock multiplexing or gating, and the device PLLs for any clock inversion, multiplication, or division (`references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt` p. 30, Design Entry item 2; live Cyclone V clock-networks doc at https://docs.altera.com/r/docs/683375/current/clock-networks-and-pll.html @ 2026-05-20, live URL, no local capture).

- [C] Reset to a Cyclone V flop is either a synchronous clear driven by destination-clock logic, or an asynchronously-asserted external reset that has been re-synchronized to the destination clock for de-assertion ("async-assert / sync-release"). Pure-async reset wired straight from a pin to many domains' flops without any sync-release stage is not permitted on a design that must close timing across its reset network. "The recommended reset architecture allows the reset signal to be asserted asynchronously and deasserted synchronously … synchronous deassertion avoids an asynchronous reset signal from being released at, or near, the active clock edge of a flipflop that can cause the output of the flipflop to go to a metastable unknown state" — Intel *Arria V and Cyclone V Design Guidelines*, Design Entry item 9 (`references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt` p. 33, Nov 2016). Cross-confirmed by FPGACPU.ca *Verilog Coding Standard*, Resets section (`references/raw/fpgacpu/verilog_coding_standard.html` lines 714–780).

- [C] Reset polarity is consistent across the design. A reset net does not change polarity between modules sharing it; if a domain requires the opposite polarity, invert exactly once at the boundary and name the resulting net accordingly. lowRISC's industry convention is active-low async (`rst_ni`, `rst_n`), and any project must pick one polarity and apply it everywhere — the rule is consistency, not the specific polarity. Cite: lowRISC SystemVerilog Style Guide, *Resets* and *Active-Low Signals* sections (`references/raw/style/lowrisc_systemverilog_style.md` lines 1372–1394 and lines 2935–2947).

- [V] Clock-enable is the synthesizable substitute for clock gating. Where the original hardware "stopped a clock," the FPGA model is an enable bit feeding `if (en) q <= d;` inside the destination clock's `always_ff`. Intel highlights LAB-wide clock-enable promotion as a power and routing benefit; FPGACPU's `Register` template combines this with an async reset port. Cite: `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt` p. 41 item 7 (clock power management); `references/raw/fpgacpu/verilog_coding_standard.html` lines 838–900.

- [V] Single clock domain is the default. Add a domain only when an external interface mandates one (audio DAC bit-clock, video pixel clock from an external source, HPS-FPGA bridge clock). Every additional domain pays for itself in synchronizers, async FIFOs, and verification effort. Cite (mindset): FPGACPU *Verilog Coding Standard*, opening "Synchronous Logic" framing (`references/raw/fpgacpu/verilog_coding_standard.html` lines 420–470); naming convention from lowRISC (`references/raw/style/lowrisc_systemverilog_style.md` lines 1306–1370).

- [I] Choose the smallest clock network that covers the fanout. Use PCLK for I/O-region-local clocks, RCLK for a clock confined to one device quadrant, GCLK for a clock that fans out across the device. On 5CSEBA6U23I7 the GCLK budget is 16 networks (`references/raw/intel/cyclone_v_product_table_api.txt`, "Clocks, Maximum I/O Pins, and Architectural Features" table, Cyclone V SoC column, 2025-09-24 cap); over-promoting clocks to GCLK wastes the budget and can prevent fitting. The inferential chain: Intel's design-entry checklist names the three tiers and their reach (Arria V/Cyclone V design guidelines item 1 of Clock Planning, `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt` p. 24); the product table gives the 16-GCLK number; the inference "use the smallest that covers your fanout" is the obvious resource-economy consequence (cross-reference [16-resource-and-state-economy.md](16-resource-and-state-economy.md)). No single corpus source phrases the rule as an imperative — hence [I].

- [I] Reset-network fanout must be analyzed before commit. If the released-reset net reaches more than one clock region or fanout is high enough to fail recovery/removal, re-synchronize per region or per clock domain rather than allowing the fitter to route a single released-reset net as a generic high-fanout signal. The inferential chain: Intel's design-entry item 9 says the async-reset source "can be directly connected to global routing resources" (`references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt` p. 33); Intel's item 8 says LAB-level dedicated control signals are limited and must be respected (same file, p. 32); the GCLK budget is 16 on this part (product table, above). The combination — async-reset is global-routable but global routing is finite, and recovery/removal slack tightens as fanout and skew grow — drives the "analyze before commit" rule. No corpus source mandates the rule in those words; downgraded to [I] per brief.

## 3. Constructs / signals / primitives

### 3.1 Cyclone V clock-network primitives

| Name | Count on 5CSEBA6U23I7 | Reach | Sanctioned use | Source for count |
|---|---|---|---|---|
| GCLK (global clock network) | 16 | device-wide | system clocks, design-wide reset distribution, high-fanout control | `references/raw/intel/cyclone_v_product_table_api.txt` (SoC column, "Global clock networks: 16") |
| RCLK (regional clock network) | quadrant-local, count not enumerated in local corpus | one device quadrant | clocks confined to a region; lowest skew within a quadrant | live URL https://docs.altera.com/r/docs/683375/current/clock-networks-and-pll.html @ 2026-05-20 (live URL, no local capture) |
| PCLK (periphery clock network) | per-periphery, count not enumerated in local corpus | I/O periphery / pin clusters | I/O-local clocks (transceiver refclk consumers, pin-fed source-synchronous interfaces) | `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt` p. 24, Clock Planning item 1, "PCLK networks are a collection of individual clock networks driven from the periphery of the device" |
| Fractional PLL | 6 (FPGA-side) on 5CSEBA6U23I7 | drives clock networks | the only sanctioned source of a derived-frequency clock from a board oscillator | `references/raw/intel/cyclone_v_product_table_api.txt` (SoC column, "PLLs (FPGA): 6") |
| Dedicated clock-control block (`ALTCLKCTRL` / clkena) | per GCLK/RCLK | local to its network | the only sanctioned way to MUX, gate, or power-down a clock | `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt` p. 32, Clock Planning item 5 |

[C] for the count of 16 GCLK on this part (product table is authoritative). [V] for the count of 6 FPGA-side PLLs (same source). [I] for RCLK/PCLK exact counts on this device variant — the brief asserts "88 RCLK" but neither the local product-table capture nor the local design-guidelines capture enumerates an RCLK number for the Cyclone V SoC line; the Cyclone V Device Handbook Volume 1 ("Clock Networks and PLLs in Cyclone V Devices") is the canonical source and is an app-shell locally, hence the live-URL citation. Treat the per-device RCLK count as something to confirm from the live handbook before committing to a design that depends on the exact number.

### 3.2 Verbatim Intel statement on the clock-network tiers

```
// references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt p.24 (Nov 2016 revision)
The GCLK networks can drive throughout the entire device, serving as low-skew clock
sources for device logic. This clock region has the maximum delay compared to other
clock regions but allows the signal to reach everywhere within the device. This option
is good for routing global reset/clear signals or routing clocks throughout the device.

The RCLK networks only pertain to the quadrant they drive into and provide the lowest
clock delay and skew for logic contained within a single device quadrant.

IOEs and internal logic can also drive GCLKs and RCLKs to create internally generated
GCLKs or RCLKs and other high fan-out control signals; for example, synchronous or
asynchronous clears and clock enables.

PLLs cannot be driven by internally-generated GCLKs or RCLKs. The input clock to the
PLL must come from dedicated clock input pins or from another pin/PLL-fed GCLK or RCLK.

PCLK networks are a collection of individual clock networks driven from the periphery
of the device. ... These PCLKs have higher skew compared to GCLK and RCLK networks ...
```

### 3.3 Verbatim Intel rule on clock generation in fabric

```
// references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt p.30 (Nov 2016 revision)
Consider the following recommendations to avoid clock signals problems:
  Use dedicated clock pins and clock routing for best results...
  For clock inversion, multiplication, and division use the device PLLs.
  For clock multiplexing and gating, use the dedicated clock control block or PLL clock
    switchover feature instead of combinational logic.
  If you must use internally generated clock signals, register the output of any
    combinational logic used as a clock signal to reduce glitches. For example, if you
    divide a clock using combinational logic, clock the final stage with the clock signal
    that was used to clock the divider circuit.
```

[C] This is the citation behind §2's fabric-gated-clock prohibition. The closing "if you must" clause is a hardening hint for unavoidable legacy code, not a license to design new RTL around fabric-derived clocks.

### 3.4 Verbatim Intel rule on async-assert / sync-release reset

```
// references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt p.33 (Nov 2016 revision)
Review recommended reset architecture
  If the clock signal is not available when reset is asserted, an asynchronous reset is
    typically used to reset the logic.
  The recommended reset architecture allows the reset signal to be asserted asynchronously
    and deasserted synchronously.
  The source of the reset signal is connected to the asynchronous port of the registers,
    which can be directly connected to global routing resources.
  The synchronous deassertion allows all state machines and registers to start at the
    same time.
  Synchronous deassertion avoids an asynchronous reset signal from being released at, or
    near, the active clock edge of a flipflop that can cause the output of the flipflop
    to go to a metastable unknown state.
```

[C] This is the citation behind §2's reset rule.

### 3.5 Cyclone V flop power-up behavior

```
// references/raw/fpgacpu/verilog_coding_standard.html lines 761-768 @ 2026-05-20
FPGA flops can very roughly be split into four categories:
  not initialisable (QuickLogic EOS S3)
  constant zero (Intel Cyclone V; Lattice iCE40)
  fully configurable (Xilinx 7 Series)
  init-matches-set (Lattice ECP5)
```

[O] Specific to Cyclone V (constant-zero power-up). Practical consequence: a register declared with `initial reg q = 1'b1;` in source will not power up high in Cyclone V silicon — it will power up at 0, and synthesis will reach the declared value either via reset assertion, via the `NOT-gate push back` optimization the Intel design guidelines describe (`references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt` p. 33, item 10), or not at all. Design accordingly: reset any flop whose post-power-up value matters.

### 3.6 Named signals introduced in this doc

| Signal | Type / direction | Meaning | Driven by | Drives |
|---|---|---|---|---|
| `clk` | input, 1-bit | primary system clock (PLL output or pin) | PLL or dedicated clock pin | every `always_ff` in its domain |
| `arst_n` | input, 1-bit (active low) | external asynchronous reset (button, watchdog, configuration done) | external pin or device-wide reset | the async port of the per-domain sync-release synchronizer |
| `rst_n` | wire, 1-bit (active low) | per-domain synchronized released reset | sync-release synchronizer in this clock domain | the async-clear port of every flop in this domain that needs reset, or the synchronous-clear logic for the rest |
| `pll_locked` | wire, 1-bit | PLL lock indicator | PLL macro `locked` output | logical AND with `arst_n` into the sync-release input |
| `en` | wire, 1-bit | clock-enable bit gating data updates inside `always_ff` | datapath control or FSM | `if (en) q <= d;` inside the `always_ff` |

## 4. Sequencing & timing

### 4.1 Reset assertion vs. release

A reset asserted asynchronously takes effect at the flop immediately — independent of clock edge — by way of the flop's dedicated async-clear/async-set hardware. Quartus models this on the Cyclone V flop. Reset *release* must be timed to a clock edge so that downstream flops do not sample a release that occurs inside their setup/hold window. The standard release pattern is a 2-flop synchronizer with its async-clear tied to the upstream async-asserted reset:

```
clk        __/--\__/--\__/--\__/--\__/--\__/--\__/--\__/--\__
arst_n     ----\___________/-------------------------------------
                ^ asserts at any phase           ^ external release
sync_q1    --------------\___________/-----------\____/------- (async-cleared while arst_n low)
sync_q2    -----------------\___________/-----------\____/----  (one extra cycle delay)
rst_n      ---------------------\___________/----------\___/---  (= sync_q2 directly; released on clk edge)
```

The async assertion drops `sync_q1` and `sync_q2` immediately (they have their own async-clear). On release, `sync_q1` samples a logic-1 (tied high), `sync_q2` samples `sync_q1` one cycle later, and the downstream `rst_n` rises on a `clk` edge two cycles after `arst_n` returns high. A third flop is common where MTBF margin matters; mechanics belong in [23-cdc-single-bit.md](23-cdc-single-bit.md).

### 4.2 PLL lock

`pll_locked` is asynchronous to the PLL output clock until the PLL settles. Treat it as a reset input: AND it with `arst_n` *into* the sync-release input, so the downstream `rst_n` does not rise until both the external reset has released and the PLL has locked. Without this, downstream flops can briefly clock from an unstable PLL output during lock acquisition.

### 4.3 What lives where

- Single-bit synchronizer mechanics, MTBF math, Quartus metastability-analyzer interpretation → [23-cdc-single-bit.md](23-cdc-single-bit.md).
- Multi-bit crossings, async FIFO architecture → [22-fifos-synchronous-and-asynchronous.md](22-fifos-synchronous-and-asynchronous.md) and [24-cdc-multi-bit.md](24-cdc-multi-bit.md).
- SDC clock definitions (`create_clock`, `derive_pll_clocks`, `set_false_path` on async deassertion), recovery/removal interpretation → [40-timing-closure-and-sdc.md](40-timing-closure-and-sdc.md).

## 5. Minimal working pattern

The smallest correct usage: one top-level module wraps a clock pin and an async reset pin, instantiates a PLL (shown as a placeholder — vendor IP cannot be reproduced verbatim), runs the released reset through a per-domain synchronizer, and uses the synchronized reset plus a clock-enable inside a clean `always_ff`. The clock-enable is the synthesizable substitute for "stopping a clock."

```systemverilog
// Composite pattern. Cites:
//   references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt p.33 (sync-release rule)
//   references/raw/fpgacpu/verilog_coding_standard.html lines 838-900 (clock-enable + areset Register)
//   references/raw/style/lowrisc_systemverilog_style.md lines 1372-1394 (active-low async naming)
`default_nettype none

module clocking_min_example #(
    parameter int WIDTH       = 8,
    parameter logic [WIDTH-1:0] RESET_VALUE = '0
) (
    input  wire                  clk_in,      // board oscillator on a dedicated clock pin
    input  wire                  arst_n_in,   // external reset button / config done, active low, async
    input  wire                  en_in,       // datapath enable (the "stop-the-clock" replacement)
    input  wire  [WIDTH-1:0]     data_in,
    output logic [WIDTH-1:0]     data_out
);

    // ---------- 1. PLL: derived clock + locked indicator ----------
    // Instantiate the Intel ALTPLL/IOPLL IP via the IP catalog. The user-RTL boundary
    // is `clk` and `pll_locked`. Do not write a fabric divider as a substitute. Cite:
    //   references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt p.30, item 2.
    wire clk;
    wire pll_locked;
    // pll_core u_pll (.refclk(clk_in), .outclk_0(clk), .locked(pll_locked), .rst(!arst_n_in));

    // ---------- 2. Async-assert / sync-release reset, gated by PLL lock ----------
    // Async-clear (negedge of (arst_n & pll_locked)) drops the chain immediately.
    // Two-flop synchronizer releases rst_n on a clk edge.
    wire async_n = arst_n_in & pll_locked;
    logic sync_q1, sync_q2;
    always_ff @(posedge clk or negedge async_n) begin
        if (!async_n) begin
            sync_q1 <= 1'b0;
            sync_q2 <= 1'b0;
        end else begin
            sync_q1 <= 1'b1;
            sync_q2 <= sync_q1;
        end
    end
    wire rst_n = sync_q2;

    // ---------- 3. Clock-enable in destination flop. THIS REPLACES CLOCK GATING. ----------
    // The "always_ff with `if (en)`" body is the FPGA-faithful substitute for gating a clock.
    // Cross-ref to [13-registers-and-combinational-blocks.md] for the discipline of
    // one driver per signal and default assignments.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out <= RESET_VALUE;
        end else if (en_in) begin
            data_out <= data_in;
        end
        // else: hold. The clock keeps toggling; the data simply does not update.
        // This is the synthesizable model of "stopped clock."
    end

endmodule
```

What this pattern delivers:

- Exactly one clock (`clk`) in the example's domain. Source is a PLL output, not a fabric divider.
- Reset asserts asynchronously at any phase; releases synchronously to `clk`, two cycles after the combined `arst_n & pll_locked` returns high.
- Clock-enable controls *whether the data flop updates*, not whether the clock toggles. The fitter places this `en` on the LAB-wide clock-enable resource where possible (`references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt` p. 41, item 7 — "the LAB-wide clock enable signal").
- One driver per signal in `always_ff`; nonblocking assignments only; defaults in the else-branch (hold). See [13-registers-and-combinational-blocks.md](13-registers-and-combinational-blocks.md) for the broader discipline.

The PLL instantiation line is a placeholder. The board oscillator on a Cyclone V design is sourced through a dedicated clock pin; the PLL is configured via the IP catalog (ALTPLL/IOPLL) with the requested output frequency. Do **not** substitute a fabric register-divider for the PLL.

## 6. Common variations across implementations

- [O] FPGACPU `Register` module (`references/raw/fpgacpu/verilog_coding_standard.html` lines 861–900) wraps the async-reset / clock-enable / synchronous-clear combination as one parametric Verilog-2001 module. It uses `always @(posedge clock or posedge areset)` (active-high async reset), keeps `areset` priority over `clock_enable` via *nested* if-statements rather than "last assignment wins," and asserts that the upstream `areset` is "fed by a synchronous reset signal" (i.e. a release-synchronizer feeds the async port). Style consequence: any "areset" pin in this codebase already implies the sync-release stage upstream.

- [O] lowRISC convention (`references/raw/style/lowrisc_systemverilog_style.md` lines 1372–1394). Active-low async reset named `rst_ni` (or `rst_n` at chip boundary), preferred form is `always_ff @(posedge clk_i or negedge rst_ni) begin if (!rst_ni) ... end`, with the sync-release implemented inside the module that owns the domain. The convention is enforced by the style guide rather than by Intel; pick the polarity and apply it everywhere.

- [O] ZipCPU material (`references/extracted_text/zipcpu/class_verilog.txt` lines 9015–9056, 13460–13520). Distinguishes two cases: (a) "Be aware of the asynchronous reset signal!" for external interfaces where reset arrives before any clock is stable (e.g. PLL reset, input deserializer reset) — here async assertion is required and the formal property must explicitly model `i_areset_n` on the sensitivity list; (b) ordinary internal logic where a purely synchronous reset suffices because the configuration bitstream defines the post-power-up state. The structural choice between the two is per-module, not project-wide.

- [V] Vendor-IP boundary. Instantiating the Intel ALTPLL/IOPLL IP from the Quartus IP catalog (or using `derive_pll_clocks` in SDC against an instantiated PLL) is the sanctioned route for any derived clock. The user-RTL boundary is the PLL output clock and `locked` signal. This is the structural variation, not a correctness rule — `derive_pll_clocks` is named in Intel's design guidelines as the recommended SDC entry-point for PLL-fed clocks (`references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt` p. 47, Timing Constraints checklist).

## 7. Anti-patterns (mistakes that compile but break)

### #9 Gated or fabric-derived clock

- **Symptom:** TimeQuest reports a `derived_clock` from a non-clock-network source; the Fitter warns that a clock signal is being routed on non-global routing; in hardware, registers downstream of the "clock" intermittently drop edges or glitch under environmental change. Synthesis may also infer the divider/AND as ordinary combinational logic and refuse to constrain the path correctly.
- **Cause:** The clock at a flop's clock pin is generated in fabric — by AND-gating an enable into the clock, by using a divider flop's output directly as the next stage's clock, or by MUX'ing two clocks through LUT logic. This violates the synchronous-design contract and corrupts both the fitter's clock-network planning and the static timing model.
- **Fix:** Derive the new frequency from a PLL output (the only sanctioned source of a different frequency) and consume it on a clock network. If the goal was "stop the clock," convert to a clock-enable inside `always_ff` (§5). For clock MUX/gate behavior that cannot be PLL-sourced, use the dedicated clock-control block (`ALTCLKCTRL` with `clkena`) and route the result on a GCLK/RCLK.
- **Citation:** Intel *Arria V and Cyclone V Design Guidelines* p. 30, Design Entry item 2 ("For clock multiplexing and gating, use the dedicated clock control block or PLL clock switchover feature instead of combinational logic", `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt`); Cyclone V Device Handbook Volume 1 "Clock Networks and PLLs in Cyclone V Devices" live URL https://docs.altera.com/r/docs/683375/current/clock-networks-and-pll.html @ 2026-05-20 (live URL, no local capture). [C]

### #10 Async reset without sync release

- **Symptom:** Design works in functional simulation; on hardware, flops downstream of the reset come out of reset on the wrong clock edge, settle into wrong states, or hang in metastable behavior near reset release. Failures are intermittent and tend to cluster around the moment the external reset button is released or the configuration `nSTATUS` settles.
- **Cause:** An external reset is wired straight to every flop's async-clear port without a per-domain synchronizer. The async assertion is fine; the async release lands within the setup/hold window of some flops, which sample metastable values and propagate them.
- **Fix:** Insert a 2-flop (or 3-flop where MTBF margin demands) sync-release synchronizer per clock domain. The chain's async-clear pin sees the external reset; its data-in is tied high; its second output drives the per-domain `rst_n` consumed by `always_ff` blocks. Pattern shown in §5; mechanics in [23-cdc-single-bit.md](23-cdc-single-bit.md).
- **Citation:** Intel *Arria V and Cyclone V Design Guidelines* p. 33, Design Entry item 9 ("synchronous deassertion avoids an asynchronous reset signal from being released at, or near, the active clock edge of a flipflop that can cause the output of the flipflop to go to a metastable unknown state", `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt`); FPGACPU.ca *Verilog Coding Standard* Resets section (`references/raw/fpgacpu/verilog_coding_standard.html` lines 720–725, 856–860). [C]

### #11 Reset polarity inconsistency across modules

- **Symptom:** Behavior in simulation depends on which module is loaded first; some submodules stay in reset while others come out; the released-reset net shows odd routing in the Fitter report and may even be inferred as two separate nets that the synthesizer hoped were the same. The most-cited variant: top-level uses `rst_n` (active-low) but a leaf module written by a different author uses `rst` (active-high) and the two are wired together expecting "they're both reset, right?"
- **Cause:** Modules sharing a physical reset net disagree on polarity. The Verilog connectivity is legal (a wire is a wire), so synthesis happily passes; the semantic mismatch silently flips one or more modules' reset condition.
- **Fix:** Pick one polarity per project (lowRISC-style active-low async `rst_n` is the convention in this bundle). Name nets accordingly. If a sub-block honestly needs the opposite polarity (e.g. wrapping an IP block that exposes only `rst`), invert exactly once at the instantiation boundary and name the inverted local wire (`rst = ~rst_n;`) so the polarity-inversion is local and reviewable.
- **Citation:** lowRISC SystemVerilog Style Guide, *Resets* (`references/raw/style/lowrisc_systemverilog_style.md` lines 1372–1394) and *Active-Low Signals* (same file, lines 2935–2947). [C] for the rule "consistency" (style guide mandates active-low; this bundle promotes the polarity to a project-wide consistency contract).

### #12 Reset network with no analysis of fanout

- **Symptom:** A small build closes timing comfortably; as the design grows, the released-reset net (or any high-fanout async net) starts showing recovery/removal violations or unexplained skew at scale. The fitter routes the reset on whatever resources are available, and the resulting skew across reset endpoints becomes inconsistent with the per-clock release timing the design was reasoning about.
- **Cause:** The released `rst_n` is treated as a fan-out-free signal and wired to every module. With enough endpoints across enough regions, no single low-skew network covers it, and the fitter splits the load across resources with different delays. Async assertion still works; synchronous release timing drifts across endpoints.
- **Fix:** Analyze the reset's fanout before commit. For designs of any size, re-synchronize the released reset *per region* (drive the global async `arst_n` into a sync-release in every clock region that needs reset, rather than fanning out a single `rst_n` from one synchronizer to the whole chip). Confirm in the Fitter report (clock-network and high-fanout-signal sections) that no single reset net exceeds a routable budget. Cross-reference [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md) for the specific reports to read.
- **Citation:** [I] — no corpus source mandates this in those words. Inferential chain: (i) Intel design-entry item 9 explicitly permits the reset source to be "connected to global routing resources" (`references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt` p. 33), but says nothing about budget when fanout is large; (ii) Intel design-entry item 8 says LAB-level dedicated control signals are finite and must be respected (same file, p. 32); (iii) the 5CSEBA6U23I7 part has 16 GCLK and a finite RCLK/PCLK budget (product table, `references/raw/intel/cyclone_v_product_table_api.txt`). Combining (i)–(iii): a global async reset *can* be put on a clock network, but the budget is bounded; large designs must either share the network or re-synchronize per region. No single source phrases the obligation as a rule.

### #13 (bonus) Reset asserted by a glitching combinational signal

- **Symptom:** Sporadic mid-operation resets in hardware that never reproduce in simulation; logic appears to reset itself at random.
- **Cause:** The async-reset input to a sync-release chain (or to a flop's async port directly) is driven by combinational logic that can glitch (e.g. an AND of two unrelated status bits, or a comparator output). A combinational glitch on the async-clear pin asserts reset on the flop *immediately*, no clock edge needed.
- **Fix:** Register the reset source. Even if the resulting reset is logically the same, a registered output cannot glitch (intra-cycle), and the async-clear pin sees a clean transition. FPGACPU's standard repeats this: "even though the flip-flop reset hardware is asynchronous, it should be fed by a synchronous reset signal" (`references/raw/fpgacpu/verilog_coding_standard.html` lines 856–860).
- **Citation:** FPGACPU.ca *Verilog Coding Standard* lines 856–860. [V]

## 8. Verification

- **TimeQuest:** Confirm exactly one clock per intended domain in the SDC. Confirm no `derived_clock` originates from a non-clock-network source (any such derived clock is a fail and the design must be re-architected). Confirm recovery and removal slack on every released-reset endpoint (`report_min_pulse_width` and the recovery/removal sections of `report_timing`).
- **Fitter report:** Confirm GCLK usage is within the 16-network budget for 5CSEBA6U23I7 (`references/raw/intel/cyclone_v_product_table_api.txt`). Confirm RCLK and PCLK usage are within their respective budgets per the Cyclone V Device Handbook (live URL https://docs.altera.com/r/docs/683375/current/clock-networks-and-pll.html). Confirm the released-reset net is routed on a recognized clock or high-fanout network, not on generic routing for a wide region.
- **Simulation:** Drive `arst_n` low at irregular phases relative to `clk` (asynchronously, at multiple sub-cycle offsets). Confirm release always lands on a `clk` edge after the sync-release latency (2 cycles minimum). Cover reset assertion during normal operation (mid-FSM, mid-handshake) for any module that resets on an event other than power-up.
- **Quartus metastability analyzer:** Confirm the sync-release chain is recognized as a synchronizer and reported with MTBF. Mechanics in [23-cdc-single-bit.md](23-cdc-single-bit.md) and [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md).
- **Lint / review gate:** Grep the design for the forbidden patterns. Zero matches before commit:
  - `always @(posedge gated_clk)` or `always_ff @(posedge gated_clk)` where `gated_clk` is the output of an `assign gated_clk = a & b;` (or `|`, or a MUX) in the same module — fabric-gated clock.
  - Two different polarities (`rst` and `rst_n`, or two different reset names) connected to the same instance hierarchy net — polarity inconsistency.
  - A flop with `posedge clk or posedge arst` where `arst` is driven by `assign arst = ~done & error;` — combinational glitch into async-clear.
- **Pre-RTL plan check:** The clocking section of the plan from [10-hardware-mindset-and-microarchitecture.md](10-hardware-mindset-and-microarchitecture.md) must name every clock, the PLL or pin sourcing it, the chosen reset polarity, and the sync-release placement per domain before any sequential RTL is written.

## 9. Provenance footer

- `references/raw/intel/arria_v_cyclone_v_design_guidelines_api.txt` @ Nov 2016 revision (Intel *Arria V and Cyclone V Design Guidelines*, 22-page PDF in the local corpus; extracted via `pdftotext`) — primary source for §2 (every [C] rule on synchronous design, fabric-clock prohibition, async-assert / sync-release, clock-network tiers), §3.2, §3.3, §3.4, §3.6, §6 (vendor-IP boundary), §7 #9 and #10 (Intel-anchored citations), §8.
- `references/raw/intel/cyclone_v_product_table_api.txt` @ 2025-09-24 cap (Cyclone V FPGA and SoC FPGA Product Table, 2-page PDF; extracted via `pdftotext`) — authoritative count of 16 GCLK and 6 FPGA-side PLLs on the 5CSEBA6 SoC line. Used in §2 [I] (clock-network choice), §3.1 (counts table), §7 #12 (inferential chain), §8.
- `references/raw/fpgacpu/verilog_coding_standard.html` @ 2026-05-20 capture (FPGACPU.ca *Verilog Coding Standard*, lines 712–900) — used for §2 (sync-release cross-confirmation, clock-enable pattern), §3.5 (Cyclone V flop power-up = constant zero, lines 761–768), §5 (clock-enable + `areset` Register template), §6 [O] (FPGACPU Register module), §7 #10 (cross-citation), §7 #13 (registered reset source).
- `references/raw/style/lowrisc_systemverilog_style.md` @ 2026-05-20 capture, lines 1372–1394 and 2935–2947 — used for §2 (polarity-consistency rule and naming convention), §3 (signal naming), §5 (active-low `rst_n` convention), §6 [O] (lowRISC convention), §7 #11 (polarity inconsistency).
- `references/extracted_text/zipcpu/class_verilog.txt` @ 2026-05-20 capture, lines 9015–9056 and 13460–13520 — used for §6 [O] (ZipCPU async-reset framing for formal verification; case (a) external interfaces with async reset before clock stable, case (b) synchronous reset for ordinary internal logic).
- Cyclone V Device Handbook Volume 1, *Clock Networks and PLLs in Cyclone V Devices*, live URL https://docs.altera.com/r/docs/683375/current/clock-networks-and-pll.html @ 2026-05-20 (live URL, no local capture; local file `references/raw/intel/cyclone_v_clock_networks.html` is a documentation-app shell of 71 lines, no body content) — used for §3.1 (RCLK and PCLK device-level enumeration, exact counts not in local corpus), §7 #9 (clock-network rule cross-citation), §8.
- Intel *Quartus Prime Standard Edition User Guide: Design Recommendations*, live URL https://docs.altera.com/r/docs/683323/current @ 2026-05-20 (live URL, no local body; local files `quartus_standard_design_recommendations_index.html`, `quartus_standard_register_latch_guidelines.html`, `quartus_standard_general_coding_guidelines.html`, `quartus_standard_hdl_design_guidelines.html` are 71-line app shells, no body content per `references/MANIFEST.md`) — named as the umbrella reference behind the rules sourced from the Arria V/Cyclone V Design Guidelines (which themselves point back to it, e.g. p. 33 item 11 cites "the Recommended HDL Coding Styles chapter").
