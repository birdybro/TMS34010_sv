// -----------------------------------------------------------------------------
// tb_line_win.sv
//
// LINE window clipping, CONTROL.W=3 (Task 0115). Per 1988 UG §7.10.3: LINE
// inhibits writes to pixels outside the window (tested per pixel at draw time,
// no preclip); the V bit at the end reflects whether the LAST pixel calculated
// was inside (V=0) or outside (V=1). No interrupt for W=3. (W=1/W=2 abort modes
// deferred — A0031.)
//
// Vertical line of 4 pixels from (0x20,1) downward (CONVDP=0x1B, OFFSET=0x800,
// PSIZE=8, COLOR1=0xAA): pixels at (0x20,1..4) -> words 145..148 low bytes.
// Window WSTART=(0x20,1)..WEND=(0x20,2): (0x20,1),(0x20,2) inside; (0x20,3),
// (0x20,4) outside. So words 145,146 drawn (0x00AA); words 147,148 left 0. The
// last pixel (0x20,4) is outside -> V=1 (captured via GETST).
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_line_win;
  import tms34010_pkg::*;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  logic                          mem_req, mem_we, mem_ack;
  logic [ADDR_WIDTH-1:0]         mem_addr;
  logic [FIELD_SIZE_WIDTH-1:0]   mem_size;
  logic [DATA_WIDTH-1:0]         mem_wdata, mem_rdata;
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
  sim_memory_model #(.DEPTH_WORDS(256)) u_mem (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack)
  );

  function automatic instr_word_t movi_il_enc(input reg_idx_t i);
    movi_il_enc = 16'h09E0 | instr_word_t'(i);
  endfunction
  function automatic instr_word_t movi_il_b_enc(input reg_idx_t i);
    movi_il_b_enc = 16'h09F0 | instr_word_t'(i);
  endfunction
  function automatic instr_word_t setf_enc(input logic [4:0] fs, input logic fe, f_sel);
    setf_enc = 16'b0000_0100_0000_0000
             | (instr_word_t'(f_sel) << 9) | 16'b0000_0001_0000_0000
             | 16'b0000_0000_0100_0000 | (instr_word_t'(fe) << 5) | instr_word_t'(fs);
  endfunction
  function automatic instr_word_t getst_enc(input reg_idx_t rd);
    getst_enc = 16'h0180 | instr_word_t'(rd);
  endfunction
  function automatic int unsigned place_movi_il(input int unsigned p, input reg_idx_t i,
                                                input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]=movi_il_enc(i); u_mem.mem[p+1]=imm[15:0]; u_mem.mem[p+2]=imm[31:16];
    place_movi_il = p + 3;
  endfunction
  function automatic int unsigned place_movi_il_b(input int unsigned p, input reg_idx_t i,
                                                  input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]=movi_il_b_enc(i); u_mem.mem[p+1]=imm[15:0]; u_mem.mem[p+2]=imm[31:16];
    place_movi_il_b = p + 3;
  endfunction
  function automatic int unsigned place_word(input int unsigned p, input instr_word_t w);
    u_mem.mem[p]=w; place_word=p+1;
  endfunction
  function automatic int unsigned place_store_abs(input int unsigned p, input reg_idx_t rs,
                                                  input logic [31:0] addr);
    u_mem.mem[p]=16'h0580|instr_word_t'(rs); u_mem.mem[p+1]=addr[15:0]; u_mem.mem[p+2]=addr[31:16];
    place_store_abs = p + 3;
  endfunction

  int unsigned failures;
  task automatic check_word(input string label, input int unsigned widx, input logic [15:0] expected);
    if (u_mem.mem[widx] !== expected) begin
      $display("TEST_RESULT: FAIL: %s: mem[%0d] expected=%04h actual=%04h",
               label, widx, expected, u_mem.mem[widx]);
      failures++;
    end
  endtask

  localparam logic [31:0] A_PSIZE   = IO_BASE_ADDR + (IO_IDX_PSIZE   << 4);
  localparam logic [31:0] A_CONVDP  = IO_BASE_ADDR + (IO_IDX_CONVDP  << 4);
  localparam logic [31:0] A_CONTROL = IO_BASE_ADDR + (IO_IDX_CONTROL << 4);
  localparam logic [15:0] CTRL_W3   = 16'(2'd3 << CTRL_W_LO);

  initial begin : main
    int unsigned p, i;
    failures = 0;
    for (i = 0; i < 256; i++) u_mem.mem[i] = 16'h0300;
    for (i = 120; i < 200; i++) u_mem.mem[i] = 16'h0000;

    p = 0;
    p = place_word(p, setf_enc(5'd16, 1'b0, 1'b0));
    p = place_movi_il  (p, 4'd0, 32'h0000_0008);
    p = place_store_abs(p, 4'd0, A_PSIZE);               // PSIZE = 8
    p = place_movi_il  (p, 4'd0, 32'h0000_001B);
    p = place_store_abs(p, 4'd0, A_CONVDP);              // CONVDP = 0x1B
    p = place_movi_il  (p, 4'd0, {16'h0, CTRL_W3});
    p = place_store_abs(p, 4'd0, A_CONTROL);             // CONTROL.W = 3 (clip)
    // Line parameters (vertical, 4 px).
    p = place_movi_il_b(p, 4'd0,  32'hFFFF_FFFD);        // d = -3
    p = place_movi_il_b(p, 4'd2,  32'h0001_0020);        // DADDR (0x20,1)
    p = place_movi_il_b(p, 4'd4,  32'h0000_0800);        // OFFSET
    p = place_movi_il_b(p, 4'd5,  32'h0001_0020);        // WSTART (0x20,1)
    p = place_movi_il_b(p, 4'd6,  32'h0002_0020);        // WEND   (0x20,2)
    p = place_movi_il_b(p, 4'd7,  32'h0000_0003);        // DYDX {b=0,a=3}
    p = place_movi_il_b(p, 4'd9,  32'h0000_00AA);        // COLOR1
    p = place_movi_il_b(p, 4'd10, 32'h0000_0004);        // COUNT = 4
    p = place_movi_il_b(p, 4'd11, 32'h0001_0000);        // INC1 (unused)
    p = place_movi_il_b(p, 4'd12, 32'h0001_0000);        // INC2 (+1 Y)
    p = place_word(p, 16'hDF1A);                         // LINE 0
    p = place_word(p, getst_enc(4'd8));                  // A8 <- ST (V=1, last pixel outside)
    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (4000) @(posedge clk);
    #1;

    // Inside pixels drawn; outside pixels clipped (skipped).
    check_word("LINE W=3: word145 (inside) = 0x00AA", 145, 16'h00AA);
    check_word("LINE W=3: word146 (inside) = 0x00AA", 146, 16'h00AA);
    check_word("LINE W=3: word147 (outside) = 0",     147, 16'h0000);
    check_word("LINE W=3: word148 (outside) = 0",     148, 16'h0000);
    // Final V = 1 (last pixel (0x20,4) was outside the window).
    if (u_core.u_regfile.a_regs[8][ST_V_BIT] !== 1'b1) begin
      $display("TEST_RESULT: FAIL: V expected 1 (last pixel outside), A8=%08h",
               u_core.u_regfile.a_regs[8]);
      failures++;
    end
    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set"); failures++;
    end

    if (failures == 0)
      $display("TEST_RESULT: PASS (LINE W=3 clip: inside pixels drawn, outside clipped, V=last-pixel-outside)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #4_000_000;
    $display("TEST_RESULT: FAIL: tb_line_win hard timeout");
    $fatal(1);
  end
endmodule : tb_line_win
