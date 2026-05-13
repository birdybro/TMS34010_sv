// -----------------------------------------------------------------------------
// tb_jump_rs.sv
//
// Register-indirect jump: `JUMP Rs` per SPVU001A page 12-98.
//
// Encoding: `0000 0001 011R DDDD`  (top11 = 11'b00000001_011 = 0x00B).
// Semantics: PC ← (Rs & ~0xF) — load PC from Rs with the bottom 4
// bits cleared (word alignment).
//
// Test strategy:
//   1. Pre-fill memory with NOP so unintended execution decodes as
//      valid no-op.
//   2. Place a fall-through "should never run" MOVI that would
//      overwrite a sentinel register if executed.
//   3. Place an unconditional JUMP A1 instruction (Rs = A1).
//   4. Pre-load A1 with the address of a far-away landing site.
//   5. At the landing site, place a MOVI that writes a known value
//      to a different register so we can confirm the jump took.
//
// We also verify the bottom-4-bits-cleared masking by setting A1 to
// a value with non-zero low nibble (e.g., A1 = target | 0xF) and
// confirming the landing site (at the aligned address) still executes.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_jump_rs;
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
  //   JUMP Rs = top11 = 11'b00000001_011, low 5 bits = {R, Rs idx}
  //           = 16'h00B0 base (top11 << 5), then | (R<<4) | Rs.
  //   Actually: top11 occupies bits[15:5], so the base value is
  //   {top11, 5'b00000} = {11'b00000001011, 5'b0} = 16'b00000001_01100000 = 0x0160.
  // ---------------------------------------------------------------------------
  function automatic instr_word_t jump_rs_enc(input reg_file_t rf, input reg_idx_t rs_idx);
    jump_rs_enc = 16'h0160 | (instr_word_t'(rf) << 4) | (instr_word_t'(rs_idx));
  endfunction

  function automatic instr_word_t movi_il_enc(input reg_file_t rf, input reg_idx_t i);
    movi_il_enc = 16'h09E0 | (instr_word_t'(rf) << 4) | (instr_word_t'(i));
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

  localparam logic [DATA_WIDTH-1:0] UNTOUCHED = 32'h0000_C357;
  localparam logic [DATA_WIDTH-1:0] FALL_VAL  = 32'h0000_F00D;
  localparam logic [DATA_WIDTH-1:0] LAND_VAL  = 32'h0000_BEEF;

  initial begin : main
    int unsigned p;
    int unsigned i;
    logic [ADDR_WIDTH-1:0] target_bit_addr;
    logic [ADDR_WIDTH-1:0] target_bit_addr_messy;
    failures = 0;

    // Encoding sanity:
    //   JUMP A1 → 0x0160 | 0x01 = 0x0161
    //   JUMP B7 → 0x0160 | 0x17 = 0x0177
    if (jump_rs_enc(REG_FILE_A, 4'd1) !== 16'h0161) begin
      $display("TEST_RESULT: FAIL: JUMP A1 enc = %04h, expected 0161",
               jump_rs_enc(REG_FILE_A, 4'd1));
      failures++;
    end
    if (jump_rs_enc(REG_FILE_B, 4'd7) !== 16'h0177) begin
      $display("TEST_RESULT: FAIL: JUMP B7 enc = %04h, expected 0177",
               jump_rs_enc(REG_FILE_B, 4'd7));
      failures++;
    end

    // Pre-fill memory with NOP.
    for (i = 0; i < 256; i++) begin
      u_mem.mem[i] = 16'h0300;
    end

    // ---- Pre-init A3 (sentinel for fall-through) ----------------------------
    p = 0;
    p = place_movi_il(p, REG_FILE_A, 4'd3, UNTOUCHED);

    // ---- Scenario 1: JUMP A1 to an aligned target ---------------------------
    // Place a landing site at word index 100 in memory. The landing
    // site writes A4 ← LAND_VAL.
    //
    // Word index 100 → byte address 100*2 = 200 → bit address 200*8 = 1600.
    // But sim_memory_model uses mem_addr[IDX_WIDTH+3:4] for indexing, which
    // means mem_addr (a bit-address) divided by 16 picks the word index.
    // So word index W corresponds to bit-address W*16.
    //
    // Landing word index 100 → bit-address 100 * 16 = 1600 = 0x640.
    target_bit_addr = 32'h0000_0640;
    u_mem.mem[100] = movi_il_enc(REG_FILE_A, 4'd4);
    u_mem.mem[101] = LAND_VAL[15:0];
    u_mem.mem[102] = LAND_VAL[31:16];

    // Pre-load A1 with the landing address.
    p = place_movi_il(p, REG_FILE_A, 4'd1, target_bit_addr);

    // Issue the JUMP A1.
    u_mem.mem[p] = jump_rs_enc(REG_FILE_A, 4'd1); p = p + 1;

    // Fall-through that should NOT execute: writes A3 ← FALL_VAL.
    // If the jump fails, the FSM will execute this and trash A3.
    p = place_movi_il(p, REG_FILE_A, 4'd3, FALL_VAL);

    // ---- Scenario 2 (chained from landing): JUMP B2 with messy LSBs --------
    // After scenario 1 lands at word 100 (which writes A4 = LAND_VAL),
    // execution continues to word 103 onward. Place a JUMP B2 there
    // that targets word 150, but pre-load B2 with target_bit_addr_150
    // OR'd with 0xF in the bottom nibble. The JUMP should still land
    // at word 150 because of the alignment-mask in the core's PC-load.
    target_bit_addr_messy = (32'd150 * 32'd16) | 32'h0000_000F;
    u_mem.mem[150] = movi_il_enc(REG_FILE_A, 4'd5);
    u_mem.mem[151] = 32'hCAFE_BABE & 32'h0000_FFFF;
    u_mem.mem[152] = 32'hCAFE_BABE >> 16;

    // Words 103-105 = MOVI IL B2 ← target_bit_addr_messy.
    u_mem.mem[103] = movi_il_enc(REG_FILE_B, 4'd2);
    u_mem.mem[104] = target_bit_addr_messy[15:0];
    u_mem.mem[105] = target_bit_addr_messy[31:16];
    // Word 106 = JUMP B2.
    u_mem.mem[106] = jump_rs_enc(REG_FILE_B, 4'd2);
    // Words 107-109 = trap fall-through (writes A3 ← FALL_VAL).
    u_mem.mem[107] = movi_il_enc(REG_FILE_A, 4'd3);
    u_mem.mem[108] = FALL_VAL[15:0];
    u_mem.mem[109] = FALL_VAL[31:16];

    // ---- Run ---------------------------------------------------------------
    repeat (3) @(posedge clk);
    rst = 1'b0;

    // Generous run length: pre-init (3 words) + load A1 (3) + JUMP (1) + skip
    // to word 100 + landing MOVI (3) + word 103 onward (load B2 = 3, JUMP =
    // 1, fall-through = 3) + skip to word 150 + landing MOVI (3) + many
    // NOPs. Probably ~120 instructions × ~7 cycles = 840 cycles. Use 2000.
    repeat (2000) @(posedge clk);
    #1;

    // ---- Checks ------------------------------------------------------------
    // Scenario 1: JUMP A1 took → A4 holds LAND_VAL.
    check_reg("JUMP A1 → landing wrote A4",
              u_core.u_regfile.a_regs[4], LAND_VAL);

    // Scenario 2: JUMP B2 took with messy LSBs → A5 holds 0xCAFEBABE.
    check_reg("JUMP B2 (messy LSBs) → landing wrote A5",
              u_core.u_regfile.a_regs[5], 32'hCAFE_BABE);

    // A3 must still hold UNTOUCHED — proves neither fall-through MOVI
    // executed.
    check_reg("A3 sentinel untouched (no fall-through executed)",
              u_core.u_regfile.a_regs[3], UNTOUCHED);

    // No illegal opcode along the executed path.
    check_bit("illegal_opcode_o stayed 0", illegal_w, 1'b0);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (JUMP Rs: A-file aligned target, B-file with bottom-nibble mask)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_jump_rs hard timeout");
    $fatal(1);
  end

endmodule : tb_jump_rs
