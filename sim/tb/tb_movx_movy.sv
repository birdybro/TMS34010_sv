// -----------------------------------------------------------------------------
// tb_movx_movy.sv
//
// MOVX Rs,Rd and MOVY Rs,Rd — move the X (low 16) / Y (high 16) half of
// Rs into the same half of Rd, leaving the other half of Rd unchanged.
// Per SPVU001A pages 12-162 (MOVX) and 12-163 (MOVY). Encodings
// 1110 110S SSSR DDDD (MOVX, 0xEC00) and 1110 111S SSSR DDDD (MOVY,
// 0xEE00). Rs and Rd same file; all status bits Unaffected.
//
// Checks the half-preservation behavior plus TI's worked examples.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_movx_movy;
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
    .state_o(state_w), .pc_o(pc_w), .instr_word_o(instr_w), .illegal_opcode_o(illegal_w), .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1), .lint2_n_i(1'b1), .host_int_set_i(1'b0), .dpyint_set_i(1'b0), .refresh_req_o(), .refresh_row_o(), .refresh_cbr_o(), .video_hsync_o(), .video_vsync_o(), .video_hblank_o(), .video_vblank_o(), .video_blank_o(), .screen_refresh_req_o(), .screen_refresh_ack_i(1'b0), .screen_refresh_srfaddr_o(), .screen_refresh_dpytap_o()
  );

  sim_memory_model #(.DEPTH_WORDS(128)) u_mem (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack)
  );

  function automatic instr_word_t movi_il_enc(input reg_idx_t i);
    movi_il_enc = 16'h09E0 | instr_word_t'(i);
  endfunction
  function automatic instr_word_t movx_enc(input reg_idx_t rs, input reg_idx_t rd);
    movx_enc = 16'hEC00 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
  endfunction
  function automatic instr_word_t movy_enc(input reg_idx_t rs, input reg_idx_t rd);
    movy_enc = 16'hEE00 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
  endfunction

  function automatic int unsigned place_movi_il(input int unsigned p,
                                                input reg_idx_t i,
                                                input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]     = movi_il_enc(i);
    u_mem.mem[p + 1] = imm[15:0];
    u_mem.mem[p + 2] = imm[31:16];
    place_movi_il = p + 3;
  endfunction
  function automatic int unsigned place_word(input int unsigned p, input instr_word_t w);
    u_mem.mem[p] = w;  place_word = p + 1;
  endfunction

  int unsigned failures;
  task automatic check_reg(input string label,
                           input logic [DATA_WIDTH-1:0] actual, expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%08h actual=%08h", label, expected, actual);
      failures++;
    end
  endtask

  initial begin : main
    int unsigned p, i;
    failures = 0;
    for (i = 0; i < 128; i++) u_mem.mem[i] = 16'h0300;

    p = 0;
    // MOVX A0,A1: A1 keeps its Y, takes A0's X.
    p = place_movi_il(p, 4'd0, 32'h1234_5678);
    p = place_movi_il(p, 4'd1, 32'hAAAA_BBBB);
    p = place_word(p, movx_enc(4'd0, 4'd1));     // A1 -> AAAA5678
    // MOVY A2,A3: A3 keeps its X, takes A2's Y.
    p = place_movi_il(p, 4'd2, 32'h1234_5678);
    p = place_movi_il(p, 4'd3, 32'hCCCC_DDDD);
    p = place_word(p, movy_enc(4'd2, 4'd3));     // A3 -> 1234DDDD
    // Spec example MOVX A4,A5: A5=0 -> 00005678.
    p = place_movi_il(p, 4'd4, 32'h1234_5678);
    p = place_movi_il(p, 4'd5, 32'h0000_0000);
    p = place_word(p, movx_enc(4'd4, 4'd5));     // A5 -> 00005678
    // Spec example MOVY A6,A7: A7=0 -> 12340000.
    p = place_movi_il(p, 4'd6, 32'h1234_5678);
    p = place_movi_il(p, 4'd7, 32'h0000_0000);
    p = place_word(p, movy_enc(4'd6, 4'd7));     // A7 -> 12340000

    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (1500) @(posedge clk);
    #1;

    check_reg("MOVX A0,A1: A1 = AAAA5678", u_core.u_regfile.a_regs[1], 32'hAAAA_5678);
    check_reg("MOVX: A0 (src) unchanged",  u_core.u_regfile.a_regs[0], 32'h1234_5678);
    check_reg("MOVY A2,A3: A3 = 1234DDDD", u_core.u_regfile.a_regs[3], 32'h1234_DDDD);
    check_reg("MOVY: A2 (src) unchanged",  u_core.u_regfile.a_regs[2], 32'h1234_5678);
    check_reg("MOVX A4,A5: A5 = 00005678 (spec)", u_core.u_regfile.a_regs[5], 32'h0000_5678);
    check_reg("MOVY A6,A7: A7 = 12340000 (spec)", u_core.u_regfile.a_regs[7], 32'h1234_0000);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (MOVX/MOVY: half-replace with other half preserved; spec examples)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_movx_movy hard timeout");
    $fatal(1);
  end

endmodule : tb_movx_movy
