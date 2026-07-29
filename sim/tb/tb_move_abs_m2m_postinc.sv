// -----------------------------------------------------------------------------
// tb_move_abs_m2m_postinc.sv
//
// End-to-end coverage for:
//   MOVE @SAddress,*Rd+ [,F] = 1101 01F0 000R DDDD + source LO16 + HI16
//
// An FS-bit field is read from the absolute bit address and written through
// the original Rd; Rd then advances by FS. FE and N/C/Z/V are unaffected.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_move_abs_m2m_postinc;
  import tms34010_pkg::*;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  logic                        mem_req;
  logic                        mem_we;
  logic [ADDR_WIDTH-1:0]       mem_addr;
  logic [FIELD_SIZE_WIDTH-1:0] mem_size;
  logic [DATA_WIDTH-1:0]       mem_wdata;
  logic [DATA_WIDTH-1:0]       mem_rdata;
  logic                        mem_ack;
  core_state_t                 state_w;
  logic [ADDR_WIDTH-1:0]       pc_w;
  instr_word_t                 instr_w;
  logic                        illegal_w;
  logic                        saw_high_source;

  tms34010_core u_core (
    .clk(clk), .vclk_i(clk), .video_hsync_n_i(1'b1), .video_vsync_n_i(1'b1), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
    .mem_size(mem_size), .mem_wdata(mem_wdata), .mem_srt(), .mem_rdata(mem_rdata),
    .mem_ack(mem_ack), .state_o(state_w), .pc_o(pc_w),
    .instr_word_o(instr_w), .illegal_opcode_o(illegal_w), .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1), .lint2_n_i(1'b1), .hcs_n_i(1'b0), .host_req_i(1'b0), .host_we_i(1'b0), .host_reg_i(HOST_REG_HSTCTL), .host_be_i(2'b00), .host_wdata_i(16'h0000), .host_rdata_o(), .host_ack_o(), .host_busy_o(), .hint_n_o(), .host_mem_req_o(), .host_mem_we_o(), .host_mem_addr_o(), .host_mem_wdata_o(), .host_mem_rdata_i(16'h0000), .host_mem_ack_i(1'b0), .dpyint_set_i(1'b0), .refresh_req_o(), .refresh_row_o(), .refresh_cbr_o(), .video_hsync_o(), .video_vsync_o(), .video_hblank_o(), .video_vblank_o(), .video_blank_o(), .video_hsync_oe_o(), .video_vsync_oe_o(), .screen_refresh_req_o(), .screen_refresh_ack_i(1'b0), .screen_refresh_srfaddr_o(), .screen_refresh_dpytap_o()
  );

  sim_memory_model #(.DEPTH_WORDS(512)) u_mem (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
    .mem_size(mem_size), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
    .mem_ack(mem_ack)
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      saw_high_source <= 1'b0;
    end else if (mem_req && !mem_we && mem_addr == 32'h1234_0C0B) begin
      saw_high_source <= 1'b1;
    end
  end

  function automatic instr_word_t movi_il_enc(input reg_file_t rf,
                                              input reg_idx_t rd);
    movi_il_enc = 16'h09E0
                | (instr_word_t'(rf) << 4)
                | instr_word_t'(rd);
  endfunction

  function automatic instr_word_t putst_enc(input reg_idx_t rs);
    putst_enc = 16'h01A0 | instr_word_t'(rs);
  endfunction

  function automatic instr_word_t getst_enc(input reg_file_t rf,
                                            input reg_idx_t rd);
    getst_enc = 16'h0180
              | (instr_word_t'(rf) << 4)
              | instr_word_t'(rd);
  endfunction

  function automatic instr_word_t move_enc(input logic f_sel,
                                           input reg_file_t rf,
                                           input reg_idx_t rd);
    move_enc = 16'hD400
             | (instr_word_t'(f_sel) << 9)
             | (instr_word_t'(rf) << 4)
             | instr_word_t'(rd);
  endfunction

  function automatic int unsigned place_movi(input int unsigned p,
                                             input reg_file_t rf,
                                             input reg_idx_t rd,
                                             input logic [DATA_WIDTH-1:0] value);
    u_mem.mem[p]     = movi_il_enc(rf, rd);
    u_mem.mem[p + 1] = value[15:0];
    u_mem.mem[p + 2] = value[31:16];
    place_movi = p + 3;
  endfunction

  function automatic int unsigned place_move(input int unsigned p,
                                             input logic f_sel,
                                             input reg_file_t rf,
                                             input reg_idx_t rd,
                                             input logic [ADDR_WIDTH-1:0] source);
    u_mem.mem[p]     = move_enc(f_sel, rf, rd);
    u_mem.mem[p + 1] = source[15:0];
    u_mem.mem[p + 2] = source[31:16];
    place_move = p + 3;
  endfunction

  int unsigned failures;

  task automatic check_reg(input string label,
                           input logic [DATA_WIDTH-1:0] actual,
                           input logic [DATA_WIDTH-1:0] expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%08h actual=%08h",
               label, expected, actual);
      failures++;
    end
  endtask

  task automatic check_word(input string label,
                            input int unsigned index,
                            input logic [15:0] expected);
    if (u_mem.mem[index] !== expected) begin
      $display("TEST_RESULT: FAIL: %s: mem[%0d] expected=%04h actual=%04h",
               label, index, expected, u_mem.mem[index]);
      failures++;
    end
  endtask

  initial begin : main
    int unsigned p;
    int unsigned i;
    failures = 0;

    for (i = 0; i < 512; i++) begin
      u_mem.mem[i] = 16'h0300;
    end
    for (i = 120; i < 240; i++) begin
      u_mem.mem[i] = 16'h0000;
    end

    u_mem.mem[130] = 16'hBABE;
    u_mem.mem[131] = 16'hCAFE;
    u_mem.mem[161] = 16'h14A0;
    u_mem.mem[176] = 16'h8001;
    u_mem.mem[192] = 16'hE000;
    u_mem.mem[193] = 16'h0055;

    if (move_enc(1'b0, REG_FILE_A, 4'd2) !== 16'hD402) begin
      $display("TEST_RESULT: FAIL: F0/A encoding expected D402, got %04h",
               move_enc(1'b0, REG_FILE_A, 4'd2));
      failures++;
    end
    if (move_enc(1'b1, REG_FILE_B, 4'd4) !== 16'hD614) begin
      $display("TEST_RESULT: FAIL: F1/B encoding expected D614, got %04h",
               move_enc(1'b1, REG_FILE_B, 4'd4));
      failures++;
    end

    p = 0;

    // 1) F0/FS=32, A-file destination.
    p = place_movi(p, REG_FILE_A, 4'd14, 32'hD000_0000);
    p = place_movi(p, REG_FILE_A, 4'd2, 32'h0000_0900);
    u_mem.mem[p] = putst_enc(4'd14); p++;
    p = place_move(p, 1'b0, REG_FILE_A, 4'd2, 32'h0000_0820);
    u_mem.mem[p] = getst_enc(REG_FILE_B, 4'd0); p++;

    // 2) F1/FS=8, B-file destination, unaligned source and destination.
    p = place_movi(p, REG_FILE_A, 4'd14, 32'hD000_0200);
    p = place_movi(p, REG_FILE_B, 4'd4, 32'h0000_0B07);
    u_mem.mem[p] = putst_enc(4'd14); p++;
    p = place_move(p, 1'b1, REG_FILE_B, 4'd4, 32'h0000_0A15);
    u_mem.mem[p] = getst_enc(REG_FILE_A, 4'd7); p++;

    // 3) F0/FS=12, straddling source/destination. A nonzero high source
    // address word verifies low-word-first assembly at the core boundary;
    // the bounded simulation memory aliases its low address bits.
    p = place_movi(p, REG_FILE_A, 4'd14, 32'hD000_000C);
    p = place_movi(p, REG_FILE_A, 4'd6, 32'h0000_0D0D);
    u_mem.mem[p] = putst_enc(4'd14); p++;
    p = place_move(p, 1'b0, REG_FILE_A, 4'd6, 32'h1234_0C0B);
    u_mem.mem[p] = getst_enc(REG_FILE_B, 4'd2); p++;

    u_mem.mem[p] = 16'hC0FF;

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (2400) @(posedge clk);
    #1;

    check_word("1: destination low",  144, 16'hBABE);
    check_word("1: destination high", 145, 16'hCAFE);
    check_reg("1: A2 += 32", u_core.u_regfile.a_regs[2], 32'h0000_0920);
    check_reg("1: status unchanged", u_core.u_regfile.b_regs[0], 32'hD000_0000);

    check_word("2: unaligned destination/preservation", 176, 16'hD281);
    check_reg("2: B4 += 8", u_core.u_regfile.b_regs[4], 32'h0000_0B0F);
    check_reg("2: status unchanged", u_core.u_regfile.a_regs[7], 32'hD000_0200);

    check_word("3: straddling destination low",  208, 16'h8000);
    check_word("3: straddling destination high", 209, 16'h0157);
    check_reg("3: A6 += 12", u_core.u_regfile.a_regs[6], 32'h0000_0D19);
    check_reg("3: status unchanged", u_core.u_regfile.b_regs[2], 32'hD000_000C);

    if (!saw_high_source) begin
      $display("TEST_RESULT: FAIL: did not observe reconstructed 0x12340C0B source address");
      failures++;
    end
    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (MOVE @SAddr,*Rd+: F0/F1, A/B, FS32/8/12, LO/HI address, unaligned/straddling, status)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #3_000_000;
    $display("TEST_RESULT: FAIL: tb_move_abs_m2m_postinc hard timeout");
    $fatal(1);
  end

endmodule : tb_move_abs_m2m_postinc
