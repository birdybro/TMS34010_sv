# Ready/Valid Handshakes

> Bundle version: 2026-05-19
> Pinned commits: see [references/MANIFEST.md](../references/MANIFEST.md) — FPGACPU `handshake.html` (raw HTML capture, 2026-05-20), ZipCPU `axi_rules.html` (raw HTML capture, 2026-05-20), FPGADesignElements commit `2450a54`, verilog-axis commit `48ff7a7`, wb2axip commit `df8e764`.
> Load with: [21-skid-buffers-and-register-slices.md](21-skid-buffers-and-register-slices.md), [22-fifos-synchronous-and-asynchronous.md](22-fifos-synchronous-and-asynchronous.md), [15-pipelines-and-latency-thinking.md](15-pipelines-and-latency-thinking.md), [10-hardware-mindset-and-microarchitecture.md](10-hardware-mindset-and-microarchitecture.md), [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md)
> Status mix: [C] dominates §2 — three load-bearing protocol rules plus composability and the directional combinational restriction. [V] for naming conventions and the legal `ready`-on-`valid` combinational asymmetry. [O] in §6 (per-implementation naming). [I] only where the protocol's intent is established by multiple sources reinforcing each other.

## 1. Purpose & one-line summary

This doc establishes the **ready/valid handshake** as the canonical inter-module flow-control contract used everywhere else in the bundle (target part: Cyclone V `5CSEBA6U23I7`, DE10-Nano): every inter-module boundary in user RTL exposes a `valid` (producer-driven), a `ready` (consumer-driven), and a payload bus, conformant to the three rules in §2. The three rules are non-negotiable; violating any one of them produces silent data corruption that simulators may miss for a long time and that Quartus will not report. This doc does not cover skid buffers ([21](21-skid-buffers-and-register-slices.md)), FIFOs ([22](22-fifos-synchronous-and-asynchronous.md)), pipelining mechanics ([15](15-pipelines-and-latency-thinking.md)), or the SVA mechanics of formal handshake assertions beyond a small inline example ([41](41-quartus-reports-and-verification.md)).

## 2. The contract (must-obey)

The three rules in this section are the spine of the doc. Each carries an explicit [C] label and a direct citation; downstream docs cite back to this section rather than re-deriving these rules.

- **[C] No valid-drop.** Once the producer asserts `valid`, it must hold `valid` continuously until the cycle in which both `valid` and `ready` are high together — the *handshake cycle*. After the handshake, `valid` may deassert on the next cycle if no new data is presented. Establishing source: FPGACPU `references/raw/fpgacpu/handshake.html` lines 159–163 — "when the source interface asserts valid *it must remain asserted until the handshake completes*, else we could end up in a situation where the source interface temporarily asserts valid and the destination interface temporarily asserts ready, but they never coincide to complete the handshake." Reinforced by ZipCPU `references/raw/zipcpu/axi_rules.html` rule 4 (lines 146–151): "Nothing can change unless `!xVALID || xREADY`."

- **[C] Payload-stable while `valid && !ready`.** While `valid` is asserted and `ready` is not, every bit of the payload bus accompanying that `valid` must remain stable, cycle-for-cycle, until the handshake completes. Establishing source: FPGACPU `references/raw/fpgacpu/handshake.html` lines 130–134 — "the source interface holds data steady alongside valid, changing data only after the handshake completes. Any data value outside of the clock cycle when the handshake completes is lost." Reinforced by ZipCPU `references/raw/zipcpu/axi_rules.html` lines 461–468: "if the stream stalled on the last cycle, then all of the values must remain the same on this cycle. That means that `M_AXIS_TVALID` must remain true, and everything else must remain stable" (formal property `assert(M_AXIS_TVALID); assert($stable(M_AXIS_TDATA));`).

- **[C] Transfer fires exactly on `valid && ready`.** A datum is consumed by the receiver, and may be advanced internally by the sender, only on cycles where both `valid` and `ready` are asserted; on every other cycle the protocol state must not advance. Establishing source: FPGACPU `references/raw/fpgacpu/handshake.html` lines 86–89 — "When both valid and ready are high, the handshake is complete, the destination interface accepts the data in the same cycle, and the ready and valid outputs change state if necessary." Reinforced (in two parts) by ZipCPU `references/raw/zipcpu/axi_rules.html` rules 2–3 (lines 131–145): "Nothing happens unless `xVALID && xREADY`" and "Something *always* happens anytime `xVALID && xREADY` — *Be careful not to add any other conditions to this check lest you miss a handshake!*" The internal-state restatement of the same rule is FPGACPU lines 179–198: "Any internal state of a module which affects a source or destination interface must only ever change in the same cycle as a *completed* handshake."

The following rules are also [C], but derived from the above three rather than independent contracts:

- **[C] Composability.** Any handshake-conformant producer connects directly to any handshake-conformant consumer with no protocol adapter; only width/payload conversion ever needs intervening logic. Source: FPGACPU `references/raw/fpgacpu/handshake.html` lines 16–22 and lines 56–57 — "A connection always goes from the source interface to the destination interface. Other pairings cannot work." This is the property that makes the §2 rules worth enforcing strictly; it disappears the moment one party violates any of the three.

- **[C] `valid` must NOT depend combinationally on `ready`.** The producer's decision to assert `valid` cannot be a combinational function of the consumer's `ready` on the same cycle. Allowing this either creates a combinational loop (when `ready` already inspects `valid`, which is the common case) or forces the producer to retract `valid` when `ready` falls mid-cycle, violating the no-valid-drop rule. The required mitigation when the producer's natural decision would depend on `ready` is a skid buffer (see [21](21-skid-buffers-and-register-slices.md)). Source: ZipCPU `references/raw/zipcpu/axi_rules.html` rule 5 (lines 152–162): "The `xREADY` signal must be registered. Use a skidbuffer if necessary to avoid any throughput impacts… The specification simply requires that, 'On master and slave interfaces, there must be no combinatorial paths between input and output signals.'" FPGACPU `handshake.html` lines 59–72 ("Loops") states the symmetric form of this prohibition.

- **[V] `ready` may depend combinationally on `valid`.** The consumer's `ready` is *allowed* to inspect the producer's `valid` combinationally on the same cycle (e.g., a stage that grants `ready` only when downstream is empty AND something is being offered). This is the common-case asymmetry that the §2 contract permits; the converse direction (above) is prohibited. Source: FPGACPU `references/raw/fpgacpu/handshake.html` lines 74–82 (ADDENDUM): "in practice allowing a combinational path between valid and ready within an interface can be a good tradeoff. Buffering every single source/destination connection can bloat a design and will not improve performance except at the highest speeds. Some pipeline control is most easily implemented combinationally between interfaces, without buffering." Cross-reinforced by ZipCPU `axi_rules.html` lines 152–162, which prescribes registered `READY` only as the rule-of-thumb-when-throughput-matters consequence of the underlying spec, not as an absolute requirement on every internal interface.

- **[V] Direction-of-drive: `valid` and payload are producer outputs; `ready` is the consumer's output.** No back-channel exists from consumer to producer beyond `ready`. This convention is established jointly by the FPGACPU and ZipCPU sources and matches verilog-axis port lists. Source: FPGACPU `references/raw/fpgacpu/handshake.html` lines 51–54 — "The *source* interface outputs valid and data, and takes ready as input. The *destination* interface outputs ready, and receives valid and data."

- **[V] Reset clears `valid`.** After reset, the producer's `valid` must be observed low; the consumer's `ready` may be either state but is conventionally driven from a registered FSM that itself comes out of reset in a known state. Source: ZipCPU `references/raw/zipcpu/axi_rules.html` rule 1 (lines 128–130) — "`xVALID` must be cleared following any reset" — reinforced by FPGACPU `handshake.html` lines 167–175 ("Any latch holding state inside the source or destination interface must be reset, else the interface may remain in the wrong state after reset").

## 3. Constructs / signals / API reference

The handshake's signal set is small. The two verbatim port excerpts below establish the two dominant naming conventions used by sources cited throughout this bundle.

The verilog-axis convention (AXI-Stream prefixes `s_axis_*` for the slave/sink and `m_axis_*` for the master/source):

```
// references/projects/verilog-axis/rtl/axis_register.v:60-87 @ 48ff7a7
(
    input  wire                   clk,
    input  wire                   rst,

    /*
     * AXI Stream input
     */
    input  wire [DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire [KEEP_WIDTH-1:0]  s_axis_tkeep,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,
    input  wire                   s_axis_tlast,
    input  wire [ID_WIDTH-1:0]    s_axis_tid,
    input  wire [DEST_WIDTH-1:0]  s_axis_tdest,
    input  wire [USER_WIDTH-1:0]  s_axis_tuser,

    /*
     * AXI Stream output
     */
    output wire [DATA_WIDTH-1:0]  m_axis_tdata,
    output wire [KEEP_WIDTH-1:0]  m_axis_tkeep,
    output wire                   m_axis_tvalid,
    input  wire                   m_axis_tready,
    output wire                   m_axis_tlast,
    output wire [ID_WIDTH-1:0]    m_axis_tid,
    output wire [DEST_WIDTH-1:0]  m_axis_tdest,
    output wire [USER_WIDTH-1:0]  m_axis_tuser
);
```

The FPGADesignElements convention (`input_*` / `output_*` prefixes, no AXI sideband):

```
// references/projects/FPGADesignElements/Pipeline_Skid_Buffer.v:113-124 @ 2450a54
(
    input   wire                        clock,
    input   wire                        clear,

    input   wire                        input_valid,
    output  wire                        input_ready,
    input   wire    [WORD_WIDTH-1:0]    input_data,

    output  wire                        output_valid,
    input   wire                        output_ready,
    output  wire    [WORD_WIDTH-1:0]    output_data
);
```

The wb2axip convention (`i_*` / `o_*` prefixes per wire direction relative to *this module*):

```
// references/projects/wb2axip/rtl/skidbuffer.v:90-100 @ df8e764
    ) (
        // {{{
        input   wire            i_clk, i_reset,
        input   wire            i_valid,
        output  wire            o_ready,
        input   wire    [DW-1:0]    i_data,
        output  wire            o_valid,
        input   wire            i_ready,
        output  reg [DW-1:0]    o_data
        // }}}
    );
```

The full signal/role table:

| Name (generic) | Direction (at producer / source) | Width | Meaning | Driven by | Drives | Label |
|---|---|---|---|---|---|---|
| `valid` | output | 1 | "I have a payload word to transfer this cycle." | producer | consumer's protocol logic | [C] |
| `ready` | input | 1 | "I can accept a payload word this cycle." | consumer | producer's protocol logic | [C] |
| payload (`tdata` / `data` / `i_data` / `o_data`) | output | arbitrary | the datum to transfer; bit-for-bit stable while `valid && !ready` per §2 | producer | consumer payload register | [C] |
| `last` / `tlast` | output | 1 | optional sideband: end-of-packet marker; obeys §2 stability rules | producer | consumer | [V] (AXI-Stream) |
| `keep` / `tkeep` | output | bytes-per-word | optional sideband: per-byte valid mask; obeys §2 stability rules | producer | consumer | [V] (AXI-Stream) |
| `id` / `dest` / `user` | output | variable | optional sideband; obeys §2 stability rules | producer | consumer | [V] (AXI-Stream) |
| reset | input | 1 | clears `valid` per §2 reset-clear rule | top-level reset network | producer FSM | [C] |
| clock | input | 1 | all handshake signals synchronous to rising edge | clock network | all FFs | [C] |

[C] The direction-of-drive rule is non-negotiable: there is no back-channel from consumer to producer other than `ready`. Sideband signals (`last`, `keep`, `id`, `dest`, `user`) are *payload* — they ride with `valid` and obey the same stability rule from §2. Sideband signals are OPTIONAL in the bundle's generic ready/valid; they are convention only when an AXI-Stream-style interface is requested. Source for this table: FPGACPU `handshake.html` lines 43–57, ZipCPU `axi_rules.html` lines 104–115 (treatment of "everything else" as `TDATA` for protocol purposes), and the three port excerpts above.

## 4. Sequencing & timing

The four canonical cases. Time advances left-to-right; `V` is `valid`, `R` is `ready`, `D` is the payload bus value, `H` marks the handshake cycle. All edges are at the same rising clock.

**Case 1 — instant transfer (`ready` already high when `valid` asserts):**

```
cycle:    0   1   2   3   4
V    : __/===\______________
R    : ====================  (held high by consumer)
D    : ----X===X-----------    X = D0 valid during cycle 1
H    :       ^                handshake on cycle 1
```

`valid` and `ready` are both high on cycle 1; transfer completes that cycle. `valid` falls on cycle 2 because the producer has nothing more to send.

**Case 2 — stall, then transfer (`ready` low for N cycles):**

```
cycle:    0   1   2   3   4   5
V    : __/===================\
R    : __________________/===\
D    : ----X===D0=========X--   D0 STABLE for cycles 1..4
H    :                   ^      handshake on cycle 4
```

Producer asserts `valid` on cycle 1 with payload `D0`. Consumer holds `ready` low through cycle 3. Producer **must hold** `valid` AND `D0` stable bit-for-bit on cycles 1, 2, 3, and 4. On cycle 4 the consumer asserts `ready`; handshake completes; `valid` may deassert on cycle 5. *(§2 rules 1 and 2 both apply here; this is the canonical "stall" pattern.)*

**Case 3 — back-to-back transfers (both held high for N cycles):**

```
cycle:    0   1   2   3   4
V    : __/=================\
R    : __/=================\
D    : ----D0==D1==D2==D3---
H    :     ^   ^   ^   ^      one handshake per cycle
```

`valid` and `ready` both held high for four cycles; one transfer completes each cycle. The payload advances to a new datum each cycle. This is the throughput-1 case; downstream docs (15, 21) describe how to *achieve* this with a registered consumer.

**Case 4 — bubble cycle (`valid` low for one cycle between two valid cycles):**

```
cycle:    0   1   2   3   4
V    : __/===\_______/===\__
R    : ====================
D    : ----D0------D1-------
H    :     ^           ^
```

`valid` deasserts on cycle 2 because the producer has no datum to present that cycle, then reasserts on cycle 4 with a new datum. **This is legal**: §2 rule 1 prohibits dropping `valid` *before the transfer completes*; it does not prohibit dropping `valid` after a handshake when no new datum is ready. The bubble cycle (cycle 2) carries no transfer.

**Illegal — valid-drop before transfer:**

```
cycle:    0   1   2   3   4
V    : __/===\______________
R    : ____________/===\____   << ready arrives, but valid has dropped
D    : ----D0--------------
H    :       (none — protocol violation in cycle 1->2)
```

Producer asserted `valid` with `D0` on cycle 1, but no handshake occurred (consumer's `ready` was low). On cycle 2 the producer dropped `valid`. This is a **§2 rule-1 violation**: from the consumer's point of view the offered datum either was or wasn't. See AP-20.1 in §7.

**Timing note.** The timing-friendly default on Cyclone V is a *registered-output* producer driving a *combinational-`ready`* consumer (i.e., the consumer's `ready` is computed combinationally from internal occupancy and asserts whenever the consumer can accept). When the consumer's `ready` must itself be registered to close timing, the canonical insertion is a skid buffer between the two — see [21-skid-buffers-and-register-slices.md](21-skid-buffers-and-register-slices.md). This doc does not derive that mechanism; it only flags the trigger.

## 5. Minimal working pattern

The smallest correct producer logic-form. Verbatim from ZipCPU, which establishes the canonical "valid-only-changes-when-`!valid || ready`" gating:

```
// references/raw/zipcpu/axi_rules.html:323-338 @ 2026-05-20 capture
always @(posedge ACLK)
if (!ARESETN)
    M_AXIS_TVALID <= 0;
else if (!M_AXIS_TVALID || M_AXIS_TREADY)
    M_AXIS_TVALID <= next_valid_signal;

always @(posedge ACLK)
if (OPT_LOWPOWER && !ARESETN)
    M_AXIS_TDATA <= 0;
else if (!M_AXIS_TVALID || M_AXIS_TREADY)
begin
    M_AXIS_TDATA <= next_data;

    if (OPT_LOWPOWER && !next_valid)
        M_AXIS_TDATA <= 0;
end
```

[I] composite. This producer template satisfies §2:
- Rule 1 (no valid-drop): `M_AXIS_TVALID` only changes on cycles where `!M_AXIS_TVALID || M_AXIS_TREADY` is true. The only way to *clear* a previously asserted `valid` is on a cycle where the handshake has completed (`M_AXIS_TVALID && M_AXIS_TREADY` was true on the prior cycle, which collapses `!M_AXIS_TVALID || M_AXIS_TREADY` to `true` and lets the next `next_valid_signal` (possibly 0) be loaded).
- Rule 2 (payload-stable): `M_AXIS_TDATA` only changes on the same `!M_AXIS_TVALID || M_AXIS_TREADY` gate. So while `valid && !ready`, neither `valid` nor the payload register can change.
- Rule 3 (transfer on `valid && ready`): satisfied automatically — the consumer below performs work only on the cycle when both are high.

The smallest correct consumer logic-form, in the same source:

```
// references/raw/zipcpu/axi_rules.html:188-193 @ 2026-05-20 capture
always @(posedge ACLK)
    // Logic to determine S_AXIS_TREADY

always @(posedge ACLK)
if (S_AXIS_TVALID && S_AXIS_TREADY) // plus nothing!
    // Do something
```

[I] composite. The "plus nothing!" comment is structural: §2 rule 3 requires the consumer to do its work **exactly** on `valid && ready`, not on any further-conditioned subset. Adding `&& other_condition` to that gate is anti-pattern AP-20.2's most common form (see §7).

Both excerpts are reproduced from ZipCPU's "Example Master logic" and "Example Slave logic" forms; the FPGACPU `Pipeline_Skid_Buffer.v` referenced in [21](21-skid-buffers-and-register-slices.md) is the full skid-buffer composition that wraps a producer of this form into one whose `ready` can also be registered. See 21 for the full module.

## 6. Common variations across implementations

The bundle does not mandate any one naming style. It mandates the rules in §2. The three styles below are the ones the consuming agent will encounter most often in this corpus.

- **[O] verilog-axis / AXI-Stream style.** `s_axis_tvalid` / `s_axis_tready` / `s_axis_tdata` for the input (slave) side and `m_axis_*` for the output (master) side, with optional AXI sideband (`tkeep`, `tlast`, `tid`, `tdest`, `tuser`). The `s_` / `m_` prefix names the *role* (slave/sink vs master/source) rather than the wire's direction. *Source:* `references/projects/verilog-axis/rtl/axis_register.v` lines 67–87 (port block excerpted in §3).

- **[O] FPGADesignElements / FPGACPU style.** `input_valid` / `input_ready` / `input_data` and `output_valid` / `output_ready` / `output_data`, no AXI sideband; ports are named by their *side of the module* rather than their wire direction. The prefix tells you which handshake interface the signal belongs to; the direction is then unambiguous from the role (the source interface drives `*_valid` and the destination drives `*_ready`). *Source:* `references/projects/FPGADesignElements/Pipeline_Skid_Buffer.v` lines 113–124 (port block excerpted in §3).

- **[O] wb2axip / ZipCPU style.** `i_valid` / `o_ready` / `i_data` on the upstream port and `o_valid` / `i_ready` / `o_data` on the downstream port; the `i_` / `o_` prefix names the *wire's direction relative to this module*, not the role. So a slave's input-side `i_valid` and a master's output-side `o_valid` look different at the source level even though they play the same protocol role. *Source:* `references/projects/wb2axip/rtl/skidbuffer.v` lines 92–99 (port block excerpted in §3).

- **[V] Choice of style is a project-level decision, not a correctness one.** Picking one style and using it consistently within a project matters; mixing styles in adjacent modules is what causes drive-direction confusion (see anti-pattern in §7). *Source:* inferred from the three style choices above plus the requirement of §2 — none of the three styles enables or prohibits any §2 rule.

## 7. Anti-patterns (mistakes that compile but break)

This section owns three handshake-rule violations that are **NOT** in the spec §9 numbered list. They are flagged here as **"spec §9 addendum"** for the Phase 3 integrator (`90-anti-patterns.md`) to pick up beyond the numbered floor of 39 candidates. They are numbered AP-20.1 / AP-20.2 / AP-20.3 for cross-reference.

---

**AP-20.1 — Valid drops before transfer.** *(spec §9 addendum — not in numbered list)*

- **Symptom:** Simulator-only "transfer" that never reaches the consumer. Downstream FIFO or pipeline reports missing words. Formal property `valid && !ready |=> valid` fires. In random-stall testbenches, the bug surfaces only when the consumer happens to stall on the same cycle the producer's `valid` source briefly drops.
- **Cause:** The producer's `valid` is a combinational function of producer-internal state that changes independently of whether a handshake has completed. Common form: counting down packet words and combinationally tying `valid = (count != 0)`, then advancing `count` on every cycle rather than only on `valid && ready`. FPGACPU `handshake.html` lines 179–198 names exactly this case: "if you are counting down words in a packet passing through a source interface, and you change state as soon as the counter reaches zero, you will lose the last packet word if, by coincidence, the ready signal of the destination interface goes low at the same time as the counter reaches zero."
- **Fix:** Gate every state transition that affects the handshake interface on a `handshake_complete = valid && ready` term. Equivalently, follow the producer template in §5: `valid` and the payload register change only when `!valid || ready`. The relevant FPGACPU code recipe is reproduced verbatim:
  ```
  // references/raw/fpgacpu/handshake.html:194-198 @ 2026-05-20 capture
  always @(*) begin
      handshake_complete = (ready == 1'b1) && (valid == 1'b1);
  end
  ```
- **Citation:** FPGACPU `references/raw/fpgacpu/handshake.html` lines 159–198 (the "Avoiding Deadlocks and Livelocks" + "Internal State" sections together) and ZipCPU `references/raw/zipcpu/axi_rules.html` rule 4 (lines 146–151).

---

**AP-20.2 — Payload changes while `valid && !ready`.** *(spec §9 addendum — not in numbered list)*

- **Symptom:** Corrupted datum captured on a delayed transfer. Consumer's payload register holds a value that was never bit-for-bit coherent with the `valid` it acknowledged. In simulation, the bug looks like "off-by-one" data shifts that only appear when the consumer stalls. In a Quartus build it is silent — there is no synthesis warning for it. Formal property `valid && !ready |=> $stable(payload)` fires.
- **Cause:** The producer treats `valid` as a one-cycle pulse and advances its internal payload-source state on every clock, regardless of whether the consumer has accepted yet. Equivalently: the payload register's enable is independent of the handshake completion. This is the *symmetric* failure to AP-20.1 — AP-20.1 lets `valid` change too soon, AP-20.2 lets the data change too soon. The Xilinx broken TLAST example in ZipCPU `axi_rules.html` lines 351–368 is exactly this form: `axis_tlast_delay` is updated on every cycle, so when the channel stalls on the penultimate beat `TLAST` toggles "in violation of the protocol."
- **Fix:** Hold the payload register on the same gate as `valid` — exactly as in the §5 producer template. Either follow that template, or insert a skid buffer on the producer's output so a downstream stall can be absorbed without back-pressuring the producer's internal state machine. The skid buffer is the right fix when the producer cannot be retrofitted; see [21-skid-buffers-and-register-slices.md](21-skid-buffers-and-register-slices.md).
- **Citation:** FPGACPU `references/raw/fpgacpu/handshake.html` lines 130–134 ("Sampling Changing Data"); ZipCPU `references/raw/zipcpu/axi_rules.html` lines 461–486 (formal property: "if the stream stalled on the last cycle, then all of the values must remain the same on this cycle"). Also formalized in wb2axip `references/projects/wb2axip/rtl/skidbuffer.v` lines 281–284:
  ```
  // references/projects/wb2axip/rtl/skidbuffer.v:281-284 @ df8e764
  property IDATA_HELD_WHEN_NOT_READY;
      @(posedge i_clk) disable iff (i_reset)
      i_valid && !o_ready |=> i_valid && $stable(i_data);
  endproperty
  ```

---

**AP-20.3 — `valid` depending combinationally on `ready` without a skid buffer.** *(spec §9 addendum — not in numbered list)*

- **Symptom:** Either Quartus reports a combinational loop in the Analysis & Synthesis stage (the most obvious case, when the consumer's `ready` already depends combinationally on the producer's `valid`), or — if the loop is unwittingly broken by an inferred latch or by an asymmetric tool transform — the no-valid-drop rule fires intermittently. The latter is the harder bug: `valid` retracts in cycles where the consumer's `ready` momentarily lowers, and the formal `valid && !ready |=> valid` property catches it but only under specific stall patterns.
- **Cause:** Producer tries to assert `valid` only when the downstream can accept it (`assign valid = have_data && ready;`). This is the natural, intuitive expression of "I will offer a word only if you'll take it" — and it is wrong. It places the producer's `valid` decision combinationally downstream of `ready`, violating the [C] directional rule in §2.
- **Fix:** Insert a skid buffer between the producer's internal logic and the external `valid` / payload outputs; the skid buffer registers the upstream `ready` decision and presents a §2-conformant interface to both sides. This is the *canonical reason* skid buffers exist on FPGAs and the canonical pattern for breaking the dependency. See [21-skid-buffers-and-register-slices.md](21-skid-buffers-and-register-slices.md) §2 and §5 for the construction.
- **Citation:** ZipCPU `references/raw/zipcpu/axi_rules.html` rule 5 (lines 152–162): "The `xREADY` signal must be registered. Use a skidbuffer if necessary to avoid any throughput impacts… 'On master and slave interfaces, there must be no combinatorial paths between input and output signals.'" Reinforced by FPGACPU `references/raw/fpgacpu/handshake.html` lines 59–72 ("Loops"): "There must be no combinational paths from input to output signals in the source interface (ready to valid), nor in the destination interface (valid to ready). Otherwise combinational loops will form when connecting interfaces."

---

**AP-20.4 — `ready` driven by the producer, or `valid` driven by the consumer.** *(spec §9 addendum — not in numbered list; minor)*

- **Symptom:** Quartus reports multiple drivers on the handshake wire, OR the design "works" in one direction but the back-pressure path produces nonsense values that the consumer interprets as data.
- **Cause:** Style confusion — typically caused by mixing two of the three naming conventions in §6 within one project without recompiling the mental model of which prefix encodes role vs. direction. The `i_` / `o_` style names directions; the `s_` / `m_` style names roles; substituting one for the other at a module boundary inverts the wire's drive.
- **Fix:** Pick ONE of the three naming styles in §6 per project and apply it uniformly. The direction-of-drive rule from §2 is independent of style: `valid` and payload always go *from* source *to* destination; `ready` always goes *back*.
- **Citation:** [I] — no single source establishes this as an anti-pattern by name. Inferred from FPGACPU `handshake.html` lines 51–57 (interface direction rule) and the style differences in the three port excerpts in §3.

---

**Cross-reference to spec §9 #38 — FIFO without producer-side backpressure.** A FIFO whose `full` signal does not feed the producer's `ready` will silently overflow under any condition where the producer's rate exceeds the FIFO's drain rate. This is the bundle's anti-pattern #38; its **primary home is [22-fifos-synchronous-and-asynchronous.md](22-fifos-synchronous-and-asynchronous.md)**. This doc only surfaces the connection: from the §2 contract, the FIFO's `full` and the producer's `ready` *are* the back-pressure channel; ignoring the connection is a §2 rule-3 violation by another name, because data on cycles where `valid && !ready` would silently be dropped if the producer ignores `ready`. See 22 for the construction; do not re-derive here.

## 8. Verification

The minimal SVA assertion set every handshake-conformant module should be paired with in simulation. Both properties below are direct restatements of §2 rules 1 and 2.

```
// Inline composite, restating §2 rules 1 and 2 as SVA.
// Citations to wb2axip/skidbuffer.v formal block (see below) and ZipCPU SVA.

// Rule 1 — no valid-drop:
assert property (@(posedge clk) disable iff (rst)
    valid && !ready |=> valid);

// Rule 2 — payload stable while waiting:
assert property (@(posedge clk) disable iff (rst)
    valid && !ready |=> valid && $stable(payload));
```

The wb2axip skid buffer's formal section captures the same two properties as a named property and uses it as either `assume` (when checking a consumer) or `assert` (when checking a producer) — a useful pattern when reusing the property across module roles:

```
// references/projects/wb2axip/rtl/skidbuffer.v:267-291 @ df8e764
always @(posedge i_clk)
if (!f_past_valid)
begin
    `ASSUME(!i_valid || !OPT_INITIAL);
end else if ($past(i_valid && !o_ready && !i_reset) && !i_reset)
    `ASSUME(i_valid && $stable(i_data));

`ifdef VERIFIC
`define FORMAL_VERIFIC
    // Reset properties
    property RESET_CLEARS_IVALID;
        @(posedge i_clk) i_reset |=> !i_valid;
    endproperty

    property IDATA_HELD_WHEN_NOT_READY;
        @(posedge i_clk) disable iff (i_reset)
        i_valid && !o_ready |=> i_valid && $stable(i_data);
    endproperty

`ifdef SKIDBUFFER
    assume property (IDATA_HELD_WHEN_NOT_READY);
`else
    assert property (IDATA_HELD_WHEN_NOT_READY);
`endif
`endif
```

ZipCPU `axi_rules.html` lines 465–486 restates the same property for AXI-Stream master verification with the additional reminder to add `$stable(...)` checks for every sideband signal actually present (TLAST, TID, TDEST, TKEEP, TUSER) — the property applies symmetrically to the full payload bus.

**Bug symptoms in simulation.** Three observations should each trigger a deeper look:

1. The producer's `valid` and the consumer's `ready` correlate suspiciously — i.e., both go high in the same cycle far more often than chance would predict — *and* a downstream FIFO reports occasional missing words. Likely: AP-20.1.
2. The consumer's captured payload register lags the producer's claimed `valid` cycle, or holds a value the producer's testbench monitor never saw asserted on the wire. Likely: AP-20.2.
3. Quartus Analysis & Synthesis reports a combinational loop touching `valid`, `ready`, and a payload register, OR (more subtly) the no-valid-drop property fires only on cycles where `ready` dips. Likely: AP-20.3.

**Checklist for a handshake-conformant module.**

- [ ] Producer's `valid` and payload register are driven by a single `always_ff` whose enable is `!valid || ready` (or equivalent). See §5.
- [ ] Consumer's "do something" logic is gated on `valid && ready` with **no further conditions**. See §5 and ZipCPU's "plus nothing!" comment.
- [ ] Reset clears producer's `valid` to 0; consumer's `ready` may be either state out of reset but its driving FSM is in a known state.
- [ ] If the consumer's `ready` is registered (e.g., to close timing), there is a skid buffer between it and the producer. See 21.
- [ ] The two SVA properties above are bound to every handshake interface in simulation builds.
- [ ] Sideband (`tlast` / `tkeep` / `tid` / `tdest` / `tuser`) is included in the `$stable` check if present.
- [ ] Quartus Analysis & Synthesis report shows no combinational loop touching `valid` or `ready`.

For deeper verification mechanics (running SVA in ModelSim, parsing TimeQuest reports, mapping handshake assertion failures back to RTL), see [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md).

## 9. Provenance footer

Every cited source listed once, with the sections it supports.

- `references/raw/fpgacpu/handshake.html` @ raw HTML capture 2026-05-20 — used for §1 (composability framing), §2 (rules 1, 2, 3, composability, direction-of-drive, the legal combinational asymmetry, reset), §3 (signal table direction rule), §5 (the `handshake_complete` recipe), §7 (AP-20.1, AP-20.2, AP-20.3).
- `references/raw/zipcpu/axi_rules.html` @ raw HTML capture 2026-05-20 — used for §2 (rules 1, 2, 3 reinforcement; the `valid`-on-`ready` combinational prohibition via the registered-`READY` recommendation; reset), §3 (treatment of "everything else" as payload), §5 (the canonical master and slave templates), §7 (AP-20.1, AP-20.2, AP-20.3 reinforcement), §8 (SVA property form).
- `references/projects/verilog-axis/rtl/axis_register.v` @ commit `48ff7a7` — used for §3 (`s_axis_*` / `m_axis_*` port-block excerpt), §6 ([O] AXI-Stream naming style).
- `references/projects/FPGADesignElements/Pipeline_Skid_Buffer.v` @ commit `2450a54` — used for §3 (`input_*` / `output_*` port-block excerpt), §6 ([O] FPGADesignElements naming style).
- `references/projects/wb2axip/rtl/skidbuffer.v` @ commit `df8e764` — used for §3 (`i_*` / `o_*` port-block excerpt), §6 ([O] wb2axip naming style), §7 (AP-20.2 formal property), §8 (formal handshake assertion block).
- `references/MANIFEST.md` (collected 2026-05-20T02:08:44Z) — used for commit pins.
