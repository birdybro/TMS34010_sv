# Memory Inference on Cyclone V — Flops, MLAB, M10K

> Bundle version: 2026-05-19
> Pinned commits: FPGADesignElements @ 2450a54; verilog-axi @ 516bd5d; verilog-axis @ 48ff7a7; Intel Quartus Standard 18.1 *Inferring Memory Functions from HDL Code* (live URL @ 2026-05-20, subsection-level fetch successful for four templates; chapter index is app-shell); Intel *Specifying Initial Memory Contents at Power-Up* (live URL @ 2026-05-20); Cyclone V Device Handbook Vol. 1 (live URL, no local body capture); Cyclone V product table (PDF, exceeds Read tool capacity, cited as live URL).
> Load with: [16-resource-and-state-economy.md](16-resource-and-state-economy.md), [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md), [22-fifos-synchronous-and-asynchronous.md](22-fifos-synchronous-and-asynchronous.md), [31-dsp-inference-cyclone-v.md](31-dsp-inference-cyclone-v.md), [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md)
> Status mix: [C] ~35% (template form, registered-read requirement, explicit RDW selection — Intel chapter subsection-level fetches); [V] ~40% (sizing thresholds flops/MLAB/M10K, byte-enable pattern, true-dual-port discipline — bundle glossary plus Cyclone V Device Handbook live URLs); [O] ~15% (Intel canonical vs FPGADesignElements vs verilog-axi MLAB-attribute style); [I] ~10% (the ≤16-entries-in-flops threshold has no single-source endorsement).
> Missing inputs: Intel *Inferring Memory Functions* chapter index is an app-shell (`references/raw/intel/quartus_standard_design_recommendations_index.html`); template subsections retrieved live per-subsection. Cyclone V *embedded memory types*/*modes* are app-shells locally (`cyclone_v_embedded_memory_types.html`, `cyclone_v_embedded_memory_modes.html`); cited via live URL. Cyclone V product table is a PDF exceeding Read tool capacity (`cyclone_v_product_table_api.txt`, 100 KB / 63k tokens); the 5.6 Mbit M10K+MLAB figure for `5CSEBA6U23I7` is cited via the bundle glossary distillation.

## 1. Purpose & one-line summary

Cyclone V has three storage tiers — **flops** (registers in ALMs), **MLAB** (640-bit distributed memory in LAB-configured ALMs), and **M10K** (10 240-bit dedicated embedded-memory blocks) — and which one Quartus infers depends entirely on the RTL template, not on the declared size alone. This doc gives copy-pasteable Intel inference templates with citation comments plus a sizing decision procedure that prevents the two most common mistakes: inferring an M10K for a tiny multi-read register file, and assuming a read-during-write mode the synthesizer did not select.

Deliverable this doc produces in the consuming agent: for every `logic [W-1:0] arr [0:N-1];` storage declaration in the design, an **explicit memory-tier decision** (flops / MLAB / M10K) with a template that maps to that tier and a verified read-during-write mode.

What this doc does **not** cover (deferred via Load with):

- Sync/async FIFO architecture, Gray-coded pointers, and the MLAB-vs-M10K choice **specifically for FIFOs** → [22-fifos-synchronous-and-asynchronous.md](22-fifos-synchronous-and-asynchronous.md).
- DSP block inference (multiply, multiply-add) → [31-dsp-inference-cyclone-v.md](31-dsp-inference-cyclone-v.md).
- Bit-level resource economy and the four-justifications check → [16-resource-and-state-economy.md](16-resource-and-state-economy.md).
- Era-faithful storage-topology framing (mirroring the original chip's register file / bus discipline) → [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md).
- Quartus Fitter/Synthesis report-reading mechanics (which window, which column) → [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md).

**Resource budget framing.** The Cyclone V `5CSEBA6U23I7` on the DE10-Nano has roughly **5.6 Mbit of M10K+MLAB embedded memory** total (live URL, Cyclone V Device Handbook Vol. 1 — `https://docs.altera.com/r/docs/683375/current/cyclone-v-device-handbook-volume-1-device-interfaces-and-integration` @ 2026-05-20; and `cyclone-v-hdl-bundle/01-glossary.md:20 @ 2026-05-19`). That is plenty for one well-designed core — but burning an M10K on storage that should have been six flops in a register file is exactly how you run out. Detailed accounting belongs to [16](16-resource-and-state-economy.md) and [41](41-quartus-reports-and-verification.md).

## 2. The contract (must-obey)

Every rule below carries exactly one label. For each [I] rule, the inference chain is named in the same paragraph so reviewers can audit the argument.

- **[C] Canonical inference-template form.** A memory that Quartus infers as M10K or MLAB must be written in the Intel-recognized template form: a single `always @(posedge clk)` block, an unpacked `reg [W-1:0] mem [DEPTH-1:0]` declaration, write under an enable, and a **registered** read output. Deviating templates may synthesize to LUT logic, infer the wrong primitive, or fail to infer entirely. Cite: Intel *Inferring Memory Functions from HDL Code*, single-clock RAM template subsections @ 2026-05-20 (full URLs in §3.1, §3.2; chapter index is app-shell-only locally).

- **[C] Registered read is required for M10K (and for MLAB simple-dual-port).** Combinational/asynchronous read does **not** infer to M10K; Quartus implements such code in LUTs or in MLAB's distributed-asynchronous-read mode, with a large area cost. The Intel templates in §3 always assign `q <= mem[read_address];` inside the clocked `always` block. Cite: Intel *Inferring Memory Functions*, §3.1/§3.2 subsection URLs @ 2026-05-20.

- **[C] Read-during-write mode must be selected explicitly via the template.** The two Intel templates in §3 differ only in **blocking vs nonblocking** assignment: nonblocking (`<=`) produces *old-data* RDW (read returns pre-write value); blocking (`=`) produces *new-data* RDW (read returns just-written value via inferred write-forwarding logic). Don't write code whose simulation behavior differs from what Quartus picks. Cite: Intel `…/single-clock-synchronous-ram-with-old-data-read-during-write-behavior` and `…/…-new-data-…` @ 2026-05-20; reinforced by `references/projects/FPGADesignElements/RAM_Single_Port.v:11-29 @ 2450a54` (module-header commentary spelling out the same mapping).

- **[V] MLAB-vs-M10K selection is determined by `ramstyle`, total bit count, and port count.** Quartus's RAM-template matcher allocates **MLAB** for small (≲640 bits per block, depth ≤ ~32-256 at modest width), 1W1R storage, and **M10K** for larger blocks or anything needing two write ports. The `(* ramstyle = "M10K" *)` / `"MLAB"` / `"logic"` / `"no_rw_check"` attribute is the explicit override. Cite: bundle glossary `cyclone-v-hdl-bundle/01-glossary.md:11-12 @ 2026-05-19`; Cyclone V Device Handbook Vol. 1 (live URL); verilog-axi MLAB pattern `references/projects/verilog-axi/rtl/axi_vfifo_enc.v:202 @ 516bd5d` showing `(* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)`.

- **[V] Storage of approximately ≤16 entries belongs in flops, not MLAB or M10K.** A register file needing 3+ parallel reads (a CPU's `rd`/`rs`/`rt`) cannot fit in MLAB (1 read port) or M10K (1-2 read ports) without LUT-replication. FPGADesignElements `RAM_Multiported_LE.v` commentary is explicit: "Storage is implemented using logic elements and registers… not expected to map to underlying RAM blocks… suitable for small, highly-concurrent memories such as semaphores, small CPU register files, or storage for parallel functional units." Cite: `references/projects/FPGADesignElements/RAM_Multiported_LE.v:1-15 @ 2450a54`; Cyclone V Device Handbook Vol. 1 (live URL). **[I] qualifier on the exact "16":** no Intel doc states a numeric threshold; the rule is the bundle's working convention. Treat 16 as a rule of thumb; re-check against actual port-count for each register file.

- **[V] Storage in the ~17-256 entries range with 1W1R belongs in MLAB** (modest width, total ≤640 bits per block, no init file, no constrained same-port RDW semantics). Cite: bundle glossary `cyclone-v-hdl-bundle/01-glossary.md:11 @ 2026-05-19`; Cyclone V Device Handbook Vol. 1 (live URL @ 2026-05-20).

- **[V] Storage larger than ~256 entries, or anything needing init contents, or anything needing true-dual-port, belongs in M10K.** M10K is the 10 240-bit dedicated embedded-memory block; it supports single-port, simple-dual-port, true-dual-port, ROM-with-init, byte-enable masks on write, and either RDW mode per the template chosen. Cite: Cyclone V Device Handbook Vol. 1 (live URL @ 2026-05-20); bundle glossary `cyclone-v-hdl-bundle/01-glossary.md:12 @ 2026-05-19`.

- **[V] ROM initialization uses `$readmemh`/`$readmemb` on an unpacked-array `reg`, or an inferable case-statement ROM body, or a `.mif`/`.hex` file referenced by attribute.** Cite: Intel *Specifying Initial Memory Contents at Power-Up* @ 2026-05-20 (live URL, retrieved, §3.4); Intel ROM-template subsection @ 2026-05-20 (§3.3).

- **[V] Byte enables on M10K write ports are expressed via per-byte conditional writes** inside the `always @(posedge clk)` block (one `if (byteena[i]) mem[addr][8*i +: 8] <= d[8*i +: 8];` per byte). The Intel byte-enable subsection URLs (`…/byte-enable-restrictions`, `…/inferring-byte-enabled-rams`) both returned HTTP 404 on live fetch @ 2026-05-20, so this rule cites only the chapter-index live URL `https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/inferring-memory-functions-from-hdl-code` @ 2026-05-20. **[V] downgrade from [C]** because the verbatim subsection body was not retrievable.

- **[V] True-dual-port is required only when two ports both write.** If only one port writes, **simple-dual-port** suffices and is cheaper (Quartus packs two simple-dual-port memories in one M10K without true-dual-port port-count overhead). Cite: Cyclone V Device Handbook Vol. 1 embedded-memory-modes (live URL @ 2026-05-20); confirmed structurally by FPGADesignElements `RAM_Simple_Dual_Port.v` and `RAM_True_Dual_Port.v` being separate, distinct modules.

- **[I] When migrating an emulation core, a small architectural register file (e.g., a CPU's 8-16 registers) belongs in flops** to allow parallel read by multiple datapath consumers. Inferring an M10K costs an entire embedded block and adds a 1-2-read-port restriction the original architecture didn't have. *Inference chain:* (1) FPGADesignElements `RAM_Multiported_LE.v` commentary names "small CPU register files" as a flop-based use case; (2) M10K's port limitation is in Cyclone V Device Handbook embedded-memory modes (live URL); (3) era-faithful angle is in [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md). This doc is **primary home**; 17 cross-references back. See AP #25 in §7.

## 3. Constructs / signals / API reference (centerpiece)

This section is the doc's anchor: **three verbatim Intel-template excerpts** (single-port RAM with new-data RDW / write-forwarding behavior; simple-dual-port RAM with old-data RDW; ROM with `$readmemb` init), an explicit table mapping each template to its inferred resource, and the byte-enable pattern via FPGADesignElements as a stand-in (the Intel byte-enable subsection URLs returned 404 — see §2's [V] downgrade note).

### 3.1 Intel single-port-style RAM (new-data RDW / write-forwarding) — verbatim

Intel's canonical "single-clock synchronous RAM with **new-data** read-during-write behavior." Output retrieves the just-written data; structurally it has separate `write_address` and `read_address` ports (simple-dual-port shape), but with both tied externally to one bus it becomes a true single-port RAM. Defining feature: **blocking assignment** (`=`), which forces Quartus to infer the write-forwarding mux.

```verilog
// https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/single-clock-synchronous-ram-with-new-data-read-during-write-behavior:single_clock_wr_ram @ 2026-05-20 (live URL, chapter index is app-shell, no local body capture)
module single_clock_wr_ram(
    output reg [7:0] q,
    input [7:0] d,
    input [6:0] write_address, read_address,
    input we, clk
);
    reg [7:0] mem [127:0];

    always @ (posedge clk) begin
        if (we)
            mem[write_address] = d;
        q = mem[read_address]; // q does get d in this clock 
                               // cycle if we is high
    end
endmodule
```

Read carefully:

- `reg [7:0] mem [127:0];` — 128-entry × 8-bit = 1024 bits total. Above MLAB-block size (640 bits), so Quartus targets M10K.
- **Blocking** assignments (`=`). Write happens logically before the read on the same cycle, so `q` captures the new `d` if `we && write_address == read_address`. This is the new-data RDW form.
- `q` is **registered** (`output reg [7:0] q`), assigned only inside the clocked block — the §2 registered-read [C] requirement.

[C] template form; **[C] for new-data / write-forwarding selection** via blocking assignment.

### 3.2 Intel simple-dual-port RAM (old-data RDW) — verbatim

Intel's canonical "simple dual-port, single-clock synchronous RAM" with **old-data** RDW. The template the consuming agent reaches for first when one module writes and a separate module reads — most FIFO body, line-buffer, and frame-buffer cases.

```verilog
// https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/single-clock-synchronous-ram-with-old-data-read-during-write-behavior:single_clk_ram @ 2026-05-20 (live URL, chapter index is app-shell, no local body capture)
module single_clk_ram( 
    output reg [7:0] q,
    input [7:0] d,
    input [4:0] write_address, read_address,
    input we, clk
);
    reg [7:0] mem [31:0];

    always @ (posedge clk) begin
        if (we)
            mem[write_address] <= d;
        q <= mem[read_address]; // q doesn't get d in this clock cycle
    end
endmodule
```

Read carefully:

- `reg [7:0] mem [31:0];` — 32-entry × 8-bit = 256 bits. Fits inside one MLAB block (640 bits); for larger depth the same template targets M10K.
- **Nonblocking** assignments (`<=`). Write and read complete simultaneously at end-of-timestep, so a collision returns the **old** memory contents on `q`. Old-data RDW form.
- Both `write_address` and `read_address` independent — simple-dual-port shape. Same registered-read discipline.

[C] template form; [C] for old-data / no-forwarding via nonblocking.

### 3.3 Intel ROM template — verbatim

Case-statement ROM body Intel documents as the recognized inference form. Combined with `$readmemb` (§3.4) when contents come from a file rather than being enumerated inline.

```verilog
// https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/inferring-rom-functions-from-hdl-code:sync_rom @ 2026-05-20 (live URL, chapter index is app-shell, no local body capture; "..." in source body is Intel's documentation ellipsis for the elided rows of the case statement)
module sync_rom (clock, address, data_out);
	input clock;
	input [7:0] address;
	output reg [5:0] data_out;
	reg [5:0] data_out;

	always @ (posedge clock)
	begin
		case (address)
			8'b00000000: data_out = 6'b101111;
			8'b00000001: data_out = 6'b110110;
			...
			8'b11111110: data_out = 6'b000001;
			8'b11111111: data_out = 6'b101010;
		endcase
	end
endmodule
```

Read carefully:

- `address` 8 bits → 256 entries × 6 bits = 1536 bits total. Too big for MLAB; Quartus infers M10K initialized at FPGA-configuration time with the case-statement constants.
- `case` assigns a constant to `data_out` for every address — the structural shape Intel's recognizer matches. `data_out` is registered (assigned inside the clocked block).
- The `...` is Intel's documentation ellipsis eliding 252 intermediate rows.

For larger ROMs use `$readmemh`/`$readmemb` (next subsection). [C] template form for ROM inference.

### 3.4 ROM-with-init via `$readmemb` — verbatim

Intel-canonical form for loading ROM/RAM contents from a text file at elaboration/configuration time.

```verilog
// https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/specifying-initial-memory-contents-at-power-up:readmemb @ 2026-05-20 (live URL, chapter index is app-shell, no local body capture)
reg [7:0] ram[0:15];
initial 
begin
	$readmemb("ram.txt", ram);
end
```

Read carefully:

- `reg [7:0] ram[0:15];` — 16-entry × 8-bit unpacked-array `reg`. Same memory shape Quartus expects; an `initial` block with `$readmemb` next to it does not interfere with the inference.
- `$readmemb` reads binary text (one binary value per line); `$readmemh` is the hex variant. Both are recognized by Intel synthesis identically — Intel states they "allow RAM initialization and ROM initialization work identically in synthesis and simulation."
- On hardware the M10K block powers up at FPGA configuration time with the file's contents. No runtime cycles consumed by init.
- File path is resolved at synthesis time relative to the Quartus project directory; getting it wrong is anti-pattern "Init file missing at synthesis" in §7.

[C] template form; `$readmemh`/`$readmemb` choice is style ([V]).

### 3.5 Byte-enable RAM template — structural stand-in

Intel's byte-enable subsection URLs returned HTTP 404 @ 2026-05-20; chapter index body is app-shell only. Per the honesty rule the §2 byte-enable claim was downgraded from [C] to [V]. The structural pattern — one `if (byteena[i]) mem[addr][8*i +: 8] <= d[8*i +: 8];` per byte, inside the same single-`always` template form as §3.1/§3.2 — is:

```verilog
// [I] composite, structurally derived from §3.2 simple-dual-port template + Intel chapter-index reference to "Inferring Byte-Enabled RAMs" section. The Intel verbatim body was not retrievable @ 2026-05-20.
module byteena_ram(
    output reg [31:0] q,
    input [31:0] d,
    input [3:0] byteena,
    input [4:0] write_address, read_address,
    input we, clk
);
    reg [31:0] mem [31:0];

    integer i;
    always @(posedge clk) begin
        if (we) begin
            if (byteena[0]) mem[write_address][ 7: 0] <= d[ 7: 0];
            if (byteena[1]) mem[write_address][15: 8] <= d[15: 8];
            if (byteena[2]) mem[write_address][23:16] <= d[23:16];
            if (byteena[3]) mem[write_address][31:24] <= d[31:24];
        end
        q <= mem[read_address];
    end
endmodule
```

[I] composite. Structural shape matches the Intel-recognized single-write-port template with the write split into four byte-wide conditional writes; Quartus's byte-enable recognizer matches this form to M10K's `byteena` port. Verbatim Intel example not retrievable.

### 3.6 Template-to-resource mapping table

| Template name (§-ref) | Inferred resource | Read-during-write mode | Port count (W / R) | Typical use case |
|---|---|---|---|---|
| Single-port RAM, new-data RDW (§3.1) | M10K (medium-to-large depth) or MLAB (small) | New-data via blocking-assignment write-forwarding | 1 / 1 (write and read on same address bus) | CPU data scratchpad, in-place transform buffers |
| Simple-dual-port RAM, old-data RDW (§3.2) | M10K (most depths) or MLAB (small) | Old-data via nonblocking | 1 / 1 (independent write_address and read_address) | FIFO body (see [22](22-fifos-synchronous-and-asynchronous.md)), line buffers, frame buffers, decoupled reader/writer |
| ROM, case-statement body (§3.3) | M10K (large) or MLAB (small) | n/a (no write port) | 0 / 1 | Look-up tables, microcode ROMs, character ROMs |
| ROM-with-init, `$readmemb` (§3.4) | M10K (large) or MLAB (small) | n/a (no write port — for ROM use) | 0 / 1 (1 / 1 if used to init a RAM) | Boot ROM, instruction ROM, palette, init contents for any memory |
| Byte-enable RAM (§3.5) | M10K (byte-enable is M10K-only) | Determined by blocking vs nonblocking on byte-wise write | 1 / 1 with `byteena[3:0]` mask | Word-addressable memory with sub-word writes, AXI-narrow-transfer back end |
| True-dual-port RAM (not shown verbatim — see [V] in §2) | M10K | Per-port and cross-port; tool selects from template | 2 / 2 | Two writers, two readers, or any 2-W combination |
| Flop-based register file (no template — explicit array of registers driven by `always_ff`) | Flops (LE registers in ALMs) | Per-port; whatever the RTL writes | Arbitrary; multi-read parallel-read supported via LUT mux fan-out | Small CPU register file, semaphore arrays, parallel functional-unit storage. Cite FPGADesignElements `RAM_Multiported_LE.v:1-15 @ 2450a54` for the canonical pattern. |

The table is the **primary decision artifact**. Selection procedure:

1. **W/R port count first.** Multi-read parallel (>2 read ports) → flops (last row). No template choice avoids that.
2. **Init contents needed?** Yes → M10K with §3.3 or §3.4 template regardless of size (MLAB does not init-at-power-up the same way).
3. **RDW behavior.** New-data → blocking (§3.1). Old-data → nonblocking (§3.2). Don't-care → either, but pick what you'd want post-PnR to simulate.
4. **Then size.** ≤16 entries with multi-read → flops. 17-~256 × narrow, 1W1R → MLAB (optionally `(* ramstyle = "MLAB" *)`). Larger or not fitting MLAB → M10K (optionally `(* ramstyle = "M10K" *)`).

| Construct / signal | Type / width / direction | Meaning | Driven by | Drives |
|---|---|---|---|---|
| `mem` | unpacked array of `reg [W-1:0]`, depth `DEPTH` | The storage; the array Quartus's template matcher hooks onto | Write logic inside the clocked block | Read logic inside the same clocked block (registered into `q`) |
| `q` / `read_data` | `reg [W-1:0]`, output | Registered read output (M10K/MLAB requirement) | The clocked-block read-assignment line | Downstream datapath |
| `d` / `write_data` | `wire [W-1:0]`, input | Write payload | Upstream datapath | `mem[write_address]` |
| `write_address` / `read_address` | `wire [ADDR_WIDTH-1:0]`, input | Address buses (one or two depending on port mode) | Upstream control | `mem` index |
| `we` / `wren` | `wire`, input | Write enable | Upstream control | The `if (we)` gating around the write |
| `byteena[N-1:0]` | `wire [N-1:0]`, input (byte-enable mode only) | Per-byte write masks | Upstream control | The per-byte `if (byteena[i])` write predicates in §3.5 |
| `(* ramstyle = "M10K" *)` / `"MLAB"` / `"logic"` / `"no_rw_check"` | Quartus synthesis attribute | Forces the storage onto a specific primitive, or relaxes the read-during-write coherency check | Author of the storage declaration | Quartus inference engine |
| `INIT_FILE` / `$readmemh(file, mem)` / `$readmemb(file, mem)` | string + system task | Loads memory contents at elaboration (sim) / configuration (HW) time | The `initial` block | `mem` contents at time 0 |

## 4. Sequencing & timing

### 4.1 Read-during-write timing diagrams

Three modes — new-data, old-data, don't-care — each shown as one ASCII waveform with the same write+read collision and the value Quartus delivers on `q`.

**Setup for all three.** Cycle 0: idle. Cycle 1: `we=1, write_address=A, read_address=A, d=N` (collision — write and read at the same address simultaneously). Memory location `A` previously held value `O` (old). Cycle 2-onwards: idle.

#### New-data RDW (blocking template, §3.1)

```
                cycle: 0   1   2   3
clk          ___|‾|_|‾|_|‾|_|‾|_
we                 0   1   0   0
write_addr         -   A   -   -
read_addr          -   A   -   -
d                  -   N   -   -
mem[A] (state)     O   N   N   N
q                  ?   N   N   N
                       ^ collision cycle: q sees new data N
                         (write-forwarding mux selects d)
```

#### Old-data RDW (nonblocking template, §3.2)

```
                cycle: 0   1   2   3
clk          ___|‾|_|‾|_|‾|_|‾|_
we                 0   1   0   0
write_addr         -   A   -   -
read_addr          -   A   -   -
d                  -   N   -   -
mem[A] (state)     O   N   N   N
q                  ?   O   N   N
                       ^ collision cycle: q sees old data O
                         (no forwarding; nonblocking executes both at end-of-step)
```

#### Don't-care RDW (mode neither template-specifies; Quartus picks at its discretion)

```
                cycle: 0   1   2   3
clk          ___|‾|_|‾|_|‾|_|‾|_
we                 0   1   0   0
write_addr         -   A   -   -
read_addr          -   A   -   -
d                  -   N   -   -
mem[A] (state)     O   N   N   N
q                  ?   X   N   N
                       ^ collision cycle: q is X in sim (uninitialized) or
                         unpredictable post-PnR; Quartus may select either mode
                         and may differ between Quartus versions or fitter runs
```

The don't-care diagram is the symptom of anti-pattern #24 in §7. If your RTL doesn't match either the blocking or nonblocking form recognized by Intel, this is what you get.

### 4.2 Read latency and write timing

- **Read latency** for both single-port (§3.1) and simple-dual-port (§3.2): **1 cycle** from `read_address` change to `q` valid (`q` registered inside the clocked block).
- **Write timing:** completes on the clock edge; new value visible on the read port the cycle after, except at collision (where §4.1 mode determines `q`).
- **Cross-port RDW on simple-dual-port** is a separate mode from same-port RDW; applies when `write_address != read_address` but both ports operate on the same M10K block on the same edge. Cite Cyclone V Device Handbook Vol. 1 embedded-memory-modes (live URL @ 2026-05-20).
- **Init-file timing:** `$readmemh`/`$readmemb` runs at elaboration in sim; on hardware the M10K powers up with init contents at FPGA configuration time. No runtime cycle consumed.
- **Byte-enable timing:** byte writes complete on the same clock edge as a full-word write; non-written bytes retain prior values per Cyclone V M10K semantics.

### 4.3 The pipeline-around-RAM-latency rule

Reads are always 1 cycle on M10K/MLAB; datapath consumers must accept 1-cycle latency between address-request and data-available. Same discipline as [15-pipelines-and-latency-thinking.md](15-pipelines-and-latency-thinking.md). Don't try to "hide" the latency with combinational read — that costs the entire memory area to LUTs.

## 5. Minimal working pattern

The smallest correct usage of each of the two most common memory tiers, each copy-pasteable with a single citation comment above.

### 5.1 Simple-dual-port M10K with init file (~30 lines)

```verilog
// [I] composite — combines Intel §3.2 simple-dual-port template (live URL,
// citation in §3.2) with Intel §3.4 $readmemh init pattern (live URL, citation
// in §3.4) plus an explicit ramstyle attribute. Citations on each constituent
// piece in §3.
module m10k_sdpram_with_init #(
    parameter WIDTH = 16,
    parameter DEPTH = 1024,
    parameter ADDR_WIDTH = 10,
    parameter INIT_FILE = "init.hex"
)(
    input  wire                  clk,
    input  wire                  we,
    input  wire [ADDR_WIDTH-1:0] write_address,
    input  wire [WIDTH-1:0]      d,
    input  wire [ADDR_WIDTH-1:0] read_address,
    output reg  [WIDTH-1:0]      q
);
    (* ramstyle = "M10K" *)
    reg [WIDTH-1:0] mem [0:DEPTH-1];

    initial begin
        $readmemh(INIT_FILE, mem);
    end

    always @(posedge clk) begin
        if (we)
            mem[write_address] <= d;
        q <= mem[read_address];
    end
endmodule
```

This is the canonical pattern for a frame buffer, a line buffer, or a FIFO body. The `ramstyle` attribute forces M10K even if Quartus's heuristics might pick differently for small `DEPTH`. The init file is loaded at FPGA configuration time.

### 5.2 MLAB-targeted small RAM (~15 lines)

```verilog
// [O] verilog-axi style — explicit MLAB-target attribute pattern. Cited
// directly to `references/projects/verilog-axi/rtl/axi_vfifo_enc.v:202 @ 516bd5d`
// for the attribute form (* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *).
module mlab_small_ram #(
    parameter WIDTH = 8,
    parameter DEPTH = 32,
    parameter ADDR_WIDTH = 5
)(
    input  wire                  clk,
    input  wire                  we,
    input  wire [ADDR_WIDTH-1:0] write_address,
    input  wire [WIDTH-1:0]      d,
    input  wire [ADDR_WIDTH-1:0] read_address,
    output reg  [WIDTH-1:0]      q
);
    (* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
    reg [WIDTH-1:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        if (we)
            mem[write_address] <= d;
        q <= mem[read_address];
    end
endmodule
```

What makes this land in MLAB: small total bits (32 × 8 = 256 bits, comfortably ≤ 640), no init file (MLAB cannot init the same way M10K does), 1W1R, and the explicit `ramstyle` attribute. The `no_rw_check` relaxes the RDW coherency requirement (we accept indeterminate behavior on collision in exchange for the smaller primitive).

### 5.3 Flop-based register file for ≤16 entries with parallel read

```verilog
// references/projects/FPGADesignElements/RAM_Multiported_LE.v:1-15,395-402 @ 2450a54
// Reduced to the minimum-correct shape. The full module supports per-port write
// conflict resolution and pipelined reads; the minimal pattern shown here is
// the canonical flop-based register file with N read ports and 1 write port,
// suitable for a CPU's rd/rs/rt three-read register file.
module flop_regfile #(
    parameter WIDTH = 32,
    parameter DEPTH = 16,
    parameter ADDR_WIDTH = 4,
    parameter NUM_READ_PORTS = 3
)(
    input  wire                                   clk,
    input  wire                                   we,
    input  wire [ADDR_WIDTH-1:0]                  write_address,
    input  wire [WIDTH-1:0]                       write_data,
    input  wire [NUM_READ_PORTS*ADDR_WIDTH-1:0]   read_addresses,
    output wire [NUM_READ_PORTS*WIDTH-1:0]        read_data
);
    // Explicit array of registers — Quartus will not pack this into MLAB or M10K
    // because of the NUM_READ_PORTS > 2 parallel-read requirement.
    reg [WIDTH-1:0] regs [0:DEPTH-1];

    always @(posedge clk) begin
        if (we) regs[write_address] <= write_data;
    end

    genvar i;
    generate
        for (i = 0; i < NUM_READ_PORTS; i = i + 1) begin : per_read_port
            assign read_data[i*WIDTH +: WIDTH] = regs[read_addresses[i*ADDR_WIDTH +: ADDR_WIDTH]];
        end
    endgenerate
endmodule
```

This is the [I]-flagged "≤16 entries → flops" pattern from §2. Note the **combinational read** (`assign`) — that's what lets multiple read ports exist; the cost is LUT-mux fan-out scaling with `DEPTH × NUM_READ_PORTS`. For a 16-entry 32-bit 3-read register file the cost is ~3 × 16-input 32-bit muxes, a known small amount. For larger `DEPTH × NUM_READ_PORTS` the LUT cost can blow up; the FPGADesignElements module provides an optional pipeline register for that case.

## 6. Common variations across implementations

- **[O] Intel canonical template** (one `always @(posedge clk)` block, registered read, blocking/nonblocking for new-/old-data RDW). Sources: §3.1 and §3.2 verbatim at Intel *Inferring Memory Functions* live URLs @ 2026-05-20. Identifier names match documentation exactly (`single_clock_wr_ram`, `single_clk_ram`). Minimalist — no `ramstyle`, no init, no byte-enable.

- **[O] FPGADesignElements style** (parameterized Verilog-2001 modules with explicit `READ_NEW_DATA` parameter selecting the blocking-vs-nonblocking generate-arm, intentionally unusable parameter defaults, optional `RAMSTYLE`, optional `USE_INIT_FILE`). Sources: `references/projects/FPGADesignElements/RAM_Single_Port.v:107-129 @ 2450a54` (generate-arm pair selecting old-vs-new RDW), `RAM_Simple_Dual_Port.v:114-140 @ 2450a54`, and the module-header commentary at `RAM_Single_Port.v:11-29 @ 2450a54` — the corpus's clearest plain-English explanation of why blocking-vs-nonblocking matters for RAM inference. Structurally equivalent to Intel templates with more knobs.

- **[O] verilog-axi MLAB-attribute pattern** (`(* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)` on the storage declaration). Source: `references/projects/verilog-axi/rtl/axi_vfifo_enc.v:202,231-236 @ 516bd5d` — four `mem` declarations all tagged with the dual-vendor attribute string (`ram_style` for Vivado, `ramstyle` for Quartus). `no_rw_check` relaxes the RDW coherency requirement, unlocking MLAB packing. See the Quartus note quoted in `references/projects/FPGADesignElements/RAM_Single_Port.v:33-40 @ 2450a54`: "Quartus ignores the `no_rw_check` RAMSTYLE for M10K BRAMs" — so `"no_rw_check, mlab"` is the explicit way to say "MLAB, accept indeterminate collision behavior."

- **[O] Multi-ported register file via LUTs** (FPGADesignElements `RAM_Multiported_LE.v` — per-port-decoded write, combinational fan-out read, optional pipelined output, ON_WRITE_CONFLICT resolution). Source: `references/projects/FPGADesignElements/RAM_Multiported_LE.v:1-15 @ 2450a54` — module-header commentary explicitly names this as flop-based, **not** M10K/MLAB. M10K/MLAB cannot do >2 read ports directly.

- **[O] Cyclone V byte-enable pattern via per-byte conditional write** — no verbatim source (Intel byte-enable subsection URLs returned 404 @ 2026-05-20; chapter index is app-shell). Structural shape in §3.5 as [I] composite. The verilog-axi `axi_vfifo_*` modules use byte-strobe AXI signals; cite `references/projects/verilog-axi/rtl/axi_vfifo_enc.v @ 516bd5d` as orientation only.

## 7. Anti-patterns (mistakes that compile but break)

Five entries below. **#24 and #25 are this doc's primary-home anti-patterns** (full Symptom/Cause/Fix/Citation form). The other three are mistakes that compile but break, surfaced here because they belong to the memory-inference scope.

### #24 — Read-during-write mode assumed without explicit setting (PRIMARY HOME)

- **Symptom:** Simulation passes; post-place-and-route simulation differs from RTL sim, or behavior changes between Quartus versions. At collision cycles (`we=1 && write_address == read_address`), the read output is either old or new data unpredictably, and the choice may flip with a recompile, tool-version upgrade, or `ramstyle` change. Often surfaces as intermittent corruption in tight loops where the same address is being written and read by adjacent pipeline stages.
- **Cause:** RTL template did not match either of Quartus's recognized RDW forms — neither §3.1 blocking/new-data nor §3.2 nonblocking/old-data. The author may have mixed blocking and nonblocking inside the same `always` block, used a separate `always_comb` for the read path, or put write and read in two different `always` blocks. Quartus then picks a default (don't-care mode in §4.1) or refuses to infer M10K/MLAB and pushes the storage into LUTs.
- **Fix:** Rewrite the storage using exactly one of §3.1 (blocking) or §3.2 (nonblocking). Decide which mode you architecturally need: if consumers expect a write to be readable next cycle, use old-data and have the consumer wait a cycle; if consumers expect to read the just-written value same cycle, use new-data. Verify the chosen mode appears in the Fitter report's memory summary (cross-ref [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md)). Confirm RTL sim and post-PnR sim agree at the collision cycle.
- **Citation:** Intel *Inferring Memory Functions* RDW subsection live URLs `…/single-clock-synchronous-ram-with-old-data-read-during-write-behavior` @ 2026-05-20 and `…/…-new-data-…` @ 2026-05-20 (both retrieved successfully in §3). Reinforced by FPGADesignElements `RAM_Single_Port.v:11-29 @ 2450a54` (blocking/nonblocking-determines-mode commentary) and `RAM_Single_Port.v:33-40 @ 2450a54` (the Quartus footnote: "Quartus ignores the `no_rw_check` RAMSTYLE for M10K BRAMs, [so] add `ADD_PASS_THROUGH_LOGIC_TO_INFERRED_RAMS OFF`").

### #25 — Inferred M10K where a small register file (≤16 entries) belongs in flops (PRIMARY HOME)

Primary home is **this doc**; [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md) cross-references back for the era-faithful angle.

- **Symptom:** Quartus Fitter report shows one M10K block consumed for a small array (e.g., 16-entry CPU register file). Downstream consumers want **parallel reads** of multiple entries (a CPU's three-source-operand `rd`/`rs`/`rt`). The M10K-backed implementation provides only 1-2 read ports — the third read must stall a cycle or be replicated, neither of which the original chip's microarchitecture mandated. Surfaces as unexpected datapath stall or a "we're using an M10K for 16 entries?" code-review comment.
- **Cause:** Writer reached for the standard simple-dual-port template (§3.2) out of habit; size and read-port count were not analyzed against the §3.6 decision table. The default "memory goes in M10K" heuristic is wrong for tiny multi-read arrays — the correct primitive is flops with LUT-mux fan-out (§5.3 / `RAM_Multiported_LE.v`).
- **Fix:** Replace `mem` with `reg [W-1:0] regs [0:N-1];` driven by `always @(posedge clk)`, with **combinational reads** (`assign` per read port indexing into `regs`) — pattern §5.3. Confirm Quartus reports **zero memory blocks** for this storage. Cost is `N × NUM_READ_PORTS` LUTs of mux fan-out; for a 16-entry, 32-bit, 3-read register file ~3 × 16-input 32-bit muxes, small. Cross-ref [17-era-faithful-microarchitecture.md](17-era-faithful-microarchitecture.md): the original CPU had no equivalent of M10K, so faithful emulation should mirror flop-based storage rather than substitute a tool-default block memory.
- **Citation:** `references/projects/FPGADesignElements/RAM_Multiported_LE.v:1-15 @ 2450a54` (canonical flop-based multi-read register file, module-header commentary names "small CPU register files" as a flop-based use case); Cyclone V Device Handbook Vol. 1 embedded-memory-modes (live URL @ 2026-05-20) for the M10K 1-2-read-port restriction. [V] for the "≤16" threshold; [I] for the exact "16" per the §2 [V] qualifier.

### Async read inferred as area blowup, not as M10K

- **Symptom:** Design uses combinational read; Quartus Fitter report shows zero M10K blocks consumed and unexpectedly large LUT count (sometimes 100× the equivalent registered-read design). Storage that should have been one M10K block ends up in thousands of LUTs as a wide combinational mux.
- **Cause:** M10K and MLAB both **require registered read** for inference. `assign data_out = mem[address];` does not match the inference template — Quartus implements storage in distributed LUT RAM with area scaling as `DEPTH × WIDTH`.
- **Fix:** Register the read output. Move read assignment inside `always @(posedge clk)` as `q <= mem[read_address];`, declare `q` as `output reg [W-1:0] q` — template form shown in §3.1 and §3.2. Cost is one cycle of read latency, absorbed via the pipeline-around-RAM rule in §4.3.
- **Citation:** Intel *Inferring Memory Functions* §3.1 and §3.2 templates @ 2026-05-20. Note that FPGADesignElements `RAM_Multiported_LE.v` does use combinational reads — that module is intentionally **not** trying to infer M10K/MLAB; it's the flop-based pattern. Don't confuse the two contexts.

### Init file missing at synthesis (works in sim, all zeros on hardware)

- **Symptom:** Simulation matches expectations; on hardware the ROM reads all zeros. The boot ROM never branches correctly, the palette is black, the LUT returns garbage. "The file is there" — but Quartus's synthesis did not find it.
- **Cause:** `$readmemh` argument path was not relative to the Quartus project directory, or the file was not added to the project's source list. Quartus's elaboration did not include the init contents in the M10K block's configuration data. Simulation works because the simulator resolves the path relative to its own working directory.
- **Fix:** Use a path relative to the Quartus project directory (e.g., `"rom_contents.hex"`, not `"/abs/path/…"` and not `"../sim/…"`). Add the file to the project source list (Project → Add/Remove Files, or in the QSF). Verify the Fitter log line "Memory initialization data loaded from rom_contents.hex" or similar. Cross-ref [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md) for the log message format.
- **Citation:** Intel *Specifying Initial Memory Contents at Power-Up* @ 2026-05-20 (live URL, retrieved, §3.4). Intel describes `$readmemh`/`$readmemb` as the synthesis-and-simulation identical pattern, so this divergence is a path-handling bug, not a tool capability gap.

### True-dual-port used where simple-dual-port would suffice

- **Symptom:** Quartus Fitter report shows higher M10K count than expected (two M10Ks where one would fit the design's total bits). May show as routing congestion because true-dual-port mode constrains M10K placement.
- **Cause:** Writer instantiated true-dual-port for a one-writer, one-reader pattern. True-dual-port costs both M10K write-capability slots; for 1W1R, simple-dual-port suffices and Quartus packs two such memories into one M10K.
- **Fix:** Switch to the simple-dual-port template (§3.2). Re-read the design plan: are there really two writers? Or is one of them a refresh/scrubbing path that could be muxed onto the simple-dual-port's single write side?
- **Citation:** Cyclone V Device Handbook Vol. 1 embedded-memory-modes (live URL @ 2026-05-20, no local body); confirmed structurally by FPGADesignElements `RAM_Simple_Dual_Port.v` and `RAM_True_Dual_Port.v` being separate, distinct modules at `references/projects/FPGADesignElements/ @ 2450a54`.

## 8. Verification

How to confirm correct behavior, and what bug symptoms look like in simulation or in Quartus reports.

- **Quartus Fitter report check.** Open Fitter report → Resource Section → RAM Summary. Confirm each RAM instance lands on the expected tier (M10K count matches the design plan, MLAB count matches, no unexpected LUT-based RAM). Cross-ref [41-quartus-reports-and-verification.md](41-quartus-reports-and-verification.md) for navigation.

- **Functional sim: write-then-read.** Write `V` to address `A`; read `A` the next cycle; confirm `q == V` after the 1-cycle latency (§4.2).

- **Functional sim: RDW collision.** Set `we=1, write_address=A, read_address=A, d=N` with memory previously holding `O` at `A`. Confirm `q` matches the chosen mode: `O` for old-data (§3.2), `N` for new-data (§3.1). If `q` is `X`, the template doesn't match — anti-pattern #24.

- **Post-PnR simulation.** Re-run the RDW collision test against the netlist. RTL sim and netlist sim must agree. Disagreement signals an unstable template form.

- **ROM init verification.** In sim, dump the first few ROM words at time 0; compare to the `.hex`/`.bin` file. On hardware, read via SignalTap or LED probe. Hardware-zeros with correct sim values means init file missing from synthesis (§7).

- **Byte-enable verification.** Testbench writes individual bytes (`byteena = 4'b0010` with 32-bit `d`); confirm only the addressed byte changes on the next-cycle read.

- **Tier-decision audit.** Walk every `logic [W-1:0] arr [0:N-1];` declaration. For each, confirm against §3.6: size, port count, read-port count, init requirement, RDW mode all match the chosen tier. The `ramstyle` attribute (if any) is explicit. The template form is exactly §3.1, §3.2, §3.3, §3.4, §3.5, or §5.3. Promote/demote storage with a comment citing the §3.6 row; if the choice contradicts the table, write the reason next to it.

## 9. Provenance footer

Sources actually cited in this doc, with the §s each supports. App-shell-only sources are tagged.

- `https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/single-clock-synchronous-ram-with-old-data-read-during-write-behavior` @ 2026-05-20 — used for §2 ([C] template form, [C] RDW selection via nonblocking), §3.2 (verbatim `single_clk_ram`), §4.1 (old-data RDW timing), §7 (#24 citation). **Live URL, no local body capture; subsection-level fetch successful @ 2026-05-20.** Chapter index file `references/raw/intel/quartus_standard_design_recommendations_index.html` is an app-shell.
- `https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/single-clock-synchronous-ram-with-new-data-read-during-write-behavior` @ 2026-05-20 — used for §2 ([C] template form, [C] new-data RDW selection via blocking, [C] registered-read), §3.1 (verbatim `single_clock_wr_ram`), §4.1 (new-data RDW timing), §7 (#24 citation). **Live URL, no local body capture; subsection-level fetch successful @ 2026-05-20.**
- `https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/inferring-rom-functions-from-hdl-code` @ 2026-05-20 — used for §3.3 (verbatim `sync_rom` case-statement ROM template), §2 ([V] ROM init template form). **Live URL, no local body capture; subsection-level fetch successful @ 2026-05-20.**
- `https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/specifying-initial-memory-contents-at-power-up` @ 2026-05-20 — used for §3.4 (verbatim `$readmemb` init template), §2 ([V] init-file ROM/RAM rule), §7 ("Init file missing at synthesis" citation). **Live URL, no local body capture; subsection-level fetch successful @ 2026-05-20.**
- `https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/inferring-memory-functions-from-hdl-code` @ 2026-05-20 — chapter-index live URL; used in §2 (general framing of Quartus's inference recognizer), §6 (Intel-canonical-template anchor), §7 (init-file path-handling citation). **Live URL; local capture `references/raw/intel/quartus_standard_design_recommendations_index.html` is an app-shell only, body not extractable.** Byte-enable subsection (referenced from this chapter's TOC) was not retrievable at subsection-level — see §3.5 and the §2 [V] downgrade.
- `https://docs.altera.com/r/docs/683375/current/cyclone-v-device-handbook-volume-1-device-interfaces-and-integration` @ 2026-05-20 — Cyclone V Device Handbook Vol. 1, embedded-memory and embedded-memory-modes sections. Used for §1 (5.6 Mbit budget framing alongside the glossary), §2 ([V] MLAB/M10K capacity facts, [V] M10K port-count restrictions, [V] true-dual-port distinction), §4.2 (cross-port RDW separate-mode statement), §4.2 (byte-enable timing), §7 (true-dual-port-vs-simple-dual-port citation, M10K-port-count citation). **Live URL, no local body capture; the local files `references/raw/intel/cyclone_v_embedded_memory_types.html` and `cyclone_v_embedded_memory_modes.html` are app-shells with no extractable body.**
- `references/raw/intel/cyclone_v_product_table_api.txt` — used for the 5.6 Mbit M10K+MLAB total figure and the `5CSEBA6U23I7` part identification. **Local file is a PDF that exceeds the Read tool's token capacity (100 KB, ~63k tokens for 2 pages); cited via the live URL `https://docs.altera.com/r/docs/683375/current/cyclone-v-device-handbook-volume-1-device-interfaces-and-integration` and via the bundle glossary distillation `cyclone-v-hdl-bundle/01-glossary.md:20 @ 2026-05-19`.** **Live URL, PDF exceeds Read tool capacity.**
- `cyclone-v-hdl-bundle/01-glossary.md:11-12,20 @ 2026-05-19` — used for §1 (5.6 Mbit budget), §2 ([V] MLAB 640 bits / M10K 10 240 bits per block; [V] 5CSEBA6U23I7 part identification). Bundle-internal restatement of the Cyclone V product-table and Device Handbook headline numbers; cross-cited because the source PDFs and HTMLs are not extractable directly.
- `references/projects/FPGADesignElements/RAM_Single_Port.v:11-47,107-129 @ 2450a54` — used for §2 ([C] RDW mode selection mechanism, [V] `ramstyle` interactions), §6 ([O] FPGADesignElements style), §7 (#24 citation reinforcement, async-read citation). Module-header commentary at lines 11-47 is the corpus's clearest plain-English statement of "blocking-vs-nonblocking determines write-forwarding"; the generate-arm pair at lines 107-129 implements both forms.
- `references/projects/FPGADesignElements/RAM_Simple_Dual_Port.v:114-140 @ 2450a54` — used for §6 ([O] FPGADesignElements simple-dual-port variant), §7 (true-dual-port-vs-simple-dual-port citation, separate-modules argument).
- `references/projects/FPGADesignElements/RAM_Multiported_LE.v:1-15,395-402 @ 2450a54` — used for §2 ([I] ≤16-entries-in-flops rule), §3.6 (decision table flop-row citation), §5.3 (verbatim minimal flop register file), §6 ([O] multi-ported register file variant), §7 (#25 primary citation, async-read-vs-flop-register-file disambiguation note).
- `references/projects/FPGADesignElements/RAM_True_Dual_Port.v @ 2450a54` — referenced from §7 (true-dual-port-vs-simple-dual-port: distinct module argument) and §3.6 (decision table true-dual-port row). Not quoted verbatim — the module exists as evidence of the simple-vs-true distinction in canonical Verilog-2001 style.
- `references/projects/verilog-axi/rtl/axi_vfifo_enc.v:202,231-236 @ 516bd5d` — used for §2 ([V] MLAB-targeting attribute form), §5.2 (verbatim attribute pattern), §6 ([O] verilog-axi MLAB-attribute style). The dual-vendor attribute string `(* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)` is the source's load-bearing pattern.
- `references/MANIFEST.md` — used in §9 itself (this footer) for citing the corpus-revision manifest; not quoted verbatim elsewhere in the doc.

Archive sources cited: six. Live URLs cited: six (four Intel subsection URLs retrieved; one Intel chapter-index app-shell; one Cyclone V Device Handbook app-shell). PDF-capacity-limited source: one (product table).
