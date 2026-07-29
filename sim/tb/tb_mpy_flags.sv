// -----------------------------------------------------------------------------
// tb_mpy_flags.sv
//
// MPYS/MPYU odd-destination status semantics. The 1988 User's Guide pages
// 12-164 through 12-167 define N/Z from the full 64-bit product when Rd is
// even, but from the stored low 32 bits when Rd is odd. These discriminator
// cases have a nonzero 64-bit product whose discarded/truncated low word is
// negative or zero. PUTST seeds every flag so unaffected C/V (and MPYU N)
// are checked as well.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_mpy_flags;
  import tms34010_pkg::*;

  localparam logic [DATA_WIDTH-1:0] ST_SEED = 32'hD000_0010;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  logic                        mem_req, mem_we, mem_ack;
  logic [ADDR_WIDTH-1:0]       mem_addr;
  logic [FIELD_SIZE_WIDTH-1:0] mem_size;
  logic [DATA_WIDTH-1:0]       mem_wdata, mem_rdata;
  core_state_t                 state_w;
  logic [ADDR_WIDTH-1:0]       pc_w;
  instr_word_t                 instr_w;
  logic                        illegal_w;

  tms34010_core u_core (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
    .mem_size(mem_size), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
    .mem_ack(mem_ack), .state_o(state_w), .pc_o(pc_w),
    .instr_word_o(instr_w), .illegal_opcode_o(illegal_w),
    .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1), .lint2_n_i(1'b1), .hcs_n_i(1'b0), .host_req_i(1'b0), .host_we_i(1'b0), .host_reg_i(HOST_REG_HSTCTL), .host_be_i(2'b00), .host_wdata_i(16'h0000), .host_rdata_o(), .host_ack_o(), .host_busy_o(), .hint_n_o(), .host_mem_req_o(), .host_mem_we_o(), .host_mem_addr_o(), .host_mem_wdata_o(), .host_mem_rdata_i(16'h0000), .host_mem_ack_i(1'b0), .dpyint_set_i(1'b0), .refresh_req_o(), .refresh_row_o(), .refresh_cbr_o(), .video_hsync_o(), .video_vsync_o(), .video_hblank_o(), .video_vblank_o(), .video_blank_o(), .screen_refresh_req_o(), .screen_refresh_ack_i(1'b0), .screen_refresh_srfaddr_o(), .screen_refresh_dpytap_o()
  );

  sim_memory_model #(.DEPTH_WORDS(128)) u_mem (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
    .mem_size(mem_size), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
    .mem_ack(mem_ack)
  );

  function automatic instr_word_t movi_il_enc(input reg_idx_t rd);
    movi_il_enc = 16'h09E0 | instr_word_t'(rd);
  endfunction
  function automatic instr_word_t mpys_enc(input reg_idx_t rs, input reg_idx_t rd);
    mpys_enc = 16'h5C00 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
  endfunction
  function automatic instr_word_t mpyu_enc(input reg_idx_t rs, input reg_idx_t rd);
    mpyu_enc = 16'h5E00 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
  endfunction
  function automatic instr_word_t putst_enc(input reg_idx_t rs);
    putst_enc = 16'h01A0 | instr_word_t'(rs);
  endfunction
  function automatic instr_word_t getst_b_enc(input reg_idx_t rd);
    getst_b_enc = 16'h0190 | instr_word_t'(rd);
  endfunction

  function automatic int unsigned place_movi_il(input int unsigned p,
                                                input reg_idx_t rd,
                                                input logic [DATA_WIDTH-1:0] value);
    u_mem.mem[p] = movi_il_enc(rd);
    u_mem.mem[p + 1] = value[15:0];
    u_mem.mem[p + 2] = value[31:16];
    place_movi_il = p + 3;
  endfunction
  function automatic int unsigned place_word(input int unsigned p,
                                              input instr_word_t word);
    u_mem.mem[p] = word;
    place_word = p + 1;
  endfunction

  int unsigned failures;

  task automatic check_word(input string label,
                            input logic [DATA_WIDTH-1:0] actual,
                            input logic [DATA_WIDTH-1:0] expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%08h actual=%08h",
               label, expected, actual);
      failures++;
    end
  endtask

  initial begin : main
    int unsigned p, i;

    failures = 0;
    for (i = 0; i < 128; i++) u_mem.mem[i] = 16'h0300;

    p = place_movi_il(0, 4'd14, ST_SEED);

    // 65535 * 65535 = 0x00000000_FFFE0001. Odd Rd stores a negative
    // low word, so MPYS must set N despite the positive full product.
    p = place_movi_il(p, 4'd0, 32'd65535);
    p = place_movi_il(p, 4'd1, 32'd65535);
    p = place_word(p, putst_enc(4'd14));
    p = place_word(p, mpys_enc(4'd0, 4'd1));
    p = place_word(p, getst_b_enc(4'd0));

    // 65536 * 65536 = 0x00000001_00000000. Odd Rd stores zero, so MPYS
    // must report N=0/Z=1 rather than status from the nonzero full product.
    p = place_movi_il(p, 4'd2, 32'h0001_0000);
    p = place_movi_il(p, 4'd3, 32'h0001_0000);
    p = place_word(p, putst_enc(4'd14));
    p = place_word(p, mpys_enc(4'd2, 4'd3));
    p = place_word(p, getst_b_enc(4'd1));

    // The same truncation controls MPYU Z; N/C/V are all unaffected.
    p = place_movi_il(p, 4'd4, 32'h0001_0000);
    p = place_movi_il(p, 4'd5, 32'h0001_0000);
    p = place_word(p, putst_enc(4'd14));
    p = place_word(p, mpyu_enc(4'd4, 4'd5));
    p = place_word(p, getst_b_enc(4'd2));
    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (2000) @(posedge clk);
    #1;

    check_word("MPYS odd negative low result", u_core.u_regfile.a_regs[1],
               32'hFFFE_0001);
    check_word("MPYS odd low-word N/Z and C/V preservation",
               u_core.u_regfile.b_regs[0], 32'hD000_0010);
    check_word("MPYS odd zero low result", u_core.u_regfile.a_regs[3],
               32'h0000_0000);
    check_word("MPYS odd zero low-word status",
               u_core.u_regfile.b_regs[1], 32'h7000_0010);
    check_word("MPYU odd zero low result", u_core.u_regfile.a_regs[5],
               32'h0000_0000);
    check_word("MPYU odd low-word Z and NCV preservation",
               u_core.u_regfile.b_regs[2], 32'hF000_0010);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0)
      $display("TEST_RESULT: PASS (MPYS/MPYU odd-Rd flags use stored low word)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_mpy_flags hard timeout");
    $fatal(1);
  end
endmodule : tb_mpy_flags
