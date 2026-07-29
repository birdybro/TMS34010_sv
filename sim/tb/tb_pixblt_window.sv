// -----------------------------------------------------------------------------
// tb_pixblt_window.sv
//
// PIXBLT XY,XY with window clipping, CONTROL.W=3 (Task 0106). Mirrors the FILL
// XY clip (Task 0105) for the block-transfer engine: destination pixels outside
// the inclusive [WSTART..WEND] XY rectangle are left unchanged. 1988 UG §7.10.3.
//
// Geometry (from tb_pixblt_xy): PSIZE=8, CONVSP=CONVDP=0x1B, OFFSET=0x800.
//   SADDR XY=(0,0) -> linear 0x800 (word 128) = source 0x2211 (pixels 0x11,0x22)
//   DADDR XY=(0x20,0) -> linear 0x900 (word 144) = dest
//   DYDX = DY=1, DX=2 → dest pixels at (X=0x20,Y=0) and (X=0x21,Y=0).
// Window WSTART=WEND=(0x20,0): includes only X=0x20, excludes X=0x21. So the
// low source pixel (0x11) is written; the high dest byte (X=0x21, outside) keeps
// its initial 0. Expected dest word144 = 0x0011 (vs 0x2211 without the window).
// A full-status seed also verifies that W=3 reports the required preclipping
// through V while leaving N/C/Z untouched.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_pixblt_window;
  import tms34010_pkg::*;

  localparam logic [DATA_WIDTH-1:0] ST_SEED = 32'hE000_0010;

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
    .clk(clk), .vclk_i(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack),
    .state_o(state_w), .pc_o(pc_w), .instr_word_o(instr_w), .illegal_opcode_o(illegal_w), .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1), .lint2_n_i(1'b1), .hcs_n_i(1'b0), .host_req_i(1'b0), .host_we_i(1'b0), .host_reg_i(HOST_REG_HSTCTL), .host_be_i(2'b00), .host_wdata_i(16'h0000), .host_rdata_o(), .host_ack_o(), .host_busy_o(), .hint_n_o(), .host_mem_req_o(), .host_mem_we_o(), .host_mem_addr_o(), .host_mem_wdata_o(), .host_mem_rdata_i(16'h0000), .host_mem_ack_i(1'b0), .dpyint_set_i(1'b0), .refresh_req_o(), .refresh_row_o(), .refresh_cbr_o(), .video_hsync_o(), .video_vsync_o(), .video_hblank_o(), .video_vblank_o(), .video_blank_o(), .screen_refresh_req_o(), .screen_refresh_ack_i(1'b0), .screen_refresh_srfaddr_o(), .screen_refresh_dpytap_o()
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
  function automatic instr_word_t putst_enc(input reg_idx_t rs);
    putst_enc = 16'h01A0 | instr_word_t'(rs);
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
  task automatic check_breg(input string label, input int unsigned bidx, input logic [31:0] expected);
    if (u_core.u_regfile.b_regs[bidx] !== expected) begin
      $display("TEST_RESULT: FAIL: %s: B%0d expected=%08h actual=%08h",
               label, bidx, expected, u_core.u_regfile.b_regs[bidx]);
      failures++;
    end
  endtask

  localparam logic [31:0] A_PSIZE   = IO_BASE_ADDR + (IO_IDX_PSIZE   << 4);
  localparam logic [31:0] A_CONVSP  = IO_BASE_ADDR + (IO_IDX_CONVSP  << 4);
  localparam logic [31:0] A_CONVDP  = IO_BASE_ADDR + (IO_IDX_CONVDP  << 4);
  localparam logic [31:0] A_CONTROL = IO_BASE_ADDR + (IO_IDX_CONTROL << 4);
  localparam logic [15:0] CTRL_W3   = 16'(2'd3 << CTRL_W_LO);

  initial begin : main
    int unsigned p, i;
    failures = 0;
    for (i = 0; i < 256; i++) u_mem.mem[i] = 16'h0300;
    for (i = 120; i < 200; i++) u_mem.mem[i] = 16'h0000;
    u_mem.mem[128] = 16'h2211;  // source: pixels 0x11 (X=0), 0x22 (X=1)
    u_mem.mem[144] = 16'h0000;  // dest starts clear

    p = 0;
    p = place_word(p, setf_enc(5'd16, 1'b0, 1'b0));
    p = place_movi_il  (p, 4'd0, 32'h0000_0008);
    p = place_store_abs(p, 4'd0, A_PSIZE);               // PSIZE=8
    p = place_movi_il  (p, 4'd0, 32'h0000_001B);
    p = place_store_abs(p, 4'd0, A_CONVSP);              // CONVSP=0x1B
    p = place_movi_il  (p, 4'd0, 32'h0000_001B);
    p = place_store_abs(p, 4'd0, A_CONVDP);              // CONVDP=0x1B
    p = place_movi_il  (p, 4'd0, {16'h0, CTRL_W3});
    p = place_store_abs(p, 4'd0, A_CONTROL);             // CONTROL.W=3
    p = place_movi_il_b(p, 4'd0, 32'h0000_0000);         // SADDR XY (0,0)
    p = place_movi_il_b(p, 4'd1, 32'h0000_0080);         // SPTCH
    p = place_movi_il_b(p, 4'd2, 32'h0000_0020);         // DADDR XY (0x20,0)
    p = place_movi_il_b(p, 4'd3, 32'h0000_0080);         // DPTCH
    p = place_movi_il_b(p, 4'd4, 32'h0000_0800);         // OFFSET
    p = place_movi_il_b(p, 4'd5, 32'h0000_0020);         // WSTART XY (0x20,0)
    p = place_movi_il_b(p, 4'd6, 32'h0000_0020);         // WEND   XY (0x20,0)
    p = place_movi_il_b(p, 4'd7, 32'h0001_0002);         // DYDX (DY=1,DX=2)
    p = place_movi_il  (p, 4'd14, ST_SEED);
    p = place_word(p, putst_enc(4'd14));                 // NCZ=111, V=0
    p = place_word(p, 16'h0F60);                         // PIXBLT XY,XY
    p = place_word(p, getst_enc(4'd8));                  // preclipping sets V only
    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (3000) @(posedge clk);
    #1;

    // Dest: low pixel (X=0x20) written = 0x11; high pixel (X=0x21) clipped = 0.
    check_word("dst word144 clipped = 0x0011", 144, 16'h0011);
    check_word("src word128 unchanged = 0x2211", 128, 16'h2211);
    // SADDR / DADDR still advance over the full array (clip doesn't change them).
    check_breg("SADDR (B0) = 0x810", 0, 32'h0000_0810);
    check_breg("DADDR (B2) = 0x910", 2, 32'h0000_0910);
    if (u_core.u_regfile.a_regs[8] !== 32'hF000_0010) begin
      $display("TEST_RESULT: FAIL: W=3 clipped ST expected=F0000010 actual=%08h",
               u_core.u_regfile.a_regs[8]);
      failures++;
    end
    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set"); failures++;
    end

    if (failures == 0)
      $display("TEST_RESULT: PASS (PIXBLT XY W=3 clip and V-only preclipping status)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #3_000_000;
    $display("TEST_RESULT: FAIL: tb_pixblt_window hard timeout");
    $fatal(1);
  end
endmodule : tb_pixblt_window
