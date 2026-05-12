// -----------------------------------------------------------------------------
// tb_jrcc_unsigned.sv
//
// Conditional branches with unsigned-compare condition codes (added in
// Task 0027): LO (lower than), LS (lower or same), HI (higher than),
// HS (higher or same). All four are well-defined across the field:
//
//   LO  (cc=0001): C = 1                  (Rd < Rs unsigned, after CMP/SUB)
//   LS  (cc=0010): C | Z = 1               (Rd <= Rs unsigned)
//   HI  (cc=0011): !C & !Z = 1              (Rd > Rs unsigned)
//   HS  (cc=1001): C = 0                   (Rd >= Rs unsigned; alias "NC")
//
// Test pattern per scenario:
//   1. MOVI <a>, A1
//   2. MOVI <b>, A2
//   3. CMP A2, A1      ; flags from A1 - A2 = a - b
//   4. JRcc <test>, +3 ; should take if condition matches
//   5. (fall-through 3 words to be skipped)
//   6. (landing site that sets dest register)
//
// We verify "branch took" by checking that the landing register holds
// the landing-site value rather than the fall-through value.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_jrcc_unsigned;
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

  function automatic instr_word_t movi_il_enc(input reg_file_t rf, input reg_idx_t i);
    movi_il_enc = 16'h09E0 | (instr_word_t'(rf) << 4) | (instr_word_t'(i));
  endfunction
  function automatic instr_word_t cmp_rr_enc(input reg_file_t rf,
                                             input reg_idx_t rs, input reg_idx_t rd);
    cmp_rr_enc = 16'h4800
               | (instr_word_t'(rs) << 5)
               | (instr_word_t'(rf) << 4)
               | (instr_word_t'(rd));
  endfunction
  function automatic instr_word_t jrcc_short_enc(input logic [3:0] cc,
                                                 input logic signed [7:0] disp);
    jrcc_short_enc = 16'hC000
                   | (instr_word_t'(cc) << 8)
                   | {8'h00, disp};
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

  // Place a "compare + JRcc + sentinel-set + landing" scenario.
  //
  // The `sentinel_rd` register is intended to be PRE-INITIALIZED to a known
  // "untouched" value by the caller. Inside the scenario:
  //   - The fall-through MOVI writes `fall_through_val` to sentinel_rd.
  //   - The landing site does NOT touch sentinel_rd; it just writes a
  //     known "landed-marker" value (LM) to ra_dst so the FSM has something
  //     to do post-branch.
  //
  // After the scenario:
  //   - sentinel_rd == untouched value  →  branch TOOK (fall-through skipped)
  //   - sentinel_rd == fall_through_val →  branch DID NOT take (fall-through ran)
  task automatic place_scenario(ref int unsigned p,
                                input reg_idx_t              ra_dst,
                                input reg_idx_t              rb_src,
                                input logic [DATA_WIDTH-1:0] a_value,
                                input logic [DATA_WIDTH-1:0] b_value,
                                input logic [3:0]            cc,
                                input reg_idx_t              sentinel_rd,
                                input logic [DATA_WIDTH-1:0] fall_through_val);
    p = place_movi_il(p, REG_FILE_A, ra_dst, a_value);                       // 3 words
    p = place_movi_il(p, REG_FILE_A, rb_src, b_value);                       // 3 words
    u_mem.mem[p] = cmp_rr_enc(REG_FILE_A, rb_src, ra_dst); p = p + 1;
    u_mem.mem[p] = jrcc_short_enc(cc, 8'sd3);              p = p + 1;        // disp = 3 words
    p = place_movi_il(p, REG_FILE_A, sentinel_rd, fall_through_val);         // 3 words: fall-through
    // landing site: write a benign value to ra_dst (which we don't check).
    p = place_movi_il(p, REG_FILE_A, ra_dst, 32'h0000_0001);                 // 3 words: landing
  endtask

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
    failures = 0;

    // Scenario design — each compare CMP A_Rs, A_Rd does Rd - Rs:
    //   Rd > Rs (unsigned):  C=0, Z=0          → HI takes, HS takes, LS/LO don't
    //   Rd = Rs:             C=0, Z=1          → EQ/LS/HS take, NE/LO/HI don't
    //   Rd < Rs (unsigned):  C=1, Z=0          → LO/LS take, HI/HS don't
    //
    // Six scenarios, each with its own sentinel register (A3..A8).
    // Sentinels are pre-initialized to 0xUNTOUCHED, then the scenario
    // either keeps that value (branch took) or overwrites it with
    // FALL_THROUGH (branch did NOT take).
    //
    //   1. JRLO taken     (a=3, b=10  → C=1)   — A3 sentinel
    //   2. JRLO not taken (a=10, b=3  → C=0)   — A4 sentinel
    //   3. JRHI taken     (a=10, b=3  → !C&!Z) — A5 sentinel
    //   4. JRLS taken     (a=5, b=5   → Z=1)   — A6 sentinel
    //   5. JRHS taken     (a=10, b=10 → !C)    — A7 sentinel
    //   6. JRHS not taken (a=3, b=10  → C=1)   — A8 sentinel

    // Pre-initialize sentinels to a recognizable "untouched" marker.
    p = 0;
    p = place_movi_il(p, REG_FILE_A, 4'd3, 32'h0000_C357);
    p = place_movi_il(p, REG_FILE_A, 4'd4, 32'h0000_C357);
    p = place_movi_il(p, REG_FILE_A, 4'd5, 32'h0000_C357);
    p = place_movi_il(p, REG_FILE_A, 4'd6, 32'h0000_C357);
    p = place_movi_il(p, REG_FILE_A, 4'd7, 32'h0000_C357);
    p = place_movi_il(p, REG_FILE_A, 4'd8, 32'h0000_C357);

    place_scenario(p, 4'd1, 4'd2, 32'd3,  32'd10, CC_LO, 4'd3, 32'h0000_BEEF);
    place_scenario(p, 4'd1, 4'd2, 32'd10, 32'd3,  CC_LO, 4'd4, 32'h0000_F00D);
    place_scenario(p, 4'd1, 4'd2, 32'd10, 32'd3,  CC_HI, 4'd5, 32'h0000_5555);
    place_scenario(p, 4'd1, 4'd2, 32'd5,  32'd5,  CC_LS, 4'd6, 32'h0000_2222);
    place_scenario(p, 4'd1, 4'd2, 32'd10, 32'd10, CC_HS, 4'd7, 32'h0000_4444);
    place_scenario(p, 4'd1, 4'd2, 32'd3,  32'd10, CC_HS, 4'd8, 32'h0000_7788);

    repeat (3) @(posedge clk);
    rst = 1'b0;

    // Each scenario is 11 words; six scenarios = 66 words. Average ~9
    // cycles/word makes 600 cycles. Use 1200 for headroom.
    repeat (1200) @(posedge clk);
    #1;

    // Branch TOOK  → sentinel still at UNTOUCHED (0xC357)
    // Branch SKIPPED → sentinel overwritten with FALL_THROUGH
    check_reg("JRLO taken (3<10 unsigned) → A3 untouched",
              u_core.u_regfile.a_regs[3], 32'h0000_C357);
    check_reg("JRLO NOT taken (10>3) → A4 has fall-through",
              u_core.u_regfile.a_regs[4], 32'h0000_F00D);
    check_reg("JRHI taken (10>3 unsigned) → A5 untouched",
              u_core.u_regfile.a_regs[5], 32'h0000_C357);
    check_reg("JRLS taken (5==5, Z=1) → A6 untouched",
              u_core.u_regfile.a_regs[6], 32'h0000_C357);
    check_reg("JRHS taken (10>=10, !C) → A7 untouched",
              u_core.u_regfile.a_regs[7], 32'h0000_C357);
    check_reg("JRHS NOT taken (3 < 10, C=1) → A8 has fall-through",
              u_core.u_regfile.a_regs[8], 32'h0000_7788);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (6 unsigned-compare branch scenarios verified: LO take/skip, HI take, LS take, HS take/skip)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_jrcc_unsigned hard timeout");
    $fatal(1);
  end

endmodule : tb_jrcc_unsigned
