// -----------------------------------------------------------------------------
// tb_call_rs.sv
//
// CALL Rs — Call Subroutine Indirect. Per SPVU001A page 12-47 +
// summary table line 27018. Encoding `0000 1001 001R DDDD`:
//   top11 = 11'b00001001_001 = 0x049
//   bit[4] = R (file of Rs)
//   bits[3:0] = Rs index
//
// Execution:
//   SP -= 32
//   mem[new SP] = PC'   (PC' = address of next instruction word)
//   PC = Rs              (with bottom 4 bits forced to 0)
//
// Status bits all "Unaffected".
//
// Test plan:
//   1. Initialize SP = 0x0000_0800.
//   2. Load A5 with the bit-address of word 100 (= 100*16 = 0x640) —
//      this is the subroutine entry.
//   3. At word 100 in memory, place a MOVI A6 = 0xCAFE_BABE (the
//      subroutine body), followed by a halt at word 103.
//   4. Place CALL A5 at a known offset.
//   5. Run.
//   6. Verify:
//        - A6 = 0xCAFE_BABE  (proves CALL transferred control to A5)
//        - SP = 0x0000_0800 - 32 = 0x0000_07E0
//        - mem[126..127] contains PC' (= the bit-address right after
//          the CALL opcode).
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_call_rs;
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
  //   CALL Rs : 0x0920 | (R<<4) | Rs   (top11 = 0x049 → base = 0x49<<5 = 0x0920)
  // ---------------------------------------------------------------------------
  function automatic instr_word_t call_rs_enc(input reg_file_t rf, input reg_idx_t rs);
    call_rs_enc = 16'h0920 | (instr_word_t'(rf) << 4) | instr_word_t'(rs);
  endfunction
  function automatic instr_word_t movi_il_enc(input reg_idx_t i);
    movi_il_enc = 16'h09E0 | instr_word_t'(i);
  endfunction
  function automatic int unsigned place_movi_il(input int unsigned p,
                                                input reg_idx_t    i,
                                                input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]     = movi_il_enc(i);
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

  localparam logic [DATA_WIDTH-1:0] SP_INIT   = 32'h0000_0800;
  localparam int unsigned           SUB_WORD  = 100;          // word index of sub entry
  localparam logic [DATA_WIDTH-1:0] SUB_ADDR  = SUB_WORD * 16;  // bit-address of sub entry

  initial begin : main
    int unsigned p;
    int unsigned i;
    int unsigned call_opcode_word;
    logic [DATA_WIDTH-1:0] expected_pc_prime;
    failures = 0;

    // Encoding sanity:
    //   CALL A5 (F=A, Rs=5) = 0x0920 | 0 | 5 = 0x0925.
    //   CALL B5 (F=B, Rs=5) = 0x0920 | 0x10 | 5 = 0x0935.
    if (call_rs_enc(REG_FILE_A, 4'd5) !== 16'h0925) begin
      $display("TEST_RESULT: FAIL: call_rs_enc(A5) = %04h, expected 0925",
               call_rs_enc(REG_FILE_A, 4'd5));
      failures++;
    end
    if (call_rs_enc(REG_FILE_B, 4'd5) !== 16'h0935) begin
      $display("TEST_RESULT: FAIL: call_rs_enc(B5) = %04h, expected 0935",
               call_rs_enc(REG_FILE_B, 4'd5));
      failures++;
    end

    // NOP-fill memory.
    for (i = 0; i < 256; i++) begin
      u_mem.mem[i] = 16'h0300;
    end

    p = 0;

    // ---- Prelude: set SP = SP_INIT (via MOVE A0,A15) and A5 = SUB_ADDR.
    p = place_movi_il(p, 4'd0, SP_INIT);
    u_mem.mem[p] = 16'h900F; p = p + 1;       // MOVE A0, A15 (= SP)
    p = place_movi_il(p, 4'd5, SUB_ADDR);

    // ---- CALL A5 -------------------------------------------------------
    call_opcode_word = p;
    u_mem.mem[p] = call_rs_enc(REG_FILE_A, 4'd5); p = p + 1;

    // ---- Trap MOVI right after CALL — should NOT run (control transfers
    //      to the subroutine). If it does, A6 will get 0xBAD instead of
    //      the subroutine's 0xCAFE_BABE.
    p = place_movi_il(p, 4'd6, 32'h0000_0BAD);

    // Place a halt where execution would land if it didn't return,
    // protecting us from runaway execution.
    u_mem.mem[p] = 16'hC0FF; p = p + 1;

    // ---- Subroutine body at SUB_WORD = 100 -----------------------------
    u_mem.mem[100] = movi_il_enc(4'd6);
    u_mem.mem[101] = 16'hBABE;
    u_mem.mem[102] = 16'hCAFE;
    // After the subroutine writes A6 = 0xCAFEBABE, halt.
    u_mem.mem[103] = 16'hC0FF;

    repeat (3) @(posedge clk);
    rst = 1'b0;

    repeat (2000) @(posedge clk);
    #1;

    // ---- Checks --------------------------------------------------------
    // A6 should hold 0xCAFEBABE — proves the subroutine ran (PC was
    // loaded from A5).
    check_reg("CALL: subroutine ran → A6 = 0xCAFEBABE",
              u_core.u_regfile.a_regs[6], 32'hCAFE_BABE);

    // SP should equal SP_INIT - 32.
    check_reg("CALL: SP decremented by 32",
              u_core.u_regfile.sp_q, SP_INIT - 32);

    // Memory at the new SP (word 126, 127) should hold PC' — the
    // bit-address of the instruction immediately following the CALL
    // opcode. The CALL opcode word index is `call_opcode_word`; PC'
    // = (call_opcode_word + 1) * 16.
    expected_pc_prime = 32'((call_opcode_word + 1) * 16);
    if (u_mem.mem[126] !== expected_pc_prime[15:0]) begin
      $display("TEST_RESULT: FAIL: mem[126] (PC' low): expected=%04h actual=%04h",
               expected_pc_prime[15:0], u_mem.mem[126]);
      failures++;
    end
    if (u_mem.mem[127] !== expected_pc_prime[31:16]) begin
      $display("TEST_RESULT: FAIL: mem[127] (PC' high): expected=%04h actual=%04h",
               expected_pc_prime[31:16], u_mem.mem[127]);
      failures++;
    end

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (CALL Rs: subroutine entered, SP -= 32, return PC' pushed)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_call_rs hard timeout");
    $fatal(1);
  end

endmodule : tb_call_rs
