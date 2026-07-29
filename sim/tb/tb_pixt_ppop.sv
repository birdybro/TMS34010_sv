// -----------------------------------------------------------------------------
// tb_pixt_ppop.sv
//
// PIXT store Boolean pixel processing (PPOP) — Task 0091. CONTROL.PPOP
// (bits 14-10) selects one of 16 Boolean operations applied to the source and
// destination pixels: processed = f(S, D); the result is then plane-masked and
// transparency-checked before the write. SPVU001A CONTROL.PPOP. PSIZE=8.
//
// Each case pre-loads a destination pixel D, stores a source S with a chosen
// PPOP, and checks the resulting 8-bit pixel. S = 0xCC, D = 0xAA throughout
// (so the bitwise results are distinct).
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_pixt_ppop;
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

  // Build one PIXT-with-PPOP case: set CONTROL=PPOP<<10, load src/ptr, store.
  // dest_word holds the destination pixel pre-loaded into the target word.
  int unsigned p;
  function automatic int unsigned place_case(input int unsigned pp,
                                             input logic [4:0]  ppop,
                                             input reg_idx_t    rs_reg,
                                             input reg_idx_t    rd_reg,
                                             input logic [31:0] dst_addr);
    pp = place_movi_il  (pp, 4'd0, {16'h0, 1'b0, ppop, 10'h0});  // CONTROL = PPOP<<10
    pp = place_store_abs(pp, 4'd0, A_CONTROL);
    pp = place_movi_il  (pp, rs_reg, 32'h0000_00CC);             // S = 0xCC
    pp = place_movi_il  (pp, rd_reg, dst_addr);                  // pointer
    pp = place_word(pp, pixt_store_enc(rs_reg, rd_reg));
    place_case = pp;
  endfunction

  initial begin : main
    int unsigned i;
    failures = 0;
    for (i = 0; i < 256; i++) u_mem.mem[i] = 16'h0300;   // NOP fill
    for (i = 120; i < 200; i++) u_mem.mem[i] = 16'h0000;
    // Pre-load destination pixels D = 0xAA at the target words.
    u_mem.mem[128] = 16'h00AA;  // 0x800: replace
    u_mem.mem[129] = 16'h00AA;  // 0x810: S AND D
    u_mem.mem[130] = 16'h00AA;  // 0x820: S OR D
    u_mem.mem[131] = 16'h00AA;  // 0x830: S XOR D
    u_mem.mem[132] = 16'h00AA;  // 0x840: ~S (NOT source)
    u_mem.mem[133] = 16'h00AA;  // 0x850: no change (D)

    p = 0;
    p = place_word(p, setf_enc(5'd16, 1'b0, 1'b0));      // FS0=16 for MOVE-to-I/O
    p = place_movi_il  (p, 4'd0, 32'h0000_0008);
    p = place_store_abs(p, 4'd0, A_PSIZE);               // PSIZE = 8

    // S=0xCC, D=0xAA. Expected pixels:
    //   replace (0x00): 0xCC ;  S AND D (0x01): 0x88 ;  S OR D (0x08): 0xEE ;
    //   S XOR D (0x0A): 0x66 ;  ~S (0x0F): 0x33 ;  no change (0x09): 0xAA.
    p = place_case(p, 5'h00, 4'd1, 4'd2,  32'h0000_0800);
    p = place_case(p, 5'h01, 4'd3, 4'd4,  32'h0000_0810);
    p = place_case(p, 5'h08, 4'd5, 4'd6,  32'h0000_0820);
    p = place_case(p, 5'h0A, 4'd7, 4'd8,  32'h0000_0830);
    p = place_case(p, 5'h0F, 4'd9, 4'd10, 32'h0000_0840);
    p = place_case(p, 5'h09, 4'd11,4'd12, 32'h0000_0850);

    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (4000) @(posedge clk);
    #1;

    check_word("replace  (S)     -> 0x00CC", 128, 16'h00CC);
    check_word("S AND D          -> 0x0088", 129, 16'h0088);
    check_word("S OR D           -> 0x00EE", 130, 16'h00EE);
    check_word("S XOR D          -> 0x0066", 131, 16'h0066);
    check_word("~S (NOT source)  -> 0x0033", 132, 16'h0033);
    check_word("no change (D)    -> 0x00AA", 133, 16'h00AA);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (PIXT PPOP boolean: replace/AND/OR/XOR/NOT-S/no-change per CONTROL.PPOP)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #4_000_000;
    $display("TEST_RESULT: FAIL: tb_pixt_ppop hard timeout");
    $fatal(1);
  end

endmodule : tb_pixt_ppop
