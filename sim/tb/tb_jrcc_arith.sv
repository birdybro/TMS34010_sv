// -----------------------------------------------------------------------------
// tb_jrcc_arith.sv
//
// Conditional branches with the general-arithmetic single-flag condition codes
// (Task 0101), from Table 12-8 (SPVU001A page 12-31):
//
//   C   (cc=1000): C = 1   (carry/borrow set)
//   V   (cc=1100): V = 1   (overflow)
//   NV  (cc=1101): V = 0   (no overflow)
//   N   (cc=1110): N = 1   (result negative)
//   NN  (cc=1111): N = 0   (result nonnegative)
//
// Each is exercised both ways (take + skip) via a `CMP Rs,Rd` (= Rd - Rs)
// that sets the flags, followed by `JRcc +3`. The fall-through MOVI overwrites
// a pre-initialized sentinel ONLY if the branch did not take. Flag setups:
//   - C : Rd=3,Rs=10  (3<10 unsigned → borrow → C=1) vs Rd=10,Rs=3 (C=0)
//   - N : Rd=3,Rs=10  (3-10<0 → N=1)               vs Rd=10,Rs=3 (N=0)
//   - V : Rd=0x80000000,Rs=1 (signed underflow → V=1) vs Rd=10,Rs=3 (V=0)
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_jrcc_arith;
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
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack),
    .state_o(state_w), .pc_o(pc_w), .instr_word_o(instr_w), .illegal_opcode_o(illegal_w), .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1), .lint2_n_i(1'b1), .hcs_n_i(1'b0), .host_ctl_we_i(1'b0), .host_ctl_be_i(2'b00), .host_ctl_wdata_i(16'h0000), .host_ctl_rdata_o(), .hint_n_o(), .dpyint_set_i(1'b0), .refresh_req_o(), .refresh_row_o(), .refresh_cbr_o(), .video_hsync_o(), .video_vsync_o(), .video_hblank_o(), .video_vblank_o(), .video_blank_o(), .screen_refresh_req_o(), .screen_refresh_ack_i(1'b0), .screen_refresh_srfaddr_o(), .screen_refresh_dpytap_o()
  );

  sim_memory_model #(.DEPTH_WORDS(512)) u_mem (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack)
  );

  function automatic instr_word_t movi_il_enc(input reg_file_t rf, input reg_idx_t i);
    movi_il_enc = 16'h09E0 | (instr_word_t'(rf) << 4) | (instr_word_t'(i));
  endfunction
  function automatic instr_word_t cmp_rr_enc(input reg_file_t rf,
                                             input reg_idx_t rs, input reg_idx_t rd);
    cmp_rr_enc = 16'h4800 | (instr_word_t'(rs) << 5)
               | (instr_word_t'(rf) << 4) | (instr_word_t'(rd));
  endfunction
  function automatic instr_word_t jrcc_short_enc(input logic [3:0] cc,
                                                 input logic signed [7:0] disp);
    jrcc_short_enc = 16'hC000 | (instr_word_t'(cc) << 8) | {8'h00, disp};
  endfunction
  function automatic int unsigned place_movi_il(input int unsigned p,
                                                input reg_file_t rf, input reg_idx_t i,
                                                input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]     = movi_il_enc(rf, i);
    u_mem.mem[p + 1] = imm[15:0];
    u_mem.mem[p + 2] = imm[31:16];
    place_movi_il = p + 3;
  endfunction
  // CMP Rs,Rd ; JRcc +3 ; fall-through sets sentinel ; landing.
  task automatic place_scenario(ref int unsigned p,
                                input reg_idx_t ra_dst, input reg_idx_t rb_src,
                                input logic [DATA_WIDTH-1:0] a_value, b_value,
                                input logic [3:0] cc, input reg_idx_t sentinel_rd,
                                input logic [DATA_WIDTH-1:0] fall_through_val);
    p = place_movi_il(p, REG_FILE_A, ra_dst, a_value);
    p = place_movi_il(p, REG_FILE_A, rb_src, b_value);
    u_mem.mem[p] = cmp_rr_enc(REG_FILE_A, rb_src, ra_dst); p = p + 1;
    u_mem.mem[p] = jrcc_short_enc(cc, 8'sd3);              p = p + 1;
    p = place_movi_il(p, REG_FILE_A, sentinel_rd, fall_through_val);
    p = place_movi_il(p, REG_FILE_A, ra_dst, 32'h0000_0001);
  endtask

  int unsigned failures;
  task automatic check_reg(input string label,
                           input logic [DATA_WIDTH-1:0] actual, expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%08h actual=%08h", label, expected, actual);
      failures++;
    end
  endtask

  localparam logic [DATA_WIDTH-1:0] UNT = 32'h0000_C357; // untouched = branch took
  localparam logic [DATA_WIDTH-1:0] FT  = 32'h0000_F00D; // fall-through = branch skipped

  initial begin : main
    int unsigned p;
    failures = 0;

    // Encoding sanity for the five new cc codes.
    if (jrcc_short_enc(CC_C,  8'sd3) !== 16'hC803) begin failures++;
      $display("TEST_RESULT: FAIL: JRC enc=%04h exp C803", jrcc_short_enc(CC_C,8'sd3)); end
    if (jrcc_short_enc(CC_V,  8'sd3) !== 16'hCC03) begin failures++;
      $display("TEST_RESULT: FAIL: JRV enc=%04h exp CC03", jrcc_short_enc(CC_V,8'sd3)); end
    if (jrcc_short_enc(CC_NV, 8'sd3) !== 16'hCD03) begin failures++;
      $display("TEST_RESULT: FAIL: JRNV enc=%04h exp CD03", jrcc_short_enc(CC_NV,8'sd3)); end
    if (jrcc_short_enc(CC_N,  8'sd3) !== 16'hCE03) begin failures++;
      $display("TEST_RESULT: FAIL: JRN enc=%04h exp CE03", jrcc_short_enc(CC_N,8'sd3)); end
    if (jrcc_short_enc(CC_NN, 8'sd3) !== 16'hCF03) begin failures++;
      $display("TEST_RESULT: FAIL: JRNN enc=%04h exp CF03", jrcc_short_enc(CC_NN,8'sd3)); end

    // Pre-initialize sentinels A3..A12 to UNTOUCHED.
    p = 0;
    for (int unsigned r = 3; r <= 12; r++)
      p = place_movi_il(p, REG_FILE_A, reg_idx_t'(r), UNT);

    // a_value → Rd (A1), b_value → Rs (A2). CMP Rs,Rd = Rd - Rs.
    place_scenario(p, 4'd1, 4'd2, 32'd3,         32'd10, CC_C,  4'd3, FT); // C=1 take
    place_scenario(p, 4'd1, 4'd2, 32'd10,        32'd3,  CC_C,  4'd4, FT); // C=0 skip
    place_scenario(p, 4'd1, 4'd2, 32'd3,         32'd10, CC_N,  4'd5, FT); // N=1 take
    place_scenario(p, 4'd1, 4'd2, 32'd10,        32'd3,  CC_N,  4'd6, FT); // N=0 skip
    place_scenario(p, 4'd1, 4'd2, 32'd10,        32'd3,  CC_NN, 4'd7, FT); // N=0 take
    place_scenario(p, 4'd1, 4'd2, 32'd3,         32'd10, CC_NN, 4'd8, FT); // N=1 skip
    place_scenario(p, 4'd1, 4'd2, 32'h8000_0000, 32'd1,  CC_V,  4'd9, FT); // V=1 take
    place_scenario(p, 4'd1, 4'd2, 32'd10,        32'd3,  CC_V,  4'd10, FT);// V=0 skip
    place_scenario(p, 4'd1, 4'd2, 32'd10,        32'd3,  CC_NV, 4'd11, FT);// V=0 take
    place_scenario(p, 4'd1, 4'd2, 32'h8000_0000, 32'd1,  CC_NV, 4'd12, FT);// V=1 skip
    u_mem.mem[p] = 16'hC0FF;  // halt

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (4000) @(posedge clk);
    #1;

    check_reg("JRC  take (3<10, C=1)  → A3 untouched", u_core.u_regfile.a_regs[3], UNT);
    check_reg("JRC  skip (10>3, C=0)  → A4 fall-through", u_core.u_regfile.a_regs[4], FT);
    check_reg("JRN  take (3-10<0)     → A5 untouched", u_core.u_regfile.a_regs[5], UNT);
    check_reg("JRN  skip (10-3>0)     → A6 fall-through", u_core.u_regfile.a_regs[6], FT);
    check_reg("JRNN take (10-3>=0)    → A7 untouched", u_core.u_regfile.a_regs[7], UNT);
    check_reg("JRNN skip (3-10<0)     → A8 fall-through", u_core.u_regfile.a_regs[8], FT);
    check_reg("JRV  take (overflow)   → A9 untouched", u_core.u_regfile.a_regs[9], UNT);
    check_reg("JRV  skip (no overflow)→ A10 fall-through", u_core.u_regfile.a_regs[10], FT);
    check_reg("JRNV take (no overflow)→ A11 untouched", u_core.u_regfile.a_regs[11], UNT);
    check_reg("JRNV skip (overflow)   → A12 fall-through", u_core.u_regfile.a_regs[12], FT);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set (a new cc should decode)");
      failures++;
    end

    if (failures == 0)
      $display("TEST_RESULT: PASS (JRcc arith cc: C/V/NV/N/NN take+skip, 5 codes x 2 directions)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #1_000_000;
    $display("TEST_RESULT: FAIL: tb_jrcc_arith hard timeout");
    $fatal(1);
  end

endmodule : tb_jrcc_arith
