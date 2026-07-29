// -----------------------------------------------------------------------------
// tb_mpy.sv
//
// MPYS / MPYU — multiply Rs by the 32-bit Rd, 64-bit result. Per SPVU001A
// pages 12-164 (MPYS) / 12-166 (MPYU). Encodings 0101 110S (MPYS, 0x5C00)
// / 0101 111S (MPYU, 0x5E00) SSSR DDDD. Scope: FS1 = 32 (the reset
// default), i.e. the full 32-bit Rs field.
//
//   Even Rd: 64-bit result -> {Rd = hi32, Rd+1 = lo32}.
//   Odd  Rd: low 32 bits -> Rd.
//   MPYS: N = result<0, Z = result==0. MPYU: Z only (N Unaffected).
//
// Cases: TI's MPYU example (even), an MPYU odd-Rd case, a signed-negative
// MPYS (even), a zero MPYS, and a signed-negative MPYS odd-Rd. Flags via
// GETST snapshots.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_mpy;
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
    .clk(clk), .vclk_i(clk), .video_hsync_n_i(1'b1), .video_vsync_n_i(1'b1), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_srt(), .mem_rdata(mem_rdata), .mem_ack(mem_ack),
    .state_o(state_w), .pc_o(pc_w), .instr_word_o(instr_w), .illegal_opcode_o(illegal_w), .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1), .lint2_n_i(1'b1), .hcs_n_i(1'b0), .host_req_i(1'b0), .host_we_i(1'b0), .host_reg_i(HOST_REG_HSTCTL), .host_be_i(2'b00), .host_wdata_i(16'h0000), .host_rdata_o(), .host_ack_o(), .host_busy_o(), .hint_n_o(), .host_mem_req_o(), .host_mem_we_o(), .host_mem_addr_o(), .host_mem_wdata_o(), .host_mem_rdata_i(16'h0000), .host_mem_ack_i(1'b0), .dpyint_set_i(1'b0), .refresh_req_o(), .refresh_row_o(), .refresh_cbr_o(), .video_hsync_o(), .video_vsync_o(), .video_hblank_o(), .video_vblank_o(), .video_blank_o(), .video_hsync_oe_o(), .video_vsync_oe_o(), .screen_refresh_req_o(), .screen_refresh_ack_i(1'b0), .screen_refresh_srfaddr_o(), .screen_refresh_dpytap_o()
  );

  sim_memory_model #(.DEPTH_WORDS(128)) u_mem (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack)
  );

  function automatic instr_word_t movi_il_enc(input reg_idx_t i);
    movi_il_enc = 16'h09E0 | instr_word_t'(i);   // A-file MOVI IL
  endfunction
  function automatic instr_word_t mpys_enc(input reg_idx_t rs, input reg_idx_t rd);
    mpys_enc = 16'h5C00 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
  endfunction
  function automatic instr_word_t mpyu_enc(input reg_idx_t rs, input reg_idx_t rd);
    mpyu_enc = 16'h5E00 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
  endfunction
  function automatic instr_word_t getst_enc(input reg_idx_t rd);
    getst_enc = 16'h0180 | instr_word_t'(rd);
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
  task automatic check_bit(input string label, input logic actual, expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%0b actual=%0b", label, expected, actual);
      failures++;
    end
  endtask

  initial begin : main
    int unsigned p, i;
    failures = 0;
    for (i = 0; i < 128; i++) u_mem.mem[i] = 16'h0300;

    p = 0;
    // 1) MPYU even (TI example): A0=0xFFFF0000 (Rd), A1=0x10000000 (Rs).
    //    -> A0=0x0FFFF000, A1=0x00000000.
    p = place_movi_il(p, 4'd0, 32'hFFFF_0000);
    p = place_movi_il(p, 4'd1, 32'h1000_0000);
    p = place_word(p, mpyu_enc(4'd1, 4'd0));
    p = place_word(p, getst_enc(4'd2));
    // 2) MPYU odd: A3=3 (Rd odd), A5=5 (Rs) -> A3=0x0000000F (low only).
    p = place_movi_il(p, 4'd3, 32'h0000_0003);
    p = place_movi_il(p, 4'd5, 32'h0000_0005);
    p = place_word(p, mpyu_enc(4'd5, 4'd3));
    p = place_word(p, getst_enc(4'd4));
    // 3) MPYS even negative: A6=-1 (Rd), A7=2 (Rs). product=-2.
    //    -> A6=0xFFFFFFFF (hi), A7=0xFFFFFFFE (lo). N=1, Z=0.
    p = place_movi_il(p, 4'd6, 32'hFFFF_FFFF);
    p = place_movi_il(p, 4'd7, 32'h0000_0002);
    p = place_word(p, mpys_enc(4'd7, 4'd6));
    p = place_word(p, getst_enc(4'd12));
    // 4) MPYS even zero: A8=0 (Rd), A9=5 (Rs) -> A8=0, A9=0. N=0, Z=1.
    p = place_movi_il(p, 4'd8, 32'h0000_0000);
    p = place_movi_il(p, 4'd9, 32'h0000_0005);
    p = place_word(p, mpys_enc(4'd9, 4'd8));
    p = place_word(p, getst_enc(4'd13));
    // 5) MPYS odd negative: A11=-1 (Rd odd), A10=3 (Rs). product=-3.
    //    -> A11=0xFFFFFFFD (low only). N=1, Z=0.
    p = place_movi_il(p, 4'd11, 32'hFFFF_FFFF);
    p = place_movi_il(p, 4'd10, 32'h0000_0003);
    p = place_word(p, mpys_enc(4'd10, 4'd11));
    p = place_word(p, getst_enc(4'd14));

    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (2500) @(posedge clk);
    #1;

    // 1) MPYU even.
    check_reg("1: A0 = 0x0FFFF000 (hi)", u_core.u_regfile.a_regs[0], 32'h0FFF_F000);
    check_reg("1: A1 = 0x00000000 (lo)", u_core.u_regfile.a_regs[1], 32'h0000_0000);
    check_bit("1: MPYU Z=0", u_core.u_regfile.a_regs[2][ST_Z_BIT], 1'b0);
    // 2) MPYU odd.
    check_reg("2: A3 = 0x0000000F (lo only)", u_core.u_regfile.a_regs[3], 32'h0000_000F);
    check_bit("2: MPYU Z=0", u_core.u_regfile.a_regs[4][ST_Z_BIT], 1'b0);
    // 3) MPYS even negative.
    check_reg("3: A6 = 0xFFFFFFFF (hi)", u_core.u_regfile.a_regs[6], 32'hFFFF_FFFF);
    check_reg("3: A7 = 0xFFFFFFFE (lo)", u_core.u_regfile.a_regs[7], 32'hFFFF_FFFE);
    check_bit("3: MPYS N=1", u_core.u_regfile.a_regs[12][ST_N_BIT], 1'b1);
    check_bit("3: MPYS Z=0", u_core.u_regfile.a_regs[12][ST_Z_BIT], 1'b0);
    // 4) MPYS even zero.
    check_reg("4: A8 = 0 (hi)", u_core.u_regfile.a_regs[8], 32'h0000_0000);
    check_reg("4: A9 = 0 (lo)", u_core.u_regfile.a_regs[9], 32'h0000_0000);
    check_bit("4: MPYS N=0", u_core.u_regfile.a_regs[13][ST_N_BIT], 1'b0);
    check_bit("4: MPYS Z=1", u_core.u_regfile.a_regs[13][ST_Z_BIT], 1'b1);
    // 5) MPYS odd negative.
    check_reg("5: A11 = 0xFFFFFFFD (lo only)", u_core.u_regfile.a_regs[11], 32'hFFFF_FFFD);
    check_bit("5: MPYS N=1", u_core.u_regfile.a_regs[14][ST_N_BIT], 1'b1);
    check_bit("5: MPYS Z=0", u_core.u_regfile.a_regs[14][ST_Z_BIT], 1'b0);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (MPYS/MPYU FS1=32: even/odd register-pair result + N/Z)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_mpy hard timeout");
    $fatal(1);
  end

endmodule : tb_mpy
