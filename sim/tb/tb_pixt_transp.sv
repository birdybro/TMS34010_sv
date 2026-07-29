// -----------------------------------------------------------------------------
// tb_pixt_transp.sv
//
// PIXT store transparency (Task 0089). When CONTROL.T (bit 5) is set, a PIXT
// store whose source pixel is 0 (in replace mode the processed value equals
// the source) is inhibited from overwriting the destination — the write is
// skipped. With T=0 a 0 pixel overwrites normally; a nonzero pixel always
// writes. SPVU001A CONTROL.T.
//
// PSIZE=8. Destination words are pre-loaded with 0x00FF so a skipped write
// leaves the low byte intact (0xFF) while a performed write clears it.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_pixt_transp;
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
    .clk(clk), .vclk_i(clk), .video_hsync_n_i(1'b1), .video_vsync_n_i(1'b1), .rst(rst), .vclk_rst_i(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_srt(), .mem_rdata(mem_rdata), .mem_ack(mem_ack),
    .state_o(state_w), .pc_o(pc_w), .instr_word_o(instr_w), .illegal_opcode_o(illegal_w), .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1), .lint2_n_i(1'b1), .hcs_n_i(1'b0), .host_req_i(1'b0), .host_we_i(1'b0), .host_reg_i(HOST_REG_HSTCTL), .host_be_i(2'b00), .host_wdata_i(16'h0000), .host_rdata_o(), .host_ack_o(), .host_busy_o(), .hint_n_o(), .host_mem_req_o(), .host_mem_we_o(), .host_mem_addr_o(), .host_mem_wdata_o(), .host_mem_rdata_i(16'h0000), .host_mem_ack_i(1'b0), .dpyint_set_i(1'b0), .refresh_req_o(), .refresh_row_o(), .refresh_cbr_o(), .video_hsync_o(), .video_vsync_o(), .video_hblank_o(), .video_vblank_o(), .video_blank_o(), .video_hsync_oe_o(), .video_vsync_oe_o(), .screen_refresh_req_o(), .screen_refresh_ack_i(1'b0), .screen_refresh_srfaddr_o(), .screen_refresh_dpytap_o()
  );

  sim_memory_model #(.DEPTH_WORDS(256)) u_mem (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack)
  );

  function automatic instr_word_t movi_il_enc(input reg_idx_t i);
    movi_il_enc = 16'h09E0 | instr_word_t'(i);
  endfunction
  function automatic instr_word_t setf_enc(input logic [4:0] fs,
                                           input logic fe, input logic f_sel);
    setf_enc = 16'b0000_0100_0000_0000
             | (instr_word_t'(f_sel) << 9) | 16'b0000_0001_0000_0000
             | 16'b0000_0000_0100_0000 | (instr_word_t'(fe) << 5)
             | instr_word_t'(fs);
  endfunction
  function automatic instr_word_t pixt_store_enc(input reg_idx_t rs, input reg_idx_t rd);
    pixt_store_enc = 16'hF800 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
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

  localparam logic [31:0] A_PSIZE   = IO_BASE_ADDR + (IO_IDX_PSIZE   << 4);
  localparam logic [31:0] A_CONTROL = IO_BASE_ADDR + (IO_IDX_CONTROL << 4);
  localparam logic [15:0] T_ON      = 16'h0020;   // CONTROL.T (bit 5)

  initial begin : main
    int unsigned p, i;
    failures = 0;
    for (i = 0; i < 256; i++) u_mem.mem[i] = 16'h0300;   // NOP fill
    for (i = 120; i < 200; i++) u_mem.mem[i] = 16'h0000;
    // Pre-load destination words with 0x00FF so a skip preserves the low byte.
    u_mem.mem[128] = 16'h00FF;   // case 1 dest (bit 0x800)
    u_mem.mem[129] = 16'h00FF;   // case 2 dest (bit 0x810)

    p = 0;
    p = place_word(p, setf_enc(5'd16, 1'b0, 1'b0));      // FS0=16 for MOVE-to-I/O
    p = place_movi_il  (p, 4'd0, 32'h0000_0008);
    p = place_store_abs(p, 4'd0, A_PSIZE);               // PSIZE = 8
    // 1) T=1, zero pixel -> SKIP (dest word128 stays 0x00FF).
    p = place_movi_il  (p, 4'd0, 32'h0000_0020);
    p = place_store_abs(p, 4'd0, A_CONTROL);             // CONTROL.T = 1
    p = place_movi_il  (p, 4'd1, 32'h0000_0000);         // zero pixel
    p = place_movi_il  (p, 4'd2, 32'h0000_0800);
    p = place_word(p, pixt_store_enc(4'd1, 4'd2));       // transparent -> skip
    // 2) T=0, zero pixel -> WRITES 0 (dest word129 low byte cleared).
    p = place_movi_il  (p, 4'd0, 32'h0000_0000);
    p = place_store_abs(p, 4'd0, A_CONTROL);             // CONTROL.T = 0
    p = place_movi_il  (p, 4'd3, 32'h0000_0000);
    p = place_movi_il  (p, 4'd4, 32'h0000_0810);
    p = place_word(p, pixt_store_enc(4'd3, 4'd4));       // writes 0
    // 3) T=1, nonzero pixel -> WRITES (dest word130 = 0x00C3).
    p = place_movi_il  (p, 4'd0, 32'h0000_0020);
    p = place_store_abs(p, 4'd0, A_CONTROL);             // CONTROL.T = 1
    p = place_movi_il  (p, 4'd5, 32'h0000_00C3);
    p = place_movi_il  (p, 4'd6, 32'h0000_0820);
    p = place_word(p, pixt_store_enc(4'd5, 4'd6));       // 0xC3 nonzero -> writes

    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (3000) @(posedge clk);
    #1;

    check_word("1: T=1 zero pixel skipped -> word128 = 0x00FF", 128, 16'h00FF);
    check_word("2: T=0 zero pixel written  -> word129 = 0x0000", 129, 16'h0000);
    check_word("3: T=1 nonzero pixel written -> word130 = 0x00C3", 130, 16'h00C3);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (PIXT transparency: T=1 skips 0 pixels, T=0 writes them, nonzero always writes)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #3_000_000;
    $display("TEST_RESULT: FAIL: tb_pixt_transp hard timeout");
    $fatal(1);
  end

endmodule : tb_pixt_transp
