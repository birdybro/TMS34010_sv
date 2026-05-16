// -----------------------------------------------------------------------------
// tb_calla_callr.sv
//
// CALLA Address (Call Subroutine Absolute) and CALLR Address (Call
// Subroutine Relative). Per SPVU001A pages 12-48 and 12-49.
//
//   CALLA : 0x0D5F (single fixed) + 32-bit absolute target.
//           PC' pushed; new PC = address (low 4 bits cleared).
//   CALLR : 0x0D3F (single fixed) + 16-bit signed disp.
//           PC' pushed; new PC = PC' + sign_ext(disp16) * 16.
//
// Both: status bits Unaffected. PC' (the return address) is the
// address of the instruction immediately after the CALL's full
// encoding (3 words for CALLA, 2 words for CALLR).
//
// Two scenarios, each a full call → subroutine → RETS round-trip:
//
//   Scenario A (CALLA):
//     1. SP = 0x0000_0800, A7 sentinel.
//     2. CALLA 0x0000_0640 → subroutine at word 100.
//     3. Subroutine writes A6 = 0xAAAA_CCCC, then RETS.
//     4. Post-CALLA MOVI writes A7 = 0x0000_BEEF.
//     5. Verify A6, A7, SP back at 0x0800.
//
//   Scenario B (CALLR):
//     Re-init SP, then CALLR with a positive offset that lands at
//     another pre-placed subroutine. Verify analogous quantities.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_calla_callr;
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

  sim_memory_model #(.DEPTH_WORDS(512)) u_mem (
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

  function automatic instr_word_t movi_il_enc(input reg_idx_t i);
    movi_il_enc = 16'h09E0 | instr_word_t'(i);
  endfunction
  function automatic instr_word_t rets_enc();
    rets_enc = 16'h0960;
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
    int unsigned callr_word_index;
    logic signed [15:0] callr_disp;
    int unsigned callr_target_word;
    failures = 0;

    // NOP-fill memory.
    for (i = 0; i < 512; i++) begin
      u_mem.mem[i] = 16'h0300;
    end

    p = 0;

    // ============================================================
    // Prelude: SP = 0x0000_0800; A7 sentinel = 0xAAAA_AAAA.
    // ============================================================
    p = place_movi_il(p, 4'd0, 32'h0000_0800);
    u_mem.mem[p] = 16'h900F; p = p + 1;             // MOVE A0, A15
    p = place_movi_il(p, 4'd7, 32'hAAAA_AAAA);

    // ============================================================
    // Scenario A: CALLA 0x0000_0640
    //   CALLA opcode at index p; LO at p+1; HI at p+2.
    //   Post-CALLA MOVI starts at p+3.
    // ============================================================
    u_mem.mem[p] = 16'h0D5F;             p = p + 1;   // CALLA
    u_mem.mem[p] = 16'h0640;             p = p + 1;   // LO of target
    u_mem.mem[p] = 16'h0000;             p = p + 1;   // HI of target
    // Post-CALLA MOVI: writes A7 = 0x0000_BEEF (proves return landed).
    p = place_movi_il(p, 4'd7, 32'h0000_BEEF);

    // ============================================================
    // Scenario B: CALLR with a positive disp.
    //   PC' at CALLR's CORE_WRITEBACK = (CALLR_word + 2)*16.
    //   We pick a target far enough away. Subroutine at word 200.
    //   Word(target) = PC'/16 + disp = (CALLR_word + 2) + disp = 200
    //   → disp = 200 - CALLR_word - 2.
    // ============================================================
    callr_word_index = p;
    u_mem.mem[p] = 16'h0D3F;             p = p + 1;   // CALLR opcode
    callr_target_word = 200;
    callr_disp = 16'(callr_target_word - callr_word_index - 2);
    u_mem.mem[p] = instr_word_t'(callr_disp);  p = p + 1;
    // Post-CALLR MOVI: writes A8 = 0x0000_F00D.
    p = place_movi_il(p, 4'd8, 32'h0000_F00D);

    // Halt
    u_mem.mem[p] = 16'hC0FF;

    // ============================================================
    // Subroutine A at word 100:  MOVI A6 = 0xAAAA_CCCC; RETS.
    // ============================================================
    u_mem.mem[100] = movi_il_enc(4'd6);
    u_mem.mem[101] = 16'hCCCC;
    u_mem.mem[102] = 16'hAAAA;
    u_mem.mem[103] = rets_enc();

    // ============================================================
    // Subroutine B at word 200:  MOVI A9 = 0xDEAD_FACE; RETS.
    // ============================================================
    u_mem.mem[200] = movi_il_enc(4'd9);
    u_mem.mem[201] = 16'hFACE;
    u_mem.mem[202] = 16'hDEAD;
    u_mem.mem[203] = rets_enc();

    repeat (3) @(posedge clk);
    rst = 1'b0;

    // Lots of work — multiple CALLA/CALLR transitions and round trips.
    repeat (4000) @(posedge clk);
    #1;

    // ---- Scenario A checks (CALLA) -------------------------------
    check_reg("CALLA: subroutine A wrote A6",
              u_core.u_regfile.a_regs[6], 32'hAAAA_CCCC);
    check_reg("CALLA: post-CALLA MOVI ran → A7 = 0xBEEF",
              u_core.u_regfile.a_regs[7], 32'h0000_BEEF);

    // ---- Scenario B checks (CALLR) -------------------------------
    check_reg("CALLR: subroutine B wrote A9",
              u_core.u_regfile.a_regs[9], 32'hDEAD_FACE);
    check_reg("CALLR: post-CALLR MOVI ran → A8 = 0xF00D",
              u_core.u_regfile.a_regs[8], 32'h0000_F00D);

    // ---- SP check (both round-trips popped back) ----------------
    check_reg("SP back at 0x0000_0800 after both CALL/RETS",
              u_core.u_regfile.sp_q, 32'h0000_0800);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (CALLA + CALLR: both round-trips via RETS; SP restored)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #4_000_000;
    $display("TEST_RESULT: FAIL: tb_calla_callr hard timeout");
    $fatal(1);
  end

endmodule : tb_calla_callr
