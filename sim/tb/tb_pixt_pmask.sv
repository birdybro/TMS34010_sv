// -----------------------------------------------------------------------------
// tb_pixt_pmask.sv
//
// PIXT store plane masking (Task 0090). PMASK protects planes (bits) of the
// destination pixel: a PMASK bit of 1 leaves that plane unchanged. A PIXT
// store reads the destination pixel, then writes
//   merged = (src & ~pmask) | (dest & pmask)
// confined to the PSIZE-bit pixel. SPVU001A PMASK. With PMASK=0 the full
// source is written (covered by the existing PIXT tests); this test exercises
// nonzero masks.
//
// PSIZE=8. Destination pre-loaded so the masked planes are visible.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_pixt_pmask;
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

  localparam logic [31:0] A_PSIZE = IO_BASE_ADDR + (IO_IDX_PSIZE << 4);
  localparam logic [31:0] A_PMASK = IO_BASE_ADDR + (IO_IDX_PMASK << 4);

  initial begin : main
    int unsigned p, i;
    failures = 0;
    for (i = 0; i < 256; i++) u_mem.mem[i] = 16'h0300;   // NOP fill
    for (i = 120; i < 200; i++) u_mem.mem[i] = 16'h0000;
    // Pre-load destination pixels (each an 8-bit pixel at a word boundary).
    u_mem.mem[128] = 16'h00F0;   // dest pixel = 0xF0 (bit 0x800)
    u_mem.mem[129] = 16'h003C;   // dest pixel = 0x3C (bit 0x810)

    p = 0;
    p = place_word(p, setf_enc(5'd16, 1'b0, 1'b0));      // FS0=16 for MOVE-to-I/O
    p = place_movi_il  (p, 4'd0, 32'h0000_0008);
    p = place_store_abs(p, 4'd0, A_PSIZE);               // PSIZE = 8
    // 1) PMASK = 0x0F (low nibble protected). Store src=0xAA over dest=0xF0:
    //    merged = (0xAA & 0xF0) | (0xF0 & 0x0F) = 0xA0 | 0x00 = 0xA0.
    p = place_movi_il  (p, 4'd0, 32'h0000_000F);
    p = place_store_abs(p, 4'd0, A_PMASK);               // PMASK = 0x0F
    p = place_movi_il  (p, 4'd1, 32'h0000_00AA);         // source pixel
    p = place_movi_il  (p, 4'd2, 32'h0000_0800);         // dest 0 (word128)
    p = place_word(p, pixt_store_enc(4'd1, 4'd2));
    // 2) PMASK = 0xF0 (high nibble protected). Store src=0xAA over dest=0x3C:
    //    merged = (0xAA & 0x0F) | (0x3C & 0xF0) = 0x0A | 0x30 = 0x3A.
    p = place_movi_il  (p, 4'd0, 32'h0000_00F0);
    p = place_store_abs(p, 4'd0, A_PMASK);               // PMASK = 0xF0
    p = place_movi_il  (p, 4'd3, 32'h0000_0800);         // dest 1 (word129)... fix below
    p = place_movi_il  (p, 4'd4, 32'h0000_0810);
    p = place_word(p, pixt_store_enc(4'd1, 4'd4));       // src=0xAA at word129

    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (3000) @(posedge clk);
    #1;

    // 1) low nibble protected: 0xF0 dest, 0xAA src -> 0xA0.
    check_word("1: PMASK=0x0F -> word128 = 0x00A0", 128, 16'h00A0);
    // 2) high nibble protected: 0x3C dest, 0xAA src -> 0x3A.
    check_word("2: PMASK=0xF0 -> word129 = 0x003A", 129, 16'h003A);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (PIXT PMASK: protected planes keep dest, unmasked planes take source)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #3_000_000;
    $display("TEST_RESULT: FAIL: tb_pixt_pmask hard timeout");
    $fatal(1);
  end

endmodule : tb_pixt_pmask
