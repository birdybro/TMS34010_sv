// -----------------------------------------------------------------------------
// tb_modu.sv
//
// MODU Rs,Rd — unsigned 32-bit modulo: Rd mod Rs -> Rd (remainder). Per
// SPVU001A page 12-113. Encoding 0110 111S SSSR DDDD (0x6E00). Reuses the
// multi-cycle divider (CORE_DIVIDE), taking the remainder. Status:
// N/C Unaffected; Z = (remainder==0); V = 1 if Rs=0 (in which case Rd is
// unchanged and Z is left Unaffected).
//
// Cases: normal (Z=0), exact division (Z=1), and Rs=0 (V=1, Rd unchanged,
// Z unaffected — checked by leaving Z=0 from the previous op and confirming
// it stays 0 even though the remainder is 0).
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_modu;
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

  sim_memory_model #(.DEPTH_WORDS(128)) u_mem (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack)
  );

  function automatic instr_word_t movi_il_enc(input reg_idx_t i);
    movi_il_enc = 16'h09E0 | instr_word_t'(i);   // A-file
  endfunction
  function automatic instr_word_t modu_enc(input reg_idx_t rs, input reg_idx_t rd);
    modu_enc = 16'h6E00 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
  endfunction
  function automatic instr_word_t getst_b_enc(input reg_idx_t rd);
    getst_b_enc = 16'h0190 | instr_word_t'(rd);   // GETST B<rd>
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

  int unsigned failures;
  task automatic check_reg(input string label,
                           input logic [DATA_WIDTH-1:0] actual, expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%08h actual=%08h", label, expected, actual);
      failures++;
    end
  endtask
  task automatic check_bit(input string label, input logic actual, expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%0b actual=%0b", label, expected, actual);
      failures++;
    end
  endtask

  initial begin : main
    int unsigned p, i;
    failures = 0;
    for (i = 0; i < 128; i++) u_mem.mem[i] = 16'h0300;

    p = 0;
    // 1) normal: A0=17, A1=5 -> 17 mod 5 = 2. Z=0, V=0.  (Leaves ST.Z=0.)
    p = place_movi_il(p, 4'd0, 32'd17);
    p = place_movi_il(p, 4'd1, 32'd5);
    p = place_word(p, modu_enc(4'd1, 4'd0));
    p = place_word(p, getst_b_enc(4'd2));
    // 2) Rs=0: A4=7, A5=0 -> V=1, A4 unchanged, Z UNAFFECTED. Load A5=0
    //    first (sets Z=1) then A4=7 LAST (sets Z=0), so Z=0 enters the
    //    MODU; if Z were (mistakenly) written it would become 1 (remainder
    //    on Rs=0 is 0). Verifying Z stays 0 confirms it is left unaffected.
    p = place_movi_il(p, 4'd5, 32'd0);
    p = place_movi_il(p, 4'd4, 32'd7);
    p = place_word(p, modu_enc(4'd5, 4'd4));
    p = place_word(p, getst_b_enc(4'd0));
    // 3) exact: A2=20, A3=5 -> 0. Z=1, V=0.
    p = place_movi_il(p, 4'd2, 32'd20);
    p = place_movi_il(p, 4'd3, 32'd5);
    p = place_word(p, modu_enc(4'd3, 4'd2));
    p = place_word(p, getst_b_enc(4'd1));

    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (2000) @(posedge clk);
    #1;

    // 1) normal.
    check_reg("1: A0 = 17 mod 5 = 2", u_core.u_regfile.a_regs[0], 32'd2);
    check_bit("1: Z=0", u_core.u_regfile.b_regs[2][ST_Z_BIT], 1'b0);
    check_bit("1: V=0", u_core.u_regfile.b_regs[2][ST_V_BIT], 1'b0);
    // 2) Rs=0.
    check_reg("2: A4 unchanged (=7)", u_core.u_regfile.a_regs[4], 32'd7);
    check_bit("2: V=1 (Rs=0)", u_core.u_regfile.b_regs[0][ST_V_BIT], 1'b1);
    check_bit("2: Z unaffected (still 0)", u_core.u_regfile.b_regs[0][ST_Z_BIT], 1'b0);
    // 3) exact.
    check_reg("3: A2 = 20 mod 5 = 0", u_core.u_regfile.a_regs[2], 32'd0);
    check_bit("3: Z=1", u_core.u_regfile.b_regs[1][ST_Z_BIT], 1'b1);
    check_bit("3: V=0", u_core.u_regfile.b_regs[1][ST_V_BIT], 1'b0);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (MODU: remainder + Z/V, Z unaffected on Rs=0)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_modu hard timeout");
    $fatal(1);
  end

endmodule : tb_modu
