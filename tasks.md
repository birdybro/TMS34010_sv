# Tasks

## Current Milestone: Phase 2 — Register and ALU foundation

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
| 0009 | Status register (ST) | in progress |

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
Status: in progress
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
- pending

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
