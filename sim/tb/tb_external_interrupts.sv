// -----------------------------------------------------------------------------
// tb_external_interrupts.sv
//
// Core-level external-interrupt regression. First, active-low LINT2 alone
// vectors through trap 2. After reset, simultaneous LINT1/LINT2 requests
// select higher-priority trap 1. The pins remain asserted through recognition,
// matching the level-sensitive contract in User's Guide §§8.1 and 8.3.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_external_interrupts;
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
  logic                          lint1_n;
  logic                          lint2_n;

  localparam logic [DATA_WIDTH-1:0] SP_INIT = 32'h0000_0800;
  localparam logic [DATA_WIDTH-1:0] SERVICE_X1 = 32'h0000_0640;
  localparam logic [DATA_WIDTH-1:0] SERVICE_X2 = 32'h0000_0780;
  localparam logic [ADDR_WIDTH-1:0] A_INTENB =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_INTENB) << 4);
  localparam logic [15:0] EXTERNAL_MASK =
      (16'h0001 << INT_X1_BIT) | (16'h0001 << INT_X2_BIT);
  localparam int unsigned X1_VEC_LO = 1020;
  localparam int unsigned X1_VEC_HI = 1021;
  localparam int unsigned X2_VEC_LO = 1018;
  localparam int unsigned X2_VEC_HI = 1019;

  tms34010_core u_core (
    .clk             (clk), .vclk_i(clk), .video_hsync_n_i(1'b1), .video_vsync_n_i(1'b1),
    .rst             (rst),
    .mem_req         (mem_req),
    .mem_we          (mem_we),
    .mem_addr        (mem_addr),
    .mem_size        (mem_size),
    .mem_wdata       (mem_wdata),
    .mem_rdata       (mem_rdata),
    .mem_ack         (mem_ack),
    .run_emu_n_i     (1'b1),
    .emua_n_o        (),
    .lint1_n_i       (lint1_n),
    .lint2_n_i       (lint2_n),
    .hcs_n_i         (1'b0),
    .host_req_i      (1'b0),
    .host_we_i       (1'b0),
    .host_reg_i      (HOST_REG_HSTCTL),
    .host_be_i       (2'b00),
    .host_wdata_i    (16'h0000),
    .host_rdata_o    (),
    .host_ack_o      (),
    .host_busy_o     (),
    .hint_n_o        (),
    .host_mem_req_o  (),
    .host_mem_we_o   (),
    .host_mem_addr_o (),
    .host_mem_wdata_o(),
    .host_mem_rdata_i(16'h0000),
    .host_mem_ack_i  (1'b0),
    .dpyint_set_i    (1'b0),
    .refresh_req_o   (),
    .refresh_row_o   (),
    .refresh_cbr_o   (),
    .video_hsync_o   (),
    .video_vsync_o   (),
    .video_hblank_o  (),
    .video_vblank_o  (),
    .video_blank_o   (),
    .screen_refresh_req_o(),
    .screen_refresh_ack_i(1'b0),
    .screen_refresh_srfaddr_o(),
    .screen_refresh_dpytap_o(),
    .state_o         (state_w),
    .pc_o            (pc_w),
    .instr_word_o    (instr_w),
    .illegal_opcode_o(illegal_w)
  );

  sim_memory_model #(.DEPTH_WORDS(1024)) u_mem (
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

  function automatic instr_word_t movi_il_enc(input reg_idx_t index);
    return 16'h09E0 | instr_word_t'(index);
  endfunction

  function automatic int unsigned place_movi_il(
    input int unsigned           word,
    input reg_idx_t              index,
    input logic [DATA_WIDTH-1:0] immediate
  );
    begin
      u_mem.mem[word]     = movi_il_enc(index);
      u_mem.mem[word + 1] = immediate[15:0];
      u_mem.mem[word + 2] = immediate[31:16];
      return word + 3;
    end
  endfunction

  function automatic int unsigned place_word(
    input int unsigned word,
    input instr_word_t instruction
  );
    begin
      u_mem.mem[word] = instruction;
      return word + 1;
    end
  endfunction

  function automatic int unsigned place_store_abs(
    input int unsigned           word,
    input reg_idx_t              source,
    input logic [ADDR_WIDTH-1:0] store_addr
  );
    begin
      u_mem.mem[word]     = 16'h0580 | instr_word_t'(source);
      u_mem.mem[word + 1] = store_addr[15:0];
      u_mem.mem[word + 2] = store_addr[31:16];
      return word + 3;
    end
  endfunction

  int unsigned failures;

  task automatic check_reg(
    input string                 label,
    input logic [DATA_WIDTH-1:0] actual,
    input logic [DATA_WIDTH-1:0] expected
  );
    begin
      if (actual !== expected) begin
        $display("TEST_RESULT: FAIL: %s expected=%08h actual=%08h",
                 label, expected, actual);
        failures++;
      end
    end
  endtask

  initial begin : main
    int unsigned i;
    int unsigned program_word;

    failures = 0;
    lint1_n  = 1'b1;
    lint2_n  = 1'b0;

    for (i = 0; i < 1024; i++) u_mem.mem[i] = 16'h0300;

    // Both service routines identify their vector and halt.
    program_word = 100;
    program_word = place_movi_il(program_word, 4'd5, 32'h0000_1111);
    program_word = place_word(program_word, 16'hC0FF);
    program_word = 120;
    program_word = place_movi_il(program_word, 4'd5, 32'h0000_2222);
    program_word = place_word(program_word, 16'hC0FF);

    u_mem.mem[X1_VEC_LO] = SERVICE_X1[15:0];
    u_mem.mem[X1_VEC_HI] = SERVICE_X1[31:16];
    u_mem.mem[X2_VEC_LO] = SERVICE_X2[15:0];
    u_mem.mem[X2_VEC_HI] = SERVICE_X2[31:16];

    // Main program enables both external sources and global IE.
    program_word = 0;
    program_word = place_movi_il(program_word, 4'd2, SP_INIT);
    program_word = place_word(program_word, 16'h4C4F);
    program_word = place_movi_il(
        program_word, 4'd0, {16'h0000, EXTERNAL_MASK});
    program_word = place_store_abs(program_word, 4'd0, A_INTENB);
    program_word = place_word(program_word, 16'h0D60);
    program_word = place_word(program_word, 16'hC0FF);

    // Phase 1: only LINT2 is active.
    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (3000) @(posedge clk);
    #1;
    check_reg("LINT2 trap vector", u_core.u_regfile.a_regs[5], 32'h0000_2222);

    // Phase 2: reset the core, then assert both pins. LINT1 must win.
    rst = 1'b1;
    lint1_n = 1'b0;
    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (3000) @(posedge clk);
    #1;
    check_reg("LINT1 priority over LINT2",
              u_core.u_regfile.a_regs[5], 32'h0000_1111);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0)
      $display("TEST_RESULT: PASS (external interrupts: LINT2 vector and LINT1 priority)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_external_interrupts hard timeout");
    $fatal(1);
  end

endmodule : tb_external_interrupts
