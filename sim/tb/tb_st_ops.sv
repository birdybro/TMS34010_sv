// -----------------------------------------------------------------------------
// tb_st_ops.sv
//
// Status-register manipulation family: CLRC, SETC, GETST, PUTST.
//
// Spec source: SPVU001A summary table page A-14:
//   CLRC     : 0x0320   (clear carry)
//   SETC     : 0x0DE0   (set carry)
//   GETST Rd : 0000 0001 100R DODD  (Rd ← ST)
//   PUTST Rs : 0000 0001 101R DODD  (ST ← Rs, full 32-bit write)
//
// Scenarios:
//   1. Pre-set ST to a known value via PUTST (the full-write path),
//      then check via GETST that the ST round-trips correctly.
//   2. CLRC clears C; verify only C changes (N/Z/V preserved).
//   3. SETC sets C; verify only C changes (N/Z/V preserved).
//   4. GETST reads the current ST into a destination register.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_st_ops;
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
  //   CLRC       : 0x0320 (single fixed encoding)
  //   SETC       : 0x0DE0
  //   GETST Rd   : 0x0180 | (R<<4) | Rd  (base = top11=0x00C << 5 = 0x0180)
  //   PUTST Rs   : 0x01A0 | (R<<4) | Rs  (base = top11=0x00D << 5 = 0x01A0)
  // ---------------------------------------------------------------------------
  function automatic instr_word_t getst_enc(input reg_file_t rf, input reg_idx_t rd);
    getst_enc = 16'h0180 | (instr_word_t'(rf) << 4) | (instr_word_t'(rd));
  endfunction
  function automatic instr_word_t putst_enc(input reg_file_t rf, input reg_idx_t rs);
    putst_enc = 16'h01A0 | (instr_word_t'(rf) << 4) | (instr_word_t'(rs));
  endfunction

  function automatic instr_word_t movi_il_enc(input reg_file_t rf, input reg_idx_t i);
    movi_il_enc = 16'h09E0 | (instr_word_t'(rf) << 4) | (instr_word_t'(i));
  endfunction

  function automatic int unsigned place_movi_il(input int unsigned p,
                                                input reg_file_t   rf,
                                                input reg_idx_t    i,
                                                input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]     = movi_il_enc(rf, i);
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
  task automatic check_bit(input string label, input logic actual, input logic expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%0b actual=%0b",
               label, expected, actual);
      failures++;
    end
  endtask

  // Build a 32-bit ST value with explicit flags + base.
  function automatic logic [DATA_WIDTH-1:0] build_st(
      input logic [DATA_WIDTH-1:0] base,
      input logic n_in, logic c_in, logic z_in, logic v_in);
    logic [DATA_WIDTH-1:0] r;
    r = base;
    r[ST_N_BIT] = n_in;
    r[ST_C_BIT] = c_in;
    r[ST_Z_BIT] = z_in;
    r[ST_V_BIT] = v_in;
    build_st = r;
  endfunction

  initial begin : main
    int unsigned p;
    int unsigned i;
    logic [DATA_WIDTH-1:0] target_st;
    failures = 0;

    // Encoding sanity.
    //   CLRC literal already checked above as 0x0320.
    //   SETC literal 0x0DE0.
    //   GETST A5 = 0x0180 | 5 = 0x0185
    //   PUTST B7 = 0x01A0 | 0x10 | 7 = 0x01B7
    if (getst_enc(REG_FILE_A, 4'd5) !== 16'h0185) begin
      $display("TEST_RESULT: FAIL: getst_enc(A5) = %04h, expected 0185",
               getst_enc(REG_FILE_A, 4'd5));
      failures++;
    end
    if (putst_enc(REG_FILE_B, 4'd7) !== 16'h01B7) begin
      $display("TEST_RESULT: FAIL: putst_enc(B7) = %04h, expected 01B7",
               putst_enc(REG_FILE_B, 4'd7));
      failures++;
    end

    // Pre-fill memory with NOP.
    for (i = 0; i < 256; i++) begin
      u_mem.mem[i] = 16'h0300;
    end

    p = 0;

    // ---- Scenario 1: PUTST round-trip (PUTST then GETST) ----------------
    // Load A0 with a known ST value: NCZV = 1010, with extra bits in
    // bit 0 set to make sure non-flag bits also round-trip.
    target_st = build_st(32'h0000_0001, 1'b1, 1'b0, 1'b1, 1'b0);
    p = place_movi_il(p, REG_FILE_A, 4'd0, target_st);
    // PUTST A0  → ST ← target_st.
    u_mem.mem[p] = putst_enc(REG_FILE_A, 4'd0); p = p + 1;
    // GETST A1  → A1 ← ST.  We'll check A1 equals target_st.
    u_mem.mem[p] = getst_enc(REG_FILE_A, 4'd1); p = p + 1;

    // ---- Scenario 2: CLRC clears C, leaves N/Z/V alone -------------------
    // After Scenario 1: ST.NCZV = {1,0,1,0}.
    //   We want to enter CLRC with C=1 to observe the clear. Currently
    //   ST.C = 0 from Scenario 1's PUTST. Use SETC first to make C=1,
    //   then CLRC to clear it, and check via GETST that only C changed.
    u_mem.mem[p] = 16'h0DE0; p = p + 1;   // SETC
    u_mem.mem[p] = getst_enc(REG_FILE_A, 4'd2); p = p + 1;  // A2 captures ST after SETC
    u_mem.mem[p] = 16'h0320; p = p + 1;   // CLRC
    u_mem.mem[p] = getst_enc(REG_FILE_A, 4'd3); p = p + 1;  // A3 captures ST after CLRC

    // Halt at end.
    u_mem.mem[p] = 16'hC0FF;

    repeat (3) @(posedge clk);
    rst = 1'b0;

    // ~10 instructions, mostly 3-word MOVI ILs and single-word ST ops.
    // ~150 cycles. Use 1000.
    repeat (1000) @(posedge clk);
    #1;

    // ---- PUTST round-trip ------------------------------------------------
    // After PUTST A0 + GETST A1: A1 should equal target_st BEFORE the
    // subsequent SETC modified C.
    //
    // But by end-of-test, ST has been further modified by SETC + CLRC.
    // A1, A2, A3 captured intermediate ST values:
    //   A1 = ST after first PUTST  = target_st
    //   A2 = ST after SETC          = target_st with C bit forced to 1
    //   A3 = ST after CLRC          = target_st with C bit forced to 0
    //                                (= target_st since C was 0 in target_st)
    check_reg("GETST after PUTST: A1 = target_st (round-trip)",
              u_core.u_regfile.a_regs[1], target_st);

    // ---- SETC leaves N/Z/V alone, sets C ---------------------------------
    check_reg("GETST after SETC: A2 = target_st with C=1",
              u_core.u_regfile.a_regs[2],
              build_st(32'h0000_0001, 1'b1, 1'b1, 1'b1, 1'b0));

    // ---- CLRC leaves N/Z/V alone, clears C -------------------------------
    check_reg("GETST after CLRC: A3 = target_st with C=0",
              u_core.u_regfile.a_regs[3],
              build_st(32'h0000_0001, 1'b1, 1'b0, 1'b1, 1'b0));

    // ---- Final ST flags ---------------------------------------------------
    check_bit("Final ST.N = 1 (preserved through SETC/CLRC)",
              u_core.u_status_reg.n_o, 1'b1);
    check_bit("Final ST.C = 0 (last touched by CLRC)",
              u_core.u_status_reg.c_o, 1'b0);
    check_bit("Final ST.Z = 1 (preserved through SETC/CLRC)",
              u_core.u_status_reg.z_o, 1'b1);
    check_bit("Final ST.V = 0 (preserved through SETC/CLRC)",
              u_core.u_status_reg.v_o, 1'b0);

    check_bit("illegal_opcode_o stayed 0", illegal_w, 1'b0);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (CLRC/SETC/GETST/PUTST + preservation)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_st_ops hard timeout");
    $fatal(1);
  end

endmodule : tb_st_ops
