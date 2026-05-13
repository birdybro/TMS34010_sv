// -----------------------------------------------------------------------------
// tb_abs_negb.sv
//
// Completes the unary-instruction family that NEG/NOT started in
// Task 0022: adds ABS and NEGB.
//
// Spec sources:
//   - ABS Rd  : SPVU001A page 12-34 ("Store Absolute Value").
//               Encoding `0000 0011 100R DDDD` (bits[6:5]=00 in the
//               unary family).
//   - NEGB Rd : SPVU001A page 12-168 ("Negate Register with Borrow").
//               Encoding `0000 0011 110R DDDD` (bits[6:5]=10).
//
// Test vectors are drawn directly from the spec's worked example tables:
//   ABS  page 12-34
//   NEGB page 12-168
//
// ABS notes:
//   - Per spec table, N is the sign of `0 - Rd` (NOT the sign of |Rd|).
//   - V=1 only when Rd was 0x80000000 (the overflow case where |Rd|
//     can't be represented; spec returns Rd unchanged).
//   - C is "Unaffected" per spec, but our all-or-nothing wb_flags_en
//     forces C update — we clear it (documented in A0024).
//
// NEGB notes:
//   - Rd = -Rd - C. Uses ALU_OP_SUBB with alu_a=0, alu_b=Rd, cin=ST.C.
//   - All four flags (N, C, Z, V) are spec-correct for NEGB —
//     standard SUB-style flag generation.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_abs_negb;
  import tms34010_pkg::*;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  logic                          mem_req;
  logic                          mem_we;
  logic [ADDR_WIDTH-1:0]         mem_addr;
  logic [FIELD_SIZE_WIDTH-1:0]   mem_size;
  logic [DATA_WIDTH-1:0]         mem_wdata;
  logic [DATA_WIDTH-1:0]         mem_rdata;
  logic                          mem_ack;
  core_state_t                   state_w;
  logic [ADDR_WIDTH-1:0]         pc_w;
  instr_word_t                   instr_w;
  logic                          illegal_w;

  tms34010_core u_core (
    .clk             (clk),
    .rst             (rst),
    .mem_req         (mem_req),
    .mem_we          (mem_we),
    .mem_addr        (mem_addr),
    .mem_size        (mem_size),
    .mem_wdata       (mem_wdata),
    .mem_rdata       (mem_rdata),
    .mem_ack         (mem_ack),
    .state_o         (state_w),
    .pc_o            (pc_w),
    .instr_word_o    (instr_w),
    .illegal_opcode_o(illegal_w)
  );

  sim_memory_model #(.DEPTH_WORDS(256)) u_mem (
    .clk      (clk),
    .rst      (rst),
    .mem_req  (mem_req),
    .mem_we   (mem_we),
    .mem_addr (mem_addr),
    .mem_size (mem_size),
    .mem_wdata(mem_wdata),
    .mem_rdata(mem_rdata),
    .mem_ack  (mem_ack)
  );

  // ---------------------------------------------------------------------------
  // Encoding helpers.
  //
  //   Unary family base: 0000 0011 1ooR DDDD, with `oo` selecting sub-op.
  //   {top9, oo, R, DDDD} = 0x0380 base for ABS (oo=00), 0x03A0 for NEG,
  //   0x03C0 for NEGB, 0x03E0 for NOT.
  //
  //   ABS  Rd = 0x0380 | (R<<4) | Rd
  //   NEGB Rd = 0x03C0 | (R<<4) | Rd
  // ---------------------------------------------------------------------------
  function automatic instr_word_t abs_enc(input reg_file_t rf, input reg_idx_t idx);
    abs_enc = 16'h0380 | (instr_word_t'(rf) << 4) | (instr_word_t'(idx));
  endfunction
  function automatic instr_word_t negb_enc(input reg_file_t rf, input reg_idx_t idx);
    negb_enc = 16'h03C0 | (instr_word_t'(rf) << 4) | (instr_word_t'(idx));
  endfunction

  function automatic instr_word_t movi_il_enc(input reg_file_t rf, input reg_idx_t i);
    movi_il_enc = 16'h09E0 | (instr_word_t'(rf) << 4) | (instr_word_t'(i));
  endfunction

  function automatic instr_word_t add_rr_enc(input reg_idx_t rs_idx,
                                             input reg_file_t rf,
                                             input reg_idx_t rd_idx);
    add_rr_enc = 16'h4000
               | (instr_word_t'(rs_idx) << 5)
               | (instr_word_t'(rf)     << 4)
               | (instr_word_t'(rd_idx));
  endfunction

  function automatic int unsigned place_movi_il(input int unsigned p,
                                                input reg_file_t   rf,
                                                input reg_idx_t    i,
                                                input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]     = movi_il_enc(rf, i);
    u_mem.mem[p + 1] = imm[15:0];
    u_mem.mem[p + 2] = imm[31:16];
    place_movi_il = p + 3;
  endfunction

  int unsigned failures;
  task automatic check_reg(input string label,
                           input logic [DATA_WIDTH-1:0] actual,
                           input logic [DATA_WIDTH-1:0] expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%08h actual=%08h",
               label, expected, actual);
      failures++;
    end
  endtask

  task automatic check_bit(input string label, input logic actual, input logic expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%0b actual=%0b",
               label, expected, actual);
      failures++;
    end
  endtask

  initial begin : main
    int unsigned p;
    int unsigned i;
    failures = 0;

    // Encoding sanity:
    //   ABS  A1 = 0x0380 | 1 = 0x0381
    //   NEGB A1 = 0x03C0 | 1 = 0x03C1
    if (abs_enc(REG_FILE_A, 4'd1) !== 16'h0381) begin
      $display("TEST_RESULT: FAIL: abs_enc(A1) = %04h, expected 0381",
               abs_enc(REG_FILE_A, 4'd1));
      failures++;
    end
    if (negb_enc(REG_FILE_A, 4'd1) !== 16'h03C1) begin
      $display("TEST_RESULT: FAIL: negb_enc(A1) = %04h, expected 03C1",
               negb_enc(REG_FILE_A, 4'd1));
      failures++;
    end

    // NOP-fill memory.
    for (i = 0; i < 256; i++) begin
      u_mem.mem[i] = 16'h0300;
    end

    p = 0;

    // ============================================================
    // ABS tests — uses A1..A6 as destination registers per spec
    // table page 12-34. Each scenario: MOVI Rd ← X; ABS Rd.
    // ============================================================

    // 1. ABS  0x7FFFFFFF → 0x7FFFFFFF  (positive max stays).
    p = place_movi_il(p, REG_FILE_A, 4'd1, 32'h7FFF_FFFF);
    u_mem.mem[p] = abs_enc(REG_FILE_A, 4'd1); p = p + 1;

    // 2. ABS  0xFFFFFFFF → 0x00000001  (negative -1 → +1).
    p = place_movi_il(p, REG_FILE_A, 4'd2, 32'hFFFF_FFFF);
    u_mem.mem[p] = abs_enc(REG_FILE_A, 4'd2); p = p + 1;

    // 3. ABS  0x80000000 → 0x80000000  (MIN_INT special case; V=1, Rd unchanged).
    p = place_movi_il(p, REG_FILE_A, 4'd3, 32'h8000_0000);
    u_mem.mem[p] = abs_enc(REG_FILE_A, 4'd3); p = p + 1;

    // 4. ABS  0x80000001 → 0x7FFFFFFF  (MIN_INT+1 negation works).
    p = place_movi_il(p, REG_FILE_A, 4'd4, 32'h8000_0001);
    u_mem.mem[p] = abs_enc(REG_FILE_A, 4'd4); p = p + 1;

    // 5. ABS  0x00000000 → 0x00000000  (zero stays; Z=1).
    p = place_movi_il(p, REG_FILE_A, 4'd5, 32'h0000_0000);
    u_mem.mem[p] = abs_enc(REG_FILE_A, 4'd5); p = p + 1;

    // 6. ABS  0xFFFA0011 → 0x0005FFEF  (spec table last row).
    p = place_movi_il(p, REG_FILE_A, 4'd6, 32'hFFFA_0011);
    u_mem.mem[p] = abs_enc(REG_FILE_A, 4'd6); p = p + 1;

    // ============================================================
    // NEGB tests — uses A7..A10 as destination registers.
    //
    // NEGB depends on ST.C. We seed C=0 or C=1 before each NEGB
    // via either MOVI (which clears C) or an overflowing ADD (which
    // sets C=1 from carry-out).
    //
    // Setup pattern:
    //   To NEGB Rd with C=0 :  MOVI Rd ← <value> ; NEGB Rd
    //                          (MOVI clears C)
    //   To NEGB Rd with C=1 :  MOVI <value>, A11
    //                          MOVI 1, A12
    //                          ADD A11, A12  (= -1+1 → 0, C=1)
    //                          NEGB Rd  (Rd's value seeded earlier
    //                                    via MOVI, then preserved
    //                                    across the carry-setup
    //                                    by checking the order)
    //
    // Simpler: just seed C=1 before each NEGB by ADD overflow, then
    // MOVK to set Rd (MOVK doesn't touch ST), then NEGB.
    // ============================================================

    // NEGB scenario A: C=0, Rd=0x55555555 → expected 0xAAAAAAAB, NCZV=1100
    // (spec row 3 in the NEGB table: page 12-168)
    p = place_movi_il(p, REG_FILE_A, 4'd7, 32'h5555_5555);
    // MOVI cleared C, so C=0 going into the NEGB.
    u_mem.mem[p] = negb_enc(REG_FILE_A, 4'd7); p = p + 1;

    // NEGB scenario B: C=1, Rd=0x80000000 → expected 0x7FFFFFFF, NCZV=0100
    // (spec row 8 of the NEGB table: shows NEGB of MIN_INT with C=1
    // gives 7FFFFFFF and NCZV = 0100).
    //   Setup: MOVI A8 = 0x80000000  (clears C); set C=1 via overflow.
    p = place_movi_il(p, REG_FILE_A, 4'd8, 32'h8000_0000);
    p = place_movi_il(p, REG_FILE_A, 4'd13, 32'hFFFF_FFFF);
    p = place_movi_il(p, REG_FILE_A, 4'd14, 32'h0000_0001);
    u_mem.mem[p] = add_rr_enc(4'd13, REG_FILE_A, 4'd14); p = p + 1;
                                                     // ADD A13, A14 → A14=0, C=1
    u_mem.mem[p] = negb_enc(REG_FILE_A, 4'd8); p = p + 1;

    // NEGB scenario C: C=0, Rd=0xFFFFFFFF → expected 0x00000001, NCZV=0100
    // (NEGB of -1 with C=0 → +1). C is cleared by MOVI A9.
    p = place_movi_il(p, REG_FILE_A, 4'd9, 32'hFFFF_FFFF);
    u_mem.mem[p] = negb_enc(REG_FILE_A, 4'd9); p = p + 1;

    // NEGB scenario D: C=1, Rd=0xFFFFFFFF → expected 0x00000000, NCZV=0110
    //   Set C=1 first via overflow, then MOVK A10 = ... wait MOVK only does
    //   5-bit zero-extend. We need a 32-bit Rd. So MOVI clears C.
    //   Instead: seed Rd via MOVI BEFORE the carry-setup, then ADD overflow,
    //   then NEGB.
    p = place_movi_il(p, REG_FILE_A, 4'd10, 32'hFFFF_FFFF);
    // Reuse A13/A14 = 0xFFFFFFFF and 0x00000001 from scenario B's setup;
    // they're still in place. ADD A13, A14 again → A14=0, C=1.
    // BUT wait — A13/A14 were modified in scenario B's ADD. Let me re-seed.
    p = place_movi_il(p, REG_FILE_A, 4'd13, 32'hFFFF_FFFF);
    p = place_movi_il(p, REG_FILE_A, 4'd14, 32'h0000_0001);
    u_mem.mem[p] = add_rr_enc(4'd13, REG_FILE_A, 4'd14); p = p + 1;
                                                     // C=1
    u_mem.mem[p] = negb_enc(REG_FILE_A, 4'd10); p = p + 1;

    // Halt
    u_mem.mem[p] = 16'hC0FF;

    repeat (3) @(posedge clk);
    rst = 1'b0;

    // Lots of MOVI IL (~12 cycles each) and a handful of single-word ops.
    // Maybe 200-300 cycles. Use 1500 for headroom.
    repeat (1500) @(posedge clk);
    #1;

    // ---- ABS register-value checks (spec page 12-34 worked examples) ------
    check_reg("ABS 0x7FFFFFFF → A1 unchanged",
              u_core.u_regfile.a_regs[1], 32'h7FFF_FFFF);
    check_reg("ABS 0xFFFFFFFF → A2 = 0x00000001",
              u_core.u_regfile.a_regs[2], 32'h0000_0001);
    check_reg("ABS 0x80000000 → A3 unchanged (V=1 case)",
              u_core.u_regfile.a_regs[3], 32'h8000_0000);
    check_reg("ABS 0x80000001 → A4 = 0x7FFFFFFF",
              u_core.u_regfile.a_regs[4], 32'h7FFF_FFFF);
    check_reg("ABS 0 → A5 unchanged (zero)",
              u_core.u_regfile.a_regs[5], 32'h0000_0000);
    check_reg("ABS 0xFFFA0011 → A6 = 0x0005FFEF",
              u_core.u_regfile.a_regs[6], 32'h0005_FFEF);

    // ---- NEGB register-value checks ---------------------------------------
    check_reg("NEGB C=0 0x55555555 → A7 = 0xAAAAAAAB",
              u_core.u_regfile.a_regs[7], 32'hAAAA_AAAB);
    check_reg("NEGB C=1 0x80000000 → A8 = 0x7FFFFFFF (spec row 8)",
              u_core.u_regfile.a_regs[8], 32'h7FFF_FFFF);
    check_reg("NEGB C=0 0xFFFFFFFF → A9 = 0x00000001",
              u_core.u_regfile.a_regs[9], 32'h0000_0001);
    check_reg("NEGB C=1 0xFFFFFFFF → A10 = 0x00000000",
              u_core.u_regfile.a_regs[10], 32'h0000_0000);

    // ---- Final ST flags from the LAST NEGB (Scenario D) -------------------
    // NEGB C=1, Rd=0xFFFFFFFF → result=0, NCZV=0110 (Z=1, V=1)
    // Per spec page 12-168 row 12: NEGB AD 0xFFFFFFFF C=1 → NCZV=0110.
    // NCZV = 0,1,1,0 → N=0, C=1, Z=1, V=0.
    // Wait, the spec table shows "0110" for that row. NCZV ordering
    // varies; per the column header "NCZV" the bits are N,C,Z,V.
    // So 0110 = N=0, C=1, Z=1, V=0. ✓
    check_bit("After NEGB scenario D: ST.N = 0",
              u_core.u_status_reg.n_o, 1'b0);
    check_bit("After NEGB scenario D: ST.C = 1",
              u_core.u_status_reg.c_o, 1'b1);
    check_bit("After NEGB scenario D: ST.Z = 1",
              u_core.u_status_reg.z_o, 1'b1);
    check_bit("After NEGB scenario D: ST.V = 0",
              u_core.u_status_reg.v_o, 1'b0);

    // No illegal opcode along the executed path.
    check_bit("illegal_opcode_o stayed 0", illegal_w, 1'b0);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (ABS + NEGB: 6 ABS cases + 4 NEGB cases from SPVU001A spec tables)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #4_000_000;
    $display("TEST_RESULT: FAIL: tb_abs_negb hard timeout");
    $fatal(1);
  end

endmodule : tb_abs_negb
