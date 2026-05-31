// -----------------------------------------------------------------------------
// tms34010_core.sv
//
// Top-level TMS34010 core wrapper. Phase 3 — decode skeleton integrated.
//
// What this module IS, today:
//   - A clocked top-level entity with explicit synchronous active-high reset.
//   - A typed-enum core FSM that fully cycles: CORE_RESET → CORE_FETCH →
//     CORE_DECODE → CORE_EXECUTE → CORE_WRITEBACK → CORE_FETCH (no
//     instruction touches memory in Phase 3, so CORE_MEMORY is unused).
//   - Memory IF that drives `mem_addr` from the PC register and asserts a
//     16-bit fetch in CORE_FETCH. On mem_ack the fetched word is latched
//     into `instr_word_q` and the PC advances by INSTR_WORD_BITS.
//   - A tms34010_decode instance evaluates `instr_word_q` combinationally.
//     Phase 3 skeleton: every encoding is flagged ILLEGAL.
//   - Sticky `illegal_opcode_o` observability output.
//   - Register file, ALU, and status register instantiated and connected
//     into the datapath: ALU result → regfile write-data port, ALU flags
//     → status-register flag-update port. All "go" signals (rf_wr_en,
//     st_flag_update_en, st_write_en) are currently tied to 0 — no
//     instruction is yet decoded into a real datapath action. Task 0012
//     replaces these tie-offs with decoded-instruction-driven values for
//     the first real instruction (MOVI).
//
// What this module IS NOT, yet:
//   - No real instruction decoded. EXECUTE / WRITEBACK are pass-through
//     states; the datapath stays at quiescent values.
//   - No branches / jumps yet, so the PC `load_en` port is tied 0.
//   - The PC starts at `RESET_PC` from the package, currently a placeholder
//     '0 — see docs/assumptions.md A0008 for the architectural reset-vector
//     fetch sequence that is Phase 8 work.
//
// Synthesis notes:
//   - One sequential `always_ff` for the state register.
//   - One `always_comb` for next-state and combinational outputs, with safe
//     defaults at the top to prevent latch inference.
//   - No `/`, `%`, runtime loops, or `initial` blocks.
//   - Reset is synchronous active-high (project convention A0003).
//
// Spec source: third_party/TMS34010_Info/docs/ti-official/
//              1988_TI_TMS34010_Users_Guide.pdf
// -----------------------------------------------------------------------------

`default_nettype none
module tms34010_core
  import tms34010_pkg::*;
(
  input  logic                                clk,
  input  logic                                rst,

  // Memory request/valid interface (stub in Phase 0 skeleton).
  output logic                                mem_req,
  output logic                                mem_we,
  output logic [ADDR_WIDTH-1:0]               mem_addr,
  output logic [FIELD_SIZE_WIDTH-1:0]         mem_size,
  output logic [DATA_WIDTH-1:0]               mem_wdata,
  input  logic [DATA_WIDTH-1:0]               mem_rdata,
  input  logic                                mem_ack,

  // Observability for testbenches (Phase 0..3 — may move to an
  // sva/observability bundle later).
  output core_state_t                         state_o,
  output logic [ADDR_WIDTH-1:0]               pc_o,
  output instr_word_t                         instr_word_o,
  output logic                                illegal_opcode_o
);

  // ---------------------------------------------------------------------------
  // Program counter
  // ---------------------------------------------------------------------------
  logic                  pc_advance_en;
  logic                  pc_load_en;
  logic [ADDR_WIDTH-1:0] pc_load_value;
  logic [ADDR_WIDTH-1:0] pc_value;

  tms34010_pc u_pc (
    .clk            (clk),
    .rst            (rst),
    .load_en        (pc_load_en),
    .load_value     (pc_load_value),
    .advance_en     (pc_advance_en),
    .advance_amount (PC_ADVANCE_WIDTH'(INSTR_WORD_BITS)),
    .pc_o           (pc_value)
  );

  // ---------------------------------------------------------------------------
  // State register
  // ---------------------------------------------------------------------------
  core_state_t state_q;
  core_state_t state_d;

  always_ff @(posedge clk) begin
    if (rst) begin
      state_q <= CORE_RESET;
    end else begin
      state_q <= state_d;
    end
  end

  // ---------------------------------------------------------------------------
  // Instruction word latch + decoder
  //
  // instr_word_q is latched the cycle the memory acks an instruction
  // fetch. The decoder runs combinationally; consumers see the decoded
  // result from CORE_DECODE onward.
  // ---------------------------------------------------------------------------
  instr_word_t    instr_word_q;
  decoded_instr_t decoded;

  always_ff @(posedge clk) begin
    if (rst) begin
      instr_word_q <= '0;
    end else if (state_q == CORE_FETCH && mem_ack) begin
      instr_word_q <= mem_rdata[INSTR_WORD_WIDTH-1:0];
    end
  end

  tms34010_decode u_decode (
    .instr  (instr_word_q),
    .decoded(decoded)
  );

  // Sticky illegal-opcode latch. Set on the cycle we are in CORE_DECODE
  // with an illegal `decoded`. Cleared only by reset.
  logic illegal_q;
  always_ff @(posedge clk) begin
    if (rst) begin
      illegal_q <= 1'b0;
    end else if (state_q == CORE_DECODE && decoded.illegal) begin
      illegal_q <= 1'b1;
    end
  end

  // ---------------------------------------------------------------------------
  // Branch-target computation (PC-relative, short form)
  //
  // For JRUC short and (future) JRcc short: the displacement in
  // instr_word_q[7:0] is a signed 8-bit count of 16-bit words. The new PC
  // is `current_pc + disp * 16` (in bits). `current_pc` is the value AFTER
  // the opcode fetch already advanced the PC by 16, which matches what
  // hand-decoding `JRGT L5 = 0xC70B` at PC=0x3B0 → target 0x470 produces
  // (target = (0x3B0+16) + 11*16 = 0x470).
  //
  // The full target is computed combinationally and only consumed when
  // the FSM is in CORE_WRITEBACK with a taken-branch decoded class.
  // ---------------------------------------------------------------------------
  logic [ADDR_WIDTH-1:0] branch_target_short;
  logic signed [INSTR_WORD_WIDTH-1:0] disp_signed_12;
  // {disp8, 4'h0} = disp * 16 expressed in 12 bits, sign-bit at [11].
  assign disp_signed_12   = $signed({instr_word_q[7:0], 4'h0});
  assign branch_target_short = pc_value + ADDR_WIDTH'(disp_signed_12);

  // Immediate latches — declared up here (before their first use in
  // the branch_target_long / branch_target_jacc combinational
  // computations below) because Questa is strict about forward
  // references in `assign` statements, even though Verilator hoists
  // them. The matching `always_ff` that actually latches imm_lo_q /
  // imm_hi_q on memory acks lives further down (search for
  // CORE_FETCH_IMM_LO / CORE_FETCH_IMM_HI).
  instr_word_t imm_lo_q;
  instr_word_t imm_hi_q;

  // Long-form JRcc target: PC_after_both_fetches + sign_extend(disp16) × 16.
  // By the time the FSM hits CORE_WRITEBACK, pc_value already equals
  // (PC_original + 32 bits) — the opcode FETCH and the IMM_LO FETCH each
  // advanced the PC by 16. `imm_lo_q` holds the 16-bit displacement word.
  // {disp16, 4'h0} is a 20-bit value; sign bit at [19] equals imm_lo_q[15].
  logic [ADDR_WIDTH-1:0]   branch_target_long;
  logic signed [19:0]      disp_signed_20;
  assign disp_signed_20   = $signed({imm_lo_q, 4'h0});
  assign branch_target_long = pc_value + ADDR_WIDTH'(disp_signed_20);

  // JAcc absolute target: PC ← address with the bottom 4 bits forced to 0
  // (spec page 12-91 explicitly: "lower four bits of the program counter
  // are set to 0"). Address is assembled from the two 16-bit imm words
  // already fetched via needs_imm32, same as MOVI IL.
  logic [ADDR_WIDTH-1:0] branch_target_jacc;
  assign branch_target_jacc = {imm_hi_q, imm_lo_q[INSTR_WORD_WIDTH-1:4], 4'h0};

  // DSJS short-form target: PC' ± offset×16 bits.
  // pc_value at CORE_WRITEBACK already equals PC' (= PC_original + 16
  // after the single-word opcode fetch). instr_word_q[10] is the
  // direction bit; instr_word_q[9:5] is the 5-bit unsigned offset.
  logic [ADDR_WIDTH-1:0] branch_target_dsjs;
  logic signed [9:0]     dsjs_disp_bits;
  // Build positive bit-offset = {1'b0, offset5, 4'h0} (signed 10-bit
  // value in [0, +496]), then negate when D=1.
  assign dsjs_disp_bits = instr_word_q[10]
                        ? -10'($signed({1'b0, instr_word_q[9:5], 4'h0}))
                        :  10'($signed({1'b0, instr_word_q[9:5], 4'h0}));
  assign branch_target_dsjs = pc_value + ADDR_WIDTH'(dsjs_disp_bits);

  // ---------------------------------------------------------------------------
  // Multi-step memory transaction support
  //
  // Some instructions (RETI, TRAP, MMTM, MMFM) chain multiple memory
  // transactions within a single CORE_MEMORY stay. `mem_op_step` ticks
  // through 0, 1, ... as each ack arrives; the FSM only exits to
  // CORE_WRITEBACK on the final step. The `popped_st_q` / `popped_pc_q`
  // / `mem_data_q` latches capture mem_rdata between transactions
  // since `mem_rdata` itself is overwritten by the next read.
  // ---------------------------------------------------------------------------
  logic [1:0]            mem_op_step;
  logic [DATA_WIDTH-1:0] popped_st_q;
  logic [DATA_WIDTH-1:0] popped_pc_q;
  // MOVE *Rs,*Rd (indirect-to-indirect): holds the field read at *Rs in
  // step 0 so it can be written to *Rd in step 1 (mem_rdata is overwritten
  // by the next transaction).
  logic [DATA_WIDTH-1:0] move_data_q;

  // TRAP 0 is special per SPVU001A page 12-253: it does NOT push PC' or
  // ST onto the stack — it just sets ST <- 0x10 and fetches the vector
  // at 0xFFFFFFE0. Intended for the SP-corrupt / SP-uninitialised case.
  // We collapse the three-step TRAP sequence to a single vector-fetch
  // step when k5 == 0 (and suppress the SP -64 update via the alu_b mux).
  logic trap_skip_push;
  assign trap_skip_push = (decoded.iclass == INSTR_TRAP) && (decoded.k5 == 5'd0);

  always_ff @(posedge clk) begin
    if (rst) begin
      mem_op_step <= 2'd0;
      popped_st_q <= '0;
      popped_pc_q <= '0;
      move_data_q <= '0;
    end else if (state_q == CORE_MEMORY && mem_ack) begin
      // MOVE *Rs,*Rd: step 0 reads the source field; latch it so step 1
      // can write it to the destination.
      if (decoded.iclass == INSTR_MOVE_FIELD_M2M && mem_op_step == 2'd0) begin
        move_data_q <= mem_rdata;
      end
      // Latch popped values per-iclass per-step before moving on.
      if (decoded.iclass == INSTR_RETI) begin
        if (mem_op_step == 2'd0) popped_st_q <= mem_rdata;
        if (mem_op_step == 2'd1) popped_pc_q <= mem_rdata;
      end
      // TRAP vector fetch:
      //   - N>0: step 2 (after the two pushes).
      //   - N=0: step 0 (the only step).
      if (decoded.iclass == INSTR_TRAP) begin
        if (trap_skip_push) begin
          if (mem_op_step == 2'd0) popped_pc_q <= mem_rdata;
        end else begin
          if (mem_op_step == 2'd2) popped_pc_q <= mem_rdata;
        end
      end
      // Step counter: advance unless this is the final step for the
      // iclass, in which case reset to 0 for the next instruction.
      unique case (decoded.iclass)
        INSTR_RETI: mem_op_step <= (mem_op_step == 2'd1) ? 2'd0 : mem_op_step + 2'd1;
        INSTR_TRAP: mem_op_step <= (trap_skip_push || mem_op_step == 2'd2)
                                 ? 2'd0
                                 : mem_op_step + 2'd1;
        INSTR_MOVE_FIELD_M2M:
                    mem_op_step <= (mem_op_step == 2'd1) ? 2'd0 : mem_op_step + 2'd1;
        default:    mem_op_step <= 2'd0;
      endcase
    end else if (state_q != CORE_MEMORY) begin
      // Defensive reset between instructions.
      mem_op_step <= 2'd0;
    end
  end

  // ---------------------------------------------------------------------------
  // MMTM / MMFM iterator (shared)
  //
  // MMTM (push, INSTR_MMTM) and MMFM (pop, INSTR_MMFM) walk the same
  // 16-bit register-list mask one set bit at a time, one 32-bit memory
  // transaction per bit. They share this iterator state and differ only
  // in scan direction, the +/-32 address step, and read-vs-write:
  //
  //   mm_mask_q (16-bit) shadows the original mask; the just-handled bit
  //   is cleared after each mem_ack.
  //   mm_rp_q (32-bit) is the working stack pointer / current transaction
  //   address.
  //   mm_iter_idx is the priority-encoded current bit:
  //     - MMTM: LOWEST set bit  (lowest-order register saved first).
  //     - MMFM: HIGHEST set bit (highest-order register restored first).
  //   It indexes both the register file and the bit to clear after ack.
  //
  // Address sequencing (predecrement vs postincrement, per SPVU001A
  // pages 12-111 / 12-109):
  //   - MMTM: mm_rp_q seeds to (initial Rp - 32) so the first push lands
  //     at Rp-32; it decrements by 32 after each ack EXCEPT the last, so
  //     the final value (= initial - 32*count) is the lowest written
  //     address, written back as the new Rp.
  //   - MMFM: mm_rp_q seeds to (initial Rp) so the first read is at Rp;
  //     it increments by 32 after EVERY ack including the last, so the
  //     final value (= initial + 32*count) points one word past the data,
  //     written back as the new Rp.
  //
  // Assumption A0026: bit N of the mask = register R(N) for both
  // instructions. The spec's chart was a graphical figure unrecoverable
  // from pdftotext; the MMTM→MMFM round-trip test is the real check, and
  // it only depends on MMTM/MMFM agreeing on the mapping, not its
  // absolute value.
  // ---------------------------------------------------------------------------
  logic [DATA_WIDTH-1:0] mm_rp_q;
  logic [15:0]           mm_mask_q;
  logic [3:0]            mm_iter_idx;
  logic                  mm_mask_will_be_empty;
  logic                  is_mmtm, is_mmfm, is_mm;

  assign is_mmtm = (decoded.iclass == INSTR_MMTM);
  assign is_mmfm = (decoded.iclass == INSTR_MMFM);
  assign is_mm   = is_mmtm || is_mmfm;

  always_comb begin
    mm_iter_idx = 4'd0;
    if (is_mmfm) begin
      // MMFM: highest set bit. Iterate low→high so the LAST overwrite
      // (the largest i with mm_mask_q[i]=1) wins.
      for (int i = 0; i < 16; i++) begin
        if (mm_mask_q[i]) mm_iter_idx = 4'(i);
      end
    end else begin
      // MMTM: lowest set bit. Iterate high→low so the loop terminates
      // on the smallest i with mm_mask_q[i]=1.
      for (int i = 15; i >= 0; i--) begin
        if (mm_mask_q[i]) mm_iter_idx = 4'(i);
      end
    end
  end
  // After we clear the bit at mm_iter_idx, will the mask be empty? Gates
  // the FSM transition (last transaction → WRITEBACK) and, for MMTM,
  // suppresses the final Rp-decrement.
  assign mm_mask_will_be_empty = ((mm_mask_q & ~(16'd1 << mm_iter_idx)) == 16'd0);

  always_ff @(posedge clk) begin
    if (rst) begin
      mm_rp_q   <= '0;
      mm_mask_q <= '0;
    end else if (state_q == CORE_EXECUTE
              && state_d == CORE_MEMORY
              && is_mm) begin
      // First entry to CORE_MEMORY: capture the mask and seed the
      // working Rp. MMTM predecrements (first push at Rp-32); MMFM
      // starts at Rp (first read at Rp).
      mm_rp_q   <= is_mmtm ? (rf_rs2_data - WORD_BIT_SIZE) : rf_rs2_data;
      mm_mask_q <= imm_lo_q;
    end else if (state_q == CORE_MEMORY
              && is_mm
              && mem_ack) begin
      mm_mask_q[mm_iter_idx] <= 1'b0;
      if (is_mmfm) begin
        // Post-increment after every read, including the last.
        mm_rp_q <= mm_rp_q + WORD_BIT_SIZE;
      end else if (!mm_mask_will_be_empty) begin
        // Pre-decrement model: skip the step after the final push so the
        // last write address remains as the new Rp.
        mm_rp_q <= mm_rp_q - WORD_BIT_SIZE;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Immediate latch
  //
  // Long-immediate-form instructions (MOVI IW/IL, ADDI IW/IL, ...) fetch
  // one or two additional 16-bit words after the opcode word. The
  // imm_lo_q / imm_hi_q registers are DECLARED earlier (just before
  // the branch_target_long block) so the assigns above can reference
  // them under strict simulators like Questa; the always_ff that
  // updates them sits here.
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      imm_lo_q <= '0;
      imm_hi_q <= '0;
    end else begin
      if (state_q == CORE_FETCH_IMM_LO && mem_ack) begin
        imm_lo_q <= mem_rdata[INSTR_WORD_WIDTH-1:0];
      end
      if (state_q == CORE_FETCH_IMM_HI && mem_ack) begin
        imm_hi_q <= mem_rdata[INSTR_WORD_WIDTH-1:0];
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Datapath modules
  //
  // Control signals are now driven by `decoded.*` plus the FSM state:
  // writes only happen in CORE_WRITEBACK, and only for instructions whose
  // decoded record requests a writeback (decoded.wb_reg_en /
  // decoded.wb_flags_en).
  // ---------------------------------------------------------------------------

  // Register-file ports.
  reg_file_t              rf_rs1_file;
  reg_idx_t               rf_rs1_idx;
  logic [DATA_WIDTH-1:0]  rf_rs1_data;
  reg_file_t              rf_rs2_file;
  reg_idx_t               rf_rs2_idx;
  logic [DATA_WIDTH-1:0]  rf_rs2_data;
  reg_file_t              rf_rs3_file;
  reg_idx_t               rf_rs3_idx;
  logic [DATA_WIDTH-1:0]  rf_rs3_data;
  logic                   rf_wr_en;
  reg_file_t              rf_wr_file;
  reg_idx_t               rf_wr_idx;
  logic [DATA_WIDTH-1:0]  rf_wr_data;
  logic [DATA_WIDTH-1:0]  rf_sp;

  // ALU ports.
  alu_op_t                alu_op;
  logic [DATA_WIDTH-1:0]  alu_a;
  logic [DATA_WIDTH-1:0]  alu_b;
  logic                   alu_cin;
  logic [DATA_WIDTH-1:0]  alu_result;
  alu_flags_t             alu_flags;

  // Status-register ports.
  logic                   st_flag_update_en;
  logic                   st_write_en;
  logic [DATA_WIDTH-1:0]  st_write_data;
  logic [DATA_WIDTH-1:0]  st_value;
  logic                   st_n, st_c, st_z, st_v;

  // Shifter ports.
  logic [DATA_WIDTH-1:0]  shifter_result;
  alu_flags_t             shifter_flags;

  // ---- Operand assembly ----------------------------------------------------
  // Full 32-bit immediate composed from the latched 16-bit pieces. For
  // IW form: sign-extend (or zero-extend) imm_lo_q. For IL form (Task
  // 0013): concatenate {imm_hi_q, imm_lo_q}.
  logic [DATA_WIDTH-1:0] imm32;
  always_comb begin
    if (decoded.needs_imm32) begin
      imm32 = {imm_hi_q, imm_lo_q};
    end else if (decoded.imm_sign_extend) begin
      imm32 = {{(DATA_WIDTH-INSTR_WORD_WIDTH){imm_lo_q[INSTR_WORD_WIDTH-1]}}, imm_lo_q};
    end else begin
      imm32 = {{(DATA_WIDTH-INSTR_WORD_WIDTH){1'b0}}, imm_lo_q};
    end
  end

  // ---- Register-file selectors driven by decode ----------------------------
  // rs1 reads Rs (used as ALU `a` for reg-reg ops). rs2 reads Rd (used as
  // ALU `b` for reg-reg ops where Rd is also a source, e.g. ADD Rs,Rd).
  // For MOVI / MOVK, the rs1/rs2 reads still occur but their values are
  // not routed to alu_a/b (the alu_b mux picks imm32 or zero-extended k5
  // instead).
  //
  // TMS34010 reg-reg encoding constrains Rs and Rd to the same file, so
  // a single `decoded.rd_file` drives both reads.
  // Read-port 1 normally reads from the destination file (reg-reg ops
  // are same-file). MOVE Rs,Rd is the one cross-file exception: Rs may
  // live in the opposite file from Rd, so it uses decoded.rs_file.
  assign rf_rs1_file = (decoded.iclass == INSTR_MOVE_RR)
                     ? decoded.rs_file
                     : decoded.rd_file;
  // Read-port 1 index is normally decoded.rs_idx. MMTM repurposes it
  // during CORE_MEMORY to scan the register list — rf_rs1_idx then
  // points at the current register being pushed, and rf_rs1_data
  // becomes the 32-bit value driven onto mem_wdata.
  assign rf_rs1_idx  = (state_q == CORE_MEMORY && is_mmtm)
                     ? mm_iter_idx
                     : decoded.rs_idx;
  // Read port 2 normally reads Rd. CPW repurposes it (Rd is not a source
  // for CPW) to read the window-start register WSTART = B5; read port 3
  // reads the window-end register WEND = B6. Both are fixed B-file
  // registers per SPVU001A page 12-57.
  assign rf_rs2_file = (decoded.iclass == INSTR_CPW) ? REG_FILE_B : decoded.rd_file;
  assign rf_rs2_idx  = (decoded.iclass == INSTR_CPW) ? CPW_WSTART_IDX : decoded.rd_idx;
  // Read port 3: CPW reads WEND (B6); DIVU (even Rd) reads the low half of
  // the 64-bit dividend, Rd+1. Otherwise it is unused.
  assign rf_rs3_file = ((decoded.iclass == INSTR_DIVU) || (decoded.iclass == INSTR_DIVS))
                     ? decoded.rd_file : REG_FILE_B;
  assign rf_rs3_idx  = ((decoded.iclass == INSTR_DIVU) || (decoded.iclass == INSTR_DIVS))
                     ? (decoded.rd_idx + 4'd1) : CPW_WEND_IDX;

  // DSJ-family runtime gate. For DSJEQ/DSJNE, the decrement (and any
  // subsequent jump) happens only if the Z bit pre-condition holds:
  //   - DSJ:   unconditional   → gate = 1
  //   - DSJEQ: gated on Z=1    → gate = st_z
  //   - DSJNE: gated on Z=0    → gate = !st_z
  // For non-DSJ instructions this signal is irrelevant; we default
  // it to 1 so it doesn't interfere with their writebacks.
  logic dsj_precondition;
  always_comb begin
    unique case (decoded.iclass)
      INSTR_DSJ,
      INSTR_DSJS:   dsj_precondition = 1'b1;
      INSTR_DSJEQ:  dsj_precondition = st_z;
      INSTR_DSJNE:  dsj_precondition = !st_z;
      default:      dsj_precondition = 1'b1;
    endcase
  end

  // "Will Rd be zero after the decrement?" — needed for the DSJ
  // branch decision. alu_result at WRITEBACK is the decremented Rd
  // (when iclass is one of the DSJ family).
  logic dsj_rd_nonzero;
  assign dsj_rd_nonzero = (alu_result != '0);

  // Writeback enable is a one-cycle pulse, gated by the FSM state.
  // Writeback data and flag-input come from either the ALU or the
  // shifter depending on `decoded.use_shifter`. For DSJEQ/DSJNE the
  // dsj_precondition further gates the write: if Z doesn't match the
  // pre-condition the spec mandates Rd is left unchanged.
  // MMFM writes a popped register on every CORE_MEMORY ack (mem_rdata is
  // valid in the same cycle mem_ack asserts). This is a second user of
  // the single regfile write port, active in CORE_MEMORY rather than
  // CORE_WRITEBACK; the final-Rp write still happens at WRITEBACK below.
  // Rp is never in the list (spec: "unpredictable results"), so the two
  // writes never target the same index.
  logic mmfm_pop_wr;
  assign mmfm_pop_wr = (state_q == CORE_MEMORY) && is_mmfm && mem_ack;

  // ---- Indirect MOVE addressing + auto inc/dec (Task 0059/0060) -----------
  // Pointer register: Rd for stores (rf_rs2), Rs for loads (rf_rs1). The
  // memory address is the pointer (postinc/none) or pointer-32 (predec);
  // the post-update pointer value is pointer±32 (FS=32). For LOAD inc/dec
  // the updated pointer is written to Rs during CORE_MEMORY (a second
  // regfile-write user, like mmfm_pop_wr); the data write to Rd happens at
  // WRITEBACK, so when Rs==Rd the data wins (SPVU001A 12-143).
  logic                  is_mv_store, is_mv_load;
  logic                  mv_postinc, mv_predec, mv_incdec;
  logic [DATA_WIDTH-1:0] mv_ptr, mv_addr, mv_ptr_new;
  logic                  mv_load_ptr_wr;
  assign is_mv_store = (decoded.iclass == INSTR_MOVE_FIELD_STORE);
  assign is_mv_load  = (decoded.iclass == INSTR_MOVE_FIELD_LOAD);
  assign mv_postinc  = (decoded.move_mode == MV_ADDR_POSTINC);
  assign mv_predec   = (decoded.move_mode == MV_ADDR_PREDEC);
  assign mv_incdec   = mv_postinc || mv_predec;
  assign mv_ptr      = is_mv_store ? rf_rs2_data : rf_rs1_data;
  assign mv_addr     = mv_predec ? (mv_ptr - WORD_BIT_SIZE) : mv_ptr;
  assign mv_ptr_new  = mv_predec ? (mv_ptr - WORD_BIT_SIZE) : (mv_ptr + WORD_BIT_SIZE);
  assign mv_load_ptr_wr = (state_q == CORE_MEMORY) && is_mv_load
                       && mv_incdec && mem_ack;

  // ---- Indirect-to-indirect MOVE auto inc/dec (Task 0062) -----------------
  // Two pointers (Rs=source, Rd=dest) both step by ±32. The source pointer
  // (Rs) is written during CORE_MEMORY at the step-0 (read) ack; the
  // destination pointer (Rd) is written at WRITEBACK. The step-1 (write)
  // address uses rf_rs2_data, which — when Rs==Rd — already reflects the
  // step-0 Rs update, so a postincrement Rs==Rd writes to the incremented
  // location (SPVU001A 12-138). To avoid double-stepping that one register,
  // the WRITEBACK Rd write is suppressed when Rs==Rd.
  logic                  is_mv_m2m, m2m_same_reg, m2m_src_wr;
  logic [DATA_WIDTH-1:0] m2m_src_addr, m2m_dst_addr, m2m_src_new, m2m_dst_new;
  assign is_mv_m2m    = (decoded.iclass == INSTR_MOVE_FIELD_M2M);
  assign m2m_same_reg = (decoded.rs_idx == decoded.rd_idx);
  assign m2m_src_addr = mv_predec ? (rf_rs1_data - WORD_BIT_SIZE) : rf_rs1_data;
  assign m2m_dst_addr = mv_predec ? (rf_rs2_data - WORD_BIT_SIZE) : rf_rs2_data;
  assign m2m_src_new  = mv_predec ? (rf_rs1_data - WORD_BIT_SIZE) : (rf_rs1_data + WORD_BIT_SIZE);
  assign m2m_dst_new  = mv_predec ? (rf_rs2_data - WORD_BIT_SIZE) : (rf_rs2_data + WORD_BIT_SIZE);
  // Update the source pointer Rs at the step-0 read ack (inc/dec M2M only).
  assign m2m_src_wr   = (state_q == CORE_MEMORY) && is_mv_m2m && mv_incdec
                     && (mem_op_step == 2'd0) && mem_ack;

  assign rf_wr_en   = ((state_q == CORE_WRITEBACK)
                       && decoded.wb_reg_en
                       && dsj_precondition
                       && !(is_mv_m2m && m2m_same_reg)   // Rs==Rd: Rs write already covered it
                       && !(is_div && div_v))            // divide overflow: leave Rd unchanged
                   || mmfm_pop_wr
                   || mv_load_ptr_wr
                   || m2m_src_wr;
  assign rf_wr_file = decoded.rd_file;
  assign rf_wr_idx  = mmfm_pop_wr                  ? mm_iter_idx
                    : (mv_load_ptr_wr || m2m_src_wr) ? decoded.rs_idx  // update pointer Rs
                    : ((is_mpy || is_div) && pair_wb_step) ? (decoded.rd_idx + 4'd1)  // pair low/rem -> Rd+1
                                                     : decoded.rd_idx;
  // EXGF (Exchange Field Definition) datapath. Per SPVU001A page 12-77:
  // Rd's low 6 bits swap with the F-selected FE:FS pair (1 + 5 bits)
  // in ST. Rd's upper 26 bits are cleared after the swap.
  //
  // Because the regfile is async-read, rf_rs2_data delivers the OLD
  // Rd value during the same CORE_WRITEBACK cycle that writes the
  // new value — so a single-cycle atomic swap is straightforward.
  logic [4:0]            exgf_cur_fs;
  logic                  exgf_cur_fe;
  logic [DATA_WIDTH-1:0] exgf_new_rd;
  logic [DATA_WIDTH-1:0] exgf_new_st;
  assign exgf_cur_fs = instr_word_q[9] ? st_value[ST_FS1_HI:ST_FS1_LO]
                                       : st_value[ST_FS0_HI:ST_FS0_LO];
  assign exgf_cur_fe = instr_word_q[9] ? st_value[ST_FE1_BIT]
                                       : st_value[ST_FE0_BIT];
  assign exgf_new_rd = {{(DATA_WIDTH-6){1'b0}}, exgf_cur_fe, exgf_cur_fs};
  always_comb begin
    exgf_new_st = st_value;
    if (instr_word_q[9]) begin
      exgf_new_st[ST_FS1_HI:ST_FS1_LO] = rf_rs2_data[4:0];
      exgf_new_st[ST_FE1_BIT]          = rf_rs2_data[5];
    end else begin
      exgf_new_st[ST_FS0_HI:ST_FS0_LO] = rf_rs2_data[4:0];
      exgf_new_st[ST_FE0_BIT]          = rf_rs2_data[5];
    end
  end

  // ---- ADDXY / SUBXY datapath (XY-coordinate arithmetic) ------------------
  // Treat each register as two 16-bit halves: X = low 16, Y = high 16.
  // ADDXY/SUBXY operate on the halves independently, with NO carry/borrow
  // propagating between them. Rd is both a source and the destination;
  // rf_rs2_data delivers the old Rd, rf_rs1_data the Rs operand.
  //   ADDXY (SPVU001A 12-41):  N=(Xres==0), V=Xres[15], Z=(Yres==0), C=Yres[15].
  //   SUBXY (SPVU001A 12-252): compare-style flags — N=(RsX==RdX),
  //     V=(RsX>RdX), Z=(RsY==RdY), C=(RsY>RdY) (unsigned, = subtract borrow).
  logic [15:0] xy_rs_x, xy_rs_y, xy_rd_x, xy_rd_y;
  logic [15:0] xy_x_add, xy_y_add, xy_x_sub, xy_y_sub;
  logic [DATA_WIDTH-1:0] addxy_result, subxy_result;
  alu_flags_t            addxy_flags, subxy_flags;
  assign xy_rs_x = rf_rs1_data[15:0];
  assign xy_rs_y = rf_rs1_data[DATA_WIDTH-1:16];
  assign xy_rd_x = rf_rs2_data[15:0];
  assign xy_rd_y = rf_rs2_data[DATA_WIDTH-1:16];
  assign xy_x_add = xy_rd_x + xy_rs_x;     // 16-bit, carry dropped
  assign xy_y_add = xy_rd_y + xy_rs_y;
  assign xy_x_sub = xy_rd_x - xy_rs_x;     // Rd - Rs per spec
  assign xy_y_sub = xy_rd_y - xy_rs_y;
  assign addxy_result = {xy_y_add, xy_x_add};
  assign subxy_result = {xy_y_sub, xy_x_sub};
  assign addxy_flags = '{n: (xy_x_add == 16'd0), c: xy_y_add[15],
                          z: (xy_y_add == 16'd0), v: xy_x_add[15]};
  // (RsX>RdX) unsigned == borrow out of (RdX - RsX) == (xy_rd_x < xy_rs_x).
  assign subxy_flags = '{n: (xy_x_sub == 16'd0), c: (xy_rd_y < xy_rs_y),
                          z: (xy_y_sub == 16'd0), v: (xy_rd_x < xy_rs_x)};
  // CMPXY (SPVU001A 12-55): nondestructive; flags use the SIGN bits of the
  // per-half subtract results (NOT the unsigned borrow SUBXY uses).
  alu_flags_t cmpxy_flags;
  assign cmpxy_flags = '{n: (xy_x_sub == 16'd0), c: xy_y_sub[15],
                          z: (xy_y_sub == 16'd0), v: xy_x_sub[15]};

  // ---- CPW (Compare Point to Window) datapath (SPVU001A 12-57) ------------
  // Compare the XY point in Rs (rf_rs1) against the window corners
  // WSTART = B5 (rf_rs2, overridden above) and WEND = B6 (rf_rs3). X = low
  // 16 signed, Y = high 16 signed. The 4-bit out-of-window code lands in
  // Rd[8:5]; all other bits 0. V = 1 iff the point is outside the window
  // (any code bit set); N/C/Z Unaffected (masked off by wb_flag_mask).
  logic [15:0] cpw_pt_x, cpw_pt_y, cpw_ws_x, cpw_ws_y, cpw_we_x, cpw_we_y;
  logic        cpw_b5, cpw_b6, cpw_b7, cpw_b8;
  logic [DATA_WIDTH-1:0] cpw_result;
  alu_flags_t  cpw_flags;
  assign cpw_pt_x = rf_rs1_data[15:0];
  assign cpw_pt_y = rf_rs1_data[DATA_WIDTH-1:16];
  assign cpw_ws_x = rf_rs2_data[15:0];        // WSTART.X (B5)
  assign cpw_ws_y = rf_rs2_data[DATA_WIDTH-1:16];
  assign cpw_we_x = rf_rs3_data[15:0];        // WEND.X   (B6)
  assign cpw_we_y = rf_rs3_data[DATA_WIDTH-1:16];
  assign cpw_b5 = ($signed(cpw_ws_x) > $signed(cpw_pt_x));  // WSTART.X > Rs.X
  assign cpw_b6 = ($signed(cpw_pt_x) > $signed(cpw_we_x));  // Rs.X > WEND.X
  assign cpw_b7 = ($signed(cpw_ws_y) > $signed(cpw_pt_y));  // WSTART.Y > Rs.Y
  assign cpw_b8 = ($signed(cpw_pt_y) > $signed(cpw_we_y));  // Rs.Y > WEND.Y
  assign cpw_result = {{(DATA_WIDTH-9){1'b0}}, cpw_b8, cpw_b7, cpw_b6, cpw_b5, 5'b0};
  assign cpw_flags  = '{n: 1'b0, c: 1'b0, z: 1'b0,
                         v: (cpw_b5 | cpw_b6 | cpw_b7 | cpw_b8)};

  // ---- MPYS / MPYU multiply datapath (SPVU001A 12-164/12-166) -------------
  // Rd (rf_rs2) is the 32-bit multiplicand, Rs (rf_rs1) the multiplier — an
  // FS1-bit field (FS1=0 means 32, the whole Rs). The 64-bit product is
  // latched in CORE_EXECUTE (mpy_product_q — the registered output for DSP
  // inference) and written back over 1 cycle (odd Rd: low 32 to Rd) or 2
  // cycles (even Rd: hi 32 to Rd, then lo 32 to Rd+1). pair_wb_step (shared
  // with DIVU) selects the second pass.
  logic                  is_mpy, mpy_signed, mpy_rd_even;
  logic signed [63:0]    mpy_sprod;
  logic        [63:0]    mpy_uprod, mpy_product, mpy_product_q;
  assign is_mpy      = (decoded.iclass == INSTR_MPYS) || (decoded.iclass == INSTR_MPYU);
  assign mpy_signed  = (decoded.iclass == INSTR_MPYS);
  assign mpy_rd_even = (decoded.rd_idx[0] == 1'b0);
  // Variable multiplier width: extract the low FS1 bits of Rs and
  // sign-extend (MPYS) or zero-extend (MPYU) to 32 bits before the multiply;
  // Rd (the multiplicand) stays full 32-bit.
  logic [4:0]            mpy_fs1;
  logic [DATA_WIDTH-1:0] mpy_fmask;
  logic [DATA_WIDTH-1:0] mpy_rs_field;
  assign mpy_fs1   = st_value[ST_FS1_HI:ST_FS1_LO];
  assign mpy_fmask = (32'd1 << mpy_fs1) - 32'd1;   // FS1 1..31; FS1=0 uses full Rs below
  always_comb begin
    if (mpy_fs1 == 5'd0) begin
      mpy_rs_field = rf_rs1_data;                                    // FS1 = 32
    end else if (mpy_signed && rf_rs1_data[mpy_fs1 - 5'd1]) begin
      mpy_rs_field = (rf_rs1_data & mpy_fmask) | ~mpy_fmask;         // MPYS sign-extend
    end else begin
      mpy_rs_field = rf_rs1_data & mpy_fmask;                        // zero-extend / positive
    end
  end
  // 64-bit-context products: operands sign/zero-extend to 64 then multiply.
  assign mpy_sprod   = $signed(rf_rs2_data) * $signed(mpy_rs_field);
  assign mpy_uprod   = rf_rs2_data * mpy_rs_field;
  assign mpy_product = mpy_signed ? unsigned'(mpy_sprod) : mpy_uprod;

  // ---- DIVU divide datapath (SPVU001A 12-69) -----------------------------
  // Multi-cycle restoring divider runs in CORE_DIVIDE. Even Rd: 64-bit
  // dividend {Rd, Rd+1} (Rd+1 read via port 3) -> quotient in Rd, remainder
  // in Rd+1. Odd Rd: 32-bit dividend Rd -> quotient in Rd. On overflow
  // (divisor 0 or quotient > 32 bits) the result is NOT written; only V is
  // set. The product/quotient pair-writeback to {Rd, Rd+1} is shared with
  // MPY via pair_wb_step.
  // is_div = the whole divide family (DIVU/MODU/DIVS/MODS) — anything that
  // runs the multi-cycle divider via CORE_DIVIDE. The divider itself is
  // unsigned; for the signed variants the core feeds |operands| and
  // sign-conditions the results.
  logic                  is_div, is_divu, is_modu, is_divs, is_mods;
  logic                  is_signed_div, is_div_mod, div_rd_even, div_use_pair;
  logic [2*DATA_WIDTH-1:0] div_dividend;
  logic [DATA_WIDTH-1:0]   div_divisor, div_quotient, div_remainder;
  logic                    div_start, div_busy, div_done, div_overflow;
  assign is_divu       = (decoded.iclass == INSTR_DIVU);
  assign is_modu       = (decoded.iclass == INSTR_MODU);
  assign is_divs       = (decoded.iclass == INSTR_DIVS);
  assign is_mods       = (decoded.iclass == INSTR_MODS);
  assign is_div        = is_divu || is_modu || is_divs || is_mods;
  assign is_signed_div = is_divs || is_mods;
  assign is_div_mod    = is_modu || is_mods;        // remainder result (vs quotient)
  assign div_rd_even   = (decoded.rd_idx[0] == 1'b0);
  // Only DIVU/DIVS with an even Rd use the 64-bit {Rd, Rd+1} dividend; the
  // MOD ops and odd-Rd divides use the 32-bit {0/sext, Rd} dividend.
  assign div_use_pair  = (is_divu || is_divs) && div_rd_even;

  // Operand signs (signed variants only) and magnitudes fed to the divider.
  // The combinational signs drive the divider-input abs at CORE_EXECUTE;
  // the LATCHED signs (_q, captured at the divide start) drive the result
  // sign-conditioning at WRITEBACK — by then Rd may already hold the
  // quotient (even-Rd pass 0), so its live MSB is no longer the dividend's.
  logic div_dvd_sign, div_dvs_sign, div_result_neg;
  logic div_dvd_sign_q, div_dvs_sign_q;
  assign div_dvd_sign = is_signed_div && rf_rs2_data[DATA_WIDTH-1];   // Rd MSB
  assign div_dvs_sign = is_signed_div && rf_rs1_data[DATA_WIDTH-1];   // Rs MSB
  assign div_result_neg = div_dvd_sign_q ^ div_dvs_sign_q;            // quotient sign

  always_ff @(posedge clk) begin
    if (rst) begin
      div_dvd_sign_q <= 1'b0;
      div_dvs_sign_q <= 1'b0;
    end else if (state_q == CORE_EXECUTE && is_div) begin
      div_dvd_sign_q <= div_dvd_sign;
      div_dvs_sign_q <= div_dvs_sign;
    end
  end

  logic [DATA_WIDTH-1:0]   rd_abs;
  logic [2*DATA_WIDTH-1:0] raw64, abs64;
  assign rd_abs = rf_rs2_data[DATA_WIDTH-1] ? (~rf_rs2_data + 1'b1) : rf_rs2_data;
  assign raw64  = {rf_rs2_data, rf_rs3_data};
  assign abs64  = rf_rs2_data[DATA_WIDTH-1] ? (~raw64 + 1'b1) : raw64;
  always_comb begin
    if (!is_signed_div)
      div_dividend = div_use_pair ? raw64 : {{DATA_WIDTH{1'b0}}, rf_rs2_data};
    else if (div_use_pair)
      div_dividend = abs64;                                // |{Rd, Rd+1}|
    else
      div_dividend = {{DATA_WIDTH{1'b0}}, rd_abs};         // {0, |Rd|}
  end
  assign div_divisor = div_dvs_sign ? (~rf_rs1_data + 1'b1) : rf_rs1_data;

  // One-cycle start pulse as we leave CORE_EXECUTE for CORE_DIVIDE; the
  // divider latches the operands on that edge.
  assign div_start = (state_q == CORE_EXECUTE) && is_div;

  tms34010_divider u_divider (
    .clk       (clk),
    .rst       (rst),
    .start     (div_start),
    .dividend  (div_dividend),
    .divisor   (div_divisor),
    .busy      (div_busy),
    .done      (div_done),
    .quotient  (div_quotient),
    .remainder (div_remainder),
    .overflow  (div_overflow)
  );

  // Sign-condition the magnitude results, and compute the divide-family
  // result/flags. div_quot_out/div_rem_out are the (possibly negated)
  // values; div_result_main is what the flags/Z reflect.
  logic [DATA_WIDTH-1:0] div_quot_out, div_rem_out, div_result_main;
  assign div_quot_out = div_result_neg  ? (~div_quotient  + 1'b1) : div_quotient;
  assign div_rem_out  = div_dvd_sign_q  ? (~div_remainder + 1'b1) : div_remainder;
  assign div_result_main = is_div_mod ? div_rem_out : div_quot_out;
  // Signed overflow: the magnitude quotient must fit a signed 32-bit value.
  //   positive result: |q| >= 2^31  -> overflow
  //   negative result: |q| >  2^31  -> overflow (|q|==2^31 is -2^31, valid)
  // (div_overflow already covers Rs=0 and |q| >= 2^32.)
  logic div_signed_ovf, div_v;
  assign div_signed_ovf = div_overflow
    || (is_signed_div &&
        (div_result_neg ? (div_quotient[DATA_WIDTH-1] && (div_quotient[DATA_WIDTH-2:0] != '0))
                        :  div_quotient[DATA_WIDTH-1]));
  assign div_v = is_signed_div ? div_signed_ovf : div_overflow;

  // ---- Pair writeback step (shared MPY-even / DIVU-even) ------------------
  // Ops that write the {Rd, Rd+1} register pair over two WRITEBACK cycles.
  // pair_wb_step selects the second pass (Rd+1). DIVU on overflow writes
  // nothing, so it is not a pair-writeback op then.
  logic is_pair_wb, pair_second_pass, pair_wb_step;
  assign is_pair_wb = (is_mpy && mpy_rd_even)
                   || (div_use_pair && !div_v);   // DIVU/DIVS even (not MOD; not on overflow)
  assign pair_second_pass = is_pair_wb && (pair_wb_step == 1'b0);

  always_ff @(posedge clk) begin
    if (rst) begin
      mpy_product_q <= '0;
      pair_wb_step  <= 1'b0;
    end else begin
      if (state_q == CORE_EXECUTE && is_mpy) begin
        mpy_product_q <= mpy_product;
      end
      // Step 0 -> 1 only while we hold in WRITEBACK for the second pass.
      if (state_q == CORE_WRITEBACK) begin
        pair_wb_step <= pair_second_pass ? 1'b1 : 1'b0;
      end else begin
        pair_wb_step <= 1'b0;
      end
    end
  end

  // SEXT / ZEXT field-extension datapath. Per SPVU001A pages 12-238
  // (SEXT) and 12-256 (ZEXT): take the low `FS` bits of Rd, then
  // either sign-extend (copy the field MSB into bits[31:FS]) or
  // zero-extend (clear bits[31:FS]). FS is read from the F-selected
  // pair in ST (FS0 if instr_word_q[9]=0, FS1 if =1). FS=5'b00000
  // encodes a field-size of 32 per Table 5-3, so the data is the
  // full 32-bit register and no extension is needed.
  logic [4:0]            fs_selected;
  logic [DATA_WIDTH-1:0] field_mask;
  logic                  field_msb;
  logic [DATA_WIDTH-1:0] sext_result;
  logic [DATA_WIDTH-1:0] zext_result;
  assign fs_selected = instr_word_q[9]
                     ? st_value[ST_FS1_HI:ST_FS1_LO]
                     : st_value[ST_FS0_HI:ST_FS0_LO];
  always_comb begin
    if (fs_selected == 5'd0) begin
      // Field-size = 32: identity.
      field_mask  = '1;
      field_msb   = rf_rs2_data[DATA_WIDTH-1];
      sext_result = rf_rs2_data;
      zext_result = rf_rs2_data;
    end else begin
      field_mask  = (32'd1 << fs_selected) - 32'd1;
      field_msb   = rf_rs2_data[fs_selected - 5'd1];
      sext_result = field_msb ? ((rf_rs2_data & field_mask) | ~field_mask)
                              :  (rf_rs2_data & field_mask);
      zext_result = rf_rs2_data & field_mask;
    end
  end

  // LMO (Leftmost-One) datapath. Pure combinational — finds the
  // highest-set bit of rf_rs1_data and computes Rd = 31 - bit_pos
  // (i.e., one's-complement of the bit position in 5 bits). The
  // upper 27 bits of Rd are zero. If rf_rs1_data == 0, Rd = 0 and
  // the Z flag (gated by wb_flag_mask) is set.
  logic [4:0]            lmo_bit_pos;
  logic [DATA_WIDTH-1:0] lmo_result;
  always_comb begin
    // Iterate low-to-high so the LAST overwrite (highest set bit)
    // wins. Synthesizable — no `break`, no run-time loop.
    lmo_bit_pos = 5'd0;
    for (int i = 0; i < DATA_WIDTH; i++) begin
      if (rf_rs1_data[i]) lmo_bit_pos = 5'(i);
    end
    if (rf_rs1_data == '0)
      lmo_result = '0;
    else
      lmo_result = {{(DATA_WIDTH-5){1'b0}}, ~lmo_bit_pos};
  end

  // Regfile write-data mux. Several "Rd ← something" instructions
  // bypass the ALU/shifter and route a different source:
  //   GETST  → ST value
  //   GETPC  → current PC value
  //   EXGPC  → current PC value (the other half of the swap)
  //   REV    → chip-revision constant (A0025)
  //   LMO_RR → priority-encoder result
  // The default routes the shifter or ALU result per decoded.use_shifter.
  always_comb begin
    unique case (decoded.iclass)
      // MOVX: Rd.X (low 16) <- Rs.X, Rd.Y (high 16) kept. MOVY: Rd.Y <-
      // Rs.Y, Rd.X kept. rf_rs1=Rs, rf_rs2=old Rd (async read, same cycle).
      INSTR_MOVX:   rf_wr_data = {rf_rs2_data[DATA_WIDTH-1:16], rf_rs1_data[15:0]};
      INSTR_MOVY:   rf_wr_data = {rf_rs1_data[DATA_WIDTH-1:16], rf_rs2_data[15:0]};
      INSTR_ADDXY:  rf_wr_data = addxy_result;
      INSTR_SUBXY:  rf_wr_data = subxy_result;
      INSTR_CPW:    rf_wr_data = cpw_result;
      // MPYS/MPYU: even Rd -> hi32 then (Rd+1) lo32; odd Rd -> lo32.
      INSTR_MPYS,
      INSTR_MPYU:   rf_wr_data = mpy_rd_even
                               ? (pair_wb_step ? mpy_product_q[31:0] : mpy_product_q[63:32])
                               : mpy_product_q[31:0];
      // DIVU: even Rd -> quotient (pass 0), remainder -> Rd+1 (pass 1);
      // odd Rd -> quotient. (Skipped entirely on overflow via rf_wr_en.)
      // DIVU/DIVS: even Rd -> quotient (pass 0), remainder -> Rd+1 (pass 1);
      // odd Rd -> quotient. div_quot_out/div_rem_out are sign-conditioned
      // (identity for the unsigned variants).
      INSTR_DIVU,
      INSTR_DIVS:   rf_wr_data = (div_rd_even && pair_wb_step) ? div_rem_out
                                                              : div_quot_out;
      // MODU/MODS: the remainder of Rd mod Rs -> Rd (single writeback).
      INSTR_MODU,
      INSTR_MODS:   rf_wr_data = div_rem_out;
      INSTR_GETST:  rf_wr_data = st_value;
      INSTR_MMTM:   rf_wr_data = mm_rp_q;       // final Rp = address of last push
      // MMFM: per-iteration pop writes mem_rdata to the popped register;
      // the WRITEBACK pass writes final Rp (= initial + 32*count).
      INSTR_MMFM:   rf_wr_data = mmfm_pop_wr ? mem_rdata : mm_rp_q;
      // MOVE *Rs,Rd: Rd <- the 32 bits read from mem[Rs]. mem_rdata still
      // holds the value at WRITEBACK (no new transaction is issued there).
      // Store inc/dec writes the auto-updated pointer back to Rd at
      // WRITEBACK (plain store has wb_reg_en=0, so this is unused there).
      INSTR_MOVE_FIELD_STORE: rf_wr_data = mv_ptr_new;
      // Load: at WRITEBACK -> the loaded data to Rd; during CORE_MEMORY
      // (inc/dec) -> the updated pointer to Rs.
      INSTR_MOVE_FIELD_LOAD: rf_wr_data = mv_load_ptr_wr ? mv_ptr_new : mem_rdata;
      // Indirect-to-indirect inc/dec: source pointer Rs (step-0 ack) or
      // destination pointer Rd (WRITEBACK).
      INSTR_MOVE_FIELD_M2M: rf_wr_data = m2m_src_wr ? m2m_src_new : m2m_dst_new;
      // MOVE @SAddr,Rd: Rd <- the field read from the absolute address.
      INSTR_MOVE_ABS_LOAD:  rf_wr_data = mem_rdata;
      // MOVE *Rs(off),Rd: Rd <- the field read from the offset address.
      INSTR_MOVE_OFF_LOAD:  rf_wr_data = mem_rdata;
      INSTR_GETPC,
      INSTR_EXGPC:  rf_wr_data = pc_value;
      INSTR_REV:    rf_wr_data = REV_VALUE;
      INSTR_LMO_RR: rf_wr_data = lmo_result;
      INSTR_SEXT:   rf_wr_data = sext_result;
      INSTR_ZEXT:   rf_wr_data = zext_result;
      INSTR_EXGF:   rf_wr_data = exgf_new_rd;
      default:      rf_wr_data = decoded.use_shifter ? shifter_result : alu_result;
    endcase
  end

  // ALU operand selection.
  //
  // Default routing puts Rs on `alu_a` and Rd on `alu_b`, which works for
  // commutative reg-reg ops (ADD, AND, OR, XOR, ...) and for the move
  // family (`alu_b` is overridden to the immediate / K).
  //
  // For SUB (Rd - Rs → Rd) the order matters: we need `alu_a = Rd` and
  // `alu_b = Rs` because the ALU computes `a - b`. The two muxes below
  // swap routing for `INSTR_SUB_RR`.
  assign alu_op  = decoded.alu_op;
  always_comb begin
    unique case (decoded.iclass)
      INSTR_SUB_RR,
      INSTR_SUBB_RR,
      INSTR_ANDN_RR,
      INSTR_CMP_RR,
      INSTR_ADDK,
      INSTR_SUBK,
      INSTR_NEG,
      INSTR_NOT,
      INSTR_ABS,
      INSTR_ADDI_IW,
      INSTR_SUBI_IW,
      INSTR_CMPI_IW,
      INSTR_ADDI_IL,
      INSTR_SUBI_IL,
      INSTR_CMPI_IL,
      INSTR_ANDI_IL,
      INSTR_ORI_IL,
      INSTR_XORI_IL,
      INSTR_DSJ,
      INSTR_DSJEQ,
      INSTR_DSJNE,
      INSTR_DSJS,
      INSTR_BTST_K,
      INSTR_BTST_RR: alu_a = rf_rs2_data;   // Rd is the operand
      INSTR_NEGB:    alu_a = '0;            // NEGB: 0 - Rd - C via SUBB
      INSTR_PUSHST,
      INSTR_POPST,
      INSTR_CALL_RS,
      INSTR_CALLA,
      INSTR_CALLR,
      INSTR_RETS,
      INSTR_RETI,
      INSTR_TRAP:    alu_a = rf_rs2_data;   // SP via rs2 (rd_idx=15)
      default:       alu_a = rf_rs1_data;   // Rs (or unused for MOVI/MOVK)
    endcase
  end
  always_comb begin
    unique case (decoded.iclass)
      INSTR_MOVI_IW,
      INSTR_MOVI_IL,
      INSTR_ADDI_IW,
      INSTR_SUBI_IW,
      INSTR_CMPI_IW,
      INSTR_ADDI_IL,
      INSTR_SUBI_IL,
      INSTR_CMPI_IL,
      INSTR_ANDI_IL,
      INSTR_ORI_IL,
      INSTR_XORI_IL: alu_b = imm32;
      INSTR_MOVK,
      INSTR_ADDK,
      INSTR_SUBK,
      INSTR_DSJ,
      INSTR_DSJEQ,
      INSTR_DSJNE,
      INSTR_DSJS:    alu_b = {{(DATA_WIDTH-5){1'b0}}, decoded.k5};
      INSTR_BTST_K:  alu_b = 32'd1 << decoded.k5;
      INSTR_BTST_RR: alu_b = 32'd1 << rf_rs1_data[4:0];
      INSTR_PUSHST,
      INSTR_POPST,
      INSTR_CALL_RS,
      INSTR_CALLA,
      INSTR_CALLR:   alu_b = WORD_BIT_SIZE;
      INSTR_RETS:    alu_b = WORD_BIT_SIZE + ({{(DATA_WIDTH-5){1'b0}}, decoded.k5} << 4);
      INSTR_RETI:    alu_b = WORD_BIT_SIZE_2;     // SP += 32 (ST pop) + 32 (PC pop) = 64
      INSTR_TRAP:    alu_b = trap_skip_push ? 32'd0 : WORD_BIT_SIZE_2;
                                          // N>0: SP -= 64 (PC push + ST push).
                                          // N=0: SP unchanged (TRAP 0 skips pushes).
      INSTR_SUB_RR,
      INSTR_SUBB_RR,
      INSTR_ANDN_RR,
      INSTR_CMP_RR:  alu_b = rf_rs1_data;   // Rs is the "second" operand
      default:       alu_b = rf_rs2_data;
    endcase
  end
  assign alu_cin = st_c;

  // Status-register inputs. Flag-update is gated by FSM state, like the
  // regfile write. Full ST write port is unused until POPST lands.
  assign st_flag_update_en = (state_q == CORE_WRITEBACK) && decoded.wb_flags_en;
  // ST-write data + enable. Two instructions drive the full ST-write
  // path:
  //   PUTST Rs: ST ← Rs (full copy).
  //   SETF FS, FE, F: read current ST, splice the F-selected FS/FE
  //                   pair with the new values from the instruction
  //                   word, write back.
  //
  // SETF operand extraction (from instr_word_q):
  //   F  = instr_word_q[9]
  //   FE = instr_word_q[5]
  //   FS = instr_word_q[4:0]
  logic [DATA_WIDTH-1:0] setf_new_st;
  always_comb begin
    setf_new_st = st_value;  // start from current
    if (instr_word_q[9]) begin
      // F=1: update FS1 (bits[10:6]) and FE1 (bit[11]).
      setf_new_st[ST_FS1_HI:ST_FS1_LO] = instr_word_q[4:0];
      setf_new_st[ST_FE1_BIT]          = instr_word_q[5];
    end else begin
      // F=0: update FS0 (bits[4:0]) and FE0 (bit[5]).
      setf_new_st[ST_FS0_HI:ST_FS0_LO] = instr_word_q[4:0];
      setf_new_st[ST_FE0_BIT]          = instr_word_q[5];
    end
  end

  assign st_write_en = (state_q == CORE_WRITEBACK)
                    && ((decoded.iclass == INSTR_PUTST) ||
                        (decoded.iclass == INSTR_SETF)  ||
                        (decoded.iclass == INSTR_EXGF)  ||
                        (decoded.iclass == INSTR_DINT)  ||
                        (decoded.iclass == INSTR_EINT)  ||
                        (decoded.iclass == INSTR_POPST) ||
                        (decoded.iclass == INSTR_RETI)  ||
                        (decoded.iclass == INSTR_TRAP));
  always_comb begin
    unique case (decoded.iclass)
      INSTR_PUTST: st_write_data = rf_rs1_data;
      INSTR_SETF:  st_write_data = setf_new_st;
      INSTR_EXGF:  st_write_data = exgf_new_st;
      INSTR_DINT:  st_write_data = st_value & ~(32'd1 << ST_IE_BIT);
      INSTR_EINT:  st_write_data = st_value |  (32'd1 << ST_IE_BIT);
      INSTR_POPST: st_write_data = mem_rdata;        // popped 32-bit ST value
      INSTR_RETI:  st_write_data = popped_st_q;      // ST captured in step 0
      INSTR_TRAP:  st_write_data = ST_RESET_VALUE;   // 0x10: IE=0, flags=0, FS0=16, FS1=0 (= reset ST).
      default:     st_write_data = '0;
    endcase
  end

  // ---- Branch-condition evaluator -----------------------------------------
  // Combinational decode of decoded.branch_cc against the current ST
  // flags. Returns 1 if the branch should be taken. Codes not in the
  // verified set (A0017) return 0 (no branch); the decoder is responsible
  // for routing unverified codes to ILLEGAL so this default isn't reached
  // by a recognized JRCC.
  logic branch_taken;
  always_comb begin
    unique case (decoded.branch_cc)
      CC_UC:   branch_taken = 1'b1;
      CC_LO:   branch_taken = st_c;                   // unsigned <
      CC_LS:   branch_taken = st_c | st_z;             // unsigned <=
      CC_HI:   branch_taken = !st_c & !st_z;           // unsigned >
      CC_LT:   branch_taken = st_n ^ st_v;             // signed   <
      CC_LE:   branch_taken = (st_n ^ st_v) | st_z;    // signed   <=
      CC_GT:   branch_taken = !(st_n ^ st_v) & !st_z;  // signed   >
      CC_GE:   branch_taken = !(st_n ^ st_v);          // signed   >=
      CC_EQ:   branch_taken = st_z;                    // =
      CC_NE:   branch_taken = !st_z;                   // !=
      CC_HS:   branch_taken = !st_c;                   // unsigned >=  (== NC)
      default: branch_taken = 1'b0;
    endcase
  end

  // ---- PC-load (branches) -------------------------------------------------
  // Gated by FSM state. For JRcc short, load the relative target in
  // CORE_WRITEBACK only when the condition is met.
  always_comb begin
    pc_load_en    = 1'b0;
    pc_load_value = '0;
    if (state_q == CORE_WRITEBACK) begin
      unique case (decoded.iclass)
        INSTR_JRCC_SHORT: begin
          if (branch_taken) begin
            pc_load_en    = 1'b1;
            pc_load_value = branch_target_short;
          end
        end
        INSTR_JRCC_LONG: begin
          if (branch_taken) begin
            pc_load_en    = 1'b1;
            pc_load_value = branch_target_long;
          end
        end
        INSTR_JUMP_RS: begin
          // Unconditional indirect jump: load PC from Rs (read via rs1
          // port) with the bottom 4 bits forced to 0 to enforce
          // word alignment per SPVU001A page 12-98.
          pc_load_en    = 1'b1;
          pc_load_value = {rf_rs1_data[ADDR_WIDTH-1:4], 4'h0};
        end
        INSTR_EXGPC: begin
          // Atomic swap PC ↔ Rd: PC ← old Rd (with bottom 4 bits forced
          // to 0 per A0025), Rd ← PC (via the rf_wr_data mux above).
          // rf_rs2_data is the async-read value of decoded.rd_idx in
          // the same file as the destination — i.e., the OLD Rd value.
          pc_load_en    = 1'b1;
          pc_load_value = {rf_rs2_data[ADDR_WIDTH-1:4], 4'h0};
        end
        INSTR_DSJ,
        INSTR_DSJEQ,
        INSTR_DSJNE: begin
          // Decrement-and-skip-jump family. Branch taken iff the
          // runtime pre-condition (always for DSJ; Z gate for
          // DSJEQ/DSJNE) holds AND the post-decrement Rd is nonzero.
          // Target shape matches the long-form JRcc:
          //   target = PC' + sign_extend(offset16) * 16
          // where PC' is pc_value at WRITEBACK (already advanced
          // through the opcode + offset-word fetches).
          if (dsj_precondition && dsj_rd_nonzero) begin
            pc_load_en    = 1'b1;
            pc_load_value = branch_target_long;
          end
        end
        INSTR_JACC: begin
          // Absolute conditional jump: PC ← {imm_hi_q, imm_lo_q} with
          // the bottom 4 bits forced to 0 (word alignment per spec
          // page 12-91). Re-uses the JRcc condition evaluator.
          if (branch_taken) begin
            pc_load_en    = 1'b1;
            pc_load_value = branch_target_jacc;
          end
        end
        INSTR_DSJS: begin
          // Short-form decrement-and-skip-jump. Branch taken iff the
          // post-decrement Rd is non-zero (dsj_precondition = 1 for
          // DSJS just like DSJ). Target = PC' ± offset×16 per
          // instr_word_q[10] direction bit.
          if (dsj_rd_nonzero) begin
            pc_load_en    = 1'b1;
            pc_load_value = branch_target_dsjs;
          end
        end
        INSTR_CALL_RS: begin
          // Subroutine call indirect: PC <- Rs (with bottom 4 bits
          // forced to 0 per SPVU001A page 12-47 "always sets the four
          // LSBs of the program counter to 0"). The return address
          // PC' has already been pushed to mem[new SP] in
          // CORE_MEMORY by the time we reach this WRITEBACK arm.
          pc_load_en    = 1'b1;
          pc_load_value = {rf_rs1_data[ADDR_WIDTH-1:4], 4'h0};
        end
        INSTR_CALLA: begin
          // Absolute call: PC <- {imm_hi_q, imm_lo_q} with bottom 4
          // bits cleared. Same target as JAcc (branch_target_jacc).
          pc_load_en    = 1'b1;
          pc_load_value = branch_target_jacc;
        end
        INSTR_CALLR: begin
          // Relative call: PC <- PC' + sign_ext(disp16) * 16. Same
          // target as JRcc long-form (branch_target_long).
          pc_load_en    = 1'b1;
          pc_load_value = branch_target_long;
        end
        INSTR_RETS: begin
          // Return from subroutine: PC <- popped value (= mem_rdata,
          // which the memory model still holds after the ack since it
          // doesn't clear on IDLE). The popped value is already
          // word-aligned (since it was pushed by a CALL/CALLA/CALLR
          // or TRAP), so no bottom-nibble mask is needed.
          pc_load_en    = 1'b1;
          pc_load_value = mem_rdata;
        end
        INSTR_RETI: begin
          // Return from interrupt: PC <- popped_pc_q (latched in
          // step 1 of CORE_MEMORY). The matching popped ST is delivered
          // via the st_write_en path above.
          pc_load_en    = 1'b1;
          pc_load_value = popped_pc_q;
        end
        INSTR_TRAP: begin
          // Software interrupt: PC <- trap-vector value (latched into
          // popped_pc_q on step 2 of CORE_MEMORY). New ST is delivered
          // via the st_write_en path; SP -64 lands via alu_result/regfile.
          pc_load_en    = 1'b1;
          pc_load_value = popped_pc_q;
        end
        default: ; // no branch
      endcase
    end
  end

  tms34010_regfile u_regfile (
    .clk      (clk),
    .rst      (rst),
    .rs1_file (rf_rs1_file),
    .rs1_idx  (rf_rs1_idx),
    .rs1_data (rf_rs1_data),
    .rs2_file (rf_rs2_file),
    .rs2_idx  (rf_rs2_idx),
    .rs2_data (rf_rs2_data),
    .rs3_file (rf_rs3_file),
    .rs3_idx  (rf_rs3_idx),
    .rs3_data (rf_rs3_data),
    .wr_en    (rf_wr_en),
    .wr_file  (rf_wr_file),
    .wr_idx   (rf_wr_idx),
    .wr_data  (rf_wr_data),
    .sp_o     (rf_sp)
  );

  tms34010_alu u_alu (
    .op    (alu_op),
    .a     (alu_a),
    .b     (alu_b),
    .cin   (alu_cin),
    .result(alu_result),
    .flags (alu_flags)
  );

  // Shifter datapath. Operand is the Rd register value (via rf_rs2_data,
  // which already reads decoded.rd_idx in the same file as the
  // destination). Shift amount comes from one of two sources:
  //   - K-form shifts (SLA/SLL/SRA/SRL/RL K, Rd):  decoded.k5 (literal K)
  //   - Rs-form left/rotate shifts (SLA/SLL/RL Rs, Rd):  Rs[4:0] directly
  //   - Rs-form right shifts (SRA/SRL Rs, Rd):  2's complement of Rs[4:0]
  //     (per spec page 12-219; "use the 2s complement value of the
  //     5 LSBs in Rs"). The negation is done here in the amount mux.
  logic [SHIFT_AMOUNT_WIDTH-1:0] shifter_amount;
  always_comb begin
    unique case (decoded.iclass)
      INSTR_SLA_RR,
      INSTR_SLL_RR,
      INSTR_RL_RR:  shifter_amount = rf_rs1_data[SHIFT_AMOUNT_WIDTH-1:0];
      INSTR_SRA_RR,
      INSTR_SRL_RR: shifter_amount = (~rf_rs1_data[SHIFT_AMOUNT_WIDTH-1:0])
                                     + {{(SHIFT_AMOUNT_WIDTH-1){1'b0}}, 1'b1};
      default:      shifter_amount = decoded.k5;
    endcase
  end

  tms34010_shifter u_shifter (
    .op    (decoded.shift_op),
    .a     (rf_rs2_data),
    .amount(shifter_amount),
    .result(shifter_result),
    .flags (shifter_flags)
  );

  // Flag-input mux: status register samples either ALU flags or shifter
  // flags depending on the source of the result.
  // Flag-input mux: SET/CLR-C inject a constant C value (paired with
  // the wb_flag_mask = c-only in their decoder arms); other
  // flag-affecting instructions get their flags from the ALU or shifter
  // per `decoded.use_shifter`.
  alu_flags_t  flag_input;
  always_comb begin
    unique case (decoded.iclass)
      INSTR_SETC:   flag_input = '{n: 1'b0, c: 1'b1, z: 1'b0, v: 1'b0};
      INSTR_CLRC:   flag_input = '{n: 1'b0, c: 1'b0, z: 1'b0, v: 1'b0};
      INSTR_LMO_RR: flag_input = '{n: 1'b0, c: 1'b0,
                                    z: (rf_rs1_data == '0), v: 1'b0};
      INSTR_SEXT:   flag_input = '{n: sext_result[DATA_WIDTH-1], c: 1'b0,
                                    z: (sext_result == '0), v: 1'b0};
      INSTR_ZEXT:   flag_input = '{n: 1'b0, c: 1'b0,
                                    z: (zext_result == '0), v: 1'b0};
      // MMTM (SPVU001A page 12-111): N = sign of (0 - original Rp) with
      // exceptions Rp=0 -> 1 and Rp=0x80000000 -> 0; the closed form is
      // N = ~Rp[31]. rf_rs2_data still reads the ORIGINAL Rp during
      // WRITEBACK (the final-Rp write is in flight on the same edge, and
      // the regfile read returns the pre-write value). C/Z/V are masked
      // off (Unaffected) via wb_flag_mask, so only the N field matters.
      INSTR_MMTM:   flag_input = '{n: ~rf_rs2_data[DATA_WIDTH-1],
                                    c: 1'b0, z: 1'b0, v: 1'b0};
      // MOVE *Rs,Rd: implicit compare-to-0 of the loaded field. At field
      // size 32 the field IS the full 32-bit word (no extension), so N/Z
      // come straight from mem_rdata; V=0; C masked off by wb_flag_mask.
      INSTR_MOVE_FIELD_LOAD,
      INSTR_MOVE_ABS_LOAD,
      INSTR_MOVE_OFF_LOAD:  flag_input = '{n: mem_rdata[DATA_WIDTH-1],
                                    c: 1'b0, z: (mem_rdata == '0), v: 1'b0};
      INSTR_ADDXY:  flag_input = addxy_flags;
      INSTR_SUBXY:  flag_input = subxy_flags;
      INSTR_CMPXY:  flag_input = cmpxy_flags;
      INSTR_CPW:    flag_input = cpw_flags;
      // MPYS: N/Z from the 64-bit product. MPYU: Z only (N masked off).
      INSTR_MPYS,
      INSTR_MPYU:   flag_input = '{n: mpy_product_q[63], c: 1'b0,
                                    z: (mpy_product_q == 64'd0), v: 1'b0};
      // Divide family (DIVU/DIVS/MODU/MODS): V = overflow; Z = (result==0);
      // N = result sign (signed variants only — masked off for unsigned by
      // wb_flag_mask). The result is the quotient (DIV) or remainder (MOD),
      // already sign-conditioned. On overflow N/Z read 0; for the MOD ops
      // the Z mask is cleared on overflow (effective_flag_mask) so Z stays
      // Unaffected when Rs=0.
      INSTR_DIVU,
      INSTR_DIVS,
      INSTR_MODU,
      INSTR_MODS:   flag_input = '{n: (is_signed_div && !div_v && div_result_main[DATA_WIDTH-1]),
                                    c: 1'b0,
                                    z: (!div_v && (div_result_main == '0)),
                                    v: div_v};
      default:      flag_input = decoded.use_shifter ? shifter_flags : alu_flags;
    endcase
  end

  // Effective per-flag update mask. Normally the decoded mask, but MODU
  // (and the future MODS) leave Z "Unaffected" when Rs=0 (overflow), which
  // is a runtime condition the static decode mask can't express.
  alu_flags_t effective_flag_mask;
  always_comb begin
    effective_flag_mask = decoded.wb_flag_mask;
    if (is_div_mod && div_v) effective_flag_mask.z = 1'b0;  // MODU/MODS: Z unaffected on Rs=0
  end

  tms34010_status_reg u_status_reg (
    .clk             (clk),
    .rst             (rst),
    .flag_update_en  (st_flag_update_en),
    .flags_in        (flag_input),
    .flag_update_mask(effective_flag_mask),
    .st_write_en     (st_write_en),
    .st_write_data   (st_write_data),
    .st_o            (st_value),
    .n_o             (st_n),
    .c_o             (st_c),
    .z_o             (st_z),
    .v_o             (st_v)
  );

  // Currently-unused datapath observability — keep the lint sweep
  // clean without falsely claiming we consume the value.
  logic [DATA_WIDTH-1:0] unused_rf_sp;
  logic [DATA_WIDTH-1:0] unused_st_value;
  logic                  unused_st_nv;
  assign unused_rf_sp    = rf_sp;
  assign unused_st_value = st_value;
  assign unused_st_nv    = st_n ^ st_v ^ st_z;  // touch all three to suppress


  // ---------------------------------------------------------------------------
  // Next-state + combinational outputs
  //
  // Safe defaults at the top — none of the output muxes can infer a latch.
  // ---------------------------------------------------------------------------
  always_comb begin
    // Defaults.
    state_d       = state_q;
    mem_req       = 1'b0;
    mem_we        = 1'b0;
    mem_addr      = '0;
    mem_size      = '0;
    mem_wdata     = '0;
    pc_advance_en = 1'b0;

    unique case (state_q)
      CORE_RESET: begin
        // Unconditional one-cycle transition out of reset.
        state_d = CORE_FETCH;
      end

      CORE_FETCH: begin
        // Architectural instruction word is 16 bits. Fetch from PC.
        mem_req  = 1'b1;
        mem_we   = 1'b0;
        mem_addr = pc_value;
        mem_size = INSTR_WORD_BITS;
        if (mem_ack) begin
          state_d       = CORE_DECODE;
          pc_advance_en = 1'b1;       // advance PC by INSTR_WORD_BITS
        end
      end

      CORE_DECODE: begin
        // Branch based on how many immediate words the decoded
        // instruction needs.
        if (decoded.needs_imm32) begin
          state_d = CORE_FETCH_IMM_LO;
        end else if (decoded.needs_imm16) begin
          state_d = CORE_FETCH_IMM_LO;
        end else begin
          state_d = CORE_EXECUTE;
        end
      end

      CORE_FETCH_IMM_LO: begin
        // Fetch the 16-bit low-immediate word from PC. Same protocol as
        // CORE_FETCH; PC advances by INSTR_WORD_BITS on ack.
        mem_req  = 1'b1;
        mem_we   = 1'b0;
        mem_addr = pc_value;
        mem_size = INSTR_WORD_BITS;
        if (mem_ack) begin
          pc_advance_en = 1'b1;
          state_d = decoded.needs_imm32 ? CORE_FETCH_IMM_HI : CORE_EXECUTE;
        end
      end

      CORE_FETCH_IMM_HI: begin
        mem_req  = 1'b1;
        mem_we   = 1'b0;
        mem_addr = pc_value;
        mem_size = INSTR_WORD_BITS;
        if (mem_ack) begin
          pc_advance_en = 1'b1;
          state_d = CORE_EXECUTE;
        end
      end

      CORE_EXECUTE: begin
        // ALU output and flags are combinational from decoded.alu_op,
        // alu_a, alu_b, and st_c. CORE_EXECUTE lets that result settle
        // for one cycle. For instructions that need a memory
        // transaction (PUSHST and the rest of the stack/CALL family),
        // route through CORE_MEMORY first; otherwise go straight to
        // CORE_WRITEBACK.
        // Divide instructions hand off to the multi-cycle divider; others
        // go to memory (if any) then writeback.
        if (is_div)
          state_d = CORE_DIVIDE;
        else
          state_d = decoded.needs_memory_op ? CORE_MEMORY : CORE_WRITEBACK;
      end

      CORE_DIVIDE: begin
        // Hold while the divider runs; proceed to writeback when it signals
        // done (results, incl. the overflow flag, are then stable).
        state_d = div_done ? CORE_WRITEBACK : CORE_DIVIDE;
      end

      CORE_MEMORY: begin
        // Memory transaction state for instructions that set
        // decoded.needs_memory_op. The IF signals (mem_req, mem_we,
        // mem_addr, mem_size, mem_wdata) are driven per iclass.
        unique case (decoded.iclass)
          INSTR_PUSHST: begin
            // Write ST to mem[new SP] as a 32-bit transfer.
            mem_req   = 1'b1;
            mem_we    = 1'b1;
            mem_addr  = alu_result;        // = SP - 32
            mem_size  = MEM_SIZE_32;
            mem_wdata = st_value;          // ST
          end
          INSTR_POPST: begin
            // Read 32-bit ST from mem[OLD SP]. The increment-by-32
            // happens via the ALU; we don't want alu_result here,
            // we want the pre-increment SP value. POPST has
            // rd_idx=15 (SP) on rs2 — so rs2 gives OLD SP.
            mem_req   = 1'b1;
            mem_we    = 1'b0;
            mem_addr  = rf_rs2_data;       // = current SP
            mem_size  = MEM_SIZE_32;
          end
          INSTR_CALL_RS,
          INSTR_CALLA,
          INSTR_CALLR: begin
            // Push PC' to mem[new SP]. new SP = alu_result = SP - 32.
            // pc_value at this point is PC' — the address of the
            // first instruction AFTER the CALL's full encoding:
            //   CALL Rs:  PC + 16 bits  (single-word opcode)
            //   CALLR:    PC + 32 bits  (opcode + 16-bit disp)
            //   CALLA:    PC + 48 bits  (opcode + 16-bit LO + 16-bit HI)
            // All three increments have already happened by the time
            // we enter CORE_MEMORY (via the FETCH / FETCH_IMM_LO /
            // FETCH_IMM_HI advances).
            mem_req   = 1'b1;
            mem_we    = 1'b1;
            mem_addr  = alu_result;        // = SP - 32
            mem_size  = MEM_SIZE_32;
            mem_wdata = pc_value;          // PC' (return address)
          end
          INSTR_RETS: begin
            // Pop PC from mem[OLD SP]. mem_addr = current SP value
            // (rf_rs2_data) — NOT alu_result, which is SP + 32 + 16*N.
            mem_req   = 1'b1;
            mem_we    = 1'b0;
            mem_addr  = rf_rs2_data;       // = current SP
            mem_size  = MEM_SIZE_32;
          end
          INSTR_RETI: begin
            // Two-step pop: step 0 reads ST from mem[SP]; step 1 reads
            // PC from mem[SP+32]. Both 32-bit reads. The latched
            // popped_st_q / popped_pc_q values flow to the WRITEBACK
            // ST-write and PC-load paths below.
            mem_req   = 1'b1;
            mem_we    = 1'b0;
            mem_size  = MEM_SIZE_32;
            mem_addr  = (mem_op_step == 2'd0)
                      ? rf_rs2_data                  // = SP
                      : (rf_rs2_data + WORD_BIT_SIZE);      // = SP + 32
          end
          INSTR_TRAP: begin
            // Three-step sequence for N>0 — see SPVU001A page 12-252:
            //   step 0: write PC' at SP-32       (push return address)
            //   step 1: write ST  at SP-64       (push status reg)
            //   step 2: read trap vector @ V_N   (= 0xFFFFFFE0 - N*32)
            // SP itself is updated via alu_result (= SP - 64) at
            // WRITEBACK; ST is replaced with 0x00000010; PC is loaded
            // from popped_pc_q (latched on step 2).
            //
            // For TRAP 0 (`trap_skip_push`): collapse to a single step
            // that is the vector fetch — no pushes (per spec note 1
            // page 12-253). SP stays unchanged (alu_b=0 above).
            mem_req   = 1'b1;
            mem_size  = MEM_SIZE_32;
            if (trap_skip_push) begin
              mem_we    = 1'b0;
              mem_addr  = TRAP_VECTOR_BASE;        // N=0 ⇒ vector @ 0xFFFFFFE0
            end else begin
              unique case (mem_op_step)
                2'd0: begin
                  mem_we    = 1'b1;
                  mem_addr  = rf_rs2_data - WORD_BIT_SIZE;
                  mem_wdata = pc_value;             // PC'
                end
                2'd1: begin
                  mem_we    = 1'b1;
                  mem_addr  = rf_rs2_data - WORD_BIT_SIZE_2;
                  mem_wdata = st_value;             // ST as it stood
                end
                default: begin                       // step 2
                  mem_we    = 1'b0;
                  // Trap-vector address = TRAP_VECTOR_BASE - N*32.
                  // N is decoded.k5 (5 bits); N*32 = N << 5.
                  mem_addr  = TRAP_VECTOR_BASE
                            - ({{(ADDR_WIDTH-5){1'b0}}, decoded.k5} << 5);
                end
              endcase
            end
          end
          INSTR_MMTM: begin
            // Push the register currently selected by mm_iter_idx to
            // mem[mm_rp_q]. Each iteration of CORE_MEMORY is one 32-bit
            // write; mm_mask_q and mm_rp_q advance on the ack. We stay
            // in CORE_MEMORY until the mask is empty.
            mem_req   = 1'b1;
            mem_we    = 1'b1;
            mem_addr  = mm_rp_q;
            mem_size  = MEM_SIZE_32;
            mem_wdata = rf_rs1_data;       // = value of register R(mm_iter_idx)
          end
          INSTR_MMFM: begin
            // Pop: read 32 bits from mem[mm_rp_q] into the register
            // selected by mm_iter_idx (highest-order first). The regfile
            // write happens via the mmfm_pop_wr path; here we just drive
            // the read. mm_mask_q clears the bit and mm_rp_q advances
            // (+32) on the ack. Stay in CORE_MEMORY until mask empty.
            mem_req   = 1'b1;
            mem_we    = 1'b0;
            mem_addr  = mm_rp_q;
            mem_size  = MEM_SIZE_32;
          end
          INSTR_MOVE_FIELD_STORE: begin
            // MOVE Rs,*Rd[+|-]: write Rs (rf_rs1_data) to mem[mv_addr].
            // mv_addr = pointer Rd (postinc/none) or Rd-32 (predec). The
            // pointer auto-update (Rd±32) is written back at WRITEBACK for
            // the inc/dec forms. 32-bit field, word-aligned.
            mem_req   = 1'b1;
            mem_we    = 1'b1;
            mem_addr  = mv_addr;           // = Rd or Rd-32 (predec)
            mem_size  = MEM_SIZE_32;
            mem_wdata = rf_rs1_data;       // = Rs (data)
          end
          INSTR_MOVE_FIELD_LOAD: begin
            // MOVE [-]*Rs[+],Rd: read 32 bits from mem[mv_addr]. mv_addr =
            // pointer Rs (postinc/none) or Rs-32 (predec). The loaded data
            // goes to Rd at WRITEBACK; for inc/dec the updated pointer Rs±32
            // is written via the mv_load_ptr_wr path on this ack.
            mem_req   = 1'b1;
            mem_we    = 1'b0;
            mem_addr  = mv_addr;           // = Rs or Rs-32 (predec)
            mem_size  = MEM_SIZE_32;
          end
          INSTR_MOVE_OFF_STORE: begin
            // MOVE Rs,*Rd(off): write Rs (rf_rs1_data) to mem[Rd + off].
            // imm32 = sign-extended 16-bit offset; Rd = rf_rs2_data.
            mem_req   = 1'b1;
            mem_we    = 1'b1;
            mem_addr  = rf_rs2_data + imm32;
            mem_size  = MEM_SIZE_32;
            mem_wdata = rf_rs1_data;       // = Rs (data)
          end
          INSTR_MOVE_OFF_LOAD: begin
            // MOVE *Rs(off),Rd: read mem[Rs + off]; result -> Rd at
            // WRITEBACK. Rs = rf_rs1_data (pointer); imm32 = sext(off16).
            mem_req   = 1'b1;
            mem_we    = 1'b0;
            mem_addr  = rf_rs1_data + imm32;
            mem_size  = MEM_SIZE_32;
          end
          INSTR_MOVE_ABS_STORE: begin
            // MOVE Rs,@DAddr: write Rs (rf_rs1_data) to the 32-bit absolute
            // address (imm32 = {imm_hi_q, imm_lo_q}). Single 32-bit write.
            mem_req   = 1'b1;
            mem_we    = 1'b1;
            mem_addr  = imm32;
            mem_size  = MEM_SIZE_32;
            mem_wdata = rf_rs1_data;       // = Rs (data)
          end
          INSTR_MOVE_ABS_LOAD: begin
            // MOVE @SAddr,Rd: read 32 bits from the absolute address imm32;
            // result goes to Rd at WRITEBACK (rf_wr_data mux), flags from
            // the loaded data.
            mem_req   = 1'b1;
            mem_we    = 1'b0;
            mem_addr  = imm32;
            mem_size  = MEM_SIZE_32;
          end
          INSTR_MOVE_FIELD_M2M: begin
            // Two-step indirect-to-indirect: step 0 reads mem[*Rs], step 1
            // writes the latched field (move_data_q) to mem[*Rd]. 32-bit,
            // word-aligned. m2m_src_addr/m2m_dst_addr fold in the predec -32
            // (plain form: move_mode=NONE -> they equal Rs/Rd). For inc/dec
            // the pointers are updated via the m2m_src_wr / WRITEBACK paths.
            mem_req   = 1'b1;
            mem_size  = MEM_SIZE_32;
            if (mem_op_step == 2'd0) begin
              mem_we   = 1'b0;
              mem_addr = m2m_src_addr;     // = Rs (or Rs-32 predec)
            end else begin
              mem_we   = 1'b1;
              mem_addr = m2m_dst_addr;     // = Rd (or Rd-32 predec; updated Rs if Rs==Rd)
              mem_wdata = move_data_q;     // field read in step 0
            end
          end
          default: ;  // no transaction (shouldn't reach with needs_memory_op=0)
        endcase
        if (mem_ack) begin
          // Multi-step instructions stay in CORE_MEMORY until their
          // final step's ack; everything else transitions on every ack.
          unique case (decoded.iclass)
            INSTR_RETI: if (mem_op_step == 2'd1) state_d = CORE_WRITEBACK;
            INSTR_TRAP: if (trap_skip_push || mem_op_step == 2'd2)
                          state_d = CORE_WRITEBACK;
            INSTR_MMTM,
            INSTR_MMFM: if (mm_mask_will_be_empty) state_d = CORE_WRITEBACK;
            INSTR_MOVE_FIELD_M2M: if (mem_op_step == 2'd1) state_d = CORE_WRITEBACK;
            default:    state_d = CORE_WRITEBACK;
          endcase
        end
      end

      CORE_WRITEBACK: begin
        // An even-Rd multiply/divide needs a second writeback cycle to
        // store the low half (product LSBs / divide remainder) into Rd+1.
        state_d = pair_second_pass ? CORE_WRITEBACK : CORE_FETCH;
      end

      default: begin
        // Defensive: any out-of-range encoding goes back to reset.
        state_d = CORE_RESET;
      end
    endcase
  end

  assign state_o          = state_q;
  assign pc_o             = pc_value;
  assign instr_word_o     = instr_word_q;
  assign illegal_opcode_o = illegal_q;

endmodule : tms34010_core
`default_nettype wire
