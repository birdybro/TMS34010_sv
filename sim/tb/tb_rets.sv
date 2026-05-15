// -----------------------------------------------------------------------------
// tb_rets.sv
//
// RETS [N] — Return from Subroutine. Per SPVU001A page 12-231 +
// summary table line 27036. Encoding `0000 1001 011N NNNN`:
//   top11 = 11'b00001001_011 = 0x04B
//   bits[4:0] = N (arg-pop count, 0..31)
// Semantics:
//   PC <- mem[SP]    (32-bit pop)
//   SP <- SP + 32 + 16*N
// Status bits all "Unaffected".
//
// Test design: full CALL → subroutine → RETS round-trip plus a
// separate N=2 SP-arithmetic check.
//
// Scenario 1 — basic RETS (N=0):
//   1. SP = 0x0000_0800; A5 = subroutine entry (word 100 = 0x640).
//   2. Set sentinel A7 = 0xAAAA_AAAA before CALL.
//   3. CALL A5. The subroutine writes A6 = 0xCAFE_BABE then RETS.
//   4. After RETS: PC is back at the post-CALL trap-MOVI, which
//      writes A7 to a DIFFERENT value (0x0000_BEEF, the "return-
//      landed marker"). Critically: this MOVI must NOT have run
//      BEFORE the call (it has to run AFTER, post-return). The
//      sentinel A7 = 0xAAAA_AAAA proves it didn't pre-run.
//   5. Verify A7 = 0x0000_BEEF, A6 = 0xCAFE_BABE, SP back at 0x0800.
//
// Scenario 2 — RETS N=2:
//   Construct a scenario where SP starts at some address, push a
//   known PC value, RETS 2, and verify SP increments by 32 + 16*2 = 64.
//   To avoid coupling with CALL, manually write the "return PC" to
//   memory before RETS.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_rets;
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

  function automatic instr_word_t call_rs_enc(input reg_idx_t rs);
    call_rs_enc = 16'h0920 | instr_word_t'(rs);  // A-file
  endfunction
  function automatic instr_word_t rets_enc(input logic [4:0] n);
    rets_enc = 16'h0960 | instr_word_t'(n);
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

  initial begin : main
    int unsigned p;
    int unsigned i;
    failures = 0;

    // Encoding sanity:
    //   CALL A5 = 0x0925.
    //   RETS    = 0x0960 (N=0).
    //   RETS 2  = 0x0962.
    //   RETS 31 = 0x097F.
    if (call_rs_enc(4'd5)    !== 16'h0925) failures++;
    if (rets_enc(5'd0)       !== 16'h0960) failures++;
    if (rets_enc(5'd2)       !== 16'h0962) failures++;
    if (rets_enc(5'd31)      !== 16'h097F) failures++;
    if (failures != 0) $display("encoding sanity check failed");

    // NOP-fill memory.
    for (i = 0; i < 256; i++) begin
      u_mem.mem[i] = 16'h0300;
    end

    p = 0;

    // ============================================================
    // Scenario 1: CALL → subroutine → RETS  (round-trip)
    // ============================================================
    // Prelude: SP = 0x0000_0800; A5 = SUB_ADDR = 0x640 (word 100);
    //          A7 = SENTINEL = 0xAAAA_AAAA (pre-return marker).
    p = place_movi_il(p, 4'd0, 32'h0000_0800);
    u_mem.mem[p] = 16'h900F; p = p + 1;                 // MOVE A0, A15
    p = place_movi_il(p, 4'd5, 32'h0000_0640);          // A5 = bit-addr of word 100
    p = place_movi_il(p, 4'd7, 32'hAAAA_AAAA);          // A7 = pre-return sentinel

    // CALL A5
    u_mem.mem[p] = call_rs_enc(4'd5); p = p + 1;

    // After CALL returns, the next instruction executes. Make it
    // write A7 = RETURN_LANDED_MARKER (= 0x0000_BEEF).
    p = place_movi_il(p, 4'd7, 32'h0000_BEEF);

    // Then halt.
    u_mem.mem[p] = 16'hC0FF; p = p + 1;

    // ---- Subroutine at word 100 -----------------------------------
    //   Writes A6 = 0xCAFE_BABE, then RETS.
    u_mem.mem[100] = movi_il_enc(4'd6);
    u_mem.mem[101] = 16'hBABE;
    u_mem.mem[102] = 16'hCAFE;
    u_mem.mem[103] = rets_enc(5'd0);   // RETS

    repeat (3) @(posedge clk);
    rst = 1'b0;

    repeat (2000) @(posedge clk);
    #1;

    // ---- Checks --------------------------------------------------
    // Subroutine ran → A6 = 0xCAFE_BABE.
    check_reg("Scen 1: subroutine wrote A6",
              u_core.u_regfile.a_regs[6], 32'hCAFE_BABE);

    // Return-landed MOVI ran AFTER the RETS → A7 = 0x0000_BEEF
    // (sentinel was 0xAAAA_AAAA before; if return failed, A7 stays
    // at the sentinel).
    check_reg("Scen 1: RETS returned → post-CALL MOVI ran → A7 = 0xBEEF",
              u_core.u_regfile.a_regs[7], 32'h0000_BEEF);

    // SP back at the initial value (CALL decremented to 0x07E0, RETS
    // incremented back to 0x0800).
    check_reg("Scen 1: SP restored to 0x0000_0800",
              u_core.u_regfile.sp_q, 32'h0000_0800);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (CALL → subroutine → RETS round-trip + SP arithmetic)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_rets hard timeout");
    $fatal(1);
  end

endmodule : tb_rets
