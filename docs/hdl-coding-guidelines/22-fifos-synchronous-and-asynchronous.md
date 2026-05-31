# FIFOs — Synchronous and Asynchronous

> Bundle version: 2026-05-19
> Pinned commits: verilog-axis @ 48ff7a7; wb2axip @ df8e764; fpgacpu.ca CDC primer @ 2026-05-20; Intel Quartus Standard 18.1 design-recommendations (live URL @ 2026-05-20); Cyclone V Device Handbook Vol. 1 (live URL @ 2026-05-20); Cummings SNUG 2002 async FIFO paper (live URL only, no local capture).
> Load with: [20-ready-valid-handshakes.md](20-ready-valid-handshakes.md), [21-skid-buffers-and-register-slices.md](21-skid-buffers-and-register-slices.md), [23-cdc-single-bit.md](23-cdc-single-bit.md), [24-cdc-multi-bit.md](24-cdc-multi-bit.md), [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md)
> Status mix: [C] ~45% (architectural rules — single/dual clock, Gray-coded async pointers, 2FF synchronizer chain, per-domain full/empty derivation — all anchored in verilog-axis source); [V] ~20% (MLAB ≤ ~32 / M10K ≳ deeper sizing guideline; ZipCPU `i_*`/`o_*` and FWFT conventions); [O] ~15% (per-project style variations — verilog-axis vs wb2axip vs Cummings reference); [I] ~20% (FIFO depth-from-backpressure sizing, and the two sizing anti-patterns in §7 that follow from it).
> Missing inputs: Cummings SNUG 2002 async FIFO paper is a fetch-failure stub locally (`references/raw/methodology/CummingsSNUG2002SJ_FIFO1_fetch_failed.html`, per [references/MANIFEST.md:60-61](../references/MANIFEST.md)); cited as live URL only. Intel app-shell HTMLs (`quartus_standard_design_recommendations_index.html`, `cyclone_v_embedded_memory_types.html`, `cyclone_v_embedded_memory_modes.html`) have no extractable body content; cited via live URLs.

## 1. Purpose & one-line summary

A FIFO is the depth-N buffer that decouples a producer from a consumer: a **sync** FIFO absorbs in-clock-domain rate mismatch and burst-vs-stall using binary pointers, while an **async** FIFO additionally crosses a clock boundary safely by Gray-coding its pointers and double-flop-synchronizing each across the boundary. The deliverable this doc produces in the consuming agent is the ability to pick (a) sync vs async based on whether the producer and consumer share a clock, (b) depth based on the worst-case producer-burst-versus-consumer-stall window from the pre-RTL plan, and (c) the Cyclone V storage primitive — MLAB for small distributed-memory FIFOs, M10K for deeper ones. The three handshake rules themselves, single-bit CDC mechanics, multi-bit-CDC theory (Gray-code derivation, MTBF), the Cyclone V memory-inference templates, and the FIFO-as-resource-economy framing are deferred to the docs in `Load with:`.

## 2. The contract (must-obey)

- [C] A handshake-conformant FIFO preserves the §20 handshake rules on **both** ports: `valid` and `ready` independently asserted, transfer on the cycle where both are high, no valid-drop without a transfer, payload stable while waiting. The sync FIFO's `s_axis_tready` is computed directly from `!full` (`references/projects/verilog-axis/rtl/axis_fifo.v:217 @ 48ff7a7`).
- [C] A sync FIFO uses a **single** clock domain; both ports advance on the same `posedge clk`. The sync source declares one clock port: `input  wire                   clk,` (`references/projects/verilog-axis/rtl/axis_fifo.v:94 @ 48ff7a7`).
- [C] An async FIFO has **two** independent clock domains; write and read sides have independent clocks and independent (or independently-synchronized) resets. The async source declares `s_clk`/`s_rst` and `m_clk`/`m_rst` as separate inputs (`references/projects/verilog-axis/rtl/axis_async_fifo.v:97-98,111-112 @ 48ff7a7`).
- [C] An async FIFO's pointers crossing the clock boundary **must** be Gray-coded so that exactly one bit changes per pointer increment; a binary counter can change many bits in one increment, and a 2FF synchronizer would then sample inconsistent bit combinations during the transition window. The verilog-axis implementation provides `bin2gray`/`gray2bin` functions for this purpose (`references/projects/verilog-axis/rtl/axis_async_fifo.v:195-204 @ 48ff7a7`) and Cummings establishes the design pattern (Cummings SNUG 2002 — `http://www.sunburst-design.com/papers/CummingsSNUG2002SJ_FIFO1.pdf`, live URL, no local capture). The full multi-bit-CDC derivation (why bit-by-bit sync of a binary counter is wrong, why one-bit-at-a-time changes make the synchronizer's sampling always-consistent) is deferred to [24-cdc-multi-bit.md](24-cdc-multi-bit.md); this doc shows only how the async FIFO uses the result.
- [C] Each pointer crossing requires a **2-flop synchronizer chain** in the destination clock domain — one for the write pointer arriving in the read domain, one for the read pointer arriving in the write domain. The verilog-axis source instantiates these as `wr_ptr_gray_sync1_reg`/`wr_ptr_gray_sync2_reg` and `rd_ptr_gray_sync1_reg`/`rd_ptr_gray_sync2_reg`, each tagged with `(* SHREG_EXTRACT = "NO" *)` to prevent synthesis from packing them into a shift-register primitive (`references/projects/verilog-axis/rtl/axis_async_fifo.v:218-227 @ 48ff7a7`).
- [C] `full` and `empty` are derived **in their own clock domain** from the **local** pointer and the **synchronized** version of the opposite pointer — never from the raw opposite-domain pointer. In the async source, `full` (write-side) compares local `wr_ptr_gray_reg` against synchronized `rd_ptr_gray_sync2_reg`, and `empty` (read-side) compares local `rd_ptr_gray_reg` against synchronized `wr_ptr_gray_sync2_reg` (`references/projects/verilog-axis/rtl/axis_async_fifo.v:263-267 @ 48ff7a7`). Note the Gray-code `full` test XORs the synchronized read pointer with `{2'b11, {ADDR_WIDTH-1{1'b0}}}` (two top bits flipped), **not** `{1'b1, {ADDR_WIDTH{1'b0}}}` (one top bit flipped, which is the binary-pointer trick used by the sync FIFO at line 200) — the Gray-code equivalent of "binary MSB different, rest same" is "top *two* bits different, rest same." Do not paraphrase across the two; the constants are different and the source comment at lines 263-264 says so.
- [V] A sync FIFO uses **binary** pointers, no Gray code. The sync source declares `reg [ADDR_WIDTH:0] wr_ptr_reg`, `wr_ptr_commit_reg`, `rd_ptr_reg` as straight binary registers and derives `full = wr_ptr_reg == (rd_ptr_reg ^ {1'b1, {ADDR_WIDTH{1'b0}}})` and `empty = wr_ptr_commit_reg == rd_ptr_reg` directly (`references/projects/verilog-axis/rtl/axis_fifo.v:187-202 @ 48ff7a7`). The pointer width is `ADDR_WIDTH+1` (one extra MSB) so the "different MSB, same low bits" condition disambiguates full from empty.
- [V] On Cyclone V, FIFO storage maps to **MLAB** when the configured depth is small (typical economic threshold ≤ ~32 entries, occasionally up to a few hundred words) and to **M10K** when deeper. MLAB is 640 bits of distributed memory per ALM-configured block; M10K is 10 240 bits per dedicated embedded-memory block (`cyclone-v-hdl-bundle/01-glossary.md:11-12 @ 2026-05-19`). The exact crossover is approximate and depends on width × depth × port count, init-file requirements, and the `ramstyle` attribute on the storage declaration. The full inference treatment — `ramstyle`, single/dual-port, read-during-write modes, init files, ROM templates — is deferred to [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md). Live URL for the recommendation: Intel *Inferring Memory Functions from HDL Code*, `https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/inferring-memory-functions-from-hdl-code` @ 2026-05-20; Cyclone V Device Handbook Vol. 1 (memory blocks), `https://docs.altera.com/r/docs/683375/current/cyclone-v-device-handbook-volume-1-device-interfaces-and-integration` @ 2026-05-20.
- [I] FIFO **depth** must be sized to absorb the worst-case producer burst within the consumer's worst-case stall window. No single archive source states this in one sentence; the inferential chain is: (1) producer-side backpressure (`!full` / `s_axis_tready`) is the consumer's only flow-control lever (see [20](20-ready-valid-handshakes.md)); (2) when the consumer stalls, the FIFO fills at the producer's rate; (3) if the FIFO fills before the consumer un-stalls, the producer must stall too — costing the producer throughput; therefore (4) depth = worst-case producer rate × worst-case consumer-stall window, plus margin. The two numbers should already exist in the pre-RTL plan from [10](10-hardware-mindset-and-microarchitecture.md); FIFO-as-resource-economy framing for the upper bound is in [16](16-resource-and-state-economy.md). The two anti-patterns in §7 ("too small" and "absurdly oversized") follow from this rule.

## 3. Constructs / signals / API reference

This section enumerates the two FIFO surfaces (sync and async) the consuming agent will instantiate, plus the Gray-code primitive functions, plus the Cyclone V resource-choice table. Sync and async share an AXI-Stream port discipline on each port but differ in the clock-port count and the pointer mechanism.

### 3.1 Sync FIFO port surface — verilog-axis style

```verilog
// references/projects/verilog-axis/rtl/axis_fifo.v:93-135 @ 48ff7a7
(
    input  wire                   clk,
    input  wire                   rst,

    /*
     * AXI input
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
     * AXI output
     */
    output wire [DATA_WIDTH-1:0]  m_axis_tdata,
    output wire [KEEP_WIDTH-1:0]  m_axis_tkeep,
    output wire                   m_axis_tvalid,
    input  wire                   m_axis_tready,
    output wire                   m_axis_tlast,
    output wire [ID_WIDTH-1:0]    m_axis_tid,
    output wire [DEST_WIDTH-1:0]  m_axis_tdest,
    output wire [USER_WIDTH-1:0]  m_axis_tuser,

    /*
     * Pause
     */
    input  wire                   pause_req,
    output wire                   pause_ack,

    /*
     * Status
     */
    output wire [$clog2(DEPTH):0] status_depth,
    output wire [$clog2(DEPTH):0] status_depth_commit,
    output wire                   status_overflow,
    output wire                   status_bad_frame,
    output wire                   status_good_frame
);
```

| Signal | Type / width / dir | Meaning | Driven by | Drives |
|---|---|---|---|---|
| `clk` | 1 bit, in | Single clock for both ports | system clock-tree | every register in the FIFO |
| `rst` | 1 bit, in | Synchronous reset | system reset (see [11](11-clocking-resets-and-cyclone-v-clock-networks.md)) | pointer/state initialisation |
| `s_axis_tdata` | `DATA_WIDTH`, in | Write-side payload | producer | `mem[wr_ptr_reg]` |
| `s_axis_tvalid` | 1 bit, in | Producer asserts payload valid | producer | write enable (with `s_axis_tready`) |
| `s_axis_tready` | 1 bit, out | FIFO has room (`!full` or stronger predicate for frame modes) | `full` and frame-mode logic (`axis_fifo.v:217`) | producer's stall logic |
| `m_axis_tdata` | `DATA_WIDTH`, out | Read-side payload | `mem[rd_ptr_reg]` via pipeline | consumer |
| `m_axis_tvalid` | 1 bit, out | FIFO has data (`!empty` plus output-pipe valid) | read logic | consumer |
| `m_axis_tready` | 1 bit, in | Consumer ready to accept | consumer | read-enable / `rd_ptr_reg` increment |
| `s_axis_tkeep` / `tlast` / `tid` / `tdest` / `tuser` | parametric, in | AXI-Stream sideband, propagated through `mem` | producer | consumer (via `m_axis_*` mirrors) |
| `pause_req` / `pause_ack`, `status_*` | parametric, in/out | Optional pause and status sideband | host control / status logic | host monitor |
| `DEPTH` | parameter | Configured FIFO depth in words | instantiation | `ADDR_WIDTH = $clog2(DEPTH)` |

### 3.2 Async FIFO port surface — verilog-axis style

```verilog
// references/projects/verilog-axis/rtl/axis_async_fifo.v:93-143 @ 48ff7a7
(
    /*
     * AXI input
     */
    input  wire                   s_clk,
    input  wire                   s_rst,
    input  wire [DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire [KEEP_WIDTH-1:0]  s_axis_tkeep,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,
    input  wire                   s_axis_tlast,
    input  wire [ID_WIDTH-1:0]    s_axis_tid,
    input  wire [DEST_WIDTH-1:0]  s_axis_tdest,
    input  wire [USER_WIDTH-1:0]  s_axis_tuser,

    /*
     * AXI output
     */
    input  wire                   m_clk,
    input  wire                   m_rst,
    output wire [DATA_WIDTH-1:0]  m_axis_tdata,
    output wire [KEEP_WIDTH-1:0]  m_axis_tkeep,
    output wire                   m_axis_tvalid,
    input  wire                   m_axis_tready,
    output wire                   m_axis_tlast,
    output wire [ID_WIDTH-1:0]    m_axis_tid,
    output wire [DEST_WIDTH-1:0]  m_axis_tdest,
    output wire [USER_WIDTH-1:0]  m_axis_tuser,

    /* Pause / Status: per-domain pairs (s_pause_*, m_pause_*, s_status_*,
       m_status_*) — omitted here for brevity; see the source. */
);
```

| Signal | Type / width / dir | Meaning | Driven by | Drives |
|---|---|---|---|---|
| `s_clk` | 1 bit, in | **Write-side** clock | source clock-tree | write-side pointer logic, write port of `mem` |
| `s_rst` | 1 bit, in | Write-side reset | source reset | write-side pointer init |
| `s_axis_t*` | parametric | Write-side AXI-Stream payload + handshake | producer | `mem` and `wr_ptr_reg` |
| `m_clk` | 1 bit, in | **Read-side** clock | sink clock-tree | read-side pointer logic, read port of `mem`, output pipe |
| `m_rst` | 1 bit, in | Read-side reset | sink reset | read-side pointer init |
| `m_axis_t*` | parametric | Read-side AXI-Stream payload + handshake | output pipe | consumer |
| `s_pause_*`, `m_pause_*`, `s_status_*`, `m_status_*` | parametric | Per-domain pause/status sideband; per-domain because the status signals must be read in their own clock | each domain's local logic | host monitor in that domain |

The async FIFO has **separate pause and status ports for each domain** because every status signal must be observed in the clock domain that owns it — anything else would need its own CDC handling. The brief's table sketch listed only the AXI-Stream port pairs; the omission of pause/status is deliberate, see the source.

### 3.3 The Gray-code primitive functions

These two functions are the load-bearing async-FIFO mechanism. Mechanics of *why* Gray code makes the multi-bit CDC sample-safe are deferred to [24-cdc-multi-bit.md](24-cdc-multi-bit.md); this section just exhibits them.

```verilog
// references/projects/verilog-axis/rtl/axis_async_fifo.v:195-204 @ 48ff7a7
function [ADDR_WIDTH:0] bin2gray(input [ADDR_WIDTH:0] b);
    bin2gray = b ^ (b >> 1);
endfunction

function [ADDR_WIDTH:0] gray2bin(input [ADDR_WIDTH:0] g);
    integer i;
    for (i = 0; i <= ADDR_WIDTH; i = i + 1) begin
        gray2bin[i] = ^(g >> i);
    end
endfunction
```

| Name | Type | Width | Meaning | Used by |
|---|---|---|---|---|
| `bin2gray(b)` | pure combinational function | `ADDR_WIDTH+1` → `ADDR_WIDTH+1` | Binary-to-Gray: `b ^ (b >> 1)`. Each Gray code has exactly one bit flipped from its successor's Gray code. | Write-side and read-side pointer-update logic (when the pointer increments). [C] |
| `gray2bin(g)` | pure combinational function | `ADDR_WIDTH+1` → `ADDR_WIDTH+1` | Gray-to-binary: per-bit XOR-reduction of the shifted Gray value. | Recovering a numeric pointer in the destination domain when the FIFO needs depth/overflow status. [C] |
| `wr_ptr_gray_reg` | register | `ADDR_WIDTH+1` | Gray-coded write pointer, the value that crosses into the read domain. | Driven by write-side from `bin2gray(wr_ptr_reg)`; consumed by `rd_ptr_gray_sync1_reg` in read domain. [C] |
| `rd_ptr_gray_reg` | register | `ADDR_WIDTH+1` | Gray-coded read pointer, the value that crosses into the write domain. | Driven by read-side; consumed by `wr_ptr_gray_sync1_reg` in write domain (symbol-name mirror; verify in source). [C] |
| `wr_ptr_gray_sync1_reg` / `wr_ptr_gray_sync2_reg` | registers in read domain | `ADDR_WIDTH+1` each | 2-flop synchronizer chain for the write pointer arriving in the read domain. Tagged `(* SHREG_EXTRACT = "NO" *)` so synthesis treats them as discrete flops, not a shift register. | `empty` derivation in read domain. [C] |
| `rd_ptr_gray_sync1_reg` / `rd_ptr_gray_sync2_reg` | registers in write domain | `ADDR_WIDTH+1` each | 2-flop synchronizer chain for the read pointer arriving in the write domain. Same `SHREG_EXTRACT` discipline. | `full` derivation in write domain. [C] |

### 3.4 Cyclone V storage primitive choice (sizing guideline)

| Depth × width | Primitive | Why | Cite |
|---|---|---|---|
| ≤ ~32 words, narrow (parametric — guideline only) | flops | A few flops cost less than the MLAB overhead and routing | [16](16-resource-and-state-economy.md), the four-justifications check |
| ~32 to ~few hundred words, narrow-to-moderate | **MLAB** (640 bits per block, distributed in ALMs) | MLAB is sized for small frequently-accessed memories; the storage shares ALMs with logic | Cyclone V Device Handbook Vol. 1 (live URL) @ 2026-05-20; bundle glossary `cyclone-v-hdl-bundle/01-glossary.md:11 @ 2026-05-19` |
| deeper (typical FIFO use, kilobits to ~10 kb each) | **M10K** (10 240 bits per dedicated embedded-memory block) | M10K is sized for FIFOs, frame buffers, line buffers, tile maps | Cyclone V Device Handbook Vol. 1 (live URL) @ 2026-05-20; bundle glossary `cyclone-v-hdl-bundle/01-glossary.md:12 @ 2026-05-19` |

The exact crossover is approximate; Quartus may select differently based on width × depth × port count, init-file presence, and the `ramstyle` attribute. The brief explicitly defers the full inference treatment to [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md). [V] for the sizing guideline; the verilog-axis sync FIFO storage declaration uses `(* ramstyle = "no_rw_check" *) reg [WIDTH-1:0] mem[(2**ADDR_WIDTH)-1:0];` at `references/projects/verilog-axis/rtl/axis_fifo.v:191-192 @ 48ff7a7` — the attribute relaxes the read-during-write check and is part of how Quartus's RAM-template matcher decides MLAB vs M10K. Mechanics in [30](30-memory-inference-cyclone-v.md).

## 4. Sequencing & timing

Two subsections, one per FIFO type. The sync case is one-clock; the async case is two-clock with synchronizer latency on each pointer crossing.

### 4.1 Sync FIFO — single clock, depth-4 example

Producer writes four payloads `D0..D3` into an empty FIFO; consumer stalls (`m_axis_tready = 0`) for two cycles; FIFO holds at depth 4; consumer asserts `ready`; FIFO drains.

```
                    cycle: 0   1   2   3   4   5   6   7   8   9  10
clk           ___|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|__
s_axis_tvalid       1   1   1   1   0   0   0   0   0   0   0
s_axis_tdata       D0  D1  D2  D3   -   -   -   -   -   -   -
s_axis_tready       1   1   1   1   1   1   1   1   1   1   1     (FIFO never full
                                                                    at depth=8)
wr_ptr_reg          0   1   2   3   4   4   4   4   4   4   4
rd_ptr_reg          0   0   0   0   0   0   0   1   2   3   4
empty               1   0   0   0   0   0   0   0   0   0   1
m_axis_tvalid       0   1   1   1   1   1   1   1   1   1   0     (high once data
                                                                    has propagated
                                                                    through output
                                                                    pipe)
m_axis_tready       0   0   0   0   0   0   1   1   1   1   1
m_axis_tdata        -   -   -   -   -   -  D0  D1  D2  D3   -
                                            ^ transfer on
                                              valid && ready
```

Key observations:

- `wr_ptr_reg` increments on every `s_axis_tvalid && s_axis_tready` cycle (cycles 0-3).
- `rd_ptr_reg` increments on every `m_axis_tvalid && m_axis_tready` cycle (cycles 6-9).
- `empty = (wr_ptr_commit_reg == rd_ptr_reg)` per `axis_fifo.v:202` — true when the two binary pointers match exactly.
- `full = (wr_ptr_reg == (rd_ptr_reg ^ {1'b1, {ADDR_WIDTH{1'b0}}}))` per `axis_fifo.v:200` — true when the MSBs differ and the low bits match. This is the standard "one extra MSB" trick on a binary pointer of width `ADDR_WIDTH+1`.
- Both pointers, the storage RAM, and the full/empty derivations live on the **same** `posedge clk`. There is no synchronizer chain.

### 4.2 Async FIFO — two clocks, Gray-coded pointers

Write side runs on `s_clk`; read side runs on `m_clk`. The two clocks are independent. The waveform below uses **two-period write clock for every one-period read clock** to illustrate the synchronizer latency; in practice the relationship is arbitrary.

```
                              s_clk side                            m_clk side
                              (write)                               (read, faster)

wclk           ___|‾‾|____|‾‾|____|‾‾|____|‾‾|____         rclk  __|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|__
wr_ptr_reg (bin)   00 -> 01 -> 10 -> 11 -> 100                    (steady; read-side reads
wr_ptr_gray_reg    00 -> 01 -> 11 -> 10 -> 110                     synchronized version)
                   ^         ^         ^
                   |         |         |
                   |         |         +--- one bit changes per pointer increment
                   |         +-------- one bit changes
                   +------------- one bit changes
                                                                 wr_ptr_gray_sync1_reg ___|‾|_|‾‾‾‾|___
                                                                                                     ^ 1 rclk later
                                                                 wr_ptr_gray_sync2_reg ____|‾|_|‾‾‾|___
                                                                                                     ^ 2 rclk later
                                                                                                       (this drives empty)

empty (rd-side) = (rd_ptr_gray_reg == wr_ptr_gray_sync2_reg)         per axis_async_fifo.v:267
full (wr-side)  = (wr_ptr_gray_reg ==
                   (rd_ptr_gray_sync2_reg ^ {2'b11, {ADDR_WIDTH-1{1'b0}}}))  per axis_async_fifo.v:265
```

Key observations:

- `wr_ptr_reg` is a binary counter on the write side; `wr_ptr_gray_reg = bin2gray(wr_ptr_reg)` is what crosses into the read domain. Exactly one bit changes per increment (the defining property of Gray code).
- The synchronizer chain `wr_ptr_gray_sync1_reg → wr_ptr_gray_sync2_reg` adds **2 read clocks of latency** between a write-pointer update and the read-side observing it. `empty` therefore appears slightly later than reality: there may be data in the FIFO that the reader doesn't see for up to two read clocks after the write.
- Symmetrically, `full` (write-side) appears slightly **earlier** than reality: when the reader drains a slot, it takes two write clocks before the writer learns of the increase in headroom.
- Both directions are conservative: the writer stalls a few cycles before it strictly must, the reader treats the FIFO as empty a few cycles after the last word actually landed. Neither produces a correctness bug — only a small efficiency cost.
- The Gray-code `full` condition uses `{2'b11, {ADDR_WIDTH-1{1'b0}}}` (top **two** bits flipped); the binary `full` condition in the sync FIFO uses `{1'b1, {ADDR_WIDTH{1'b0}}}` (one MSB flipped). Both encode the same "wrapped one whole capacity" condition, but in Gray space the wrap involves the top two bits. The source comment at `axis_async_fifo.v:263-264` is `// full when first TWO MSBs do NOT match, but rest matches // (gray code equivalent of first MSB different but rest same)`.
- The underlying multi-bit-CDC theory (why exactly one bit per increment makes 2FF-synchronizer sampling correct, MTBF arithmetic) is deferred to [24-cdc-multi-bit.md](24-cdc-multi-bit.md). The single-bit-CDC mechanics — the synchronizer chain itself — are in [23-cdc-single-bit.md](23-cdc-single-bit.md). This doc shows only the pattern: Gray + 2FF + per-domain derivation.

## 5. Minimal working pattern

### 5.1 Smallest correct sync FIFO core

```verilog
// references/projects/verilog-axis/rtl/axis_fifo.v:187-204 @ 48ff7a7
reg [ADDR_WIDTH:0] wr_ptr_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] wr_ptr_commit_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] rd_ptr_reg = {ADDR_WIDTH+1{1'b0}};

(* ramstyle = "no_rw_check" *)
reg [WIDTH-1:0] mem[(2**ADDR_WIDTH)-1:0];
reg mem_read_data_valid_reg = 1'b0;

(* shreg_extract = "no" *)
reg [WIDTH-1:0] m_axis_pipe_reg[RAM_PIPELINE+1-1:0];
reg [RAM_PIPELINE+1-1:0] m_axis_tvalid_pipe_reg = 0;

// full when first MSB different but rest same
wire full = wr_ptr_reg == (rd_ptr_reg ^ {1'b1, {ADDR_WIDTH{1'b0}}});
// empty when pointers match exactly
wire empty = wr_ptr_commit_reg == rd_ptr_reg;
// overflow within packet
wire full_wr = wr_ptr_reg == (wr_ptr_commit_reg ^ {1'b1, {ADDR_WIDTH{1'b0}}});
```

Plus the single line that wires backpressure to the producer:

```verilog
// references/projects/verilog-axis/rtl/axis_fifo.v:217 @ 48ff7a7
assign s_axis_tready = FRAME_FIFO ? (!full || (full_wr && DROP_OVERSIZE_FRAME) || DROP_WHEN_FULL) : (!full || MARK_WHEN_FULL);
```

In the default (non-frame, non-mark-when-full) mode, this collapses to `s_axis_tready = !full`. This is the [C] backpressure path — disconnecting it is the #38 anti-pattern in §7. The `(* ramstyle = "no_rw_check" *)` attribute on `mem` is the synthesis hint that pushes the storage toward M10K-or-MLAB inference rather than flops; the trade-off mechanics belong in [30](30-memory-inference-cyclone-v.md).

### 5.2 Smallest correct async FIFO core

The async FIFO's load-bearing block is the Gray-code functions + pointer registers + synchronizer chain + per-domain full/empty derivation. The brief authorises ~70 verbatim lines here because this is the doc's anchor excerpt:

```verilog
// references/projects/verilog-axis/rtl/axis_async_fifo.v:195-267 @ 48ff7a7
function [ADDR_WIDTH:0] bin2gray(input [ADDR_WIDTH:0] b);
    bin2gray = b ^ (b >> 1);
endfunction

function [ADDR_WIDTH:0] gray2bin(input [ADDR_WIDTH:0] g);
    integer i;
    for (i = 0; i <= ADDR_WIDTH; i = i + 1) begin
        gray2bin[i] = ^(g >> i);
    end
endfunction

reg [ADDR_WIDTH:0] wr_ptr_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] wr_ptr_commit_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] wr_ptr_gray_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] wr_ptr_sync_commit_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] rd_ptr_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] rd_ptr_gray_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] wr_ptr_conv_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] rd_ptr_conv_reg = {ADDR_WIDTH+1{1'b0}};

reg [ADDR_WIDTH:0] wr_ptr_temp;
reg [ADDR_WIDTH:0] rd_ptr_temp;

(* SHREG_EXTRACT = "NO" *)
reg [ADDR_WIDTH:0] wr_ptr_gray_sync1_reg = {ADDR_WIDTH+1{1'b0}};
(* SHREG_EXTRACT = "NO" *)
reg [ADDR_WIDTH:0] wr_ptr_gray_sync2_reg = {ADDR_WIDTH+1{1'b0}};
(* SHREG_EXTRACT = "NO" *)
reg [ADDR_WIDTH:0] wr_ptr_commit_sync_reg = {ADDR_WIDTH+1{1'b0}};
(* SHREG_EXTRACT = "NO" *)
reg [ADDR_WIDTH:0] rd_ptr_gray_sync1_reg = {ADDR_WIDTH+1{1'b0}};
(* SHREG_EXTRACT = "NO" *)
reg [ADDR_WIDTH:0] rd_ptr_gray_sync2_reg = {ADDR_WIDTH+1{1'b0}};

reg wr_ptr_update_valid_reg = 1'b0;
reg wr_ptr_update_reg = 1'b0;
(* SHREG_EXTRACT = "NO" *)
reg wr_ptr_update_sync1_reg = 1'b0;
(* SHREG_EXTRACT = "NO" *)
reg wr_ptr_update_sync2_reg = 1'b0;
(* SHREG_EXTRACT = "NO" *)
reg wr_ptr_update_sync3_reg = 1'b0;
(* SHREG_EXTRACT = "NO" *)
reg wr_ptr_update_ack_sync1_reg = 1'b0;
(* SHREG_EXTRACT = "NO" *)
reg wr_ptr_update_ack_sync2_reg = 1'b0;

(* SHREG_EXTRACT = "NO" *)
reg s_rst_sync1_reg = 1'b1;
(* SHREG_EXTRACT = "NO" *)
reg s_rst_sync2_reg = 1'b1;
(* SHREG_EXTRACT = "NO" *)
reg s_rst_sync3_reg = 1'b1;
(* SHREG_EXTRACT = "NO" *)
reg m_rst_sync1_reg = 1'b1;
(* SHREG_EXTRACT = "NO" *)
reg m_rst_sync2_reg = 1'b1;
(* SHREG_EXTRACT = "NO" *)
reg m_rst_sync3_reg = 1'b1;

(* ramstyle = "no_rw_check" *)
reg [WIDTH-1:0] mem[(2**ADDR_WIDTH)-1:0];
reg mem_read_data_valid_reg = 1'b0;

(* shreg_extract = "no" *)
reg [WIDTH-1:0] m_axis_pipe_reg[RAM_PIPELINE+1-1:0];
reg [RAM_PIPELINE+1-1:0] m_axis_tvalid_pipe_reg = 0;

// full when first TWO MSBs do NOT match, but rest matches
// (gray code equivalent of first MSB different but rest same)
wire full = wr_ptr_gray_reg == (rd_ptr_gray_sync2_reg ^ {2'b11, {ADDR_WIDTH-1{1'b0}}});
// empty when pointers match exactly
wire empty = FRAME_FIFO ? (rd_ptr_reg == wr_ptr_commit_sync_reg) : (rd_ptr_gray_reg == wr_ptr_gray_sync2_reg);
```

Three things to notice across the two minimal patterns:

1. **The sync FIFO has no Gray-code functions, no `*_sync*_reg` chain, and a one-MSB-flip `full` test.** The async FIFO has all three. Copying the sync pattern into a two-clock design produces silent corruption (anti-pattern #21 in §7); copying the async pattern into a one-clock design adds unnecessary latency (anti-pattern #20 in §7).
2. **Both files declare `mem` with `(* ramstyle = "no_rw_check" *)` and a power-of-two depth `(2**ADDR_WIDTH)`.** The attribute steers Quartus toward block-RAM inference and relaxes the read-during-write check; depth being a power of two simplifies pointer-wrap modulo arithmetic to a free bit-truncation. Inference mechanics live in [30](30-memory-inference-cyclone-v.md).
3. **Both files declare pointers at width `ADDR_WIDTH+1`** (one extra MSB beyond what the address into `mem` needs). The extra MSB is what disambiguates full from empty: `wr_ptr == rd_ptr` is empty, `wr_ptr == rd_ptr ^ {1'b1, 0…}` (or the Gray two-MSB equivalent) is full. Without the extra bit, the two conditions collide.

## 6. Common variations across implementations

- **[O] verilog-axis style** (this doc's primary source): AXI-Stream port discipline (`s_axis_*` / `m_axis_*` with `tdata`, `tkeep`, `tvalid`, `tready`, `tlast`, `tid`, `tdest`, `tuser`), parametric depth and width, optional frame-mode (`FRAME_FIFO`, `DROP_OVERSIZE_FRAME`, `DROP_BAD_FRAME`, `MARK_WHEN_FULL`), optional pause, optional status sideband, RAM-inferred storage via `(* ramstyle = "no_rw_check" *)`. `references/projects/verilog-axis/rtl/axis_fifo.v @ 48ff7a7` and `axis_async_fifo.v @ 48ff7a7`.
- **[O] wb2axip / ZipCPU style** (formally-verified): ZipCPU `i_*` / `o_*` port-direction prefix convention; smaller bare-FIFO surface (`i_wr`, `i_data`, `o_full`, `o_fill`, `i_rd`, `o_data`, `o_empty`); a `LGFLEN` log-two depth parameter rather than a `DEPTH` parameter; an `OPT_ASYNC_READ` toggle that distinguishes the LUT-RAM and registered-read variants; formal-mode `f_*` peek ports for SymbiYosys proof harness. `references/projects/wb2axip/rtl/sfifo.v:26-62 @ df8e764`. The async sibling `references/projects/wb2axip/rtl/afifo.v:36-90 @ df8e764` adds an `NFF` parameter for the synchronizer depth (default 2, so the user can extend to 3+ in high-MTBF applications), the `(* ASYNC_REG = "TRUE" *)` attribute on the synchronizer chain, and an `OPT_REGISTER_READS` toggle for the distributed-RAM-vs-block-RAM read path. Cite for the formal-verification framing.
- **[O] Cummings academic reference design** (canonical: separate read-pointer module, separate write-pointer module, separate dual full/empty derivations, a separate FIFO-memory module): the structural template most newer designs descend from. Cited live URL only: `http://www.sunburst-design.com/papers/CummingsSNUG2002SJ_FIFO1.pdf` (live URL, no local capture — the local file `references/raw/methodology/CummingsSNUG2002SJ_FIFO1_fetch_failed.html` is a fetch-failure stub per [references/MANIFEST.md:60-61](../references/MANIFEST.md)).
- **[V] FWFT vs standard-read** discipline: in **FWFT** (first-word fall-through) the FIFO presents the head-of-queue datum at the output **without requiring a read-enable pulse**, so the read side observes the data and asserts `ready` when it wants to consume; in **standard-read** the consumer must drive a read pulse to advance the FIFO and the data appears one cycle later. The verilog-axis FIFOs are effectively FWFT — `m_axis_tvalid` rises when data is available, `m_axis_tready` consumes it on the cycle both are high. FWFT is what makes a depth-2 FIFO equivalent to a skid buffer (see [21-skid-buffers-and-register-slices.md](21-skid-buffers-and-register-slices.md) for the depth-1/2 FWFT-as-skid-buffer framing).
- **[O] MLAB-inferred small FIFO vs M10K-inferred deeper FIFO** on Cyclone V: at small depths the Quartus RAM-template matcher allocates MLAB (640 bits per block, distributed in ALMs); at larger depths it allocates M10K (10 240 bits per dedicated block). The threshold depends on width × depth × port count and is approximate — Intel's design-recommendations document calls it a guideline, not a hard line. Cite: Intel *Inferring Memory Functions from HDL Code* (live URL, `https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/inferring-memory-functions-from-hdl-code` @ 2026-05-20) plus the Cyclone V Device Handbook Vol. 1 memory-block sections (live URL, `https://docs.altera.com/r/docs/683375/current/cyclone-v-device-handbook-volume-1-device-interfaces-and-integration` @ 2026-05-20). Full inference mechanics — `ramstyle` values, single/dual-port, read-during-write modes, init files — defer to [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md).
- **[O] AXI4 register-slice FIFOs** (`verilog-axi/rtl/axi_register_rd.v` / `axi_register_wr.v` @ 516bd5d) — register-slice patterns on the AXI4 full bus rather than AXI-Stream, with separate AR/R and AW/W/B channel buffering. Surfaced only as a pointer for AXI4 work (not AXI-Stream).

## 7. Anti-patterns (mistakes that compile but break)

Five entries below. #38 is the **primary home** for this doc; #21 and #20 are surfaced as cross-references because the temptation lives here, with primary treatments in 24 and 23 respectively. The two FIFO-sizing entries are **spec §9 addendum** — they extend the spec's pre-committed anti-pattern list and Phase 3 should pick them up into `90-anti-patterns.md`.

### #38 — FIFO without producer-side backpressure (PRIMARY HOME)

- **Symptom:** FIFO occasionally overflows under burst load; data corruption; the producer drops values silently OR the system "works in simulation, fails on hardware" because the testbench's producer happens to never burst at the rate the actual upstream module does. Often surfaces as intermittent stream-position drift between producer and consumer, framed by a partner module that finally notices.
- **Cause:** The producer is not wired to honor the FIFO's `s_axis_tready` (or equivalently `!full`). One of: the wire is left unconnected, is tied to a constant `1'b1`, the producer's local stall-logic is missing, or someone elided the gating with a "the FIFO is deep enough, this won't happen" comment.
- **Fix:** Route the FIFO's upstream-facing `s_axis_tready` (or `!full`) back to the producer and obey the §20 handshake rules — payload-stable while `!ready`, work on the cycle where both are asserted, no valid-drop without a transfer. If the producer is genuinely incapable of stalling (e.g. fixed-rate ADC), the FIFO must be sized to never fill (§7 entry "depth too small" below) **and** an overflow status flag must be exported and a software/host policy installed for the case the producer outruns the consumer's worst-case stall window for longer than expected.
- **Citation:** `references/projects/verilog-axis/rtl/axis_fifo.v:217 @ 48ff7a7` shows `s_axis_tready` as an **output** of the FIFO computed from `!full` (with frame-mode predicates). Treating it as a "didn't need to wire that up" output is the canonical form of this anti-pattern. Cross-ref [20-ready-valid-handshakes.md](20-ready-valid-handshakes.md) for the three handshake rules themselves.

### Under-sized FIFO depth for worst-case burst (spec §9 addendum)

- **Symptom:** FIFO stalls the producer in steady state because the consumer cannot drain fast enough during transient stalls; the design's throughput target is missed under measured worst-case input rates even though all individual modules meet their local timing. Often discovered late, in system-level performance testing after individual-module verification has signed off.
- **Cause:** Depth was guessed (often "power of two, round up, looks fine") rather than computed from the producer's worst-case burst rate × the consumer's worst-case stall window, both of which should be in the pre-RTL plan from [10-hardware-mindset-and-microarchitecture.md](10-hardware-mindset-and-microarchitecture.md). Depth-by-guess works only when the actual workload happens to have less burstiness than the guess assumed; the bug surfaces when workload changes.
- **Fix:** Re-derive depth from the design plan. The minimum depth is `producer_rate × consumer_worst_stall_window` (in word/clock units consistent with the FIFO's `DATA_WIDTH`); add margin for measurement uncertainty in the stall window. Then check the Cyclone V resource cost via the §3.4 table and confirm the chosen depth × width still fits the MLAB/M10K budget allocated in [16-resource-and-state-economy.md](16-resource-and-state-economy.md).
- **Citation:** [I] — inferential chain from §2 [I] rule on depth-from-backpressure. No single archive source frames this as a named anti-pattern, but every text covering ready/valid composability and FIFO design implies it.

### Over-sized FIFO depth "to be safe" (spec §9 addendum)

- **Symptom:** Deep FIFOs whose status registers show they never approach full in any observed workload; the design consumes more M10K blocks than the resource budget allocates; Fitter report shows M10K utilisation at 70%+ with several FIFOs each holding orders of magnitude more depth than they ever use. Surfaces as a resource-economy violation when [16](16-resource-and-state-economy.md)'s four-justifications check is applied to the storage.
- **Cause:** Misunderstanding the FIFO as defensive plumbing — "more is safer" — rather than as a sized buffer between a producer with a known worst-case burst and a consumer with a known worst-case stall. Often happens when the pre-RTL plan is skipped and the FIFO is dropped in at integration time with a depth chosen by superstition.
- **Fix:** Size to the computed worst-case burst plus a measurement-uncertainty margin (typically <2×, not 10× or 100×). When the computed worst case turns out to fit in flops or MLAB, **use that primitive** rather than M10K. Cross-ref [16-resource-and-state-economy.md](16-resource-and-state-economy.md) (resource economy) and [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md) (which primitive Quartus picks for a given depth × width).
- **Citation:** [I] — same inferential chain as the under-sized case, from the opposite direction. Cross-ref [16-resource-and-state-economy.md](16-resource-and-state-economy.md) §2's four-justifications check, which treats every storage bit as something that must justify itself.

### Binary counter as async-FIFO pointer (cross-ref to doc 24 #21)

- **Symptom:** Intermittent data corruption in an async FIFO, correlated with burst rate at the source; failure rate depends on the value-pattern of the pointer (worst when many low bits transition together — e.g. crossing from `0111` to `1000`); sometimes invisible in simulation because most simulators don't model setup/hold-window metastability faithfully.
- **Cause:** The async-FIFO pointer crossing the clock domain is a raw binary counter rather than a Gray-coded one. When the counter increments through a multi-bit transition (`0111 → 1000` flips four bits), the 2-flop synchronizer on the receiving side can sample partway through the transition and capture an intermediate value (e.g. `1111` or `0000`) that never existed in the source domain. Full/empty derivation then uses a fictitious pointer value.
- **Fix:** Gray-code the pointer. Use `bin2gray(b) = b ^ (b >> 1)` at the source side, run that through the 2FF synchronizer at the destination, and (if a numeric value is needed in the destination domain) recover it with `gray2bin`. Pattern: `references/projects/verilog-axis/rtl/axis_async_fifo.v:195-204,208-227,263-267 @ 48ff7a7`.
- **Citation:** This is **spec §9 #21**, primary home **[24-cdc-multi-bit.md](24-cdc-multi-bit.md)** — surfaced here because the async FIFO is where the requirement bites in practice. Cite `references/projects/verilog-axis/rtl/axis_async_fifo.v:195-204 @ 48ff7a7` (Gray functions) plus Cummings SNUG 2002 (`http://www.sunburst-design.com/papers/CummingsSNUG2002SJ_FIFO1.pdf`, live URL, no local capture).

### 2FF synchronizer on a same-clock-domain pointer (cross-ref to doc 23 #20)

- **Symptom:** "The sync FIFO seems slow" — extra latency between write and read appearing where the design plan expected none; the FIFO works correctly but consumes more cycles than the pre-RTL plan budgeted for; Fitter report shows the FIFO consuming more flops than its width × depth × pointer-bits would predict.
- **Cause:** The author copied the async FIFO pattern (Gray pointer + 2FF synchronizer chain + per-domain derivation) into a one-clock design without recognising the synchronizers are unnecessary when both ports advance on the same clock. The synchronizer chain adds two cycles of latency to the read-side observation of `wr_ptr_reg`, and the Gray-code conversion adds combinational delay with no benefit (the receiving flop is in the same clock domain — there is no metastability to mitigate).
- **Fix:** Remove the synchronizer chain. Use binary pointers directly, derive `full = wr_ptr_reg == (rd_ptr_reg ^ {1'b1, {ADDR_WIDTH{1'b0}}})` and `empty = wr_ptr_reg == rd_ptr_reg`. The sync source `references/projects/verilog-axis/rtl/axis_fifo.v:187-202 @ 48ff7a7` shows the bare pattern.
- **Citation:** Spec §9 **#20**, primary home **[23-cdc-single-bit.md](23-cdc-single-bit.md)**. [I] for this doc's framing of the FIFO-specific manifestation; the underlying 2FF-synchronizer-purpose-and-cost analysis lives in 23.

## 8. Verification

How to confirm the FIFO is doing what it should and how the canonical bug symptoms map back to root causes.

### 8.1 SVA handshake assertions on both ports

For both the sync and the async FIFO, the §20 handshake rules apply on each port. The bundle's SVA framing belongs to [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md); for this topic the load-bearing assertions are:

- `!s_axis_tready |-> !$past(s_axis_tready_handshake_committed)` — once `s_axis_tready` deasserts, the FIFO must not have silently committed a transfer that the producer wasn't expecting (handshake-rule #2 mirror on the FIFO side).
- `s_axis_tvalid && !s_axis_tready |=> $stable(s_axis_tdata) && $stable(s_axis_tlast) && …` — payload-stable while waiting (handshake-rule #1).
- `m_axis_tvalid |-> !empty_or_intermediate_state` — the FIFO must not assert `m_axis_tvalid` when it has no data to present (the output-pipe valid mirrors the storage state).

For the async FIFO, additionally:

- The pre-synchronization pointer (`wr_ptr_gray_reg`) and its post-synchronization version (`wr_ptr_gray_sync2_reg`) differ by **exactly the synchronizer latency** in the read clock domain. SVA cannot directly assert this across clock domains; Quartus's metastability analyzer is the tool — cross-ref [23-cdc-single-bit.md](23-cdc-single-bit.md) for the MTBF report.
- `full` is derived only from local + synchronized counterparts, never from the raw opposite-domain pointer. Checked by code review of `axis_async_fifo.v:263-267 @ 48ff7a7` — the assertion is on the source, not the simulation.

The wb2axip `afifo.v` has a formal-mode section (`f_fill` and friends) that proves these properties with SymbiYosys. Use it as a reference template when adapting; the bundle does not require running SymbiYosys, but the proof artifacts are useful when designing the SVA checks.

### 8.2 Bug-symptom → root-cause cheat sheet

| Bug symptom | Likely root cause | Diagnostic |
|---|---|---|
| Corruption only under burst load | Depth too small (§7) | Compare measured worst-case fill to declared `DEPTH`; re-derive from worst-case burst × stall window |
| Intermittent corruption in async FIFO; pattern-dependent | Pointer not Gray-coded (§7 #21) or synchronizer chain wrong | Grep for `bin2gray` use; check `(* SHREG_EXTRACT = "NO" *)` on each `*_sync*_reg`; check `full`/`empty` are derived from `*_sync2_reg`, not raw |
| Sync FIFO has extra latency | Unnecessary synchronizer chain copied from async pattern (§7 #20) | Remove the `*_sync*_reg` declarations; use binary pointers directly |
| Producer drops values silently | `s_axis_tready` not connected back to producer (§7 #38) | Check the producer's instantiation: `s_axis_tready` must be an input it honours |
| M10K count too high | Over-sized depth (§7) | Compare `DEPTH` to computed worst case; right-size and re-elaborate |
| `m_axis_tvalid` rises but `m_axis_tdata` is X | Reset polarity / reset coverage problem | Cross-ref [11-clocking-resets-and-cyclone-v-clock-networks.md](11-clocking-resets-and-cyclone-v-clock-networks.md); reset coverage check |

### 8.3 Quartus report check for storage primitive

The Fitter report's "RAM Summary" section names the inferred storage primitive (MLAB or M10K) per `mem` declaration. Confirm the FIFO landed on the primitive the design plan budgeted: small FIFOs in MLAB, deep FIFOs in M10K. If Quartus chose differently, re-examine the depth × width × port-count combination and the `ramstyle` attribute. Cross-ref [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md) for the inference table and [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md) for the report-reading mechanics.

## 9. Provenance footer

- `references/projects/verilog-axis/rtl/axis_fifo.v @ 48ff7a7` — used for §2 ([C] single-clock, [C] handshake backpressure, [V] binary pointers), §3.1 (sync port surface), §5.1 (minimal sync core), §7 (#38 backpressure-citation), §8.
- `references/projects/verilog-axis/rtl/axis_async_fifo.v @ 48ff7a7` — used for §2 ([C] two-clock, [C] Gray-coded pointers, [C] 2FF synchronizer chain, [C] per-domain full/empty derivation), §3.2 (async port surface), §3.3 (Gray-code functions and pointer table), §4.2 (async waveform), §5.2 (load-bearing minimal async core, lines 195-267), §7 (#21 cross-ref citation), §8.
- `references/projects/wb2axip/rtl/sfifo.v @ df8e764` — used for §6 ([O] ZipCPU formally-verified sync FIFO style).
- `references/projects/wb2axip/rtl/afifo.v @ df8e764` — used for §6 ([O] ZipCPU formally-verified async FIFO style with `NFF` parameter and `(* ASYNC_REG = "TRUE" *)` attribute), §8 (formal proof template reference).
- `references/projects/verilog-axi/rtl/axi_register_rd.v @ 516bd5d` and `axi_register_wr.v @ 516bd5d` — used for §6 ([O] AXI4 register-slice pointer; orientation only, not load-bearing).
- `references/raw/fpgacpu/cdc.html @ 2026-05-20` — used for the framing in §2 ([C] Gray pointers crossing the clock boundary) and §4.2 (synchronizer-latency narrative); mechanics deferred to [24-cdc-multi-bit.md](24-cdc-multi-bit.md).
- `cyclone-v-hdl-bundle/01-glossary.md:11-12 @ 2026-05-19` — used for §2 ([V] MLAB 640 bits, M10K 10 240 bits) and §3.4 (Cyclone V resource-choice table); bundle-internal restatement of the Cyclone V product-table headline numbers.
- `https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/inferring-memory-functions-from-hdl-code` @ 2026-05-20 — Intel *Quartus Standard 18.1 Design Recommendations: Inferring Memory Functions from HDL Code*. Live URL; the local `references/raw/intel/quartus_standard_design_recommendations_index.html` is a 2.6 KB app-shell with no extractable body content. Used for §2 ([V] MLAB-vs-M10K sizing guidance) and §3.4. **Live URL, local capture is app-shell only.**
- `https://docs.altera.com/r/docs/683375/current/cyclone-v-device-handbook-volume-1-device-interfaces-and-integration` @ 2026-05-20 — Intel *Cyclone V Device Handbook Volume 1, Device Interfaces and Integration*. Live URL; the local `references/raw/intel/cyclone_v_embedded_memory_types.html` and `cyclone_v_embedded_memory_modes.html` are app-shells with no extractable body content. Used for §2 ([V] MLAB / M10K capacity facts) and §3.4. **Live URL, local capture is app-shell only.**
- `http://www.sunburst-design.com/papers/CummingsSNUG2002SJ_FIFO1.pdf` — Cummings, *Simulation and Synthesis Techniques for Asynchronous FIFO Design*, SNUG 2002 San Jose. **Live URL, no local capture** (the local file `references/raw/methodology/CummingsSNUG2002SJ_FIFO1_fetch_failed.html` is a fetch-failure stub per [references/MANIFEST.md:60-61](../references/MANIFEST.md)). Used for §2 ([C] Gray-coded pointers — design-pattern attribution), §6 ([O] Cummings academic reference design), §7 (#21 cross-ref citation).
- [`references/MANIFEST.md`](../references/MANIFEST.md) — used in §9 itself to document the fetch-failure status of the Cummings paper.

Archive sources cited: nine. Live URLs cited: three (Intel design-recommendations, Cyclone V Device Handbook Vol. 1, Cummings SNUG 2002).
