# Tasks

## Current Milestone: Phase 1 — Core shell

## Task index

| ID | Title | Status |
|----|-------|--------|
| 0001 | Add TMS34010_Info reference submodule | complete |
| 0002 | Create project planning and docs scaffolding | complete |
| 0003 | Initial synthesizable core skeleton + smoke test | complete |
| 0004 | PC module + core integration | complete |
| 0005 | Behavioral memory model + fetch-walk test | in progress |

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
Status: in progress
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
