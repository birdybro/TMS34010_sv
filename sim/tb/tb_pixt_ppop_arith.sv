// -----------------------------------------------------------------------------
// tb_pixt_ppop_arith.sv
//
// PIXT store arithmetic pixel processing (PPOP 0x10-0x15) — Task 0092. The six
// arithmetic CONTROL.PPOP ops operate on the unsigned PSIZE-bit pixel values:
//   0x10 D+S (wrap), 0x11 ADDS (add, saturate to all-1s), 0x12 D-S (wrap),
//   0x13 SUBS (subtract, saturate to 0), 0x14 MAX(D,S), 0x15 MIN(D,S).
// SPVU001A CONTROL.PPOP. PSIZE=8. Each case pre-loads a destination pixel D,
// stores a source S, and checks the resulting 8-bit pixel.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_pixt_ppop_arith;
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

  function automatic int unsigned place_case(input int unsigned pp,
                                             input logic [4:0]  ppop,
                                             input logic [31:0] s_val,
                                             input reg_idx_t    rs_reg,
                                             input reg_idx_t    rd_reg,
                                             input logic [31:0] dst_addr);
    pp = place_movi_il  (pp, 4'd0, {16'h0, 1'b0, ppop, 10'h0});  // CONTROL = PPOP<<10
    pp = place_store_abs(pp, 4'd0, A_CONTROL);
    pp = place_movi_il  (pp, rs_reg, s_val);
    pp = place_movi_il  (pp, rd_reg, dst_addr);
    pp = place_word(pp, pixt_store_enc(rs_reg, rd_reg));
    place_case = pp;
  endfunction

  int unsigned p;
  initial begin : main
    int unsigned i;
    failures = 0;
    for (i = 0; i < 256; i++) u_mem.mem[i] = 16'h0300;   // NOP fill
    for (i = 120; i < 200; i++) u_mem.mem[i] = 16'h0000;
    // Pre-load destination pixels D.
    u_mem.mem[128] = 16'h0030;  // ADD : D=0x30
    u_mem.mem[129] = 16'h00F0;  // ADDS: D=0xF0
    u_mem.mem[130] = 16'h0050;  // SUB : D=0x50
    u_mem.mem[131] = 16'h0020;  // SUBS: D=0x20
    u_mem.mem[132] = 16'h0030;  // MAX : D=0x30
    u_mem.mem[133] = 16'h0030;  // MIN : D=0x30

    p = 0;
    p = place_word(p, setf_enc(5'd16, 1'b0, 1'b0));      // FS0=16 for MOVE-to-I/O
    p = place_movi_il  (p, 4'd0, 32'h0000_0008);
    p = place_store_abs(p, 4'd0, A_PSIZE);               // PSIZE = 8

    p = place_case(p, 5'h10, 32'h0000_0040, 4'd1, 4'd2,  32'h0000_0800); // 0x30+0x40=0x70
    p = place_case(p, 5'h11, 32'h0000_0030, 4'd3, 4'd4,  32'h0000_0810); // 0xF0+0x30 sat 0xFF
    p = place_case(p, 5'h12, 32'h0000_0020, 4'd5, 4'd6,  32'h0000_0820); // 0x50-0x20=0x30
    p = place_case(p, 5'h13, 32'h0000_0050, 4'd7, 4'd8,  32'h0000_0830); // 0x20-0x50 sat 0x00
    p = place_case(p, 5'h14, 32'h0000_0080, 4'd9, 4'd10, 32'h0000_0840); // max(0x30,0x80)=0x80
    p = place_case(p, 5'h15, 32'h0000_0080, 4'd11,4'd12, 32'h0000_0850); // min(0x30,0x80)=0x30

    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (4000) @(posedge clk);
    #1;

    check_word("ADD  0x30+0x40       -> 0x0070", 128, 16'h0070);
    check_word("ADDS 0xF0+0x30 sat   -> 0x00FF", 129, 16'h00FF);
    check_word("SUB  0x50-0x20       -> 0x0030", 130, 16'h0030);
    check_word("SUBS 0x20-0x50 sat   -> 0x0000", 131, 16'h0000);
    check_word("MAX  max(0x30,0x80)  -> 0x0080", 132, 16'h0080);
    check_word("MIN  min(0x30,0x80)  -> 0x0030", 133, 16'h0030);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (PIXT PPOP arith: ADD/ADDS/SUB/SUBS/MAX/MIN with saturation)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #4_000_000;
    $display("TEST_RESULT: FAIL: tb_pixt_ppop_arith hard timeout");
    $fatal(1);
  end

endmodule : tb_pixt_ppop_arith
