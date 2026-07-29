// -----------------------------------------------------------------------------
// tb_pixblt_ll.sv
//
// PIXBLT L,L (0x0F00) — Task 0094. Transfer a DY×DX source pixel array
// (SADDR=B0, rows SPTCH=B1 apart) to a destination array (DADDR=B2, rows
// DPTCH=B3 apart), processing each pixel through the CONTROL pixel engine.
// SADDR and DADDR are updated to the pixel following their last. SPVU001A
// PIXBLT L,L. PSIZE=8, replace mode (verifies the transfer + register updates).
//
// Source row 0 (word128/129) = pixels 0x11,0x22,0x33,0x44; row 1 (word136/137)
// = 0x55,0x66,0x77,0x88. Dest at 0x900 -> words 144,145 (row 0) and 152,153
// (row 1, +DPTCH 0x80). SADDR final = 0x8A0, DADDR final = 0x9A0.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_pixblt_ll;
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
  task automatic check_breg(input string label, input int unsigned bidx,
                            input logic [DATA_WIDTH-1:0] expected);
    if (u_core.u_regfile.b_regs[bidx] !== expected) begin
      $display("TEST_RESULT: FAIL: %s: B%0d expected=%08h actual=%08h",
               label, bidx, expected, u_core.u_regfile.b_regs[bidx]);
      failures++;
    end
  endtask

  localparam logic [31:0] A_PSIZE = IO_BASE_ADDR + (IO_IDX_PSIZE << 4);

  initial begin : main
    int unsigned p, i;
    failures = 0;
    for (i = 0; i < 256; i++) u_mem.mem[i] = 16'h0300;   // NOP fill
    for (i = 120; i < 200; i++) u_mem.mem[i] = 16'h0000;
    // Source pixel array.
    u_mem.mem[128] = 16'h2211;  // row0: 0x11, 0x22
    u_mem.mem[129] = 16'h4433;  //       0x33, 0x44
    u_mem.mem[136] = 16'h6655;  // row1: 0x55, 0x66
    u_mem.mem[137] = 16'h8877;  //       0x77, 0x88

    p = 0;
    p = place_word(p, setf_enc(5'd16, 1'b0, 1'b0));      // FS0=16 for MOVE-to-I/O
    p = place_movi_il  (p, 4'd0, 32'h0000_0008);
    p = place_store_abs(p, 4'd0, A_PSIZE);               // PSIZE = 8
    p = place_movi_il_b(p, 4'd0, 32'h0000_0800);         // SADDR (B0)
    p = place_movi_il_b(p, 4'd1, 32'h0000_0080);         // SPTCH (B1)
    p = place_movi_il_b(p, 4'd2, 32'h0000_0900);         // DADDR (B2)
    p = place_movi_il_b(p, 4'd3, 32'h0000_0080);         // DPTCH (B3)
    p = place_movi_il_b(p, 4'd7, 32'h0002_0004);         // DYDX (B7): DY=2, DX=4
    p = place_word(p, 16'h0F00);                         // PIXBLT L,L

    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (4000) @(posedge clk);
    #1;

    // Destination row 0 (words 144,145) and row 1 (words 152,153) = source.
    check_word("dst row0 word144 = 0x2211", 144, 16'h2211);
    check_word("dst row0 word145 = 0x4433", 145, 16'h4433);
    check_word("dst row1 word152 = 0x6655", 152, 16'h6655);
    check_word("dst row1 word153 = 0x8877", 153, 16'h8877);
    // Source unchanged.
    check_word("src word128 = 0x2211 (unchanged)", 128, 16'h2211);
    // SADDR / DADDR updated to the pixel following the last.
    check_breg("SADDR (B0) = 0x8A0", 0, 32'h0000_08A0);
    check_breg("DADDR (B2) = 0x9A0", 2, 32'h0000_09A0);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (PIXBLT L,L: 2x4 source array transferred to dest, SADDR/DADDR updated)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #4_000_000;
    $display("TEST_RESULT: FAIL: tb_pixblt_ll hard timeout");
    $fatal(1);
  end

endmodule : tb_pixblt_ll
