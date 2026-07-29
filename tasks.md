# Tasks

## Current Milestone: Reconcile and complete the remaining architecture

The functional implementation is complete through Task 0155. Task 0155 moves
timing/display ownership to independent VCLK and closes every core/video
crossing with coherent MCP/event/transaction handshakes. Task 0154 closes
the remaining reserved I/O field/location behavior for both processor and
host-indirect accesses. Task 0153 wraps
the synchronous four-register host engine with the original asynchronous host
controls, HD direction, and HRDY behavior. Task 0152
phases the landed EMU handshake into exact Q1/Q2 windows and combines it with
Q3/Q4 HLDA on the original shared output pin. Task 0151
connects active-low physical HOLD to the fixed-priority arbiter through
synchronized level handshakes and implements early Q3/Q4 HOLDA plus exact
Q2/Q3 output-enable release and resume. Task 0150
routes host-indirect accesses to the on-chip I/O page through the same
two-clock physical cycle contract, shared register owner, and returned
completion as processor accesses. Task 0149
routes processor on-chip I/O accesses into dedicated physical I/O read/write
cycles and qualifies their internal side effects with returned completion.
Task 0148 connects the core-clock fabric to the 8× original-pin engine through a
coherent two-phase MCP command/response bridge, propagates IAQ and captured
screen ORG, and adds the integrated pin-system wrapper. Task 0147 implements
the 8× original-pin local-bus phase engine, all landed cycle families, LRDY
waits, exact address/status multiplexing, and eight post-reset RAS-only
cycles. Task 0146 connects the core's CPU/graphics,
screen, DRAM-refresh, and host-indirect clients through the field sequencer
and fixed-priority arbiter to one abstract controller boundary. Task 0145
landed that arbiter with active-owner
retention, DRAM-refresh event capture, CPU RMW reservation, inter-word
preemption, and the HOLD restart exception. Task 0144 integrated the host
engine into the I/O/core hierarchy, made HSTADR/HSTDATA common processor/host
state, and exposed its held local-word client. Task 0143
implemented the synchronous HSTADR/HSTDATA indirect engine with LBL byte
completion, prefetch buffering, INCR/INCW ordering, held local-word requests,
and host backpressure. Task 0142
completed direct host-side HSTCTL access, HINT, HCS-selected reset halt, and
instruction-boundary HLT/NMI behavior. Task 0141 made
DPYADR live and added held, acknowledged screen-refresh scheduling with exact
frame reload, line cadence, and DUDATE/ORG completion updates. Task 0140
corrected every internal sync/blank interval endpoint for the specified
one-VCLK delay after equality. Task 0139 corrected the display-interrupt
compare point and integrated internal, noninterlaced video timing with the
live I/O registers, DIP latch, and core timing outputs. Task 0138 corrected
the legacy refresh model against the
individual REFCNT pages, integrated the live counter with CONTROL and the I/O
register file, and exported its request/row/mode boundary for the future
memory fabric. Task 0137 closed the interrupt-register/source portion of exit
gate 3 by
implementing every maskable pending source, the external-pin synchronizers,
and the exact processor-side register rules. Task 0118
reconciled the repository for continued work, Task 0119 made every tracked
testbench part of one strict local validation gate, and Task 0120 closed the
two explicitly tracked multiword MOVB gaps. Task 0121 began the remaining
cross-phase integration with the architectural reset-vector fetch. Task 0122
closed the deferred illegal-opcode interrupt path. Task 0123 resolved the
remaining interrupt-entry status assumption directly against the guide.
Task 0124 established the primary-spec completion ledger that now drives
further implementation. Task 0125 closed its logical-status, ANDI/ANDNI, CLR,
and DEC findings. Task 0126 closed the first missing MOVE form.
Task 0127 closed the second. Task 0128 implemented EMU and closed the last
unimplemented official instruction-summary row. Task 0129 corrected the
encoded-zero constant semantics for MOVK, ADDK, and SUBK. Task 0130 corrected
the complete shift family's encodings, SLA overflow, and status masks.
Task 0131 corrected both MOVI widths to preserve C while updating N/Z and
clearing V, and made carry-dependent tests establish their inputs explicitly.
Task 0132 resolved REV's result and EXGPC's next-PC/alignment behavior against
their primary instruction pages. Task 0133 resolved FILL XY's final linear
DADDR representation and W=0 status behavior. Task 0134 corrected SUBXY's
greater-than flags to signed 16-bit XY comparisons. Task 0135 completed the
individual-page N/C/Z/V audit, corrected divide/modulo and odd-result multiply
semantics, completed graphics W=3 V reporting and PIXT XY-to-XY window
handling, and resolved A0009. Task 0136 resolved A0005 by sequencing every
architectural field onto the exact required ascending 16-bit word operations.

## Task index

| ID | Title | Status |
|----|-------|--------|
| 0001 | Add TMS34010_Info reference submodule | complete |
| 0002 | Create project planning and docs scaffolding | complete |
| 0003 | Initial synthesizable core skeleton + smoke test | complete |
| 0004 | PC module + core integration | complete |
| 0005 | Behavioral memory model + fetch-walk test | complete |
| 0006 | A/B register file with shared SP | complete |
| 0007 | ALU + flag generation | complete |
| 0008 | Barrel shifter | complete |
| 0009 | Status register (ST) | complete |
| 0010 | Decode skeleton + full execute cycle | complete |
| 0011 | Wire datapath modules into core | complete |
| 0012 | Implement MOVI IW end-to-end | complete |
| 0013 | Implement MOVI IL end-to-end | complete |
| 0014 | Implement MOVK K, Rd | complete |
| 0015 | Implement ADD Rs, Rd | complete |
| 0016 | Implement SUB Rs, Rd | complete |
| 0017 | Reg-reg logical instructions (AND, ANDN, OR, XOR) | complete |
| 0018 | Implement CMP Rs, Rd | complete |
| 0019 | First branch — JRUC short | complete |
| 0020 | JRcc short conditional (UC, EQ, NE) | complete |
| 0021 | K-form arithmetic (ADDK, SUBK) | complete |
| 0022 | Single-reg unary ops (NEG, NOT) | complete |
| 0023 | Immediate arithmetic IW (ADDI, SUBI, CMPI) | complete |
| 0024 | K-form shifts (RL, SLA, SLL, SRA, SRL) | complete |
| 0025 | Immediate IL batch (ADDI/SUBI/CMPI/ANDI/ORI/XORI) | complete |
| 0026 | MOVE Rs, Rd (register-to-register) | complete |
| 0027 | JRcc unsigned compares (LO, LS, HI, HS) | complete |
| 0028 | NOP (No Operation) | complete |
| 0029 | ADDC / SUBB Rs, Rd (carry-chain reg-reg) | complete |
| 0030 | JRcc condition-code correction + signed compares | complete |
| 0031 | JRcc long form (16-bit displacement) | complete |
| 0032 | JUMP Rs (register-indirect jump) | complete |
| 0033 | DSJ / DSJEQ / DSJNE Rd, Address (decrement-and-jump family) | complete |
| 0034 | JAcc Address (absolute conditional jump) | complete |
| 0035 | DSJS Rd, Address (decrement-and-skip-jump short form) | complete |
| 0036 | ABS / NEGB Rd (complete the unary family) | complete |
| 0037 | BTST K/Rs + per-flag wb_flag_mask refactor | complete |
| 0038 | CLRC / SETC / GETST / PUTST (status-reg ops) | complete |
| 0039 | Shift Rs-form (SLA/SLL/SRA/SRL/RL with Rs amount) | complete |
| 0040 | GETPC / EXGPC / REV (PC + revision register ops) | complete |
| 0041 | LMO Rs, Rd (Leftmost-One priority encoder) | complete |
| 0042 | ST layout finalization (FS0/FE0/FS1/FE1/IE/PBX) | complete |
| 0043 | SETF FS, FE, F (set field-size params) | complete |
| 0044 | SEXT / ZEXT Rd, F (field-size extension) | complete |
| 0045 | EXGF Rd, F (exchange field definition) | complete |
| 0046 | DINT / EINT (interrupt-enable control) | complete |
| 0047 | Memory-write infrastructure + PUSHST | complete |
| 0048 | POPST (PUSHST inverse; first memory-read instr) | complete |
| 0049 | CALL Rs (Call Subroutine Indirect) | complete |
| 0050 | RETS [N] (Return from Subroutine) | complete |
| 0051 | CALLA / CALLR (absolute + relative call) | complete |
| 0052 | RETI + multi-transaction memory FSM       | complete |
| 0053 | TRAP N (3-transaction software interrupt) | complete |
| 0054 | TRAP 0 (special-cased, no pushes)         | complete |
| 0055 | MMTM Rp, list (multi-register push)       | complete |
| 0056 | MMFM Rp, list (multi-register pop)        | complete |
| 0057 | MMTM N flag (sign of 0 - Rp)              | complete |
| 0058 | Fix MOVE Rs,Rd opcode (0x4C00) + cross-file | complete |
| 0059 | MOVE Rs,*Rd / *Rs,Rd (field-32, word-aligned) | complete |
| 0060 | MOVE indirect auto inc/dec (field-32)        | complete |
| 0061 | MOVE *Rs,*Rd indirect-to-indirect (field-32) | complete |
| 0062 | MOVE *Rs+,*Rd+ / -*Rs,-*Rd inc/dec (field-32) | complete |
| 0063 | MOVE @SAddr,Rd / Rs,@DAddr absolute (field-32) | complete |
| 0064 | MOVE Rs,*Rd(off) / *Rs(off),Rd offset (field-32) | complete |
| 0065 | MOVX / MOVY (half-register moves)             | complete |
| 0066 | ADDXY / SUBXY (dual 16-bit XY arithmetic)     | complete |
| 0067 | CMPXY (nondestructive XY compare)            | complete |
| 0068 | HDL coding-guidelines audit + compliance fixes | complete |
| 0069 | word-step / mem-size literals → DATA_WIDTH constants | complete |
| 0070 | CPW (compare point to window) + 3rd regfile read port | complete |
| 0071 | MPYS / MPYU multiply (FS1=32)                | complete |
| 0072 | DIVU unsigned divide + multi-cycle divider   | complete |
| 0073 | MODU unsigned modulo (reuses divider)        | complete |
| 0074 | DIVS / MODS signed divide & modulo           | complete |
| 0075 | MPYS / MPYU variable multiplier width (FS1 != 32) | complete |
| 0076 | sim memory arbitrary bit-field read/write | complete |
| 0077 | field-size-aware MOVE register/indirect | complete |
| 0078 | field-size-aware MOVE offset and absolute forms | complete |
| 0079 | field-size-aware MOVE memory-to-memory | complete |
| 0080 | MOVB (move byte), FS forced to 8 | complete |
| 0081 | I/O register file foundation | complete |
| 0082 | Wire I/O registers into the core memory path | complete |
| 0083 | PIXT linear forms | complete |
| 0084 | CVXYL conversion | complete |
| 0085 | XY-addressed PIXT load/store | complete |
| 0086 | XY-to-XY PIXT memory-to-memory | complete |
| 0087 | FILL L engine | complete |
| 0088 | FILL XY engine | complete |
| 0089 | PIXT transparency | complete |
| 0090 | PIXT plane masking | complete |
| 0091 | PIXT Boolean pixel processing | complete |
| 0092 | PIXT arithmetic pixel processing | complete |
| 0093 | FILL pixel processing | complete |
| 0094 | PIXBLT L,L | complete |
| 0095 | PIXBLT XY variants | complete |
| 0096 | PIXBLT binary-source color expansion | complete |
| 0097 | Standalone video timing generator | complete |
| 0098 | Standalone maskable-interrupt priority encoder | complete |
| 0099 | Standalone DRAM-refresh generator | complete |
| 0100 | Maskable-interrupt entry integration | complete |
| 0101 | Complete JRcc/JAcc arithmetic condition codes | complete |
| 0102 | Interrupt/RETI round-trip integration test | complete |
| 0103 | Nonmaskable interrupt via HSTCTLH | complete |
| 0104 | NMI/maskable-interrupt priority test | complete |
| 0105 | FILL XY window clipping (W=3) | complete |
| 0106 | PIXBLT XY window clipping (W=3) | complete |
| 0107 | FILL XY window miss detection (W=2) | complete |
| 0108 | PIXBLT XY window miss detection (W=2) | complete |
| 0109 | FILL XY window hit detection (W=1) | complete |
| 0110 | PIXBLT XY window hit detection (W=1) | complete |
| 0111 | DRAV, W=0 | complete |
| 0112 | DRAV window checking (W=1/2/3) | complete |
| 0113 | Widen core state enum for LINE | complete |
| 0114 | LINE Bresenham engine, W=0 | complete |
| 0115 | LINE window clipping (W=3) | complete |
| 0116 | LINE window abort modes (W=1/2) | complete |
| 0117 | PIXT XY per-pixel window checking | complete |
| 0118 | Migrate agent guidance and restore local validation entry points | complete |
| 0119 | Establish strict full-regression gate | complete |
| 0120 | Complete multiword MOVB memory-to-memory forms | complete |
| 0121 | Fetch the architectural level-0 reset vector | complete |
| 0122 | Trap illegal opcodes through architectural vector 30 | complete |
| 0123 | Initialize architectural ST on every interrupt entry | complete |
| 0124 | Audit the remaining ISA and system completion gaps | complete |
| 0125 | Correct logical flags and ANDI/ANDNI semantics | complete |
| 0126 | Implement MOVE offset-to-postincrement | complete |
| 0127 | Implement MOVE absolute-to-postincrement | complete |
| 0128 | Implement EMU pin handshake and halt state | complete |
| 0129 | Correct 5-bit constant zero encoding | complete |
| 0130 | Correct shift encodings and status semantics | complete |
| 0131 | Correct MOVI status semantics | complete |
| 0132 | Resolve REV and EXGPC architectural semantics | complete |
| 0133 | Resolve FILL XY DADDR writeback semantics | complete |
| 0134 | Correct SUBXY signed comparison semantics | complete |
| 0135 | Complete the instruction status audit | complete |
| 0136 | Sequence architectural fields onto 16-bit memory words | complete |
| 0137 | Complete interrupt-pending source semantics | complete |
| 0138 | Correct and integrate DRAM refresh semantics | complete |
| 0139 | Integrate internal noninterlaced video timing | complete |
| 0140 | Correct sync and blank interval endpoints | complete |
| 0141 | Integrate DPYADR and screen-refresh scheduling | complete |
| 0142 | Integrate direct host control and halt semantics | complete |
| 0143 | Implement the synchronous host-indirect engine | complete |
| 0144 | Integrate the four-register host port | complete |
| 0145 | Implement specification-priority local-bus arbitration | complete |
| 0146 | Integrate the core memory clients and arbiter | complete |
| 0147 | Implement the original-pin local-bus phase engine | complete |
| 0148 | Integrate the core and local-bus clocks | complete |
| 0149 | Route processor I/O through physical I/O cycles | complete |
| 0150 | Route host-indirect I/O through physical cycles | complete |
| 0151 | Implement physical HOLD/HOLDA bus release | complete |
| 0152 | Implement the shared physical HLDA/EMUA pin | complete |
| 0153 | Implement the asynchronous physical host bus | complete |
| 0154 | Enforce reserved I/O fields and locations | complete |

---

### Task 0001: Add TMS34010_Info reference submodule
Status: complete
Dependencies: none
Acceptance Criteria:
- `third_party/TMS34010_Info` exists as a git submodule.
- `git submodule status` reports the expected pinned commit.
- Reference contents have been inspected and the primary spec documents are identified.
Tests:
- `git submodule status` succeeds.
- Submodule HEAD matches the pinned commit recorded in `.gitmodules` / parent tree.
Docs:
- `docs/architecture.md` records the reference source.
- `docs/assumptions.md` records the spec-source-of-truth decision.
Commit:
- c8db96c

---

### Task 0002: Create project planning and docs scaffolding
Status: complete
Dependencies:
- Task 0001
Acceptance Criteria:
- `tasks.md` exists with current milestone, task list, and acceptance criteria template.
- `changelog.md` exists.
- `docs/architecture.md`, `docs/assumptions.md`, `docs/instruction_coverage.md`,
  `docs/timing_notes.md`, `docs/memory_map.md` exist as honest scaffolds — they
  describe what is *planned* and explicitly mark unimplemented sections.
- `scripts/sim.sh`, `scripts/lint.sh`, `scripts/synth_quartus.sh` exist as
  minimal launchers that locate the toolchain via env or PATH and fail
  clearly otherwise.
- `CLAUDE.md` reflects the actual project conventions (RTL style, spec
  workflow, doc requirements).
- `.gitignore` excludes simulator work directories and synthesis output.
Tests:
- N/A — documentation-only commit. Marked as documentation-only per project rules.
Docs:
- All of the above are themselves the documentation deliverable.
Commit:
- 676bdb6

---

### Task 0003: Initial synthesizable core skeleton + smoke test
Status: complete
Dependencies:
- Task 0002
Acceptance Criteria:
- `rtl/tms34010_pkg.sv` exists with the minimum widths/typedefs the skeleton
  needs (no invented architectural constants).
- `rtl/core/tms34010_core.sv` exists with explicit clock + active-high reset,
  a typed-enum core FSM (`CORE_RESET → CORE_FETCH`), and a clean memory
  request/valid interface stub.
- `sim/tb/tb_smoke.sv` drives reset, observes the FSM leaves `CORE_RESET`,
  and prints `SMOKE: PASS` / `SMOKE: FAIL` with `$finish`.
- `scripts/sim.sh tb_smoke` exits 0 when Questa or ModelSim is on PATH (or
  via `$VLOG`/`$VSIM` env), and exits with a clear "simulator not found"
  message otherwise — without claiming success.
- The skeleton infers no latches, no combinational loops, no `/` or `%`,
  and uses `always_ff` + nonblocking for sequential state and `always_comb`
  + blocking for combinational paths.
Tests:
- `tb_smoke` reaches `SMOKE: PASS` (FSM observed in `CORE_FETCH` within a
  bounded number of cycles after reset deassertion).
Docs:
- `docs/architecture.md` updated with the actual skeleton module list.
- `docs/instruction_coverage.md` unchanged — no instructions yet.
- `changelog.md` updated.
Commit:
- e65f6db

---

### Task 0004: PC module + core integration
Status: complete
Dependencies:
- Task 0003
Spec sources (citation policy A0007):
- `third_party/TMS34010_Info/bibliography/hdl-reimplementation/01-architecture.md`
  §"Datapath summary" — "PC is itself a bit address into instruction
  memory"; "Instructions are 16-bit-aligned half-words … PC … increments
  by 16 per fetch".
- `third_party/TMS34010_Info/bibliography/hdl-reimplementation/11-interrupts-reset.md`
  §"Reset" — reset vector lives in trap table at the top of address
  space (near `0xFFFFFFC0` per the bibliography, exact value pending
  SPVU001A Ch. 13). The reset *sequence* (fetch PC from vector, then
  resume normal fetch) is Phase 8 work.
Acceptance Criteria:
- `rtl/core/tms34010_pc.sv` exists as a parameterized bit-addressed PC
  register: `RESET_VALUE` parameter, `load_en`/`load_value` for absolute
  jump, `advance_en`/`advance_amount` for variable forward advance
  measured in bits. Single `always_ff`, single `always_comb` with safe
  defaults. No `/`, no `%`, no implicit width.
- `rtl/tms34010_pkg.sv` gains `INSTR_WORD_BITS = 6'd16` and a
  `PC_ADVANCE_WIDTH = 8` parameter (so the advance amount can express
  up to 31 bytes / 15 16-bit words per advance, covering 1- to 3-word
  instructions plus headroom).
- `rtl/core/tms34010_core.sv` instantiates the PC, drives `mem_addr`
  from `pc_o`, and asserts `advance_en` with `INSTR_WORD_BITS` when
  `mem_ack` arrives in `CORE_FETCH`. `load_en` is tied 0 (no
  branches/jumps yet).
- `sim/tb/tb_pc.sv` covers: reset value, single load, single advance,
  cumulative advances, load-while-advance precedence (load wins),
  no-op cycles (PC stable when neither `load_en` nor `advance_en`).
- `sim/tb/tb_smoke.sv` still passes after PC integration (no observable
  state change since `mem_ack` is tied 0 in the smoke harness).
- `docs/assumptions.md` gains an entry (A0008) for the reset-vector
  value and reset-fetch sequence deferral.
Tests:
- `scripts/sim.sh tb_pc` → `TEST_RESULT: PASS`.
- `scripts/sim.sh tb_smoke` → `TEST_RESULT: PASS` (regression).
- `scripts/lint.sh` → compile clean.
Docs:
- `docs/architecture.md` — PC row updated to "landed".
- `docs/assumptions.md` — A0008 entry added.
- `changelog.md`, `tasks.md`.
Commit:
- 244864d

---

### Task 0005: Behavioral memory model + fetch-walk test
Status: complete
Dependencies:
- Task 0004
Spec sources:
- `third_party/TMS34010_Info/bibliography/hdl-reimplementation/01-architecture.md`
  §"Datapath summary" — 16-bit-aligned instruction words; PC is bit-
  addressed and increments by 16 per fetch.
Acceptance Criteria:
- `sim/models/sim_memory_model.sv` exists as a non-synthesizable
  behavioral memory: 16-bit-word backing store indexed by
  `mem_addr[IDX_WIDTH+3:4]`, two-state mini-FSM (`MEM_IDLE`/`MEM_ACK`)
  with a one-cycle ack pulse. Lives under `sim/models/` so it is
  never compiled into a synthesis flow.
- The model enforces the request/ack handshake: a new request is only
  accepted when `!mem_ack`, so the producer's "stale `mem_req` on the
  ack cycle" (a property of a synchronous req/valid protocol where
  `mem_req` is combinational from a state register that NBA-updates
  one cycle later) does not retrigger a duplicate latch.
- `sim/tb/tb_fetch_walk.sv` connects core to memory model, preloads
  8 instruction words, watches every ack via an active-region monitor,
  and verifies (a) `mem_addr === pc_o` at each ack, (b) PC sequence is
  `0, 16, 32, ..., 112`, (c) `mem_size === INSTR_WORD_BITS` at each
  ack, (d) `mem_rdata[15:0]` matches the preloaded word, (e)
  `mem_rdata[31:16] === 0` (zero-extension contract), (f) final PC =
  `N*16` after the ack-driven advance commits.
- `scripts/sim.sh` discovers `sim/models/*.sv` automatically.
Tests:
- `scripts/sim.sh tb_fetch_walk` → PASS.
- `scripts/sim.sh tb_smoke` → PASS (regression).
- `scripts/sim.sh tb_pc` → PASS (regression).
- `scripts/lint.sh` → clean.
Docs:
- `docs/architecture.md` — note the memory model substrate.
- `changelog.md`, `tasks.md`.
Commit:
- 2f6bdb9

---

### Task 0006: A/B register file with shared SP
Status: complete
Dependencies:
- Task 0003
Spec source:
- `third_party/TMS34010_Info/bibliography/hdl-reimplementation/03-registers.md`
  §"General-purpose register files A and B":
  - Two banks, 15 32-bit registers each (A0..A14, B0..B14).
  - One shared SP, accessible from both files as A15/B15.
  - All 32 bits.
  - Graphics ops implicitly read the B file (Phase 7 work).
Acceptance Criteria:
- `rtl/core/tms34010_regfile.sv` exists. Storage: 15-entry A array,
  15-entry B array, single SP register. Two read ports (combinational
  / async read for FPGA distributed-RAM friendliness — regfile is
  ~1 Kb so block RAM is overkill). One synchronous write port.
- Selector encoding: 1-bit file select + 4-bit index. Index 4'hF on
  either file routes to the shared SP for both read and write.
- Synchronous active-high reset clears all entries (bounded for-loop,
  fully unrollable, no inferred latches).
- Observability `sp_o` port for testbenches.
- Package typedefs added: `reg_file_t` (enum A/B), `reg_idx_t` (4-bit).
- `sim/tb/tb_regfile.sv` covers reset, isolated A/B writes, read-after-
  write same and different ports, SP aliasing (write A15 → read B15
  returns the value, and `sp_o` matches), file-A and file-B index 15
  both alias to SP.
Tests:
- `scripts/sim.sh tb_regfile` → PASS.
- All previous tests still PASS.
- Lint clean.
Docs:
- `docs/architecture.md` — regfile row → landed.
- `changelog.md`, `tasks.md`.
Commit:
- afc4381

---

### Task 0007: ALU + flag generation
Status: complete
Dependencies:
- Task 0006
Spec sources:
- `third_party/TMS34010_Info/bibliography/hdl-reimplementation/02-instruction-set.md`
  §"Flag effects" (per-instruction flag list in SPVU001A Appendix A is
  authoritative).
- `third_party/TMS34010_Info/bibliography/hdl-reimplementation/03-registers.md`
  §"Status register" (N, C, Z, V from the ALU).
Acceptance Criteria:
- `rtl/core/tms34010_alu.sv` exists as a purely combinational module.
  Operations: ADD, ADDC, SUB, SUBB, CMP, AND, ANDN, OR, XOR, NOT,
  NEG, PASS_A, PASS_B. Output: 32-bit `result` + packed `alu_flags_t`
  (N, C, Z, V).
- One 33-bit adder + one 33-bit subtractor (a + ~b + cin) shared
  across all arithmetic ops — no per-op duplicated adders.
- Logical ops set C = V = 0 per the convention in A0009. Arithmetic
  ops use the standard two's-complement carry/borrow/overflow rules.
- Package gains `alu_op_t` (4-bit enum) and `alu_flags_t` (packed
  struct with n/c/z/v).
- `sim/tb/tb_alu.sv` covers every operation with at least 2-3 vectors,
  including the corner cases: signed-overflow on ADD, borrow on SUB,
  Z on ADD producing 0 via carry, V on NEG of MIN_INT.
Tests:
- `scripts/sim.sh tb_alu` → PASS.
- All previous tests still PASS.
- Lint clean.
Docs:
- `docs/architecture.md` — ALU row → landed.
- `docs/assumptions.md` — A0009 entry added.
- `changelog.md`, `tasks.md`.
Commit:
- cae8f71

---

### Task 0008: Barrel shifter
Status: complete
Dependencies:
- Task 0007
Spec source:
- `third_party/TMS34010_Info/bibliography/hdl-reimplementation/01-architecture.md`
  §"Top-level blocks" — "32-bit barrel shifter; the shifter is critical
  for field operations and pixel shifts".
- `02-instruction-set.md` lists SLA, SLL, SRA, SRL, RL as shift/rotate
  primitives.
Acceptance Criteria:
- `rtl/core/tms34010_shifter.sv` exists as a purely combinational
  module. Ops: SLL, SLA (alias of SLL for now), SRL, SRA, RL, RR.
  5-bit shift amount. Output: 32-bit result + `alu_flags_t` with V
  tied 0.
- amount==0 identity (result = a, C = 0).
- C semantics: SLL/SLA/RL use the MSB-departing bit `a[32 - amount]`;
  SRL/SRA/RR use the LSB-departing bit `a[amount - 1]`.
- Package: `shift_op_t` (3-bit enum) and `SHIFT_AMOUNT_WIDTH = 5`.
- `sim/tb/tb_shifter.sv` covers each op with identity (amount=0),
  small shift, large shift, rotate-by-16 half-word swap, sign-
  extension on SRA, MSB/LSB carry capture.
Tests:
- `scripts/sim.sh tb_shifter` → PASS.
- All previous tests still PASS.
- Lint clean.
Docs:
- `docs/architecture.md` — shifter row → landed.
- `changelog.md`, `tasks.md`.
Commit:
- 08fae79

---

### Task 0009: Status register (ST)
Status: complete
Dependencies:
- Task 0007 (ALU produces alu_flags_t)
Spec source:
- `third_party/TMS34010_Info/bibliography/hdl-reimplementation/03-registers.md`
  §"Status register".
Acceptance Criteria:
- `rtl/core/tms34010_status_reg.sv` exists. 32-bit ST. Update priority:
  reset → 0, then `st_write_en` (full POPST-style write), then
  `flag_update_en` (selective N/C/Z/V update via `alu_flags_t`).
- Bit positions parameterized as `ST_N_BIT/C/Z/V` in
  `tms34010_pkg.sv` (placeholders pending SPVU001A; documented in
  assumption A0010).
- Named flag outputs: `n_o`, `c_o`, `z_o`, `v_o`.
- `sim/tb/tb_status_reg.sv` covers reset, selective flag update,
  full write, non-flag bit preservation, st_write-wins-over-flag-
  update.
Tests:
- `scripts/sim.sh tb_status_reg` → PASS.
- All previous tests still PASS.
- Lint clean.
Docs:
- `docs/architecture.md` — ST row → landed.
- `docs/assumptions.md` — A0010 entry added.
- `changelog.md`, `tasks.md`.
Commit:
- 24edaee

---

### Task 0010: Decode skeleton + full execute cycle
Status: complete
Dependencies:
- Task 0005 (memory model + fetch substrate)
Spec sources:
- `third_party/TMS34010_Info/bibliography/hdl-reimplementation/02-instruction-set.md`
  §"Encoding shape" (16-bit-aligned half-words; SPVU004 opcode chart
  is authoritative; decode space is dense, no top-bits-give-class).
Acceptance Criteria:
- `rtl/core/tms34010_decode.sv` exists as a purely combinational
  decoder. Phase 3 skeleton always flags ILLEGAL.
- Package gains `instr_word_t`, `instr_class_t` (currently
  `INSTR_ILLEGAL` only), `decoded_instr_t` (`{illegal, iclass}`),
  `INSTR_WORD_WIDTH = 16`.
- Core wiring: latch `instr_word_q` from `mem_rdata[15:0]` on
  `mem_ack` in CORE_FETCH; combinational decode runs over
  `instr_word_q`; FSM now walks `FETCH → DECODE → EXECUTE →
  WRITEBACK → FETCH` (5 cycles per instruction in the current
  placeholder loop, was 3 before).
- Sticky `illegal_opcode_o` observability output: latches on the
  first CORE_DECODE cycle where `decoded.illegal == 1`, cleared
  only by reset.
- `sim/tb/tb_illegal_opcode.sv` verifies the end-to-end path.
- `sim_memory_model.sv` deterministic-init: backing store zeroed in
  an `initial` block so unpreloaded addresses read as 0, not X.
Tests:
- `scripts/sim.sh tb_illegal_opcode` → PASS.
- All previous tests still PASS (8/8).
- Lint clean.
Docs:
- `docs/architecture.md` — decode row → skeleton landed.
- `docs/instruction_coverage.md` — note that Phase 3 skeleton routes
  every encoding to ILLEGAL; first real instruction lands Task 0011.
- `changelog.md`, `tasks.md`.
Commit:
- a959c28

---

### Task 0011: Wire datapath modules into core
Status: complete
Dependencies:
- Task 0010 (decode skeleton already wired)
- Tasks 0006, 0007, 0009 (regfile, ALU, ST modules ready to instantiate)
Acceptance Criteria:
- `rtl/core/tms34010_core.sv` instantiates `tms34010_regfile`,
  `tms34010_alu`, and `tms34010_status_reg`. The shifter is NOT
  wired yet (no shift instruction lands until shifts are added).
- Datapath connections: ALU `result` → regfile `wr_data` port;
  ALU `flags` → status-register `flags_in` port; status-register
  `c_o` → ALU `cin`. ALU `a` and `b` come from the regfile's two
  read ports.
- All "go" signals (`rf_wr_en`, `st_flag_update_en`, `st_write_en`)
  tied 0 — no observable behavior change in this commit.
- Control selectors (`rf_rs*_idx/file`, `rf_wr_idx/file`, `alu_op`,
  `st_write_data`) tied to safe defaults (file A, index 0,
  `ALU_OP_PASS_A`, 0).
- Existing 8 testbenches all PASS with no test modifications.
- Lint clean.
Tests:
- Full regression: 8/8 PASS.
- Lint clean.
Docs:
- `docs/architecture.md` — module-instantiation comment updated.
- `changelog.md`, `tasks.md`.
Commit:
- 8f8a1ec

---

### Task 0012: Implement MOVI IW end-to-end
Status: complete
Dependencies:
- Task 0011 (datapath wired)
Spec sources:
- `third_party/TMS34010_Info/tools/assembler/TMS34010_Assembly_Language_Tools_Users_Guide_SPVU004.pdf`
  — assembler listings provide ground-truth encodings; the description
  "Move Immediate - Short or Long" provides the semantics.
  Captured in `docs/assumptions.md` A0011 (flag policy) and A0012
  (encoding).
- `third_party/TMS34010_Info/bibliography/hdl-reimplementation/02-instruction-set.md`
  §"Encoding shape" — long-immediate forms are 16-bit opcode followed
  by 16 or 32 bits of immediate data.
Acceptance Criteria:
- Decoder recognizes the MOVI IW encoding (top 10 bits = 0x027,
  bit[5]=0). Returns `iclass=INSTR_MOVI_IW`, destination from bits
  [4:0], `needs_imm16=1`, `imm_sign_extend=1`, `alu_op=PASS_B`,
  `wb_reg_en=1`, `wb_flags_en=1`.
- Core FSM adds CORE_FETCH_IMM_LO (and reserves CORE_FETCH_IMM_HI
  for IL). Latches `imm_lo_q` on mem_ack, advances PC by 16 bits.
- ALU operand B selects `imm32` (sign-extended `imm_lo_q`) when the
  decoded class is `INSTR_MOVI_IW`. Result routed to regfile write
  port; flags routed to ST flag-update port. Writes gated by
  `state_q == CORE_WRITEBACK` and the corresponding decoded `wb_*_en`.
- `sim/tb/tb_movi.sv` exercises 5 MOVI IW instructions covering both
  files, positive/zero/negative immediates, and verifies (a) each
  destination register holds the sign-extended value via
  hierarchical reference, (b) ST flags after the last MOVI match the
  expected N/Z/C/V, (c) `illegal_opcode_o` stays 0 during the valid
  program window.
- Full regression: 9/9 PASS; lint clean.
Tests:
- `scripts/sim.sh tb_movi` → PASS.
- All previous 8 tests still PASS.
- Lint clean.
Docs:
- `docs/architecture.md` — decode row updated.
- `docs/instruction_coverage.md` — first real row (MOVI IW) added.
- `docs/assumptions.md` — A0011 (flag policy), A0012 (encoding).
- `changelog.md`, `tasks.md`.
Commit:
- e1ff18e

---

### Task 0013: Implement MOVI IL end-to-end
Status: complete
Dependencies:
- Task 0012 (MOVI IW; FSM IMM_HI state already in place; imm32 assembly
  already handles needs_imm32)
Spec sources:
- A0012 in `docs/assumptions.md` — encoding for MOVI IW/IL.
- SPVU004 description: "In the long form, the operand is a 32-bit
  signed value."
Acceptance Criteria:
- Decoder adds an arm matching `top10 == 0x027 && instr[5] == 1`.
  Sets `iclass=INSTR_MOVI_IL`, `needs_imm32=1`, `imm_sign_extend=0`,
  `alu_op=PASS_B`, `wb_reg_en=1`, `wb_flags_en=1`.
- No core changes required — the FETCH_IMM_LO → FETCH_IMM_HI path,
  imm32 assembly, and writeback wiring all already work.
- `sim/tb/tb_movi_il.sv` runs 5 MOVI IL instructions with immediates
  the IW form cannot encode (upper 16 bits ≠ sign-extension of
  lower). Verifies destination registers via hierarchical reference.
- Full regression: 10/10 PASS; lint clean.
Tests:
- `scripts/sim.sh tb_movi_il` → PASS.
- All previous 9 tests still PASS.
- Lint clean.
Docs:
- `docs/instruction_coverage.md` — MOVI IL row → implemented.
- `changelog.md`, `tasks.md`.
Commit:
- aebf99a

---

### Task 0014: Implement MOVK K, Rd
Status: complete
Dependencies:
- Task 0011 (datapath wired)
Spec sources:
- SPVU004 §"Move Constant - 5 Bits" plus assembler listings
  `MOVK 1,A12 → 0x182C` and `MOVK 8,B1 → 0x1911` (captured in A0013).
Acceptance Criteria:
- Decoder recognizes `bits[15:10] == 0x06`; sets `iclass=INSTR_MOVK`,
  extracts K from bits[9:5] into `decoded.k5`, sets `alu_op=PASS_B`,
  `wb_reg_en=1`, `wb_flags_en=0` (MOVK does NOT affect ST).
- Package: `INSTR_MOVK` added to `instr_class_t`; `k5` field added
  to `decoded_instr_t` (5 bits).
- Core: alu_b mux gains an arm for INSTR_MOVK that zero-extends
  `decoded.k5` to DATA_WIDTH.
- `sim/tb/tb_movk.sv` exercises K=0, K=1, K=16, K=31 across A and B
  files. Verifies both regfile content AND that ST is unchanged
  from reset zeros.
- Encoding helper sanity-checked against the two SPVU004 listings.
- Full regression: 11/11 PASS; lint clean.
Tests:
- `scripts/sim.sh tb_movk` → PASS.
- All previous 10 tests still PASS.
- Lint clean.
Docs:
- `docs/instruction_coverage.md` — MOVK row added.
- `docs/assumptions.md` — A0013 added.
- `changelog.md`, `tasks.md`.
Commit:
- 2c351a3

---

### Task 0015: Implement ADD Rs, Rd
Status: complete
Dependencies:
- Task 0011 (datapath wired)
Spec sources:
- SPVU001A Appendix A page A-14 (A0014, A0015).
Acceptance Criteria:
- Decoder recognizes `bits[15:9] == 7'b0100000`; sets
  `iclass=INSTR_ADD_RR`, `rs_idx=instr[8:5]`, `rd_file=instr[4]`,
  `rd_idx=instr[3:0]`, `alu_op=ALU_OP_ADD`, both wb enables.
- Package: `INSTR_ADD_RR` added to `instr_class_t`; `rs_idx` field
  added to `decoded_instr_t`.
- Core: regfile rs1 reads Rs and rs2 reads Rd. Both use
  `decoded.rd_file` for the file bit (TMS34010 architectural
  constraint).
- `sim/tb/tb_add_rr.sv` covers four cases including signed overflow
  and unsigned wrap; encoding helper independently re-derives the
  hand-decoded `ADD A1,A2 → 0x4022`.
- Full regression: 12/12 PASS; lint clean.
Tests:
- `scripts/sim.sh tb_add_rr` → PASS.
- All previous 11 tests still PASS.
- Lint clean.
Docs:
- `docs/instruction_coverage.md` — ADD Rs,Rd row added.
- `docs/assumptions.md` — A0014 (chart source) and A0015 (ADD
  encoding) added.
- `changelog.md`, `tasks.md`.
Commit:
- 4e7cacb

---

### Task 0016: Implement SUB Rs, Rd
Status: complete
Dependencies:
- Task 0015 (ADD; same encoding shape, same datapath wiring approach)
Spec source: SPVU001A A-14 chart row `0100 010S SSSR DDDD`.
Acceptance Criteria:
- Decoder arm for `top7 == 7'b0100010` setting `iclass=INSTR_SUB_RR`,
  `alu_op=ALU_OP_SUB`, both wb enables.
- Core: alu_a mux swaps to `rf_rs2_data` (Rd) for SUB so ALU's
  `a - b` produces `Rd - Rs` matching the spec.
- `sim/tb/tb_sub_rr.sv`: five cases (simple, equal, borrow,
  signed overflow, B-file).
- Full regression: 13/13 PASS; lint clean.
Tests: tb_sub_rr PASS; full regression PASS; lint clean.
Docs: instruction_coverage.md, changelog.md, tasks.md.
Commit:
- ac0dbbf

---

### Task 0017: Reg-reg logical instructions (AND, ANDN, OR, XOR)
Status: complete
Dependencies:
- Tasks 0015/0016 (reg-reg shape, operand-swap pattern from SUB).
Spec source: SPVU001A A-14 chart rows for AND/ANDN/OR/XOR.
Acceptance Criteria:
- Four new decoder arms with 7-bit prefixes 7'b0101_000..011.
  iclass enum values INSTR_AND_RR / ANDN_RR / OR_RR / XOR_RR.
- alu_op selects ALU_OP_{AND,ANDN,OR,XOR}. ANDN reuses the SUB
  operand-swap (alu_a=Rd, alu_b=Rs) so the ALU's `a & ~b` produces
  the spec-mandated `Rd & ~Rs`.
- `sim/tb/tb_logical_rr.sv`: characteristic patterns for each op,
  encoder cross-checked against `XOR A0,A0=0x5600`.
- Full regression: 14/14 PASS; lint clean.
Tests: tb_logical_rr PASS; full regression PASS; lint clean.
Docs: instruction_coverage.md (4 rows), changelog.md, tasks.md.
Commit:
- e13e6a4

---

### Task 0018: Implement CMP Rs, Rd
Status: complete
Dependencies: Task 0016 (SUB infrastructure: alu_op CMP, operand-swap mux).
Spec source: SPVU001A A-14 chart row `0100 100S SSSR DDDD`.
Acceptance Criteria:
- Decoder arm `top7 == 7'b0100100`; `iclass = INSTR_CMP_RR`;
  `alu_op = ALU_OP_CMP`; `wb_reg_en = 0`; `wb_flags_en = 1`.
- Core: alu_a/b muxes add INSTR_CMP_RR to the SUB-style swap group.
- `sim/tb/tb_cmp_rr.sv` confirms Rd untouched after a CMP and the
  flags exactly match an equivalent SUB.
- Full regression: 15/15 PASS; lint clean.
Tests: tb_cmp_rr PASS; full regression PASS; lint clean.
Docs: instruction_coverage.md (CMP row), changelog.md, tasks.md.
Commit:
- 4ba4171

---

### Task 0019: First branch — JRUC short
Status: complete
Dependencies:
- Task 0011 (PC module instantiated in core but with load_en tied 0).
Spec sources:
- SPVU001A A-14 chart row `JRcc Address 1100 code xxxx xxxx`.
- SPVU001A Table 12-8 (cc=0000 = UC).
- A0016 (target math verified against SPVU004 assembler listing).
Acceptance Criteria:
- Decoder recognizes `instr[15:8] == 8'hC0 && instr[7:0] != 8'h00 &&
  instr[7:0] != 8'h80`. Returns `iclass=INSTR_JRUC_SHORT`,
  `wb_reg_en=0`, `wb_flags_en=0`.
- Core computes `branch_target_short = pc_value +
  $signed({instr[7:0], 4'h0})` combinationally.
- Core drives `pc_load_en=1`, `pc_load_value=branch_target_short`
  during `CORE_WRITEBACK` when `iclass == INSTR_JRUC_SHORT`.
- `sim/tb/tb_jruc_short.sv` proves the branch took (destination
  register holds landing-site value, not skipped-instruction value).
- Full regression: 16/16 PASS; lint clean.
Tests: tb_jruc_short PASS; full regression PASS; lint clean.
Docs: instruction_coverage.md, assumptions.md A0016, changelog.md, tasks.md.
Commit:
- dc01463

---

### Task 0020: JRcc short — conditional branches (UC, EQ, NE)
Status: complete
Dependencies: Task 0019 (PC load_en path + branch_target_short already
  computed combinationally).
Spec source: SPVU001A Table 12-8 (subset verified per A0017).
Acceptance Criteria:
- Refactor: `INSTR_JRUC_SHORT` replaced with `INSTR_JRCC_SHORT`;
  `branch_cc` (4 bits) added to `decoded_instr_t`. Package gets
  `CC_UC/EQ/NE` constants.
- Decoder accepts the three verified cc values; other cc on the
  JRcc shape falls through to ILLEGAL.
- Core gains combinational `branch_taken` evaluator switching on
  `decoded.branch_cc` against ST flags. PC load only fires when
  `branch_taken=1` in `CORE_WRITEBACK`.
- `sim/tb/tb_jrcc_short.sv` covers JREQ taken, JRNE taken, JREQ
  not-taken. tb_jruc_short continues to verify the UC path.
- Full regression: 17/17 PASS; lint clean.
Tests: tb_jrcc_short PASS; full regression PASS; lint clean.
Docs: instruction_coverage.md, assumptions.md A0017, changelog.md, tasks.md.
Commit:
- 4c5e69a

---

### Task 0021: K-form arithmetic (ADDK, SUBK)
Status: complete
Dependencies: Task 0014 (MOVK k5 infrastructure), Task 0016 (SUB swap pattern).
Spec source: SPVU001A A-14 chart rows for ADDK/SUBK; A0018 for K=0 interpretation.
Acceptance Criteria:
- Decoder arms for `top6 == 6'b000100` (ADDK) and `6'b000101` (SUBK).
- `decoded.k5` populated from `instr[9:5]`; `decoded.rd_file/idx` from
  `instr[4:0]`. alu_op = ADD / SUB. wb_reg_en = 1, wb_flags_en = 1.
- Core's alu_a/b muxes route Rd → alu_a and zero-extended K → alu_b
  for both ADDK and SUBK (joining the existing swap group).
- `sim/tb/tb_addk_subk.sv` covers increment/decrement, max-K,
  unsigned-wrap, zero-result, and a B-file case. Encoder verified
  against three hand-decoded encodings.
- A0018 added documenting the literal-K choice and flagging the
  unresolved K=0 → 32 hypothesis.
- Full regression: 18/18 PASS; lint clean.
Tests: tb_addk_subk PASS; full regression PASS; lint clean.
Docs: instruction_coverage.md (ADDK + SUBK rows), assumptions.md A0018,
  changelog.md, tasks.md.
Commit:
- f286298

---

### Task 0022: Single-reg unary ops (NEG, NOT)
Status: complete
Dependencies: Task 0007 (ALU already has NEG and NOT ops).
Spec source: SPVU001A A-14 unary chart rows.
Acceptance Criteria:
- Decoder recognizes the unary family by `instr[15:7] == 9'b000000111`.
  Sub-op `instr[6:5]`: 01 = NEG, 11 = NOT. ABS (00) and NEGB (10)
  fall through to ILLEGAL (deferred).
- INSTR_NEG and INSTR_NOT added to iclass enum; widened to 5 bits.
- Core: alu_a routes `rf_rs2_data` (Rd value) for both NEG and NOT.
- `sim/tb/tb_neg_not.sv` covers NEG of 5, NEG of 0, NEG of MIN_INT
  (V-flag), NOT of a mixed pattern, NOT of 0, NOT of -1 in B file.
- Full regression: 19/19 PASS; lint clean.
Tests: tb_neg_not PASS; full regression PASS; lint clean.
Docs: instruction_coverage.md (NEG + NOT rows + ABS/NEGB placeholders),
  changelog.md, tasks.md.
Commit:
- 7b9135d

---

### Task 0023: Immediate arithmetic IW (ADDI, SUBI, CMPI)
Status: complete
Dependencies: Task 0012 (MOVI IW IMM_LO fetch infra), Task 0018 (CMP wb_reg_en=0 pattern).
Spec source: SPVU001A A-14 chart rows for ADDI/SUBI/CMPI IW.
Acceptance Criteria:
- Three new INSTR_*_IW enum values (ADDI/SUBI/CMPI).
- Decoder grows a `top11` view; three new arms matching 11-bit prefixes:
  ADDI=11'b0000_1011_000, SUBI=11'b0000_1011_111, CMPI=11'b0000_1011_010.
- All three set needs_imm16=1, imm_sign_extend=1.
- alu_a routes Rd via the swap group; alu_b routes imm32 via the
  MOVI-IW arm.
- CMPI has wb_reg_en=0 (same as CMP Rs, Rd).
- `sim/tb/tb_immi_iw.sv` covers add-positive, sub-to-zero, add-
  negative-immediate (verifies sign-extension), CMPI equal, B-file
  add.
- Full regression: 20/20 PASS; lint clean.
Tests: tb_immi_iw PASS; full regression PASS; lint clean.
Docs: instruction_coverage.md (3 rows), changelog.md, tasks.md.
Commit:
- 574ed33

---

### Task 0024: K-form shifts (RL, SLA, SLL, SRA, SRL)
Status: complete
Dependencies: Task 0008 (shifter module), Task 0011 (datapath wired).
Spec source: SPVU001A A-14 chart rows for shift K-forms; A0019 for K
  treatment.
Acceptance Criteria:
- Five new INSTR_*_K enum values.
- Decoder: five new top6 patterns matching `001000..001100`.
- `decoded_instr_t` gains `shift_op` (shift_op_t) and `use_shifter`
  (bool).
- Core: shifter instantiated; result-data and flag-input muxes
  select between ALU and shifter outputs based on `use_shifter`.
- `sim/tb/tb_shift_k.sv` covers each op with characteristic patterns
  (sign-extension, logical-vs-arithmetic, rotate half-word swap, B
  file). Encoders verified against hand-decoded 0x2020 / 0x3200.
- A0019 added documenting K=0 literal interpretation and deferred
  K=0 → 32 hypothesis.
- Full regression: 21/21 PASS; lint clean.
Tests: tb_shift_k PASS; full regression PASS; lint clean.
Docs: instruction_coverage.md (5 rows), assumptions.md A0019,
  changelog.md, tasks.md.
Commit:
- 6a107ef

---

### Task 0025: Immediate IL batch (ADDI/SUBI/CMPI/ANDI/ORI/XORI)
Status: complete
Dependencies: Task 0013 (MOVI IL IMM_HI fetch infra).
Spec source: SPVU001A A-14 chart rows for each IL-form.
Acceptance Criteria:
- Six new INSTR_*_IL enum values.
- Decoder: six new top11 patterns. ADDI/CMPI/ANDI/ORI/XORI share
  base prefix 0000_1011_XXX; SUBI IL has its own base 0000_1101_000.
- All set needs_imm32=1 (use MOVI IL fetch path).
- alu_a and alu_b muxes extended with all six new iclasses.
- CMPI IL uses wb_reg_en=0.
- `sim/tb/tb_immi_il.sv` covers all six with characteristic 32-bit-
  immediate cases. Encoder verified against 0x0B20 (ADDI IL,A0)
  and 0x0D00 (SUBI IL,A0).
- Full regression: 22/22 PASS; lint clean.
Tests: tb_immi_il PASS; full regression PASS; lint clean.
Docs: instruction_coverage.md (6 rows), changelog.md, tasks.md.
Commit:
- 61c608f

---

### Task 0026: MOVE Rs, Rd (register-to-register)
Status: complete
Dependencies: Task 0011 (datapath wired).
Spec source: SPVU001A A-14 chart row for MOVE Rs, Rd.
Acceptance Criteria:
- INSTR_MOVE_RR enum value.
- Decoder arm `top6 == 6'b100100`. F bit at [9] ignored (A0020).
- alu_op = PASS_A (alu_a routes rf_rs1_data which is Rs).
- wb_reg_en = 1, wb_flags_en = 1 (N/Z from result per A0009).
- `sim/tb/tb_move_rr.sv` covers four cases.
- Full regression: 23/23 PASS; lint clean.
- Documentation: A0020 added for the F-bit deferral.
Tests: tb_move_rr PASS; full regression PASS; lint clean.
Docs: instruction_coverage.md, assumptions.md A0020, changelog.md, tasks.md.
Commit:
- 95e0a29

---

### Task 0027: JRcc unsigned compares (LO, LS, HI, HS)
Status: complete
Dependencies: Task 0020 (JRcc framework).
Spec source: SPVU001A Table 12-8 (universally defined codes; less
  ambiguous than the signed compares).
Acceptance Criteria:
- Four new CC_* parameters in the package: CC_LO=0001, CC_LS=0010,
  CC_HI=0011, CC_HS=1001.
- Decoder accepts all four; the existing list-of-allowed-cc-values
  expands.
- Core's branch_taken evaluator computes each condition from ST flags.
- `sim/tb/tb_jrcc_unsigned.sv` covers each cc's take and skip arms,
  using a "sentinel register" pattern so the test cleanly
  distinguishes "branch took" from "branch did not take".
- Full regression: 24/24 PASS; lint clean.
Tests: tb_jrcc_unsigned PASS; full regression PASS; lint clean.
Docs: instruction_coverage.md (JRcc row updated), changelog.md, tasks.md.
Commit:
- 1addcc2

---

### Task 0028: NOP (No Operation)
Status: complete
Dependencies:
- Task 0010 (decode skeleton; FSM walks FETCH→DECODE→EXECUTE→WRITEBACK
  → FETCH with default writeback gates).
Spec source: SPVU001A §"NOP" page 12-170 plus instruction-summary table
  on the same page (A0021). Encoding = `0000 0011 0000 0000` = `0x0300`.
Acceptance Criteria:
- `INSTR_NOP` added to `instr_class_t` enum (5'd31).
- Decoder recognizes the single fixed encoding `0x0300` and returns
  `iclass = INSTR_NOP`, `wb_reg_en = 0`, `wb_flags_en = 0`, no
  needs_imm*.
- No core changes required — defaults handle "valid but no datapath
  action"; PC advance comes for free via the existing FETCH-ack pulse.
- `sim/tb/tb_nop.sv` validates: NOP encoding helper = 0x0300; A0
  retains the MOVI value across NOP; B5 holds the post-NOP MOVK value
  (proves PC advanced through NOP); ST.N and ST.Z preserved across
  NOP+MOVK (proves NOP did not update flags); `illegal_opcode_o == 0`
  (NOP not flagged). Memory pre-filled with NOP so end-of-program
  doesn't trip the illegal latch — also exercises NOP many more times
  as a bonus.
- A0021 documents the encoding source and the distinction from the
  unary family (ABS A0 = `0x0380`, not `0x0300`).
- Full regression: clean on the testbenches that pass under both
  Questa and Verilator; lint clean.
Tests: tb_nop PASS; full regression PASS; lint clean.
Docs: instruction_coverage.md (NOP row), assumptions.md A0021,
  changelog.md, tasks.md.
Commit:
- 0288d0f

---

### Task 0029: ADDC / SUBB Rs, Rd (carry-chain reg-reg arithmetic)
Status: complete
Dependencies:
- Task 0015/0016 (reg-reg shape + ALU has ADDC/SUBB ops + cin wired
  from st_c + SUB-style operand swap pattern available).
Spec source: SPVU001A page 12-37 (ADDC), page 12-248 (SUBB), plus the
  instruction-summary table. Encodings `0100 001S SSSR DDDD` (ADDC)
  and `0100 011S SSSR DDDD` (SUBB). A0022 captures the carry/borrow
  semantics and the use of the spec's worked examples as test vectors.
Acceptance Criteria:
- `instr_class_t` widened from 5 to 6 bits to make room past
  INSTR_NOP (5'd31). All existing enumerators kept their integer
  values; new entries are INSTR_ADDC_RR = 6'd32 and
  INSTR_SUBB_RR = 6'd33.
- Decoder: two new arms with 7-bit prefixes `7'b0100_001` (ADDC) and
  `7'b0100_011` (SUBB), each setting `alu_op = ALU_OP_{ADDC,SUBB}`,
  `wb_reg_en = 1`, `wb_flags_en = 1`.
- Core: SUBB joins the alu_a / alu_b operand-swap groups (alu_a = Rd,
  alu_b = Rs) so the ALU computes `Rd - Rs - cin`. ADDC uses the
  default routing because the operation is commutative on its
  register operands.
- `sim/tb/tb_addc_subb.sv` covers five cases landing in distinct
  destinations: ADDC C=0; ADDC C=1; SUBB C=0; SUBB C=1; and the
  SPVU001A page 12-248 row 7 signed-overflow vector
  (`0x7FFFFFFE - 0xFFFFFFFE` with C=0 → `0x80000000`, NCZV=1101).
  Final ST is checked against the spec NCZV row. Memory is pre-filled
  with NOP so end-of-program stays valid.
- A0022 records the semantics and test-vector source.
- Full Verilator regression of the 13 testbenches that already pass
  cleanly under Verilator: 13/13 PASS. RTL lint clean. Questa
  regression to be run on the Windows dev box.
Tests: tb_addc_subb PASS; the previous Verilator-clean regression set
  still PASS; lint clean.
Docs: instruction_coverage.md (ADDC + SUBB rows), assumptions.md
  A0022, changelog.md, tasks.md.
Commit:
- ccf6450

---

### Task 0030: JRcc condition-code correction + signed compares
Status: complete
Dependencies:
- Task 0027 (unsigned-compare JRcc framework).
Spec source: SPVU001A Table 12-8, re-extracted with `pdftotext -layout`
  from the long-form JRcc page (page 12-96). A0023 captures the
  corrected table; A0017 marked superseded.
Acceptance Criteria:
- Recognize and correct the EQ/NE encoding bug introduced in Task
  0020 / A0017: `CC_EQ` from `4'b0100` → `4'b1010`, `CC_NE` from
  `4'b0111` → `4'b1011`. The original guesses turned out to be the
  signed-compare LT and GT codes, not EQ/NE.
- Add the four signed-compare cc parameters: `CC_LT = 4'b0100`,
  `CC_GE = 4'b0101`, `CC_LE = 4'b0110`, `CC_GT = 4'b0111`.
- Decoder accepts all 11 verified cc values (UC, LO, LS, HI, LT, GE,
  LE, GT, HS, EQ, NE); other JRcc-shape codes still fall through to
  ILLEGAL (defensive).
- Core's `branch_taken` evaluator gains four new arms with the
  standard signed-compare logic: LT = `N^V`; GE = `!(N^V)`;
  LE = `(N^V) | Z`; GT = `!(N^V) & !Z`.
- `tb_jrcc_short.sv` sanity hex-constants updated from `0xC405` /
  `0xC705` → `0xCA05` / `0xCB05` for JREQ/JRNE +5. The
  encoding helper itself composes the cc by name and tracks the
  package change automatically.
- `tb_jrcc_signed.sv` added: 8 scenarios spanning all 4 signed cc's
  in both directions (take + skip), using the sentinel-register
  pattern from `tb_jrcc_unsigned.sv`.
- A0023 added (full corrected cc table). A0017 marked superseded but
  preserved for historical context. A0009-style lesson about
  `pdftotext -layout` on charts cross-referenced.
- Full Verilator regression of 24 testbenches that pass cleanly under
  Verilator: 24/24 PASS. Lint clean.
Tests: tb_jrcc_signed PASS; tb_jrcc_short/unsigned/jruc_short PASS;
  the previously Verilator-clean regression set still PASS; lint clean.
Docs: instruction_coverage.md (JRcc row updated to 11 cc codes),
  assumptions.md (A0023 added, A0017 superseded), changelog.md,
  tasks.md.
Commit:
- 61c5b1c

---

### Task 0031: JRcc long form (16-bit displacement)
Status: complete
Dependencies:
- Task 0030 (cc encoding fix + signed compares).
- Tasks 0012/0013 (CORE_FETCH_IMM_LO path; needs_imm16 already wired
  for MOVI IW and IW-immediate arithmetic).
Spec source: SPVU001A page 12-96 ("Jump Relative Conditional - ±32K
  Words"), referring to the same Table 12-8 the short form uses.
Acceptance Criteria:
- INSTR_JRCC_LONG added to instr_class_t (6'd34).
- Decoder recognizes JRCC-shape encodings where the opcode word's
  low byte is exactly `0x00` (the long-form marker) and the cc field
  is one of the 11 recognized codes from A0023. Sets
  `iclass = INSTR_JRCC_LONG`, `needs_imm16 = 1`, `branch_cc = cc`,
  `wb_reg_en = 0`, `wb_flags_en = 0`. The absolute-form marker
  (low byte = `0x80`) remains deferred.
- Core gains a combinational `branch_target_long = pc_value +
  sign_extend({imm_lo_q, 4'h0})`. The PC at CORE_WRITEBACK already
  reflects both fetches (opcode + disp), so `pc_value` is the
  spec's PC' — same target formula shape as the short form.
- PC-load mux extended with an INSTR_JRCC_LONG arm gated by
  `branch_taken`.
- `sim/tb/tb_jrcc_long.sv` covers four scenarios: JRUC long taken
  with small positive disp; JREQ long taken via CMPI Z=1; JREQ long
  NOT taken via CMPI Z=0; JRUC long with a larger positive disp
  (+64 words) that exercises the high byte of the disp word. Memory
  pre-filled with NOP so end-of-program doesn't trip
  `illegal_opcode_o`.
- Verilator regression of the 25 Verilator-friendly testbenches:
  25/25 PASS. Lint clean.
Tests: tb_jrcc_long PASS; the existing Verilator-clean regression
  set still PASS; lint clean.
Docs: instruction_coverage.md (new JRcc-long row), changelog.md,
  tasks.md.
Commit:
- 355dad5

---

### Task 0032: JUMP Rs (register-indirect jump)
Status: complete
Dependencies:
- Task 0019 (PC load_en path); Task 0011 (regfile rs1 port).
Spec source: SPVU001A page 12-98 ("Jump Indirect") + summary table.
  Encoding `0000 0001 011R DDDD`; top11 = 11'b00000001_011 = 0x00B.
Acceptance Criteria:
- INSTR_JUMP_RS added to instr_class_t (6'd35).
- Decoder recognizes the top11 prefix; `decoded.rd_file` and
  `decoded.rs_idx` populated so the regfile's rs1 port reads Rs.
  No writeback enables; no status update.
- Core's PC-load mux gains an INSTR_JUMP_RS arm that unconditionally
  loads PC with `{rf_rs1_data[31:4], 4'h0}` — Rs with the bottom
  4 bits forced to 0 for word alignment.
- `sim/tb/tb_jump_rs.sv` covers two scenarios: aligned target
  (A-file Rs holding a word-aligned bit-address); messy LSBs
  (B-file Rs with bottom nibble = 0xF, target should land at the
  aligned position anyway). Plus a sentinel-untouched check
  confirming neither fall-through MOVI ran, and the standard
  illegal-flag check (memory NOP-pre-filled).
- Encoding helper independently verified against
  `jump_rs_enc(A, 1) = 0x0161` and `jump_rs_enc(B, 7) = 0x0177`.
- Full Verilator regression: 26/26 PASS. Lint clean.
Tests: tb_jump_rs PASS; full regression PASS; lint clean.
Docs: instruction_coverage.md (JUMP Rs row), changelog.md, tasks.md.
Commit:
- 19b075b

---

### Task 0033: DSJ / DSJEQ / DSJNE Rd, Address (decrement-and-skip-jump family)
Status: complete
Dependencies:
- Task 0014 (K-form alu_b path; reused with k5=1).
- Task 0016 (SUB-style operand swap; reused with alu_a=Rd, alu_b=1).
- Task 0031 (16-bit signed-displacement target math; reused from JRcc long).
Spec source: SPVU001A pages 12-70 (DSJ), 12-72 (DSJEQ), 12-73 (DSJNE)
  + the instruction-summary table. All three: encoding
  `0000 1101 1xxR DDDD` followed by a 16-bit signed word-offset.
Acceptance Criteria:
- INSTR_DSJ, INSTR_DSJEQ, INSTR_DSJNE added to instr_class_t (6'd36..38).
- Decoder: one combined arm that recognizes any of the three top11
  prefixes (`11'b00001101_100`, `_101`, `_110`) and dispatches the
  iclass via an inner `unique case`. Sets `alu_op = ALU_OP_SUB`,
  `decoded.k5 = 5'd1`, `needs_imm16 = 1`, `wb_reg_en = 1`,
  `wb_flags_en = 0` (status unaffected per the spec).
- Core gains:
  - `dsj_precondition` signal: 1 for DSJ; `st_z` for DSJEQ; `!st_z`
    for DSJNE; 1 (default — no-op) for other iclasses. This gates
    rf_wr_en so DSJEQ Z=0 / DSJNE Z=1 leave Rd untouched per spec.
  - `dsj_rd_nonzero = (alu_result != 0)`: true when the
    post-decrement Rd is non-zero.
  - PC-load mux arm for the three iclasses fires
    `dsj_precondition && dsj_rd_nonzero`, reusing `branch_target_long`.
- DSJ-family joins the alu_a swap group (Rd via rs2 port) and the
  alu_b K-form mux arm (decoded.k5 = 1 → alu_b = 32'd1).
- `sim/tb/tb_dsj.sv` exercises 8 scenarios across all three
  instructions, with distinct counter registers per scenario so the
  end-of-test checks don't get clobbered by subsequent scenarios.
  Includes the four SPVU001A spec-table boundary cases (Rd=9 take;
  Rd=1 skip; Rd=0 take wraps to -1; Z=mismatch no-op). Test ends
  with a `0xC0FF` halt (JRUC short -1 = jump-to-self) to prevent
  memory wraparound re-executing the program and clobbering the
  per-scenario counter registers.
- Encoding helpers verified against `dsj_enc(A,5) = 0x0D85`,
  `dsjeq_enc(A,5) = 0x0DA5`, `dsjne_enc(A,5) = 0x0DC5`.
- DSJS (single-word short form with 5-bit offset + direction bit)
  explicitly deferred to a future task — different encoding shape.
- Full Verilator regression: 27/27 PASS. Lint clean.
Tests: tb_dsj PASS; full Verilator-friendly regression PASS;
  lint clean.
Docs: instruction_coverage.md (3 new rows + DSJS deferred note),
  changelog.md, tasks.md.
Commit:
- 23b3aa7

---

### Task 0034: JAcc Address (absolute conditional jump)
Status: complete
Dependencies:
- Task 0030 (corrected cc encoding + signed compares).
- Tasks 0012-0013 (CORE_FETCH_IMM_HI path; needs_imm32 already wired
  for MOVI IL etc.).
Spec source: SPVU001A page 12-91 ("Jump Absolute Conditional") +
  summary table. Encoding: opcode word `1100 cccc 1000 0000` (low
  byte = `0x80` unlocks the absolute form), followed by 32-bit
  absolute target address (LO word first, then HI word).
Acceptance Criteria:
- INSTR_JACC added to instr_class_t (6'd39).
- Decoder recognizes JRCC-shape encodings with `disp8 == 0x80` and
  one of the 11 recognized cc codes (A0023). Sets
  `iclass = INSTR_JACC`, `needs_imm32 = 1`, `branch_cc = cc`,
  `wb_reg_en = 0`, `wb_flags_en = 0` (status unaffected).
- Core gains `branch_target_jacc = {imm_hi_q, imm_lo_q[15:4], 4'h0}`
  (32-bit absolute target with bottom 4 bits forced to 0 per spec
  page 12-91 word-alignment requirement).
- PC-load mux extended with INSTR_JACC arm gated by `branch_taken`,
  reusing the existing JRcc condition evaluator.
- `sim/tb/tb_jacc.sv` covers three scenarios: JAUC absolute taken
  with messy bottom-nibble target (verifies alignment mask); JAEQ
  absolute taken via CMPI Z=1; JANE absolute NOT taken via CMPI Z=1.
  Memory NOP-pre-filled; final scenario ends with `0xC0FF` halt.
Tests: tb_jacc PASS; Verilator regression PASS; lint clean.
Docs: instruction_coverage.md (new JAcc row), changelog.md, tasks.md.
Commit:
- ae618c3

---

### Task 0035: DSJS Rd, Address (decrement-and-skip-jump short form)
Status: complete
Dependencies:
- Task 0033 (DSJ-family precondition/nonzero gating + alu_a/alu_b
  mux entries; reused with INSTR_DSJS added).
Spec source: SPVU001A page 12-74 ("Decrement Register and Skip Jump
  - Short") + summary table line 13844. Encoding `0011 1Dxx xxxR DDDD`
  (top5 = 5'b00111). bit[10] = D (direction); bits[9:5] = 5-bit
  unsigned offset; bit[4] = R; bits[3:0] = Rd index. Single-word
  instruction, no immediate fetch.
Acceptance Criteria:
- INSTR_DSJS = 6'd40 added to instr_class_t.
- Decoder: top5 == 5'b00111 → INSTR_DSJS, with alu_op=SUB, k5=1,
  wb_reg_en=1, wb_flags_en=0. Direction and offset are NOT captured
  in the decoded struct — they're extracted in the core directly
  from instr_word_q[10] and instr_word_q[9:5].
- Core:
  - INSTR_DSJS joins the alu_a swap group (Rd via rs2) and the
    K-form alu_b mux arm (k5=1 → alu_b=1).
  - dsj_precondition for DSJS = 1'b1 (unconditional, like DSJ).
  - New branch_target_dsjs = pc_value + (D ? -off*16 : +off*16),
    where pc_value at WRITEBACK already equals PC' (= PC_original
    + 16 after the single-word opcode fetch). PC-load mux gains a
    new INSTR_DSJS arm gated by dsj_rd_nonzero.
- `sim/tb/tb_dsjs.sv` covers four scenarios:
  - Forward DSJS Rd=9→8 take (sentinel preserved);
  - Forward DSJS Rd=1→0 skip (fall-through runs);
  - Backward DSJS Rd=5→4 take, choreographed so the backward target
    is a known MOVI that writes a sentinel (verifies the D=1 path
    end-to-end);
  - Forward DSJS Rd=0→0xFFFFFFFF take (verifies the decrement-of-0
    case from the spec example table).
- Encoding helper verified: `dsjs_enc(D=0, off=5, A, 5) = 0x38A5`,
  `dsjs_enc(D=1, off=5, A, 5) = 0x3CA5`.
- Branch-family regression: all 9 branch tbs PASS.
Tests: tb_dsjs PASS; branch-family regression PASS; lint clean.
Docs: instruction_coverage.md (DSJS row), changelog.md, tasks.md.
Commit:
- c60c723

---

### Task 0036: ABS / NEGB Rd (complete the unary family)
Status: complete
Dependencies:
- Task 0022 (unary-family decoder framework + ALU_OP_NEG / NOT).
- Task 0029 (ALU_OP_SUBB; NEGB is implemented as SUBB with alu_a=0).
Spec source: SPVU001A page 12-34 (ABS), page 12-168 (NEGB). Encodings
  from the unary chart (`0000 0011 1ooR DDDD` with `oo` selecting
  sub-op): ABS = bits[6:5]=00; NEGB = bits[6:5]=10.
Acceptance Criteria:
- INSTR_ABS = 6'd41 and INSTR_NEGB = 6'd42 added to instr_class_t.
- ALU_OP_ABS = 4'd13 added to alu_op_t.
- `tms34010_alu.sv` gains an ALU_OP_ABS arm: result is the conditional
  select between `a` (when `0-a` has its sign bit set — either a was
  already non-negative or a == MIN_INT) and `0-a` (when `0-a` is
  non-negative — i.e., a was negative and small enough to flip).
  N is set to the sign of `0-a` per spec; Z = (a == 0); V on MIN_INT
  overflow. **C is cleared (A0024 deviation)** — spec says "Unaffected"
  but the project's wb_flags_en is currently all-or-nothing.
- NEGB reuses ALU_OP_SUBB. Core's alu_a mux gains an `INSTR_NEGB`
  arm forcing `alu_a = '0`; the default alu_b mux already routes
  `rf_rs2_data` (Rd) when not overridden, so ALU computes
  `0 - Rd - C` as required.
- Decoder's unary-family case statement gains the `2'b00` (ABS) and
  `2'b10` (NEGB) sub-op arms; ILLEGAL fallthrough removed.
- `sim/tb/tb_abs_negb.sv` runs 6 ABS test vectors from the spec
  example table (page 12-34) and 4 NEGB vectors from page 12-168.
  Final ST.NCZV checked against the spec NCZV column for NEGB's
  last scenario (`-1 - 1 → 0, NCZV = 0110` per the last row).
- Encoding helper verified: `abs_enc(A,1) = 0x0381`,
  `negb_enc(A,1) = 0x03C1`.
- A0024 added to docs/assumptions.md documenting the C-clear
  deviation and the deferred per-flag-mask refactor (also flagging
  BTST as the natural next instruction to motivate that refactor).
Tests: tb_abs_negb PASS; tb_neg_not / tb_alu / tb_sub_rr /
  tb_addc_subb regression PASS; lint clean.
Docs: instruction_coverage.md (ABS / NEGB rows updated from "not
  started" to "implemented"), assumptions.md A0024, changelog.md,
  tasks.md.
Commit:
- aac06d5

---

### Task 0037: BTST K/Rs + per-flag wb_flag_mask refactor
Status: complete
Dependencies:
- Tasks 0009 (status register), 0017 (logical ops + ALU_OP_AND).
- Task 0036 (ABS — its A0024 C-clear deviation is RESOLVED by the
  refactor that lands here).
Spec source: SPVU001A pages 12-46 (BTST K, Rd) and 12-47 (BTST Rs, Rd)
  + summary table lines 26942/26943. Encodings `0001 11KK KKKR DDDD`
  (BTST K) and `0100 101S SSSR DDDD` (BTST Rs). Status: Z = !bit;
  N, C, V "Unaffected" per spec.
Acceptance Criteria:
- **wb_flag_mask refactor** (architectural):
  - `decoded_instr_t` gains `wb_flag_mask : alu_flags_t` field.
  - `tms34010_status_reg.sv` gains a `flag_update_mask` input;
    per-bit gating on N/C/Z/V update in the always_ff.
  - `tms34010_core.sv` wires `decoded.wb_flag_mask` into the
    status_reg's new input.
  - Decoder's always_comb defaults `decoded.wb_flag_mask = '1` (all
    flags update) so every existing arm Just Works — no per-arm
    changes needed except for instructions that DO want selective
    updates.
  - `tb_status_reg.sv` updated for the new port (driven all-ones by
    default; existing checks unchanged).
- **A0024 resolved**: ABS arm in the decoder now sets
  `wb_flag_mask = '{n:1, c:0, z:1, v:1}`. ABS becomes spec-correct
  for C — the flag is truly "Unaffected". A0024 marked RESOLVED.
- **BTST**:
  - INSTR_BTST_K = 6'd43 and INSTR_BTST_RR = 6'd44 added to
    instr_class_t.
  - Decoder: top6 = 6'b000111 (BTST K) and top7 = 7'b0100_101
    (BTST Rs) arms with `alu_op = ALU_OP_AND`, `wb_reg_en = 0`,
    `wb_flag_mask = '{n:0, c:0, z:1, v:0}`.
  - Core's alu_a mux: INSTR_BTST_K and INSTR_BTST_RR join the
    swap group (alu_a = Rd via rs2 port).
  - Core's alu_b mux: new arms drive `32'd1 << decoded.k5` for
    BTST K and `32'd1 << rf_rs1_data[4:0]` for BTST Rs.
- `sim/tb/tb_btst.sv`: 5 scenarios using JRZ/JRNE probes to verify
  Z-flag behavior for each BTST (since the JRcc destination
  register reveals Z without needing direct ST sampling between
  BTSTs). Plus a final CMP-NCZV=1101 → BTST → halt sequence that
  verifies N, C, V are preserved unchanged across the BTST.
- Encoding helpers verified: `btst_k_enc(0,A0) = 0x1C00`,
  `btst_k_enc(1,A2) = 0x1C22`, `btst_k_enc(31,A0) = 0x1FE0`,
  `btst_rr_enc(A3,A4) = 0x4A64`.
- Full Verilator regression: all existing tbs still PASS after the
  flag-mask refactor. tb_btst PASS. tb_status_reg unit test PASS
  (with the new port wired with mask=all-ones).
- BTST Rs/K is the first instruction in the project to exercise the
  per-flag mask; ABS retroactively becomes the second instruction.
Tests: tb_btst PASS; broader regression including tb_movi/tb_movk/
  tb_add_rr/tb_sub_rr/tb_cmp_rr/tb_logical_rr/tb_addc_subb/
  tb_immi_iw/tb_shift_k/tb_neg_not/tb_abs_negb/tb_jrcc_short/
  tb_jrcc_signed/tb_dsj PASS; lint clean.
Docs: instruction_coverage.md (BTST K + Rs rows added; ABS row
  updated to reflect resolved deviation), assumptions.md (A0024
  marked RESOLVED), changelog.md, tasks.md.
Commit:
- d9a75b0

---

### Task 0038: CLRC / SETC / GETST / PUTST (status-register manipulation)
Status: complete
Dependencies:
- Task 0037 (wb_flag_mask used by CLRC/SETC for selective C-only updates).
- Task 0009 (status register has full ST-write path used by PUTST).
Spec source: SPVU001A summary table page A-14:
  CLRC  : 0x0320
  SETC  : 0x0DE0
  GETST Rd : 0000 0001 100R DDDD
  PUTST Rs : 0000 0001 101R DDDD
Acceptance Criteria:
- Four new iclass enumerators (INSTR_CLRC/SETC/GETST/PUTST,
  6'd45..48).
- Decoder arms:
  - CLRC/SETC: single fixed encodings, `wb_reg_en=0`,
    `wb_flags_en=1`, `wb_flag_mask = {c-only}`.
  - GETST: top11 = 0x00C, `wb_reg_en=1`, no flag update.
  - PUTST: top11 = 0x00D, `wb_reg_en=0`, no flag update; the
    full-ST-write happens via st_write_en in the core.
- Core:
  - Flag-input mux gains SETC arm (`flags_in.c = 1`) and CLRC arm
    (`flags_in.c = 0`); paired with the c-only mask from the
    decoder, only ST.C updates.
  - rf_wr_data mux gains GETST arm routing `st_value`.
  - `st_write_en` now derives from `(CORE_WRITEBACK && iclass == PUTST)`;
    `st_write_data = rf_rs1_data`.
- `sim/tb/tb_st_ops.sv` verifies a PUTST → GETST round-trip with a
  custom ST value, then a SETC followed by GETST, then a CLRC
  followed by GETST. Each captured GETST result is cross-checked
  bit-by-bit, and the final ST.{N,C,Z,V} are checked individually
  to confirm CLRC/SETC truly leave N/Z/V alone.
- Encoding helpers verified: `getst_enc(A,5) = 0x0185`,
  `putst_enc(B,7) = 0x01B7`.
Tests: tb_st_ops PASS; full Verilator regression PASS; lint clean.
Docs: instruction_coverage.md (4 new rows), changelog.md, tasks.md.
Commit:
- 1236868

---

### Task 0039: Shift Rs-form (SLA/SLL/SRA/SRL/RL with Rs amount)
Status: complete
Dependencies:
- Task 0024 (K-form shifter wired; this task extends with a second
  amount source).
Spec source: SPVU001A summary table page A-15 + page 12-219 prose
  (the per-shift detail pages). Encodings `0110 0NNS SSSR DDDD`
  where NN selects {SLA, SLL, SRA, SRL, RL} per top7 prefixes
  `7'b0110_000..100`.
Acceptance Criteria:
- Five new iclass values (INSTR_{SLA,SLL,SRA,SRL,RL}_RR) at
  6'd49..53.
- Decoder arms with the corresponding top7 prefixes, populating
  `decoded.shift_op`, `decoded.rs_idx`, `decoded.rd_*`,
  `use_shifter = 1`, `wb_reg_en = 1`, `wb_flags_en = 1`.
- Core gains a `shifter_amount` mux signal:
  - For `INSTR_SLA_RR/SLL_RR/RL_RR`: `shifter_amount = rf_rs1_data[4:0]`.
  - For `INSTR_SRA_RR/SRL_RR`: `shifter_amount = (~rf_rs1_data[4:0]) + 1`
    (2's complement per A0019-extended; the assembler emits the
    negated amount).
  - Default (K-form): `shifter_amount = decoded.k5` (unchanged).
- `sim/tb/tb_shift_rr.sv` covers all 5 Rs-form shifts with shift
  amount = 4. For SRA/SRL it uses A1 = 28 (5-bit 2's-comp of 4)
  to drive the HW into a magnitude-4 right shift.
- Encoding helper verified: `shift_rr_enc(SLL_top7, A1, A, A2) = 0x6222`,
  `shift_rr_enc(SRA_top7, A3, A, A4) = 0x6464`.
- Full Verilator regression PASS; lint clean.
Tests: tb_shift_rr PASS; tb_shift_k unchanged; full regression PASS.
Docs: instruction_coverage.md (5 new rows), changelog.md, tasks.md.
Commit:
- 7381452

---

### Task 0040: GETPC / EXGPC / REV (PC + revision register ops)
Status: complete
Dependencies:
- Task 0038 (status-reg manipulation; rf_wr_data mux already supports
  "non-ALU" sources). This task extends that mux pattern.
Spec source: SPVU001A summary table A-16:
  GETPC Rd  : 0000 0001 010R DDDD
  EXGPC Rd  : 0000 0001 001R DDDD
  REV   Rd  : 0000 0000 001R DDDD
  Plus SPVU001A page 12-233 (REV constant value example).
Acceptance Criteria:
- Three new iclass values (INSTR_GETPC=54, INSTR_EXGPC=55,
  INSTR_REV=56).
- Decoder arms recognizing the top11 prefixes 0x00A / 0x009 / 0x001.
- Core's `rf_wr_data` mux extended with:
  - INSTR_GETPC, INSTR_EXGPC → pc_value
  - INSTR_REV → 32'h0000_0008 (the revision constant per A0025)
- Core's PC-load mux extended with an INSTR_EXGPC arm:
  `pc_load_value = {rf_rs2_data[31:4], 4'h0}` (word-aligned per A0025;
  rs2 reads decoded.rd_idx, async, so it sees the OLD Rd value during
  the same WRITEBACK cycle that writes the new value).
- A0025 added documenting the REV constant choice (taken from the
  spec's worked example) and the bottom-nibble PC alignment for EXGPC.
- `sim/tb/tb_pc_ops.sv` exercises all three:
  - GETPC verifies A1 = `(getpc_word_index + 1) * 16` (the bit
    address after the single-word PC advance).
  - REV verifies A2 = 0x00000008.
  - EXGPC verifies (a) A3 = old PC at the EXGPC's WRITEBACK; (b) the
    CPU lands at the target word and the sentinel MOVI there writes
    A4 = 0xCAFE_FACE; (c) the trap MOVI right after EXGPC does NOT
    execute (its target register stays unchanged).
- Encoding helpers verified.
Tests: tb_pc_ops PASS; full Verilator regression PASS; lint clean.
Docs: instruction_coverage.md (3 new rows), assumptions.md A0025,
  changelog.md, tasks.md.
Commit:
- e50d77a

---

### Task 0041: LMO Rs, Rd (Leftmost-One priority encoder)
Status: complete
Dependencies:
- Task 0037 (wb_flag_mask refactor — LMO uses Z-only updates per spec).
Spec source: SPVU001A page 12-108 ("Find Leftmost One") + summary
  table line 26955. Encoding `0110 101S SSSR DDDD` (top7 =
  7'b0110_101). Status: Z = (Rs == 0); N, C, V unaffected.
Acceptance Criteria:
- INSTR_LMO_RR = 6'd57 added.
- Decoder arm with top7 = 7'b0110_101 setting wb_reg_en=1,
  wb_flag_mask = `'{n:0, c:0, z:1, v:0}` (Z-only via the mask
  machinery added in Task 0037).
- Core gains a combinational LMO datapath:
    lmo_bit_pos = position of highest-set bit of rf_rs1_data
                  (low-to-high scan; last hit wins → highest
                  position; synthesizable without `break`)
    lmo_result = (rf_rs1_data == 0) ? 32'h0
                                    : {{27{1'b0}}, ~lmo_bit_pos}
  rf_wr_data mux routes lmo_result for INSTR_LMO_RR.
  flag_input mux delivers `{z: (rf_rs1_data == 0), others 0}`
  for INSTR_LMO_RR; combined with the mask only Z updates.
- `sim/tb/tb_lmo.sv` covers all 5 spec-table worked examples
  (page 12-108):
    Rs=0x00000000 → Rd=0, Z=1
    Rs=0x00000001 → Rd=0x1F
    Rs=0x00000010 → Rd=0x1B
    Rs=0x08000000 → Rd=0x04
    Rs=0x80000000 → Rd=0
  Plus an N/C/V-preservation check after a CMP-set NCZV=1101.
Tests: tb_lmo PASS; lint clean.
Docs: instruction_coverage.md (LMO row), changelog.md, tasks.md.
Commit:
- 8d8d5f6

---

### Task 0042: ST layout finalization (FS0/FE0/FS1/FE1/IE/PBX positions + reset value)
Status: complete
Dependencies:
- Task 0009 (status register exists).
- Task 0037 (per-flag mask machinery, prerequisite for Phase 5).
Spec source: SPVU001A §5.2 Table 5-2 (page 5-18). The N/C/Z/V positions
  31..28 happen to match the earlier A0010 placeholders; this task
  pins down the field-size bits and IE/PBX to their authoritative
  positions and locks ST's reset value to `0x0000_0010` (FS0 = 16).
Acceptance Criteria:
- `rtl/tms34010_pkg.sv` gains `ST_FS0_LO/HI`, `ST_FE0_BIT`,
  `ST_FS1_LO/HI`, `ST_FE1_BIT`, `ST_IE_BIT`, `ST_PBX_BIT`
  parameters, and a `ST_RESET_VALUE = 32'h0000_0010` constant.
- `rtl/core/tms34010_status_reg.sv` initializes `st_q` to
  `ST_RESET_VALUE` instead of all-zeros.
- `sim/tb/tb_status_reg.sv`'s "after reset" check updated to expect
  the new value (`ST_RESET_VALUE`, flags all zero).
- A0010 marked RESOLVED; the resolution note in `docs/assumptions.md`
  spells out the full ST layout.
- This task is foundational: it adds no instruction. Subsequent
  Phase 5 tasks (SETF, EXGF, SEXT, ZEXT) and the DINT/EINT pair
  use these constants.
- Functional regression (13 Verilator-clean tbs) PASS, including
  `tb_st_ops` (which uses PUTST/GETST round-trips that don't depend
  on the reset value).
Tests: 13/13 Verilator regression PASS; lint clean (modulo
  UNUSEDPARAM warnings on the new constants — they're used by the
  next tasks). Questa lint also clean.
Docs: assumptions.md (A0010 marked RESOLVED with full layout),
  changelog.md, tasks.md. No instruction_coverage.md change since no
  instructions land here.
Commit:
- d7a0ed3

---

### Task 0043: SETF FS, FE, F (set field-size parameters)
Status: complete
Dependencies:
- Task 0042 (ST layout constants + reset value).
Spec source: SPVU001A page 12-237 + summary table line 26978.
  Encoding bits: `[15:10]=000001 [9]=F [8]=1 [7:6]=01 [5]=FE [4:0]=FS`.
  Per spec, F selects the FS/FE pair (0 = FS0/FE0; 1 = FS1/FE1).
  FS = 0 encodes field-size 32 (Table 5-3). All status bits "Unaffected".
Acceptance Criteria:
- INSTR_SETF = 6'd58 added.
- Decoder predicate: top6 = 6'b000001, bit[8] = 1, bits[7:6] = 2'b01.
- Core's `st_write_en` extended to fire for INSTR_SETF as well as
  INSTR_PUTST.
- Core's `st_write_data` becomes a mux:
  - INSTR_PUTST → rf_rs1_data (existing)
  - INSTR_SETF  → splice current `st_value` with the F-selected
                   FS/FE pair replaced by `instr_word_q[4:0]` /
                   `instr_word_q[5]`. Reads F from `instr_word_q[9]`.
- `sim/tb/tb_setf.sv` runs 5 scenarios: SETF 17/1/0 → FS0/FE0;
  SETF 8/0/1 → FS1/FE1 (FS0/FE0 from previous SETF preserved);
  SETF 0/1/0 → FS=0 encodes field-size 32 (the encoding edge case);
  SETF 31/1/1 → boundary; and a CMP-set-NCZV → SETF → GETST sequence
  to verify N, C, Z, V are preserved by SETF.
- Status-preservation check verified directly via GETST captures
  and via final ST flag-bit outputs.
- Encoding helpers verified: setf_enc(17,1,0)=0x0571,
  setf_enc(8,0,1)=0x0748.
- Lint clean (modulo UNUSEDPARAM on the still-unused FS/FE
  constants — SEXT/ZEXT in the next task uses them).
Tests: tb_setf PASS; tb_st_ops/tb_btst/tb_lmo/tb_abs_negb/tb_movi/
  tb_cmp_rr/tb_jrcc_short/tb_jrcc_signed all still PASS; lint clean.
Docs: instruction_coverage.md (SETF row), changelog.md, tasks.md.
Commit:
- 6332e86

---

### Task 0044: SEXT / ZEXT Rd, F (sign-/zero-extend a field)
Status: complete
Dependencies:
- Task 0042 (ST field-size constants).
- Task 0043 (SETF — needed to load FS0/FS1 for spec test vectors).
- Task 0037 (per-flag wb_flag_mask).
Spec source: SPVU001A pages 12-238 (SEXT) and 12-256 (ZEXT) plus
  summary table lines 26979 / 27011. Encodings:
    SEXT: bits[15:10]=000001, bit[9]=F, bit[8]=1, bits[7:5]=000,
          bit[4]=R, bits[3:0]=Rd  →  base 0x0500
    ZEXT: same but bits[7:5]=001  →  base 0x0520
Acceptance Criteria:
- INSTR_SEXT = 6'd59, INSTR_ZEXT = 6'd60.
- Decoder predicates: top6==000001 AND bit[8]==1 AND bits[7:5]==000
  (SEXT) or ==001 (ZEXT). wb_flag_mask for SEXT = `{n:1, c:0, z:1, v:0}`;
  for ZEXT = `{n:0, c:0, z:1, v:0}` (Z-only per spec).
- Core's SEXT/ZEXT datapath:
  - `fs_selected` reads FS0 (bits[ST_FS0_HI:ST_FS0_LO]) or FS1 from
    `st_value` based on `instr_word_q[9]`.
  - `field_mask` = (1 << fs_selected) - 1, with the FS=0 → 32 case
    handled as identity (mask = all-ones, no extension).
  - `field_msb` = `rf_rs2_data[fs_selected - 1]` (variable bit-index;
    Verilog/Verilator/Questa all synthesize this as a 32:1 mux).
  - `sext_result` = (field_msb) ? (Rd & mask) | ~mask : (Rd & mask).
  - `zext_result` = Rd & mask.
- rf_wr_data and flag_input muxes extended with SEXT/ZEXT arms.
- `sim/tb/tb_sext_zext.sv` runs 6 SEXT spec-vector scenarios (FS=15,
  16, 17 × F=0, 1) and 5 ZEXT spec-vector scenarios (FS=32 via the
  0 encoding, 31, 1, 16 × F=0/1). Each scenario uses a distinct
  destination so end-of-test verification is independent.
- Encoding helpers verified inline.
- Lint clean.
Tests: tb_sext_zext PASS; 16-tb sanity regression PASS.
Docs: instruction_coverage.md (SEXT + ZEXT rows), changelog.md,
  tasks.md.
Commit:
- 4c16ad8

---

### Task 0045: EXGF Rd, F (Exchange Field Definition)
Status: complete
Dependencies:
- Task 0042 (ST field-size constants).
- Task 0038 (PUTST path / `st_write_en` machinery; used by EXGF to
  write the modified ST).
Spec source: SPVU001A page 12-77 + summary table line 26954.
  Encoding `1101 01F1 000R DDDD`:
    bits[15:10] = 6'b110101  (= 0x35)
    bit[9]      = F  (selector: 0 = FE0/FS0; 1 = FE1/FS1)
    bit[8]      = 1  (constant)
    bits[7:5]   = 000 (sub-op)
    bit[4]      = R  (file)
    bits[3:0]   = Rd index
  Semantics (atomic): Rd[5:0] ↔ {FE<F>, FS<F>} in ST. Rd[31:6] cleared.
  Status bits all "Unaffected".
Acceptance Criteria:
- INSTR_EXGF = 6'd61.
- Decoder predicate: bits[15:10]==EXGF_TOP6 AND bit[8]==1 AND
  bits[7:5]==000. wb_reg_en=1, wb_flags_en=0.
- Core gains a small EXGF datapath:
    exgf_cur_fs/fe: read FS<F>/FE<F> from st_value via instr_word_q[9].
    exgf_new_rd = {26'b0, exgf_cur_fe, exgf_cur_fs}.
    exgf_new_st = st_value with the F-selected slot overwritten by
                  rf_rs2_data[5:0] (i.e., the OLD Rd value, since
                  the regfile is async-read).
- rf_wr_data mux: INSTR_EXGF → exgf_new_rd.
- st_write_en: now `iclass ∈ {PUTST, SETF, EXGF}`.
- st_write_data: INSTR_EXGF → exgf_new_st.
- `sim/tb/tb_exgf.sv` runs both spec-page-12-77 worked examples:
    EXGF A1, F=0: A1=0xFFFFFFC0, ST=0xF0000FFF
                 → A1=0x0000003F, ST=0xF0000FC0
    EXGF A3, F=1: A3=0xFFFFFFC0, ST=0xF0000FFF
                 → A3=0x0000003F, ST=0xF000003F
- Crucial test-design point: MOVI to load registers MUST happen
  BEFORE PUTST sets the target ST, because MOVI's wb_flag_mask
  defaults to all-1s and so MOVI clobbers ST.{N,C,Z,V}. The test
  comment explains this trap and the sequence.
Tests: tb_exgf PASS; tb_st_ops/tb_setf/tb_sext_zext also PASS;
  lint clean.
Docs: instruction_coverage.md (EXGF row), changelog.md, tasks.md.
Commit:
- b883a89

---

### Task 0046: DINT / EINT — interrupt-enable control
Status: complete
Dependencies:
- Task 0042 (ST.IE bit position pinned at bit 21).
- Task 0038 (full ST-write path; reused).
Spec source: SPVU001A summary table page A-14. Encodings:
  DINT = 0x0360 (clear IE), EINT = 0x0D60 (set IE). Status N, C, Z, V
  all "Unaffected".
Acceptance Criteria:
- INSTR_DINT = 6'd62, INSTR_EINT = 6'd63.
- Decoder arms matching the two single-fixed encodings.
- Core's `st_write_en` extended to fire for INSTR_DINT and
  INSTR_EINT (now `iclass ∈ {PUTST, SETF, EXGF, DINT, EINT}`).
- Core's `st_write_data` mux adds:
    INSTR_DINT → `st_value & ~(1 << ST_IE_BIT)`
    INSTR_EINT → `st_value |  (1 << ST_IE_BIT)`
- `sim/tb/tb_dint_eint.sv` seeds ST via PUTST with a known
  bit-pattern (IE=0), runs EINT then GETST, runs DINT then GETST,
  and verifies (a) the IE bit toggles as expected and (b) all
  other ST bits are preserved (the pattern `0xA5A5_05A5` has bits
  scattered so any accidental wider write is detected).
- IE bit position `ST_IE_BIT` from Task 0042 now finally used —
  resolves one of the UNUSEDPARAM lint warnings.
Tests: tb_dint_eint PASS; lint clean.
Docs: instruction_coverage.md (DINT + EINT rows), changelog.md,
  tasks.md.
Commit:
- 5e6c3c9

---

### Task 0047: Memory-write infrastructure + PUSHST
Status: complete
Dependencies:
- Task 0042 (ST register pinning — PUSHST writes the full ST value).
- Task 0009 (regfile SP alias — PUSHST reads/writes A15 = SP).
Spec source: SPVU001A summary table page A-16 (PUSHST = 0x01E0).
  PUSHST is `SP <- SP - 32; mem[SP] <- ST` with status bits Unaffected.
Acceptance Criteria:
- **Architectural changes**:
  - `decoded_instr_t` gains a `needs_memory_op` field that the
    decoder sets when an instruction requires a CORE_MEMORY-state
    transaction between EXECUTE and WRITEBACK.
  - The core's FSM transition `CORE_EXECUTE → state_d` now selects
    `CORE_MEMORY` when `needs_memory_op` is set, else
    `CORE_WRITEBACK` as before.
  - The previously-stubbed `CORE_MEMORY` state now drives the
    memory IF (`mem_req`, `mem_we`, `mem_addr`, `mem_size`,
    `mem_wdata`) for write transactions and waits for `mem_ack`
    before transitioning to `CORE_WRITEBACK`.
  - `sim_memory_model.sv` extended to atomically handle 32-bit
    writes (and reads): when `latched_size == 6'd32`, two adjacent
    16-bit words are written/read in a single ack.
  - `instr_class_t` widened from 6 to 7 bits to accommodate
    INSTR_PUSHST (= 6'd64, which overflowed the previous 6-bit cap).
- **PUSHST instruction**:
  - INSTR_PUSHST = 7'd64.
  - Decoder arm matching the literal 0x01E0 encoding. Sets
    `rs_idx = 15` (read SP via rs1), `rd_idx = 15` (write back
    to SP), `alu_op = SUB`, `wb_reg_en = 1`, `wb_flags_en = 0`,
    `needs_memory_op = 1`.
  - Core's alu_b mux gets an `INSTR_PUSHST → 32'd32` entry so the
    ALU computes `SP - 32`.
  - The CORE_MEMORY state drives the memory write with
    `mem_addr = alu_result`, `mem_wdata = st_value`, `mem_size = 32`.
- `sim/tb/tb_pushst.sv` initializes SP = `0x0000_0800` (= word 128),
  PUTSTs a seed ST = `0xC3C3_03C3`, runs PUSHST, then verifies:
  (a) SP = `0x0000_07E0`, (b) `mem[word 126]` = `0x03C3`, `mem[word 127]`
  = `0xC3C3`, (c) ST itself is unchanged. The standard halt/run pattern.
- This is the FIRST instruction in the project that uses the memory
  write path; future tasks (POPST, CALL, RETS, MMTM, MMFM, TRAP,
  MOVE *Rd) will all build on this scaffolding.
Tests: tb_pushst PASS; full Verilator regression PASS; lint clean.
Docs: instruction_coverage.md (PUSHST row added with the memory
  column = "write"), changelog.md, tasks.md.
Commit:
- fd5b1c0

---

### Task 0048: POPST (PUSHST inverse; first memory-read-into-ST instr)
Status: complete
Dependencies:
- Task 0047 (CORE_MEMORY state, 32-bit memory transactions, st_write_en
  path, regfile SP alias — all reused).
Spec source: SPVU001A summary table page A-16. POPST = 0x01C0;
  semantics `ST <- mem[SP]; SP <- SP + 32`. All four status flags are
  written by the popped value.
Acceptance Criteria:
- INSTR_POPST = 7'd65.
- Decoder arm matching the literal 0x01C0 encoding. Sets rs_idx=15,
  rd_idx=15, alu_op=ADD (so the ALU computes SP+32 for the SP
  writeback), wb_reg_en=1, wb_flags_en=0 (ST update goes through
  st_write_en, not the per-flag mask path), needs_memory_op=1.
- Core's alu_b mux: INSTR_POPST joins INSTR_PUSHST's `→ 32'd32` entry.
- Core's CORE_MEMORY state extended with an INSTR_POPST arm:
  mem_req=1, mem_we=0, mem_addr=`rf_rs1_data` (the OLD SP value —
  NOT `alu_result`, since we read BEFORE the increment), mem_size=32.
- Core's st_write_en list extended to fire for INSTR_POPST; the
  st_write_data mux gets a `mem_rdata` arm for POPST. Note: mem_rdata
  is a registered output from the memory model that holds the last
  fetched value, so it's still valid in the WRITEBACK cycle one
  cycle after the CORE_MEMORY ack.
- `sim/tb/tb_popst.sv` does a round-trip:
    1. Set SP = `0x0000_0800` (via MOVE A0, A15).
    2. PUTST a seed `ST_SEED = 0xC3C3_03C3`.
    3. PUSHST — drops SP to `0x07E0`, writes ST to mem[126..127].
    4. PUTST a different ST_TMP (= reset value `0x10`) and GETST →
       confirms clobbered ST = ST_TMP.
    5. POPST — recovers ST = ST_SEED, restores SP = `0x0000_0800`.
    6. GETST captures the restored ST → A4 should equal ST_SEED.
    7. Per-flag check: ST.N/C/Z/V each match ST_SEED[31:28].
Tests: tb_popst PASS; tb_pushst still PASS; lint clean.
Docs: instruction_coverage.md (POPST row), changelog.md, tasks.md.
Commit:
- 5c32697

---

### Task 0049: CALL Rs (Call Subroutine Indirect)
Status: complete
Dependencies:
- Task 0047 (memory-write infrastructure + CORE_MEMORY state).
- Task 0032 (JUMP Rs — same PC-load-from-register pattern with
  bottom-nibble word-alignment mask).
Spec source: SPVU001A page 12-47 + summary table line 27018.
  CALL Rs encoding `0000 1001 001R DDDD` (top11 = 0x049).
  Semantics:
    SP -= 32
    mem[new SP] = PC'    (PC' = address of next instruction word)
    PC = Rs              (with bottom 4 bits cleared)
  Status bits all "Unaffected".
Acceptance Criteria:
- INSTR_CALL_RS = 7'd66.
- Decoder arm with top11 = 11'b00001001_001 (= 0x049). Sets:
    - rs_idx     = instr[3:0]   (Rs index — read via rs1)
    - rd_idx     = REG_SP_IDX   (write SP; read SP via rs2)
    - rd_file    = instr[4]     (file of Rs)
    - alu_op     = SUB
    - wb_reg_en  = 1
    - wb_flags_en = 0
    - needs_memory_op = 1
- Core's alu_a swap group: INSTR_PUSHST/POPST/CALL_RS all join (alu_a
  = rs2 = SP). This factors the SP read for all three stack ops.
- Core's alu_b mux: same three iclasses → 32'd32.
- CORE_MEMORY new arm for INSTR_CALL_RS: mem_we=1, mem_addr=alu_result
  (= SP-32), mem_size=32, mem_wdata=pc_value (= PC' at CORE_MEMORY
  time, since the FETCH-ack advance has already happened).
- PC-load mux new arm for INSTR_CALL_RS: unconditional pc_load_en=1
  with pc_load_value = {rf_rs1_data[31:4], 4'h0}.
- `sim/tb/tb_call_rs.sv` verifies:
    1. The CALLed subroutine runs (sentinel-write MOVI at the
       subroutine entry succeeds).
    2. A trap MOVI right AFTER the CALL opcode does NOT run.
    3. SP decremented by 32.
    4. The two 16-bit memory words at the new SP hold the bit-address
       of the instruction following the CALL opcode (= PC').
- Encoding helpers verified: `call_rs_enc(A,5) = 0x0925`,
  `call_rs_enc(B,5) = 0x0935`.
Tests: tb_call_rs PASS; tb_pushst & tb_popst still PASS (the
  alu_a swap-group addition is benign for them — both decoded sources
  alias SP anyway); lint clean.
Docs: instruction_coverage.md (CALL Rs row), changelog.md, tasks.md.
Commit:
- 728d94c

---

### Task 0050: RETS [N] (Return from Subroutine)
Status: complete
Dependencies:
- Task 0048 (POPST — same pop-from-stack pattern).
- Task 0049 (CALL Rs — for end-to-end round-trip testing).
Spec source: SPVU001A page 12-231 + summary table line 27036.
  Encoding `0000 1001 011N NNNN` (top11 = 0x04B; bits[4:0] = N).
  Semantics:
    PC <- mem[SP]    (32-bit pop)
    SP <- SP + 32 + 16*N
  Status bits all "Unaffected". RETS with no operand = RETS 0.
Acceptance Criteria:
- INSTR_RETS = 7'd67. Decoded.k5 carries the N field.
- Decoder arm matches top11 = 0x04B (= 11'b00001001_011). Sets
  rs_idx=15, rd_idx=15, k5=instr[4:0], alu_op=ADD, wb_reg_en=1,
  needs_memory_op=1.
- alu_a swap group adds INSTR_RETS (alu_a = SP via rs2).
- alu_b mux new entry: INSTR_RETS → `32'd32 + (decoded.k5 << 4)`.
  This delivers 32 + 16*N for N ∈ {0..31} → range 32..528.
- CORE_MEMORY new arm: mem_we=0, mem_addr=rf_rs2_data (= OLD SP),
  mem_size=32.
- PC-load mux: INSTR_RETS sets `pc_load_en = 1`, `pc_load_value =
  mem_rdata`. The popped value is taken as-is (no bottom-nibble
  mask) because the pushed PC was already word-aligned.
- `sim/tb/tb_rets.sv` runs a full CALL → subroutine → RETS round-trip
  using the same memory layout as `tb_call_rs.sv`. Adds a "pre-return
  sentinel" pattern: A7 is set to `0xAAAA_AAAA` BEFORE the CALL; the
  post-CALL instruction writes A7 = `0x0000_BEEF` — that MOVI runs
  if and only if RETS actually returned. So a passing test directly
  exercises the round trip.
Tests: tb_rets PASS; tb_call_rs / tb_pushst / tb_popst still PASS;
  lint clean.
Docs: instruction_coverage.md (RETS row), changelog.md, tasks.md.
Commit:
- a747083

---

### Task 0051: CALLA / CALLR (absolute + relative subroutine calls)
Status: complete
Dependencies:
- Task 0047 (memory-write infrastructure).
- Task 0049 (CALL Rs — same stack-push pattern).
- Task 0031 (JRcc long — `branch_target_long` reused for CALLR).
- Task 0034 (JAcc — `branch_target_jacc` reused for CALLA).
Spec source: SPVU001A pages 12-48 (CALLA) and 12-49 (CALLR). Both:
  Push PC' to stack (SP -= 32), then jump.
    CALLA = 0x0D5F + 32-bit absolute target; PC <- address (low 4
            bits cleared).
    CALLR = 0x0D3F + 16-bit signed disp;     PC <- PC' + disp*16.
  Status bits all "Unaffected".
Acceptance Criteria:
- INSTR_CALLA = 7'd68, INSTR_CALLR = 7'd69.
- Decoder: single-fixed-encoding arms for the two opcodes. Both set
  rd_idx=15, alu_op=SUB, wb_reg_en=1, wb_flags_en=0,
  needs_memory_op=1. CALLA additionally sets needs_imm32=1
  (fetches LO + HI of the target address). CALLR additionally sets
  needs_imm16=1 (fetches the displacement word).
- Core's alu_a / alu_b swap groups: INSTR_CALLA and INSTR_CALLR
  join the existing PUSHST/POPST/CALL_RS group (alu_a = SP via
  rs2; alu_b = 32 constant).
- CORE_MEMORY arms for CALLA and CALLR: SAME as CALL_RS — push
  pc_value (= PC' at that point in the FSM) to mem[alu_result].
  Because each instruction fetches a different number of words
  before reaching CORE_MEMORY, pc_value naturally takes the
  correct PC' value (CALL Rs: PC+16; CALLR: PC+32; CALLA: PC+48).
- PC-load mux:
  - INSTR_CALLA → branch_target_jacc (same as JAcc).
  - INSTR_CALLR → branch_target_long (same as JRcc long).
- `sim/tb/tb_calla_callr.sv` runs two full call/return round trips:
    A) CALLA 0x0000_0640 → subroutine at word 100 writes A6 and RETS.
    B) CALLR with computed positive disp → subroutine at word 200
       writes A9 and RETS.
  Post-CALLA and post-CALLR MOVIs write distinct sentinel values to
  prove the returns landed correctly. Final SP back at the initial
  value after both round-trips.
Tests: tb_calla_callr PASS; tb_pushst/tb_popst/tb_call_rs/tb_rets
  still PASS; broader stack + JAcc/JRcc-long regression PASS;
  lint clean.
Docs: instruction_coverage.md (CALLA + CALLR rows), changelog.md,
  tasks.md.
Commit:
- b05a46f (CALLA + CALLR).

---

### Task 0052: RETI + multi-transaction memory FSM
Status: complete
Dependencies:
- Task 0047 (memory-write infrastructure / CORE_MEMORY).
- Task 0048 (POPST — popped-value → st_write_data path).
- Task 0050 (RETS — popped-value → PC-load path).
Spec source: SPVU001A page 12-230 + summary table. Single fixed
  encoding `0x0940`. Semantics:
    ST <- mem[SP]; SP += 32   (step 0: restore ST)
    PC <- mem[SP]; SP += 32   (step 1: restore PC)
  Status bits "Restored from popped ST" (i.e., the full 32-bit ST
  is written, all four flag bits included).
Acceptance Criteria:
- INSTR_RETI = 7'd70.
- Decoder: single-fixed-encoding arm with rd_idx=15, rs_idx=15,
  alu_op=ADD, wb_reg_en=1, wb_flags_en=0, needs_memory_op=1.
- Core: alu_a swap group includes INSTR_RETI (alu_a = SP via rs2);
  alu_b mux includes INSTR_RETI → `32'd64` (total SP increment for
  both pops).
- New multi-transaction infrastructure:
  - `mem_op_step` (2-bit) counter increments on every `mem_ack`
    while in CORE_MEMORY for multi-step iclasses; held at 0 for
    all single-transaction iclasses.
  - `popped_st_q` / `popped_pc_q` latch `mem_rdata` at the right
    step.
  - CORE_MEMORY → CORE_WRITEBACK transition now gates on
    `mem_op_step == 1` for INSTR_RETI (single-step iclasses
    transition on every ack as before).
- CORE_MEMORY arm for INSTR_RETI: 32-bit read at `rf_rs2_data`
  (step 0) or `rf_rs2_data + 32` (step 1).
- st_write_en includes INSTR_RETI; st_write_data mux returns
  `popped_st_q` for INSTR_RETI (full-ST write — all four flag bits
  restored atomically through the existing `st_write_en` priority
  path in the status register).
- PC-load mux: INSTR_RETI sets `pc_load_en = 1`, `pc_load_value =
  popped_pc_q`.
- `sim/tb/tb_reti.sv`: hand-built stack frame (no TRAP yet — that's
  the next task). Pre-place saved ST at `mem[SP]` and saved PC at
  `mem[SP+32]`, plus a `0xC0FF` halt sentinel at the popped-PC
  target. Critically, the popped-PC target MUST be a halt and
  nothing else — any instruction at the target would update N/Z
  and clobber the popped flag bits before the testbench could
  sample them. Verifications: ST = popped value (incl. all flag
  bits); PC >= popped-PC target (i.e., second pop landed); SP =
  SP_INIT + 64.
Tests: tb_reti PASS; the full 23-tb regression set still PASS;
  Verilator lint clean (`verilator --lint-only -Wall ...`).
Docs: instruction_coverage.md (RETI row), changelog.md, tasks.md.
Memory: tb-flag-side-effects.md (testbenches that verify ST after a
  control transfer MUST land on a halt sentinel — captured this
  lesson after the first tb_reti run failed with
  `expected=cafebabe actual=0afebabe` because a MOVI at the popped
  PC cleared N and Z before the check).
Commit:
- aef7603

---

### Task 0053: TRAP N (3-transaction software interrupt)
Status: complete
Dependencies:
- Task 0047 (memory-write infrastructure / CORE_MEMORY).
- Task 0052 (multi-transaction memory FSM; mem_op_step counter and
  popped_*_q latches).
Spec source: SPVU001A page 12-252. Encoding `0000 1001 000N NNNN`
  (top11 = `00001001_000`, N at instr[4:0]). Semantics:
    1) SP -= 32; mem[SP] <- PC'         (push return address)
    2) SP -= 32; mem[SP] <- ST          (push status register)
    3) ST <- 0x00000010                  (clear flags + IE; FS0=16)
    4) PC <- mem[0xFFFFFFE0 - N*32]     (fetch trap vector)
  TRAP 0 is special-cased in the spec (skips the pushes); we defer
  TRAP 0 to a follow-up.
Acceptance Criteria:
- INSTR_TRAP = 7'd71.
- Decoder: `top11 == TRAP_TOP11` (=11'b00001001_000) arms TRAP with
  rd_idx=15, rs_idx=15, k5=instr[4:0], alu_op=SUB, wb_reg_en=1,
  wb_flags_en=0, needs_memory_op=1.
- Core: INSTR_TRAP joins the alu_a swap group (alu_a = SP via rs2)
  and the alu_b = 32'd64 mux (SP - 64 via SUB).
- CORE_MEMORY arm for INSTR_TRAP cycles through three steps:
  - Step 0: `mem_we=1, mem_addr=rf_rs2_data - 32, mem_wdata=pc_value`.
  - Step 1: `mem_we=1, mem_addr=rf_rs2_data - 64, mem_wdata=st_value`.
  - Step 2: `mem_we=0, mem_addr=0xFFFFFFE0 - (k5<<5)`.
- mem_op_step counter extended to 3 steps (still 2-bit) for INSTR_TRAP.
- popped_pc_q latches mem_rdata on step 2 (= trap vector).
- CORE_MEMORY → CORE_WRITEBACK transition gates on `mem_op_step == 2`
  for INSTR_TRAP.
- st_write_en includes INSTR_TRAP; st_write_data mux returns the
  spec-fixed `32'h00000010` for INSTR_TRAP.
- PC-load mux: INSTR_TRAP sets `pc_load_en = 1`, `pc_load_value =
  popped_pc_q`.
- `sim/tb/tb_trap.sv`: runs TRAP 3 with DEPTH_WORDS=1024 (which
  causes 0xFFFFFFE0 - N*32 to alias to the top of memory at word
  indices 1016/1017 for N=3 — same arithmetic the model's
  word_idx slicing would do in any case, but explicit in the test
  setup). Pre-TRAP program loads SP, then PUTSTs a distinguishable
  value (0xCAFEBABE) into ST so we can verify push-then-replace
  ordering unambiguously. Service routine at the vector target
  writes A6 = 0x0BADC0DE and halts. Verifications:
    A6  = 0x0BADC0DE             (routine ran ⇒ PC <- vector worked)
    SP  = SP_INIT - 64           (two pushes happened)
    ST  = 0x00000010             (spec-fixed post-TRAP ST)
    pushed-ST slot  = 0xCAFEBABE (= pre-TRAP ST, distinguishable
                                    from post-TRAP overwrite)
    pushed-PC' slot non-zero     (return address captured)
Tests: tb_trap PASS; full 24-tb regression PASS;
  Verilator lint clean.
Docs: instruction_coverage.md (TRAP row), changelog.md, tasks.md.
Known limitations:
- TRAP 0 not yet handled. Per spec, TRAP 0 skips pushes (intended
  for use when SP is corrupt/uninitialised) and only loads ST=0x10
  + PC=mem[0xFFFFFFE0]. A follow-up task will add an early-exit
  path in the CORE_MEMORY arm for k5==0.
Commit:
- 337d8bc

---

### Task 0054: TRAP 0 (level-0 trap, no pushes)
Status: complete
Dependencies:
- Task 0053 (TRAP N with N>0).
Spec source: SPVU001A page 12-253 note 1: "The level 0 trap differs
  from all other traps; it does not save the old status register
  or program counter. This may be useful in cases where the stack
  pointer is corrupted or uninitialised."
  Semantics for N=0:
    ST <- 0x00000010
    PC <- mem[0xFFFFFFE0]
  SP NOT decremented; nothing pushed.
Acceptance Criteria:
- New `trap_skip_push` core wire: `(iclass == INSTR_TRAP) && (k5 == 0)`.
- alu_b mux for INSTR_TRAP returns 0 when `trap_skip_push` (so the
  ALU computes SP - 0 = SP and the regfile writeback is a no-op).
- CORE_MEMORY arm for INSTR_TRAP: when `trap_skip_push`, emit a
  single 32-bit read at 0xFFFFFFE0 (no PC'/ST writes).
- mem_op_step counter for INSTR_TRAP collapses to a single step
  when `trap_skip_push` (popped_pc_q latches on step 0).
- CORE_MEMORY → CORE_WRITEBACK transition for INSTR_TRAP fires
  on step 0 when `trap_skip_push`, on step 2 otherwise.
- ST overwrite (st_write_data = 0x10) and PC load
  (pc_load_value = popped_pc_q) reuse the existing TRAP wiring
  unchanged.
- `sim/tb/tb_trap0.sv`: runs TRAP 0 from a known SP and verifies:
    A6 = sentinel (service routine ran ⇒ vector fetch worked)
    SP unchanged (= SP_INIT)
    ST = 0x10
    Pre-placed sentinel values at mem[SP-32] and mem[SP-64]
    UNTOUCHED (proves the pushes were genuinely skipped).
Tests: tb_trap0 PASS; tb_trap (N=3) still PASS; full 25-tb
  regression PASS; Verilator lint clean.
Docs: instruction_coverage.md (TRAP N row updated to "all N
  implemented"), changelog.md, tasks.md.
Commit:
- f991683

---

### Task 0055: MMTM Rp, register list (multi-register push)
Status: complete (N flag added later in Task 0057)
Dependencies:
- Task 0047 (memory-write infrastructure / CORE_MEMORY).
- Task 0053 (multi-transaction memory FSM).
Spec source: SPVU001A page 12-111. Encoding `0000 1001 100R DDDD`
  + 16-bit register-list mask. For each set bit (lowest-order
  register first): Rp -= 32; mem[Rp] <- Rn. Final Rp points at the
  address of the lowest-written register.
Acceptance Criteria:
- INSTR_MMTM = 7'd72.
- Decoder: `top11 == MMTM_TOP11` (=11'b00001001_100) arms MMTM with
  rd_idx/rs_idx = instr[3:0] (Rp), rd_file/rs_file from R bit,
  needs_imm16=1 (mask fetch), wb_reg_en=1 (write final Rp),
  wb_flags_en=0 (N flag deferred), needs_memory_op=1.
- Core: new `mmtm_rp_q` (32-bit working Rp), `mmtm_mask_q` (16-bit
  residual mask), `mmtm_iter_idx` (4-bit priority-encoded lowest
  set bit of mask_q).
- `rf_rs1_idx` is multiplexed during CORE_MEMORY for MMTM to point
  at `mmtm_iter_idx`, so `rf_rs1_data` serves as the per-cycle
  push data source (regfile is async-read).
- Init: on CORE_EXECUTE → CORE_MEMORY transition for MMTM, capture
  `mmtm_rp_q <= rf_rs2_data - 32` (address of first push) and
  `mmtm_mask_q <= imm_lo_q` (the fetched mask word).
- CORE_MEMORY arm: drive `mem_req=1, mem_we=1, mem_addr=mmtm_rp_q,
  mem_size=32, mem_wdata=rf_rs1_data`. On ack, clear the just-pushed
  bit and (if more pushes remain) decrement `mmtm_rp_q` by 32.
- CORE_MEMORY → CORE_WRITEBACK transition gates on
  `mmtm_mask_will_be_empty` (i.e., the residual mask becomes 0
  after the current bit clear) for INSTR_MMTM.
- rf_wr_data mux: INSTR_MMTM returns `mmtm_rp_q` (final Rp = address
  of the last push).
- Bit-to-register mapping per assumption A0026: bit N = R(N) for
  both MMTM and MMFM. Graphical figure didn't survive pdftotext.
- `sim/tb/tb_mmtm.sv`: loads A0..A15 with recognisable sentinel
  values, sets Rp=A1=0x800, executes MMTM A1, {A0, A2, A4, A8,
  A12, A13, A14, A15(=SP)} (mask=0xF115). Verifies:
    Final A1 = 0x0800 - 8*32 = 0x0700
    mem[Rp-32]=A0, mem[Rp-64]=A2, …, mem[Rp-256]=SP
  (i.e., 8 32-bit writes at descending bit-addresses, lowest-order
  register at highest address).
Known limitations:
- N flag computation deferred. Per SPVU001A page 12-111:
  "N: Set to the sign of the result of 0 - Rp" with two edge cases
  (Rp=0 → N=1, Rp=0x80000000 → N=0). All four other flags
  ("C/Z/V Unaffected") — current implementation leaves all four
  unchanged.
Tests: tb_mmtm PASS; full 28-tb regression PASS; Verilator lint
  clean.
Docs: instruction_coverage.md (MMTM row), assumptions.md (A0026
  on mask bit-to-register mapping), changelog.md, tasks.md.
Commit:
- 608c7aa

---

### Task 0056: MMFM Rp, register list (multi-register pop)
Status: complete
Dependencies:
- Task 0047 (memory infrastructure / CORE_MEMORY).
- Task 0055 (MMTM — shares the iterator generalised here).
Spec source: SPVU001A page 12-109 (description) / 12-110 (worked
  example). Encoding `0000 1001 101R DDDD` + 16-bit register-list
  mask. For each register in the list, highest-order first:
  `Rn <- mem[Rp]; Rp += 32`. The post-increment fires after every
  read including the last, so final Rp = initial Rp + 32*count
  (points one word past the restored block). All flags Unaffected.
Acceptance Criteria:
- INSTR_MMFM = 7'd73.
- Decoder: `top11 == MMFM_TOP11` (=11'b00001001_101) arms MMFM with
  rd_idx/rs_idx = instr[3:0] (Rp), rd_file/rs_file from R bit,
  needs_imm16=1 (mask fetch), wb_reg_en=1 (write final Rp),
  wb_flags_en=0 (all flags Unaffected), needs_memory_op=1.
- Core: the MMTM iterator generalised to a shared MMTM/MMFM iterator.
  `mmtm_*` renamed to `mm_*` (`mm_rp_q`, `mm_mask_q`, `mm_iter_idx`,
  `mm_mask_will_be_empty`); new `is_mmtm`/`is_mmfm`/`is_mm` selectors.
  `mm_iter_idx` = lowest set bit for MMTM, highest set bit for MMFM.
- Seed/step asymmetry: on CORE_EXECUTE → CORE_MEMORY, MMTM seeds
  `mm_rp_q <= Rp - 32`, MMFM seeds `mm_rp_q <= Rp`. On each ack MMFM
  does `mm_rp_q <= mm_rp_q + 32` (every read, incl. last); MMTM does
  `-32` on every ack except the last.
- CORE_MEMORY arm for MMFM: `mem_req=1, mem_we=0, mem_addr=mm_rp_q,
  mem_size=32` (32-bit read). Restored value written to the regfile
  via the new `mmfm_pop_wr` path: `rf_wr_en` pulses on each ack,
  `rf_wr_idx = mm_iter_idx`, `rf_wr_data = mem_rdata`. The final-Rp
  write still happens at CORE_WRITEBACK (`rf_wr_data = mm_rp_q`).
  Rp is never in the list (spec: "unpredictable results"), so the
  two write users never target the same index.
- CORE_MEMORY → CORE_WRITEBACK gates on `mm_mask_will_be_empty` for
  both MMTM and MMFM.
- Bit-to-register mapping per assumption A0026 (bit N = R(N)). The
  TI worked example (page 12-110) now confirms this **absolutely**
  for MMFM, not just by internal consistency.
- `sim/tb/tb_mmfm.sv`: two subtests.
    (1) TI page-12-110 example in the B file: B0=0x10000 (stack
        pointer), memory pre-seeded with TI's exact stack image,
        mask {B1,B2,B4,B8,B12,B13,B14,SP}=0xF116. Checks the eight
        published register results bit-for-bit and B0=0x10100.
    (2) A-file MMTM → corrupt → MMFM round-trip, mask
        {A0,A2,A4,A8,A12,A13,A14}=0x7115 (SP omitted so it doesn't
        fight the B-file subtest's SP). Verifies all registers are
        restored to their pre-push sentinels and Rp returns to its
        initial value. Doubles as the MMTM regression after the
        `mm_*` rename.
Tests: tb_mmfm PASS; full 49-tb integration regression PASS under
  Verilator (3 module-level tbs need Questa, unchanged); lint clean.
Docs: instruction_coverage.md (MMFM row + MMTM row mm_* rename),
  changelog.md, tasks.md.
Commit:
- 287ccce

---

### Task 0057: MMTM N flag (sign of 0 - Rp)
Status: complete
Dependencies:
- Task 0055 (MMTM — this fills its one deferred gap).
Spec source: SPVU001A page 12-111, Status Bits: "N: Set to the sign
  of the result of 0 - Rp. (This value is typically 1 if the original
  contents of Rp are positive; otherwise, it is 0. The only exceptions
  to this are when Rp=80000000h, N is set to 0, and when Rp=0, N is
  set to 1.)" C, Z, V Unaffected.
Key insight: the spec definition + its two exceptions reduce to the
  single closed form **N = ~Rp[31]** (inverted sign bit of the ORIGINAL
  Rp). The ALU's raw `0 - Rp` sign bit would disagree at exactly the
  two edge cases (Rp=0 gives ALU N=0 but spec N=1; Rp=0x80000000 gives
  ALU N=1 but spec N=0), so N is computed directly from Rp[31], not
  taken from the ALU flags.
Acceptance Criteria:
- Decoder MMTM arm: `wb_flags_en = 1`, `wb_flag_mask =
  '{n:1, c:0, z:0, v:0}` (N-only; C/Z/V Unaffected).
- Core `flag_input` mux: new `INSTR_MMTM` case sets
  `n = ~rf_rs2_data[DATA_WIDTH-1]`. `rf_rs2_data` (= Rp index) still
  reads the ORIGINAL Rp during WRITEBACK because the final-Rp regfile
  write is in flight on the same edge and the async read returns the
  pre-write value — no extra latch needed. MMTM never writes the Rp
  slot before WRITEBACK, so the original Rp is stable throughout.
- MMFM is unaffected (all flags Unaffected — already correct).
- `sim/tb/tb_mmtm_nflag.sv`: four MMTM ops with Rp =
  0x00001000 (positive → N=1), 0xFFFFF000 (negative → N=0),
  0x00000000 (zero edge → N=1), 0x80000000 (min-neg edge → N=0).
  N is captured immediately after each MMTM with a GETST snapshot
  (GETST has wb_flags_en=0, so it doesn't disturb flags) into A2..A5;
  each snapshot's bit[31] is checked. Memory writes land at wrapped
  (Rp-32) addresses above the program region.
- `tb_mmtm` gains an N=1 assertion for its positive-Rp 8-register push
  (the trailing 0xC0FF JRUC halt doesn't touch flags, so MMTM's N
  persists to the check).
Tests: tb_mmtm_nflag PASS; tb_mmtm PASS; full 50-tb integration
  regression PASS under Verilator (3 module-level tbs need Questa,
  unchanged); lint clean.
Docs: instruction_coverage.md (MMTM row N flag), changelog.md,
  tasks.md.
Commit:
- 28eec5c

---

### Task 0058: Fix register-to-register MOVE opcode + cross-file support
Status: complete
Dependencies:
- Pre-existing MOVE Rs,Rd (the buggy version); unblocks the future
  MOVE-indirect family.
Trigger: while scoping the MOVE-indirect arc, found that reg-to-reg
  MOVE was decoded at 0x9000 (`1001 00FS`), which both TI editions
  assign to MOVE Rs,*Rd+ (a memory store). Surfaced to the user, who
  approved fixing the opcode AND adding cross-file support now.
Spec source: SPVU001A page 12-126 (MOVE Rs,Rd detail) + Move-Instruction
  summary table, verified against the 1986 first edition and the 1988
  User's Guide. Object code Figure 12-3: MOVE A0,B1 = 0x4E01.
Acceptance Criteria:
- Encoding `0100 11MS SSSR DDDD` (base 0x4C00). NOT a field move (full
  32-bit copy; no F bit). M=instr[9]: 0=same file, 1=cross-file.
  R=instr[4]: file for both (M=0) or source file (M=1, dest = other).
  Rs=instr[8:5], Rd=instr[3:0].
- Decoder MOVE_RR_TOP6 = 6'b010011 (was 6'b100100). rs_file = R;
  rd_file = (M==0)?R:~R. wb_flag_mask = N/Z/V only (C Unaffected, per
  spec); N/Z/V come from ALU PASS_A (V defaults 0).
- New `reg_file_t rs_file` field in decoded_instr_t (source file).
  Defaults to reg_file_from_instr; only MOVE_RR sets it for cross-file.
- Core: rf_rs1_file = (iclass==INSTR_MOVE_RR) ? decoded.rs_file :
  decoded.rd_file. (Localized; no other instruction affected.)
- tb_move_rr rewritten: encoding sanity vs TI object codes (0x4C22,
  0x4CB7, 0x4E01, 0x4E74), same-file cases (incl. zero/MIN_INT/B-file),
  and A->B / B->A cross-file cases with source-unchanged checks.
- All stack/control tbs that set SP via "MOVE A0/A2/A14,A15" updated
  from the 0x9000 form to 0x4C00: tb_pushst, tb_popst, tb_call_rs,
  tb_calla_callr, tb_rets, tb_reti, tb_trap, tb_trap0, tb_mmtm.
- The freed 0x9000/0x8000/0xA000 opcodes are now ILLEGAL until the
  MOVE-indirect family lands.
Tests: full 50-tb integration regression PASS under Verilator (3
  module-level tbs need Questa, unchanged); lint clean.
Docs: assumptions.md (A0020 corrected), instruction_coverage.md (MOVE
  row), changelog.md, tasks.md.
Commit:
- 6478e56

---

### Task 0059: MOVE Rs,*Rd / *Rs,Rd (register <-> indirect, field-size 32)
Status: complete
Dependencies:
- Task 0058 (freed the 0x8000 opcode block; corrected MOVE_RR).
- Task 0047 (CORE_MEMORY infrastructure).
Spec source: SPVU001A page 12-127 (MOVE Rs,*Rd store) and page 12-135
  (MOVE *Rs,Rd load). Encodings 1000 00FS / 1000 01FS SSSR DDDD.
Scope: field-size-32, word-aligned pointer only — the first increment
  of the MOVE-indirect family. F bit + runtime FS0/FS1 ignored.
Acceptance Criteria:
- INSTR_MOVE_FIELD_STORE = 7'd74, INSTR_MOVE_FIELD_LOAD = 7'd75.
- Decoder: top6 (instr[15:10]) == 100000 -> store, == 100001 -> load.
  Rs=instr[8:5], Rd=instr[3:0], R=instr[4] (same file). Store:
  wb_reg_en=0, wb_flags_en=0 (all Unaffected). Load: wb_reg_en=1,
  wb_flags_en=1 with N/Z/V mask (C Unaffected).
- Core CORE_MEMORY (single transaction, default ack -> WRITEBACK):
    store: mem_we=1, mem_addr=rf_rs2_data (Rd ptr), mem_wdata=rf_rs1_data
           (Rs data), mem_size=32.
    load:  mem_we=0, mem_addr=rf_rs1_data (Rs ptr), mem_size=32.
- Load writeback: rf_wr_data mux returns mem_rdata (valid at WRITEBACK,
  no new transaction issued there — same pattern POPST uses). flag_input
  mux: N=mem_rdata[31], Z=(mem_rdata==0), V=0.
- Pointer register is never written by the store (wb_reg_en=0).
- sim/tb/tb_move_indirect.sv: three store->load round-trips
  (0xCAFEBABE -> N=1/Z=0; 0 -> N=0/Z=1; 0x12345678 -> N=0/Z=0) checking
  memory contents, recovered register, pointer-unchanged, and load N/Z
  flags via GETST snapshots.
Known limitations:
- Field sizes other than 32, unaligned pointers, FE sign/zero extension,
  and the predecrement/postincrement/offset/absolute addressing modes
  are NOT implemented (their opcodes still ILLEGAL). Deferred to later
  MOVE-family tasks; see assumptions.md A0020.
Tests: tb_move_indirect PASS; full 51-tb integration regression PASS
  under Verilator (3 module-level tbs need Questa, unchanged); lint clean.
Docs: instruction_coverage.md (two MOVE rows), changelog.md, tasks.md.
Commit:
- a20ae35

---

### Task 0060: MOVE indirect with auto inc/dec (field-size 32)
Status: complete
Dependencies:
- Task 0059 (plain indirect MOVE datapath; reused here).
Spec source: SPVU001A pages 12-129 (Rs,*Rd+), 12-130 (Rs,-*Rd),
  12-139 (*Rs+,Rd), 12-143 (-*Rs,Rd). Encodings 1001/1010 00FS/01FS.
Scope: field-size-32, word-aligned (same as Task 0059). Step = ±32.
Acceptance Criteria:
- Reuse INSTR_MOVE_FIELD_STORE/_LOAD; new move_addr_mode_t move_mode
  field (NONE/POSTINC/PREDEC) on decoded_instr_t.
- Decoder: top6 100100 (store postinc, 0x9000), 101000 (store predec,
  0xA000), 100101 (load postinc, 0x9400), 101001 (load predec, 0xA400).
  Store inc/dec: wb_reg_en=1 (write pointer Rd back). Load inc/dec:
  wb_reg_en=1 (data to Rd) + pointer Rs updated in the core.
- Core helpers: mv_ptr (Rd for store / Rs for load), mv_addr (= mv_ptr,
  or mv_ptr-32 for predec), mv_ptr_new (mv_ptr±32). CORE_MEMORY uses
  mv_addr. Store pointer writeback at WRITEBACK (rf_wr_data=mv_ptr_new
  for INSTR_MOVE_FIELD_STORE). Load pointer writeback during CORE_MEMORY
  via mv_load_ptr_wr (rf_wr_idx=rs_idx, rf_wr_data=mv_ptr_new); data to
  Rd at WRITEBACK.
- Rs==Rd on a load: data wins (pointer written in CORE_MEMORY, data
  overwrites at WRITEBACK) — matches SPVU001A 12-143.
- sim/tb/tb_move_indirect_incdec.sv: post/pre store+load round-trips,
  pointer ±32, load N/Z flags, Rs==Rd data-wins case.
Known limitations:
- Field sizes != 32, unaligned pointers, FE extension, and the
  offset/absolute addressing modes still deferred (A0020). The
  indirect-to-indirect (*Rs,*Rd) forms are also not implemented.
Tests: tb_move_indirect_incdec PASS; full 52-tb integration regression
  PASS under Verilator (3 module-level tbs need Questa); lint clean.
Docs: instruction_coverage.md (four MOVE rows), changelog.md, tasks.md.
Commit:
- de8a9d1

---

### Task 0061: MOVE *Rs,*Rd (indirect-to-indirect, field-size 32)
Status: complete
Dependencies:
- Task 0059/0060 (indirect MOVE datapath).
- Task 0052 (mem_op_step multi-transaction FSM).
Spec source: SPVU001A page 12-137. Encoding 1000 10FS SSSR DDDD (0x8800).
Scope: plain form only (no inc/dec), field-size-32, word-aligned.
Acceptance Criteria:
- INSTR_MOVE_FIELD_M2M = 7'd76. Decoder: top6 == 100010. Rs=instr[8:5]
  (src ptr), Rd=instr[3:0] (dst ptr), same file. wb_reg_en=0,
  wb_flags_en=0 (all Unaffected), needs_memory_op=1.
- First memory-to-memory op: two-step CORE_MEMORY via mem_op_step.
  Step 0: read mem[Rs] (mem_we=0, addr=rf_rs1_data), latch into new
  move_data_q. Step 1: write move_data_q to mem[Rd] (mem_we=1,
  addr=rf_rs2_data). FSM -> WRITEBACK after step 1 ack.
- Pointers unchanged (plain form).
- sim/tb/tb_move_m2m.sv: two mem->mem copies; verify destination data,
  source unchanged, pointer registers unchanged.
Known limitations:
- The inc/dec indirect-to-indirect forms (*Rs+,*Rd+ 0x9800 /
  -*Rs,-*Rd 0xA800) auto-update BOTH pointers (two regfile writes) and
  have an Rs==Rd corner the spec only partly defines; deferred (still
  ILLEGAL). Offset/absolute modes, arbitrary field sizes, FE: A0020.
Tests: tb_move_m2m PASS; full 53-tb integration regression PASS under
  Verilator (3 module-level tbs need Questa); lint clean.
Docs: instruction_coverage.md (M2M row), changelog.md, tasks.md.
Commit:
- e92c939

---

### Task 0062: MOVE *Rs+,*Rd+ / -*Rs,-*Rd (indirect-to-indirect inc/dec)
Status: complete
Dependencies:
- Task 0061 (plain M2M; reused INSTR_MOVE_FIELD_M2M + move_data_q).
Spec source: SPVU001A page 12-138. Encodings 1001 10FS (0x9800,
  postinc) and 1010 10FS (0xA800, predec).
Scope: field-size-32, word-aligned. Both pointers step by ±32.
Acceptance Criteria:
- Decoder: top6 100110 (postinc), 101010 (predec) -> INSTR_MOVE_FIELD_M2M
  with move_mode POSTINC/PREDEC, wb_reg_en=1 (Rd writeback).
- Core helpers m2m_src_addr/m2m_dst_addr (= pointer, or pointer-32 for
  predec) and m2m_src_new/m2m_dst_new (pointer±32). Source pointer Rs is
  written at the step-0 read ack (m2m_src_wr -> rf_wr_idx=rs_idx); dest
  pointer Rd at WRITEBACK (rf_wr_data=m2m_dst_new). Step-1 write address
  = m2m_dst_addr (uses rf_rs2_data, which reflects the step-0 Rs update
  when Rs==Rd).
- Rs==Rd: WRITEBACK Rd write suppressed (!(is_mv_m2m && m2m_same_reg))
  so the register single-steps. For postincrement this matches spec
  12-138 (data to the incremented location). Predecrement Rs==Rd is
  spec-undefined; documented deviation in A0020.
- sim/tb/tb_move_m2m_incdec.sv: postinc + predec (Rs!=Rd) round-trips
  and the Rs==Rd postincrement incremented-location case (Case C).
Known limitations:
- Field sizes != 32, unaligned pointers, FE, and the offset/absolute
  addressing modes still deferred (A0020).
Tests: tb_move_m2m_incdec PASS; full 54-tb integration regression PASS
  under Verilator (3 module-level tbs need Questa); lint clean.
Docs: instruction_coverage.md (two M2M inc/dec rows), assumptions.md
  (A0020 Rs==Rd note), changelog.md, tasks.md.
Commit:
- 2dcf45d

---

### Task 0063: MOVE @SAddr,Rd / Rs,@DAddr (absolute addressing, field 32)
Status: complete
Dependencies:
- Task 0013 (imm32 fetch path); Task 0047 (CORE_MEMORY).
Spec source: SPVU001A page 12-134 (store) and 12-153 (load). Encodings
  0000 01F1 100R SSSS (store) / 0000 01F1 101R DDDD (load) + 32-bit addr.
Scope: field-size-32, word-aligned.
Acceptance Criteria:
- INSTR_MOVE_ABS_STORE = 7'd77, INSTR_MOVE_ABS_LOAD = 7'd78.
- Decoder: same `0000 01F1` family as SETF/SEXT/ZEXT —
  instr[15:10]==SETF_TOP6 && instr[8] && instr[7:5]==100 (store) / 101
  (load). Register operand at instr[3:0]; R=instr[4]. needs_imm32=1
  (fetch the 32-bit absolute bit-address, LSBs first). Store: wb_reg_en=0,
  wb_flags_en=0. Load: wb_reg_en=1, wb_flags_en=1 (N/Z mask).
- Core: single CORE_MEMORY transaction with mem_addr=imm32. Store
  mem_wdata=rf_rs1_data (Rs). Load -> rf_wr_data=mem_rdata + flag_input
  from mem_rdata.
- No collision with SETF/SEXT/ZEXT (distinct instr[7:5] sub-ops);
  tb_setf/tb_sext_zext/tb_exgf still PASS.
- sim/tb/tb_move_abs.sv: three store->load round-trips (neg/zero/pos)
  checking memory, recovered register, and load N/Z flags.
Known limitations:
- MOVE @SAddr,@DAddr (5-word mem-to-mem absolute) and offset addressing
  modes deferred; arbitrary field sizes / FE deferred (A0020).
Tests: tb_move_abs PASS; full 55-tb integration regression PASS under
  Verilator (3 module-level tbs need Questa); lint clean.
Docs: instruction_coverage.md (two absolute rows), changelog.md, tasks.md.
Commit:
- 3284c88

---

### Task 0064: MOVE Rs,*Rd(off) / *Rs(off),Rd (indirect with offset, field 32)
Status: complete
Dependencies:
- Task 0059 (register-indirect MOVE datapath); imm16 fetch path.
Spec source: SPVU001A page 12-132 (store) and 12-147 (load). Encodings
  1011 00FS (0xB000, store) / 1011 01FS (0xB400, load) + 16-bit offset.
Scope: field-size-32, word-aligned. Effective addr = pointer +
  sign_extend(offset16); pointer unchanged.
Acceptance Criteria:
- INSTR_MOVE_OFF_STORE = 7'd79, INSTR_MOVE_OFF_LOAD = 7'd80.
- Decoder: top6 101100 (store) / 101101 (load). needs_imm16=1,
  imm_sign_extend=1 (fetch the signed offset). Rs=instr[8:5],
  Rd=instr[3:0]. Store: data=Rs, pointer=Rd, wb_reg_en=0, wb_flags_en=0.
  Load: pointer=Rs, dest=Rd, wb_reg_en=1, wb_flags_en=1 (N/Z mask).
- Core: single CORE_MEMORY transaction. Store mem_addr=rf_rs2_data+imm32,
  mem_wdata=rf_rs1_data. Load mem_addr=rf_rs1_data+imm32 -> rf_wr_data=
  mem_rdata + flag_input from mem_rdata. (imm32 = sext(offset16).)
- sim/tb/tb_move_offset.sv: store->load round-trips with +0x20, -0x20
  (0xFFE0), and zero offsets; memory, recovered register,
  pointer-unchanged, and load N/Z flags.
Known limitations:
- The offset<->offset (3-word, *Rs(SOff),*Rd(DOff)) form, arbitrary
  field sizes, unaligned/non-16-aligned effective addresses, and FE
  deferred (A0020).
Tests: tb_move_offset PASS; full 56-tb integration regression PASS under
  Verilator (3 module-level tbs need Questa); lint clean.
Docs: instruction_coverage.md (two offset rows), changelog.md, tasks.md.
Commit:
- 5bc51d8

---

### Task 0065: MOVX / MOVY (half-register moves)
Status: complete
Dependencies: none (pure register op).
Spec source: SPVU001A pages 12-162 (MOVX) / 12-163 (MOVY). Encodings
  1110 110S SSSR DDDD (MOVX, 0xEC00) / 1110 111S SSSR DDDD (MOVY, 0xEE00).
First of the XY-coordinate instruction family.
Acceptance Criteria:
- INSTR_MOVX = 7'd81, INSTR_MOVY = 7'd82.
- Decoder: top7 MOVX_TOP7=1110_110 / MOVY_TOP7=1110_111. Same-file reg-reg
  (Rs=instr[8:5], Rd=instr[3:0]). wb_reg_en=1, wb_flags_en=0 (all flags
  Unaffected).
- Core rf_wr_data mux: MOVX = {old_Rd[31:16], Rs[15:0]} (replace X, keep
  Y); MOVY = {Rs[31:16], old_Rd[15:0]} (replace Y, keep X). The
  async-read regfile supplies the old Rd (rf_rs2_data) in the same
  WRITEBACK cycle as the write. No memory, no ALU.
- Also corrected a stale comment block above the MOVE_RR arm (it still
  cited the pre-0058 wrong 0x9000 encoding).
- sim/tb/tb_movx_movy.sv: half-preservation checks + TI worked examples
  (MOVX A4,A5 -> 0x00005678; MOVY A6,A7 -> 0x12340000).
Tests: tb_movx_movy PASS; full 57-tb integration regression PASS under
  Verilator (3 module-level tbs need Questa); lint clean.
Docs: instruction_coverage.md (MOVX/MOVY rows), changelog.md, tasks.md.
Commit:
- f238ea6

---

### Task 0066: ADDXY / SUBXY (dual 16-bit XY arithmetic)
Status: complete
Dependencies: none (pure register op).
Spec source: SPVU001A pages 12-41 (ADDXY) / 12-252 (SUBXY). Encodings
  1110 000S (ADDXY, 0xE000) / 1110 001S (SUBXY, 0xE200) SSSR DDDD.
Acceptance Criteria:
- INSTR_ADDXY = 7'd83, INSTR_SUBXY = 7'd84. Decoder top7 1110_000 /
  1110_001; same-file reg-reg; wb_reg_en=1, wb_flags_en=1 (full mask).
- Core XY datapath: X = low 16, Y = high 16. ADDXY Rd.X+=Rs.X, Rd.Y+=Rs.Y;
  SUBXY Rd.X-=Rs.X, Rd.Y-=Rs.Y — separate 16-bit adders/subtractors, NO
  carry/borrow between halves. Rd is source+dest (rf_rs2), Rs (rf_rs1).
- Status bits (verified vs TI tables):
    ADDXY: N=(Xres==0), V=Xres[15], Z=(Yres==0), C=Yres[15].
    SUBXY: N=(RsX==RdX), V=(RsX>RdX), Z=(RsY==RdY), C=(RsY>RdY); Task
      0134 resolved the `>` relations as signed 16-bit XY comparisons.
- rf_wr_data and flag_input muxes route addxy_result/subxy_result and
  addxy_flags/subxy_flags.
- sim/tb/tb_addxy_subxy.sv: ADDXY/SUBXY cases from TI's example tables
  checking the result AND the NCZV pattern (GETST snapshots).
Tests: tb_addxy_subxy PASS; full 58-tb integration regression PASS under
  Verilator (3 module-level tbs need Questa); lint clean.
Docs: instruction_coverage.md (ADDXY/SUBXY rows), assumptions.md (A0027),
  changelog.md, tasks.md.
Commit:
- 7522799

---

### Task 0067: CMPXY (nondestructive XY compare)
Status: complete
Dependencies: Task 0066 (XY subtract datapath, reused).
Spec source: SPVU001A page 12-55. Encoding 1110 010S SSSR DDDD (0xE400).
Acceptance Criteria:
- INSTR_CMPXY = 7'd85. Decoder top7 1110_010; same-file reg-reg;
  wb_reg_en=0 (NONDESTRUCTIVE — Rd unchanged), wb_flags_en=1.
- Status bits = sign bits of the per-half subtract results (distinct from
  SUBXY's signed greater-than flags): N=(Xres==0), V=Xres[15],
  Z=(Yres==0), C=Yres[15]
  where Xres=RdX-RsX, Yres=RdY-RsY. Unambiguous (no A0027 dependency).
- Core: new cmpxy_flags assign reusing xy_x_sub/xy_y_sub; flag_input mux
  routes it. No rf_wr_data entry (no writeback).
- sim/tb/tb_cmpxy.sv: TI example cases checking NCZV (GETST) and Rd/Rs
  unchanged.
Tests: tb_cmpxy PASS; full 59-tb integration regression PASS under
  Verilator (3 module-level tbs need Questa); lint clean.
Docs: instruction_coverage.md (CMPXY row), changelog.md, tasks.md.
Commit:
- 8fd5324

---

### Task 0068: HDL coding-guidelines audit + compliance fixes
Status: complete
Trigger: user added the Cyclone V HDL coding-guidelines bundle at
  `docs/hdl-coding-guidelines/` (23 docs, target 5CSEBA6U23I7/DE10-Nano)
  and asked to audit + bring the RTL into compliance.
What was done:
- Extracted the load-bearing [C] rules from the bundle (12/13/14 subset,
  16 economy, 32 operator cost, 90 anti-patterns, 91 bring-up checklist)
  and scanned all of rtl/ against them. The RTL was already compliant on
  every hard [C] rule (always_ff/comb split, single-driver, safe comb
  defaults, no unsynth constructs, no /%* , complete sync resets).
- Fixes: (1) added `default: ;` to the UNARY `case(instr[6:5])` in
  tms34010_decode.sv; (2) added `default_nettype none`/`wire` to all 8
  RTL files; (3) removed magic-number duplicates — TRAP entry-ST uses
  pkg ST_RESET_VALUE; new pkg REV_VALUE / TRAP_VECTOR_BASE replace inline
  literals in core.sv.
- Docs: CLAUDE.md now points to the bundle as the authoritative RTL style
  reference and records two intentional [C]-compliant deviations
  (sync active-high reset A0003; default_nettype placement). Memory:
  hdl_coding_guidelines.md added.
Deferred follow-up (own task): replace the pervasive 32'd32 / 32'd64 /
  6'd32 literals with DATA_WIDTH / 2*DATA_WIDTH / the 32-bit-transfer
  size — semantically these ARE DATA_WIDTH (one 32-bit word). Skipped
  here to keep the change focused and low-risk (~36 sites).
Tests: full 59-tb integration regression PASS under Verilator; lint
  clean. No behavioral change.
Docs: CLAUDE.md, changelog.md, tasks.md (no instruction_coverage change).
Commit:
- df05687

---

### Task 0069: word-step / mem-size literals → DATA_WIDTH constants
Status: complete
Trigger: deferred follow-up from Task 0068 (finish the "no magic numbers"
  compliance for the core datapath).
What was done:
- Added pkg constants WORD_BIT_SIZE (=DATA_WIDTH=32), WORD_BIT_SIZE_2
  (=2*DATA_WIDTH=64), MEM_SIZE_32 (=FIELD_SIZE_WIDTH'(DATA_WIDTH)=6'd32).
- Replaced all 33 occurrences of 32'd32 / 32'd64 / 6'd32 in
  tms34010_core.sv (stack/pointer steps + mem_size) with the constants.
  Left 32'd0 / 32'd1 and the shifter's local 6'd32 (rotate modulus, a
  module-internal datapath width, not a stack/mem constant).
Tests: full 59-tb integration regression PASS under Verilator; lint
  clean. Pure refactor, no behavioral change.
Docs: changelog.md, tasks.md.
Commit:
- 8612743

---

### Task 0070: CPW (Compare Point to Window) + 3rd regfile read port
Status: complete
Dependencies: none new (reuses reg-op writeback/flag paths).
Spec source: SPVU001A page 12-57. Encoding 1110 011S SSSR DDDD (0xE600).
Acceptance Criteria:
- INSTR_CPW = 7'd86. Decoder top7 1110_011; rd/rs from instr; wb_reg_en=1,
  wb_flags_en=1 with V-only flag mask.
- Reads 3 sources: Rs (point) on port 1, WSTART=B5 on port 2 (overridden;
  Rd is not a source for CPW), WEND=B6 on a NEW port 3 added to
  tms34010_regfile.sv. New pkg CPW_WSTART_IDX=5 / CPW_WEND_IDX=6.
- Datapath: X=low16 signed, Y=high16 signed. Rd[8:5] = {Rs.Y>WEND.Y,
  WSTART.Y>Rs.Y, Rs.X>WEND.X, WSTART.X>Rs.X}, all else 0. V = (any code
  bit set). N/C/Z Unaffected ($signed comparisons).
- sim/tb/tb_cpw.sv: TI example window (5,5)-(A,A) across points checking
  the code in Rd and V, plus a negative-X point locking the signed
  comparison. tb_regfile.sv updated for the new port.
Tests: tb_cpw PASS; full 60-tb integration regression PASS under
  Verilator (3 module-level tbs need Questa); lint clean.
Docs: instruction_coverage.md (CPW row), changelog.md, tasks.md.
Commit:
- 74ad4c1

---

### Task 0071: MPYS / MPYU multiply (FS1=32)
Status: complete
Dependencies: none new (reg-op writeback + a new 2-pass WRITEBACK).
Spec source: SPVU001A pages 12-164 (MPYS) / 12-166 (MPYU). Encodings
  0101 110S (MPYS, 0x5C00) / 0101 111S (MPYU, 0x5E00) SSSR DDDD.
Scope: FS1=32 (reset default = full 32-bit Rs); variable FS1 deferred.
Acceptance Criteria:
- INSTR_MPYS=7'd87, INSTR_MPYU=7'd88. Decoder top7 0101_110 / 0101_111.
  MPYS wb_flag_mask {n,z}; MPYU {z} only.
- Core: 64-bit product (mpy_sprod/$signed, mpy_uprod) latched in
  CORE_EXECUTE into mpy_product_q (registered DSP output). Even Rd (rd_idx
  [0]==0): WRITEBACK loops once via mpy_wb_step — pass 0 writes
  product[63:32] to Rd, pass 1 writes product[31:0] to Rd+1
  (rf_wr_idx = rd_idx+1). Odd Rd: single pass, product[31:0] to Rd.
  Flags from the full 64-bit product (N=bit63, Z=all-zero).
- sim/tb/tb_mpy.sv: TI MPYU example (even), MPYU odd, MPYS even negative,
  MPYS zero, MPYS odd negative; register-pair results + N/Z via GETST.
Known limitations:
- FS1 != 32 (variable Rs field size) not implemented — needs the
  field-size machinery (A0020). The 32×32 multiply is combinational +
  one register stage; if it fails Fmax, pipeline it (timing_notes.md).
Tests: tb_mpy PASS; full 61-tb integration regression PASS under
  Verilator (3 module-level tbs need Questa); lint clean.
Docs: instruction_coverage.md (MPYS/MPYU rows), timing_notes.md,
  changelog.md, tasks.md.
Commit:
- 8dd0b47

---

### Task 0072: DIVU unsigned divide + multi-cycle divider
Status: complete
Dependencies: Task 0070 (3rd regfile read port — used for Rd+1);
  Task 0071 (pair-writeback step, generalized here).
Spec source: SPVU001A page 12-69. Encoding 0101 101S SSSR DDDD (0x5A00).
Acceptance Criteria:
- New module rtl/core/tms34010_divider.sv: restoring 64÷32 → 32-bit
  quotient + 32-bit remainder + overflow; start/busy/done; ~32+2 cycles.
- INSTR_DIVU = 7'd89. Decoder top7 0101_101; wb_flag_mask {z, v}.
- core_state_t widened to 4 bits; new CORE_DIVIDE state. EXECUTE routes
  div to CORE_DIVIDE (div_start pulses on that edge; divider latches
  operands); CORE_DIVIDE holds until div_done -> WRITEBACK.
- Operands: rf_rs1=Rs (divisor), rf_rs2=Rd, rf_rs3=Rd+1 (port-3 override).
  dividend = even ? {Rd, Rd+1} : {0, Rd}.
- Even Rd: quotient -> Rd (pass 0), remainder -> Rd+1 (pass 1) via the
  shared pair_wb_step (renamed from mpy_wb_step). Odd Rd: quotient -> Rd.
  Overflow -> rf_wr_en suppressed (regs unchanged), V set, Z=0.
- sim/tb/tb_divu.sv: TI even example (exact quotient/remainder), odd-Rd,
  divide-by-zero, quotient-overflow, zero-quotient; Z/V flags.
Known limitations:
- MODU and signed DIVS/MODS reuse this divider — follow-ups.
Tests: tb_divu PASS; full 62-tb integration regression PASS under
  Verilator (3 module-level tbs need Questa); lint clean.
Docs: instruction_coverage.md (DIVU row), timing_notes.md, changelog.md,
  tasks.md.
Commit:
- 79384f3

---

### Task 0073: MODU unsigned modulo (reuses divider)
Status: complete
Dependencies: Task 0072 (the divider + CORE_DIVIDE).
Spec source: SPVU001A page 12-113. Encoding 0110 111S SSSR DDDD (0x6E00).
Acceptance Criteria:
- INSTR_MODU = 7'd90. Decoder top7 0110_111; wb_flag_mask {z, v}.
- Reuses tms34010_divider via the generalized is_div (now DIVU || MODU).
  dividend = {0, Rd} (32-bit); the divider's remainder -> Rd (single
  writeback; MODU never uses the pair-writeback).
- Flags: Z = (remainder==0), V = (Rs==0). On Rs=0: regfile write
  suppressed (Rd unchanged), and Z left Unaffected via a new runtime
  effective_flag_mask (clears the Z mask for MODU when div_overflow) —
  the static decode mask can't express the "Z unaffected only if Rs=0"
  rule. N/C Unaffected.
- sim/tb/tb_modu.sv: normal (Z=0), exact (Z=1), Rs=0 (V=1, Rd unchanged,
  Z unaffected — verified by entering the op with Z=0).
Known limitations:
- Signed DIVS/MODS reuse the divider with operand abs + result
  sign-conditioning — follow-up.
Tests: tb_modu PASS; full 63-tb integration regression PASS under
  Verilator (3 module-level tbs need Questa); lint clean.
Docs: instruction_coverage.md (MODU row), changelog.md, tasks.md.
Commit:
- 0d87bfd

---

### Task 0074: DIVS / MODS signed divide & modulo
Status: complete
Dependencies: Tasks 0072/0073 (divider + DIVU/MODU datapath).
Spec source: SPVU001A pages 12-63 (DIVS) / 12-112 (MODS). Encodings
  0101 100S (DIVS) / 0110 110S (MODS) SSSR DDDD.
Acceptance Criteria:
- INSTR_DIVS = 7'd91, INSTR_MODS = 7'd92. wb_flag_mask {n, z, v}.
- The divider stays unsigned; the core abs-conditions the inputs (|Rd|,
  |{Rd,Rd+1}|, |Rs|) and sign-conditions the outputs: quotient sign =
  Rd.sign ^ Rs.sign, remainder sign = Rd.sign. The signs are LATCHED at
  divide-start (div_dvd_sign_q/div_dvs_sign_q) — the even-Rd pass-0 write
  overwrites Rd before the remainder pass.
- Signed overflow div_signed_ovf: |quotient| won't fit signed-32 (positive:
  |q|>=2^31; negative: |q|>2^31, so -2^31 is valid), OR the unsigned
  div_overflow (Rs=0, |q|>=2^32). div_v selects signed vs unsigned ovf.
- Unified div-family rf_wr_data / flag_input (DIVU/DIVS/MODU/MODS).
  N = is_signed && !ovf && result[31]. MODS reuses effective_flag_mask
  (Z off on Rs=0).
- sim/tb/tb_divs_mods.sv: DIVS even (both signs, exact TI quotient/
  remainder), DIVS odd, Rs=0, MODS negative, MODS Rs=0 (Z unaffected).
Tests: tb_divs_mods PASS; full 64-tb integration regression PASS under
  Verilator (3 module-level tbs need Questa); lint clean.
Docs: instruction_coverage.md (DIVS/MODS rows), changelog.md, tasks.md.
Commit:
- e8ef4ea

---

### Task 0075: MPYS / MPYU variable multiplier width (FS1 != 32)
Status: complete
Dependencies: Task 0071 (MPYS/MPYU FS1=32 datapath).
Spec source: SPVU001A pages 12-164 (MPYS) / 12-166 (MPYU): the Rs
  multiplier is an FS1-bit field; FS1=0 encodes width 32.
Acceptance Criteria:
- Extract the low FS1 bits of Rs (`st_value[ST_FS1_HI:ST_FS1_LO]`) into
  `mpy_rs_field`: FS1=0 → full rf_rs1_data; MPYS sign-extends the field
  (high bit = bit FS1-1) to 32 bits; MPYU zero-extends. Rd (the
  multiplicand, rf_rs2_data) stays full 32-bit.
- `mpy_sprod`/`mpy_uprod` multiply rf_rs2_data by `mpy_rs_field` (not
  rf_rs1_data). FS1=32 behavior (tb_mpy) unchanged.
- sim/tb/tb_mpy_fs1.sv: MPYU at FS1=16/8/4 against TI's MPYU example
  (Rd=0xFFFF0000, Rs=0x10001010 → 0x0000100F_EFF00000 / 0x0000000F_FFF00000
  / 0), plus MPYS sign-extend (negative field → negative product) and
  positive-field cases. SETF (F=1) sets FS1 per case.
Tests: tb_mpy_fs1 PASS; tb_mpy regression PASS; full integration regression
  PASS under Verilator (3 module-level tbs need Questa); lint clean.
Docs: instruction_coverage.md (MPYS/MPYU rows), changelog.md, tasks.md.
Commit:
- 9ef3701

---

### Task 0076: sim_memory_model arbitrary bit-field read/write (field-machinery foundation)
Status: complete
Dependencies: none (sim-model only; RTL unchanged).
Spec source: TMS34010 memory is bit-addressed (SPVU001A §2 / memory_map.md);
  fields are 1..32 bits at any bit address (FS0/FS1 + FE0/FE1). This task
  builds the memory-model half of the field machinery; the core-side field
  extract/insert + FS-aware pointer step are later tasks.
Acceptance Criteria:
- sim_memory_model handles reads and writes of size 1..32 at ANY bit
  address, including fields straddling 16-bit word boundaries (span <= 3
  words). Writes are read-modify-write: bits outside the field preserved.
- Reads return the field zero-extended into the 32-bit bus (core applies
  FE sign/zero extension later). Sizes 0 or >32 warn.
- Backward compatible: the core's existing aligned 16/32-bit accesses are
  the boff=0 special cases; full integration regression unchanged.
- sim/tb/tb_mem_field.sv (drives the mem IF directly, no core): aligned
  32/16, sub-word read, RMW preservation, word-straddling 9-bit field,
  unaligned 32-bit field (spans 3 words), single-bit write/read.
Tests: tb_mem_field PASS; full integration regression PASS under Verilator
  (3 module-level tbs need Questa); lint clean.
Docs: assumptions.md (A0020 note), changelog.md, tasks.md, memory_map.md.
Commit:
- c5e3914

---

### Task 0077: field-size-aware MOVE register↔indirect (FS/FE machinery, core side)
Status: complete
Dependencies: Task 0076 (memory-model bit-field RMW).
Spec source: SPVU001A pages 12-127 (MOVE Rs,*Rd store) / 12-135 (MOVE
  *Rs,Rd load). Field size/extend from the F-selected ST pair (FS0/FE0 or
  FS1/FE1; FS=0 ⇒ 32); pointers step by ±FS.
Acceptance Criteria:
- New core signals: mv_fs (1..32 from FS0/FS1 per instr_word_q[9]), mv_fe
  (FE0/FE1), mv_fs_ext (±pointer step), mv_load_data (FE sign/zero extension
  of the loaded field). FIELD_STORE/FIELD_LOAD drive mem_size = mv_fs.
- FIELD_LOAD writeback + N/Z flags use mv_load_data (the extended value);
  ABS/OFF loads still use raw mem_rdata (they stay FS=32). Pointer step
  ±mv_fs for postinc/predec.
- M2M / offset / absolute MOVE forms remain FS=32 (later task).
- Existing tb_move_indirect / tb_move_indirect_incdec issue SETF FS0=0 up
  front (reset FS0=16) to preserve their 32-bit-move intent.
- sim/tb/tb_move_field.sv: FS=8 zext round-trip, FS=8 sext load, FS=16 sext
  round-trip, zero field (Z=1), FS-aware postinc (+8), FS=16 straddling field.
Tests: tb_move_field PASS; tb_move_indirect / tb_move_indirect_incdec updated
  and PASS; full integration regression PASS under Verilator (3 module-level
  tbs need Questa); lint clean.
Docs: instruction_coverage.md (6 register↔indirect rows), assumptions.md
  (A0020 note), changelog.md, tasks.md.
Commit:
- 5ea49ad

---

### Task 0078: field-size-aware MOVE offset & absolute forms
Status: complete
Dependencies: Task 0077 (mv_fs / mv_load_data field machinery).
Spec source: SPVU001A pages 12-132/12-141 (offset) / 12-134/12-153 (absolute).
Acceptance Criteria:
- OFF_STORE / OFF_LOAD / ABS_STORE / ABS_LOAD drive `mem_size = mv_fs`
  (F = instr bit 9 selects FS0/FS1). No pointer step (neither form moves a
  pointer).
- ABS_LOAD / OFF_LOAD writeback + N/Z flags use `mv_load_data` (FE-extended),
  merged with FIELD_LOAD in the rf_wr_data and flag_input muxes.
- M2M MOVE forms remain FS=32 (later task).
- Existing tb_move_offset / tb_move_abs issue SETF FS0=0 up front.
- sim/tb/tb_move_offabs_field.sv: offset FS=8 zext/sext, absolute FS=16
  zext/sext, absolute FS=12 straddling field.
Tests: tb_move_offabs_field PASS; tb_move_offset / tb_move_abs updated and
  PASS; full integration regression PASS under Verilator (3 module-level tbs
  need Questa); lint clean.
Docs: instruction_coverage.md (4 offset/absolute rows), assumptions.md
  (A0020 note), changelog.md, tasks.md.
Commit:
- e17910d

---

### Task 0079: field-size-aware MOVE indirect-to-indirect (M2M); MOVE field machinery complete
Status: complete
Dependencies: Task 0077/0078 (mv_fs machinery), Task 0062 (M2M datapath).
Spec source: SPVU001A pages 12-137 (MOVE *Rs,*Rd) / 12-138 (inc/dec).
Acceptance Criteria:
- The M2M arm drives `mem_size = mv_fs` on both steps (read into move_data_q,
  write low FS bits). m2m_src_addr/m2m_dst_addr/m2m_src_new/m2m_dst_new use
  ±mv_fs_ext instead of ±WORD_BIT_SIZE. No FE extension (mem→mem).
- Existing tb_move_m2m / tb_move_m2m_incdec issue SETF FS0=0 up front.
- sim/tb/tb_move_m2m_field.sv: FS=8 plain copy, FS=8 postinc (both pointers
  +8), FS=12 copy with src and dst both straddling word boundaries.
- After this task ALL MOVE addressing forms honor arbitrary FS 1..31 + FE,
  unaligned + word-straddling fields. (MOVB still pending.)
Tests: tb_move_m2m_field PASS; tb_move_m2m / tb_move_m2m_incdec updated and
  PASS; full integration regression PASS under Verilator (3 module-level tbs
  need Questa); lint clean.
Docs: instruction_coverage.md (3 M2M rows), assumptions.md (A0020 note),
  changelog.md, tasks.md.
Commit:
- 744afc8

---

### Task 0080: MOVB (move byte) — FS forced to 8
Status: complete
Dependencies: Tasks 0077–0079 (MOVE field machinery: mv_fs/mv_fe/mv_load_data).
Spec source: SPVU001A pages 12-118..12-125 (MOVB forms); loads sign-extend
  the byte to 32 bits with implicit compare-to-0 (12-120).
Acceptance Criteria:
- New `decoded.force_byte` field (pkg struct, decode default 0). When set:
  core forces `mv_fs = 8` and `mv_fe = 1` (sign-extend) regardless of ST.
- Decode 7 MOVB forms onto existing iclasses: Rs,*Rd (0x8C00, top7 1000110),
  *Rs,Rd (0x8E00, 1000111), *Rs,*Rd (0x9C00, 1001110), Rs,*Rd(off) (0xAC00,
  1010110), *Rs(off),Rd (0xAE00, 1010111), Rs,@DAddr (0x05E0: SETF_TOP6,
  !bit9, bit8, [7:5]=111), @SAddr,Rd (0x07E0: bit9, bit8, [7:5]=111).
  move_mode=NONE (MOVB has no inc/dec).
- Deferred (trap illegal): MOVB *Rs(SOff),*Rd(DOff) (0xBC00) and
  MOVB @SAddr,@DAddr (0x0340) — need new multi-word datapaths.
- sim/tb/tb_movb.sv: all 7 forms, sign-extend vs positive byte, M2M, offset,
  absolute, unaligned byte. No SETF (force_byte overrides reset FS0=16).
Tests: tb_movb PASS; full integration regression PASS under Verilator (3
  module-level tbs need Questa); lint clean.
Docs: instruction_coverage.md (9 MOVB rows incl. 2 deferred), assumptions.md
  (A0020 note), changelog.md, tasks.md.
Commit:
- 2e3f9a5

---

### Task 0081: I/O register file foundation (rtl/io/tms34010_io_regs.sv)
Status: complete
Dependencies: none (standalone module; begins the graphics/video/interrupt arc).
Spec source: 1988 User's Guide Figure 6-1 (page 6-3), §6 "I/O Registers".
Acceptance Criteria:
- New module: 32×16-bit registers in 0xC0000000–0xC00001FF (each 0x10-bit
  aligned). is_io = addr[31:30]==11 && addr[29:9]==0; index = addr[8:4].
  Sync active-high reset → all 0; sync write (req&we&is_io); async read;
  is_io output. Plain R/W storage (side-effect/read-only registers deferred).
- pkg: IO_BASE_ADDR / IO_REG_COUNT / IO_REG_IDX_W + IO_IDX_<NAME> for all 28
  named registers.
- sim/tb/tb_io_regs.sv: reset-0, write/read-back of the graphics control
  registers (no aliasing), boundary indices 0 and 31, is_io decode (in/out
  of range, wrong MSBs), non-I/O write ignored.
- Not wired into the core memory path yet (next: address-decode routing).
Tests: tb_io_regs PASS; full integration regression PASS under Verilator
  (3 module-level tbs need Questa); lint clean.
Docs: memory_map.md (full I/O register table), architecture.md (module map),
  changelog.md, tasks.md.
Commit:
- ba4106e

---

### Task 0082: wire the I/O register file into the core memory path
Status: complete
Dependencies: Task 0081 (io_regs module).
Spec source: SPVU001A §6 (I/O Registers), Figure 6-1.
Acceptance Criteria:
- Instantiate tms34010_io_regs inside tms34010_core. Compute io_is_io from
  mem_addr; mux io_regs async read into mem_rdata_eff (all internal mem_rdata
  consumers now read mem_rdata_eff).
- Gate the external write for I/O space: mem_we = mem_we_int && !io_is_io
  (so I/O writes don't corrupt external RAM). External cycle still issued
  (provides ack).
- Latch the I/O read at the access ack (io_rdata_q/io_is_io_q) so it persists
  into WRITEBACK like the external model holds mem_rdata; effective-read mux
  uses combinational decode during an active transaction (mem_req), latched
  value after.
- sim/tb/tb_io_access.sv: MOVE absolute (FS=16) writes PSIZE/PMASK on-chip and
  reads back (no aliasing); a normal external MOVE still works.
- A0028 documents the integration model + the deferred external-cycle/on-chip
  ack refinement and the 16-bit I/O-access assumption.
Tests: tb_io_access PASS; full integration regression PASS under Verilator
  (3 module-level tbs need Questa); lint clean.
Docs: assumptions.md (A0028), architecture.md, changelog.md, tasks.md.
Commit:
- ab5b69a

---

### Task 0083: PIXT pixel transfer (linear forms) — first graphics instruction
Status: complete
Dependencies: Tasks 0077–0080 (field machinery + force_byte pattern), Task
  0081/0082 (I/O regs + PSIZE readable in the core).
Spec source: SPVU001A §"PIXT" (Pixel Transfer) detail pages; encoding table.
Acceptance Criteria:
- New `decoded.force_pixel` field. When set: core uses mv_fs = io_psize and
  mv_fe = 0 (zero-extend). io_regs exposes `psize_o`.
- Decode 3 linear PIXT forms: Rs,*Rd (0xF800 top7 1111100 -> FIELD_STORE),
  *Rs,Rd (0xFA00 top7 1111101 -> FIELD_LOAD), *Rs,*Rd (0xFC00 top7 1111110 ->
  FIELD_M2M), each with force_pixel.
- PIXT store/M2M: all flags Unaffected. PIXT load: V = (pixel != 0), N/C/Z
  masked off (Undefined); flag_input.v overridden for force_pixel.
- XY PIXT forms (0xF000/0xF200/0xF400) remain illegal (need XY conversion).
- Replace mode only; PMASK/transparency/PPOP deferred (no-op at reset).
- sim/tb/tb_pixt.sv: set PSIZE via MOVE to I/O reg; PIXT store/load/M2M at
  PSIZE=8 (+ zero-extend vs MOVB, V flag), a zero pixel (V=0), and a PSIZE=4
  pixel.
Tests: tb_pixt PASS; full integration regression PASS under Verilator (3
  module-level tbs need Questa); lint clean.
Docs: instruction_coverage.md (6 PIXT rows: 3 done + 3 deferred), changelog.md,
  tasks.md.
Commit:
- e65ba2c

---

### Task 0084: CVXYL (convert XY address to linear)
Status: complete
Dependencies: Task 0081/0083 (I/O regs + PSIZE/CONVDP taps), Task 0070 (3rd
  regfile read port, here repurposed for OFFSET=B4).
Spec source: SPVU001A page 12-59. Encoding 1110 100S SSSR DDDD (0xE800).
Acceptance Criteria:
- INSTR_CVXYL = 7'd93. Datapath: Rd = ((Y << (31-CONVDP[4:0])) | (X <<
  log2(PSIZE))) + OFFSET; X=Rs[15:0], Y=Rs[31:16] sign-extended.
- io_regs gains convdp_o tap; B_OFFSET_IDX/B_DPTCH_IDX constants. rf_rs3
  reads OFFSET (B4) for CVXYL.
- All flags Unaffected. Rs/Rd same file.
- sim/tb/tb_cvxyl.sv: TI example table (PSIZE 16/8/4/2/1, CONVDP 0x14/0x13,
  nonzero OFFSET). PSIZE=4 / nonzero-OFFSET rows use recomputed exact values
  (spec table OCR-corrupted there).
Tests: tb_cvxyl PASS; full integration regression PASS under Verilator (3
  module-level tbs need Questa); lint clean.
Docs: instruction_coverage.md (CVXYL row), changelog.md, tasks.md.
Commit:
- 27b4319

---

### Task 0085: XY-addressed PIXT (store 0xF000 / load 0xF200)
Status: complete
Dependencies: Task 0083 (PIXT/force_pixel), Task 0084 (CVXYL conversion + B4
  OFFSET on read port 3).
Spec source: SPVU001A §"PIXT" (XY addressing); conversion per 12-59.
Acceptance Criteria:
- New `decoded.xy_addr` flag. When set, the field machinery converts the
  pointer (mv_ptr) XY -> linear: ((Y<<(31-CONV)) | (X<<log2 PSIZE)) + OFFSET,
  CONV = CONVDP (store/dest) or CONVSP (load/source). io_regs gains convsp_o;
  rf_rs3 reads OFFSET (B4) for xy_addr.
- Decode 0xF000 -> FIELD_STORE+force_pixel+xy_addr; 0xF200 ->
  FIELD_LOAD+force_pixel+xy_addr (V=pixel!=0, N/C/Z masked).
- XY-to-XY M2M (0xF400) deferred (dual conversion) -> illegal.
- sim/tb/tb_pixt_xy.sv: XY store (CONVDP) + XY load (CONVSP), with a
  CONVSP!=CONVDP case proving the load uses the source pitch.
Tests: tb_pixt_xy PASS; tb_pixt/tb_cvxyl regress PASS; full integration
  regression PASS under Verilator (3 module-level tbs need Questa); lint clean.
Docs: instruction_coverage.md (3 XY-PIXT rows), changelog.md, tasks.md.
Commit:
- 4e1b819

---

### Task 0086: XY-to-XY PIXT M2M (0xF400) — completes the PIXT family
Status: complete
Dependencies: Task 0085 (xy_addr conversion path).
Spec source: SPVU001A §"PIXT" (Indirect XY to Indirect XY).
Acceptance Criteria:
- Decode 0xF400 (top7 1111010) -> FIELD_M2M + force_pixel + xy_addr.
- New pix_xy_dst_linear converts the destination (rf_rs2) via CONVDP; the
  M2M src/dst address muxes use pix_xy_linear (src, CONVSP) and
  pix_xy_dst_linear (dst, CONVDP) when xy_addr.
- All 6 PIXT forms now implemented (replace mode).
- sim/tb/tb_pixt_xy.sv extended: XY-to-XY M2M copy (src via CONVSP, dst via
  CONVDP).
Tests: tb_pixt_xy PASS; full integration regression PASS under Verilator (3
  module-level tbs need Questa); lint clean.
Docs: instruction_coverage.md (XY M2M row), changelog.md, tasks.md.
Commit:
- bec49f8

---

### Task 0087: FILL L — first multi-cycle graphics engine
Status: complete
Dependencies: Task 0081/0082 (I/O regs + PSIZE), field machinery, B-file
  graphics register reads.
Spec source: SPVU001A page 12-80. Fixed opcode 0x0FC0.
Acceptance Criteria:
- INSTR_FILL_L = 7'd94. New core states CORE_FILL_SETUP/CORE_FILL/CORE_FILL_WB.
  EXECUTE latches DADDR(B2)/DPTCH(B3)/DYDX(B7) via the 3 read ports;
  CORE_FILL_SETUP latches COLOR1(B9). CORE_FILL writes one PSIZE-bit COLOR1
  pixel per ack; column counter to DX, row base += DPTCH per row, DY rows.
  DADDR updated to the pixel following the last; written to B2 in CORE_FILL_WB.
- All flags Unaffected. Replace mode only (no window/PMASK/transparency/PPOP).
- pkg: B_DADDR_IDX/B_DYDX_IDX/B_COLOR1_IDX constants.
- sim/tb/tb_fill_l.sv: 2×4 fill (PSIZE=8, COLOR1=0xAA); checks filled words,
  untouched inter-row gap, updated DADDR (0x8A0).
Tests: tb_fill_l PASS; full integration regression PASS under Verilator (3
  module-level tbs need Questa); lint clean.
Docs: instruction_coverage.md (FILL L row), changelog.md, tasks.md.
Commit:
- eff49f3

---

### Task 0088: FILL XY
Status: complete
Dependencies: Task 0087 (FILL engine), Task 0084/0085 (XY conversion).
Spec source: 1988 User's Guide pages 12-84 through 12-86. Fixed opcode 0x0FE0.
Acceptance Criteria:
- INSTR_FILL_XY = 7'd95. is_fill covers FILL_L|FILL_XY; fill_is_xy selects
  the start conversion. At CORE_FILL_SETUP, port 3 reads OFFSET(B4) and the
  XY DADDR (latched raw at EXECUTE) is converted to a linear start
  (CONVDP+OFFSET+PSIZE); FILL_L uses the raw DADDR. Rest of the engine shared.
- Final DADDR written back linear (A0029, resolved by Task 0133).
- sim/tb/tb_fill_xy.sv: XY start (X=0x20,Y=1, CONVDP=0x1B, OFFSET=0x800 ->
  0x910) fills a 2×2 array; checks words, gap, DADDR (0x9A0).
Tests: tb_fill_xy PASS; tb_fill_l regress PASS; full integration regression
  PASS under Verilator (3 module-level tbs need Questa); lint clean.
Docs: instruction_coverage.md (FILL XY row), assumptions.md (A0029),
  changelog.md, tasks.md.
Commit:
- 77272bb

---

### Task 0089: PIXT store transparency (CONTROL.T)
Status: complete
Dependencies: Task 0083/0085 (PIXT store forms), Task 0081 (I/O regs).
Spec source: SPVU001A CONTROL register, T bit (bit 5).
Acceptance Criteria:
- io_regs control_o tap; pkg CTRL_T_BIT (=5) + CTRL_W/PBH/PBV/PPOP consts.
- pixt_transp_skip = force_pixel && is_mv_store && CONTROL[5] &&
  ((Rs & mv_fmask) == 0). EXECUTE → WRITEBACK (skip memory) when set, so the
  transparent pixel is not written. Replace-mode only (the processed value =
  source). Applies to PIXT store linear+XY; load/M2M unaffected.
- sim/tb/tb_pixt_transp.sv: T=1 zero pixel skipped (dest preserved), T=0 zero
  pixel written, nonzero always written.
Tests: tb_pixt_transp PASS; full integration regression PASS under Verilator
  (3 module-level tbs need Questa); lint clean.
Docs: instruction_coverage.md (PIXT store rows), changelog.md, tasks.md.
Commit:
- 319d0e9

---

### Task 0090: PIXT store plane masking (RMW pixel-write engine)
Status: complete
Dependencies: Task 0089 (transparency / control_o tap).
Spec source: SPVU001A PMASK register; pixel processing reads dest "through
  the plane mask".
Acceptance Criteria:
- io_regs pmask_o tap. PIXT store (force_pixel && is_mv_store, non-transparent)
  becomes a 2-step CORE_MEMORY RMW: step0 read dest pixel (latch pix_dest_q),
  step1 write merged = (src & ~pmask_field) | (dest & pmask_field), pmask_field
  = low PSIZE bits of PMASK. Gated on force_pixel so MOVE store stays 1-step.
  mem_op_step + CORE_MEMORY exit updated for FIELD_STORE pixt_rmw.
- PMASK=0 ⇒ merged=src; all existing PIXT/MOVE-store tests stay green.
- sim/tb/tb_pixt_pmask.sv: low/high nibble masks; protected planes keep dest.
Tests: tb_pixt_pmask PASS; existing PIXT/MOVE store tests PASS; full
  integration regression PASS under Verilator (3 module-level tbs need
  Questa); lint clean.
Docs: instruction_coverage.md (PIXT store rows), changelog.md, tasks.md.
Commit:
- a9e2c4c

---

### Task 0091: PIXT store Boolean pixel processing (PPOP)
Status: complete
Dependencies: Task 0090 (RMW pixel-write engine).
Spec source: SPVU001A CONTROL.PPOP (bits 14-10); the 16 Boolean PPOP table.
Acceptance Criteria:
- pixt_processed = PPOP(rf_rs1_data, pix_dest_q) via a 16-way case on
  io_control[CTRL_PPOP_HI:CTRL_PPOP_LO]; arith codes (0x10-0x15) fall back to
  replace (TODO). Unified merge: transparency tests the PROCESSED pixel (T &&
  processed==0 ⇒ write dest back); then plane mask. The Task 0089 EXECUTE-skip
  is removed (transparent store now RMWs and writes dest back; spec: "memory
  cycles still occur"). pixt_rmw = force_pixel && is_mv_store.
- Reset defaults (PPOP=0/T=0/PMASK=0) ⇒ plain replace; existing tests green.
- sim/tb/tb_pixt_ppop.sv: replace/AND/OR/XOR/NOT-S/no-change (S=0xCC,D=0xAA).
Tests: tb_pixt_ppop PASS; existing PIXT tests (transp/pmask) PASS; full
  integration regression PASS under Verilator (3 module-level tbs need Questa);
  lint clean.
Docs: instruction_coverage.md (PIXT store rows), changelog.md, tasks.md.
Commit:
- 991c6cf

---

### Task 0092: PIXT store arithmetic pixel processing (PPOP 0x10-0x15)
Status: complete
Dependencies: Task 0091 (PPOP boolean engine).
Spec source: SPVU001A CONTROL.PPOP arithmetic table (0x10-0x15).
Acceptance Criteria:
- Add the 6 arith ops to the PPOP case on the unsigned PSIZE-bit pixels
  (pix_src_p/pix_dst_p = Rs/dest & mv_fmask): D+S, ADDS (sat all-1s via
  pix_addsum > mv_fmask), D-S, SUBS (sat 0), MAX, MIN. Completes 22 PPOP ops.
- sim/tb/tb_pixt_ppop_arith.sv: all six incl. ADDS/SUBS saturation.
Tests: tb_pixt_ppop_arith PASS; full integration regression PASS under
  Verilator (3 module-level tbs need Questa); lint clean.
Docs: instruction_coverage.md (PIXT store row), changelog.md, tasks.md.
Commit:
- a7ef356

---

### Task 0093: FILL pixel processing (shared PPOP function; per-pixel RMW)
Status: complete
Dependencies: Tasks 0091/0092 (PPOP engine), Task 0087 (FILL).
Spec source: SPVU001A FILL + CONTROL (PPOP/T/PMASK apply to FILL).
Acceptance Criteria:
- Refactor the 22-way PPOP into a module function ppop_apply(src,dest,ppop,
  fmask); PIXT uses it (pixt_processed). Regression unchanged.
- FILL CORE_FILL loop becomes a per-pixel read-modify-write: fill_substep_q 0
  reads dest into fill_dest_q, 1 writes fill_merged = PPOP(COLOR1,dest) plane-
  masked + transparency-checked. Counters advance on the write ack; exit on
  (write ack && fill_done). Reset defaults ⇒ replace (existing FILL tests
  green).
- sim/tb/tb_fill_ppop.sv: XOR fill, transparent COLOR1=0 fill, plane-masked
  fill.
Tests: tb_fill_ppop PASS; tb_fill_l/tb_fill_xy + PIXT PPOP tests PASS; full
  integration regression PASS under Verilator (3 module-level tbs need Questa);
  lint clean.
Docs: instruction_coverage.md (FILL rows), changelog.md, tasks.md.
Commit:
- b648563

---

### Task 0094: PIXBLT L,L — source-array graphics engine
Status: complete
Dependencies: Task 0087/0093 (FILL engine + shared ppop_apply), pixel engine.
Spec source: SPVU001A PIXBLT L,L (0x0F00).
Acceptance Criteria:
- INSTR_PIXBLT_LL; state enum widened to 5 bits + CORE_PBLT_SETUP/CORE_PBLT/
  CORE_PBLT_WB/CORE_PBLT_WB2. pkg B_SADDR/B_SPTCH/B_COLOR0 consts.
- Read 5 implied B-regs across EXECUTE (SADDR/DADDR/DYDX) + SETUP (SPTCH/DPTCH)
  via the 3 ports (rf_rs is_pblt overrides). Per-pixel 3-step loop: read src,
  read dst, write ppop_apply(src,dst) merged (transp + PMASK). Dual address
  trackers advance ±PSIZE + row-step by pitch. SADDR→B0, DADDR→B2 updated
  (CORE_PBLT_WB / WB2). Deferred: corner adjust, window, XY/B variants.
- sim/tb/tb_pixblt_ll.sv: 2×4 transfer; check pixels, source unchanged,
  SADDR/DADDR updated.
Tests: tb_pixblt_ll PASS; full integration regression PASS under Verilator
  (3 module-level tbs need Questa); lint clean.
Docs: instruction_coverage.md (PIXBLT rows), changelog.md, tasks.md.
Commit:
- 85053cd

---

### Task 0095: PIXBLT XY variants (L,XY / XY,L / XY,XY)
Status: complete
Dependencies: Task 0094 (PIXBLT L,L engine), XY conversion.
Spec source: SPVU001A PIXBLT XY variants (0x0F20/0x0F40/0x0F60).
Acceptance Criteria:
- New struct flags blt_src_xy/blt_dst_xy; decode 0x0F20 (dst), 0x0F40 (src),
  0x0F60 (both) -> INSTR_PIXBLT_LL + flags. rf_rs3 reads OFFSET(B4) at
  PBLT_SETUP. Convert XY SADDR/DADDR to linear at SETUP (pblt_src_conv via
  CONVSP, pblt_dst_conv via CONVDP, +OFFSET+log2 PSIZE).
- Updated SADDR/DADDR written back linear. Rest shared with L,L.
- sim/tb/tb_pixblt_xy.sv: PIXBLT XY,XY both converted; check transfer + addrs.
Tests: tb_pixblt_xy PASS; tb_pixblt_ll regress PASS; full integration
  regression PASS under Verilator (3 module-level tbs need Questa); lint clean.
Docs: instruction_coverage.md (PIXBLT XY rows), changelog.md, tasks.md.
Commit:
- 7fd6225

---

### Task 0096: PIXBLT B,L / B,XY — 1-bit source color-expand
Status: complete
Dependencies: Task 0094/0095 (PIXBLT engine + XY).
Spec source: SPVU001A PIXBLT B,L (0x0F80) / B,XY (0x0FA0).
Acceptance Criteria:
- New struct flag blt_binary; new state CORE_PBLT_SETUP2 (5'd16) reads
  COLOR0(B8)/COLOR1(B9). Source sub-step reads 1 bit (mem_size=1); src addr
  advances by pblt_src_step (1 for binary, PSIZE otherwise). pblt_src_eff =
  src_bit ? COLOR1 : COLOR0 (or the raw pixel) feeds ppop_apply.
- Decode 0x0F80 (B,L) / 0x0FA0 (B,XY = binary + dst XY).
- sim/tb/tb_pixblt_b.sv: 4-bit source bitmap expanded; check pixels + SADDR/
  DADDR updates. All 6 PIXBLT forms now implemented.
Tests: tb_pixblt_b PASS; tb_pixblt_ll/tb_pixblt_xy regress PASS; full
  integration regression PASS under Verilator (3 module-level tbs need Questa);
  lint clean.
Docs: instruction_coverage.md (PIXBLT B rows), changelog.md, tasks.md.
Commit:
- 6ea50b1

---

### Task 0097: video timing generator (standalone module)
Status: complete
Dependencies: none (standalone; begins the video subsystem).
Spec source: 1988 UG §"Video Timing"; HESYNC/HEBLNK/HSBLNK/HTOTAL + V* regs.
Acceptance Criteria:
- New rtl/video/tms34010_video.sv: HCOUNT increments per clk, wraps at HTOTAL
  (VCOUNT++); VCOUNT wraps at VTOTAL. hsync=(hcount<hesync); hblank=(hcount<
  heblnk)||(hcount>=hsblnk); same for V; blank=hblank||vblank; dpyint_pulse=
  (hcount==0)&&(vcount==dpyint). Sync active-high (document); rising-edge clk
  (A0003).
- sim/tb/tb_video.sv: per-cycle transition + window + strobe checks over
  ~2.5 frames; confirms HTOTAL/VTOTAL reached and wrap.
- Not yet wired to io_regs timing values or a pixel clock (follow-up).
Tests: tb_video PASS; full integration regression PASS under Verilator (3
  module-level tbs need Questa); lint clean.
Docs: architecture.md (module map), changelog.md, tasks.md.
Commit:
- 2f78003

---

### Task 0098: maskable-interrupt priority encoder (standalone module)
Status: complete
Dependencies: none (standalone; begins the interrupt subsystem).
Spec source: 1988 UG §8.3/§8.4, Tables 8-2/8-3 (vectors + priority).
Acceptance Criteria:
- New rtl/core/tms34010_int_ctrl.sv: int_req = ie && |(intpend & intenb over
  the maskable bits); int_vector = the highest-priority winner's vector.
  Priority HI>DI>WV>INT1>INT2. pkg INT_*_BIT + INT_VEC_* constants.
- sim/tb/tb_int_ctrl.sv: gating (INTENB/IE), priority order, vector mapping.
- FSM recognition + entry sequence is the follow-up (reuse TRAP push).
Tests: tb_int_ctrl PASS; full integration regression PASS under Verilator (3
  module-level tbs need Questa); lint clean.
Docs: changelog.md, tasks.md.
Commit:
- 840917e

---

### Task 0099: DRAM-refresh address generator (standalone module)
Status: complete
Dependencies: none (standalone).
Spec source: 1988 UG §6 (REFCNT, CONTROL.RR), page 6-11.
Acceptance Criteria:
- New rtl/video/tms34010_refresh.sv: prescaler off clk, interval 32 (RR=00) /
  64 (RR=01); RR=10/11 disable. 8-bit REFCNT row increments per refresh,
  wraps 255->0; refresh_req one-clock strobe.
- sim/tb/tb_refresh.sv: interval per RR, row increment, RR=11 disable.
- Not yet wired to a memory arbiter (follow-up).
Tests: tb_refresh PASS; full integration regression PASS under Verilator (3
  module-level tbs need Questa); lint clean.
Docs: architecture.md (module map), changelog.md, tasks.md.
Commit:
- dee5c72

---

### Task 0100: Maskable-interrupt recognition + entry sequence (core integration)
Status: complete
Dependencies: Task 0098 (int_ctrl), Task 0082 (io_regs integration).
Spec source: 1988 UG §8 (interrupt processing: push PC+ST, vector→PC, IE clear);
  RETI restore semantics. Vectors/priority per Table 8-2 and int_ctrl.
Acceptance Criteria:
- io_regs: add INTENB/INTPEND taps (wire in tb_io_regs).
- core: instantiate tms34010_int_ctrl (ie=ST.IE). At CORE_FETCH, if int_req,
  divert (no fetch) into CORE_INT_PUSH_PC → PUSH_ST → VECTOR → DONE. Push PC at
  SP-32, ST at SP-64; read vector→PC; SP-=64; clear ST.IE only (A0030). No new
  core ports.
- tb_int_entry: INTENB.DI+INTPEND.DI+EINT → ISR entered, post-EINT instr
  skipped, SP-64, pushed PC/ST correct, ST.IE cleared.
Tests: tb_int_entry PASS; full integration regression PASS under Verilator
  (3 module-level tbs need Questa); lint clean.
Docs: assumptions.md (A0030), architecture.md, changelog.md, tasks.md.
Commit:
- 678fa11

---

### Task 0101: JRcc/JAcc general-arithmetic condition codes (C/V/NV/N/NN)
Status: complete
Dependencies: none (extends existing JRcc/JAcc decode + branch evaluator).
Spec source: SPVU001A Table 12-8 (page 12-31): single-flag arithmetic codes
  C/B(1000), V(1100), NV(1101), N(1110), NN(1111).
Acceptance Criteria:
- pkg: add CC_C/CC_V/CC_NV/CC_N/CC_NN.
- core branch evaluator: add the five single-flag tests.
- decode: add the five codes to JRcc short / JRcc long / JAcc recognition
  (previously trapped as illegal).
- tb_jrcc_arith: each code take + skip via CMP-set flags.
Tests: tb_jrcc_arith PASS; full integration regression PASS under Verilator
  (3 module-level tbs need Questa); lint clean.
Docs: instruction_coverage.md (JRcc rows → 16/16 cc), changelog.md, tasks.md.
Commit:
- 35db85f

---

### Task 0102: Interrupt + RETI round-trip integration test
Status: complete
Dependencies: Task 0100 (interrupt entry), RETI (existing).
Spec source: 1988 UG §8 (interrupt processing) + RETI (page 12-230).
Acceptance Criteria:
- New tb_int_reti: main sets SP/INTENB.DI/INTPEND.DI/EINT; ISR clears INTPEND,
  sets A5, RETI; verify ISR ran once, resume target after RETI ran, SP back to
  SP_INIT, ST.IE re-enabled, INTPEND cleared, no re-entry.
- Test-only; no RTL change.
Tests: tb_int_reti PASS (Verilator); lint unaffected (no RTL change).
Docs: changelog.md, tasks.md.
Commit:
- d11564a

---

### Task 0103: Nonmaskable interrupt (NMI) via HSTCTLH
Status: complete
Dependencies: Task 0100 (interrupt entry FSM), Task 0082 (io_regs integration).
Spec source: 1988 UG §8 (NMI, NMIM; auto-clear), HSTCTLH (page 5507/4322),
  Table 8-2 NMI vector 0xFFFFFEE0 (trap 8).
Acceptance Criteria:
- pkg: INT_VEC_NMI, HSTCTL_NMI_BIT(8), HSTCTL_NMIM_BIT(9).
- io_regs: HSTCTLH tap + nmi_clear input (clears NMI bit synchronously); wire
  in tb_io_regs.
- core: nmi_req (ignores IE) priority over int_req at CORE_FETCH; latch
  is_nmi/push flags; NMIM=1 → straight to CORE_INT_VECTOR (no push); SP/IE
  writeback gated by push; assert nmi_clear in CORE_INT_DONE.
- tb_nmi (NMIM=0, IE=0, RETI resume) + tb_nmi_nopush (NMIM=1, no push).
Tests: tb_nmi, tb_nmi_nopush PASS; full integration regression PASS under
  Verilator (3 module-level tbs need Questa); lint clean.
Docs: architecture.md, changelog.md, tasks.md.
Commit:
- 772115d

---

### Task 0104: NMI + maskable interrupt priority integration test
Status: complete
Dependencies: Task 0100 (maskable entry), Task 0103 (NMI).
Spec source: 1988 UG §8 (NMI non-maskable + priority; maskable gated by IE).
Acceptance Criteria:
- New tb_int_priority: arm NMI(NMIM=0)+INTPEND.DI+IE; verify NMI taken first,
  DI after NMI's RETI, resume after both, SP balanced, both sources cleared.
- Ordering guaranteed by construction (NMI clears IE → DI can't preempt).
- Test-only; no RTL change.
Tests: tb_int_priority PASS (Verilator); lint unaffected (no RTL change).
Docs: changelog.md, tasks.md.
Commit:
- 41a5e36

---

### Task 0105: FILL XY window clipping (CONTROL.W=3)
Status: complete
Dependencies: Task 0088 (FILL XY engine).
Spec source: 1988 UG §7.10.3 (W=3 Window Clipping); WSTART(B5)/WEND(B6).
Acceptance Criteria:
- pkg: CORE_FILL_SETUP_WIN state.
- core: for FILL XY with CONTROL.W=3, read WSTART/WEND (new setup cycle via
  spare regfile ports B5/B6); per-pixel absolute XY = (DADDR.X+col, DADDR.Y+row)
  tested against inclusive [WSTART..WEND]; out-of-window pixels skipped (write
  dest unchanged, reusing the transparency path). Non-windowed FILL timing
  unchanged (extra cycle only when windowed).
- A0031: only W=3 for FILL XY; W=1/W=2/WV-interrupt/PIXBLT-LINE-DRAV-PIXT
  deferred and DOCUMENTED (not silent-stubbed).
- tb_fill_window: 2x2 FILL XY, window excludes one column.
Tests: tb_fill_window PASS; full integration regression PASS under Verilator
  (3 module-level tbs need Questa); lint clean.
Docs: assumptions.md (A0031), instruction_coverage.md (FILL XY row),
  changelog.md, tasks.md.
Commit:
- cef1f81

---

### Task 0106: PIXBLT XY window clipping (CONTROL.W=3)
Status: complete
Dependencies: Task 0095 (PIXBLT XY engine), Task 0105 (FILL window template).
Spec source: 1988 UG §7.10.3 (W=3 Window Clipping); WSTART(B5)/WEND(B6).
Acceptance Criteria:
- pkg: CORE_PBLT_SETUP_WIN state.
- core: for any XY-destination PIXBLT with CONTROL.W=3, preserve the raw XY
  DADDR (pblt_dst_xy_raw_q), read WSTART/WEND (new setup cycle, after SETUP/
  SETUP2), per-pixel absolute XY tested against [WSTART..WEND], out-of-window
  dest pixels skipped (reuse transparency path). Non-windowed timing unchanged.
- A0031 extended to PIXBLT XY; W=1/W=2/WV/LINE/DRAV/PIXT still deferred.
- tb_pixblt_window: PIXBLT XY,XY with a 1-pixel window.
Tests: tb_pixblt_window PASS; full integration regression PASS under Verilator
  (3 module-level tbs need Questa); lint clean.
Docs: assumptions.md (A0031), instruction_coverage.md (PIXBLT XY row),
  changelog.md, tasks.md.
Commit:
- b3d8d5c

---

### Task 0107: FILL XY window miss detection (CONTROL.W=2)
Status: complete
Dependencies: Task 0105 (FILL window setup), Task 0100 (interrupt subsystem).
Spec source: 1988 UG §7.10.2 (W=2 Window Miss Detection); WV=INTPEND bit 11.
Acceptance Criteria:
- pkg: CORE_FILL_WIN_MISS state.
- io_regs: wvp_set input sets INTPEND.WV (wire in tb_io_regs).
- core: for FILL XY W=2, compute array containment at CORE_FILL_SETUP_WIN
  (corners vs WSTART/WEND from live reads). Inside → draw, V=0. Miss →
  CORE_FILL_WIN_MISS (no draw), V=1, wvp_set. V written via the
  fill_win_flag_wb override on the status-register flag-update port.
- A0031 extended; W=1, PIXBLT W=2, LINE/DRAV/PIXT still deferred.
- tb_fill_w2: inside (drawn, V=0) + miss (not drawn, V=1, INTPEND.WV), V via
  GETST.
Tests: tb_fill_w2 PASS; full integration regression PASS under Verilator
  (3 module-level tbs need Questa); lint clean.
Docs: assumptions.md (A0031), instruction_coverage.md (FILL XY row),
  changelog.md, tasks.md.
Commit:
- cf59503

---

### Task 0108: PIXBLT XY window miss detection (CONTROL.W=2)
Status: complete
Dependencies: Task 0106 (PIXBLT window setup), Task 0107 (FILL W=2 mechanism).
Spec source: 1988 UG §7.10.2 (W=2 Window Miss Detection).
Acceptance Criteria:
- pkg: CORE_PBLT_WIN_MISS state.
- core: pblt_w2_q; array containment at CORE_PBLT_SETUP_WIN (corners of
  pblt_dst_xy_raw_q + DX/DY vs live WSTART/WEND). Inside → blt + V=0 at
  PBLT_WB2; miss → CORE_PBLT_WIN_MISS (no draw) + V=1 + wvp_set. Reuses the
  shared fill_win_flag_wb / wvp_set V-write mechanism (now OR'd with PBLT).
- A0031 extended; W=1, LINE/DRAV/PIXT still deferred.
- tb_pixblt_w2: inside (drawn, V=0) + miss (not drawn, V=1, INTPEND.WV).
Tests: tb_pixblt_w2 PASS; full integration regression PASS under Verilator
  (3 module-level tbs need Questa); lint clean.
Docs: assumptions.md (A0031), instruction_coverage.md (PIXBLT XY row),
  changelog.md, tasks.md.
Commit:
- b425065

---

### Task 0109: FILL XY window hit detection (CONTROL.W=1)
Status: complete
Dependencies: Task 0107 (FILL W=2 mechanism).
Spec source: 1988 UG §7.10.1 (W=1 Window Hit Detection).
Acceptance Criteria:
- pkg: CORE_FILL_WIN_HIT state.
- core: fill_w1_q; overlap test (fill_array_hit, from latched WSTART/WEND).
  W=1 never draws → CORE_FILL_WIN_HIT. Overlap → V=0 + wvp_set; outside →
  V=1, no wvp. Reuses the shared V-write path; W=2/W=3 untouched.
- A0031: FILL XY now W=0/1/2/3 complete; PIXBLT W=1 + LINE/DRAV/PIXT deferred.
- tb_fill_w1: outside (V=1, no WVP) + overlap (V=0, INTPEND.WV), neither drawn.
Tests: tb_fill_w1 PASS; full integration regression PASS under Verilator
  (3 module-level tbs need Questa); lint clean.
Docs: assumptions.md (A0031), instruction_coverage.md (FILL XY row),
  changelog.md, tasks.md.
Commit:
- 1af38dd

---

### Task 0110: PIXBLT XY window hit detection (CONTROL.W=1)
Status: complete
Dependencies: Task 0108 (PIXBLT W=2), Task 0109 (FILL W=1 mechanism).
Spec source: 1988 UG §7.10.1 (W=1 Window Hit Detection).
Acceptance Criteria:
- pkg: CORE_PBLT_WIN_HIT state.
- core: pblt_w1_q; overlap test (pblt_array_hit from latched WSTART/WEND).
  W=1 never draws → CORE_PBLT_WIN_HIT. Overlap → V=0 + wvp_set; outside →
  V=1, no wvp. Reuses the shared V-write path (OR'd with PBLT_WIN_HIT).
- A0031: window checking COMPLETE for FILL XY + PIXBLT XY (all W modes);
  only LINE/DRAV/PIXT deferred.
- tb_pixblt_w1: outside (V=1, no WVP) + overlap (V=0, INTPEND.WV), neither drawn.
Tests: tb_pixblt_w1 PASS; full integration regression PASS under Verilator
  (3 module-level tbs need Questa); lint clean.
Docs: assumptions.md (A0031), instruction_coverage.md (PIXBLT XY row),
  changelog.md, tasks.md.
Commit:
- 625f4ea

---

### Task 0111: DRAV (Draw and Advance), W=0
Status: complete
Dependencies: pixel engine (ppop_apply), XY conversion (pix_xy_dst_linear),
  ADDXY datapath.
Spec source: 1988 UG page 12-67 (DRAV Rs,Rd; encoding 0xF600).
Acceptance Criteria:
- pkg: INSTR_DRAV, CORE_DRAV state.
- decode: DRAV_TOP7 (1111011) reg-reg arm (rs/rd same file).
- core: EXECUTE latches Rd/Rs and the XY→linear address (port3=OFFSET);
  CORE_DRAV 2-step RMW (port1=COLOR1, FILL-style merge); CORE_WRITEBACK writes
  Rd ← XY-add(Rd,Rs). No flags (W=0).
- A0031: DRAV window modes (W=1/2/3) deferred (behave as W=0).
- tb_drav: two chained DRAVs draw both pixels of a word, Rd advances each time.
Tests: tb_drav PASS; full integration regression PASS under Verilator
  (3 module-level tbs need Questa); lint clean.
Docs: instruction_coverage.md (new DRAV row), assumptions.md (A0031),
  changelog.md, tasks.md.
Commit:
- a352ca5

---

### Task 0112: DRAV per-pixel window checking (CONTROL.W=1/2/3)
Status: complete
Dependencies: Task 0111 (DRAV W=0), Tasks 0107-0110 (window V-write/wvp).
Spec source: 1988 UG page 12-67 / §7.10 (per-pixel window for DRAV).
Acceptance Criteria:
- pkg: CORE_DRAV_SETUP_WIN state.
- core: drav_w_q (latched at EXECUTE); a windowed DRAV reads WSTART/WEND at
  CORE_DRAV_SETUP_WIN, tests Rd's pixel (drav_in_window), latches drav_inside_q.
  W=1 never draws; W=2/W=3 draw iff inside; no-draw routes straight to
  CORE_WRITEBACK. Advance always. V/WVP at WRITEBACK via the shared
  fill_win_flag_wb/wvp_set path (DRAV terms, is_drav-keyed).
- tb_drav_win: W=3 in/out, W=2 out, W=1 in — draw/skip + V + INTPEND.WV.
Tests: tb_drav_win PASS; full integration regression PASS under Verilator
  (3 module-level tbs need Questa); lint clean.
Docs: instruction_coverage.md (DRAV row), assumptions.md (A0031),
  changelog.md, tasks.md.
Commit:
- ba61d32

---

### Task 0113: Widen core_state_t to 6 bits (enable LINE)
Status: complete
Dependencies: none (enabling refactor for Task 0114 LINE).
Acceptance Criteria:
- core_state_t: logic [4:0] → logic [5:0]; all enum values 5'dN → 6'dN. No new
  states, no behavior change.
- Full regression unchanged (no functional impact).
Tests: full integration regression PASS under Verilator (3 module-level tbs
  need Questa); lint clean.
Docs: changelog.md, tasks.md.
Commit:
- 0be4f38

---

### Task 0114: LINE (Bresenham inner loop), W=0
Status: complete
Dependencies: Task 0113 (6-bit state enum), DRAV/FILL pixel engine, ADDXY.
Spec source: 1988 UG page 12-99 (LINE Z; encoding 0xDF1A/0xDF9A).
Acceptance Criteria:
- pkg: INSTR_LINE, 7 LINE states, B_COUNT/INC1/INC2 idx consts.
- decode: 0xDF1A/0xDF9A (Z=bit7) → INSTR_LINE; operands implied (B file).
- core: 3 setup cycles read d/DYDX/COUNT/INC1/INC2/OFFSET/DADDR/COLOR1;
  CORE_LINE_DRAW per-pixel RMW + Bresenham step (d += 2b−2a/2b, DADDR +=
  INC1/INC2 XY, COUNT−−; Z selects d>0 vs d≥0); writeback d/DADDR/COUNT to
  B0/B2/B10. Window deferred (A0031).
- tb_line: vertical line (INC2) + 45° diagonal (INC1) + writeback checks.
Tests: tb_line PASS; full integration regression PASS under Verilator
  (3 module-level tbs need Questa); lint clean.
Docs: instruction_coverage.md (new LINE row), assumptions.md (A0031),
  changelog.md, tasks.md.
Commit:
- 3df5ff5

---

### Task 0115: LINE window clipping (CONTROL.W=3)
Status: complete
Dependencies: Task 0114 (LINE engine), window V-write mechanism.
Spec source: 1988 UG §7.10.3 (LINE W=3 — inhibit outside pixels, V from last).
Acceptance Criteria:
- pkg: CORE_LINE_SETUP_WIN state.
- core: read WSTART/WEND at CORE_LINE_SETUP_WIN (only when W=3); per-pixel
  inside test on DADDR; out-of-window pixels write dest unchanged (clip); track
  last-pixel inside; V = NOT last-inside at CORE_LINE_WB_D via shared
  fill_win_flag_wb. No interrupt (W=3).
- A0031: LINE W=1/W=2 (abort) + PIXT window still deferred.
- tb_line_win: vertical line half in window — inside drawn, outside clipped,
  V=1 (last pixel outside).
Tests: tb_line_win PASS; full integration regression PASS under Verilator
  (3 module-level tbs need Questa); lint clean.
Docs: instruction_coverage.md (LINE row), assumptions.md (A0031),
  changelog.md, tasks.md.
Commit:
- 70cd3c8

---

### Task 0116: LINE window abort modes (CONTROL.W=1/W=2)
Status: complete
Dependencies: Task 0115 (LINE W=3 window infra), interrupt subsystem.
Spec source: 1988 UG §7.10.1/2 (LINE hit/miss detection with abort).
Acceptance Criteria:
- core: generalize line_win_en to W!=0; per-pixel line_draw_pixel (W=1 draws
  outside, W=2/3 inside) and line_abort (W=1 inside / W=2 outside); latch
  line_aborted_q; LINE_DRAW terminal includes line_abort; wvp_set on
  (line_win_wb && aborted); V = NOT last-inside (all windowed). W=3 unchanged.
- tb_line_abort: W=2 (abort on outside, V=1) + W=1 (abort on inside, V=0),
  drawn/skipped pixels + INTPEND.WV.
- A0031: LINE window complete; only PIXT window + multi-word MOVB remain.
Tests: tb_line_abort + tb_line_win PASS; full integration regression PASS under
  Verilator (3 module-level tbs need Questa); lint clean.
Docs: instruction_coverage.md (LINE row), assumptions.md (A0031),
  changelog.md, tasks.md.
Commit:
- 31dc4b2

---

### Task 0117: PIXT XY per-pixel window checking
Status: complete
Dependencies: Task 0112 (DRAV window pattern), Task 0085 (PIXT XY).
Spec source: 1988 UG §7.10 (per-pixel window for PIXT/DRAV).
Acceptance Criteria:
- pkg: CORE_PIXT_SETUP_WIN state.
- core: pixt_xy_win = pixt_rmw && xy_addr && W!=0; route EXECUTE→SETUP_WIN→
  CORE_MEMORY for windowed XY PIXT; read WSTART/WEND; test mv_ptr's XY;
  inhibit pixt_merged outside (W=1 always); latch pixt_inside_q at the RMW
  write step; V/WVP at CORE_WRITEBACK via shared fill_win_flag_wb/wvp_set.
  Regular MOVE / non-XY PIXT / W=0 unaffected.
- tb_pixt_win: W=3 in/out + W=2 out (WVP).
- Window checking now complete for ALL drawing instructions.
Tests: tb_pixt_win PASS; full integration regression PASS under Verilator
  (3 module-level tbs need Questa); lint clean.
Docs: instruction_coverage.md (PIXT XY row), assumptions.md (A0031),
  changelog.md, tasks.md.
Commit:
- 5089ca2

---

### Task 0118: Migrate agent guidance and restore local validation entry points
Status: complete
Dependencies: none (documentation and developer-tooling handoff).
Acceptance Criteria:
- Replace the root `CLAUDE.md` with repository-wide `AGENTS.md` guidance that
  preserves the specification, HDL-style, testing, and documentation contracts
  while removing Claude-specific behavior and automatic commit/push assumptions.
- Reconcile the current milestone and task index with the implementation,
  which is complete through Task 0117.
- Make the documented scripts executable and let `scripts/lint.sh` and
  `scripts/sim.sh` fall back to Verilator when Questa/ModelSim is unavailable.
- Refresh the current-state summaries in the README and core project docs
  without rewriting historical task/changelog records.
- Record a concise, evidence-based implementation map and next-step backlog for
  the next coding session.
Tests:
- `scripts/lint.sh` runs through the available Verilator installation; known
  width warnings are reported, not hidden.
- `scripts/sim.sh tb_smoke` prints `TEST_RESULT: PASS`.
- At least the latest graphics/window test (`tb_pixt_win`) passes through the
  same script.
- Shell syntax checks pass for all scripts.
Docs:
- `AGENTS.md`, `README.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/assumptions.md`,
  `docs/instruction_coverage.md`, `docs/memory_map.md`,
  `docs/timing_notes.md`, plus stale current-state header comments in the
  package/core/decode/status/I/O RTL files.
Commit:
- 509f670

---

### Task 0119: Establish strict full-regression gate
Status: complete
Dependencies:
- Task 0118 (portable local validation entry points).
Acceptance Criteria:
- Add one repository command that discovers every `sim/tb/tb_*.sv` bench,
  requires each bench's authoritative `TEST_RESULT: PASS` marker, writes
  per-test logs, reports an aggregate count, and supports bounded parallel
  Verilator execution without racing Questa's shared work library.
- Successful regression workers remove their generated simulator build
  directories; failed workers retain logs and builds for diagnosis.
- Make RTL lint a zero-diagnostic gate and resolve the two known core width
  diagnostics with explicit, behavior-preserving sizing.
- Remove simulator scheduling races from the three module-level benches
  (`tb_pc`, `tb_regfile`, and `tb_status_reg`) and preserve the architectural
  `ST_RESET_VALUE` through masked flag-update expectations.
- No architectural behavior, instruction encoding, or external cycle count
  changes.
Tests:
- Shell syntax checks pass for every script.
- `scripts/lint.sh` completes with zero RTL diagnostics under Verilator 5.048.
- `tb_pc`, `tb_regfile`, and `tb_status_reg` print `TEST_RESULT: PASS` under
  Verilator.
- `REGRESS_JOBS=4 scripts/regress.sh` reports `109/109 PASS` under Verilator.
Docs:
- `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`.
Commit:
- be793d7

---

### Task 0120: Complete multiword MOVB memory-to-memory forms
Status: complete
Dependencies:
- Task 0080 (seven existing MOVB forms and forced 8-bit field machinery).
- Task 0119 (strict 109-test regression gate).
Spec source:
- 1988 TI TMS34010 User's Guide pages 12-120/12-121: MOVB
  `*Rs(SOffset),*Rd(DOffset)`.
- 1988 TI TMS34010 User's Guide pages 12-123/12-124: MOVB
  `@SAddress,@DAddress`.
Acceptance Criteria:
- Decode the three-word offset-to-offset form (`0xBC00` family), fetch source
  offset followed by destination offset, sign-extend each independently, and
  copy exactly eight bits from `Rs+SOffset` to `Rd+DOffset`.
- Decode the fixed five-word absolute-to-absolute form (`0x0340`), fetch source
  low/high followed by destination low/high, and copy exactly eight bits
  between the two bit addresses.
- Reuse the existing two-step memory-to-memory byte-copy path, with no
  register writeback and N/C/Z/V all unaffected.
- Preserve instruction-word PC advancement and support unaligned,
  16-bit-word-straddling source and destination bytes.
Tests:
- Add `tb_movb_multiword` covering signed offsets, operand-word order,
  unaligned/straddling copies, register preservation, flags unaffected,
  post-instruction execution, and no illegal-opcode latch.
- Run strict RTL lint, the existing `tb_movb`, the new focused test, and the
  complete regression.
- `scripts/lint.sh` completed with zero diagnostics under Verilator 5.048;
  `tb_movb` and `tb_movb_multiword` both passed.
- `REGRESS_JOBS=4 scripts/regress.sh` reported `110/110 PASS`.
Docs:
- `README.md`, `tasks.md`, `changelog.md`, `docs/assumptions.md`,
  `docs/architecture.md`, `docs/instruction_coverage.md`, `AGENTS.md`.
Commit:
- 704840e

---

### Task 0121: Fetch the architectural level-0 reset vector
Status: complete
Dependencies:
- Task 0004 (bit-addressed PC and the original reset-sequence deferral).
- Task 0049 (TRAP 0 vector constant and no-push behavior).
- Task 0119 (strict full-regression gate).
Spec source:
- 1988 TI TMS34010 User's Guide pages 8-10 and 8-12: after reset, fetch the
  level-0 vector from bit address `0xFFFF_FFE0`; reset saves neither PC nor ST.
Acceptance Criteria:
- While synchronous `rst` is asserted, keep the external memory request
  inactive and hold the FSM in `CORE_RESET`.
- After release, hold one 32-bit read request at `TRAP_VECTOR_BASE` until
  `mem_ack`, load PC from the returned vector only on that acknowledge, and
  begin the first instruction fetch at the loaded bit address.
- Do not advance PC, write memory, push PC/ST, or modify SP during the reset
  vector transaction.
- Give the bounded simulation memory a dedicated public level-0 vector word,
  defaulting to zero so focused programs can continue to start at word zero
  while still exercising the architectural bus transaction. Use the same
  word for later TRAP 0 accesses instead of low-address aliasing.
- Leave the specified eight post-reset RAS-only initialization cycles and
  HCS/HLT host-present mode to the memory-controller and host-interface tasks;
  document that boundary explicitly.
Tests:
- Add `tb_reset_vector` with a nonzero vector, request/address/size/write
  checks, PC hold/load checks, no reset-time writes, and execution at the
  vector target.
- Update `tb_smoke`, `tb_fetch_walk`, and `tb_trap0` for the architectural
  reset transaction and dedicated level-0 vector storage.
- Run strict RTL lint, all focused reset/fetch/TRAP 0 tests, and the complete
  regression.
- `scripts/lint.sh` completed with zero diagnostics under Verilator 5.048;
  `tb_reset_vector`, `tb_smoke`, `tb_fetch_walk`, `tb_trap0`, and
  `tb_mem_field` passed.
- `REGRESS_JOBS=4 scripts/regress.sh` reported `111/111 PASS`.
Docs:
- `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/assumptions.md`, `docs/memory_map.md`,
  `docs/timing_notes.md`, `docs/instruction_coverage.md`.
Commit:
- f087ece

---

### Task 0122: Trap illegal opcodes through architectural vector 30
Status: complete
Dependencies:
- Task 0010 (decoder illegal classification and sticky observability).
- Task 0053 (TRAP 30 architectural behavior).
- Task 0100 (shared interrupt-entry state sequence).
- Task 0119 (strict full-regression gate).
Spec source:
- 1988 TI TMS34010 User's Guide §8.1 and §8.7, pages 8-2 and 8-9:
  reserved opcodes generate an unmaskable interrupt equivalent to TRAP 30;
  vector 30 is the 32-bit word at bit address `0xFFFF_FC20`.
- User's Guide Table 8-6, page 8-9: `0x0200` is in an explicitly reserved
  illegal-opcode range.
Acceptance Criteria:
- Classify the complete User's Guide Table 8-6 reserved ranges separately
  from other not-yet-implemented valid encodings, and redirect that
  architectural-illegal subset from `CORE_DECODE` into interrupt entry.
- Push the already advanced PC at `SP-32`, push the pre-entry ST at `SP-64`,
  fetch the handler PC from `0xFFFF_FC20`, decrement SP by 64 bits, and install
  `ST_RESET_VALUE`, matching the existing TRAP 30 behavior.
- Ignore ST.IE and the interrupt-enable mask for illegal-opcode recognition.
- Preserve the sticky `illegal_opcode_o` diagnostic until reset.
- Leave the existing maskable/NMI entry policy unchanged; resolving A0030's
  post-entry ST assumption is a separate task.
Tests:
- Replace the Phase-3 visibility-only `tb_illegal_opcode` scenario with a
  complete reserved-opcode/vector-30 integration test covering every reserved
  range boundary, adjacent non-reserved values, bus direction, address, size,
  pushed data, SP/ST/PC results, skipped fall-through code, handler execution,
  and sticky diagnostics.
- Retain the broader regression's existing unsupported-encoding fall-through
  behavior until those valid ISA encodings are implemented.
- Run strict RTL lint, focused illegal/TRAP/interrupt-entry tests, and the
  complete regression.
- `scripts/lint.sh` completed with zero diagnostics under Verilator 5.048;
  `tb_illegal_opcode`, `tb_add_rr`, `tb_trap`, `tb_int_entry`, `tb_int_reti`,
  `tb_nmi`, and `tb_nmi_nopush` passed.
- `REGRESS_JOBS=4 scripts/regress.sh` reported `111/111 PASS`.
Docs:
- `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/instruction_coverage.md`,
  `docs/memory_map.md`, `docs/timing_notes.md`.
Commit:
- 1ede2ba

---

### Task 0123: Initialize architectural ST on every interrupt entry
Status: complete
Dependencies:
- Task 0100 (shared maskable-interrupt entry FSM and A0030).
- Task 0103 (NMI context-save/no-save modes).
- Task 0122 (shared illegal-opcode entry and `ST_RESET_VALUE` behavior).
Spec source:
- 1988 TI TMS34010 User's Guide §8.5, page 8-6, step 3 and the accompanying
  status-register diagram: interrupt entry clears every live ST bit except
  `FS0=16`, producing `0x0000_0010`; the text confirms IE=0, FE0/FE1=0,
  FS0=16, and FS1=32.
- User's Guide §8.4, page 8-5: HSTCTLH.NMIM controls whether NMI context is
  saved on the stack; it does not exempt NMI from the §8.5 live-ST update.
Acceptance Criteria:
- Replace the provisional A0030 “clear IE only” behavior with
  `ST_RESET_VALUE` for maskable interrupts and context-saving NMI.
- Apply the same live-ST initialization to NMIM=1 NMI while continuing to
  suppress both stack writes and the SP decrement in that mode.
- Preserve the pre-entry ST in the stacked word whenever context saving is
  enabled, so RETI still restores the interrupted context exactly.
- Remove state that existed only to distinguish illegal-opcode ST replacement
  from the provisional hardware-interrupt behavior.
Tests:
- Strengthen `tb_int_entry` with a nondefault pre-interrupt ST and verify that
  the exact old word is stacked while live ST becomes `ST_RESET_VALUE`.
- Strengthen `tb_nmi_nopush` with a nondefault pre-NMI ST and verify
  `ST_RESET_VALUE` despite no stack or SP update.
- Run strict RTL lint, focused maskable/NMI/illegal/TRAP/RETI tests, and the
  complete regression.
- `scripts/lint.sh` completed with zero diagnostics under Verilator 5.048;
  `tb_int_entry`, `tb_nmi_nopush`, `tb_int_reti`, `tb_nmi`,
  `tb_int_priority`, `tb_illegal_opcode`, `tb_trap`, and `tb_trap0` passed.
- `REGRESS_JOBS=4 scripts/regress.sh` reported `111/111 PASS`.
Docs:
- `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/assumptions.md`, `docs/timing_notes.md`.
Commit:
- e4768a1

---

### Task 0124: Audit the remaining ISA and system completion gaps
Status: complete
Dependencies:
- Task 0118 (repository handoff/reconciliation).
- Task 0123 (clean architectural interrupt baseline).
Spec sources:
- 1988 TI TMS34010 User's Guide §12.3, pages 12-12 through 12-18
  (complete TMS34010 instruction summary).
- Individual instruction pages 12-43/12-45 (ANDI/ANDNI), 12-51 (CLR),
  12-61 (DEC), 12-77 (EMU), 12-149 (MOVE offset-to-postincrement), and
  12-155 (MOVE absolute-to-postincrement).
- SPVS002C datasheet and User's Guide bus/host/video chapters for the
  physical integration boundaries already named in the architecture docs.
Acceptance Criteria:
- Reconcile every row of the official instruction-summary tables against
  `docs/instruction_coverage.md` and the decoder.
- Record every missing instruction/form, every implemented alias that lacks
  direct verification, and every discovered noncompliant implementation
  without presenting it as complete.
- Reconcile current architecture/module-map gaps, active assumptions, and
  Quartus-flow limitations into one ordered completion ledger with objective
  exit gates.
- Keep historical task/changelog statements intact; update only current
  status summaries.
Tests:
- `scripts/lint.sh` — PASS; Verilator lint clean with zero diagnostics.
- `REGRESS_JOBS=4 scripts/regress.sh` — PASS, 111/111 self-checking
  testbenches.
Docs:
- Add `docs/completion_audit.md`; update `README.md`, `AGENTS.md`, `tasks.md`,
  `changelog.md`, `docs/architecture.md`, `docs/assumptions.md`,
  `docs/instruction_coverage.md`.
Commit:
- `ee74bef` — Audit remaining completion gaps (Task 0124)

---

### Task 0125: Correct logical flags and ANDI/ANDNI semantics
Status: complete
Dependencies:
- Task 0124 (official ISA reconciliation).
Spec sources:
- 1988 TI TMS34010 User's Guide pages 12-42 through 12-45
  (AND/ANDI/ANDN/ANDNI).
- 1988 TI TMS34010 User's Guide pages 12-51 and 12-61 (CLR and DEC
  aliases).
- 1988 TI TMS34010 User's Guide pages 12-171 through 12-173 and 12-255
  through 12-256 (NOT, OR/ORI, and XOR/XORI).
Acceptance Criteria:
- Make AND, ANDN, OR, XOR, NOT, ANDI/ANDNI, ORI, and XORI update only Z
  while preserving N, C, and V.
- Implement the shared ANDI/ANDNI hardware opcode as `Rd & ~extension`;
  verify ANDI's complemented extension and ANDNI's direct extension.
- Directly verify the exact CLR=`XOR Rd,Rd` and DEC=`SUBK 1,Rd` aliases.
- Update the official coverage ledger and retire the corresponding Task
  0124 audit findings.
Tests:
- `scripts/sim.sh tb_logical_flags`, `tb_logical_rr`, `tb_immi_il`,
  `tb_neg_not`, and `tb_addk_subk` — PASS.
- `scripts/lint.sh` — PASS; Verilator lint clean with zero diagnostics.
- `REGRESS_JOBS=4 scripts/regress.sh` — PASS, 112/112 self-checking
  testbenches.
Docs:
- Update `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/assumptions.md`,
  `docs/completion_audit.md`, and `docs/instruction_coverage.md`.
Commit:
- `97794d9` — Correct logical instruction semantics (Task 0125)

---

### Task 0126: Implement MOVE offset-to-postincrement
Status: complete
Dependencies:
- Task 0079 (field-aware memory-to-memory sequencing).
- Task 0124 (official ISA reconciliation).
Spec sources:
- 1988 TI TMS34010 User's Guide page 12-149, “Move Field — Indirect
  with Offset to Indirect (Postincrement).”
Acceptance Criteria:
- Decode `MOVE *Rs(offset),*Rd+ [,F]` at `1101 00FS SSSR DDDD` plus a
  signed 16-bit bit offset.
- Read an FS-bit field at `Rs + sign_extend(offset)`, write it through
  the original Rd, leave Rs unchanged, and postincrement Rd by FS.
- Support both F-selected field definitions, FS=32, signed offsets, and
  unaligned/straddling fields without changing N/C/Z/V.
- Directly verify the encoding, memory results, pointer results, and
  status preservation.
Tests:
- `scripts/sim.sh tb_move_off_m2m_postinc` — PASS.
- `scripts/lint.sh` — PASS; Verilator lint clean with zero diagnostics.
- `REGRESS_JOBS=4 scripts/regress.sh` — PASS, 113/113 self-checking
  testbenches.
Docs:
- Update `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/completion_audit.md`,
  `docs/instruction_coverage.md`, and `docs/timing_notes.md`.
Commit:
- `97c163c` — Implement MOVE offset postincrement (Task 0126)

---

### Task 0127: Implement MOVE absolute-to-postincrement
Status: complete
Dependencies:
- Task 0079 (field-aware memory-to-memory sequencing).
- Task 0126 (destination-only M2M postincrement pattern).
Spec sources:
- 1988 TI TMS34010 User's Guide page 12-155, “Move Field — Absolute to
  Indirect (Postincrement).”
Acceptance Criteria:
- Decode `MOVE @SAddress,*Rd+ [,F]` at `1101 01F0 000R DDDD` plus the
  32-bit source bit address, low word first.
- Read an FS-bit field at the absolute source, write it through the
  original Rd, and postincrement Rd by FS.
- Support both F-selected field definitions, FS=32, and
  unaligned/straddling fields without changing N/C/Z/V.
- Directly verify opcode/address word order, memory results, pointer
  results, and status preservation.
Tests:
- `scripts/sim.sh tb_move_abs_m2m_postinc` — PASS.
- `scripts/lint.sh` — PASS; Verilator lint clean with zero diagnostics.
- `REGRESS_JOBS=4 scripts/regress.sh` — PASS, 114/114 self-checking
  testbenches.
Docs:
- Update `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/completion_audit.md`,
  `docs/instruction_coverage.md`, and `docs/timing_notes.md`.
Commit:
- `b3ac2e4` — Implement MOVE absolute postincrement (Task 0127)

---

### Task 0128: Implement EMU pin handshake and halt state
Status: complete
Dependencies:
- Task 0124 (official ISA reconciliation).
- Task 0127 (all other §12.3 rows implemented).
Spec sources:
- 1988 TI TMS34010 User's Guide page 12-77, “Initiate Emulation.”
- 1988 TI TMS34010 User's Guide page 2-10, RUN/EMU and HLDA/EMUA pin
  descriptions.
Acceptance Criteria:
- Decode the fixed EMU opcode `0x0100`.
- Expose active-high-RUN `run_emu_n_i` and active-low acknowledge
  `emua_n_o` at the core boundary.
- Pulse EMUA for one core cycle when EMU executes; sample RUN/EMU there.
- In RUN state, retire EMU as a NOP. In EMU state, halt instruction and
  memory activity with PC already pointing after EMU, hold EMUA active,
  and resume fetch when RUN returns high.
- Keep deterministic FPGA status behavior explicit even though the
  original instruction documents N/C/Z/V as indeterminate.
Tests:
- Focused `tb_emu` covering RUN and EMU samples, pulse width, halt
  quiescence, PC, resume, and no illegal-opcode indication.
- Strict RTL lint and the complete self-checking regression.
- `scripts/sim.sh tb_emu` — PASS.
- `scripts/lint.sh` — PASS, strict Verilator lint clean.
- `REGRESS_JOBS=4 scripts/regress.sh` — PASS, 115/115 self-checking
  testbenches.
Docs:
- Update `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/assumptions.md`,
  `docs/completion_audit.md`, `docs/instruction_coverage.md`, and
  `docs/timing_notes.md`.
Commit:
- `1a47e5c` — Implement EMU handshake and halt state (Task 0128)

---

### Task 0129: Correct 5-bit constant zero encoding
Status: complete
Dependencies:
- Task 0124 (active-assumption audit).
Spec sources:
- 1988 TI TMS34010 User's Guide page 12-40, ADDK.
- 1988 TI TMS34010 User's Guide page 12-161, MOVK.
- 1988 TI TMS34010 User's Guide page 12-251, SUBK.
Acceptance Criteria:
- Treat a zero `K` opcode field as architectural constant 32 for MOVK,
  ADDK, and SUBK.
- Preserve literal encoded values 1 through 31 and keep each instruction's
  existing register-file and status behavior.
- Resolve A0013 and A0018 against their individual primary-spec pages.
Tests:
- Extend `tb_movk` with the specified MOVK 32 / encoded-zero result.
- Extend `tb_addk_subk` with encoded-zero ADDK/SUBK result and flag cases.
- Run both focused benches, strict RTL lint, and the complete self-checking
  regression.
- `scripts/sim.sh tb_movk` — PASS.
- `scripts/sim.sh tb_addk_subk` — PASS.
- `scripts/lint.sh` — PASS, strict Verilator lint clean.
- `REGRESS_JOBS=4 scripts/regress.sh` — PASS, 115/115 self-checking
  testbenches.
Docs:
- Update `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/assumptions.md`,
  `docs/completion_audit.md`, and `docs/instruction_coverage.md`.
Commit:
- `23932ec` — Correct 5-bit constant zero encoding (Task 0129)

---

### Task 0130: Correct shift encodings and status semantics
Status: complete
Dependencies:
- Task 0124 (active-assumption and status audit).
Spec sources:
- 1988 TI TMS34010 User's Guide pages 12-234/12-235, RL constant/register.
- 1988 TI TMS34010 User's Guide pages 12-239 through 12-246,
  SLA/SLL/SRA/SRL constant/register.
Acceptance Criteria:
- Decode the SRA/SRL constant-form opcode field as the two's complement of
  the architectural right-shift count; keep zero as a zero shift.
- Retain direct 0..31 counts for left shifts/rotate and the existing
  two's-complement register-count rule for right shifts.
- Implement SLA overflow when the new sign or any shifted-out bit differs
  from the original sign.
- Apply the individual NCZV masks to both constant and register forms:
  SLA updates NCZV; SRA updates NCZ; SLL/SRL/RL update CZ.
- Resolve A0019 with exact encoding, result, flag-value, and unaffected-flag
  tests based on the individual instruction pages.
Tests:
- Update `tb_shift_k` for architectural right-count encoding and K=0.
- Update `tb_shift_rr` for the documented register right-count convention.
- Add focused shift status/overflow and unaffected-flag coverage.
- Run the focused shift benches, strict RTL lint, and the complete
  self-checking regression.
- `scripts/sim.sh tb_shifter` — PASS.
- `scripts/sim.sh tb_shift_k` — PASS.
- `scripts/sim.sh tb_shift_rr` — PASS.
- `scripts/sim.sh tb_shift_flags` — PASS.
- `scripts/lint.sh` — PASS, strict Verilator lint clean.
- `REGRESS_JOBS=4 scripts/regress.sh` — PASS, 116/116 self-checking
  testbenches.
Docs:
- Update `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/assumptions.md`,
  `docs/completion_audit.md`, `docs/instruction_coverage.md`, and
  `docs/timing_notes.md`.
Commit:
- `39ccb9b` — Correct shift encodings and status semantics (Task 0130)

---

### Task 0131: Correct MOVI status semantics
Status: complete
Dependencies:
- Task 0124 (active-assumption and status audit).
Spec sources:
- 1988 TI TMS34010 User's Guide page 12-159, MOVI 16-bit.
- 1988 TI TMS34010 User's Guide page 12-160, MOVI 32-bit.
Acceptance Criteria:
- Make both MOVI widths update N from the moved sign and Z from a zero
  result, preserve C, and force V to zero.
- Keep the existing IW sign extension, IL low/high word order, destination
  selection, and register writeback behavior unchanged.
- Resolve A0011 with full-ST tests that seed C/V independently of reset.
Tests:
- `tb_movi`, `tb_movi_il`, and new `tb_movi_flags` PASS for IW/IL positive,
  negative, zero, C-preservation, V-clear, and unchanged data semantics.
- `tb_abs_negb` and `tb_addc_subb` PASS after replacing their obsolete
  MOVI-clears-C fixture assumption with explicit CLRC setup.
- Strict RTL lint clean; complete regression PASS (117/117).
Docs:
- Update `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/assumptions.md`,
  `docs/completion_audit.md`, and `docs/instruction_coverage.md`.
Commit:
- 385f54b

---

### Task 0132: Resolve REV and EXGPC architectural semantics
Status: complete
Dependencies:
- Task 0124 (active-assumption and status audit).
Spec sources:
- 1988 TI TMS34010 User's Guide page 12-233, REV.
- 1988 TI TMS34010 User's Guide page 12-79, EXGPC.
Acceptance Criteria:
- Resolve A0025 directly from the primary guide: REV returns the documented
  TMS34010 revision value `0x00000008`; EXGPC exchanges the next PC with Rd
  and clears the four least-significant bits of the register-sourced PC.
- Preserve the existing atomic exchange datapath and prove the alignment
  behavior with a deliberately unaligned source-register target.
- Verify that both instructions leave N/C/Z/V unaffected.
Tests:
- Extended `tb_pc_ops` PASS with direct REV, unaligned EXGPC target,
  dynamically calculated return-PC, and full-status preservation checks.
- `scripts/lint.sh` PASS, strict RTL lint clean.
- `REGRESS_JOBS=4 scripts/regress.sh` PASS, 117/117 self-checking benches.
Docs:
- Update `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/assumptions.md`,
  `docs/completion_audit.md`, and `docs/instruction_coverage.md`.
Commit:
- ce5caba

---

### Task 0133: Resolve FILL XY DADDR writeback semantics
Status: complete
Dependencies:
- Task 0124 (active-assumption and status audit).
- Task 0088 (FILL XY engine).
Spec sources:
- 1988 TI TMS34010 User's Guide pages 12-84 through 12-86, FILL XY.
Acceptance Criteria:
- Resolve A0029 from the primary FILL XY page: convert the initial XY DADDR
  with OFFSET/CONVDP and write back the linear address immediately following
  the last pixel on the final row.
- Preserve the existing row-pitch and last-row-width behavior.
- Verify that W=0 leaves N/C/Z/V unaffected.
Tests:
- Strengthened `tb_fill_xy` PASS with exact converted start/final linear
  DADDR and full-status preservation checks.
- `scripts/lint.sh` PASS, strict RTL lint clean.
- `REGRESS_JOBS=4 scripts/regress.sh` PASS, 117/117 self-checking benches.
Docs:
- Update `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/assumptions.md`,
  `docs/completion_audit.md`, and `docs/instruction_coverage.md`.
Commit:
- bd14d03

---

### Task 0134: Correct SUBXY signed comparison semantics
Status: complete
Dependencies:
- Task 0124 (active-assumption and status audit).
- Task 0066 (ADDXY/SUBXY implementation).
Spec sources:
- 1988 TI TMS34010 User's Guide §4.3 page 4-11, signed XY components.
- 1988 TI TMS34010 User's Guide page 12-252, SUBXY status rules.
Acceptance Criteria:
- Resolve A0027 from the primary guide: evaluate SUBXY's source-X and
  source-Y greater-than conditions as signed 16-bit XY comparisons.
- Keep the two independent 16-bit subtraction results plus N/Z equality
  behavior unchanged.
- Add a direct vector whose signed and unsigned comparisons disagree for
  both C and V.
Tests:
- Extended `tb_addxy_subxy` PASS with signed-negative comparison coverage;
  `tb_cmpxy` also PASS with its distinct result-sign rules.
- `scripts/lint.sh` PASS, strict RTL lint clean.
- `REGRESS_JOBS=4 scripts/regress.sh` PASS, 117/117 self-checking benches.
Docs:
- Update `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/assumptions.md`,
  `docs/completion_audit.md`, and `docs/instruction_coverage.md`.
Commit:
- fc5001d

---

### Task 0135: Complete the instruction status audit
Status: complete
Dependencies:
- Task 0124 (active-assumption and status audit).
- Tasks 0125 and 0129–0134 (previous individual-family corrections).
Spec sources:
- 1988 TI TMS34010 User's Guide chapter 12, every implemented
  instruction family's individual `Status Bits` table.
- 1988 TI TMS34010 User's Guide §7.10, window-checking modes.
Acceptance Criteria:
- Reconcile every implemented instruction family's N/C/Z/V writers,
  unaffected bits, undefined bits, runtime qualifications, and full-ST
  transitions against the primary pages; resolve A0009.
- Exhaustively enforce the static decoder policy for all 65,536 opcode words.
- Correct MODS/DIVS overflow status and MODS valid-remainder writeback.
- Derive odd-destination MPYS/MPYU N/Z from the stored low 32-bit result.
- Report W=3 preclipping in V for FILL XY and XY-destination PIXBLT while
  preserving N/C/Z.
- Apply PIXT window draw/skip, V, and WV behavior to XY-to-XY as well as
  register-to-XY writes.
- Distinguish architecturally Unaffected flags from Undefined/Indeterminate
  flags retained only as a deterministic FPGA choice.
Tests:
- New `tb_status_decode`, `tb_div_flags`, and `tb_mpy_flags` PASS.
- Strengthened `tb_fill_window`, `tb_pixblt_window`, and `tb_pixt_win` PASS.
- Existing `tb_divs_mods`, `tb_mpy`, `tb_mpy_fs1`, and related graphics
  regressions remain PASS.
- `scripts/lint.sh` PASS, strict Verilator lint clean.
- `REGRESS_JOBS=4 scripts/regress.sh` PASS, 120/120 self-checking benches.
Docs:
- Add `docs/status_audit.md`.
- Update `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/assumptions.md`,
  `docs/completion_audit.md`, and `docs/instruction_coverage.md`.
Commit:
- 6916227

---

### Task 0136: Sequence architectural fields onto 16-bit memory words
Status: complete
Dependencies:
- Task 0076 (abstract arbitrary-field simulation semantics).
- Task 0135 (complete ISA/status exit gate).
Spec sources:
- 1988 TI TMS34010 User's Guide §3.1, pages 3-2 through 3-3
  (bit-addressed logical memory and 16-bit physical words).
- 1988 TI TMS34010 User's Guide §4.1, pages 4-2 through 4-5
  (the seven minimum-cycle field-alignment cases).
- 1988 TI TMS34010 User's Guide §11.3, page 11-4
  (word-level read/modify/write indivisibility and arbitration boundaries).
Acceptance Criteria:
- Add a synthesizable field sequencer that translates one bit-addressed
  1–32-bit request into the specified minimum sequence of aligned 16-bit
  word reads and writes.
- Preserve bits outside partial-word writes, directly write every fully
  covered word, return reads right-justified, and handle one-, two-, and
  three-word fields in ascending address order.
- Hold every physical-word request and payload stable through arbitrary
  wait states and expose the indivisible partial-word RMW interval.
- Route the shared simulation memory model through the sequencer so all
  core-level tests exercise physical word splitting instead of an atomic
  behavioral 48-bit splice.
- Resolve A0005 with primary-spec evidence and retain pin-level RAS/CAS
  timing as the next memory-controller task rather than conflating it with
  field alignment.
Tests:
- `tb_field_sequencer` PASS for all seven write cases, 1/2/3-word reads,
  exact transaction order/count/data, stalls, payload stability, and reset.
- `tb_mem_field`, `tb_smoke`, and `tb_move_field` focused integration
  regressions PASS.
- `scripts/lint.sh` PASS, strict RTL lint clean.
- `REGRESS_JOBS=4 scripts/regress.sh` PASS, 121/121 self-checking benches.
Docs:
- Update `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/assumptions.md`,
  `docs/completion_audit.md`, `docs/memory_map.md`, and
  `docs/timing_notes.md`.
Commit:
- 789eef2

---

### Task 0137: Complete interrupt-pending source semantics
Status: complete
Dependencies:
- Task 0081 (I/O register file).
- Task 0100 (maskable-interrupt entry).
- Task 0136 (current completion baseline).
Spec sources:
- 1988 TI TMS34010 User's Guide pages 6-36 through 6-42
  (HSTCTLL.INTIN, INTENB, and INTPEND register semantics).
- 1988 TI TMS34010 User's Guide §§8.1 through 8.4, pages 8-2 through 8-5
  (source priority, active-low external interrupts, and vectors).
- SPVS002C TMS34010 data sheet local-interrupt timing requirements.
Acceptance Criteria:
- Synchronize the active-low LINT1/LINT2 pins through dedicated, recognized
  two-flop synchronizers and expose their level-sensitive state as read-only
  INTPEND.X1P/X2P bits.
- Make INTPEND.HIP a read-only reflection of HSTCTLL.INTIN; provide
  synchronous host/display source sidebands for later host/video integration.
- Implement DIP and WVP as hardware-set latches for which a processor write
  of zero clears and a write of one has no effect; a coincident set wins.
- Restrict INTENB to its five implemented enable bits and retain the
  specification-derived priority/vector behavior.
- Exercise each maskable source through the I/O register boundary and verify
  external interrupt entry at the core boundary.
Tests:
- `tb_io_interrupts` PASS (reserved-bit masks, synchronized external levels,
  read-only X1P/X2P/HIP, independent DIP/WVP clears, and set-over-clear).
- `tb_external_interrupts` PASS (LINT2 vector and LINT1-over-LINT2 priority).
- Existing `tb_int_ctrl`, `tb_int_entry`, `tb_int_reti`,
  `tb_int_priority`, and `tb_io_regs` focused regressions PASS.
- `scripts/lint.sh` PASS, strict RTL lint clean.
- `REGRESS_JOBS=4 scripts/regress.sh` PASS, 123/123 self-checking benches.
Docs:
- Update `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/assumptions.md`,
  `docs/completion_audit.md`, `docs/memory_map.md`, and
  `docs/timing_notes.md`.
Commit:
- 7c483a6

---

### Task 0138: Correct and integrate DRAM refresh semantics
Status: complete
Dependencies:
- Task 0081 (I/O register file).
- Task 0099 (standalone refresh generator).
- Task 0137 (current completion baseline).
Spec sources:
- 1988 TI TMS34010 User's Guide pages 6-10/6-11
  (CONTROL.RM/RR modes and reset behavior).
- 1988 TI TMS34010 User's Guide pages 6-45/6-46
  (REFCNT field layout, decrement/borrow behavior, row address, and access).
Acceptance Criteria:
- Model REFCNT bits 2-15 as one continuous writable 14-bit counter:
  RR=00 decrements RINTVL by two each local clock, RR=01 decrements it by
  one, and an underflow decrements ROWADR and requests a refresh.
- Preserve software-written reserved bits 1:0, reset the whole register to
  zero, and make an explicit processor load take precedence over automatic
  counting as required for deterministic FPGA behavior.
- Integrate the refresh generator into `tms34010_io_regs`, so processor
  reads/writes observe the live REFCNT register and CONTROL.RR/RM drive the
  refresh behavior.
- Expose the refresh request, decremented row address, and RAS-only versus
  CAS-before-RAS mode at the core boundary for the future memory arbiter.
- Directly test first-underflow behavior, 32/64-clock periods, descending
  rows, wrap, disable modes, software load, reserved-bit retention, and I/O
  integration.
Tests:
- `tb_refresh` PASS (first borrow, 32/64-clock periods, descending rows,
  disable modes, write priority, reserved bits, and wrap).
- `tb_io_refresh` PASS (live REFCNT reads/writes plus exported
  request/row/mode).
- Existing `tb_io_regs`, `tb_io_interrupts`, and `tb_smoke` focused
  regressions PASS.
- `scripts/lint.sh` PASS, strict RTL lint clean.
- `REGRESS_JOBS=4 scripts/regress.sh` PASS, 124/124 self-checking benches.
Docs:
- Update `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/assumptions.md`,
  `docs/completion_audit.md`, `docs/memory_map.md`, and
  `docs/timing_notes.md`.
Commit:
- 485f2d2

---

### Task 0139: Integrate internal noninterlaced video timing
Status: complete
Dependencies:
- Task 0097 (standalone video timing generator).
- Task 0137 (display-interrupt pending latch).
- Task 0138 (current completion baseline).
Spec sources:
- 1988 TI TMS34010 User's Guide pages 6-18 through 6-25
  (DPYCTL.ENV, horizontal timing registers, and HCOUNT).
- 1988 TI TMS34010 User's Guide pages 6-31 and 6-47
  (DPYINT and VCOUNT).
- 1988 TI TMS34010 User's Guide §9.7
  (display interrupt at the start of horizontal blanking).
Acceptance Criteria:
- Drive the timing generator from the processor-visible HESYNC/HEBLNK/
  HSBLNK/HTOTAL, VESYNC/VEBLNK/VSBLNK/VTOTAL, DPYCTL, and DPYINT registers.
- Make HCOUNT and VCOUNT live writable counters rather than stale ordinary
  register storage, with deterministic same-clock write precedence.
- Correct DIP generation to the start of horizontal blanking
  (`HCOUNT == HSBLNK`) on the selected VCOUNT line, latch it through the
  existing hardware-set/write-zero-clear INTPEND path, and inhibit new DIP
  events while DPYCTL.ENV is zero.
- Force the active-high internal BLANK indication while ENV is zero and
  export horizontal/vertical sync and blank intervals at the core boundary.
- Keep this increment explicitly internal/noninterlaced and same-clock under
  A0004/A0034; do not introduce an unsafe implicit multi-bit VCLK crossing.
Tests:
- `tb_video` PASS (writable counters, wraps, sync/blank windows, ENV gating,
  and HSBLNK-positioned display-interrupt pulse).
- `tb_io_video` PASS (live I/O counter reads/writes, timing outputs, ENV,
  integrated DIP latch, and processor clear).
- Existing `tb_io_regs`, `tb_io_interrupts`, `tb_io_refresh`, and `tb_smoke`
  focused regressions PASS.
- `scripts/lint.sh` PASS, strict RTL lint clean.
- `REGRESS_JOBS=4 scripts/regress.sh` PASS, 125/125 self-checking benches.
Docs:
- Update `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/assumptions.md`,
  `docs/completion_audit.md`, `docs/memory_map.md`, and
  `docs/timing_notes.md`.
Commit:
- 1ab082d

---

### Task 0140: Correct sync and blank interval endpoints
Status: complete
Dependencies:
- Task 0139 (integrated internal/noninterlaced timing).
Spec sources:
- 1988 TI TMS34010 User's Guide pages 6-26 through 6-28
  (HCOUNT, HEBLNK, HESYNC, and HSBLNK equality behavior).
- 1988 TI TMS34010 User's Guide pages 6-48 through 6-51
  (VEBLNK, VESYNC, VSBLNK, and VTOTAL equality behavior).
- 1988 TI TMS34010 User's Guide §§9.5/9.6, especially pages 9-6 through 9-8
  (one-VCLK output delay after each equality compare).
Acceptance Criteria:
- Keep HSYNC active through HCOUNT=HESYNC and VSYNC active through
  VCOUNT=VESYNC, so their programmed values represent duration minus one.
- Keep leading horizontal/vertical blank active through HEBLNK/VEBLNK and
  begin trailing blank only after HSBLNK/VSBLNK.
- Preserve the display-interrupt request at the HSBLNK equality event even
  though the externally visible blank interval changes one clock later.
- Directly regression-lock all inclusive/exclusive count-space boundaries.
Tests:
- `tb_video` PASS (every counter value checked against the exact sync/blank
  intervals over multiple frames).
- `tb_io_video` PASS (HSBLNK equality versus following-count blank transition,
  integrated DIP, and visible-coordinate outputs).
- `scripts/lint.sh` PASS, strict RTL lint clean.
- `REGRESS_JOBS=4 scripts/regress.sh` PASS, 125/125 self-checking benches.
Docs:
- Update `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/assumptions.md`,
  `docs/completion_audit.md`, and `docs/timing_notes.md`.
Commit:
- 675863c

---

### Task 0141: Integrate DPYADR and screen-refresh scheduling
Status: complete
Dependencies:
- Task 0139 (live internal/noninterlaced counters and timing events).
- Task 0140 (exact sync/blank endpoint phases).
Spec sources:
- 1988 TI TMS34010 User's Guide pages 6-17 through 6-24
  (DPYADR, DPYCTL.DUDATE/ORG/SRE, DPYSTRT, and DPYTAP).
- 1988 TI TMS34010 User's Guide §9.10.1, especially pages 9-18 through 9-25
  (screen-refresh address generation, line cadence, scheduling, completion
  updates, and held requests through bus unavailability).
Acceptance Criteria:
- Make DPYADR a live, full-word processor-writable register owned by a
  dedicated display-address block.
- Reload SRFADR from DPYSTRT at the start of vertical blanking and LNCNT at
  the final horizontal blank preceding active display.
- Schedule the first enabled screen refresh before active display and then
  every LCSTRT+1 eligible lines, with no ordinary requests during vertical
  blanking.
- Hold each request plus captured SRFADR/DPYTAP stable until an explicit
  completion acknowledge from the future memory/VRAM controller; keep
  DPYTAP's reserved bits 15:14 zero.
- Advance/decrement SRFADR by DUDATE according to ORG and reload LNCNT only
  after acknowledged completion; preserve deterministic processor-write
  priority over a same-edge automatic update.
- Export request/ack/SRFADR/DPYTAP at the core boundary without claiming the
  physical VRAM row/column cycle or interlaced/VCLK behavior.
Tests:
- `tb_display_addr` PASS (frame/line field loads, vertical suppression,
  LCSTRT cadence, stall stability, acknowledge updates, ORG, SRE re-enable,
  processor collision priority, and reset recovery).
- `tb_io_display` PASS (live DPYADR I/O reads/writes, generated timing events,
  DPYTAP reserved bits, held payload, acknowledge updates, and core-facing
  client signals).
- Existing `tb_video`, `tb_io_video`, `tb_io_regs`, and `tb_smoke` focused
  regressions PASS.
- `scripts/lint.sh` PASS, strict RTL lint clean.
- `REGRESS_JOBS=4 scripts/regress.sh` PASS, 127/127 self-checking benches.
Docs:
- Update `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/assumptions.md`,
  `docs/completion_audit.md`, `docs/memory_map.md`, and
  `docs/timing_notes.md`.
Commit:
- 2ed909c

---

### Task 0142: Integrate direct host control and halt semantics
Status: complete
Dependencies:
- Task 0137 (HSTCTLL.INTIN/HIP and NMI register behavior).
- Task 0141 (current completion baseline).
Spec sources:
- 1988 TI TMS34010 User's Guide pages 6-31 through 6-37
  (HSTCTLH/HSTCTLL field ownership, HINT, NMI, and HLT).
- 1988 TI TMS34010 User's Guide §8.8, pages 8-10 through 8-13
  (HCS-selected host-present reset and deferred level-0 vector fetch).
- 1988 TI TMS34010 User's Guide §10.3.3.5 and §10.3.4, pages 10-18 through
  10-20 (simultaneous NMI/HLT ordering and instruction-boundary halt latency).
Acceptance Criteria:
- Replace the provisional one-bit host interrupt input with one synchronous
  direct-host HSTCTL transaction boundary and a combined 16-bit read view.
- Implement complementary host/processor ownership of MSGIN, INTIN, MSGOUT,
  and INTOUT, active-low HINT, byte enables, and defined HSTCTLH reserved bits.
- Sample active-low HCS into HLT on reset; in host-present mode, issue no
  level-0 vector request until the host clears HLT.
- Halt only after the current instruction completes, issue no processor
  memory request or interrupt entry while halted, and resume at the saved
  boundary while refresh/video state continues clocking.
- Service a simultaneous new NMI before HLT so entry completes and the core
  halts before the first service-routine instruction; retain NMI pending when
  asserted after the core is already halted.
- Isolate deterministic collision choices for same-clock direct-host and
  processor writes without claiming original asynchronous pin timing or
  host-indirect memory access.
Tests:
- `tb_host_control` PASS (HCS reset values, combined reads, byte enables,
  per-side ownership, HINT, masks, automatic NMI clear, and collisions).
- `tb_host_halt` PASS (deferred reset vector, instruction completion,
  quiescent halt, continuing refresh/video state, pending NMI, and
  simultaneous NMI+HLT ordering).
- Existing `tb_io_interrupts`, `tb_reset_vector`, `tb_nmi`, `tb_emu`,
  `tb_io_regs`, and `tb_external_interrupts` focused regressions PASS.
- `scripts/lint.sh` PASS, strict RTL lint clean.
- `REGRESS_JOBS=4 scripts/regress.sh` PASS, 129/129 self-checking benches.
Docs:
- Update `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/assumptions.md`,
  `docs/completion_audit.md`, `docs/memory_map.md`, and
  `docs/timing_notes.md`.
Commit:
- 81a889f

---

### Task 0143: Implement the synchronous host-indirect engine
Status: complete
Dependencies:
- Task 0142 (defined HSTCTL high-byte fields and direct host-control boundary).
- Task 0136 (defined the aligned 16-bit local-word transaction contract).
Spec sources:
- 1988 TI TMS34010 User's Guide §10.2, pages 10-2 through 10-3
  (four host registers and HFS selection).
- 1988 TI TMS34010 User's Guide §10.3.2 through §10.3.3.4, pages 10-8
  through 10-18 (host backpressure, indirect prefetch/read/write operation,
  increment ordering, processor access, and unsupported collisions).
- 1988 TI TMS34010 User's Guide §10.3.5, pages 10-20 through 10-21
  (LBL-selected last-byte side-effect triggers).
Acceptance Criteria:
- Add a synthesizable synchronous host-register request/ack module that owns
  word-aligned HSTADRL/HSTADRH and buffered HSTDATA state while forwarding
  HSTCTL accesses to the existing I/O-register owner.
- Trigger one no-increment prefetch when the host completes an address load
  in either LBL byte order.
- Return the buffered word on a host HSTDATA read, then launch a new held
  local read; apply INCR before selecting its address.
- Merge selected HSTDATA bytes on a host write, launch the held local write
  only on the LBL-selected last byte, and apply INCW after acknowledgement.
- Hold local direction/address/write-data stable through arbitrary stalls,
  serialize later host requests behind an outstanding side effect, and wrap
  pointer increments at 32 bits.
- Preserve the rule that processor HSTADR/HSTDATA accesses have no indirect
  side effect, and isolate a deterministic policy for simultaneous accesses
  that the guide requires software to avoid.
- Leave I/O/core instantiation, local-memory arbitration, and asynchronous
  physical host strobes/HRDY/CDC to following tasks.
Tests:
- `tb_host_if` PASS (reset, processor access, HSTCTL pass-through, LBL=0/1,
  address prefetch, HSTDATA buffering, INCR/INCW ordering, partial bytes,
  request stalls/stability, backpressure, wraparound, and collision policy).
- `scripts/lint.sh` PASS, strict RTL lint clean.
- `REGRESS_JOBS=4 scripts/regress.sh` PASS, 130/130 self-checking benches.
Docs:
- Update `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/assumptions.md`,
  `docs/completion_audit.md`, `docs/memory_map.md`, and
  `docs/timing_notes.md`.
Commit:
- 7639249

---

### Task 0144: Integrate the four-register host port
Status: complete
Dependencies:
- Task 0143 (synchronous host-register and indirect-memory engine).
- Task 0142 (direct HSTCTL ownership and halt semantics).
Spec sources:
- 1988 TI TMS34010 User's Guide §10.2, pages 10-2 through 10-3
  (four host registers and HFS selection).
- 1988 TI TMS34010 User's Guide §10.3.2 through §10.3.3.4, pages 10-8
  through 10-18 (host backpressure, indirect operation, processor access,
  and unsupported simultaneous accesses).
- 1988 TI TMS34010 User's Guide §10.3.5, pages 10-20 through 10-21
  (LBL-selected last-byte completion).
Acceptance Criteria:
- Instantiate `tms34010_host_if` in the I/O register block and replace the
  temporary HSTCTL-only core port with one synchronous request/ack boundary
  selecting HSTADRL, HSTADRH, HSTDATA, or HSTCTL.
- Make processor HSTADR/HSTDATA reads and writes use the same engine-owned
  state observed by the host without initiating an indirect local cycle.
- Preserve Task 0142 HSTCTL ownership, HINT, HCS/HLT, NMI, byte-enable, and
  collision behavior through the generalized host port.
- Export the engine's held aligned 16-bit local-memory request, direction,
  address, write data, read data, and acknowledge at the core boundary.
- Migrate every core/I/O integration bench to the new explicit boundary
  without claiming host/local arbitration, HRDY, asynchronous pin timing,
  or CDC.
Tests:
- `tb_host_integration` PASS (shared processor/host register state, HSTCTL
  ownership/HINT, address prefetch, INCR/INCW, and exposed local-word cycles).
- `tb_host_if`, `tb_host_control`, `tb_host_halt`, `tb_io_access`, and
  `tb_io_interrupts` focused regressions PASS.
- `scripts/lint.sh` PASS, strict RTL lint clean.
- `REGRESS_JOBS=4 scripts/regress.sh` PASS, 131/131 self-checking benches.
Docs:
- Update `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/assumptions.md`,
  `docs/completion_audit.md`, `docs/memory_map.md`, and
  `docs/timing_notes.md`.
Commit:
- 77feb2f

---

### Task 0145: Implement specification-priority local-bus arbitration
Status: complete
Dependencies:
- Task 0136 (aligned 16-bit field sequencer and per-word RMW lock).
- Task 0138 (one-clock DRAM-refresh request plus row/mode).
- Task 0141 (held screen-refresh request and payload).
- Task 0144 (held host-indirect aligned-word client).
Spec sources:
- 1988 TI TMS34010 User's Guide §11.3, page 11-4
  (HOLD/screen/DRAM/host/CPU priority, active-cycle completion,
  partial-word RMW indivisibility, inter-word preemption, and HOLD restart).
Acceptance Criteria:
- Add a synthesizable registered-owner arbiter with the exact fixed priority:
  external HOLD, screen refresh, DRAM refresh, host indirect, CPU/graphics.
- Hold an issued controller-facing cycle and all payload stable through
  acknowledge even if a higher-priority request arrives.
- Capture a one-clock DRAM-refresh request with its row/mode until physical
  completion and preserve a same-edge replacement event.
- Reserve the CPU between the selected partial-word read and its matching
  write, while permitting higher-priority service between different words of
  a multiword field.
- Accept HOLD only after an active cycle completes; if it intervenes between
  the partial read and write, suppress the not-yet-issued write and restart
  the complete RMW pair after release.
- Keep the output as an abstract local-cycle contract; leave LAD/RAS/CAS/LRDY
  phase generation and full core/client integration to following tasks.
Tests:
- `tb_bus_arbiter` PASS (reset, full fixed-priority chain, HOLD retention,
  response routing, active-cycle/payload stability, pulsed DRAM capture, and
  same-edge refresh-event replacement).
- `tb_bus_arbiter_rmw` PASS (real field-sequencer RMW reservation, legal
  inter-word host preemption, active-read completion, and HOLD pair restart).
- `tb_field_sequencer` PASS (all alignment cases and existing stall/reset
  behavior with the new restart input inactive).
- `scripts/lint.sh` PASS, strict RTL lint clean.
- `REGRESS_JOBS=4 scripts/regress.sh` PASS, 133/133 self-checking benches.
Docs:
- Update `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/assumptions.md`,
  `docs/completion_audit.md`, `docs/memory_map.md`, and
  `docs/timing_notes.md`.
Commit:
- 5c7aedd

---

### Task 0146: Integrate the core memory clients and arbiter
Status: complete
Dependencies:
- Task 0136 (architectural-field to aligned-word sequencer).
- Task 0144 (integrated held host-indirect client).
- Task 0145 (fixed-priority arbiter and RMW/HOLD contract).
Spec sources:
- 1988 TI TMS34010 User's Guide §4.1, pages 4-2 through 4-5
  (architectural fields and aligned 16-bit physical words).
- 1988 TI TMS34010 User's Guide §11.3, page 11-4
  (shared CPU/display/refresh/host ownership and HOLD behavior).
- 1988 TI TMS34010 User's Guide §9.10.1, pages 9-18 through 9-25
  (screen-refresh request retention and completed-cycle update).
- 1988 TI TMS34010 User's Guide §10.3.3, pages 10-11 through 10-18
  (host-indirect local-memory access and backpressure).
Acceptance Criteria:
- Add a reusable synthesizable memory-fabric module that composes the landed
  field sequencer and arbiter without adding another scheduling policy.
- Add a synthesizable functional-system wrapper that connects the core's
  architectural CPU/graphics, host-indirect, screen-refresh, and DRAM-refresh
  clients plus external HOLD through that fabric.
- Expose one held abstract controller cycle carrying the selected word,
  screen, or DRAM-refresh payload and route completion/read data to the
  originating client.
- Preserve the synchronous host, interrupt, emulation, functional-video, and
  core observability boundaries without claiming physical host, VCLK, or
  local-bus pin timing.
- Boot and execute real instructions through the integrated field/arbiter
  path; directly observe all four memory clients and HOLD at the shared
  controller boundary.
Tests:
- `tb_system_fabric` PASS (two-word reset vector, real instruction execution,
  CPU field traffic, programmed screen refresh/payload, automatic DRAM
  refresh, host-indirect prefetch/read, controller stalls/payload stability,
  active-cycle completion, HOLD quiescence, and release recovery).
- Existing `tb_bus_arbiter`, `tb_bus_arbiter_rmw`, `tb_field_sequencer`, and
  `tb_host_integration` focused regressions PASS.
- `scripts/lint.sh` PASS, strict RTL lint clean.
- `REGRESS_JOBS=4 scripts/regress.sh` PASS, 134/134 self-checking benches.
Docs:
- Update `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/assumptions.md`,
  `docs/completion_audit.md`, `docs/memory_map.md`, and
  `docs/timing_notes.md`.
Commit:
- 87d30e3

---

### Task 0147: Implement the original-pin local-bus phase engine
Status: complete
Dependencies:
- Task 0145 (controller-facing local-cycle kinds and held payload contract).
- Task 0146 (integrated abstract system/fabric boundary).
Spec sources:
- 1988 TI TMS34010 User's Guide §11.4, Figures 11-3 through 11-14,
  pages 11-7 through 11-18 (word, register-transfer, refresh, I/O, and LRDY
  phase behavior).
- 1988 TI TMS34010 User's Guide §11.4.12, Figure 11-17, page 11-22
  (eight post-reset RAS-only initialization cycles).
- 1988 TI TMS34010 User's Guide §11.5, Figures 11-18/11-19, pages 11-23
  through 11-27 (word/status and DRAM-refresh row formats).
- 1988 TI TMS34010 User's Guide §9.10.1.2, Figures 9-13/9-14, pages 9-20
  through 9-23 (screen-refresh SRFADR/DPYTAP/ORG address generation).
Acceptance Criteria:
- Add a synthesizable standalone local-bus controller whose dedicated 8×
  timing clock represents both halves of Q1..Q4, generates LCLK1/LCLK2, and
  never uses either output waveform as a fabric clock.
- Generate exact LAD row/column/data and active-low RAS/CAS/LAL/W/TR/QE/DEN
  plus DDOUT behavior for ordinary word read/write, screen
  memory-to-register, RAS-only, CAS-before-RAS, and I/O read/write cycles.
- Encode RF/TR/IAQ and logical address bits exactly for word accesses; encode
  duplicated REFCNT rows, screen SRFADR/DPYTAP/ORG addresses, and inactive
  I/O address/status values exactly.
- Sample LRDY at the end of Q1, repeat one whole local-clock access period for
  every low sample, retain the specified screen-transfer TR/QE release point,
  and ignore LRDY for I/O cycles.
- Sample ordinary read data in the middle of Q4 and return on a completing
  end-Q4 acknowledge; source I/O read data from the on-chip-data input.
- Automatically perform exactly eight extendable zero-row RAS-only cycles
  after synchronous reset release before accepting a client command.
- Keep the command interface synchronous to the 8× domain and explicitly
  defer core-clock CDC/system connection, physical HOLD release, and upstream
  IAQ/screen-ORG/I/O metadata propagation.
Tests:
- `tb_local_bus` PASS (both LCLK waveforms, all seven cycle kinds,
  half-quarter strobe order, exact word/screen/refresh/I/O address/status
  values, write data, middle-Q4 read capture, ordinary/screen/reset waits,
  I/O LRDY bypass, and exactly eight reset initialization cycles).
- `scripts/lint.sh` PASS, strict RTL lint clean.
- `REGRESS_JOBS=4 scripts/regress.sh` PASS, 135/135 self-checking benches.
Docs:
- Update `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/assumptions.md`,
  `docs/completion_audit.md`, `docs/memory_map.md`, and
  `docs/timing_notes.md`.
Commit:
- 8eff258

---

### Task 0148: Integrate the core and original-pin local bus coherently
Status: complete
Dependencies:
- Task 0146 (integrated core-clock memory-fabric boundary).
- Task 0147 (standalone 8× original-pin phase engine).
Spec sources:
- 1988 TI TMS34010 User's Guide §11.5, pages 11-23 through 11-24
  (IAQ status and instruction-acquisition scope).
- 1988 TI TMS34010 User's Guide §9.10.1.2, Figures 9-13/9-14,
  pages 9-20 through 9-23 (screen-refresh ORG address selection).
- `docs/hdl-coding-guidelines/23-cdc-single-bit.md` and
  `24-cdc-multi-bit.md` (Cyclone V synchronizer and MCP contracts).
Acceptance Criteria:
- Add a synthesizable lossless command/response crossing between the
  core-clock fabric and 8× local-bus controller without independently
  synchronizing any changing multi-bit bus.
- Register and hold the complete source command until a two-phase request/
  acknowledge exchange finishes; capture the stable payload in the
  destination domain and keep its request stable through controller waits.
- Hold returned read data in the 8× domain until the acknowledge toggle
  reaches the source, then emit exactly one core-clock completion pulse.
- Prevent the arbiter's held request from being accepted twice around the
  completion edge.
- Generate IAQ only for opcode fetch words with the current cacheless core,
  capture screen ORG with each refresh request, and propagate both metadata
  values through the fabric and bridge.
- Add an integrated synthesizable wrapper joining the functional system,
  CDC bridge, and original-pin engine while leaving physical HOLD and
  asynchronous host pins isolated for following tasks.
- Verify reset ordering so the core's pending vector request cannot reach
  physical memory until all eight automatic reset RAS cycles complete.
Tests:
- `tb_local_bus_bridge` PASS (non-integer clock ratio, every command payload
  field, variable destination stalls, returned data, one-shot completion,
  held-source duplicate suppression, and five consecutive toggle phases).
- `tb_pin_system` PASS (eight reset RAS-only cycles, physical two-word reset
  vector, pin-returned opcode execution, and IAQ low/high distinction).
- Updated `tb_display_addr`, `tb_bus_arbiter`, `tb_bus_arbiter_rmw`, and
  `tb_system_fabric` PASS with captured ORG, IAQ, and payload-stability checks.
- `scripts/lint.sh` PASS, strict RTL lint clean.
- `REGRESS_JOBS=4 scripts/regress.sh` PASS, 137/137 self-checking benches.
Docs:
- Update `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/assumptions.md`,
  `docs/completion_audit.md`, `docs/memory_map.md`, and
  `docs/timing_notes.md`.
Commit:
- 1341f07

---

### Task 0149: Route processor I/O through physical I/O cycles
Status: complete
Dependencies:
- Task 0148 (integrated core-to-8× command/response path).
Spec sources:
- 1988 TI TMS34010 User's Guide §6, Figure 6-1
  (C0000000h-C00001FFh on-chip I/O decode).
- 1988 TI TMS34010 User's Guide §11.4.8, Figures 11-10/11-11,
  pages 11-13 through 11-15 (processor/host-indirect I/O cycle selection,
  two-clock duration, LRDY bypass, address/status, controls, and data phase).
Acceptance Criteria:
- Export the core's processor I/O decode, original read/write intent, and
  internal read word without allowing an I/O write to reach ordinary RAM.
- Register each architectural CPU request before classification, hold its
  payload through completion, and avoid a combinational acknowledge/address
  decode loop.
- Route non-I/O fields through the existing field sequencer unchanged; route
  processor I/O directly to the arbiter as `LOCAL_CYCLE_IO_READ` or
  `LOCAL_CYCLE_IO_WRITE`.
- Force IAQ inactive for I/O, carry the on-chip read word coherently to the
  8× controller, and return completion through the existing bridge.
- Qualify processor I/O writes/live-register loads with the single returned
  completion pulse so physical waits cannot repeat their side effects.
- Keep host-indirect I/O routing separate because it requires a second
  access/ownership path into the shared I/O register owner.
Tests:
- Updated `tb_bus_arbiter` PASS with dedicated processor I/O read/write kinds,
  internal read data, IAQ suppression, response routing, and held-payload
  checks.
- Updated `tb_system_fabric` PASS with real program-generated I/O write cycles
  and stable internal read-data payload.
- Updated `tb_pin_system` PASS with a real PMASK write/read program, exactly
  one physical cycle per access, zero I/O address/status, RAS/LAL-only
  controls, write data on LAD, read-phase LAD release, completion-qualified
  register update, and returned read value.
- Updated `tb_local_bus_bridge` PASS with exact full-command comparison,
  including the new I/O read-data field.
- Existing focused I/O/core/host tests PASS.
- `scripts/lint.sh` PASS, strict RTL lint clean.
- `REGRESS_JOBS=4 scripts/regress.sh` PASS, 137/137 self-checking benches.
Docs:
- Update `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/assumptions.md`,
  `docs/completion_audit.md`, `docs/memory_map.md`, and
  `docs/timing_notes.md`.
Commit:
- `9d6a5bf` — Route processor I/O through physical cycles (Task 0149)

---

### Task 0150: Route host-indirect I/O through physical cycles
Status: complete
Dependencies:
- Task 0149 (processor physical I/O cycle path and coherent read-data
  command).
Spec sources:
- 1988 TI TMS34010 User's Guide §6.1, page 6-2 (host-indirect access to the
  complete on-chip I/O register page).
- 1988 TI TMS34010 User's Guide §10.3.3.4, page 10-18
  (host-indirect access to every internal I/O register and simultaneous
  HSTADR/HSTDATA collision rule).
- 1988 TI TMS34010 User's Guide §11.4.8, Figures 11-10/11-11,
  pages 11-13 through 11-15 (host-indirect I/O cycle selection,
  two-clock duration, LRDY bypass, address/status, controls, and data phase).
Acceptance Criteria:
- Decode the held host-indirect address against
  `C0000000h-C00001FFh` without changing ordinary aligned-word requests.
- Provide an independent internal-register read view so a waiting processor
  access and a host-indirect access do not share a combinational selector.
- Select `LOCAL_CYCLE_IO_READ` or `LOCAL_CYCLE_IO_WRITE` for the host owner,
  sample live read data when the host wins arbitration, and hold the complete
  command through controller/CDC stalls.
- Return I/O read data through the existing phase engine and host prefetch
  buffer; commit I/O writes exactly once on the returned physical completion.
- Preserve host-side HSTCTLL field ownership and shared HSTADR/HSTDATA state
  for indirect accesses into the host-register portion of the I/O page.
- Retain the existing host priority, LBL, INCR/INCW, and backpressure
  contracts.
Tests:
- Updated `tb_bus_arbiter` PASS with host I/O read/write kinds, sampled live
  read data, payload stability, response routing, and inactive IAQ.
- Updated `tb_host_integration` PASS with full-address I/O classification,
  PSIZE read/write completion, pre-ack state preservation, and indirect
  HSTCTLL host ownership.
- Updated `tb_system_fabric` PASS with host-indirect DPYTAP prefetch/read/write
  cycles, internal read payloads, and completion-qualified state.
- Updated `tb_pin_system` PASS with two processor and three host PMASK I/O
  cycles, exact zero address/status, RAS/LAL-only controls, LAD write data/
  read release, returned BEEF, and final acknowledged 1234 state.
- Existing focused host-interface, I/O-register, RMW, bridge, and local-bus
  tests PASS.
- `scripts/lint.sh` PASS, strict RTL lint clean.
- `REGRESS_JOBS=4 scripts/regress.sh` PASS, 137/137 self-checking benches.
Docs:
- Update `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/assumptions.md`,
  `docs/completion_audit.md`, `docs/memory_map.md`, and
  `docs/timing_notes.md`.
Commit:
- `fc1e47e` — Route host-indirect I/O through physical cycles (Task 0150)

---

### Task 0151: Implement physical HOLD/HOLDA bus release
Status: complete
Dependencies:
- Task 0145 (fixed-priority HOLD arbitration and partial-RMW restart).
- Task 0148 (integrated core-to-8× command/response path).
Spec sources:
- 1988 TI TMS34010 User's Guide §2.5, Table 2-5, pages 2-10 through
  2-11 (active-low HOLD and shared HLDA/EMUA pin roles).
- 1988 TI TMS34010 User's Guide §11.3, page 11-4 (HOLD priority and
  active-cycle completion).
- 1988 TI TMS34010 User's Guide §11.4.11, Figures 11-15/11-16,
  pages 11-18 through 11-21 (end-Q1 sampling, early HOLDA, Q2/Q3 release,
  high impedance, and resume).
Acceptance Criteria:
- Replace the integrated pin system's abstract HOLD request/acknowledge
  boundary with active-low physical HOLD sampling at the end of Q1.
- Cross the sampled request into the core and the arbiter's quiescent grant
  back into the 8× domain through dedicated synchronized level paths.
- Finish an active physical cycle before acknowledging HOLD and preserve the
  existing highest-priority arbitration and partial-RMW restart contract.
- Drive the active-low HOLDA component only during Q3/Q4, beginning one
  quarter-clock before the bus is released.
- Release LAD and the majority of bus controls at the following Q2, then
  release DEN/DDOUT at Q3; retain all output enables inactive while granted.
- Reacquire the majority controls at Q2 and DEN/DDOUT at Q3 after an
  end-Q1 release sample, without accepting a queued command while held.
- Keep the Q1/Q2 EMUA half and final shared HLDA/EMUA pin mux explicit as
  separate physical-wrapper work.
Tests:
- Added `tb_local_bus_hold` PASS for request sampling, early HOLDA, exact
  Q2/Q3 release and reacquisition, held command suppression, and
  active-cycle completion before grant.
- Updated `tb_pin_system` PASS for physical HOLD during real core traffic,
  synchronized quiescence, exact output-enable phases, and execution resume.
- Existing `tb_local_bus`, `tb_local_bus_bridge`, `tb_bus_arbiter_rmw`, and
  `tb_system_fabric` PASS.
- `scripts/lint.sh` PASS, strict RTL lint clean.
- `REGRESS_JOBS=4 scripts/regress.sh` PASS, 138/138 self-checking benches.
Docs:
- Update `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/assumptions.md`,
  `docs/completion_audit.md`, `docs/memory_map.md`, and
  `docs/timing_notes.md`.
Commit:
- `9f2794e` — Implement physical HOLD/HOLDA bus release (Task 0151)

---

### Task 0152: Implement the shared physical HLDA/EMUA pin
Status: complete
Dependencies:
- Task 0128 (architectural RUN/EMU handshake and halt).
- Task 0151 (Q3/Q4 HLDA component and physical HOLD release).
Spec sources:
- 1988 TI TMS34010 User's Guide §2.5, Table 2-5, page 2-10
  (HLDA in Q3/Q4, EMUA in Q1/Q2, halted indication, and one-LCLK1-cycle
  opcode pulse).
- 1988 TI TMS34010 User's Guide §11.4.11, page 11-20
  (shared-pin mux selects HLDA while LCLK1 is low and EMUA while LCLK1 is
  high).
- 1988 TI TMS34010 User's Guide EMU instruction, page 12-77
  (pulse EMUA, sample RUN/EMU, NOP in RUN, halt in EMU).
Acceptance Criteria:
- Synchronize the physical RUN/EMU input into the core domain with inactive
  RUN as the reset-safe value.
- Convert each core EMU execution into a source-held event and acknowledge
  it only after one complete destination Q1/Q2 pulse has been emitted.
- Cross the core halt state as a separately registered level and sample it
  only at a Q4-to-Q1 boundary so EMUA never changes within Q1/Q2.
- Drive EMUA active-low for exactly one complete Q1/Q2 window in RUN mode
  and for every Q1/Q2 window while halted.
- Drive the shared output from EMUA only while LCLK1 is high and from the
  Task 0151 HLDA component only while LCLK1 is low.
- Preserve both halves under simultaneous HOLD and EMU/halt conditions
  without exposing an abstract duplicate pin at `tms34010_pin_system`.
Tests:
- Added `tb_emu_bridge` PASS with non-integer clocks, two re-armed held
  events, simultaneous event/halt entry, repeating Q1/Q2 halt indication,
  phase-aligned release, and independent Q3/Q4 HLDA selection.
- Updated `tb_pin_system` PASS with a real RUN-mode opcode pulse,
  synchronized physical emulator entry, repeating halt indication,
  simultaneous HOLD, HLDA-only release, and execution resume.
- Existing `tb_emu`, `tb_local_bus_hold`, and `tb_local_bus` PASS.
- `scripts/lint.sh` PASS, strict RTL lint clean.
- `REGRESS_JOBS=4 scripts/regress.sh` PASS, 139/139 self-checking benches.
Docs:
- Update `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/assumptions.md`,
  `docs/completion_audit.md`, `docs/instruction_coverage.md`,
  `docs/memory_map.md`, and `docs/timing_notes.md`.
Commit:
- `ba9d8d6` — Implement the shared physical HLDA/EMUA pin (Task 0152)

---

### Task 0153: Implement the asynchronous physical host bus
Status: complete
Dependencies:
- Task 0144 (synchronous four-register host boundary).
- Task 0150 (host-indirect physical I/O completion).
- Task 0152 (integrated original-pin system boundary).
Spec sources:
- 1988 TI TMS34010 User's Guide §2.2, Table 2-2, pages 2-5 through 2-6
  (HCS/HFS/HREAD/HWRITE/HLDS/HUDS/HRDY/HD pin functions).
- 1988 TI TMS34010 User's Guide §10.3, pages 10-4 through 10-10
  (last-active/first-inactive access strobes, byte enables, HD direction,
  HCS-triggered HRDY, HSTCTL delay, prior-indirect busy wait, and ready hold).
Acceptance Criteria:
- Replace `tms34010_pin_system`'s synchronous host request/payload ports with
  active-low HCS, HREAD, HWRITE, HLDS, HUDS, two HFS inputs, and split HD
  input/output/byte-enable signals.
- Recognize only legal read-exclusive or write-exclusive accesses with at
  least one selected byte; HREAD and HWRITE active together must not launch a
  transaction.
- Establish an immediate HRDY wait before capturing the asynchronous bundled
  HFS/HD/direction/byte payload, then hold one synchronous request and stable
  payload until the existing host engine acknowledges it.
- Latch returned read data before raising HRDY and drive only the selected HD
  byte lanes during a completed read access; never drive HD during writes or
  waits.
- Keep HRDY high through the end of an access once that access has been
  released to complete, even if it starts a new indirect-memory side effect;
  use that busy state to wait a following selected access.
- Trigger the mandatory HSTCTL HRDY-low interval from HCS and a stable HFS
  selection even before a read/write/byte strobe completes the access.
- Retain HCS reset-strap semantics and active-low HINT.
Tests:
- Add a focused host-pin bridge test covering HCS/read/write/byte-strobe
  starts, waits, payload stability, invalid read+write, HD direction, HSTCTL
  delay, busy carryover, and back-to-back re-arm.
- Convert `tb_pin_system` host traffic to physical pins and retain all
  processor/host I/O, HOLD, and EMU checks.
- Keep existing `tb_host_if`, `tb_host_integration`, and `tb_host_control`
  PASS.
- `scripts/lint.sh` PASS, strict RTL lint clean.
- `scripts/regress.sh` PASS for every discovered self-checking bench.
Docs:
- Update `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/assumptions.md`,
  `docs/completion_audit.md`, `docs/memory_map.md`, and
  `docs/timing_notes.md`.
Commit:
- `85ac04a68fa53fcd45e0ccab6404cfd3e74e44e6`

---

### Task 0154: Enforce reserved I/O fields and locations
Status: complete
Dependencies:
- Task 0137 (interrupt-register reserved fields).
- Task 0141 (DPYTAP reserved fields).
- Task 0150 (host-indirect I/O completion).
Spec sources:
- 1988 TI TMS34010 User's Guide §6.1, Figure 6-1, pages 6-2 through
  6-3 (reserved register locations `C0000170h`–`C00001A0h`).
- CONTROL register, pages 6-10 through 6-14 (bits 1:0 reserved/not used).
- DPYCTL register, pages 6-18 through 6-22 (bit 1 reserved).
- DPYTAP register, pages 6-24 through 6-25 (bits 15:14 reserved/not used).
- PMASK register, pages 6-43 through 6-44 (`C0000170h` compatibility write
  has no effect on the TMS34010).
Acceptance Criteria:
- Add shared package masks for all ordinary stored I/O registers containing
  reserved bits that must remain zero: CONTROL bits 1:0, DPYCTL bit 1, and
  DPYTAP bits 15:14.
- Apply those masks on every completed processor or host-indirect write
  without altering the defined fields or their existing consumers.
- Treat all four reserved register indices 17h through 1Ah as non-storage:
  writes have no effect and processor/host-indirect reads return zero.
- Retain the explicit A0033 choice that software-written REFCNT bits 1:0
  persist; do not silently change an already isolated undefined behavior.
- Keep HSTCTL, INTENB, INTPEND, and live-register ownership unchanged.
Tests:
- Extend `tb_io_regs` to cover CONTROL/DPYCTL/DPYTAP masks and all four
  reserved locations.
- Extend `tb_host_integration` to prove host-indirect reads/writes observe
  the same CONTROL mask and reserved-location behavior after physical
  completion.
- Keep `tb_io_display`, `tb_io_refresh`, `tb_io_interrupts`, and
  `tb_system_fabric` PASS.
- `scripts/lint.sh` PASS, strict RTL lint clean.
- `scripts/regress.sh` PASS for every discovered self-checking bench.
Docs:
- Update `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/assumptions.md`,
  `docs/completion_audit.md`, and `docs/memory_map.md`.
Commit:
- `940e809c45b8f6a23fa5090a6d22343602717ef5`

---

### Task 0155: Introduce the dedicated VCLK domain and video CDC
Status: complete
Dependencies:
- Task 0140 (verified internal timing interval endpoints).
- Task 0141 (live display-address scheduler and held screen request).
- Task 0148 (core-to-local-bus CDC and physical screen-transfer service).
Spec sources:
- 1988 TI TMS34010 User's Guide §2.4, page 2-9 (VCLK is independent
  of INCLK and owns the video timing logic).
- 1988 TI TMS34010 User's Guide §§9.2–9.6, pages 9-3 through 9-12
  (VCLK timing-counter ownership, timing events, and display scheduling).
- 1988 TI TMS34010 User's Guide §9.10.1, pages 9-18 through 9-25
  (screen-refresh scheduling and completed-transfer address updates).
Acceptance Criteria:
- Add an explicit VCLK input through the core, functional-system, and
  original-pin hierarchy; retain same-clock unit-test composition by tying
  that input to the core clock where a separate domain is not under test.
- Move HCOUNT/VCOUNT, all timing compares, DPYADR, and the screen-refresh
  scheduler wholly into VCLK without sampling changing multi-bit buses
  through independent synchronizers.
- Transfer the complete timing/display configuration as an atomic MCP
  snapshot and transfer HCOUNT/VCOUNT/DPYADR writes as coalescing,
  completion-qualified commands.
- Return coherent HCOUNT/VCOUNT/DPYADR snapshots to the core for both
  processor and host-indirect reads, with an explicitly documented bounded
  stale-view contract.
- Carry each display-interrupt event into the core through a lossless
  toggle handshake.
- Carry the held screen-refresh request and bundled SRFADR/DPYTAP/ORG payload
  into the core domain, retain it through arbitrary memory waits, and return
  exactly one completion to VCLK.
- Keep external synchronization, interlaced half-line/address adjustment,
  and physical serial pixel output as subsequent numbered video tasks.
Tests:
- Added `tb_video_cdc` PASS with asynchronous-clock CDC coverage for atomic
  and coalesced configuration,
  live-register commands/snapshots, lossless DIP, stable screen payloads,
  arbitrary completion waits, reset, and non-integer clock ratios.
- Updated `tb_io_video` and `tb_io_display` PASS for completion-qualified
  writes, destination-domain timing/scheduling, coherent live snapshots, DIP,
  and returned screen completion under asynchronous VCLK.
- Updated `tb_pin_system` PASS with an independent VCLK while retaining all
  physical local-bus, host, HOLD, and RUN/EMU checks.
- Existing `tb_video`, `tb_display_addr`, `tb_system_fabric`,
  `tb_host_halt`, `tb_io_regs`, and `tb_host_integration` PASS.
- `scripts/lint.sh` PASS, strict RTL lint clean.
- `REGRESS_JOBS=4 scripts/regress.sh` PASS, 141/141 self-checking benches.
Docs:
- Update `README.md`, `AGENTS.md`, `tasks.md`, `changelog.md`,
  `docs/architecture.md`, `docs/assumptions.md`,
  `docs/completion_audit.md`, `docs/memory_map.md`, and
  `docs/timing_notes.md`.
Commit:
- `04ddaf4c057b24315cd4745a04c4f75bbfb1d6ab`

---

## Task entry template (for future tasks)

```
### Task NNNN: <short imperative title>
Status: <pending|in progress|complete|blocked>
Dependencies:
- Task NNNN (or "none")
Acceptance Criteria:
- <observable, testable bullets>
Tests:
- <named tests that must pass; or explicitly state why testing is deferred>
Docs:
- <which doc files this task updates>
Commit:
- <hash, or "pending">
```

---

## Roadmap (post-Phase 0)

Tracked at coarse granularity here; each phase expands into numbered tasks
when its predecessor lands.

- **Phase 1 — Core shell**: package constants, top-level ports, clock/reset,
  PC skeleton, memory IF, fetch/decode/execute FSM scaffold.
- **Phase 2 — Register/ALU foundation**: register file (A/B + SP + ST + PC),
  ALU, flag logic, shifter, targeted tests.
- **Phase 3 — Instruction fetch/decode**: opcode decode tables, operand
  decode, illegal-opcode trap, `docs/instruction_coverage.md` populated.
- **Phase 4 — Simple execution**: reg-reg, immediates, branches, basic
  load/store, flag updates.
- **Phase 5 — Addressing modes**: architectural modes, field/pixel
  addressing, alignment + boundary behavior.
- **Phase 6 — Memory and bus**: external memory IF, host-visible behavior,
  bus arbitration, wait states.
- **Phase 7 — Graphics**: PIXBLT/FILL/LINE, plane masking, transparency,
  window checking, multi-cycle graphics FSMs.
- **Phase 8 — Interrupts/traps**: reset, IRQ recognition, trap entry/return,
  status save/restore, priority + masking.
- **Phase 9 — Video/display**: video timing, refresh, display memory.
- **Phase 10 — Synthesis & optimization**: Cyclone V build, timing closure,
  resource reduction, regression.
