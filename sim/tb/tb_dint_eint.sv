// -----------------------------------------------------------------------------
// tb_dint_eint.sv
//
// DINT / EINT — single-fixed-encoding interrupt-enable control.
// Per SPVU001A summary table page A-14:
//   DINT = 0x0360 — clear ST.IE (bit 21)
//   EINT = 0x0D60 — set   ST.IE
// Status bits N, C, Z, V Unaffected.
//
// Test plan:
//   1. PUTST a known ST value (with IE bit clear initially).
//   2. EINT → bit 21 should become 1; other bits preserved.
//   3. DINT → bit 21 should become 0 again; other bits preserved.
//   4. Verify by capturing ST via GETST into distinct registers.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_dint_eint;
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
    .clk             (clk),
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
    .illegal_opcode_o(illegal_w)
  );

  sim_memory_model #(.DEPTH_WORDS(256)) u_mem (
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

  function automatic instr_word_t movi_il_enc(input reg_idx_t i);
    movi_il_enc = 16'h09E0 | instr_word_t'(i);
  endfunction
  function automatic instr_word_t putst_enc(input reg_idx_t rs);
    putst_enc = 16'h01A0 | instr_word_t'(rs);
  endfunction
  function automatic instr_word_t getst_enc(input reg_idx_t rd);
    getst_enc = 16'h0180 | instr_word_t'(rd);
  endfunction
  function automatic int unsigned place_movi_il(input int unsigned p,
                                                input reg_idx_t    i,
                                                input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]     = movi_il_enc(i);
    u_mem.mem[p + 1] = imm[15:0];
    u_mem.mem[p + 2] = imm[31:16];
    place_movi_il = p + 3;
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

  // IE bit = bit 21. As a 32-bit mask: 1<<21 = 0x0020_0000.
  localparam logic [DATA_WIDTH-1:0] IE_MASK   = 32'h0020_0000;
  // ST seed value: a known pattern with IE clear, varied non-IE bits so
  // we can verify they're preserved across DINT/EINT.
  localparam logic [DATA_WIDTH-1:0] ST_SEED   = 32'hA5A5_05A5;
  //   Bit 21 cleared (= 0).
  //   N=1 (bit 31 of A5A5_05A5 is 1), C=0, Z=1, V=0, etc.

  initial begin : main
    int unsigned p;
    int unsigned i;
    failures = 0;

    // NOP-fill memory.
    for (i = 0; i < 256; i++) begin
      u_mem.mem[i] = 16'h0300;
    end

    p = 0;

    // Load A0 with the seed ST value (must come BEFORE PUTST to avoid
    // MOVI clobbering ST.NCZV after the PUTST, per the same trap noted
    // in tb_exgf).
    p = place_movi_il(p, 4'd0, ST_SEED & ~IE_MASK);  // make sure IE=0
    u_mem.mem[p] = putst_enc(4'd0); p = p + 1;

    // EINT → ST.IE = 1. Capture into A1.
    u_mem.mem[p] = 16'h0D60;        p = p + 1;       // EINT
    u_mem.mem[p] = getst_enc(4'd1); p = p + 1;

    // DINT → ST.IE = 0. Capture into A2.
    u_mem.mem[p] = 16'h0360;        p = p + 1;       // DINT
    u_mem.mem[p] = getst_enc(4'd2); p = p + 1;

    // Halt.
    u_mem.mem[p] = 16'hC0FF;

    repeat (3) @(posedge clk);
    rst = 1'b0;

    repeat (1000) @(posedge clk);
    #1;

    // Expected captures:
    //   A1 = ST_SEED with IE forced 1 = (ST_SEED & ~IE_MASK) | IE_MASK
    //   A2 = ST_SEED with IE forced 0 = (ST_SEED & ~IE_MASK)
    check_reg("EINT sets ST.IE → A1 = seed | IE",
              u_core.u_regfile.a_regs[1],
              (ST_SEED & ~IE_MASK) | IE_MASK);
    check_reg("DINT clears ST.IE → A2 = seed & ~IE",
              u_core.u_regfile.a_regs[2],
              ST_SEED & ~IE_MASK);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (EINT sets ST.IE; DINT clears it; other ST bits preserved)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #1_000_000;
    $display("TEST_RESULT: FAIL: tb_dint_eint hard timeout");
    $fatal(1);
  end

endmodule : tb_dint_eint
