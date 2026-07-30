// -----------------------------------------------------------------------------
// tb_line.sv
//
// LINE Z=0 — Bresenham inner loop (SPVU001A page 12-99, encoding 0xDF1A).
// Draws COUNT pixels of COLOR1 along a line; the B-file holds the parameters.
//
// Vertical line (minor b=0, major=Y), 4 pixels downward. A vertical line keeps
// X constant so the X field (X<<3) never collides with the Y field (Y<<4) in
// the XY→linear conversion. PSIZE=8, CONVDP=0x1B (Y shift 4), OFFSET(B4)=0x800,
// COLOR1(B9)=0xAA.
//   DADDR(B2)=(X=0x20,Y=1); DYDX(B7)={b=0, a=3}; d(B0)=2b-a=-3; COUNT(B10)=4;
//   INC2(B12)=(X=0,Y=1) dominant +1 Y; INC1(B11)=(0,1) (unused for b=0).
// b=0 → d=-3 stays ≤0 → INC2 each step. Pixels at (0x20,1),(0x20,2),(0x20,3),
// (0x20,4) → words 145,146,147,148 each low byte = 0xAA (= 0x00AA).
// After: COUNT=0, DADDR=(0x20,5)=0x00050020, d still -3 (0xFFFFFFFD).
// A display interrupt is asserted after the first completed LINE pixel. The
// entry may be deferred until completion (Task 0167) or accepted at a future
// LINE checkpoint (Task 0168), but its stacked ST must never claim PBX.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_line;
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
  logic                          dpyint_set;
  logic                          saw_line_st_push;
  logic [DATA_WIDTH-1:0]         line_pushed_st;

  tms34010_core u_core (
    .clk(clk), .vclk_i(clk), .video_hsync_n_i(1'b1), .video_vsync_n_i(1'b1), .rst(rst), .vclk_rst_i(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_srt(), .mem_rdata(mem_rdata), .mem_ack(mem_ack),
    .state_o(state_w), .pc_o(pc_w), .instr_word_o(instr_w), .illegal_opcode_o(illegal_w), .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1), .lint2_n_i(1'b1), .hcs_n_i(1'b0), .host_req_i(1'b0), .host_we_i(1'b0), .host_reg_i(HOST_REG_HSTCTL), .host_be_i(2'b00), .host_wdata_i(16'h0000), .host_rdata_o(), .host_ack_o(), .host_busy_o(), .hint_n_o(), .host_mem_req_o(), .host_mem_we_o(), .host_mem_addr_o(), .host_mem_wdata_o(), .host_mem_rdata_i(16'h0000), .host_mem_ack_i(1'b0), .dpyint_set_i(dpyint_set), .refresh_req_o(), .refresh_row_o(), .refresh_cbr_o(), .video_hsync_o(), .video_vsync_o(), .video_hblank_o(), .video_vblank_o(), .video_blank_o(), .video_hsync_oe_o(), .video_vsync_oe_o(), .screen_refresh_req_o(), .screen_refresh_ack_i(1'b0), .screen_refresh_srfaddr_o(), .screen_refresh_dpytap_o()
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

  localparam logic [31:0] A_PSIZE  = IO_BASE_ADDR + (IO_IDX_PSIZE  << 4);
  localparam logic [31:0] A_CONVDP = IO_BASE_ADDR + (IO_IDX_CONVDP << 4);
  localparam logic [31:0] A_INTENB = IO_BASE_ADDR + (IO_IDX_INTENB << 4);
  localparam logic [31:0] A_INTPEND = IO_BASE_ADDR + (IO_IDX_INTPEND << 4);
  localparam logic [31:0] SP_INIT = 32'h0000_0E00;
  localparam logic [31:0] ISR_PC = 32'h0000_0D20;
  localparam int unsigned ISR_WORD = ISR_PC >> LOCAL_WORD_ADDR_LSB;
  localparam int unsigned DI_VEC_WORD =
      (INT_VEC_DI >> LOCAL_WORD_ADDR_LSB) & 8'hFF;

  always @(posedge clk) begin
    if (rst) begin
      saw_line_st_push <= 1'b0;
      line_pushed_st   <= '0;
    end else if ((state_w == CORE_INT_PUSH_ST) && mem_ack) begin
      saw_line_st_push <= 1'b1;
      line_pushed_st   <= mem_wdata;
    end
  end

  initial begin : main
    int unsigned p, i;
    failures = 0;
    dpyint_set = 1'b0;
    for (i = 0; i < 256; i++) u_mem.mem[i] = 16'h0300;
    for (i = 120; i < 200; i++) u_mem.mem[i] = 16'h0000;

    p = 0;
    p = place_movi_il  (p, 4'd2, SP_INIT);
    p = place_word(p, 16'h4C4F);                         // A15/SP <- A2
    p = place_movi_il  (p, 4'd0, 32'(1 << INT_DI_BIT));
    p = place_store_abs(p, 4'd0, A_INTENB);
    p = place_word(p, 16'h0D60);                         // EINT
    p = place_word(p, setf_enc(5'd16, 1'b0, 1'b0));      // FS0=16 for MOVE-to-I/O
    p = place_movi_il  (p, 4'd0, 32'h0000_0008);
    p = place_store_abs(p, 4'd0, A_PSIZE);               // PSIZE = 8
    p = place_movi_il  (p, 4'd0, 32'h0000_001B);
    p = place_store_abs(p, 4'd0, A_CONVDP);              // CONVDP = 0x1B
    // B-file line parameters (vertical line).
    p = place_movi_il_b(p, 4'd0,  32'hFFFF_FFFD);        // B0  d = -3
    p = place_movi_il_b(p, 4'd2,  32'h0001_0020);        // B2  DADDR (0x20,1)
    p = place_movi_il_b(p, 4'd4,  32'h0000_0800);        // B4  OFFSET
    p = place_movi_il_b(p, 4'd7,  32'h0000_0003);        // B7  DYDX {b=0,a=3}
    p = place_movi_il_b(p, 4'd9,  32'hAAAA_AAAA);        // B9 uniform COLOR1
    p = place_movi_il_b(p, 4'd10, 32'h0000_0004);        // B10 COUNT = 4
    p = place_movi_il_b(p, 4'd11, 32'h0001_0000);        // B11 INC1 (unused; b=0)
    p = place_movi_il_b(p, 4'd12, 32'h0001_0000);        // B12 INC2 (+1 Y)
    p = place_word(p, 16'hDF1A);                         // LINE 0

    // ---- Second line: 45° diagonal (a=b=2) to exercise the d>0 -> INC1 path.
    // CONVDP=0x19 (Y shift 6) + OFFSET=0x720 keeps X and Y fields non-overlapping
    // AND lands the pixels in the cleared data region (words 120-200), clear of
    // the program and the first line. d=2b-a=2 stays >0 (2b-2a=0), so every step
    // takes INC1=(1,1). 3 pixels: (4,1)->w120, (5,2)->w124, (6,3)->w129.
    p = place_movi_il  (p, 4'd0, 32'h0000_0019);
    p = place_store_abs(p, 4'd0, A_CONVDP);              // CONVDP = 0x19 (Y shift 6)
    p = place_movi_il_b(p, 4'd4,  32'h0000_0720);        // OFFSET = 0x720
    p = place_movi_il_b(p, 4'd0,  32'h0000_0002);        // d = 2b-a = 2
    p = place_movi_il_b(p, 4'd2,  32'h0001_0004);        // DADDR (4,1)
    p = place_movi_il_b(p, 4'd7,  32'h0002_0002);        // DYDX {b=2,a=2}
    p = place_movi_il_b(p, 4'd10, 32'h0000_0003);        // COUNT = 3
    p = place_movi_il_b(p, 4'd11, 32'h0001_0001);        // INC1 (1,1) diagonal
    p = place_movi_il_b(p, 4'd12, 32'h0001_0000);        // INC2 (0,1) (unused here)
    p = place_word(p, 16'hDF1A);                         // LINE 0
    p = place_word(p, 16'hC0FF);

    // Handler and aliased DI vector.
    p = ISR_WORD;
    p = place_movi_il(p, 4'd3, 32'd0);
    p = place_store_abs(p, 4'd3, A_INTPEND);
    p = place_movi_il(p, 4'd5, 32'h0000_BEEF);
    p = place_word(p, 16'h0940);
    u_mem.mem[DI_VEC_WORD] = ISR_PC[15:0];
    u_mem.mem[DI_VEC_WORD + 1] = ISR_PC[31:16];

    repeat (3) @(posedge clk);
    rst = 1'b0;
    wait ((state_w == CORE_LINE_DRAW) && mem_req && mem_ack);
    @(negedge clk);
    dpyint_set = 1'b1;
    @(negedge clk);
    dpyint_set = 1'b0;
    repeat (4000) @(posedge clk);
    #1;

    // Four pixels drawn, one per row: words 145..148 each low byte 0xAA.
    check_word("LINE: word145 = 0x00AA", 145, 16'h00AA);
    check_word("LINE: word146 = 0x00AA", 146, 16'h00AA);
    check_word("LINE: word147 = 0x00AA", 147, 16'h00AA);
    check_word("LINE: word148 = 0x00AA", 148, 16'h00AA);
    check_word("LINE: word149 untouched", 149, 16'h0000);
    // (The vertical line's B0/B2/B10 writebacks are overwritten by the second
    //  LINE below; its pixel words 145..148 persist and are checked above.)

    // Diagonal line pixels: (4,1)->word120 low, (5,2)->word124 high, (6,3)->word129 low.
    check_word("LINE diag: word120 = 0x00AA", 120, 16'h00AA);
    check_word("LINE diag: word124 = 0xAA00", 124, 16'hAA00);
    check_word("LINE diag: word129 = 0x00AA", 129, 16'h00AA);
    // Diagonal writebacks: COUNT=0, DADDR=(7,4), d stays 2.
    check_breg("LINE diag: B10 COUNT = 0",        10, 32'h0000_0000);
    check_breg("LINE diag: B2 DADDR = (7,4)",      2, 32'h0004_0007);
    check_breg("LINE diag: B0 d = 2",              0, 32'h0000_0002);
    if (!saw_line_st_push || line_pushed_st[ST_PBX_BIT] !== 1'b0
        || u_core.u_regfile.a_regs[5] !== 32'h0000_BEEF
        || u_core.u_regfile.sp_q !== SP_INIT) begin
      $display("TEST_RESULT: FAIL: LINE interrupt PBX/handler/SP ST=%08h seen=%0b A5=%08h SP=%08h",
               line_pushed_st, saw_line_st_push,
               u_core.u_regfile.a_regs[5], u_core.u_regfile.sp_q);
      failures++;
    end
    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set"); failures++;
    end

    if (failures == 0)
      $display("TEST_RESULT: PASS (LINE: 4-pixel Bresenham line drawn, d/DADDR/COUNT written back)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #4_000_000;
    $display("TEST_RESULT: FAIL: tb_line hard timeout");
    $fatal(1);
  end
endmodule : tb_line
