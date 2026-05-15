// -----------------------------------------------------------------------------
// tb_popst.sv
//
// POPST — pop status register from stack. Per SPVU001A summary table
// page A-16. Single fixed encoding 0x01C0. Semantics:
//   ST <- mem[SP]   (32-bit read)
//   SP <- SP + 32
// All status bits are set from the popped value (the read covers the
// full 32-bit ST, including the N/C/Z/V flag positions at 28..31).
//
// Test plan combines POPST with PUSHST for a round-trip:
//   1. Initialize SP = 0x0000_0800 (= word 128 in the sim memory).
//   2. PUTST a seed ST = 0xC3C3_03C3 (arbitrary pattern with bit 31
//      set so N=1 after POPST, bit 29 set so Z=1, etc.).
//   3. PUSHST.  After: SP = 0x07E0, mem[126..127] = ST.
//   4. PUTST a different ST = 0x0000_0010 (= reset value; clears
//      all interesting bits).
//   5. POPST.   After: ST should match the originally-pushed seed,
//                      SP should be back at 0x0000_0800.
//
// This explicitly tests:
//   - The CORE_MEMORY read path (mem_we=0, mem_size=32).
//   - The new mem_rdata → st_write_data path in WRITEBACK.
//   - SP increment via the same ALU+mux path PUSHST uses.
//   - Round-trip integrity: ST recovers after PUSHST→PUTST→POPST.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_popst;
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

  localparam logic [DATA_WIDTH-1:0] SP_INIT  = 32'h0000_0800;
  localparam logic [DATA_WIDTH-1:0] ST_SEED  = 32'hC3C3_03C3;
  localparam logic [DATA_WIDTH-1:0] ST_TMP   = 32'h0000_0010;

  initial begin : main
    int unsigned p;
    int unsigned i;
    failures = 0;

    // NOP-fill.
    for (i = 0; i < 256; i++) begin
      u_mem.mem[i] = 16'h0300;
    end

    p = 0;

    // ---- Set SP = SP_INIT via MOVE A0, A15 ------------------------------
    p = place_movi_il(p, 4'd0, SP_INIT);
    u_mem.mem[p] = 16'h900F; p = p + 1;     // MOVE A0, A15 (= SP)

    // ---- Set ST = ST_SEED via PUTST -------------------------------------
    p = place_movi_il(p, 4'd1, ST_SEED);
    u_mem.mem[p] = putst_enc(4'd1); p = p + 1;

    // ---- PUSHST → mem[words 126..127] = ST_SEED, SP -= 32 ---------------
    u_mem.mem[p] = 16'h01E0; p = p + 1;

    // ---- Clobber ST to a known different value (ST_TMP) -----------------
    p = place_movi_il(p, 4'd2, ST_TMP);
    u_mem.mem[p] = putst_enc(4'd2); p = p + 1;
    // Capture the clobbered ST so we know what was there before POPST.
    u_mem.mem[p] = getst_enc(4'd3); p = p + 1;   // A3 = ST_TMP

    // ---- POPST → ST recovers, SP recovers --------------------------------
    u_mem.mem[p] = 16'h01C0; p = p + 1;

    // ---- GETST A4 to capture the popped ST ------------------------------
    u_mem.mem[p] = getst_enc(4'd4); p = p + 1;

    // Halt
    u_mem.mem[p] = 16'hC0FF;

    repeat (3) @(posedge clk);
    rst = 1'b0;

    repeat (2000) @(posedge clk);
    #1;

    // ---- Checks ----------------------------------------------------------
    // After clobbering, A3 = ST_TMP (proves the PUTST round-trip and that
    // ST had been overwritten just before POPST).
    check_reg("Clobber: A3 = ST_TMP",
              u_core.u_regfile.a_regs[3], ST_TMP);

    // After POPST, A4 should equal ST_SEED (the popped 32-bit value).
    check_reg("POPST: A4 = ST_SEED (full ST round-trip)",
              u_core.u_regfile.a_regs[4], ST_SEED);

    // SP should be back at SP_INIT (PUSHST decremented to 0x07E0,
    // POPST incremented back to 0x0800).
    check_reg("POPST: SP back at SP_INIT",
              u_core.u_regfile.sp_q, SP_INIT);

    // Final ST: the popped value (ST_SEED = 0xC3C3_03C3).
    // bits[31:28] = 0xC = 1100 → N=1, C=1, Z=0, V=0.
    if (u_core.u_status_reg.n_o !== ST_SEED[31]) begin
      $display("TEST_RESULT: FAIL: ST.N after POPST: expected %0b actual %0b",
               ST_SEED[31], u_core.u_status_reg.n_o);
      failures++;
    end
    if (u_core.u_status_reg.c_o !== ST_SEED[30]) begin
      $display("TEST_RESULT: FAIL: ST.C after POPST: expected %0b actual %0b",
               ST_SEED[30], u_core.u_status_reg.c_o);
      failures++;
    end
    if (u_core.u_status_reg.z_o !== ST_SEED[29]) begin
      $display("TEST_RESULT: FAIL: ST.Z after POPST: expected %0b actual %0b",
               ST_SEED[29], u_core.u_status_reg.z_o);
      failures++;
    end
    if (u_core.u_status_reg.v_o !== ST_SEED[28]) begin
      $display("TEST_RESULT: FAIL: ST.V after POPST: expected %0b actual %0b",
               ST_SEED[28], u_core.u_status_reg.v_o);
      failures++;
    end

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (PUSHST/POPST round-trip: ST recovered, SP restored, flags from popped value)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_popst hard timeout");
    $fatal(1);
  end

endmodule : tb_popst
