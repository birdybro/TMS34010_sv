// -----------------------------------------------------------------------------
// tb_div_flags.sv
//
// Signed DIVS/MODS status and overflow edge cases from the 1988 User's Guide
// pages 12-63/64 and 12-112/113. The cases distinguish MODS's unaffected N/C,
// its valid remainder write on signed quotient overflow, and DIVS N behavior
// on signed-range overflow that did not trigger the divider's early raw
// overflow path. Full PUTST/GETST snapshots make every affected/unaffected bit
// observable.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_div_flags;
  import tms34010_pkg::*;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  logic                        mem_req, mem_we, mem_ack;
  logic [ADDR_WIDTH-1:0]       mem_addr;
  logic [FIELD_SIZE_WIDTH-1:0] mem_size;
  logic [DATA_WIDTH-1:0]       mem_wdata, mem_rdata;
  core_state_t                 state_w;
  logic [ADDR_WIDTH-1:0]       pc_w;
  instr_word_t                 instr_w;
  logic                        illegal_w;

  tms34010_core u_core (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
    .mem_size(mem_size), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
    .mem_ack(mem_ack), .state_o(state_w), .pc_o(pc_w),
    .instr_word_o(instr_w), .illegal_opcode_o(illegal_w),
    .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1), .lint2_n_i(1'b1), .hcs_n_i(1'b0), .host_ctl_we_i(1'b0), .host_ctl_be_i(2'b00), .host_ctl_wdata_i(16'h0000), .host_ctl_rdata_o(), .hint_n_o(), .dpyint_set_i(1'b0), .refresh_req_o(), .refresh_row_o(), .refresh_cbr_o(), .video_hsync_o(), .video_vsync_o(), .video_hblank_o(), .video_vblank_o(), .video_blank_o(), .screen_refresh_req_o(), .screen_refresh_ack_i(1'b0), .screen_refresh_srfaddr_o(), .screen_refresh_dpytap_o()
  );

  sim_memory_model #(.DEPTH_WORDS(160)) u_mem (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
    .mem_size(mem_size), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
    .mem_ack(mem_ack)
  );

  function automatic instr_word_t movi_il_enc(input reg_idx_t rd);
    movi_il_enc = 16'h09E0 | instr_word_t'(rd);
  endfunction
  function automatic instr_word_t divs_enc(input reg_idx_t rs, input reg_idx_t rd);
    divs_enc = 16'h5800 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
  endfunction
  function automatic instr_word_t mods_enc(input reg_idx_t rs, input reg_idx_t rd);
    mods_enc = 16'h6C00 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
  endfunction
  function automatic instr_word_t putst_enc(input reg_idx_t rs);
    putst_enc = 16'h01A0 | instr_word_t'(rs);
  endfunction
  function automatic instr_word_t getst_b_enc(input reg_idx_t rd);
    getst_b_enc = 16'h0190 | instr_word_t'(rd);
  endfunction

  function automatic int unsigned place_movi_il(input int unsigned p,
                                                input reg_idx_t rd,
                                                input logic [DATA_WIDTH-1:0] value);
    u_mem.mem[p] = movi_il_enc(rd);
    u_mem.mem[p + 1] = value[15:0];
    u_mem.mem[p + 2] = value[31:16];
    place_movi_il = p + 3;
  endfunction
  function automatic int unsigned place_word(input int unsigned p,
                                              input instr_word_t word);
    u_mem.mem[p] = word;
    place_word = p + 1;
  endfunction

  int unsigned failures;

  task automatic check_word(input string label,
                            input logic [DATA_WIDTH-1:0] actual,
                            input logic [DATA_WIDTH-1:0] expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%08h actual=%08h",
               label, expected, actual);
      failures++;
    end
  endtask

  initial begin : main
    int unsigned p, i;

    failures = 0;
    for (i = 0; i < 160; i++) u_mem.mem[i] = 16'h0300;
    p = 0;

    // MODS -7 % 4 = -3. Seed N=0/C=1 proves N follows "Unaffected", not
    // the negative remainder; Z/V are both defined and clear.
    p = place_movi_il(p, 4'd0, 32'hFFFF_FFF9);
    p = place_movi_il(p, 4'd1, 32'd4);
    p = place_movi_il(p, 4'd14, 32'h4000_0010);
    p = place_word(p, putst_enc(4'd14));
    p = place_word(p, mods_enc(4'd1, 4'd0));
    p = place_word(p, getst_b_enc(4'd0));

    // -2^31 % -1 has a signed quotient overflow but a valid zero remainder.
    // MODS always overwrites Rd, updates Z from that remainder, and sets V.
    p = place_movi_il(p, 4'd2, 32'h8000_0000);
    p = place_movi_il(p, 4'd3, 32'hFFFF_FFFF);
    p = place_movi_il(p, 4'd14, 32'hC000_0010);
    p = place_word(p, putst_enc(4'd14));
    p = place_word(p, mods_enc(4'd3, 4'd2));
    p = place_word(p, getst_b_enc(4'd1));

    // 64-bit -2147483649 / +1 has magnitude 0x80000001: signed overflow,
    // but no raw >=2^32 overflow. DIVS preserves the pair and reports N=1
    // for the negative quotient, Z=0, V=1, with C unaffected.
    p = place_movi_il(p, 4'd4, 32'hFFFF_FFFF);
    p = place_movi_il(p, 4'd5, 32'h7FFF_FFFF);
    p = place_movi_il(p, 4'd6, 32'h0000_0001);
    p = place_movi_il(p, 4'd14, 32'h4000_0010);
    p = place_word(p, putst_enc(4'd14));
    p = place_word(p, divs_enc(4'd6, 4'd4));
    p = place_word(p, getst_b_enc(4'd2));

    // The explicitly documented 0x80000000 result exception sets DIVS N,
    // including the positive signed-overflow computation -2^31 / -1.
    p = place_movi_il(p, 4'd7, 32'h8000_0000);
    p = place_movi_il(p, 4'd8, 32'hFFFF_FFFF);
    p = place_movi_il(p, 4'd14, 32'h4000_0010);
    p = place_word(p, putst_enc(4'd14));
    p = place_word(p, divs_enc(4'd8, 4'd7));
    p = place_word(p, getst_b_enc(4'd3));
    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (5000) @(posedge clk);
    #1;

    check_word("MODS negative remainder", u_core.u_regfile.a_regs[0],
               32'hFFFF_FFFD);
    check_word("MODS preserves N/C and defines Z/V",
               u_core.u_regfile.b_regs[0], 32'h4000_0010);
    check_word("MODS overflow writes valid zero remainder",
               u_core.u_regfile.a_regs[2], 32'h0000_0000);
    check_word("MODS signed-overflow Z/V with N/C preserved",
               u_core.u_regfile.b_regs[1], 32'hF000_0010);
    check_word("DIVS negative overflow preserves Rd",
               u_core.u_regfile.a_regs[4], 32'hFFFF_FFFF);
    check_word("DIVS negative overflow preserves Rd+1",
               u_core.u_regfile.a_regs[5], 32'h7FFF_FFFF);
    check_word("DIVS negative-overflow NCZV",
               u_core.u_regfile.b_regs[2], 32'hD000_0010);
    check_word("DIVS 0x80000000 overflow preserves Rd",
               u_core.u_regfile.a_regs[7], 32'h8000_0000);
    check_word("DIVS 0x80000000-result NCZV",
               u_core.u_regfile.b_regs[3], 32'hD000_0010);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0)
      $display("TEST_RESULT: PASS (DIVS/MODS edge-case NCZV and overflow semantics)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #5_000_000;
    $display("TEST_RESULT: FAIL: tb_div_flags hard timeout");
    $fatal(1);
  end
endmodule : tb_div_flags
