// -----------------------------------------------------------------------------
// tb_addc_subb.sv
//
// End-to-end test for `ADDC Rs, Rd` and `SUBB Rs, Rd` — register-register
// arithmetic with carry-in / borrow-in from ST.C.
//
// Spec citations:
//   - ADDC: `third_party/TMS34010_Info/docs/ti-official/
//           1988_TI_TMS34010_Users_Guide.pdf` §"ADDC" page 12-37,
//           summary table around 12-271. Encoding `0100 001S SSSR DDDD`.
//           Semantics: Rd = Rs + Rd + C; flags N, C, Z, V.
//   - SUBB: same User's Guide §"SUBB" page 12-248. Encoding
//           `0100 011S SSSR DDDD`. Semantics: Rd = Rd - Rs - C;
//           flags N, C, Z, V.
//
// Two structural challenges for an end-to-end test of carry-chain ops:
//
//   1. ST.C must be at a known value before the ADDC/SUBB under test.
//      MOVI / MOVK / MOVE set ST.C = 0 (per A0009/A0011 — logical and
//      PASS-through ops clear C). MOVK doesn't touch ST at all.
//      ADD / SUB / ADDC / SUBB / ADDK / SUBK / CMP set C from the
//      arithmetic. So:
//         - to enter ADDC/SUBB with C=0, follow a MOVI (or another op
//           that leaves C=0) before it;
//         - to enter ADDC/SUBB with C=1, use a deliberately-overflowing
//           ADD (or borrow-producing SUB) to set C=1, then load Rd via
//           MOVK (which preserves ST) before the ADDC/SUBB.
//
//   2. Final ST is only meaningful for the LAST flag-affecting
//      instruction in the trace. We therefore check Rd values (durable
//      via the regfile) for every test case, but only the LAST test's
//      ST flags. The final test is the SPVU001A page 12-248 row 7 case
//      — SUBB of 0x7FFFFFFE - 0xFFFFFFFE with C=0, producing 0x80000000
//      with NCZV = 1101 (signed overflow).
//
// Test cases land in distinct destination registers so each can be
// independently verified at the end:
//
//   A1  ← ADDC A0, A1   with C=0  : 5  + 10 + 0 = 15
//   A4  ← ADDC A0, A4   with C=1  : 7  + 10 + 1 = 18
//   A5  ← SUBB A0, A5   with C=0  : 5  - 10 - 0 = -5  = 0xFFFFFFFB
//   A6  ← SUBB A0, A6   with C=1  : 10 - 10 - 1 = -1  = 0xFFFFFFFF
//   A10 ← SUBB A11, A10 with C=0  : 0x7FFFFFFE - 0xFFFFFFFE - 0
//                                  = 0x80000000  (spec page 12-248 row 7)
//
// After the final SUBB, ST is checked against the spec row: NCZV = 1101.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_addc_subb;
  import tms34010_pkg::*;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  // ---------------------------------------------------------------------------
  // Wiring
  // ---------------------------------------------------------------------------
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

  sim_memory_model #(.DEPTH_WORDS(64)) u_mem (
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
  //
  //   ADDC Rs,Rd = bits[15:9]=7'b0100_001, [8:5]=Rs, [4]=R, [3:0]=Rd
  //              = 0x4200 | (Rs<<5) | (R<<4) | Rd
  //   SUBB Rs,Rd = same shape with prefix 7'b0100_011
  //              = 0x4600 | (Rs<<5) | (R<<4) | Rd
  //   ADD Rs,Rd  = 0x4000 | (Rs<<5) | (R<<4) | Rd   (reused for carry setup)
  //   MOVI IW    = 0x09C0 | (R<<4) | Rd  + 16-bit imm
  //   MOVK K, Rd = 0x1800 | (K<<5) | (R<<4) | Rd
  // ---------------------------------------------------------------------------
  function automatic instr_word_t addc_rr_enc(input reg_idx_t  rs_idx,
                                              input reg_file_t rf,
                                              input reg_idx_t  rd_idx);
    addc_rr_enc = 16'h4200
                | (instr_word_t'(rs_idx) << 5)
                | (instr_word_t'(rf)     << 4)
                | (instr_word_t'(rd_idx));
  endfunction

  function automatic instr_word_t subb_rr_enc(input reg_idx_t  rs_idx,
                                              input reg_file_t rf,
                                              input reg_idx_t  rd_idx);
    subb_rr_enc = 16'h4600
                | (instr_word_t'(rs_idx) << 5)
                | (instr_word_t'(rf)     << 4)
                | (instr_word_t'(rd_idx));
  endfunction

  function automatic instr_word_t add_rr_enc(input reg_idx_t  rs_idx,
                                             input reg_file_t rf,
                                             input reg_idx_t  rd_idx);
    add_rr_enc = 16'h4000
               | (instr_word_t'(rs_idx) << 5)
               | (instr_word_t'(rf)     << 4)
               | (instr_word_t'(rd_idx));
  endfunction

  function automatic instr_word_t movi_iw_enc(input reg_file_t rf,
                                              input reg_idx_t  idx);
    movi_iw_enc = 16'h09C0
                | (instr_word_t'(rf) << 4)
                | (instr_word_t'(idx));
  endfunction

  function automatic instr_word_t movk_enc(input logic [4:0] k,
                                           input reg_file_t  rf,
                                           input reg_idx_t   idx);
    movk_enc = 16'h1800
             | (instr_word_t'(k)  << 5)
             | (instr_word_t'(rf) << 4)
             | (instr_word_t'(idx));
  endfunction

  int unsigned failures;

  task automatic check_word(input string                  label,
                            input logic [DATA_WIDTH-1:0]  actual,
                            input logic [DATA_WIDTH-1:0]  expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%08h actual=%08h",
               label, expected, actual);
      failures++;
    end
  endtask

  task automatic check_bit(input string  label,
                           input logic   actual,
                           input logic   expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%0b actual=%0b",
               label, expected, actual);
      failures++;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Test body
  // ---------------------------------------------------------------------------
  initial begin : main
    int unsigned i;
    failures = 0;

    // Encoding sanity-checks.
    //   ADDC A0,A1 should be 0x4201; SUBB A0,A1 should be 0x4601.
    if (addc_rr_enc(4'd0, REG_FILE_A, 4'd1) !== 16'h4201) begin
      $display("TEST_RESULT: FAIL: addc_rr_enc(A0,A1) = %04h, expected 4201",
               addc_rr_enc(4'd0, REG_FILE_A, 4'd1));
      failures++;
    end
    if (subb_rr_enc(4'd0, REG_FILE_A, 4'd1) !== 16'h4601) begin
      $display("TEST_RESULT: FAIL: subb_rr_enc(A0,A1) = %04h, expected 4601",
               subb_rr_enc(4'd0, REG_FILE_A, 4'd1));
      failures++;
    end

    // Default-fill memory with NOP so end-of-program runs clean (same
    // pattern as tb_nop). NOP encoding is 0x0300.
    for (i = 0; i < 64; i++) begin
      u_mem.mem[i] = 16'h0300;
    end

    // ---- Program ------------------------------------------------------------
    // Each numbered section corresponds to one of the five tested ADDC/SUBB
    // operations described in the header comment.

    // Setup constants we reuse: A0 = 10.
    // (MOVK preserves ST.)
    u_mem.mem[0]  = movk_enc(5'd10, REG_FILE_A, 4'd0);   // A0  = 10

    // (1) ADDC with C=0
    //     ST.C is 0 from reset (MOVK doesn't touch it).
    u_mem.mem[1]  = movk_enc(5'd5,  REG_FILE_A, 4'd1);   // A1  = 5
    u_mem.mem[2]  = addc_rr_enc(4'd0, REG_FILE_A, 4'd1); // A1  = 5 + 10 + 0 = 15

    // (2) ADDC with C=1
    //     The prior ADDC left ST.C=0 (15 didn't overflow). Set C=1 by
    //     adding 0xFFFFFFFF + 1, which wraps to 0 with carry-out.
    u_mem.mem[3]  = movi_iw_enc(REG_FILE_A, 4'd8);       // MOVI ... A8
    u_mem.mem[4]  = 16'hFFFF;                            //   imm sign-ext → A8 = 0xFFFFFFFF
    u_mem.mem[5]  = movk_enc(5'd1,  REG_FILE_A, 4'd9);   // A9  = 1
    u_mem.mem[6]  = add_rr_enc(4'd8, REG_FILE_A, 4'd9);  // A9 = 1 + 0xFFFFFFFF = 0; ST.C=1
    u_mem.mem[7]  = movk_enc(5'd7,  REG_FILE_A, 4'd4);   // A4 = 7 (MOVK preserves C=1)
    u_mem.mem[8]  = addc_rr_enc(4'd0, REG_FILE_A, 4'd4); // A4 = 7 + 10 + 1 = 18; ST.C → 0

    // (3) SUBB with C=0
    //     ST.C is 0 from prior ADDC (18 didn't carry out).
    u_mem.mem[9]  = movk_enc(5'd5,  REG_FILE_A, 4'd5);   // A5 = 5
    u_mem.mem[10] = subb_rr_enc(4'd0, REG_FILE_A, 4'd5); // A5 = 5 - 10 - 0 = 0xFFFFFFFB;
                                                          // ST.C=1 (borrow)

    // (4) SUBB with C=1
    //     ST.C is 1 from prior SUBB. MOVK preserves C.
    u_mem.mem[11] = movk_enc(5'd10, REG_FILE_A, 4'd6);   // A6 = 10
    u_mem.mem[12] = subb_rr_enc(4'd0, REG_FILE_A, 4'd6); // A6 = 10 - 10 - 1 = 0xFFFFFFFF;
                                                          // ST.C=1 (borrow)

    // (5) Spec test vector: SUBB with C=0 producing signed overflow
    //     From SPVU001A page 12-248 row 7:
    //       SUBB A1, A0;  C_before=0;  A0_before=0x7FFFFFFE;  A1=0xFFFFFFFE
    //       → A0_after = 0x80000000;   NCZV = 1101
    //     We use A10 (= "A0_under_test") and A11 (= "A1_source") so it
    //     doesn't collide with earlier tests' A0/A1.
    //
    //     ST.C is 1 from prior SUBB. Need to clear it before this SUBB
    //     so cin matches the spec row. MOVI clears C.
    u_mem.mem[13] = movi_iw_enc(REG_FILE_A, 4'd11);      // MOVI ... A11
    u_mem.mem[14] = 16'hFFFE;                            //   sign-ext → A11 = 0xFFFFFFFE
                                                          //   ST: N=1, C=0, Z=0, V=0
    u_mem.mem[15] = movi_iw_enc(REG_FILE_A, 4'd12);      // MOVI ... A12 (scratch:
    u_mem.mem[16] = 16'h7FFE;                            //   A12 = 0x00007FFE;
                                                          //   ST.C still 0)
    // A10 needs to hold 0x7FFFFFFE. Use MOVI with imm 0x7FFE — sign-extends
    // to 0x00007FFE, NOT 0x7FFFFFFE. So we can't use MOVI IW. Use a
    // 32-bit-load sequence (MOVI IL would have been cleanest but we have
    // a simpler alternative: build it from two arithmetic steps using
    // operations that don't touch C until the final SUBB).
    //
    // Actually the simplest path: MOVI IW with 0x7FFE gives 0x00007FFE.
    // Then SLA by 16 in K-form would give 0x7FFE0000, not what we want
    // either. Direct construction: use MOVI IW with imm 0x7FFE, then
    // SUBK 1 to make it 0x00007FFD, ... no. None of these fit cleanly.
    //
    // The simplest is two arithmetic ops to build 0x7FFFFFFE in A10:
    //   MOVI 0xFFFF, A10    → A10 = 0xFFFFFFFF; ST.N=1, C=0, Z=0, V=0
    //   SRL  1, A10         → A10 = 0x7FFFFFFF; ST.C=1 (from LSB shifted
    //                          out!) — that disturbs C!
    // SRL in this core *does* update ST. Bad.
    //
    // Try yet another path: use MOVI IL with imm 0x7FFFFFFE. MOVI IL is
    // already wired (Task 0013). Its flag policy is N/Z from the loaded
    // value; C is cleared (PASS_B in the ALU sets c=0). So MOVI IL of
    // 0x7FFFFFFE sets ST.N=0, Z=0, C=0, V=0. Perfect.
    //
    // MOVI IL encoding (per A0012): bits[15:6]=10'b00_0010_0111,
    //   bit[5]=1 (long), bit[4]=R, bits[3:0]=Rd.
    //   16-bit base = 0x09E0 | (R<<4) | Rd.
    // Then 32-bit immediate stored as LO,HI two words.
    //
    // Overwrite the words we just wrote and rebuild with MOVI IL:
    u_mem.mem[13] = 16'h09EB;     // MOVI IL ..., A11  (R=A, idx=11=0xB)
    u_mem.mem[14] = 16'hFFFE;     //   imm low  = 0xFFFE
    u_mem.mem[15] = 16'hFFFF;     //   imm high = 0xFFFF  →  A11 = 0xFFFFFFFE
                                  //   ST.N=1, C=0, Z=0, V=0
    u_mem.mem[16] = 16'h09EA;     // MOVI IL ..., A10  (idx=10=0xA)
    u_mem.mem[17] = 16'hFFFE;     //   imm low  = 0xFFFE
    u_mem.mem[18] = 16'h7FFF;     //   imm high = 0x7FFF  →  A10 = 0x7FFFFFFE
                                  //   ST.N=0, C=0, Z=0, V=0   (this is the C=0
                                  //   we need before the final SUBB)
    // Now do the spec-vector SUBB.
    u_mem.mem[19] = subb_rr_enc(4'd11, REG_FILE_A, 4'd10);
                                  // A10 = 0x7FFFFFFE - 0xFFFFFFFE - 0
                                  //     = 0x80000000
                                  // ST.N=1, C=1 (borrow), Z=0, V=1

    // Reset.
    repeat (3) @(posedge clk);
    rst = 1'b0;

    // ~20 instructions, mix of single-word and IL (3-word). Worst case
    // about 25 + 8 = 33 instructions × ~7 cycles = ~230 cycles. Use 350
    // for headroom.
    repeat (350) @(posedge clk);
    #1;

    // ---- Register-value checks ----------------------------------------------
    check_word("A1  after ADDC C=0",  u_core.u_regfile.a_regs[1],
               32'h0000_000F);                       // 5 + 10 + 0 = 15
    check_word("A4  after ADDC C=1",  u_core.u_regfile.a_regs[4],
               32'h0000_0012);                       // 7 + 10 + 1 = 18
    check_word("A5  after SUBB C=0",  u_core.u_regfile.a_regs[5],
               32'hFFFF_FFFB);                       // 5 - 10 - 0 = -5
    check_word("A6  after SUBB C=1",  u_core.u_regfile.a_regs[6],
               32'hFFFF_FFFF);                       // 10 - 10 - 1 = -1
    check_word("A10 after spec SUBB", u_core.u_regfile.a_regs[10],
               32'h8000_0000);                       // spec page 12-248 row 7

    // ---- Final ST: matches the spec row's NCZV = 1101 -----------------------
    check_bit("ST.N  after spec SUBB", u_core.u_status_reg.n_o, 1'b1);
    check_bit("ST.C  after spec SUBB", u_core.u_status_reg.c_o, 1'b1);
    check_bit("ST.Z  after spec SUBB", u_core.u_status_reg.z_o, 1'b0);
    check_bit("ST.V  after spec SUBB", u_core.u_status_reg.v_o, 1'b1);

    // No instruction in the trace is unrecognized.
    check_bit("illegal_opcode_o", illegal_w, 1'b0);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (ADDC+SUBB with cin sweep + spec page 12-248 row 7)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #100_000;
    $display("TEST_RESULT: FAIL: tb_addc_subb hard timeout");
    $fatal(1);
  end

endmodule : tb_addc_subb
