// -----------------------------------------------------------------------------
// tb_jrcc_signed.sv
//
// Conditional branches with signed-compare condition codes (added in
// Task 0030 once Table 12-8 was re-extracted cleanly from the spec):
//
//   LT  (cc=0100): N ^ V = 1            (Rd < Rs  signed, after CMP/SUB)
//   GE  (cc=0101): N ^ V = 0            (Rd >= Rs signed)
//   LE  (cc=0110): (N ^ V) | Z = 1       (Rd <= Rs signed)
//   GT  (cc=0111): !(N ^ V) & !Z = 1     (Rd > Rs  signed)
//
// Signed-compare semantics: after `CMP Rs, Rd` the ALU computes
// (Rd - Rs); the signed-comparison result is encoded by the (N, V, Z)
// triple. The (N ^ V) bit is 1 iff the signed result is negative —
// i.e., Rd < Rs in the signed sense.
//
// Spec source: SPVU001A Table 12-8 (page 12-31 and reproduced on
// pages 12-95 and 12-96 for the short and long JRcc forms).
//
// Test pattern mirrors `tb_jrcc_unsigned.sv` — sentinel registers
// pre-initialized to a recognizable marker, then a `CMP + JRcc` pair
// where the fall-through MOVI overwrites the sentinel ONLY if the
// branch didn't take.
//
// Two operand "directions" exercise each cc both ways:
//
//   Direction A (Rd > Rs signed):  Rd = 5,  Rs = -5
//     → flags: result=10, N=0, V=0, Z=0
//     → LT skip, GE take, LE skip, GT take
//
//   Direction B (Rd < Rs signed):  Rd = -5, Rs = 5
//     → flags: result=-10, N=1, V=0, Z=0
//     → LT take, GE skip, LE take, GT skip
//
// Direction C (Rd == Rs):           Rd = 5,  Rs = 5
//     → flags: result=0,   N=0, V=0, Z=1
//     → LE take (via Z), GE take (via !(N^V)), GT skip (Z=1)
//
// We pick 8 representative scenarios spanning all 4 cc's with at
// least one take and one skip each.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_jrcc_signed;
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

  // Place a "CMP + JRcc + sentinel-set + landing" scenario.
  //
  // sentinel_rd is intended to be PRE-INITIALIZED to a known "untouched"
  // value by the caller. Inside the scenario:
  //   - The fall-through MOVI writes `fall_through_val` to sentinel_rd.
  //   - The landing site writes a benign value to ra_dst (which we
  //     don't check) so the FSM has something to do post-branch.
  //
  // After the scenario:
  //   - sentinel_rd == untouched value  →  branch TOOK (fall-through skipped)
  //   - sentinel_rd == fall_through_val →  branch DID NOT take
  task automatic place_scenario(ref int unsigned p,
                                input reg_idx_t              ra_dst,
                                input reg_idx_t              rb_src,
                                input logic [DATA_WIDTH-1:0] a_value,
                                input logic [DATA_WIDTH-1:0] b_value,
                                input logic [3:0]            cc,
                                input reg_idx_t              sentinel_rd,
                                input logic [DATA_WIDTH-1:0] fall_through_val);
    p = place_movi_il(p, REG_FILE_A, ra_dst, a_value);                       // 3 words: Rd value
    p = place_movi_il(p, REG_FILE_A, rb_src, b_value);                       // 3 words: Rs value
    u_mem.mem[p] = cmp_rr_enc(REG_FILE_A, rb_src, ra_dst); p = p + 1;        // CMP Rs, Rd
    u_mem.mem[p] = jrcc_short_enc(cc, 8'sd3);              p = p + 1;        // disp = 3 words
    p = place_movi_il(p, REG_FILE_A, sentinel_rd, fall_through_val);         // 3 words: fall-through
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

  localparam logic [DATA_WIDTH-1:0] UNTOUCHED  = 32'h0000_C357;
  localparam logic [DATA_WIDTH-1:0] FT_LT_TAKE = 32'h0000_BEEF;  // not used (branch should TAKE)
  localparam logic [DATA_WIDTH-1:0] FT_LT_SKIP = 32'h0000_F00D;
  localparam logic [DATA_WIDTH-1:0] FT_GE_TAKE = 32'h0000_AAAA;
  localparam logic [DATA_WIDTH-1:0] FT_GE_SKIP = 32'h0000_5555;
  localparam logic [DATA_WIDTH-1:0] FT_LE_TAKE = 32'h0000_1111;
  localparam logic [DATA_WIDTH-1:0] FT_LE_SKIP = 32'h0000_2222;
  localparam logic [DATA_WIDTH-1:0] FT_GT_TAKE = 32'h0000_3333;
  localparam logic [DATA_WIDTH-1:0] FT_GT_SKIP = 32'h0000_4444;

  initial begin : main
    int unsigned p;
    failures = 0;

    // Encoding sanity (signed-compare cc values).
    if (jrcc_short_enc(CC_LT, 8'sd3) !== 16'hC403) begin
      $display("TEST_RESULT: FAIL: JRLT +3 enc = %04h, expected C403",
               jrcc_short_enc(CC_LT, 8'sd3));
      failures++;
    end
    if (jrcc_short_enc(CC_GE, 8'sd3) !== 16'hC503) begin
      $display("TEST_RESULT: FAIL: JRGE +3 enc = %04h, expected C503",
               jrcc_short_enc(CC_GE, 8'sd3));
      failures++;
    end
    if (jrcc_short_enc(CC_LE, 8'sd3) !== 16'hC603) begin
      $display("TEST_RESULT: FAIL: JRLE +3 enc = %04h, expected C603",
               jrcc_short_enc(CC_LE, 8'sd3));
      failures++;
    end
    if (jrcc_short_enc(CC_GT, 8'sd3) !== 16'hC703) begin
      $display("TEST_RESULT: FAIL: JRGT +3 enc = %04h, expected C703",
               jrcc_short_enc(CC_GT, 8'sd3));
      failures++;
    end

    // Pre-initialize sentinels (A3..A10) to UNTOUCHED.
    p = 0;
    p = place_movi_il(p, REG_FILE_A, 4'd3,  UNTOUCHED);
    p = place_movi_il(p, REG_FILE_A, 4'd4,  UNTOUCHED);
    p = place_movi_il(p, REG_FILE_A, 4'd5,  UNTOUCHED);
    p = place_movi_il(p, REG_FILE_A, 4'd6,  UNTOUCHED);
    p = place_movi_il(p, REG_FILE_A, 4'd7,  UNTOUCHED);
    p = place_movi_il(p, REG_FILE_A, 4'd8,  UNTOUCHED);
    p = place_movi_il(p, REG_FILE_A, 4'd9,  UNTOUCHED);
    p = place_movi_il(p, REG_FILE_A, 4'd10, UNTOUCHED);

    // Eight scenarios. Operand convention: a_value goes into Rd (A1),
    // b_value goes into Rs (A2). CMP Rs, Rd computes Rd - Rs.
    //
    //   1. JRLT take  : Rd=-5, Rs= 5   (Rd<Rs signed)    → A3
    //   2. JRLT skip  : Rd= 5, Rs=-5   (Rd>Rs signed)    → A4
    //   3. JRGE take  : Rd= 5, Rs=-5   (Rd>Rs signed)    → A5
    //   4. JRGE skip  : Rd=-5, Rs= 5   (Rd<Rs signed)    → A6
    //   5. JRLE take  : Rd= 5, Rs= 5   (equality, Z=1)   → A7
    //   6. JRLE skip  : Rd= 5, Rs=-5   (Rd>Rs signed)    → A8
    //   7. JRGT take  : Rd= 5, Rs=-5   (Rd>Rs signed)    → A9
    //   8. JRGT skip  : Rd= 5, Rs= 5   (equality, Z=1)   → A10
    place_scenario(p, 4'd1, 4'd2, -32'sd5,  32'sd5,  CC_LT, 4'd3,  FT_LT_TAKE);
    place_scenario(p, 4'd1, 4'd2,  32'sd5, -32'sd5,  CC_LT, 4'd4,  FT_LT_SKIP);
    place_scenario(p, 4'd1, 4'd2,  32'sd5, -32'sd5,  CC_GE, 4'd5,  FT_GE_TAKE);
    place_scenario(p, 4'd1, 4'd2, -32'sd5,  32'sd5,  CC_GE, 4'd6,  FT_GE_SKIP);
    place_scenario(p, 4'd1, 4'd2,  32'sd5,  32'sd5,  CC_LE, 4'd7,  FT_LE_TAKE);
    place_scenario(p, 4'd1, 4'd2,  32'sd5, -32'sd5,  CC_LE, 4'd8,  FT_LE_SKIP);
    place_scenario(p, 4'd1, 4'd2,  32'sd5, -32'sd5,  CC_GT, 4'd9,  FT_GT_TAKE);
    place_scenario(p, 4'd1, 4'd2,  32'sd5,  32'sd5,  CC_GT, 4'd10, FT_GT_SKIP);

    repeat (3) @(posedge clk);
    rst = 1'b0;

    // Each scenario is 11 words; 8 scenarios = 88 words plus 8 sentinel
    // inits at 3 words each = 24 words; total ≈ 112 words. Average ~9
    // cycles/word ≈ 1000 cycles. Use 2000 for headroom.
    repeat (2000) @(posedge clk);
    #1;

    // Branch TOOK  → sentinel still at UNTOUCHED (0xC357)
    // Branch SKIPPED → sentinel overwritten with FT_*_SKIP value
    check_reg("JRLT take (-5<5)  → A3 untouched",
              u_core.u_regfile.a_regs[3],  UNTOUCHED);
    check_reg("JRLT skip (5>-5)  → A4 has fall-through",
              u_core.u_regfile.a_regs[4],  FT_LT_SKIP);
    check_reg("JRGE take (5>=-5) → A5 untouched",
              u_core.u_regfile.a_regs[5],  UNTOUCHED);
    check_reg("JRGE skip (-5<5)  → A6 has fall-through",
              u_core.u_regfile.a_regs[6],  FT_GE_SKIP);
    check_reg("JRLE take (5==5)  → A7 untouched",
              u_core.u_regfile.a_regs[7],  UNTOUCHED);
    check_reg("JRLE skip (5>-5)  → A8 has fall-through",
              u_core.u_regfile.a_regs[8],  FT_LE_SKIP);
    check_reg("JRGT take (5>-5)  → A9 untouched",
              u_core.u_regfile.a_regs[9],  UNTOUCHED);
    check_reg("JRGT skip (5==5)  → A10 has fall-through",
              u_core.u_regfile.a_regs[10], FT_GT_SKIP);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (8 signed-compare branch scenarios verified: LT/GE/LE/GT take+skip)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #4_000_000;
    $display("TEST_RESULT: FAIL: tb_jrcc_signed hard timeout");
    $fatal(1);
  end

endmodule : tb_jrcc_signed
