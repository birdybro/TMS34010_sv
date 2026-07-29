// -----------------------------------------------------------------------------
// tb_cmpxy.sv
//
// CMPXY Rs,Rd — nondestructive compare of the X (low 16) and Y (high 16)
// halves of Rs and Rd. Per SPVU001A page 12-55. Encoding 1110 010S SSSR
// DDDD (0xE400). Rd is NOT modified; only the status bits are set, as if
// RdX-RsX and RdY-RsY had been computed:
//   N=(Xres==0), V=Xres[15], Z=(Yres==0), C=Yres[15]
// (X/Y result sign bits — unlike SUBXY's signed greater-than C/V).
//
// Cases from TI's example table (Rs=A1=0x00090009, Rd varies); flags via
// GETST snapshots; Rd checked unchanged.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_cmpxy;
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
  function automatic instr_word_t cmpxy_enc(input reg_idx_t rs, input reg_idx_t rd);
    cmpxy_enc = 16'hE400 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
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
  task automatic check_nczv(input string label, input logic [DATA_WIDTH-1:0] st,
                            input logic [3:0] nczv);
    logic [3:0] got;
    got = {st[ST_N_BIT], st[ST_C_BIT], st[ST_Z_BIT], st[ST_V_BIT]};
    if (got !== nczv) begin
      $display("TEST_RESULT: FAIL: %s: expected NCZV=%04b actual=%04b", label, nczv, got);
      failures++;
    end
  endtask

  initial begin : main
    int unsigned p, i;
    failures = 0;
    for (i = 0; i < 128; i++) u_mem.mem[i] = 16'h0300;

    p = 0;
    p = place_movi_il(p, 4'd1, 32'h0009_0009);   // Rs = A1 (shared)
    // Rd=0x00010001 -> NCZV=0101.
    p = place_movi_il(p, 4'd0, 32'h0001_0001);
    p = place_word(p, cmpxy_enc(4'd1, 4'd0));
    p = place_word(p, getst_enc(4'd8));
    // Rd=0x00090009 -> NCZV=1010.
    p = place_movi_il(p, 4'd2, 32'h0009_0009);
    p = place_word(p, cmpxy_enc(4'd1, 4'd2));
    p = place_word(p, getst_enc(4'd9));
    // Rd=0x00100000 -> NCZV=0001.
    p = place_movi_il(p, 4'd3, 32'h0010_0000);
    p = place_word(p, cmpxy_enc(4'd1, 4'd3));
    p = place_word(p, getst_enc(4'd10));
    // Rd=0x00100009 -> NCZV=1000.
    p = place_movi_il(p, 4'd4, 32'h0010_0009);
    p = place_word(p, cmpxy_enc(4'd1, 4'd4));
    p = place_word(p, getst_enc(4'd11));

    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (1500) @(posedge clk);
    #1;

    check_nczv("CMPXY Rd=00010001 NCZV=0101", u_core.u_regfile.a_regs[8],  4'b0101);
    check_nczv("CMPXY Rd=00090009 NCZV=1010", u_core.u_regfile.a_regs[9],  4'b1010);
    check_nczv("CMPXY Rd=00100000 NCZV=0001", u_core.u_regfile.a_regs[10], 4'b0001);
    check_nczv("CMPXY Rd=00100009 NCZV=1000", u_core.u_regfile.a_regs[11], 4'b1000);
    // Nondestructive: Rd and Rs unchanged.
    check_reg("Rd A0 unchanged", u_core.u_regfile.a_regs[0], 32'h0001_0001);
    check_reg("Rd A2 unchanged", u_core.u_regfile.a_regs[2], 32'h0009_0009);
    check_reg("Rd A3 unchanged", u_core.u_regfile.a_regs[3], 32'h0010_0000);
    check_reg("Rd A4 unchanged", u_core.u_regfile.a_regs[4], 32'h0010_0009);
    check_reg("Rs A1 unchanged", u_core.u_regfile.a_regs[1], 32'h0009_0009);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (CMPXY: nondestructive XY compare; NCZV per TI table)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_cmpxy hard timeout");
    $fatal(1);
  end

endmodule : tb_cmpxy
