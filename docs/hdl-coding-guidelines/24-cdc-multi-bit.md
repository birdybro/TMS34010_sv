# CDC — Multi-Bit Crossings

> Bundle version: 2026-05-19
> Pinned commits: FPGADesignElements `CDC_Word_Synchronizer.v` / `CDC_FIFO_Buffer.v` / `Binary_to_Gray_Reflected.v` @ 2026-05-20; verilog-axis @ 48ff7a7; verilogpro CDC part 2 @ 2026-05-20; fpgacpu.ca CDC primer @ 2026-05-20; Cummings SNUG 2008 Boston CDC paper (live URL only, no local capture); Cummings SNUG 2002 SJ async FIFO paper (live URL only, no local capture).
> Load with: [23-cdc-single-bit.md](23-cdc-single-bit.md), [22-fifos-synchronous-and-asynchronous.md](22-fifos-synchronous-and-asynchronous.md), [16-resource-and-state-economy.md](16-resource-and-state-economy.md), [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md)
> Status mix: [C] ~50% (the multi-bit anti-rule, the three correct patterns, Gray-before-crossing-register, payload-stable hold — anchored in Cummings SNUG2008 CDC, Cummings SNUG2002 async FIFO, and verilogpro CDC part 2); [V] ~15% (MCP payload hold mechanics, FIFO-vs-MCP selection rationale); [O] ~20% (per-project pattern realizations — verilog-axis Gray pointers, FPGADesignElements MCP, FPGADesignElements MCP-based async FIFO variant); [I] ~15% (FIFO-vs-MCP throughput comparison, quasi-static "configuration register" exception). **Both Cummings papers are cited from live URLs only; the local-archive copies are fetch-failure stubs and Phase 4 cannot verify those samples from disk** — see §9 for the live URLs and the explicit "live URL, no local capture" flag.
> Missing inputs: `references/raw/methodology/CummingsSNUG2008Boston_CDC_fetch_failed.html` and `references/raw/methodology/CummingsSNUG2002SJ_FIFO1_fetch_failed.html` (and their `_sunburstdesign_*` siblings) are fetch-failure stubs; cited via live URLs only.

## 1. Purpose & one-line summary

This doc is the contract for moving a **multi-bit** value across two asynchronously related clock domains on Cyclone V: the three correct patterns are the **dual-clock async FIFO** (for bursts or high-rate streams), the **MCP / word synchronizer handshake** (for occasional words held stable), and the **Gray-coded counter** when one side must sample the other's count without a handshake. Read [23-cdc-single-bit.md](23-cdc-single-bit.md) first for the 2FF synchronizer mechanics this doc builds on; the full async FIFO architecture (storage, depth sizing, empty/full derivation in detail) lives in [22-fifos-synchronous-and-asynchronous.md](22-fifos-synchronous-and-asynchronous.md); this doc is the home for *when to pick which pattern* and the foundational anti-rule **"never run N independent 2FF chains on the data bits of a changing multi-bit bus."**

## 2. The contract (must-obey)

- [C] A multi-bit value crossing asynchronous clock domains **must not** be carried by N independent 2FF bit synchronizers on the data bits, because each bit's settling time and skew are independent and the destination can latch a combination that never existed on the source side. Cummings SNUG2008 CDC paper, `http://www.sunburst-design.com/papers/CummingsSNUG2008Boston_CDC.pdf` (live URL, no local capture); and verilogpro CDC part 2, `references/raw/verilogpro/cdc_part2.html @ 2026-05-20` — *"if they are synchronized individually, they cannot be guaranteed to arrive in the destination clock domain on the same clock edge… the destination clock can (and will) sample at a time when not all the bits are at their stable final values. Therefore synchronizing individual bits of a multi-bit signal is not sufficient!"*
- [C] When the multi-bit value changes frequently or in bursts, **use a dual-clock async FIFO**: storage is a dual-port memory with separate read and write clocks, and only the **Gray-coded** read and write pointers cross domains, each through a 2FF synchronizer chain in the opposite domain. Cummings SNUG2002 SJ async FIFO paper, `http://www.sunburst-design.com/papers/CummingsSNUG2002SJ_FIFO1.pdf` (live URL, no local capture); the verilog-axis realization is cited in §3.
- [C] When the multi-bit value changes occasionally and the producer can hold it stable for many destination cycles, **use a multi-cycle pulse (MCP) handshake / word synchronizer**: the payload bus crosses **unsynchronized** (directly source FF to destination FF), and a single `req`/load-toggle bit is 2FF-synchronized into the destination clock domain to *time* the capture; an `ack`/return toggle is 2FF-synchronized back so the source knows the payload may change again. verilogpro CDC part 2 (`references/raw/verilogpro/cdc_part2.html @ 2026-05-20`) — *"the multi-bit data signal passes straight from source (clock) flip-flop to destination (clock) flip-flop to avoid problems with synchronizing multiple bits. A single control signal is synchronized to allow time for the multi-bit data to settle from possible metastable state"* — and FPGADesignElements `CDC_Word_Synchronizer.v` (cited in §3).
- [C] A multi-bit counter or pointer that is *sampled* across asynchronous clock domains (no handshake) **must be Gray-coded** so that any single increment changes exactly one bit; a destination sample taken mid-transition is then at worst one count off (old value or new value), never an invalid intermediate. Cummings SNUG2002 SJ async FIFO (live URL above) and FPGADesignElements `Binary_to_Gray_Reflected.v` (cited in §3) — *"Each Gray code word differs by exactly 1 bit from the previous and the next code in sequence, which makes it behave nicely if a word may be read inaccurately from a mechanical indicator or a Clock Domain Crossing. Missing the changed bit means you are off by 1 step, not some variable number of steps as with a binary code."*
- [C] In an async FIFO, the binary read/write counter **must be converted to Gray *before* the source-domain flop whose output is the bus that crosses the domain**; the synchronized bus on the destination side must be the *Gray* value, not the binary value re-encoded after the synchronizer. Cummings SNUG2002 SJ async FIFO (live URL above); positive example: verilog-axis declares `wr_ptr_gray_reg`/`rd_ptr_gray_reg` as the registers whose values feed the synchronizer chains, with the `bin2gray = b ^ (b >> 1)` conversion already collapsed into the register's combinational drive (`references/projects/verilog-axis/rtl/axis_async_fifo.v:195-227 @ 48ff7a7`).
- [C] In the destination domain of an async FIFO, **full** and **empty** are derived from the **local** pointer (Gray) and the **synchronized opposite** pointer (Gray), and the comparison uses the *Gray-coded* "full" and "empty" conditions — not a Gray→binary conversion followed by an arithmetic compare on the synchronized side. Cummings SNUG2002 SJ async FIFO (live URL above); the verilog-axis realization is *"full when first TWO MSBs do NOT match, but rest matches (gray code equivalent of first MSB different but rest same)"* — `references/projects/verilog-axis/rtl/axis_async_fifo.v:263-267 @ 48ff7a7`. The full empty/full derivation, depth sizing, and storage-primitive selection are deferred to [22-fifos-synchronous-and-asynchronous.md](22-fifos-synchronous-and-asynchronous.md).
- [V] During an MCP / word-synchronizer exchange, the payload register on the source side **must hold its value stable** from before the `req` (load-toggle) edge propagates into the synchronizer chain until after the `ack` (completion-toggle) edge has been observed back in the source domain; this is what makes the unsynchronized data crossing safe. FPGADesignElements `CDC_Word_Synchronizer.v:152-192 @ 2026-05-20` — the source latches `sending_handshake_data` into `sending_data_storage` on handshake-complete and only toggles `start_async_handshake` *after* the latch — and verilogpro CDC part 2 (`references/raw/verilogpro/cdc_part2.html @ 2026-05-20`).
- [V] Choose **async FIFO over MCP** when the producer's average rate approaches the consumer's rate (buffering smooths the rate mismatch) or when the latency budget cannot absorb the MCP's round-trip; choose **MCP over async FIFO** when transfers are rare, the payload is wide, and a multi-kbit dual-clock memory would be wasteful. Direct rate-comparison rationale from verilogpro CDC part 2 (`references/raw/verilogpro/cdc_part2.html @ 2026-05-20`): *"to use this circuit, you must be certain that the input data only needs to be synchronized not more than once every three destination clock cycles. If you are unsure, then a more advanced synchronization circuit like the synchronizer with feedback acknowledgement or Dual-Clock Asynchronous FIFO should be used."* The Cyclone-V resource trade is [I] from [22-fifos-synchronous-and-asynchronous.md](22-fifos-synchronous-and-asynchronous.md) (M10K cost of a small-payload async FIFO) and [30-memory-inference-cyclone-v.md](30-memory-inference-cyclone-v.md).
- [I] A hand-rolled **binary** counter used as an async FIFO read or write pointer breaks under multi-bit-transition sampling and is the most common reason a custom async FIFO appears to "lose entries" only at fast clocks or specific clock ratios — *replace it with a Gray counter (or a binary counter followed by `bin ^ (bin >> 1)` on the register that crosses)*. Inferred from Cummings SNUG2002 SJ (live URL above; the paper's principal teaching) chained with the §2 anti-rule against bit-by-bit multi-bit sync; see §7-#21 for the full anti-pattern entry.

## 3. Constructs / signals / API reference

This section enumerates the three multi-bit-CDC primitives the consuming agent will instantiate: the Gray converter (combinational), the MCP / word synchronizer (handshake), and the Gray-pointer crossing inside an async FIFO. The §3.4 table contrasts the three patterns side-by-side.

### 3.1 Gray converter (`bin ^ (bin >> 1)`)

```verilog
// references/projects/FPGADesignElements/Binary_to_Gray_Reflected.v:38-75 @ 2026-05-20
module Binary_to_Gray_Reflected
#(
    parameter WORD_WIDTH = 0
)
(
    input  wire [WORD_WIDTH-1:0]  binary_in,
    output reg  [WORD_WIDTH-1:0]  gray_out
);

    localparam ZERO = {WORD_WIDTH{1'b0}};

    initial begin
        gray_out = ZERO;
    end

    function [WORD_WIDTH-1:0] binary_to_gray
    (
        input [WORD_WIDTH-1:0] binary
    );
        integer i;
        reg [WORD_WIDTH-1:0] gray;

        begin
            for(i=0; i < WORD_WIDTH-1; i=i+1) begin
                gray[i] = binary[i] ^ binary[i+1];
            end

            gray[WORD_WIDTH-1] = binary[WORD_WIDTH-1];

            binary_to_gray = gray;
        end
    endfunction

    always@(*) begin
        gray_out = binary_to_gray(binary_in);
    end

endmodule
```

This is the reflected-binary Gray encoding; the closed-form `gray = bin ^ (bin >> 1)` (with the top bit copied through) gives identical bits. The verilog-axis async FIFO uses the closed form directly: `bin2gray = b ^ (b >> 1)` (`references/projects/verilog-axis/rtl/axis_async_fifo.v:195-197 @ 48ff7a7`). [O] Both styles are equivalent on Cyclone V — synthesis collapses the loop into the same XOR network.

### 3.2 Gray-pointer crossing inside an async FIFO

This is the canonical async-FIFO pointer crossing: a binary counter on the write side, a combinational Gray conversion, a register stage on the write side whose output is the bus that crosses, a 2FF chain on the read side, and the read-side empty/full comparison against the local Gray pointer.

```verilog
// references/projects/verilog-axis/rtl/axis_async_fifo.v:195-227 @ 48ff7a7
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
```

And the read-side empty/full derivation in the *Gray* domain:

```verilog
// references/projects/verilog-axis/rtl/axis_async_fifo.v:263-267 @ 48ff7a7
// full when first TWO MSBs do NOT match, but rest matches
// (gray code equivalent of first MSB different but rest same)
wire full = wr_ptr_gray_reg == (rd_ptr_gray_sync2_reg ^ {2'b11, {ADDR_WIDTH-1{1'b0}}});
// empty when pointers match exactly
wire empty = FRAME_FIFO ? (rd_ptr_reg == wr_ptr_commit_sync_reg) : (rd_ptr_gray_reg == wr_ptr_gray_sync2_reg);
```

[O] Verilog-axis tags each synchronizer register with `(* SHREG_EXTRACT = "NO" *)` to keep synthesis from packing the chain into a shift-register primitive (which would defeat the metastability resolution). On Cyclone V the equivalent is the `altera_attribute` `-name SYNCHRONIZER_IDENTIFICATION FORCED` or the `(* preserve *)` register attribute — see [23-cdc-single-bit.md](23-cdc-single-bit.md) for the Cyclone V incantation and the synthesizer-identification mechanism. Full empty/full derivation, depth sizing, and storage-primitive choice live in [22-fifos-synchronous-and-asynchronous.md](22-fifos-synchronous-and-asynchronous.md).

### 3.3 MCP / word synchronizer (handshake-mediated payload crossing)

The MCP / word synchronizer takes a payload word in the source domain, latches it on the source side, signals "new data" by toggling a single bit into the destination domain through a 2FF chain, and returns a completion toggle back through another 2FF chain to release the source side for the next word. The payload bus itself crosses **unsynchronized**.

```verilog
// references/projects/FPGADesignElements/CDC_Word_Synchronizer.v:96-117 @ 2026-05-20
module CDC_Word_Synchronizer
#(
    parameter WORD_WIDTH                = 0,
    parameter EXTRA_CDC_DEPTH           = 0,
    parameter OUTPUT_BUFFER_TYPE        = "", // "HALF", "SKID", "FIFO"
    parameter OUTPUT_BUFFER_CIRCULAR    = 0,  // non-zero to enable
    parameter FIFO_BUFFER_DEPTH         = 0,  // Only for "FIFO"
    parameter FIFO_BUFFER_RAMSTYLE      = ""  // Only for "FIFO"
)
(
    input   wire                        sending_clock,
    input   wire                        sending_clear,
    input   wire    [WORD_WIDTH-1:0]    sending_data,
    input   wire                        sending_valid,
    output  wire                        sending_ready,

    input   wire                        receiving_clock,
    input   wire                        receiving_clear,
    output  wire    [WORD_WIDTH-1:0]    receiving_data,
    output  wire                        receiving_valid,
    input   wire                        receiving_ready
);
```

The source-side latch and load-toggle (the part that holds the payload stable for the destination's settling window):

```verilog
// references/projects/FPGADesignElements/CDC_Word_Synchronizer.v:152-208 @ 2026-05-20
// Then latch the data when the sending handshake completes.

    wire [WORD_WIDTH-1:0]   sending_handshake_data_latched;

    Register
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .RESET_VALUE    (WORD_ZERO)
    )
    sending_data_storage
    (
        .clock          (sending_clock),
        .clock_enable   (sending_handshake_complete),
        .clear          (sending_clear),
        .data_in        (sending_handshake_data),
        .data_out       (sending_handshake_data_latched)
    );

// Convert the completion of the sending handshake into a level toggle, which
// initiates a 2-phase asynchronous handshake. This level does not toggle
// again until the completion of the next sending handshake, which since it
// can only happen after the receiving handshake completes, guarantees the
// level stays constant long enough to pass through CDC, regardless of
// relative clock frequency.

    wire sending_handshake_toggle;

    Register_Toggle
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    start_async_handshake
    (
        .clock          (sending_clock),
        .clock_enable   (1'b1),
        .clear          (sending_clear),
        .toggle         (sending_handshake_complete),
        .data_in        (sending_handshake_toggle),
        .data_out       (sending_handshake_toggle)
    );

// Then we synchronize the start of the 2-phase asynchronous handshake into
// the receiving clock domain.

    wire sending_handshake_synced;

    CDC_Bit_Synchronizer
    #(
        .EXTRA_DEPTH        (EXTRA_CDC_DEPTH)  // Must be 0 or greater
    )
    into_receiving
    (
        .receiving_clock    (receiving_clock),
        .bit_in             (sending_handshake_toggle),
        .bit_out            (sending_handshake_synced)
    );
```

Note in the excerpt above that the payload latch (`sending_data_storage`) is clock-enabled by the *same* `sending_handshake_complete` event that toggles `sending_handshake_toggle` — this guarantees the latched payload is stable from before the destination 2FF chain begins to settle. [O] The author's prose explicitly states the invariant: *"this level does not toggle again until the completion of the next sending handshake, which since it can only happen after the receiving handshake completes, guarantees the level stays constant long enough to pass through CDC, regardless of relative clock frequency."* (FPGADesignElements `CDC_Word_Synchronizer.v:170-176 @ 2026-05-20`.)

### 3.4 The three patterns side-by-side

| Pattern | When to use | Latency (source→dest) | Throughput | Source-side complexity | Dest-side complexity | Storage cost |
|---|---|---|---|---|---|---|
| **Dual-clock async FIFO** with Gray pointers ([C]) | High-rate or bursty streaming; producer and consumer rates close to each other; need to buffer through rate mismatch | First word: pointer-sync latency (≈ 2–3 dest cycles) + memory read latency; subsequent words: 1 dest cycle each after the first | Up to one transfer per dest clock cycle, sustained | Binary counter + Gray converter + register stage + dual-clock RAM port | 2FF chain on incoming Gray pointer + dual-clock RAM port + empty/full compare in Gray | One M10K (or MLAB for tiny depths) per FIFO instance |
| **MCP / word synchronizer** ([C]) | Occasional words held stable; configuration registers, request/response, infrequent commands; no buffering needed | ≈ 5–8 *sending* clock cycles for the full 2-phase round-trip with roughly-equal clocks (FPGADesignElements `CDC_Word_Synchronizer.v:80-86 @ 2026-05-20`) | At most one transfer per ≈ 5–8 *sending* clock periods; collapses under high producer rate | Payload latch + toggle register + 2FF chain (ack return) | 2FF chain (req) + edge-detect + capture register + 2FF chain (ack out) | Two register-widths (latch + payload-out); no RAM |
| **Gray-coded counter, sampled raw** ([C]) | Destination needs to *observe* a count that lives in the source domain (free-running cycle counter, frame-counter snapshot) with no handshake; sample is allowed to be ±1 stale | 2 dest clocks for the sync chain; the sample itself can be any phase | Sample-on-demand; not a transfer rate | Binary counter + Gray converter on the register that crosses | 2FF chain per pointer bit + optional Gray→binary on the destination side | Counter-width register only |

Use one of these three. Anything else — and in particular, "I'll just sync each data bit with a 2FF chain" — is the anti-rule of §2 and the §7-#19 anti-pattern below.

## 4. Sequencing & timing

### 4.1 MCP / word synchronizer — 2-phase exchange

Below: the producer writes a fresh payload, fires the load-toggle, the destination 2FF chain settles, the destination captures the (still-stable) payload, fires the completion-toggle, and the source 2FF chain settles to release the producer.

```
sending_clock      ___|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
sending_data       XXXXX==========D0========================================== (held stable for full RT)
sending_handshake_  __|‾|_______________________________________________________ (1-cycle pulse on src)
   complete
sending_handshake_  ____|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾|________________________ (toggles on complete)
   toggle

receiving_clock    ___|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|
sending_handshake_  __________??____|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾|_____________________ (2FF settles, then level)
   synced
sending_handshake_  ______________________|‾‾|________________________________ (1-cycle pulse on rising edge)
   data_latched_valid
receiving_data     XXXXXXXXXXXXXXXXXXXXXX===D0=================================== (captured here)

receiving_handshake_____________________________|‾|________________________ (downstream handshake completes)
   complete
receiving_handshake_______________________________|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾ (toggles back)
   toggle

receiving_handshake__________________________________??____|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾ (2FF settles on src side)
   synced
accept_next_word    ________________________________________|‾|______________ (src is free to advance payload)
```

Total round-trip with roughly-equal clocks is ≈ 5–8 sending clock cycles (FPGADesignElements `CDC_Word_Synchronizer.v:80-86 @ 2026-05-20`). The payload bus crosses **unsynchronized** but is held stable from before `sending_handshake_toggle` flips until after `receiving_handshake_synced` rises in the source domain — that hold is what makes the unsynchronized data crossing safe.

### 4.2 Async FIFO pointer crossing

```
input_clock        ___|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
wr_ptr_reg         ==K==K+1=K+2==K+3==K+4=K+5=K+6==K+7========= (binary increment, may flip many bits)
wr_ptr_gray_reg    ==G(K)=G(K+1)=G(K+2)=G(K+3)=G(K+4)=G(K+5)=== (Gray; exactly 1 bit changes per step)

output_clock         _|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|__|‾‾|_
wr_ptr_gray_sync1   ==stale==?==G(K+1)===G(K+3)====G(K+5)====== (sample point: 1st flop, may be metastable)
wr_ptr_gray_sync2   ==stale=====G(K)=====G(K+1)===G(K+3)====== (2nd flop, settled, valid Gray code)

empty (Gray comp)   _|‾‾|_____|______________________________ (clears when sync2 != rd_ptr_gray)
```

Because the source increments Gray (one-bit-per-step), every sample at `wr_ptr_gray_sync1` is at most one Gray step away from "current" — never a mid-transition phantom value. The 2FF chain handles the metastability of that single transitioning bit. The destination's empty/full compare uses the *Gray* value directly (see §3.2 excerpt).

### 4.3 The failure mode of bit-by-bit synchronization (what §2 forbids)

Consider a 4-bit value transitioning from `4'b0111` (= 7) to `4'b1000` (= 8). All four bits flip on the same source-domain edge. With independent 2FF chains on each bit:

```
source bus     0111 ───►───► 1000  (one increment, four bits flip simultaneously)

bit[3] sync:   0 ......... 0 . 1 (settled at t+2)
bit[2] sync:   1 ........... 0 . (settled at t+3 — different chain, different timing)
bit[1] sync:   1 ........ 0 ... (settled at t+2)
bit[0] sync:   1 .. 0 ......... (settled at t+1 — fastest chain)

what destination sees, sampled at the wrong cycle: 0110 (= 6) or 1111 (= 15) or 1100 (= 12) or 0000 (= 0)
                                                   ^^^^                       ^^^^
                                  none of these is a value the source ever produced
```

Each bit's metastability resolves on its own timeline; the destination's *combination* of those independently-settling bits forms an invalid word the source never emitted. The 2FF synchronizer is correct **for one bit**; the multi-bit problem is not that each bit's metastability is more dangerous — it's that the combination of independently-settling bits is what produces the phantom word. **Gray code reduces this to "at most one bit transitions per source step,"** so the destination either samples the old value or the new value — never a phantom. **An MCP handshake achieves the same safety by not sampling the data bus until a synchronized control bit declares it stable.** verilogpro CDC part 2 (`references/raw/verilogpro/cdc_part2.html @ 2026-05-20`) and Cummings SNUG2008 CDC (live URL above).

## 5. Minimal working pattern

A copy-pasteable wrapper that moves an 8-bit configuration word from a 50 MHz domain to a 100 MHz domain, instantiating the FPGADesignElements `CDC_Word_Synchronizer` (the MCP pattern). Producer writes the word once; the consumer sees it after the 2-phase round-trip settles.

```systemverilog
// references/projects/FPGADesignElements/CDC_Word_Synchronizer.v:96-117 @ 2026-05-20
// (Wrapper composed for this doc; instance is verbatim from cited file.)
`default_nettype none

module cfg_word_50_to_100
(
    input  wire        clk_50,           // 50 MHz producer domain
    input  wire        rst_50,           // sync to clk_50
    input  wire [7:0]  cfg_word_in,      // payload from producer
    input  wire        cfg_word_write,   // 1-cycle write pulse in clk_50

    input  wire        clk_100,          // 100 MHz consumer domain
    input  wire        rst_100,          // sync to clk_100
    output wire [7:0]  cfg_word_out,     // payload in clk_100
    output wire        cfg_word_valid_100// 1-cycle pulse when new word arrives
);

    wire sending_ready_unused;

    CDC_Word_Synchronizer
    #(
        .WORD_WIDTH             (8),
        .EXTRA_CDC_DEPTH        (0),
        .OUTPUT_BUFFER_TYPE     ("HALF"),  // see CDC_Word_Synchronizer.v:36-39 @ 2026-05-20
        .OUTPUT_BUFFER_CIRCULAR (0),
        .FIFO_BUFFER_DEPTH      (0),
        .FIFO_BUFFER_RAMSTYLE   ("")
    ) u_cfg_sync (
        .sending_clock    (clk_50),
        .sending_clear    (rst_50),
        .sending_data     (cfg_word_in),
        .sending_valid    (cfg_word_write),
        .sending_ready    (sending_ready_unused),    // tie if no backpressure desired

        .receiving_clock  (clk_100),
        .receiving_clear  (rst_100),
        .receiving_data   (cfg_word_out),
        .receiving_valid  (cfg_word_valid_100),
        .receiving_ready  (cfg_word_valid_100)       // self-loop = always accept
    );

endmodule
```

The corresponding SDC declaration for the asynchronous clock pair lives in the project's `.sdc`:

```tcl
# Cross-ref: SDC essentials in 40-timing-closure-and-sdc.md
create_clock -name clk_50  -period 20.000 [get_ports clk_50]
create_clock -name clk_100 -period 10.000 [get_ports clk_100]
set_clock_groups -asynchronous -group {clk_50} -group {clk_100}
```

[I] composite — the wrapper is composed for this doc; the `CDC_Word_Synchronizer` instantiation is verbatim from the cited file, and the parameter shape (`WORD_WIDTH`, `OUTPUT_BUFFER_TYPE`, `EXTRA_CDC_DEPTH`) matches the module's declared interface (`references/projects/FPGADesignElements/CDC_Word_Synchronizer.v:96-117 @ 2026-05-20`). Full SDC discussion of asynchronous clock groups is in [40-timing-closure-and-sdc.md](40-timing-closure-and-sdc.md); the single-bit-CDC mechanics underneath this module are in [23-cdc-single-bit.md](23-cdc-single-bit.md).

## 6. Common variations across implementations

- [O] **verilog-axis async FIFO — direct Gray + 2FF** (`references/projects/verilog-axis/rtl/axis_async_fifo.v:195-227,263-267 @ 48ff7a7`). The classical Cummings-2002 pattern: binary counter, `b ^ (b >> 1)` combinational Gray, register stage whose output is the bus that crosses, plain 2FF chain on the destination side tagged `(* SHREG_EXTRACT = "NO" *)`, empty/full compared in Gray. This is the canonical async-FIFO pointer crossing and the one to mirror unless you have a specific reason not to.
- [O] **FPGADesignElements CDC_FIFO_Buffer — MCP-based pointer crossing** (`references/projects/FPGADesignElements/CDC_FIFO_Buffer.v:280-363 @ 2026-05-20`). An *alternative* async-FIFO architecture that ships its write and read addresses across the clock boundary not as Gray pointers through a 2FF chain, but as **binary addresses (plus a 1-bit wrap-around flag)** through two `CDC_Word_Synchronizer` instances — i.e., an MCP handshake per pointer crossing. The empty/full check then runs against the synchronized binary addresses. The author's prose explains the trade: *"It takes a few cycles to do the CDC word transfer, so when comparing the local read or write address with the synchronized counterpart from the other clock domain, we are comparing to a slightly stale version, lagging behind the actual value. However, since the addresses never pass eachother, this does not cause any corruption."* (`CDC_FIFO_Buffer.v:295-301 @ 2026-05-20`). This trades the simple constant-latency Gray-pointer crossing for the MCP handshake's variable 5–8-cycle round-trip per pointer update; the upside is that *any* depth (not only powers-of-two) is supported and the comparison hardware on each side stays as a plain binary comparator.
- [O] **FPGADesignElements word synchronizer (4-phase with explicit handshake)** (`references/projects/FPGADesignElements/CDC_Word_Synchronizer.v:96-318 @ 2026-05-20`). The module exposes a full `ready`/`valid` handshake on both sides (see §3.3), implements internally a 2-phase toggle exchange, and offers configurable output buffering ("HALF" / "SKID" / "FIFO" — `CDC_Word_Synchronizer.v:36-50 @ 2026-05-20`). Choose "HALF" when sampling a slowly-changing counter (forces sender's rate to match receiver's); "SKID" when both ends can usefully overlap; "FIFO" when the downstream takes data in bursts.
- [O] **2-phase MCP variant — toggle, not pulse** (verilogpro CDC part 2, `references/raw/verilogpro/cdc_part2.html @ 2026-05-20`). The producer *toggles* `req` once per transfer rather than *pulsing* it; the destination edge-detects after sync. Lower latency than the 4-phase req/ack flavor — the FPGADesignElements `CDC_Word_Synchronizer` is itself built on this pattern (see the prose in `CDC_Word_Synchronizer.v:14-19 @ 2026-05-20`: *"This module is closely related to the 2-phase Pulse Synchronizer."*). The correctness argument is more subtle because there is no idle level to return to between transfers.
- [V] **Quasi-static "configuration register" pattern**. When a value is written once at boot and held forever (e.g., a strap register sampled into a configuration bus), a single 2FF chain per bit is *acceptable* because the bus is stable for thousands of destination cycles before any consumer samples it, and the destination has time to allow all bits' chains to settle before observing. **Distinguish carefully from the §2 anti-rule** — the safety here comes from the producer's stable-hold time, not from the sync chain itself. The §2 contract still applies whenever the value can *change* relative to the destination's sampling cadence; the moment it does, this pattern is wrong and the consumer needs an MCP or a FIFO. verilogpro CDC part 2 names the exception (`references/raw/verilogpro/cdc_part2.html @ 2026-05-20`): *"You may get away with using a simple two flip-flop synchronizer if you know there will be sufficient time for the signal to settle before reading the synchronized value (like a relatively static encoded status signal). But it's still not the best practice."* — and even there, the source calls it "not the best practice." Prefer MCP for any value the source-side software or hardware can rewrite during normal operation.
- [O] **Bus-narrowing before crossing** — collapse two or more semantically-equivalent signals into one (e.g., a single "begin" pulse rather than separate "begin-A" and "begin-B" pulses) so the destination only has to synchronize one bit and reconstruct the second event downstream. verilogpro CDC part 2 (`references/raw/verilogpro/cdc_part2.html @ 2026-05-20`) names this as *"Multi-bit signal consolidation … it's always good to reduce as much as possible the number of signals that need to cross a clock domain crossing (CDC)."* Cross-ref [16-resource-and-state-economy.md](16-resource-and-state-economy.md) for the resource-economy framing.

## 7. Anti-patterns (mistakes that compile but break)

This doc is the primary home for anti-pattern **#19** (bit-by-bit multi-bit CDC) and anti-pattern **#21** (hand-rolled binary counter as CDC pointer); both have full entries below.

### #19 — Bit-by-bit 2FF synchronization of a changing multi-bit bus *(primary home — full entry)*

- **Symptom:** the destination occasionally observes a multi-bit value that *the source never emitted* — an arithmetic counter appears to skip backwards, an encoded state appears as an undefined state, or a multi-bit control word loads the wrong configuration. Failure rate scales with the bus's toggle rate (more transitions = more chances) and with the source/destination clock ratio (specific ratios maximize the phase coverage that exposes the bug). Functional simulation passes because most simulators do not model metastability or per-bit settling skew.
- **Cause:** N independent 2FF synchronizer chains, one per data bit. Each bit's metastability resolves on its own timeline, and the destination's *combination* of those independently-resolved bits forms a phantom word that was never present on the source side. Equivalently: there is no synchronized *control* bit telling the destination when the data bus is stable; the destination is free to sample mid-transition.
- **Fix:** pick one of the three §3 patterns: (a) **async FIFO** if the value changes frequently or in bursts; (b) **MCP / word synchronizer** if the value changes occasionally and can be held stable across the synchronizer round-trip; (c) **Gray-coded counter** if the destination is sampling a count without a handshake. *Never* a bank of independent 2FF chains on the data bits.
- **Citation:** Cummings SNUG2008 CDC paper, `http://www.sunburst-design.com/papers/CummingsSNUG2008Boston_CDC.pdf` (live URL, no local capture); verilogpro CDC part 2, `references/raw/verilogpro/cdc_part2.html @ 2026-05-20` — *"if they are synchronized individually, they cannot be guaranteed to arrive in the destination clock domain on the same clock edge … therefore synchronizing individual bits of a multi-bit signal is not sufficient!"*.

### #21 — Hand-rolled binary counter used as an async FIFO pointer *(primary home — full entry)*

- **Symptom:** a custom async FIFO appears to "lose" or "duplicate" entries; empty/full flags become spuriously asserted or deasserted; the bug appears *only* at high clocks, at specific clock-frequency ratios, or under sustained throughput — and disappears under single-step debug or slow producer rates. Functional simulation often passes.
- **Cause:** the read or write pointer is incremented as a plain binary counter and the binary value crosses the clock boundary through a 2FF chain (per bit) into the opposite domain. On the cycle a binary increment flips multiple bits (e.g., `8'b00111111 → 8'b01000000` flips 7 bits at once), the destination's 2FF chains settle each bit independently, and the synchronized pointer value briefly takes on a phantom intermediate (e.g., `8'b00000000`, `8'b01111111`, `8'b01100000`, etc.). The downstream empty/full comparator sees that phantom as a real pointer position and either falsely declares empty (so the consumer stalls or stops reading) or falsely declares the FIFO non-full (so the producer overwrites unread data).
- **Fix:** **Gray-code the pointer**: feed `wr_ptr_gray = wr_ptr_bin ^ (wr_ptr_bin >> 1)` into the register stage whose output crosses the boundary; do the conversion **before** the source-side register, not after the synchronizer. The destination's 2FF chain then sees at most one bit transitioning per source increment, and the synchronized value is either the old or the new pointer — never a phantom. Compare empty/full in the *Gray* domain (§3.2 shows the verilog-axis comparator constants). If a non-power-of-two depth is required, the alternative is the MCP-based pointer crossing of FPGADesignElements `CDC_FIFO_Buffer.v` (§6) which moves binary addresses safely through an MCP handshake instead of relying on Gray-code's one-bit-per-step property.
- **Citation:** Cummings SNUG 2002 SJ async FIFO paper, `http://www.sunburst-design.com/papers/CummingsSNUG2002SJ_FIFO1.pdf` (live URL, no local capture) — the paper's principal teaching is exactly this construction; positive examples in archive are `references/projects/verilog-axis/rtl/axis_async_fifo.v:195-227,263-267 @ 48ff7a7`. The FPGADesignElements MCP alternative is documented in `references/projects/FPGADesignElements/CDC_FIFO_Buffer.v:280-363 @ 2026-05-20`.

### MCP without payload-stable hold

- **Symptom:** the destination intermittently captures the *next* payload (one transfer late), or a partially-updated payload mixing bits from two consecutive writes. Looks like a one-cycle or half-word offset bug.
- **Cause:** the producer modifies the payload register before the destination has captured it — i.e., before the source's `ack`/return-toggle has been observed. The unsynchronized payload bus then changes mid-capture and the destination samples a stitched-together word.
- **Fix:** hold the payload register stable from before the load-toggle propagates into the destination synchronizer until after the return-toggle has settled in the source domain. The FPGADesignElements `CDC_Word_Synchronizer` enforces this structurally by latching `sending_data` into `sending_data_storage` on `sending_handshake_complete` and only releasing for the next transfer when `accept_next_word` pulses on the source side (`references/projects/FPGADesignElements/CDC_Word_Synchronizer.v:152-168,300-315 @ 2026-05-20`). When rolling your own MCP, the producer's state machine must not advance the payload until it observes the ack — and the ack must come from a 2FF chain in the source domain, not from a same-clock-domain assumption.
- **Citation:** verilogpro CDC part 2 (`references/raw/verilogpro/cdc_part2.html @ 2026-05-20`) — the prose specifies *"the input data has to be held until the synchronization pulse loads the data in the destination clock domain"* — and FPGADesignElements `CDC_Word_Synchronizer.v:170-176 @ 2026-05-20` for the structural enforcement.

### MCP used for high-rate data

- **Symptom:** the producer stalls more than it transmits; effective throughput collapses to roughly one transfer every 5–8 sending clock cycles regardless of the bus width or the destination clock rate. CPU-style profiling shows the producer is `ready`-blocked the majority of the time.
- **Cause:** the MCP / word synchronizer's round-trip latency is structurally bounded below by the 2-phase 2FF synchronization in each direction (≈ 5–8 sending clock cycles with roughly-equal clocks per FPGADesignElements `CDC_Word_Synchronizer.v:80-86 @ 2026-05-20`). For occasional words that's invisible; for a streaming datapath it's the throughput.
- **Fix:** use a **dual-clock async FIFO** instead. After the initial pointer-sync latency, the FIFO sustains one transfer per destination clock cycle. The MCP pattern is only correct when the *transfer rate* is well below the round-trip rate — verilogpro CDC part 2 (`references/raw/verilogpro/cdc_part2.html @ 2026-05-20`): *"you must be certain that the input data only needs to be synchronized not more than once every three destination clock cycles. If you are unsure, then … the synchronizer with feedback acknowledgement or Dual-Clock Asynchronous FIFO should be used."*
- **Citation:** verilogpro CDC part 2 above; FPGADesignElements `CDC_Word_Synchronizer.v:58-91 @ 2026-05-20` for the latency analysis.

### Async FIFO with empty/full computed against an un-Gray-coded synchronized pointer

- **Symptom:** the FIFO works at low throughput and fails — overflow, underflow, false empty/full — under sustained throughput or specific clock ratios.
- **Cause:** the pointer is correctly Gray-coded and synchronized, but the destination's empty/full comparator is written as if the synchronized pointer were binary (e.g., arithmetic compare on the synchronized side), or the *local* pointer in the empty/full compare is the binary version rather than the Gray version. Either way the compare is operating on inconsistent encodings.
- **Fix:** keep the synchronized opposite-domain pointer in *Gray* form and compare *Gray* against *Gray*. The verilog-axis pattern (§3.2) shows the right constants: `full` is `wr_ptr_gray_reg == (rd_ptr_gray_sync2_reg ^ {2'b11, {ADDR_WIDTH-1{1'b0}}})` — note the *two* top bits flipped, which is the Gray-code equivalent of "binary MSB different, rest same." If you need binary on the local side for downstream logic, derive it from the local binary counter, not by Gray→binary-converting the synchronized pointer. Full empty/full derivation is in [22-fifos-synchronous-and-asynchronous.md](22-fifos-synchronous-and-asynchronous.md).
- **Citation:** Cummings SNUG 2002 SJ (live URL above); `references/projects/verilog-axis/rtl/axis_async_fifo.v:263-267 @ 48ff7a7`.

### Multi-bit "defensive" 2FF chain on a same-clock-domain signal

- **Symptom:** consumes registers; sometimes a Quartus report flags it as a synchronizer of a same-clock signal; otherwise silent.
- **Cause:** the author conflated "defense against metastability" with "defense against logic bugs"; both endpoints are on the *same* clock, so there is no metastability and no need for a synchronizer chain. The chain adds latency, area, and confusion.
- **Fix:** remove the chain. A signal that lives entirely on one clock needs no 2FF.
- **Citation:** primary home is [16-resource-and-state-economy.md](16-resource-and-state-economy.md) (anti-pattern #20); the multi-bit version is mentioned here only as a cross-reference. The single-bit form is also covered in [23-cdc-single-bit.md](23-cdc-single-bit.md).

## 8. Verification

- **Inspect the synthesis / fitter reports.** For an async FIFO, the Gray pointer should show as a recognized synchronizer chain (typically with an MTBF estimate from Quartus's metastability analyzer) on each of the pointer bits crossing the boundary. For an MCP / word synchronizer, the *control* bits (`req`/`ack` toggles) should show as recognized synchronizer chains; the **payload bus** should *not* show synchronizer chains on its bits — it crosses unsynchronized by design. Full report-reading procedure is in [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md).
- **Do not trust functional simulation alone.** Standard async-clock simulation does not model metastability or per-bit settling skew, so a bit-by-bit-sync bug will *pass* simulation even though it will fail in silicon. Use a CDC lint tool if one is available; otherwise rely on architectural review against the rules in §2 and the anti-patterns in §7.
- **Stress test the clock ratio.** Run the consuming module at a clock ratio chosen to maximize phase coverage (e.g., source 27 MHz, destination 50 MHz — a non-integer ratio with no simple alignment). Inject payload patterns that maximize Hamming-distance per transition (e.g., toggle the full bus every source cycle). Bit-by-bit synchronization bugs surface under exactly this stress; clean patterns (FIFO, MCP) remain stable.
- **Confirm Gray-pointer recognition.** Quartus should report the synchronizer chain on each pointer bit as a recognized synchronizer with a calculated MTBF; if it reports the chain as `RAM` or `shift register` instead, synthesis has packed the chain into a shift-register primitive — re-add the equivalent of verilog-axis's `(* SHREG_EXTRACT = "NO" *)` (on Cyclone V via `altera_attribute`, `(* preserve *)`, or `(* dont_merge *)`, as established in [23-cdc-single-bit.md](23-cdc-single-bit.md)) and recompile.
- **Document the pattern in the module header.** Every module that performs a multi-bit CDC must declare which of the three patterns it uses, in a header comment: e.g., *"Async FIFO crossing from `clk_in` to `clk_out`, Gray-coded depth-N pointers, M10K storage"*, or *"MCP word synchronizer, 8-bit payload, `clk_50 → clk_100`, payload held stable for the full handshake round-trip"*, or *"Gray-coded counter sampled raw into `clk_dst`, ±1 stale tolerated"*. The bringup checklist in [91-core-bringup-checklist.md](91-core-bringup-checklist.md) reads these headers as part of its gate review.

## 9. Provenance footer

- `http://www.sunburst-design.com/papers/CummingsSNUG2008Boston_CDC.pdf` — used for §2 (multi-bit anti-rule), §4.3 (failure-mode framing), §7-#19 — **live URL only; no local capture**; local archive copies (`references/raw/methodology/CummingsSNUG2008Boston_CDC_fetch_failed.html` and `references/raw/methodology/CummingsSNUG2008Boston_CDC_sunburstdesign_fetch_failed.html`) are fetch-failure stubs.
- `http://www.sunburst-design.com/papers/CummingsSNUG2002SJ_FIFO1.pdf` — used for §2 (Gray-pointer rules, async-FIFO empty/full-in-Gray), §7-#21 — **live URL only; no local capture**; local archive copies (`references/raw/methodology/CummingsSNUG2002SJ_FIFO1_fetch_failed.html` and `references/raw/methodology/CummingsSNUG2002SJ_FIFO1_sunburstdesign_fetch_failed.html`) are fetch-failure stubs.
- `references/raw/verilogpro/cdc_part2.html @ 2026-05-20` — used for §2 (multi-bit anti-rule, MCP rule, FIFO-vs-MCP selection), §4.3, §6 (2-phase MCP variant, bus-narrowing, quasi-static exception), §7-#19, §7 (MCP-no-hold, MCP-for-high-rate).
- `references/raw/fpgacpu/cdc.html @ 2026-05-20` — supporting source for §1 / §3 framing ("pass the multi-bit value directly with a single synchronized valid"); the page's recommended further reading is the Cummings SNUG2008 paper cited above.
- `references/projects/FPGADesignElements/Binary_to_Gray_Reflected.v @ 2026-05-20` — used for §2 (Gray-code primitive), §3.1.
- `references/projects/FPGADesignElements/CDC_Word_Synchronizer.v @ 2026-05-20` — used for §2 (MCP rule, payload-stable rule), §3.3, §4.1, §5, §6 (FPGADesignElements 4-phase word synchronizer), §7 (MCP-no-hold, MCP-for-high-rate).
- `references/projects/FPGADesignElements/CDC_FIFO_Buffer.v @ 2026-05-20` — used for §6 (MCP-based async FIFO variant), §7-#21 (non-Gray alternative for non-power-of-two depths).
- `references/projects/verilog-axis/rtl/axis_async_fifo.v @ 48ff7a7` — used for §2 (Gray-conversion-before-crossing, Gray empty/full compare), §3.1 ([O] closed-form), §3.2 (canonical Gray-pointer pattern), §7-#21 (positive example), §7 (no-Gray-compare anti-pattern), §8.
- `references/MANIFEST.md` — used as the source of pinned commits and the fetch-failure status of both Cummings papers.
- `cyclone-v-hdl-bundle/22-fifos-synchronous-and-asynchronous.md @ 2026-05-19` — cross-ref for async FIFO architecture (storage, depth, empty/full derivation).
- `cyclone-v-hdl-bundle/23-cdc-single-bit.md @ 2026-05-19` — cross-ref for single-bit 2FF mechanics, synchronizer-recognition attributes, MTBF reporting.
- `cyclone-v-hdl-bundle/01-glossary.md:39-49 @ 2026-05-19` — definitions for metastability, 2FF synchronizer, MTBF, Gray code, async FIFO, MCP.
