// -----------------------------------------------------------------------------
// tb_move_abs_m2m.sv
//
// Direct coverage for the five-word production-revision instruction:
//   MOVE @SAddress,@DAddress[,F]
//
// The 1988 TI TMS34010 User's Guide pp. 12-157/158 specifies opcode
// 0000 01 F1 1100 0000, source LO/HI followed by destination LO/HI. The
// selected FS0/FS1 field is transferred and every status bit is unaffected.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_move_abs_m2m;
  import tms34010_pkg::*;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  logic                        mem_req;
  logic                        mem_we;
  logic [ADDR_WIDTH-1:0]       mem_addr;
  logic [FIELD_SIZE_WIDTH-1:0] mem_size;
  logic [DATA_WIDTH-1:0]       mem_wdata;
  logic [DATA_WIDTH-1:0]       mem_rdata;
  logic                        mem_ack;
  core_state_t                 state_w;
  logic [ADDR_WIDTH-1:0]       pc_w;
  instr_word_t                 instr_w;
  logic                        illegal_w;

  tms34010_core u_core (
    .clk(clk), .vclk_i(clk), .video_hsync_n_i(1'b1),
    .video_vsync_n_i(1'b1), .rst(rst), .vclk_rst_i(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
    .mem_size(mem_size), .mem_wdata(mem_wdata), .mem_srt(),
    .mem_rdata(mem_rdata), .mem_ack(mem_ack), .state_o(state_w),
    .pc_o(pc_w), .instr_word_o(instr_w), .illegal_opcode_o(illegal_w),
    .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1),
    .lint2_n_i(1'b1), .hcs_n_i(1'b0), .host_req_i(1'b0),
    .host_we_i(1'b0), .host_reg_i(HOST_REG_HSTCTL), .host_be_i(2'b00),
    .host_wdata_i(16'h0000), .host_rdata_o(), .host_ack_o(),
    .host_busy_o(), .hint_n_o(), .host_mem_req_o(), .host_mem_we_o(),
    .host_mem_addr_o(), .host_mem_wdata_o(), .host_mem_rdata_i(16'h0000),
    .host_mem_ack_i(1'b0), .dpyint_set_i(1'b0), .refresh_req_o(),
    .refresh_row_o(), .refresh_cbr_o(), .video_hsync_o(),
    .video_vsync_o(), .video_hblank_o(), .video_vblank_o(),
    .video_blank_o(), .video_hsync_oe_o(), .video_vsync_oe_o(),
    .screen_refresh_req_o(), .screen_refresh_ack_i(1'b0),
    .screen_refresh_srfaddr_o(), .screen_refresh_dpytap_o()
  );

  sim_memory_model #(.DEPTH_WORDS(512)) u_mem (
    .clk(clk), .rst(rst), .mem_req(mem_req), .mem_we(mem_we),
    .mem_addr(mem_addr), .mem_size(mem_size), .mem_wdata(mem_wdata),
    .mem_rdata(mem_rdata), .mem_ack(mem_ack)
  );

  function automatic instr_word_t movi_il_enc(input reg_idx_t rd);
    return 16'h09E0 | instr_word_t'(rd);
  endfunction

  function automatic instr_word_t putst_enc(input reg_idx_t rs);
    return 16'h01A0 | instr_word_t'(rs);
  endfunction

  function automatic instr_word_t movk_enc(
      input logic [4:0] k, input reg_idx_t rd);
    return 16'h1800 | (instr_word_t'(k) << 5) | instr_word_t'(rd);
  endfunction

  function automatic int unsigned place_movi(
      input int unsigned p, input reg_idx_t rd,
      input logic [DATA_WIDTH-1:0] value);
    u_mem.mem[p] = movi_il_enc(rd);
    u_mem.mem[p + 1] = value[15:0];
    u_mem.mem[p + 2] = value[31:16];
    return p + 3;
  endfunction

  function automatic int unsigned place_move(
      input int unsigned p, input logic f_select,
      input logic [ADDR_WIDTH-1:0] source,
      input logic [ADDR_WIDTH-1:0] destination);
    u_mem.mem[p] = 16'h05C0 | (instr_word_t'(f_select) << 9);
    u_mem.mem[p + 1] = source[15:0];
    u_mem.mem[p + 2] = source[31:16];
    u_mem.mem[p + 3] = destination[15:0];
    u_mem.mem[p + 4] = destination[31:16];
    return p + 5;
  endfunction

  int unsigned failures;

  task automatic check_word(
      input string label, input int unsigned index,
      input logic [15:0] expected);
    if (u_mem.mem[index] !== expected) begin
      $display("TEST_RESULT: FAIL: %s: mem[%0d] expected=%04h actual=%04h",
               label, index, expected, u_mem.mem[index]);
      failures++;
    end
  endtask

  task automatic check_reg(
      input string label, input logic [DATA_WIDTH-1:0] actual,
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
    for (int unsigned index = 0; index < 512; index++)
      u_mem.mem[index] = 16'h0300;

    // FS0=0 denotes a 32-bit transfer.
    u_mem.mem[130] = 16'hBABE;
    u_mem.mem[131] = 16'hCAFE;
    // At bit address 0xA15, bits 5..12 encode byte A5.
    u_mem.mem[161] = 16'h14A0;
    // The unaligned destination retains bits outside 7..14.
    u_mem.mem[176] = 16'h8001;

    p = 0;
    p = place_movi(p, 4'd14, 32'hD000_0000);
    u_mem.mem[p] = putst_enc(4'd14);
    p++;
    p = place_move(p, 1'b0, 32'h0000_0820, 32'h0000_0900);

    // FS1=8 and F=1 exercise the 0x07C0 encoding and a straddling byte.
    p = place_movi(p, 4'd14, 32'hD000_0200);
    u_mem.mem[p] = putst_enc(4'd14);
    p++;
    p = place_move(p, 1'b1, 32'h0000_0A15, 32'h0000_0B07);

    // A following instruction proves that both absolute forms advance PC by
    // all five words rather than interpreting an address word as an opcode.
    u_mem.mem[p] = movk_enc(5'd21, 4'd2);
    p++;
    u_mem.mem[p] = 16'hC0FF;

    repeat (3) @(posedge clk);
    #1;
    rst = 1'b0;
    repeat (2500) @(posedge clk);
    #1;

    check_word("FS0 destination low", 144, 16'hBABE);
    check_word("FS0 destination high", 145, 16'hCAFE);
    check_word("FS1 unaligned destination", 176, 16'hD281);
    check_reg("five-word PC sentinel", u_core.u_regfile.a_regs[2], 32'd21);
    check_reg("status unaffected", u_core.u_status_reg.st_o, 32'hD000_0200);
    check_reg("nonoperand register unchanged",
              u_core.u_regfile.a_regs[0], 32'h0000_0000);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0)
      $display("TEST_RESULT: PASS (MOVE absolute-to-absolute F0/F1, FS32/8, unaligned, operand order, five-word PC, status)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #3_000_000;
    $display("TEST_RESULT: FAIL: tb_move_abs_m2m hard timeout");
    $fatal(1);
  end

endmodule : tb_move_abs_m2m
