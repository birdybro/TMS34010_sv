# Skid Buffers and Register Slices

> Bundle version: 2026-05-19
> Pinned commits: wb2axip @ `df8e764`, verilog-axis @ `48ff7a7`, FPGADesignElements @ `2450a54`; zipcpu axi_rules.html (raw capture).
> Load with: [20-ready-valid-handshakes.md](20-ready-valid-handshakes.md), [22-fifos-synchronous-and-asynchronous.md](22-fifos-synchronous-and-asynchronous.md), [15-pipelines-and-latency-thinking.md](15-pipelines-and-latency-thinking.md), [40-timing-closure-and-sdc.md](40-timing-closure-and-sdc.md)
> Status mix: §2 is [C]-heavy (3×[C], 2×[V]); §3 is [C]/[V] for ports and parameters; §6 is [O]-dominated (4×[O], 1×[V]); §7 mixes source-cited entries with one [I] cautionary cross-reference. No bare [C] is claimed for inferential bullets.

## 1. Purpose & one-line summary

A skid buffer (a.k.a. register slice) is a 2-deep storage element placed on a `valid`/`ready` handshake path that registers both the downstream payload outputs and the upstream `ready`, breaking the combinational ready chain without dropping throughput. Insert one **only** when a Quartus TimeQuest report names the ready or output path as the critical path, **or** when the module's external contract requires registered I/O at that boundary. Out of scope: the underlying handshake rules (see [20](20-ready-valid-handshakes.md)); deeper storage with the same backpressure (that is a FIFO — see [22](22-fifos-synchronous-and-asynchronous.md)); parallel pipelines with synchronous `valid` (see [15](15-pipelines-and-latency-thinking.md)); MLAB inference for SRL-style storage (see [30](30-memory-inference-cyclone-v.md)); and the resource-economy framing of "stop inserting these for safety" (primary home is [16](16-resource-and-state-economy.md)).

## 2. The contract (must-obey)

- **[C] A skid buffer preserves the §20 handshake rules independently on each side.** The upstream interface (`i_valid`/`o_ready`/`i_data`) and downstream interface (`o_valid`/`i_ready`/`o_data`) are each independently conformant to the three handshake rules; the wb2axip formal section asserts payload-stability across stalls on both sides (`references/projects/wb2axip/rtl/skidbuffer.v` lines 271–272 for input side; 308–311 for output side @ `df8e764`).
- **[C] Storage capacity is exactly two payload values.** One in the registered output (`o_data`) and one in the "skid" register (`r_data`); the canonical implementation declares precisely these two storage registers (`references/projects/wb2axip/rtl/skidbuffer.v` lines 98 and 129 @ `df8e764`). Anything less drops throughput on the cycle a stall arrives; anything more is a FIFO and belongs in [22](22-fifos-synchronous-and-asynchronous.md).
- **[C] `o_ready` is fed by a register (`r_valid`), not a combinational chain from `i_ready`.** The implementation drives `assign o_ready = !r_valid;` (`references/projects/wb2axip/rtl/skidbuffer.v` line 160 @ `df8e764`), where `r_valid` is a flop updated only on the clock edge (lines 134–141). This is what breaks the ready-path comb chain and is the canonical timing fix; the upstream `ready` no longer combinationally depends on anything downstream of the buffer.
- **[V] FWFT FIFO equivalence.** A FIFO operated in First-Word Fall-Through mode with depth ≤ 2 is functionally equivalent to a skid buffer for the purposes of handshake decoupling; the same two-storage rule applies. Treated as a degenerate case here; structural details (M10K/MLAB FIFO storage) belong in [22](22-fifos-synchronous-and-asynchronous.md). Cross-referenced by FPGADesignElements `Pipeline_Skid_Buffer.v` lines 8–14 @ `2450a54` ("A skid buffer is the smallest Pipeline FIFO Buffer, with only two entries").
- **[V] "Register slice" and "skid buffer" refer to the same pattern.** verilog-axis names the same 2-deep structure a "register" (`axis_register.v` REG_TYPE=2 comment at line 57 @ `48ff7a7`); wb2axip names it a "skid buffer" (`skidbuffer.v` header lines 7–16 @ `df8e764`). "Register slice" emphasizes the timing-closure intent; "skid buffer" emphasizes the flow-control intent.

## 3. Constructs / signals / API reference

Verbatim port list from the canonical module:

```verilog
// references/projects/wb2axip/rtl/skidbuffer.v:81-100 @ df8e764
module skidbuffer #(
		// {{{
		parameter	[0:0]	OPT_LOWPOWER = 0,
		parameter	[0:0]	OPT_OUTREG = 1,
		//
		parameter	[0:0]	OPT_PASSTHROUGH = 0,
		parameter		DW = 8,
		parameter	[0:0]	OPT_INITIAL = 1'b1
		// }}}
	) (
		// {{{
		input	wire			i_clk, i_reset,
		input	wire			i_valid,
		output	wire			o_ready,
		input	wire	[DW-1:0]	i_data,
		output	wire			o_valid,
		input	wire			i_ready,
		output	reg	[DW-1:0]	o_data
		// }}}
	);
```

| Name | Type / Width / Direction | Meaning | Driven by | Drives |
|---|---|---|---|---|
| `i_clk` | wire, 1b, in | Single clock for both interfaces. | parent module | all internal flops |
| `i_reset` | wire, 1b, in | Synchronous reset (per the `always @(posedge i_clk) if (i_reset) ...` style at lines 134–136). [C] | parent module | `r_valid`, `ro_valid`, optionally `r_data`/`o_data` |
| `i_valid` | wire, 1b, in (upstream) | Producer asserts: "I have a payload this cycle." [C] | upstream producer | `r_valid` next-state (line 137), `o_valid` (lines 172, 198) |
| `o_ready` | wire, 1b, out (upstream) | Skid buffer's "ready to accept" toward upstream, **registered through `r_valid`** (line 160). [C] | `r_valid` flop | upstream producer's stall logic |
| `i_data` | wire, DW-bit, in (upstream) | Payload from upstream. Must be stable while `i_valid && !o_ready` (formal property `IDATA_HELD_WHEN_NOT_READY`, lines 281–283). [C] | upstream producer | `r_data` (line 153), `o_data` directly when output empty |
| `o_valid` | wire, 1b, out (downstream) | Skid buffer's "I have a payload" toward downstream. Combinational when `OPT_OUTREG=0` (line 172); registered when `OPT_OUTREG=1` (lines 191–200). [C] | `r_valid`+`i_valid` (comb mode) or `ro_valid` flop (reg mode) | downstream consumer |
| `i_ready` | wire, 1b, in (downstream) | Downstream consumer's "I can accept this cycle." [C] | downstream consumer | `r_valid` clear (line 140), `o_data` update gate (lines 197, 209) |
| `o_data` | reg, DW-bit, out (downstream) | Payload to downstream. Combinational mux when `OPT_OUTREG=0` (lines 177–183); registered when `OPT_OUTREG=1` (lines 206–218). [C] | `r_data` or `i_data` | downstream consumer |
| `DW` | parameter, integer | Payload width in bits. [V] | parent module | port widths |
| `OPT_OUTREG` | parameter, 1b | `0` = combinational outputs (lower latency, but `o_data`/`o_valid` are a wire); `1` = registered outputs (the timing-closure default; recommended for Cyclone V module boundaries). Default `1`. [V] | parent module | generate branch |
| `OPT_LOWPOWER` | parameter, 1b | If set, forces `r_data`/`o_data` to zero when their valid is low (lines 148–151, 207–217). Saves toggling on long high-fanout buses; costs extra logic. Default `0`. [V] | parent module | `r_data`, `o_data` zeroing |
| `OPT_PASSTHROUGH` | parameter, 1b | If set, the module becomes a pure wire (lines 104–124). Intended for formal verification only — do not enable in synthesized RTL. [V] | parent module | generate branch |
| `OPT_INITIAL` | parameter, 1b | If set, allows `initial` blocks to zero `r_valid`/`r_data`/`ro_valid`/`o_data` at power-up; harmless on Cyclone V where flops do initialize from the config bitstream. [V] | parent module | `initial` guards |

Parameter-choice note: for Cyclone V Quartus closure work, `OPT_OUTREG=1` is the default to reach for. It registers both `o_valid` and `o_data` so the downstream side sees zero combinational delay from the buffer's inputs to its outputs, and (combined with the always-registered `o_ready = !r_valid` on line 160) it gives a single-LAB-friendly boundary on **both** sides of the slice.

## 4. Sequencing & timing

ASCII waveform: upstream produces 3 back-to-back transfers; downstream stalls for 2 cycles after the first arrives; `OPT_OUTREG=1`. Cycles are numbered; payload values are `A`, `B`, `C`.

```
cycle:        0    1    2    3    4    5    6    7
              ----------------------------------------
i_valid       0    1    1    1    0    0    0    0
i_data        -    A    B    C    -    -    -    -
o_ready       1    1    1    0    0    0    1    1     <-- registered through r_valid
                            ^^^^^^^^^^^^^^^^
                            upstream sees backpressure here

r_valid       0    0    0    1    1    1    0    0     <-- skid storage occupancy
r_data        -    -    -    -    C    C    C    -     <-- holds C while o_data stalled

o_valid       0    0    1    1    1    1    1    0     <-- registered
o_data        -    -    A    B    B    B    C    -
i_ready       1    1    1    0    0    1    1    1     <-- downstream stall on cycles 3,4
```

Reading: cycle 1, `A` is accepted (upstream `i_valid && o_ready`); cycle 2, `A` appears at output and `B` is accepted; cycle 3, downstream deasserts `i_ready`, but `C` is accepted upstream and parks in `r_data` because `r_valid` goes high; cycle 4, `o_ready` falls (now `!r_valid` = 0), so upstream is told to stop, and upstream's already-deasserted `i_valid` is harmless; cycle 6, downstream resumes (`i_ready`=1), `r_data` drains into `o_data`, `r_valid` clears, `o_ready` rises again. Throughput recovered to 1/cycle. No transfer dropped. (Source: trace of behavior implied by `references/projects/wb2axip/rtl/skidbuffer.v` lines 134–222 @ `df8e764`.)

**Latency penalty.** With `OPT_OUTREG=1`, a value entering on cycle N (`i_valid && o_ready`) appears on `o_data` on cycle N+1 in the unstalled path. Under stall, latency grows by the number of stall cycles, exactly as expected for a 2-deep buffer.

**Depth > 2 with the same backpressure.** That's a FIFO. Do not insert a third or larger skid stage to "increase margin" — either insert a second skid buffer further along the path, or use a sync FIFO. Cross-ref: [22](22-fifos-synchronous-and-asynchronous.md).

## 5. Minimal working pattern

The canonical implementation, copy-pasteable, in two citation-headed chunks. The first is the module declaration (also reproduced in §3); the second is the LOGIC block — `r_valid`/`r_data`/`o_ready` and the registered-output branch.

**Module declaration and ports:**

```verilog
// references/projects/wb2axip/rtl/skidbuffer.v:81-100 @ df8e764
module skidbuffer #(
		// {{{
		parameter	[0:0]	OPT_LOWPOWER = 0,
		parameter	[0:0]	OPT_OUTREG = 1,
		//
		parameter	[0:0]	OPT_PASSTHROUGH = 0,
		parameter		DW = 8,
		parameter	[0:0]	OPT_INITIAL = 1'b1
		// }}}
	) (
		// {{{
		input	wire			i_clk, i_reset,
		input	wire			i_valid,
		output	wire			o_ready,
		input	wire	[DW-1:0]	i_data,
		output	wire			o_valid,
		input	wire			i_ready,
		output	reg	[DW-1:0]	o_data
		// }}}
	);
```

**Skid storage + registered-output branch (excluding the `OPT_PASSTHROUGH` formal-only branch and the combinational `NET_OUTPUT` branch; both are off in the default configuration):**

```verilog
// references/projects/wb2axip/rtl/skidbuffer.v:128-161 @ df8e764
		reg			r_valid;
		reg	[DW-1:0]	r_data;

		// r_valid
		// {{{
		initial if (OPT_INITIAL) r_valid = 0;
		always @(posedge i_clk)
		if (i_reset)
			r_valid <= 0;
		else if ((i_valid && o_ready) && (o_valid && !i_ready))
			// We have incoming data, but the output is stalled
			r_valid <= 1;
		else if (i_ready)
			r_valid <= 0;
		// }}}

		// r_data
		// {{{
		initial if (OPT_INITIAL) r_data = 0;
		always @(posedge i_clk)
		if (OPT_LOWPOWER && i_reset)
			r_data <= 0;
		else if (OPT_LOWPOWER && (!o_valid || i_ready))
			r_data <= 0;
		else if ((!OPT_LOWPOWER || !OPT_OUTREG || i_valid) && o_ready)
			r_data <= i_data;

		assign	w_data = r_data;
		// }}}

		// o_ready
		// {{{
		assign o_ready = !r_valid;
		// }}}
```

```verilog
// references/projects/wb2axip/rtl/skidbuffer.v:186-222 @ df8e764
		end else begin : REG_OUTPUT
			// Register our outputs
			// {{{
			// o_valid
			// {{{
			reg	ro_valid;

			initial if (OPT_INITIAL) ro_valid = 0;
			always @(posedge i_clk)
			if (i_reset)
				ro_valid <= 0;
			else if (!o_valid || i_ready)
				ro_valid <= (i_valid || r_valid);

			assign	o_valid = ro_valid;
			// }}}

			// o_data
			// {{{
			initial if (OPT_INITIAL) o_data = 0;
			always @(posedge i_clk)
			if (OPT_LOWPOWER && i_reset)
				o_data <= 0;
			else if (!o_valid || i_ready)
			begin

				if (r_valid)
					o_data <= r_data;
				else if (!OPT_LOWPOWER || i_valid)
					o_data <= i_data;
				else
					o_data <= 0;
			end
			// }}}

			// }}}
		end
```

**Walk-through:**

- **`r_valid` set (lines 137–139).** `r_valid` goes high exactly when an upstream transfer happens (`i_valid && o_ready`) **and** the output is simultaneously stalled (`o_valid && !i_ready`). That is the one cycle on which a payload "skids" into the buffer because the output cannot accept it.
- **`r_valid` cleared (lines 140–141).** Any cycle the downstream side accepts (`i_ready`), the skid storage drains and `r_valid` returns to 0. There is no other clear condition besides reset; the buffer cannot lose data silently.
- **`o_ready` derivation (line 160).** `assign o_ready = !r_valid;` is the load-bearing line of the whole pattern: `o_ready` is a function of a single flop, with **no** combinational path from `i_ready` (or from anything downstream) to the upstream side. That is the timing-closure win.
- **Registered outputs when `OPT_OUTREG=1` (lines 191–200, 206–218).** `o_valid` becomes `ro_valid`, a flop that loads `(i_valid || r_valid)` on cycles when the output is free (`!o_valid || i_ready`); `o_data` is similarly loaded — preferring `r_data` if the skid buffer holds something, else `i_data`. Combined with line 160, **both** `o_ready` toward upstream and `o_valid`/`o_data` toward downstream are flop-driven; the module presents a registered interface on every output.

## 6. Common variations across implementations

- **[O] wb2axip `skidbuffer.v` (the §5 canonical).** Two-flag formulation: `r_valid` + `r_data` plus `OPT_OUTREG` selecting registered vs combinational outputs. `o_ready = !r_valid` is registered in either output mode. Formally verified (formal block starts at line 244). Cite `references/projects/wb2axip/rtl/skidbuffer.v` lines 128–222 @ `df8e764`.
- **[O] verilog-axis `axis_register.v` REG_TYPE=2.** Three-flag state machine: `store_axis_input_to_output`, `store_axis_input_to_temp`, `store_axis_temp_to_output`. Uses a `temp_*_reg` set as the second storage and the comb signal `s_axis_tready_early = m_axis_tready || (!temp_m_axis_tvalid_reg && (!m_axis_tvalid_reg || !s_axis_tvalid))` to derive next-cycle `tready`. Functionally equivalent to the wb2axip pattern; differs in stylistic factoring (one combinational `always @*` deriving three control flags, then one sequential `always @(posedge clk)` consuming them). Cite `references/projects/verilog-axis/rtl/axis_register.v` lines 91–195 @ `48ff7a7` (comment at line 57 names this REG_TYPE: "2 for skid buffer").
- **[O] verilog-axis `axis_pipeline_register.v` — chained skid buffers.** When a single stage is not enough — e.g., the ready path still crosses too many LABs after one slice — instantiate `LENGTH` skid buffers in series using a `generate for` loop, each an `axis_register` with `REG_TYPE=2`. This is **N** register slices, not a FIFO: each stage independently registers `ready`. Latency grows linearly with `LENGTH`; throughput stays at 1 transfer per cycle. Cite `references/projects/verilog-axis/rtl/axis_pipeline_register.v` lines 91–158 @ `48ff7a7`.
- **[O] verilog-axis `axis_srl_register.v` — SRL-based variant.** Uses a shift-register-LUT (SRL) as the storage primitive, exploiting Xilinx LUT-as-SRL inference. On **Cyclone V** there is no SRL primitive; the closest equivalent is **MLAB** distributed memory (single-port LUT-RAM), which the Quartus inferencer recognises from the appropriate register-array template — see [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md) for the inference rules. **Do not port `axis_srl_register.v` directly to Cyclone V**; for a Cyclone V design use the LAB-flop-backed `skidbuffer.v`/`axis_register.v` pattern or an explicitly MLAB-inferred small FIFO. Cite `references/projects/verilog-axis/rtl/axis_srl_register.v` lines 1–80 @ `48ff7a7`.
- **[V] FWFT FIFO with depth 1 or 2.** Interface-equivalent to a skid buffer for handshake decoupling: a 2-deep First-Word Fall-Through FIFO with the same `valid`/`ready` ports has the same external behaviour as the 2-deep skid buffer above. Storage may be flops or MLAB; that is a [22](22-fifos-synchronous-and-asynchronous.md) decision, not a [21] decision. Cited contextually by `references/projects/FPGADesignElements/Pipeline_Skid_Buffer.v` lines 8–9 @ `2450a54` ("A skid buffer is the smallest Pipeline FIFO Buffer, with only two entries").

## 7. Anti-patterns (mistakes that compile but break)

- **#18 — Ready-path combinational chain longer than one LAB. (Primary ownership of this anti-pattern lives here.)**
  - **Symptom:** Quartus TimeQuest reports the worst-case setup path traversing N modules along the `ready` (or `tready`) signal; reported fmax falls roughly inversely with N as the design scales; the failing path appears in the "Combinational path delay" section with most of its delay attributed to a single chain of `&&` and mux logic culminating at an upstream module's `valid` gating.
  - **Cause:** Every consumer's `ready` is combinationally derived from its downstream consumer's `ready`. With three or more modules chained on the same handshake, the chain runs through every stage and crosses LAB boundaries; routing delay between LABs dominates the path.
  - **Fix:** Insert a canonical skid buffer (per §5) at one or more stage boundaries to convert `o_ready` into a flop output (`o_ready = !r_valid` — wb2axip `skidbuffer.v` line 160). Each slice breaks the ready chain at that point. If one slice does not give enough margin, chain two or more (per the `axis_pipeline_register` pattern in §6) — but only after re-running timing analysis on the first insertion to confirm the path actually moves.
  - **Citation:** ZipCPU AXI Handshaking Rules — `references/raw/zipcpu/axi_rules.html` lines 152–161 (raw capture): "The `xREADY` signal must be registered. Use a skidbuffer if necessary to avoid any throughput impacts." Reinforced by `references/projects/wb2axip/rtl/skidbuffer.v` header lines 9–14 @ `df8e764`: "Skid buffers are required for high throughput AXI code, since the AXI specification requires that all outputs be registered. This means that, if there are any stall conditions calculated, it will take a clock cycle before the stall can be propagated up stream."

- **#17 cross-reference — Skid buffer inserted "for safety" without timing pressure.** Primary home: [16-resource-and-state-economy.md](16-resource-and-state-economy.md). The temptation to over-insert is **strongest at this topic**, which is why it is flagged here before the reader leaves the page. Symptom: the design has skid buffers at every module boundary; latency budget is blown out; area inflated by tens to hundreds of register bits per slice for zero fmax benefit; in cycle-accurate emulation work (see [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md)) the extra cycles silently break the external timing contract. Cause: the agent treats skid buffers as defensive plumbing rather than a targeted timing fix. Fix: insert a skid buffer only after (a) TimeQuest names the ready or output path as the critical path on that boundary, **or** (b) the module's external contract requires registered I/O (e.g., the boundary appears in an SDC `set_output_delay` constraint and TimeQuest hold-analysis demands a flop in the IOE — see [40-timing-closure-and-sdc.md](40-timing-closure-and-sdc.md)). Citation: [I] inferential — no single source frames this as an explicit anti-pattern; the chain is "spec §9 #17 (over-insertion of pipeline registers without timing justification) + the resource-economy framing in [16](16-resource-and-state-economy.md) + the latency cost evident from §4 above". Full treatment in [16](16-resource-and-state-economy.md).

- **Skid buffer placed inside a single combinational stage to "split" it without registering ready.**
  - **Symptom:** The writer pipes `valid` and `data` through a register but leaves the consumer-side `ready` driving the producer-side `ready` directly through a wire (or worse, through a comb mux). Simulation shows one extra cycle of latency, but the ready path's critical-path delay is identical to before; in Quartus the path now starts at a flop on the producer side and ends back at the same upstream register, through the same chain.
  - **Cause:** Misunderstanding that a skid buffer must register **both** directions — payload outputs **and** the upstream `ready`. Registering only the forward path adds latency without adding any timing benefit.
  - **Fix:** Use the canonical module from §5; do not hand-roll the pattern. If the codebase has reasons to write it inline, copy the three load-bearing lines from `skidbuffer.v`: the `r_valid` flop (lines 134–141), the `r_data` flop (lines 147–153), and `assign o_ready = !r_valid;` (line 160). Verify by re-running TimeQuest after the change; the ready-path critical chain should now start at `r_valid` and not propagate further upstream.
  - **Citation:** `references/projects/wb2axip/rtl/skidbuffer.v` header lines 9–14 (motivation) and line 160 (the registered-`ready` derivation) @ `df8e764`.

- **Storage capacity > 2 inserted at a boundary "as a skid buffer."**
  - **Symptom:** A 4-, 8-, or 16-deep FIFO is dropped in at a module boundary because "the ready path was failing timing"; later, when the path still fails timing somewhere else, the writer adds **another** FIFO downstream, doubling area and latency, without confirming where the comb chain actually breaks.
  - **Cause:** Conflation of skid buffer with FIFO. Depth-2 with `o_ready = !r_valid` (the §5 pattern) is the smallest correct timing fix; depth > 2 with the **same** backpressure semantics is a FIFO and exists for rate decoupling, not for breaking comb chains.
  - **Fix:** Use the 2-deep skid buffer in §5 first. Confirm in TimeQuest that the ready-path chain moves (a re-run should show the new critical path starting at `r_valid` of the inserted slice, not further upstream). Only escalate to a deeper FIFO if the application **also** needs rate decoupling (occasional bursts being absorbed into average-rate consumption), and at that point the design decision belongs in [22-fifos-synchronous-and-asynchronous.md](22-fifos-synchronous-and-asynchronous.md), not here.
  - **Citation:** [I] — synthesised from the explicit two-storage architecture of `references/projects/wb2axip/rtl/skidbuffer.v` lines 98 and 129 @ `df8e764`, combined with the FWFT-equivalence statement in `references/projects/FPGADesignElements/Pipeline_Skid_Buffer.v` lines 8–9 @ `2450a54`. No single source explicitly names "FIFO mistaken for skid buffer" as an anti-pattern.

## 8. Verification

**SVA properties (paraphrased from the wb2axip formal section).** Each rule below has a property in the formal section of the canonical source; quoting the closest concrete property for each.

- **Upstream payload-stability under stall.** When `i_valid && !o_ready`, `i_valid` must remain asserted and `i_data` must not change. Cite `references/projects/wb2axip/rtl/skidbuffer.v` lines 281–283 @ `df8e764` — the `IDATA_HELD_WHEN_NOT_READY` property: ``i_valid && !o_ready |=> i_valid && $stable(i_data)``.
- **Downstream payload-stability under stall.** Symmetric on the output side: when `o_valid && !i_ready`, `o_valid` must remain asserted and `o_data` must not change. Cite the assert at lines 308–311 @ `df8e764`: "Following any stall, valid must remain high and data must be preserved" (`assert(o_valid && $stable(o_data))`).
- **No payload loss across the slice.** Each transfer accepted on the upstream side (`i_valid && o_ready`) must appear exactly once on the downstream side, either passing directly through (when the output is empty) or via `r_data` (when the output was stalled). The "Rule #2: All incoming data must either go directly to the output port, or into the skid buffer" property at lines 333–348 @ `df8e764` formalises this: ``(i_valid && o_ready && (!OPT_OUTREG || o_valid) && !i_ready) |=> (!o_ready && w_data == $past(i_data))``.

For richer SVA mechanics (assert vs assume vs cover, immediate vs concurrent), see [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md).

**Quartus indicator that a skid buffer is needed.** In a TimeQuest setup-analysis report, the critical path's Data Arrival chain traverses two or more modules' `ready` (or `tready`) wires before terminating at a downstream register. The fix is a skid buffer at one of those module boundaries; the chain should then split, with the new critical path starting at the new `r_valid` flop. For the mechanics of reading TimeQuest reports and the SDC constraints involved, see [40-timing-closure-and-sdc.md](40-timing-closure-and-sdc.md).

**Sanity checks after inserting a skid buffer.**

- Synthesis report: extra flops appear at the boundary (roughly `2 × DW + 2` per slice — two payload registers plus `r_valid` and `ro_valid` when `OPT_OUTREG=1`). If the count is wrong, the parametrisation is wrong.
- Timing report: re-run TimeQuest; the previous critical path's worst-slack number should improve, and the new worst slack should belong to a **different** path. If the same path is still critical, the slice is in the wrong place.
- Simulation: drive the back-to-back-with-stall pattern from §4 and confirm no upstream `i_valid && o_ready` transfer is dropped and the output sequence matches the input.

## 9. Provenance footer

- `references/projects/wb2axip/rtl/skidbuffer.v @ df8e764` — used for §2 (storage capacity, registered `o_ready`, formal properties), §3 (port list verbatim, parameter table), §4 (waveform behaviour trace), §5 (canonical excerpt, both citation blocks), §6 (wb2axip style variation), §7 (anti-pattern #18 motivation and hand-rolled-pattern fix), §8 (SVA properties).
- `references/projects/verilog-axis/rtl/axis_register.v @ 48ff7a7` — used for §2 (register-slice/skid-buffer synonymy), §6 (REG_TYPE=2 three-flag style variation, line 57 comment).
- `references/projects/verilog-axis/rtl/axis_pipeline_register.v @ 48ff7a7` — used for §6 (chained-skid-buffer variation), §7 (escalation path for #18).
- `references/projects/verilog-axis/rtl/axis_srl_register.v @ 48ff7a7` — used for §6 (SRL-based variation note, Cyclone V MLAB cross-ref to [30](30-memory-inference-cyclone-v.md)).
- `references/projects/FPGADesignElements/Pipeline_Skid_Buffer.v @ 2450a54` — used for §2 (FWFT-FIFO equivalence), §6 (FWFT equivalence framing), §7 (storage-capacity inference).
- `references/raw/zipcpu/axi_rules.html` (raw capture; see [references/MANIFEST.md](../references/MANIFEST.md)) — used for §7 (anti-pattern #18 primary citation: "The `xREADY` signal must be registered. Use a skidbuffer if necessary to avoid any throughput impacts."), §1 (motivation context).
- `references/MANIFEST.md` (archive index) — used to pin commit hashes `df8e764` (wb2axip, manifest line 133), `48ff7a7` (verilog-axis, manifest line 131), `2450a54` (FPGADesignElements, manifest line 130).
