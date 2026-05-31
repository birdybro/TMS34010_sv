# Cyclone V HDL Bundle — Index

> Bundle version: 2026-05-19
> Target part: Intel Cyclone V SoC `5CSEBA6U23I7` (Terasic DE10-Nano)
> Target toolchain: Intel Quartus Standard/Lite 18.1-era HDL coding guidance
> Language: SystemVerilog synthesis-safe subset (see [12-synthesizable-sv-subset.md](12-synthesizable-sv-subset.md))
> Scope: generic Cyclone V HDL practice — framework-agnostic; MiSTer wrapper not covered.

## What this bundle is

A drop-in reference for an AI agent that writes Verilog/SystemVerilog for Cyclone V FPGAs. It teaches:

- Parallel/pipelined microarchitecture thinking rather than software transliteration.
- The synthesizable SystemVerilog subset that maps cleanly to Cyclone V resources.
- Clock-domain, reset, and CDC discipline.
- Ready/valid handshakes, FIFOs, skid buffers.
- Cyclone V resource inference (M10K, MLAB, variable-precision DSP).
- Timing closure mindset, basic SDC, Quartus report reading.
- Verification expectations with light SVA handshake assertions.
- Resource economy (every register and bus bit must justify itself).
- Era-faithful microarchitecture for emulation cores (mirror the original chip).

## What this bundle is NOT

- The MiSTer framework wrapper (`sys_top.sv`, `hps_io`, status word, framework video/audio conventions). Covered by a separate companion bundle if needed.
- Vendor-IP wizards (beyond a brief "when to instantiate IP" note).
- Soft-CPU bring-up (Nios II), HPS-FPGA bridges, OpenCL.
- Deep formal verification (SymbiYosys, k-induction). Light SVA handshake assertions only.
- High-speed transceivers, DDR3 controller IP, PCIe.
- Tooling beyond Quartus Standard/Lite 18.1-era.

## Claim labels (load-bearing)

Every factual sentence in §2, §3, and §6 of every topic doc carries exactly one of:

- **[C] Contract** — strictly required by the upstream framework/protocol/synthesis. Violation breaks correctness.
- **[V] Convention** — common pattern not strictly required; violating is allowed but unusual.
- **[O] Observed in implementation X** — present in a specific instance at a specific revision; the instance is named.
- **[I] Inference** — synthesized from multiple sources; no single citation establishes it. Treat with care.

When loading topic docs, weight assertions accordingly: a [C] rule is non-negotiable; an [I] rule is a judgment call that depends on context.

## How to use the bundle

**Always load first:**

1. [00-INDEX.md](00-INDEX.md) (this file).
2. [01-glossary.md](01-glossary.md) — terms used throughout.
3. [02-source-map.md](02-source-map.md) — citation hub.

**Then selectively load topic docs relevant to your task.** Each topic doc declares its `Load with:` dependencies — load those too.

**For a cold start** (new agent, no prior context on the project):

- Read 10 (mindset), 12 (language subset), 13 (registers/comb), 16 (resource economy), 17 (era-faithful microarchitecture). That's the foundation.
- Then load topic-specific docs as the task requires.

**For review of completed RTL:**

- Load [91-core-bringup-checklist.md](91-core-bringup-checklist.md) for the sequential gate checklist.
- Load [90-anti-patterns.md](90-anti-patterns.md) and grep for symptoms.

## Reading order (dependency order)

Foundations (10-series, 8 docs) → Datapath patterns (20-series, 5 docs) → Cyclone V resource inference (30-series, 3 docs) → Quality & closure (40-series, 2 docs) → Patterns (90-series, 2 docs).

## Topic index

### Foundations

| # | File | Status mix | Topic |
|---|---|---|---|
| 10 | [10-hardware-mindset-and-microarchitecture.md](10-hardware-mindset-and-microarchitecture.md) | [C] ~15% / [V] ~40% / [O] ~15% / [I] ~30% | Describe circuits not algorithms; pre-RTL microarchitecture plan; for emulation, reverse-engineer the original chip. |
| 11 | [11-clocking-resets-and-cyclone-v-clock-networks.md](11-clocking-resets-and-cyclone-v-clock-networks.md) | [C]-heavy (Intel-mandated synth rules); few [V] (single-clock default, polarity, IP-vs-RTL); few [O]; few [I] (network-tier choice, reset-fanout) | Single-clock-domain default; async-assert sync-release reset; GCLK/PLL primitives; no gated/derived clocks. |
| 12 | [12-synthesizable-sv-subset.md](12-synthesizable-sv-subset.md) | Heavy [V] (Table B); substantial [C]; 4×[O] in §6; 8×[I] in Table B forbidden-construct rows | The allowed SystemVerilog constructs; what to avoid; widths/signedness explicit. |
| 13 | [13-registers-and-combinational-blocks.md](13-registers-and-combinational-blocks.md) | Heavy [C] (single-driver, NBA/blocking, latch avoidance); some [V] (ordering, naming); a few [O]; 1×[I] | One driver per signal; blocking-in-comb / nonblocking-in-seq; latch avoidance; one logical concern per `always` block. |
| 14 | [14-finite-state-machines.md](14-finite-state-machines.md) | [C] ~40% / [V] ~30% / [O] ~20% / [I] ~10% | One/two/three-block FSMs; encoding; default state; FSM extraction hints. |
| 15 | [15-pipelines-and-latency-thinking.md](15-pipelines-and-latency-thinking.md) | [V] and [O] dominate; [I] anchors cycle-accuracy/retiming; 2 firm [C] (valid-follows-data; cycle-accuracy preservation) | Pipeline registers; valid-follows-data; wrapping a cycle-accurate interface with internal pipelining. |
| 16 | [16-resource-and-state-economy.md](16-resource-and-state-economy.md) | [C] ~25% / [V] ~20% / [O] ~15% / [I] ~40% | Every register and bus bit must justify itself; minimum-sufficient-state; bus narrowing; FSM state minimization. |
| 17 | [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md) | Heavy [V] and [I]; few [C] (only no-internal-tristate is firm) | Mirror the original chip; resource sharing as the era's default; cycle-accurate external interface with internal pipelining only where invisible. |

### Datapath patterns

| # | File | Status mix | Topic |
|---|---|---|---|
| 20 | [20-ready-valid-handshakes.md](20-ready-valid-handshakes.md) | [C] dominates §2 (3 protocol rules + composability + comb-restriction); [V] naming/asymmetry; [O] in §6; [I] only via reinforcing sources | No valid-drop; payload-stable while `!ready`; work on `valid && ready`. |
| 21 | [21-skid-buffers-and-register-slices.md](21-skid-buffers-and-register-slices.md) | §2: 3×[C], 2×[V]; §3: [C]/[V]; §6: 4×[O], 1×[V]; §7 mixes cited entries with 1×[I] | When ready paths break timing; canonical skid buffer; FWFT equivalence. |
| 22 | [22-fifos-synchronous-and-asynchronous.md](22-fifos-synchronous-and-asynchronous.md) | [C] ~45% / [V] ~20% / [O] ~15% / [I] ~20% | Sync and async FIFOs; Gray pointers; MLAB vs M10K sizing. |
| 23 | [23-cdc-single-bit.md](23-cdc-single-bit.md) | [C] ~45% / [V] ~15% / [O] ~25% / [I] ~15% | 2FF synchronizer; pulse/toggle synchronizers; MTBF; Quartus metastability analyzer. |
| 24 | [24-cdc-multi-bit.md](24-cdc-multi-bit.md) | [C] ~50% / [V] ~15% / [O] ~20% / [I] ~15% | Async FIFO for bursts; handshake/MCP for occasional words; why bit-by-bit sync is wrong; Gray for counters. |

### Cyclone V resource inference

| # | File | Status mix | Topic |
|---|---|---|---|
| 30 | [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md) | [C] ~35% / [V] ~40% / [O] ~15% / [I] ~10% | M10K vs MLAB; single/dual port; read-during-write modes; init files; ROM templates; flops vs MLAB vs M10K decision. |
| 31 | [31-dsp-inference-cyclone-v.md](31-dsp-inference-cyclone-v.md) | Few firm [C] (registered template, signedness, precision set); several [V] (multiply-add, IP guidance, strength reduction); one load-bearing [I] (era rule) | Variable-precision DSP; multiply / multiply-add patterns; when to model iterative shift-add instead. |
| 32 | [32-arithmetic-patterns-and-operator-cost.md](32-arithmetic-patterns-and-operator-cost.md) | [C] ~30% / [V] ~15% / [O] ~15% / [I] ~40% | What every Verilog operator actually costs on Cyclone V (incl. `/`, `%`, variable shifts, wide muxes/comparators). |

### Quality & closure

| # | File | Status mix | Topic |
|---|---|---|---|
| 40 | [40-timing-closure-and-sdc.md](40-timing-closure-and-sdc.md) | [C]-heavy in §2/§3 (SDC vendor-required); [V] for registered I/O; [O] in §6 for variation patterns; [I] for pipelining-as-remedy and exact QSF assignment names | fmax thinking; pipelining for closure; registered I/O; SDC essentials; false/multicycle paths. |
| 41 | [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md) | ~5×[C], 6×[V], 4×[O], 2×[I] (heavy [C] for report-reading and resource-confirmation; [V] for TB/SVA; one [I] mindset rule) | Fitter/Synthesis reports; TimeQuest setup/hold; testbench style; SVA handshake assertions; reset/edge coverage. |

### Patterns (synthesized)

| # | File | Topic |
|---|---|---|
| 90 | [90-anti-patterns.md](90-anti-patterns.md) | Named anti-patterns: Symptom → Cause → Fix → Citation. Synthesized from each topic's §7. |
| 91 | [91-core-bringup-checklist.md](91-core-bringup-checklist.md) | Sequential checklist gates for bringing a new core from spec to closed timing. |

## Provenance

This bundle was distilled from the corpus at [references/](../references/) per pinned commits/dates in [references/MANIFEST.md](../references/MANIFEST.md). The methodology is [knowledge-bundle-prompt.md](../knowledge-bundle-prompt.md). The design spec is [docs/specs/2026-05-19-cyclone-v-hdl-bundle.md](../docs/specs/2026-05-19-cyclone-v-hdl-bundle.md).
