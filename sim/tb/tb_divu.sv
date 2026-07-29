// -----------------------------------------------------------------------------
// tb_divu.sv
//
// DIVU Rs,Rd — unsigned divide. Per SPVU001A page 12-69. Encoding
// 0101 101S SSSR DDDD (0x5A00). Multi-cycle (the core runs the divider).
//   Even Rd: 64-bit dividend {Rd, Rd+1} / Rs -> quotient in Rd, remainder
//            in Rd+1.
//   Odd  Rd: 32-bit dividend Rd / Rs -> quotient in Rd.
// Status: N Unaffected; Z = quotient==0; V = 1 on overflow (divisor 0 or
// quotient > 32 bits), in which case the result registers are unchanged.
//
// Cases: TI's even example, an odd-Rd divide, divide-by-zero, a
// quotient-overflow, and a zero-quotient. Flags snapshot to B0..B4.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_divu;
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

  sim_memory_model #(.DEPTH_WORDS(128)) u_mem (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack)
  );

  function automatic instr_word_t movi_il_enc(input logic r, input reg_idx_t i);
    movi_il_enc = 16'h09E0 | (instr_word_t'(r) << 4) | instr_word_t'(i);
  endfunction
  function automatic instr_word_t divu_enc(input reg_idx_t rs, input reg_idx_t rd);
    divu_enc = 16'h5A00 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
  endfunction
  function automatic instr_word_t getst_b_enc(input reg_idx_t rd);  // GETST B<rd>
    getst_b_enc = 16'h0190 | instr_word_t'(rd);
  endfunction

  function automatic int unsigned place_movi_il(input int unsigned p,
                                                input logic r, input reg_idx_t i,
                                                input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]     = movi_il_enc(r, i);
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
    // 1) even normal (TI example): A0:A1 = 0x12345678_87654321 / A2=0x789ABCDF.
    p = place_movi_il(p, 1'b0, 4'd0, 32'h1234_5678);
    p = place_movi_il(p, 1'b0, 4'd1, 32'h8765_4321);
    p = place_movi_il(p, 1'b0, 4'd2, 32'h789A_BCDF);
    p = place_word(p, divu_enc(4'd2, 4'd0));
    p = place_word(p, getst_b_enc(4'd0));
    // 2) odd Rd: A3=100 / A7=7 -> quotient 14 in A3.
    p = place_movi_il(p, 1'b0, 4'd3, 32'd100);
    p = place_movi_il(p, 1'b0, 4'd7, 32'd7);
    p = place_word(p, divu_enc(4'd7, 4'd3));
    p = place_word(p, getst_b_enc(4'd1));
    // 3) divide by zero (even): A4:A5 / A6=0 -> V=1, unchanged.
    p = place_movi_il(p, 1'b0, 4'd4, 32'h1234_5678);
    p = place_movi_il(p, 1'b0, 4'd5, 32'h8765_4321);
    p = place_movi_il(p, 1'b0, 4'd6, 32'h0000_0000);
    p = place_word(p, divu_enc(4'd6, 4'd4));
    p = place_word(p, getst_b_enc(4'd2));
    // 4) quotient overflow (even): A8:A9 = 0x87654321_00000000 / A10=0x87654321
    //    -> quotient 2^32 > 32b -> V=1, unchanged.
    p = place_movi_il(p, 1'b0, 4'd8, 32'h8765_4321);
    p = place_movi_il(p, 1'b0, 4'd9, 32'h0000_0000);
    p = place_movi_il(p, 1'b0, 4'd10, 32'h8765_4321);
    p = place_word(p, divu_enc(4'd10, 4'd8));
    p = place_word(p, getst_b_enc(4'd3));
    // 5) zero quotient (even): A12:A13 = 0 / A14=5 -> quotient 0, Z=1.
    p = place_movi_il(p, 1'b0, 4'd12, 32'h0000_0000);
    p = place_movi_il(p, 1'b0, 4'd13, 32'h0000_0000);
    p = place_movi_il(p, 1'b0, 4'd14, 32'd5);
    p = place_word(p, divu_enc(4'd14, 4'd12));
    p = place_word(p, getst_b_enc(4'd4));

    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (3000) @(posedge clk);
    #1;

    // 1) even normal.
    check_reg("1: A0 = quotient 0x26A439F6",  u_core.u_regfile.a_regs[0], 32'h26A4_39F6);
    check_reg("1: A1 = remainder 0x15CA1DD7", u_core.u_regfile.a_regs[1], 32'h15CA_1DD7);
    check_reg("1: A2 (divisor) unchanged",    u_core.u_regfile.a_regs[2], 32'h789A_BCDF);
    check_bit("1: V=0", u_core.u_regfile.b_regs[0][ST_V_BIT], 1'b0);
    check_bit("1: Z=0", u_core.u_regfile.b_regs[0][ST_Z_BIT], 1'b0);
    // 2) odd.
    check_reg("2: A3 = quotient 14", u_core.u_regfile.a_regs[3], 32'd14);
    check_bit("2: V=0", u_core.u_regfile.b_regs[1][ST_V_BIT], 1'b0);
    // 3) divide by zero.
    check_reg("3: A4 unchanged", u_core.u_regfile.a_regs[4], 32'h1234_5678);
    check_reg("3: A5 unchanged", u_core.u_regfile.a_regs[5], 32'h8765_4321);
    check_bit("3: V=1 (div by zero)", u_core.u_regfile.b_regs[2][ST_V_BIT], 1'b1);
    // 4) overflow.
    check_reg("4: A8 unchanged", u_core.u_regfile.a_regs[8], 32'h8765_4321);
    check_reg("4: A9 unchanged", u_core.u_regfile.a_regs[9], 32'h0000_0000);
    check_bit("4: V=1 (overflow)", u_core.u_regfile.b_regs[3][ST_V_BIT], 1'b1);
    // 5) zero quotient.
    check_reg("5: A12 = 0 (quotient)",  u_core.u_regfile.a_regs[12], 32'h0000_0000);
    check_reg("5: A13 = 0 (remainder)", u_core.u_regfile.a_regs[13], 32'h0000_0000);
    check_bit("5: Z=1", u_core.u_regfile.b_regs[4][ST_Z_BIT], 1'b1);
    check_bit("5: V=0", u_core.u_regfile.b_regs[4][ST_V_BIT], 1'b0);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (DIVU: even/odd, div-by-zero, overflow, zero-quotient)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #5_000_000;
    $display("TEST_RESULT: FAIL: tb_divu hard timeout");
    $fatal(1);
  end

endmodule : tb_divu
