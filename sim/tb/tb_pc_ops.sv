// -----------------------------------------------------------------------------
// tb_pc_ops.sv
//
// PC / revision register-context ops: GETPC, EXGPC, REV.
// Per SPVU001A summary table page A-16:
//   GETPC Rd  : 0000 0001 010R DDDD  (top11 = 0x00A; base 0x0140)
//   EXGPC Rd  : 0000 0001 001R DDDD  (top11 = 0x009; base 0x0120)
//   REV   Rd  : 0000 0000 001R DDDD  (top11 = 0x001; base 0x0020)
//
// Test scenarios:
//   1. GETPC : capture current PC into A1. Verify A1's value
//      matches the expected PC at that point in the program.
//   2. REV   : read the chip-revision constant into A2. Per A0025
//      and the spec's worked example, the value is 0x00000008.
//   3. EXGPC : atomic swap. Pre-load A3 with a known target
//      bit-address (the word-aligned position of a sentinel-write
//      instruction). After EXGPC: A3 should hold the OLD PC; the
//      CPU should land at the address that was in A3 before; the
//      sentinel-write instruction runs, writing A4.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_pc_ops;
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
  //   GETPC Rd  : 0x0140 | (R<<4) | Rd
  //   EXGPC Rd  : 0x0120 | (R<<4) | Rd
  //   REV Rd    : 0x0020 | (R<<4) | Rd
  // ---------------------------------------------------------------------------
  function automatic instr_word_t getpc_enc(input reg_file_t rf, input reg_idx_t rd);
    getpc_enc = 16'h0140 | (instr_word_t'(rf) << 4) | (instr_word_t'(rd));
  endfunction
  function automatic instr_word_t exgpc_enc(input reg_file_t rf, input reg_idx_t rd);
    exgpc_enc = 16'h0120 | (instr_word_t'(rf) << 4) | (instr_word_t'(rd));
  endfunction
  function automatic instr_word_t rev_enc(input reg_file_t rf, input reg_idx_t rd);
    rev_enc = 16'h0020 | (instr_word_t'(rf) << 4) | (instr_word_t'(rd));
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

  initial begin : main
    int unsigned p;
    int unsigned i;
    int unsigned getpc_word_index;
    int unsigned exgpc_target_word;
    failures = 0;

    // Encoding sanity:
    //   GETPC A1 = 0x0140 | 1 = 0x0141
    //   EXGPC A3 = 0x0120 | 3 = 0x0123
    //   REV   A2 = 0x0020 | 2 = 0x0022
    if (getpc_enc(REG_FILE_A, 4'd1) !== 16'h0141) begin
      $display("TEST_RESULT: FAIL: getpc_enc(A1) = %04h, expected 0141",
               getpc_enc(REG_FILE_A, 4'd1));
      failures++;
    end
    if (exgpc_enc(REG_FILE_A, 4'd3) !== 16'h0123) begin
      $display("TEST_RESULT: FAIL: exgpc_enc(A3) = %04h, expected 0123",
               exgpc_enc(REG_FILE_A, 4'd3));
      failures++;
    end
    if (rev_enc(REG_FILE_A, 4'd2) !== 16'h0022) begin
      $display("TEST_RESULT: FAIL: rev_enc(A2) = %04h, expected 0022",
               rev_enc(REG_FILE_A, 4'd2));
      failures++;
    end

    // Pre-fill memory with NOP.
    for (i = 0; i < 256; i++) begin
      u_mem.mem[i] = 16'h0300;
    end

    p = 0;

    // ---- Scenario 1: GETPC A1 ---------------------------------------------
    //   Place GETPC at a known word index. After execution, A1 should
    //   equal the bit-address PC at WRITEBACK. pc_value at WRITEBACK
    //   is (W+1)*16 — after the single-word opcode fetch's PC advance.
    getpc_word_index = p;
    u_mem.mem[p] = getpc_enc(REG_FILE_A, 4'd1); p = p + 1;
    // expected_A1 = (getpc_word_index + 1) * 16 bits.

    // ---- Scenario 2: REV A2 -----------------------------------------------
    //   After REV: A2 = 0x00000008 (A0025).
    u_mem.mem[p] = rev_enc(REG_FILE_A, 4'd2); p = p + 1;

    // ---- Scenario 3: EXGPC A3 ---------------------------------------------
    //   Pre-load A3 with the bit-address of word index 100. The
    //   EXGPC swaps PC ↔ A3. After EXGPC:
    //     A3 ← old PC (= (exgpc_word_index + 1) * 16)
    //     PC ← old A3 (= 100 * 16 = 1600 = 0x640) with bottom 4 bits cleared
    //   We pre-place a "landing-site" instruction at word 100 that
    //   writes A4 with a marker, so we can verify EXGPC took us
    //   there. After the landing-site MOVI, place a HALT.
    exgpc_target_word = 100;
    p = place_movi_il(p, REG_FILE_A, 4'd3, 32'(exgpc_target_word * 16));
    u_mem.mem[p] = exgpc_enc(REG_FILE_A, 4'd3); p = p + 1;
    // EXGPC at this word; pc_value at WB = (p) * 16 ... actually p
    // got incremented; so the EXGPC's word index was (p-1). At WB,
    // pc_value = p * 16. Save that as expected_A3.

    // Pre-place a "should never run" sentinel at the words right after
    // EXGPC, in case the swap fails: write A4 ← 0xBAD.
    p = place_movi_il(p, REG_FILE_A, 4'd4, 32'h0000_0BAD);

    // Pre-place the actual landing site at word 100:
    u_mem.mem[100] = movi_il_enc(REG_FILE_A, 4'd4);
    u_mem.mem[101] = 16'hFACE;
    u_mem.mem[102] = 16'hCAFE;
    // After landing MOVI: A4 = 0xCAFE_FACE.
    // Then a halt at word 103.
    u_mem.mem[103] = 16'hC0FF;

    repeat (3) @(posedge clk);
    rst = 1'b0;

    repeat (1500) @(posedge clk);
    #1;

    // ---- Checks ------------------------------------------------------------
    // GETPC: A1 = (getpc_word_index + 1) * 16 (PC after the single
    // opcode fetch advanced through GETPC).
    check_reg("GETPC: A1 = pc_value at WRITEBACK",
              u_core.u_regfile.a_regs[1],
              32'((getpc_word_index + 1) * 16));

    // REV: A2 = 0x00000008 (A0025).
    check_reg("REV: A2 = 0x00000008",
              u_core.u_regfile.a_regs[2], 32'h0000_0008);

    // EXGPC: A4 should hold 0xCAFE_FACE (landing MOVI at word 100 ran).
    check_reg("EXGPC: landing site executed → A4 = 0xCAFE_FACE",
              u_core.u_regfile.a_regs[4], 32'hCAFE_FACE);
    // EXGPC: A3 should hold the OLD PC (the pc_value at the EXGPC's
    // WRITEBACK). pc_value = (exgpc_word_index + 1) * 16, where
    // exgpc_word_index is the word slot the EXGPC opcode occupied.
    // That index is (post-EXGPC p value - 1) before the trap-sentinel
    // MOVI was placed. We saved it implicitly; recompute below.
    //   Layout: GETPC at word 0; REV at word 1; MOVI A3 at words 2,3,4;
    //   EXGPC at word 5. PC at WB after EXGPC = 6*16 = 96 = 0x60.
    check_reg("EXGPC: A3 = old PC (pc_value at WRITEBACK)",
              u_core.u_regfile.a_regs[3], 32'h0000_0060);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (GETPC + REV + EXGPC)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_pc_ops hard timeout");
    $fatal(1);
  end

endmodule : tb_pc_ops
