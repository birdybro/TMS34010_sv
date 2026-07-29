// -----------------------------------------------------------------------------
// tb_divs_mods.sv
//
// DIVS / MODS — signed divide / modulo. Per SPVU001A pages 12-63 (DIVS) /
// 12-112 (MODS). Encodings 0101 100S (DIVS, 0x5800) / 0110 110S (MODS,
// 0x6C00) SSSR DDDD. The divider stays unsigned; the core feeds
// |operands| and sign-conditions the results:
//   quotient sign  = dividend.sign ^ divisor.sign
//   remainder sign = dividend.sign
// DIVS even Rd: 64-bit {Rd, Rd+1} dividend -> quotient in Rd, remainder in
// Rd+1; odd Rd: 32-bit -> quotient in Rd. MODS: remainder -> Rd.
// DIVS defines N from the quotient/0x80000000 rules. MODS leaves N and C
// Unaffected. Z follows the stored result (Unaffected if Rs=0 for MODS), and
// V reports quotient overflow.
//
// Cases from TI's DIVS/MODS example tables.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_divs_mods;
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
  function automatic instr_word_t divs_enc(input reg_idx_t rs, input reg_idx_t rd);
    divs_enc = 16'h5800 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
  endfunction
  function automatic instr_word_t mods_enc(input reg_idx_t rs, input reg_idx_t rd);
    mods_enc = 16'h6C00 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
  endfunction
  function automatic instr_word_t getst_b_enc(input reg_idx_t rd);
    getst_b_enc = 16'h0190 | instr_word_t'(rd);
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
  task automatic check_nzv(input string label, input logic [DATA_WIDTH-1:0] st,
                           input logic n, input logic z, input logic v);
    if (st[ST_N_BIT] !== n || st[ST_Z_BIT] !== z || st[ST_V_BIT] !== v) begin
      $display("TEST_RESULT: FAIL: %s: exp NZV=%0b%0b%0b got %0b%0b%0b",
               label, n, z, v, st[ST_N_BIT], st[ST_Z_BIT], st[ST_V_BIT]);
      failures++;
    end
  endtask

  initial begin : main
    int unsigned p, i;
    failures = 0;
    for (i = 0; i < 128; i++) u_mem.mem[i] = 16'h0300;

    p = 0;
    // 1) DIVS even, neg result: {A0,A1}=0x12345678_87654321 / A2=0x87654321
    //    -> A0=0xD95BC60A, A1=0x15CA1DD7. N=1, Z=0, V=0.
    p = place_movi_il(p, 4'd0, 32'h1234_5678);
    p = place_movi_il(p, 4'd1, 32'h8765_4321);
    p = place_movi_il(p, 4'd2, 32'h8765_4321);
    p = place_word(p, divs_enc(4'd2, 4'd0));
    p = place_word(p, getst_b_enc(4'd0));
    // 2) DIVS even, pos result: {A4,A5}=0xEDCBA987_789ABCDF / A6=0x87654321
    //    -> A4=0x26A439F6, A5=0xEA35E229. N=0, Z=0, V=0.
    p = place_movi_il(p, 4'd4, 32'hEDCB_A987);
    p = place_movi_il(p, 4'd5, 32'h789A_BCDF);
    p = place_movi_il(p, 4'd6, 32'h8765_4321);
    p = place_word(p, divs_enc(4'd6, 4'd4));
    p = place_word(p, getst_b_enc(4'd1));
    // 3) DIVS even Rs=0: unchanged, V=1.
    p = place_movi_il(p, 4'd8, 32'h1234_5678);
    p = place_movi_il(p, 4'd9, 32'h8765_4321);
    p = place_movi_il(p, 4'd10, 32'h0000_0000);
    p = place_word(p, divs_enc(4'd10, 4'd8));
    p = place_word(p, getst_b_enc(4'd2));
    // 4) DIVS odd: A3=0x87654321 (-) / A7=0x12345678 (+) -> A3=0xFFFFFFFA (-6). N=1.
    p = place_movi_il(p, 4'd3, 32'h8765_4321);
    p = place_movi_il(p, 4'd7, 32'h1234_5678);
    p = place_word(p, divs_enc(4'd7, 4'd3));
    p = place_word(p, getst_b_enc(4'd3));
    // 5) MODS neg: A12=-7 (0xFFFFFFF9) mod A11=4 -> -3 (0xFFFFFFFD).
    //    N remains 1 from case 4; Z becomes 0.
    p = place_movi_il(p, 4'd11, 32'd4);
    p = place_movi_il(p, 4'd12, 32'hFFFF_FFF9);
    p = place_word(p, mods_enc(4'd11, 4'd12));
    p = place_word(p, getst_b_enc(4'd4));
    // 6) MODS Rs=0: load A14=0 first (Z=1), A13=7 last (Z=0); MODS A14,A13
    //    -> A13 unchanged (7), V=1, Z UNAFFECTED (stays 0).
    p = place_movi_il(p, 4'd14, 32'd0);
    p = place_movi_il(p, 4'd13, 32'd7);
    p = place_word(p, mods_enc(4'd14, 4'd13));
    p = place_word(p, getst_b_enc(4'd5));

    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (4000) @(posedge clk);
    #1;

    // 1) DIVS even neg.
    check_reg("1: A0 quotient 0xD95BC60A",  u_core.u_regfile.a_regs[0], 32'hD95B_C60A);
    check_reg("1: A1 remainder 0x15CA1DD7", u_core.u_regfile.a_regs[1], 32'h15CA_1DD7);
    check_nzv("1: NZV=1,0,0", u_core.u_regfile.b_regs[0], 1'b1, 1'b0, 1'b0);
    // 2) DIVS even pos.
    check_reg("2: A4 quotient 0x26A439F6",  u_core.u_regfile.a_regs[4], 32'h26A4_39F6);
    check_reg("2: A5 remainder 0xEA35E229", u_core.u_regfile.a_regs[5], 32'hEA35_E229);
    check_nzv("2: NZV=0,0,0", u_core.u_regfile.b_regs[1], 1'b0, 1'b0, 1'b0);
    // 3) Rs=0.
    check_reg("3: A8 unchanged", u_core.u_regfile.a_regs[8], 32'h1234_5678);
    check_nzv("3: V=1", u_core.u_regfile.b_regs[2], 1'b0, 1'b0, 1'b1);
    // 4) DIVS odd.
    check_reg("4: A3 quotient 0xFFFFFFFA (-6)", u_core.u_regfile.a_regs[3], 32'hFFFF_FFFA);
    check_nzv("4: NZV=1,0,0", u_core.u_regfile.b_regs[3], 1'b1, 1'b0, 1'b0);
    // 5) MODS neg.
    check_reg("5: A12 remainder 0xFFFFFFFD (-3)", u_core.u_regfile.a_regs[12], 32'hFFFF_FFFD);
    check_nzv("5: NZV=1,0,0 (N preserved)", u_core.u_regfile.b_regs[4], 1'b1, 1'b0, 1'b0);
    // 6) MODS Rs=0.
    check_reg("6: A13 unchanged (=7)", u_core.u_regfile.a_regs[13], 32'd7);
    check_nzv("6: V=1, Z unaffected (=0)", u_core.u_regfile.b_regs[5], 1'b0, 1'b0, 1'b1);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (DIVS/MODS signed results and documented status behavior)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #5_000_000;
    $display("TEST_RESULT: FAIL: tb_divs_mods hard timeout");
    $fatal(1);
  end

endmodule : tb_divs_mods
