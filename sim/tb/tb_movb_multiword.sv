// -----------------------------------------------------------------------------
// tb_movb_multiword.sv
//
// Completes the two multiword MOVB memory-to-memory forms:
//   - *Rs(SOffset),*Rd(DOffset): opcode, signed source offset, signed dest offset
//   - @SAddress,@DAddress: opcode, source low/high, destination low/high
//
// 1988 TI TMS34010 User's Guide pp. 12-120/121 and 12-123/124. Both forms
// transfer exactly eight bits between bit addresses and leave registers and
// status flags unaffected. The vectors deliberately cross 16-bit memory-word
// boundaries so operand ordering or accidental word-sized transfers fail.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_movb_multiword;
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
    .state_o(state_w), .pc_o(pc_w), .instr_word_o(instr_w), .illegal_opcode_o(illegal_w), .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1), .lint2_n_i(1'b1), .host_int_set_i(1'b0), .dpyint_set_i(1'b0), .refresh_req_o(), .refresh_row_o(), .refresh_cbr_o(), .video_hsync_o(), .video_vsync_o(), .video_hblank_o(), .video_vblank_o(), .video_blank_o()
  );

  sim_memory_model #(.DEPTH_WORDS(512)) u_mem (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack)
  );

  function automatic instr_word_t movi_il_enc(input reg_idx_t rd);
    return 16'h09E0 | instr_word_t'(rd);
  endfunction

  function automatic instr_word_t movk_enc(
      input logic [4:0] k,
      input reg_idx_t rd);
    return 16'h1800 | (instr_word_t'(k) << 5) | instr_word_t'(rd);
  endfunction

  function automatic instr_word_t putst_enc(input reg_idx_t rs);
    return 16'h01A0 | instr_word_t'(rs);
  endfunction

  function automatic int unsigned place_movi_il(
      input int unsigned p,
      input reg_idx_t rd,
      input logic [DATA_WIDTH-1:0] value);
    u_mem.mem[p]     = movi_il_enc(rd);
    u_mem.mem[p + 1] = value[15:0];
    u_mem.mem[p + 2] = value[31:16];
    return p + 3;
  endfunction

  function automatic int unsigned place_movb_off_m2m(
      input int unsigned p,
      input reg_idx_t rs,
      input reg_idx_t rd,
      input logic [15:0] src_offset,
      input logic [15:0] dst_offset);
    u_mem.mem[p]     = 16'hBC00 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
    u_mem.mem[p + 1] = src_offset;
    u_mem.mem[p + 2] = dst_offset;
    return p + 3;
  endfunction

  function automatic int unsigned place_movb_abs_m2m(
      input int unsigned p,
      input logic [ADDR_WIDTH-1:0] src_addr,
      input logic [ADDR_WIDTH-1:0] dst_addr);
    u_mem.mem[p]     = 16'h0340;
    u_mem.mem[p + 1] = src_addr[15:0];
    u_mem.mem[p + 2] = src_addr[31:16];
    u_mem.mem[p + 3] = dst_addr[15:0];
    u_mem.mem[p + 4] = dst_addr[31:16];
    return p + 5;
  endfunction

  int unsigned failures;

  task automatic check_word(
      input string label,
      input int unsigned word_idx,
      input logic [15:0] expected);
    if (u_mem.mem[word_idx] !== expected) begin
      $display("TEST_RESULT: FAIL: %s: mem[%0d] expected=%04h actual=%04h",
               label, word_idx, expected, u_mem.mem[word_idx]);
      failures++;
    end
  endtask

  task automatic check_reg(
      input string label,
      input logic [DATA_WIDTH-1:0] actual,
      input logic [DATA_WIDTH-1:0] expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%08h actual=%08h",
               label, expected, actual);
      failures++;
    end
  endtask

  initial begin : main
    int unsigned i;
    int unsigned p;

    failures = 0;
    for (i = 0; i < 512; i++) u_mem.mem[i] = 16'h0300;

    // Source byte 0xC3 at bit address 0x804 (word 128, bit offset 4).
    u_mem.mem[128] = 16'h0C30;
    u_mem.mem[129] = 16'h0000;
    // Absolute source byte 0xC3 at 0xA09, straddling words 160/161.
    u_mem.mem[160] = 16'h8600;
    u_mem.mem[161] = 16'h0001;
    // Destination sentinels prove neighboring bits survive each 8-bit write.
    u_mem.mem[144] = 16'h0555;
    u_mem.mem[145] = 16'hAAA0;
    u_mem.mem[176] = 16'h8007;

    p = 0;
    // A0 + (-0x3C) = 0x804; A1 + 0x0C = 0x90C (straddles words).
    p = place_movi_il(p, 4'd0, 32'h0000_0840);
    p = place_movi_il(p, 4'd1, 32'h0000_0900);
    // Seed NCZV to 1101 immediately before the two MOVB operations. PUTST
    // restores the exact value after MOVI's implicit flag update.
    p = place_movi_il(p, 4'd3, 32'hD000_0010);
    u_mem.mem[p] = putst_enc(4'd3);
    p = p + 1;
    p = place_movb_off_m2m(p, 4'd0, 4'd1, 16'hFFC4, 16'h000C);

    // Absolute operands are source low/high followed by destination low/high.
    p = place_movb_abs_m2m(p, 32'h0000_0A09, 32'h0000_0B03);

    // This flag-neutral instruction must execute after all four absolute
    // address words, proving five-word PC advancement.
    u_mem.mem[p] = movk_enc(5'd21, 4'd2);
    p = p + 1;
    u_mem.mem[p] = 16'hC0FF;

    repeat (3) @(posedge clk);
    #1;
    rst = 1'b0;
    repeat (2500) @(posedge clk);
    #1;

    // Offset destination: retain low 12 bits of word 144 and high 12 bits of
    // word 145 while inserting byte C3 across the boundary.
    check_word("offset destination low",  144, 16'h3555);
    check_word("offset destination high", 145, 16'hAAAC);
    // Absolute destination 0xB03: C3 occupies bits 3..10; bit 15 sentinel stays.
    check_word("absolute destination", 176, 16'h861F);

    check_reg("offset source base preserved", u_core.u_regfile.a_regs[0], 32'h0000_0840);
    check_reg("offset dest base preserved",   u_core.u_regfile.a_regs[1], 32'h0000_0900);
    check_reg("post-instruction sentinel",    u_core.u_regfile.a_regs[2], 32'd21);
    check_reg("status unaffected", u_core.u_status_reg.st_o, 32'hD000_0010);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (multiword MOVB offset/absolute memory-to-memory)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #3_000_000;
    $display("TEST_RESULT: FAIL: tb_movb_multiword hard timeout");
    $fatal(1);
  end

endmodule : tb_movb_multiword
