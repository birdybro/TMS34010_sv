# Memory map

> Status: **field-to-word translation, interrupt-register semantics, direct
> HSTCTL access, live REFCNT, internal video timing, and live DPYADR
> implemented through Task 0156**. The core issues bit-addressed 1–32-bit
> accesses, and a synthesizable sequencer expands them into aligned 16-bit
> word cycles. The on-chip I/O page is decoded and stored in the core.
> The original-pin phase engine is connected through a coherent core-to-8×
> bridge, processor/host-indirect on-chip I/O use the dedicated cycle kinds,
> physical HOLD/HOLDA bus release and the shared HLDA/EMUA output are
> integrated, and the original asynchronous host controls, HRDY, and split
> HD direction now wrap the four-register engine. Defined reserved fields and
> locations are enforced on both processor and host-indirect paths. Video
> counters/display state now live in VCLK behind coherent core-domain views.

## Architectural address space

The TMS34010 uses a **32-bit bit-addressed** memory model. Address bits
[31:4] select a 16-bit word in external memory; address bits [3:0] select
a bit within that word.

```
   bit 31                                  bit 4 bit 3      bit 0
   ┌──────────────────────────────────────┐─────┬───────────┐
   │           word address (28 bits)     │     │ bit offset│
   └──────────────────────────────────────┘─────┴───────────┘
```

Field operations specify a **field size** (1–32 bits) and read/write that
many bits starting at the bit address, crossing word boundaries as needed.

`rtl/memory/tms34010_field_sequencer.sv` implements the §4.1 field semantics
as of Task 0136. It issues aligned 16-bit words in ascending address order:
one, two, or three reads; direct writes for every fully covered word; and
read/modify/write for a partial first or last word. These combinations give
the guide's exact seven cases A–G. Read results are masked and right
justified. `word_rmw_lock_o` covers each partial-word read through its
matching write acknowledge, without incorrectly locking the gaps between
different words. Task 0145 adds the HOLD restart input: if HOLD is accepted
after a partial read but before its write begins, that write is suppressed and
the complete RMW pair repeats.

`rtl/memory/tms34010_bus_arbiter.sv` implements the §11.3 fixed order of
external HOLD, screen refresh, DRAM refresh, host indirect, and CPU/graphics.
An active controller cycle retains ownership through acknowledge. CPU
partial-word RMW pairs retain a reservation across the read/write boundary;
different field words remain preemptable. A one-clock DRAM-refresh event is
captured with its row/mode until serviced.

Task 0146 composes those blocks in `tms34010_memory_fabric` and connects the
core through `tms34010_system`. CPU/graphics fields, screen refresh, DRAM
refresh, and host-indirect accesses now converge on one held abstract
controller cycle.

Task 0147 adds `tms34010_local_bus` at the physical side of that
boundary. From a dedicated 8× timing clock it generates LCLK1/LCLK2 and the
half-quarter LAD/RAS/CAS/LAL/W/TR/DEN/DDOUT schedule for word reads/writes,
screen memory-to-register transfers, both DRAM-refresh modes, and I/O cycles.
It emits the exact §11.5 word/refresh status format plus the §9.10.1.2
screen-address network, repeats the access period while LRDY is low, and
performs eight zero-row RAS-only cycles after reset. The controller command
port is intentionally synchronous to the 8× domain.

Task 0148 adds `tms34010_local_bus_bridge` and `tms34010_pin_system`. A
source-registered `local_cycle_cmd_t` holds kind, address/data, IAQ,
SRFADR/DPYTAP/ORG, and DRAM row while a request toggle crosses to the 8×
domain. The completed read word is held in the reverse direction until the
acknowledge toggle returns. The current cacheless core asserts IAQ only for
the opcode word fetched in `CORE_FETCH`; immediate instruction words and all
data/vector words drive it low. The integrated reset-vector transaction waits
behind the controller's eight reset RAS cycles before appearing on LAD.

Task 0149 registers and classifies each architectural CPU memory request in
`tms34010_memory_fabric`. External 1–32-bit fields continue through
`tms34010_field_sequencer`; a processor address in
`C0000000h-C00001FFh` bypasses splitting and selects
`LOCAL_CYCLE_IO_READ/WRITE`. The coherent command includes the internal
16-bit register read value, IAQ is inactive, and physical completion produces
the single processor acknowledge that commits a write/load.

Task 0150 applies that same full-address decode to the held host-indirect word
client. It has an independent read view into all 32 internal registers; the
arbiter snapshots live read data on selection and emits
`LOCAL_CYCLE_IO_READ/WRITE`. Returned completion fills HSTDATA or commits the
write once. Host-indirect HSTCTLL writes use host-side field ownership, and
HSTADR/HSTDATA retain shared storage through an independent selector.

Task 0151 connects active-low physical HOLD to the abstract arbiter without
crossing a changing bus payload. The phase engine samples the level at
end-Q1; synchronized request/grant levels allow the current cycle to finish,
then phase HOLDA and the physical output-enable groups through Q3/Q4, Q2,
and Q3. Address/data and all affected controls remain released until the
inverse resume sequence completes.

Task 0152 completes the hold/emulator pin around that bus. Physical RUN/EMU
is synchronized into the core; a held event bridge turns each architectural
EMU execution into one complete Q1/Q2 EMUA pulse, and a phase-latched halt
level repeats it while stopped. LCLK1 selects EMUA in Q1/Q2 and the Task 0151
HLDA result in Q3/Q4 on one shared output.

Task 0153 adds `tms34010_host_bus` around the synchronous register engine.
The original active-low HCS/direction/byte strobes and HFS selection now form
one coherently captured transaction; HRDY waits for the response and any
older indirect operation, while completed reads retain data and enable only
the selected HD byte lanes. HCS remains the reset strap presented to the I/O
owner and independently starts the HSTCTL wait interval.

Task 0154 completes the ordinary I/O storage masks. CONTROL bits 1:0,
DPYCTL bit 1, and DPYTAP bits 15:14 remain zero. Reserved indices 17h–1Ah
ignore completed writes and return zero through either read view; this
includes the documented no-effect PMASK compatibility word at `C0000170h`.
REFCNT bits 1:0 retain the separate deterministic A0033 policy.

Task 0155 moves all live timing/display state into VCLK behind coherent
configuration, command, status, event, and screen-transaction crossings.
Task 0156 consumes DPYCTL.NIL there: internal interlace starts the odd field
at HTOTAL/2, advances VCOUNT at the odd VESYNC half-line point, and carries
field phase to DPYADR. The DPYSTRT reload preceding an even field applies
signed DUDATE/2; the reload preceding an odd field remains unchanged.

The simulation memory model (`sim/models/sim_memory_model.sv`) retains its
public core-side interface and backing `mem[]`, but now routes every request
through the synthesizable sequencer into a one-cycle aligned 16-bit target.
Thus all integration benches exercise physical word splitting. Tasks
0077–0079 remain responsible for FS, FE, pointer stepping, and MOVE addressing;
pixel operations similarly drive `mem_size` from PSIZE.

The architectural address is 32 bits; the local-bus controller emits logical
address bits [29:4] in the original multiplexed format, with RF/TR/IAQ in the
three status positions. The MCP layer transfers held arbiter commands and
completed read/ack responses between the core and 8× domains without treating
the multi-bit payload as independently synchronized bits.

## Architectural vector words

Reset and TRAP 0 read the same 32-bit level-0 vector at bit address
`0xFFFF_FFE0` (1988 User's Guide pages 8-10 and 8-12). Task 0121 makes
`CORE_RESET` issue that read before the first instruction fetch.

The simulation model is intentionally much smaller than the architectural
address space. It therefore exposes a dedicated public `level0_vector` word
instead of folding `0xFFFF_FFE0` through its low index bits and aliasing an
ordinary program/data word. The word defaults to zero for focused programs
that begin at word zero; `tb_reset_vector` assigns a nonzero value, and
`tb_trap0` retargets it after boot for the later software trap.

Illegal opcodes use the 32-bit vector-30 word at bit address `0xFFFF_FC20`
(1988 User's Guide §8.7). Unlike the dedicated level-0 test-model word, this
and other nonzero trap vectors currently fold through the bounded backing
store's low address-index bits. `tb_illegal_opcode` verifies the full
architectural bus address before the model applies that simulation alias.

## I/O register space

The TMS34010 maps 32 on-chip 16-bit I/O registers into the bit-address
range `0xC0000000`–`0xC00001FF` (1988 User's Guide Figure 6-1, page 6-3).
Each register sits at a `0x10`-bit-aligned address (16 bits apart). An
address decodes to I/O space when its two MSBs are `11` and bits[29:9] are
`0`; the register index is `addr[8:4]`. **All I/O registers reset to 0
except HSTCTLH.HLT**, which resets to the sampled HCS level: active-low HCS
selects self-bootstrap/run and inactive-high HCS selects host-present halt.

`rtl/io/tms34010_io_regs.sv` implements the register file and is wired into
the core memory path (Tasks 0081–0082). Graphics-control taps drive PSIZE,
PMASK, conversion pitch, CONTROL/PPOP, and interrupt behavior. HSTCTLH.NMI is
auto-cleared on entry. Task 0137 made INTENB reserved bits read zero and
implemented INTPEND by source: synchronized read-only LINT1/LINT2 levels,
read-only HSTCTLL.INTIN/HIP, and hardware-set DIP/WVP latches cleared by
writing zero. Processor-side HSTCTLL writes also obey the INTIN, MSGOUT, and
INTOUT restrictions on pages 6-36/6-37. Task 0138 made REFCNT a live
processor-writable continuous interval/row down-counter driven by
CONTROL.RR, with CONTROL.RM and request/row outputs for the future memory
fabric.

Task 0139 connects the horizontal/vertical timing values and DPYINT/DPYCTL
to the internally generated timing path. HCOUNT/VCOUNT are now live writable
counters, and its start-of-HBLANK compare sets the existing DIP latch.
Task 0141 makes DPYADR live: DPYSTRT supplies its frame/line reloads,
DPYCTL.SRE/DUDATE/ORG controls held screen-refresh scheduling and
acknowledge-time updates, and DPYTAP is captured with each client request.
Task 0142 connects the complementary host-visible HSTCTL view: host writes
own MSGIN, set INTIN, and clear INTOUT; processor writes own MSGOUT, clear
INTIN, and set INTOUT. Both sides can write the seven defined HSTCTLH fields,
reserved bits read zero, and active-low HINT reflects INTOUT.

Task 0143 implements the HSTADR/HSTDATA semantics in the integration-ready
`tms34010_host_if`: HSTADR is word-aligned, a completed host address load
prefetches HSTDATA, HSTDATA reads/writes launch held 16-bit local cycles,
LBL chooses the last byte, and INCR/INCW update the pointer in the specified
order. Processor accesses cause no indirect side effect.

Task 0144 instantiates the engine in the I/O/core path. Processor and host
therefore observe the same HSTADR/HSTDATA state, while the host's indirect
aligned-word request leaves the core on a held request/ack client. Task 0146
wires that client to the shared arbiter, and Tasks 0149–0150 select the exact
physical I/O cycle for either requester as documented in A0028.
Task 0154 applies the final ordinary reserved masks to both completed write
paths and makes all four reserved locations explicit non-storage.
Task 0155 moves live counters and display state into VCLK with coherent
core-domain views. Task 0156 consumes NIL for internal field sequencing and
the field-aware half-DUDATE DPYADR reload.

| Addr (bit) | Index | Name | Group | Notes |
|------------|-------|------|-------|-------|
| C0000000 | 0x00 | HESYNC  | video timing | Horizontal End Sync |
| C0000010 | 0x01 | HEBLNK  | video timing | Horizontal End Blank |
| C0000020 | 0x02 | HSBLNK  | video timing | Horizontal Start Blank |
| C0000030 | 0x03 | HTOTAL  | video timing | Horizontal Total |
| C0000040 | 0x04 | VESYNC  | video timing | Vertical End Sync |
| C0000050 | 0x05 | VEBLNK  | video timing | Vertical End Blank |
| C0000060 | 0x06 | VSBLNK  | video timing | Vertical Start Blank |
| C0000070 | 0x07 | VTOTAL  | video timing | Vertical Total |
| C0000080 | 0x08 | DPYCTL  | video timing | Bit 1 reads zero; DUDATE/ORG/SRE drive screen refresh; NIL selects internal field sequencing; ENV gates combined blank and new DIP events; DXV external sync and SRT remain subsequent consumers |
| C0000090 | 0x09 | DPYSTRT | video timing | LCSTRT/SRSTRT reload live DPYADR at line/frame boundaries |
| C00000A0 | 0x0A | DPYINT  | video timing | VCOUNT line selected for DIP at start of horizontal blanking |
| C00000B0 | 0x0B | CONTROL | graphics ctl | Bits 1:0 read zero; RM/RR, transparency, window, direction, PPOP, CD |
| C00000C0 | 0x0C | HSTDATA | host         | Host Data |
| C00000D0 | 0x0D | HSTADRL | host         | Host Address (LSBs) |
| C00000E0 | 0x0E | HSTADRH | host         | Host Address (MSBs) |
| C00000F0 | 0x0F | HSTCTLL | host         | Host: MSGIN/set INTIN/clear INTOUT; CPU: clear INTIN/MSGOUT/set INTOUT |
| C0000100 | 0x10 | HSTCTLH | host         | Shared NMI/NMIM/INCW/INCR/LBL/CF/HLT; reserved bits zero |
| C0000110 | 0x11 | INTENB  | interrupt    | Five source enables; reserved bits read zero |
| C0000120 | 0x12 | INTPEND | interrupt    | X1P/X2P/HIP read-only; DIP/WVP hardware-set and write-zero-to-clear |
| C0000130 | 0x13 | CONVSP  | graphics ctl | Source Conversion Pitch |
| C0000140 | 0x14 | CONVDP  | graphics ctl | Destination Conversion Pitch |
| C0000150 | 0x15 | PSIZE   | graphics ctl | Pixel Size (1/2/4/8/16) |
| C0000160 | 0x16 | PMASK   | graphics ctl | Plane Mask |
| C0000170–C00001A0 | 0x17–0x1A | — | reserved | Writes ignored; reads return zero |
| C00001B0 | 0x1B | DPYTAP  | video timing | Bits 13:0 captured per screen-refresh request; reserved bits 15:14 read zero |
| C00001C0 | 0x1C | HCOUNT  | video timing | VCLK-owned writable counter; core reads a coherent bounded-stale snapshot and writes use the A0045 command mailbox |
| C00001D0 | 0x1D | VCOUNT  | video timing | VCLK-owned writable scan-line counter with the same coherent snapshot/command contract |
| C00001E0 | 0x1E | DPYADR  | video timing | VCLK-owned LNCNT/SRFADR; coherent core snapshot, command writes, field-aware DPYSTRT/DUDATE/2 reload, and acknowledged screen-refresh updates |
| C00001F0 | 0x1F | REFCNT  | refresh      | Live writable RINTVL/ROWADR down-counter; RR=00/01 requests every 32/64 clocks |

Indices are named in `rtl/tms34010_pkg.sv` as `IO_IDX_<NAME>`. Implemented bit
fields for graphics and interrupt behavior are also named in the package.
Remaining video-mode fields must be documented as their consuming blocks are
integrated.

## Host-interface-visible registers

The physical host boundary maps HFS `00/01/10/11` to HSTADRL, HSTADRH,
HSTDATA, and combined HSTCTL respectively, with active-low HREAD/HWRITE and
HLDS/HUDS controls plus active-low HINT. `tms34010_host_bus` establishes a
coherent core-clock request and returns HRDY/read data; `tms34010_host_if`
owns HSTADR/HSTDATA storage and side effects while passing HSTCTL through to
the I/O register owner. Host-indirect addresses in the I/O page traverse the
landed arbiter, CDC bridge, and physical RAS/LAL-only cycle before HSTDATA
updates or a register write commits. Final FPGA pin buffers and timing
constraints remain part of hardware realization, not the register map.

## Display / video memory behavior

The original device interacts with VRAM through random-access and serial-shift
cycles. The current repository schedules and holds the screen-refresh
client request in VCLK with captured SRFADR/DPYTAP/ORG. The Task 0155 MCP
transaction bridge carries it into the core, and the integrated local-bus MCP
routes it to the controller's physical memory-to-register pin cycle before
completion returns to DPYADR. Task 0156 adds the interlaced starting-address
displacement without changing that completed-transfer contract. There is
still no VRAM serial-output model or pixel output.

## Uncertain / partially implemented areas

- External-sync timing, VRAM shift-register behavior, and pixel output.
