// -----------------------------------------------------------------------------
// tb_movi_flags.sv
//
// Full-status integration coverage for both MOVI widths. The individual
// pages specify N from the moved sign, Z from a zero result, C Unaffected,
// and V=0. PUTST restores NCZV=1111 before every MOVI, and GETST snapshots
// the post-instruction word so C preservation and V clearing are observable.
//
// Spec: 1988 TI TMS34010 User's Guide pages 12-159 and 12-160.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_movi_flags;
  import tms34010_pkg::*;

  localparam logic [DATA_WIDTH-1:0] ST_SEED = 32'hF000_0010;

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
    .clk             (clk), .vclk_i(clk),
    .rst             (rst),
    .mem_req         (mem_req),
    .mem_we          (mem_we),
    .mem_addr        (mem_addr),
    .mem_size        (mem_size),
    .mem_wdata       (mem_wdata),
    .mem_rdata       (mem_rdata),
    .mem_ack         (mem_ack),
    .state_o         (state_w),
    .pc_o            (pc_w),
    .instr_word_o    (instr_w),
    .illegal_opcode_o(illegal_w),
    .run_emu_n_i     (1'b1),
    .emua_n_o        (), .lint1_n_i(1'b1), .lint2_n_i(1'b1), .hcs_n_i(1'b0), .host_req_i(1'b0), .host_we_i(1'b0), .host_reg_i(HOST_REG_HSTCTL), .host_be_i(2'b00), .host_wdata_i(16'h0000), .host_rdata_o(), .host_ack_o(), .host_busy_o(), .hint_n_o(), .host_mem_req_o(), .host_mem_we_o(), .host_mem_addr_o(), .host_mem_wdata_o(), .host_mem_rdata_i(16'h0000), .host_mem_ack_i(1'b0), .dpyint_set_i(1'b0), .refresh_req_o(), .refresh_row_o(), .refresh_cbr_o(), .video_hsync_o(), .video_vsync_o(), .video_hblank_o(), .video_vblank_o(), .video_blank_o(), .screen_refresh_req_o(), .screen_refresh_ack_i(1'b0), .screen_refresh_srfaddr_o(), .screen_refresh_dpytap_o()
  );

  sim_memory_model #(.DEPTH_WORDS(128)) u_mem (
    .clk      (clk),
    .rst      (rst),
    .mem_req  (mem_req),
    .mem_we   (mem_we),
    .mem_addr (mem_addr),
    .mem_size (mem_size),
    .mem_wdata(mem_wdata),
    .mem_rdata(mem_rdata),
    .mem_ack  (mem_ack)
  );

  function automatic instr_word_t movi_iw_enc(input reg_idx_t rd);
    movi_iw_enc = 16'h09C0 | instr_word_t'(rd);
  endfunction

  function automatic instr_word_t movi_il_enc(input reg_idx_t rd);
    movi_il_enc = 16'h09E0 | instr_word_t'(rd);
  endfunction

  function automatic instr_word_t putst_enc(input reg_idx_t rs);
    putst_enc = 16'h01A0 | instr_word_t'(rs);
  endfunction

  function automatic instr_word_t getst_b_enc(input reg_idx_t rd);
    getst_b_enc = 16'h0190 | instr_word_t'(rd);
  endfunction

  function automatic int unsigned place_movi_iw(input int unsigned p,
                                                input reg_idx_t   rd,
                                                input logic [15:0] value);
    u_mem.mem[p]     = movi_iw_enc(rd);
    u_mem.mem[p + 1] = value;
    place_movi_iw = p + 2;
  endfunction

  function automatic int unsigned place_movi_il(input int unsigned p,
                                                input reg_idx_t   rd,
                                                input logic [DATA_WIDTH-1:0] value);
    u_mem.mem[p]     = movi_il_enc(rd);
    u_mem.mem[p + 1] = value[15:0];
    u_mem.mem[p + 2] = value[31:16];
    place_movi_il = p + 3;
  endfunction

  function automatic int unsigned place_iw_case(input int unsigned p,
                                                input reg_idx_t   rd,
                                                input logic [15:0] value,
                                                input reg_idx_t   snapshot);
    int unsigned q;
    begin
      q = p;
      u_mem.mem[q] = putst_enc(4'd14); q++;
      q = place_movi_iw(q, rd, value);
      u_mem.mem[q] = getst_b_enc(snapshot); q++;
      place_iw_case = q;
    end
  endfunction

  function automatic int unsigned place_il_case(input int unsigned p,
                                                input reg_idx_t   rd,
                                                input logic [DATA_WIDTH-1:0] value,
                                                input reg_idx_t   snapshot);
    int unsigned q;
    begin
      q = p;
      u_mem.mem[q] = putst_enc(4'd14); q++;
      q = place_movi_il(q, rd, value);
      u_mem.mem[q] = getst_b_enc(snapshot); q++;
      place_il_case = q;
    end
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
    int unsigned p;
    int unsigned i;

    failures = 0;
    for (i = 0; i < 128; i++) begin
      u_mem.mem[i] = 16'h0300;
    end

    // A14 remains the PUTST source throughout the program.
    p = place_movi_il(0, 4'd14, ST_SEED);

    p = place_iw_case(p, 4'd0, 16'h0001, 4'd0); // positive
    p = place_iw_case(p, 4'd1, 16'h0000, 4'd1); // zero
    p = place_iw_case(p, 4'd2, 16'hFFFF, 4'd2); // negative/sign extension
    p = place_il_case(p, 4'd3, 32'h8000_0000, 4'd3); // negative
    p = place_il_case(p, 4'd4, 32'h0000_0000, 4'd4); // zero
    u_mem.mem[p] = 16'hC0FF; // JRUC -1

    repeat (3) @(posedge clk);
    rst = 1'b0;

    repeat (1000) @(posedge clk);
    #1;

    // N/C/Z/V:
    // positive = 0/1/0/0; zero = 0/1/1/0; negative = 1/1/0/0.
    check_word("MOVI IW positive ST", u_core.u_regfile.b_regs[0],
               32'h4000_0010);
    check_word("MOVI IW zero ST", u_core.u_regfile.b_regs[1],
               32'h6000_0010);
    check_word("MOVI IW negative ST", u_core.u_regfile.b_regs[2],
               32'hC000_0010);
    check_word("MOVI IL negative ST", u_core.u_regfile.b_regs[3],
               32'hC000_0010);
    check_word("MOVI IL zero ST", u_core.u_regfile.b_regs[4],
               32'h6000_0010);

    check_word("MOVI IW positive result", u_core.u_regfile.a_regs[0],
               32'h0000_0001);
    check_word("MOVI IW zero result", u_core.u_regfile.a_regs[1],
               32'h0000_0000);
    check_word("MOVI IW sign extension", u_core.u_regfile.a_regs[2],
               32'hFFFF_FFFF);
    check_word("MOVI IL negative result", u_core.u_regfile.a_regs[3],
               32'h8000_0000);
    check_word("MOVI IL zero result", u_core.u_regfile.a_regs[4],
               32'h0000_0000);
    check_word("legal MOVI program", {{(DATA_WIDTH-1){1'b0}}, illegal_w},
               32'h0000_0000);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (MOVI IW/IL N/Z, C preservation, and V clear verified)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #1_000_000;
    $display("TEST_RESULT: FAIL: tb_movi_flags hard timeout");
    $fatal(1);
  end

endmodule : tb_movi_flags
