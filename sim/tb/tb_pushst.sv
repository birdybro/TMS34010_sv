// -----------------------------------------------------------------------------
// tb_pushst.sv
//
// PUSHST — push status register onto the stack. Per SPVU001A summary
// table page A-16. Single fixed encoding 0x01E0. Semantics:
//   SP <- SP - 32  (decrement SP by 32 bits = one 32-bit word)
//   mem[SP] <- ST  (32-bit memory write at the new SP address)
// Status bits N, C, Z, V Unaffected.
//
// This is the FIRST test of the project's memory-write infrastructure
// (Task 0047). It exercises:
//   - The new CORE_MEMORY FSM state (driven by decoded.needs_memory_op).
//   - sim_memory_model's 32-bit write path (mem_size=32, mem_we=1).
//   - The ALU's SUB path for the SP decrement (alu_b=32 via the new
//     INSTR_PUSHST mux entry).
//   - Concurrent SP writeback + memory write (the new SP value is
//     used as the mem_addr).
//
// Test plan:
//   1. Initialize SP (= A15) to a known mid-memory bit-address, e.g.,
//      32'h0000_0800  (= word 128 in the sim memory).
//   2. PUTST a known seed ST value, e.g., 0xC3C3_03C3.
//   3. PUSHST.
//   4. After PUSHST:
//        SP must equal initial_SP - 32 = 0x0000_07E0 (one 32-bit word
//          below — = word 126 in the memory backing store).
//        mem[word 126] should be ST_seed[15:0] = 0x03C3.
//        mem[word 127] should be ST_seed[31:16] = 0xC3C3.
//   5. GETST captures ST → A0 should equal the seed (proves ST is
//      unchanged by PUSHST).
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_pushst;
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

  // ---------------------------------------------------------------------------
  // Encoding helpers.
  //   PUSHST     = 0x01E0
  //   PUTST Rs   = 0x01A0 | Rs    (assuming A-file)
  //   GETST Rd   = 0x0180 | Rd
  //   MOVI IL Rd = 0x09E0 | Rd
  // ---------------------------------------------------------------------------
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
  task automatic check_mem(input string label, input int unsigned idx,
                           input logic [15:0] expected);
    if (u_mem.mem[idx] !== expected) begin
      $display("TEST_RESULT: FAIL: %s mem[%0d]: expected=%04h actual=%04h",
               label, idx, expected, u_mem.mem[idx]);
      failures++;
    end
  endtask

  localparam logic [DATA_WIDTH-1:0] SP_INIT  = 32'h0000_0800;  // bit-addr of word 128
  localparam logic [DATA_WIDTH-1:0] ST_SEED  = 32'hC3C3_03C3;  // arbitrary-looking pattern

  initial begin : main
    int unsigned p;
    int unsigned i;
    failures = 0;

    // NOP-fill memory.
    for (i = 0; i < 256; i++) begin
      u_mem.mem[i] = 16'h0300;
    end

    p = 0;

    // ---- Setup: load A0 = SP_INIT, A1 = ST_SEED -------------------------
    //   MOVI A0, SP_INIT; MOVI A1, ST_SEED.  Note MOVI clobbers ST.NCZV,
    //   so we PUTST AFTER both MOVIs (same trap as in tb_exgf).
    p = place_movi_il(p, 4'd0, SP_INIT);
    p = place_movi_il(p, 4'd1, ST_SEED);

    // ---- Move A0 into SP (= A15) via a MOVE A0, A15 instruction.
    //   We don't have a "set SP" alias; use MOVE Rs, Rd to copy A0 → A15.
    //   MOVE A0, A15 encoding: top6 = 6'b100100, S=0 (Rs=A0=0), F bit
    //   ignored (per A0020), R=0 (file A), D=15.  = 0x9000 | (0<<5)
    //   | (0<<4) | 15 = 0x900F.
    u_mem.mem[p] = 16'h900F; p = p + 1;
    //   But MOVE updates ST.{N,Z}.  That's OK — PUTST below overwrites ST.

    // ---- Set ST = ST_SEED via PUTST A1 ----------------------------------
    u_mem.mem[p] = putst_enc(4'd1); p = p + 1;

    // ---- PUSHST ---------------------------------------------------------
    u_mem.mem[p] = 16'h01E0; p = p + 1;

    // ---- GETST A2 to capture ST after PUSHST (should still equal ST_SEED).
    u_mem.mem[p] = getst_enc(4'd2); p = p + 1;

    // Halt
    u_mem.mem[p] = 16'hC0FF;

    repeat (3) @(posedge clk);
    rst = 1'b0;

    repeat (2000) @(posedge clk);
    #1;

    // ---- SP should now hold SP_INIT - 32 = 0x0000_07E0 -----------------
    // SP is at file-A index 15. The regfile's `sp_q` (or a_regs[15] alias)
    // holds the shared SP.  We check via the regfile's `sp_o` output.
    check_reg("PUSHST: SP = SP_INIT - 32",
              u_core.u_regfile.sp_q,
              SP_INIT - 32);

    // ---- Memory: mem[word 126] (low half) = ST_SEED[15:0]; mem[word 127]
    //      (high half) = ST_SEED[31:16].
    //   SP_INIT_new = 0x07E0 in bits = word (0x07E0 >> 4) = 126.
    check_mem("PUSHST: low-half word",  126, ST_SEED[15:0]);
    check_mem("PUSHST: high-half word", 127, ST_SEED[31:16]);

    // ---- ST should still equal ST_SEED -----------------------------------
    check_reg("PUSHST: ST unchanged (GETST → A2)",
              u_core.u_regfile.a_regs[2],
              ST_SEED);

    // No illegal opcode along the executed path.
    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (PUSHST: SP decremented by 32, ST written to mem, ST itself unchanged)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_pushst hard timeout");
    $fatal(1);
  end

endmodule : tb_pushst
