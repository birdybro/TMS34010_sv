// -----------------------------------------------------------------------------
// tb_movi_il.sv
//
// End-to-end test for `MOVI IL K, Rd`.
//
// What it exercises that tb_movi (IW) didn't:
//   - The CORE_FETCH_IMM_HI state and the 32-bit immediate assembly path
//     (`imm32 = {imm_hi_q, imm_lo_q}` with imm_sign_extend=0).
//   - Immediate values that the IW form physically cannot encode, e.g.
//     0xCAFE_BABE and other patterns where the upper 16 bits are not
//     just sign-extension of the lower 16.
//   - Two-word immediate ordering (LO comes first in memory, then HI).
//
// Encoding (A0012): `MOVI IL K, Rd` = `0x09E0 | (R<<4) | N`, followed by
// the 32-bit immediate stored as two 16-bit words: low half first, then
// high half. Flag effects per A0011: N/Z from result, C/V cleared.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_movi_il;
  import tms34010_pkg::*;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  // ---------------------------------------------------------------------------
  // Wiring
  // ---------------------------------------------------------------------------
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
  // Encoding helper. MOVI IL: 0x09E0 | (R<<4) | N
  // ---------------------------------------------------------------------------
  function automatic instr_word_t movi_il_enc(input reg_file_t rf,
                                              input reg_idx_t  idx);
    movi_il_enc = 16'h09E0 | (instr_word_t'(rf) << 4) | (instr_word_t'(idx));
  endfunction

  int unsigned failures;

  task automatic check_reg(input string                label,
                           input logic [DATA_WIDTH-1:0] actual,
                           input logic [DATA_WIDTH-1:0] expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%08h actual=%08h",
               label, expected, actual);
      failures++;
    end
  endtask

  // Preload a single `MOVI IL imm, Rd` at the given memory-word offset.
  // The immediate occupies two 16-bit words: low half at offset+1, high
  // half at offset+2.
  task automatic place_movi_il(input int unsigned         word_offset,
                               input reg_file_t           rf,
                               input reg_idx_t            idx,
                               input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[word_offset]     = movi_il_enc(rf, idx);
    u_mem.mem[word_offset + 1] = imm[15:0];
    u_mem.mem[word_offset + 2] = imm[31:16];
  endtask

  // ---------------------------------------------------------------------------
  // Test body
  // ---------------------------------------------------------------------------
  initial begin : main
    failures = 0;

    // Five MOVI IL instructions covering patterns that distinguish IL
    // from IW:
    //   Offset 0:  MOVI IL 0xCAFE_BABE, A1   ← classic 32-bit pattern
    //   Offset 3:  MOVI IL 0xDEAD_BEEF, A6   ← bit[31]=1, low half doesn't sign-extend
    //   Offset 6:  MOVI IL 0x0000_FFFF, B0   ← positive 32-bit > 16-bit range
    //   Offset 9:  MOVI IL 0xFFFF_0000, B11  ← high bits set but low bits 0
    //   Offset 12: MOVI IL 0x0000_0000, A8   ← Z=1
    place_movi_il( 0, REG_FILE_A, 4'd1,  32'hCAFE_BABE);
    place_movi_il( 3, REG_FILE_A, 4'd6,  32'hDEAD_BEEF);
    place_movi_il( 6, REG_FILE_B, 4'd0,  32'h0000_FFFF);
    place_movi_il( 9, REG_FILE_B, 4'd11, 32'hFFFF_0000);
    place_movi_il(12, REG_FILE_A, 4'd8,  32'h0000_0000);

    // Reset.
    repeat (3) @(posedge clk);
    rst = 1'b0;

    // Each MOVI IL is ~9 cycles (FETCH + DECODE + IMM_LO + IMM_HI +
    // EXECUTE + WRITEBACK plus memory ack waits). Five = ~45 cycles.
    // Use 100 for headroom.
    repeat (100) @(posedge clk);
    #1;

    check_reg("A1  = 0xCAFEBABE", u_core.u_regfile.a_regs[1],  32'hCAFE_BABE);
    check_reg("A6  = 0xDEADBEEF", u_core.u_regfile.a_regs[6],  32'hDEAD_BEEF);
    check_reg("B0  = 0x0000FFFF", u_core.u_regfile.b_regs[0],  32'h0000_FFFF);
    check_reg("B11 = 0xFFFF0000", u_core.u_regfile.b_regs[11], 32'hFFFF_0000);
    check_reg("A8  = 0x00000000", u_core.u_regfile.a_regs[8],  32'h0000_0000);

    // PC: 5 instructions × 3 words × 16 bits = 240 bits = 0xF0 minimum.
    if (pc_w < ADDR_WIDTH'(32'hF0)) begin
      $display("TEST_RESULT: FAIL: PC=%08h did not advance past valid program end (0xF0)",
               pc_w);
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (5 MOVI IL writes verified; A1=%08h A6=%08h B0=%08h B11=%08h A8=%08h)",
               u_core.u_regfile.a_regs[1],  u_core.u_regfile.a_regs[6],
               u_core.u_regfile.b_regs[0],  u_core.u_regfile.b_regs[11],
               u_core.u_regfile.a_regs[8]);
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #200_000;
    $display("TEST_RESULT: FAIL: tb_movi_il hard timeout");
    $fatal(1);
  end

endmodule : tb_movi_il
