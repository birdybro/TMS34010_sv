// -----------------------------------------------------------------------------
// tb_fill_l.sv
//
// FILL L (fill array, linear) — Task 0087. The first multi-cycle graphics
// engine. FILL writes COLOR1 (B9) into a DY×DX pixel array (DYDX=B7) starting
// at DADDR (B2), with rows DPTCH (B3) bits apart; each pixel is a PSIZE-bit
// field write. DADDR is updated to the address following the last pixel.
// Replace mode (no window/PMASK/transparency/PPOP). SPVU001A 12-80. All flags
// Unaffected.
//
// Vector: DADDR=0x800, DPTCH=0x80, DYDX=0x00020004 (DY=2, DX=4), PSIZE=8,
// COLOR1=0xAA. Row 0 fills bits 0x800,0x808,0x810,0x818 -> words 128,129 =
// 0xAAAA; row 1 starts at 0x880 -> words 136,137 = 0xAAAA. Final DADDR =
// 0x800 + (2-1)*0x80 + 4*8 = 0x8A0.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_fill_l;
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

  sim_memory_model #(.DEPTH_WORDS(256)) u_mem (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack)
  );

  function automatic instr_word_t movi_il_enc(input reg_idx_t i);
    movi_il_enc = 16'h09E0 | instr_word_t'(i);   // A-file
  endfunction
  function automatic instr_word_t movi_il_b_enc(input reg_idx_t i);
    movi_il_b_enc = 16'h09F0 | instr_word_t'(i);  // B-file
  endfunction
  function automatic instr_word_t setf_enc(input logic [4:0] fs,
                                           input logic fe, input logic f_sel);
    setf_enc = 16'b0000_0100_0000_0000
             | (instr_word_t'(f_sel) << 9) | 16'b0000_0001_0000_0000
             | 16'b0000_0000_0100_0000 | (instr_word_t'(fe) << 5)
             | instr_word_t'(fs);
  endfunction

  function automatic int unsigned place_movi_il(input int unsigned p,
                                                input reg_idx_t i,
                                                input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]     = movi_il_enc(i);
    u_mem.mem[p + 1] = imm[15:0];
    u_mem.mem[p + 2] = imm[31:16];
    place_movi_il = p + 3;
  endfunction
  function automatic int unsigned place_movi_il_b(input int unsigned p,
                                                  input reg_idx_t i,
                                                  input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]     = movi_il_b_enc(i);
    u_mem.mem[p + 1] = imm[15:0];
    u_mem.mem[p + 2] = imm[31:16];
    place_movi_il_b = p + 3;
  endfunction
  function automatic int unsigned place_word(input int unsigned p, input instr_word_t w);
    u_mem.mem[p] = w;  place_word = p + 1;
  endfunction
  function automatic int unsigned place_store_abs(input int unsigned p,
                                                  input reg_idx_t rs,
                                                  input logic [31:0] addr);
    u_mem.mem[p]     = 16'h0580 | instr_word_t'(rs);
    u_mem.mem[p + 1] = addr[15:0];
    u_mem.mem[p + 2] = addr[31:16];
    place_store_abs = p + 3;
  endfunction

  int unsigned failures;
  task automatic check_word(input string label, input int unsigned widx,
                            input logic [15:0] expected);
    if (u_mem.mem[widx] !== expected) begin
      $display("TEST_RESULT: FAIL: %s: mem[%0d] expected=%04h actual=%04h",
               label, widx, expected, u_mem.mem[widx]);
      failures++;
    end
  endtask

  localparam logic [31:0] A_PSIZE = IO_BASE_ADDR + (IO_IDX_PSIZE << 4);

  initial begin : main
    int unsigned p, i;
    failures = 0;
    for (i = 0; i < 256; i++) u_mem.mem[i] = 16'h0300;   // NOP fill
    for (i = 120; i < 200; i++) u_mem.mem[i] = 16'h0000;

    p = 0;
    p = place_word(p, setf_enc(5'd16, 1'b0, 1'b0));      // FS0=16 for MOVE-to-PSIZE
    p = place_movi_il  (p, 4'd0, 32'h0000_0008);
    p = place_store_abs(p, 4'd0, A_PSIZE);               // PSIZE = 8
    p = place_movi_il_b(p, 4'd2, 32'h0000_0800);         // DADDR (B2)
    p = place_movi_il_b(p, 4'd3, 32'h0000_0080);         // DPTCH (B3)
    p = place_movi_il_b(p, 4'd7, 32'h0002_0004);         // DYDX (B7): DY=2, DX=4
    p = place_movi_il_b(p, 4'd9, 32'h0000_00AA);         // COLOR1 (B9)
    p = place_word(p, 16'h0FC0);                         // FILL L

    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (3000) @(posedge clk);
    #1;

    // Row 0 (words 128,129) and row 1 (words 136,137) filled with 0xAA pixels.
    check_word("row0 word128 = 0xAAAA", 128, 16'hAAAA);
    check_word("row0 word129 = 0xAAAA", 129, 16'hAAAA);
    check_word("row1 word136 = 0xAAAA", 136, 16'hAAAA);
    check_word("row1 word137 = 0xAAAA", 137, 16'hAAAA);
    // Gap between rows (words 130..135) untouched.
    check_word("gap word130 = 0", 130, 16'h0000);
    check_word("gap word135 = 0", 135, 16'h0000);
    // DADDR (B2) updated to the pixel following the last (0x8A0).
    if (u_core.u_regfile.b_regs[2] !== 32'h0000_08A0) begin
      $display("TEST_RESULT: FAIL: DADDR(B2) = %08h, expected 000008A0",
               u_core.u_regfile.b_regs[2]);
      failures++;
    end

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (FILL L: 2x4 pixel array filled with COLOR1, DADDR updated)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #3_000_000;
    $display("TEST_RESULT: FAIL: tb_fill_l hard timeout");
    $fatal(1);
  end

endmodule : tb_fill_l
