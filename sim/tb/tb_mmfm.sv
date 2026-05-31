// -----------------------------------------------------------------------------
// tb_mmfm.sv
//
// MMFM Rp, register list — Move Multiple Registers From Memory (the pop
// counterpart of MMTM). Per SPVU001A page 12-109. Encoding
// `0000 1001 101R DDDD` + 16-bit register-list mask. For each register
// Rn in the list (HIGHEST-order register restored first), a 32-bit value
// is read from mem[Rp] into Rn and Rp is post-incremented by 32 — for
// every register including the last, so the final Rp points one word
// past the restored block (final Rp = initial Rp + 32*count). All four
// status bits are Unaffected.
//
// Two independent subtests:
//
//   PHASE 2 (run second in the instruction stream, checked first below):
//     Reproduces the worked example on TI User's Guide page 12-110
//     verbatim, using the B file. Memory is pre-seeded with TI's exact
//     stack image; B0 = 0x10000 is the stack pointer; the published
//     register results are checked bit-for-bit. This is the strongest
//     ABSOLUTE-correctness test and pins down the bit-to-register
//     mapping (assumption A0026) against TI's own numbers.
//       mask = {B1,B2,B4,B8,B12,B13,B14,SP} = bits 1,2,4,8,12,13,14,15
//            = 0xF116.
//
//   PHASE 1 (run first, A file): MMTM → corrupt → MMFM round-trip. This
//     is the strongest INTERNAL-CONSISTENCY test: it only relies on MMTM
//     and MMFM agreeing on the mask mapping, not on its absolute value,
//     and it also regression-checks that the shared mm_* iterator still
//     pushes correctly after the MMTM/MMFM merge.
//       mask = {A0,A2,A4,A8,A12,A13,A14} = bits 0,2,4,8,12,13,14 = 0x7115
//       (SP/bit15 deliberately omitted so PHASE 1 and PHASE 2 don't fight
//        over the shared SP register).
//
// Assumption A0026 (shared with MMTM): bit N of the mask = register R(N).
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_mmfm;
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

  // Needs to span both the low program/stack region and the PHASE-2
  // stack image at bit address 0x10000 (word index 4096..4111).
  sim_memory_model #(.DEPTH_WORDS(8192)) u_mem (
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

  // ---- Program-assembly helpers --------------------------------------------
  // MOVI IL K, Rd — `0x09E0 | (R<<4) | N` + 32-bit immediate (LO, HI).
  function automatic instr_word_t movi_il_enc(input logic r, input reg_idx_t i);
    movi_il_enc = 16'h09E0 | (instr_word_t'(r) << 4) | instr_word_t'(i);
  endfunction
  function automatic int unsigned place_movi_il(input int unsigned p,
                                                input logic        r,
                                                input reg_idx_t    i,
                                                input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]     = movi_il_enc(r, i);
    u_mem.mem[p + 1] = imm[15:0];
    u_mem.mem[p + 2] = imm[31:16];
    place_movi_il = p + 3;
  endfunction
  function automatic int unsigned place_word(input int unsigned p,
                                             input instr_word_t w);
    u_mem.mem[p] = w;
    place_word   = p + 1;
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

  // Per-register sentinel values for the PHASE-1 round-trip.
  function automatic logic [DATA_WIDTH-1:0] reg_sentinel(input int idx);
    reg_sentinel = {16'(idx) * 16'h0101, 16'(idx) * 16'h1010};
  endfunction

  // ---- PHASE-1 (round-trip) parameters -------------------------------------
  localparam logic [DATA_WIDTH-1:0] RP1_INIT = 32'h0000_0800;   // A1 = Rp
  // {A0,A2,A4,A8,A12,A13,A14} (no SP) = bits 0,2,4,8,12,13,14 = 0x7115.
  localparam logic [15:0]           MASK1    = 16'h7115;
  localparam logic [DATA_WIDTH-1:0] GARBAGE  = 32'hDEAD_BEEF;

  // ---- PHASE-2 (TI spec example) parameters --------------------------------
  localparam logic [DATA_WIDTH-1:0] RP2_INIT = 32'h0001_0000;   // B0 = Rp
  // {B1,B2,B4,B8,B12,B13,B14,SP} = bits 1,2,4,8,12,13,14,15 = 0xF116.
  localparam logic [15:0]           MASK2    = 16'hF116;

  // The list of A-file registers touched by PHASE 1 (excludes Rp=A1).
  localparam int unsigned LIST1 [0:6] = '{0, 2, 4, 8, 12, 13, 14};

  initial begin : main
    int unsigned p;
    int unsigned i;
    int unsigned base2;        // word index of the PHASE-2 stack top
    failures = 0;

    // NOP-fill the program region.
    for (i = 0; i < 4096; i++) begin
      u_mem.mem[i] = 16'h0300;
    end

    // ---- Pre-seed the PHASE-2 stack image (TI page 12-110) ---------------
    // 32-bit reads return {mem[word+1], mem[word]}; word = bit_addr/16.
    // Top of stack (lowest addr, 0x10000) holds the highest-order register
    // (SP). Each register occupies two consecutive words (LSW, MSW).
    base2 = RP2_INIT >> 4;     // 0x10000 / 16 = 4096
    u_mem.mem[base2 +  0] = 16'hBFBF;  u_mem.mem[base2 +  1] = 16'hFFFF; // SP  = FFFFBFBF
    u_mem.mem[base2 +  2] = 16'hBEBE;  u_mem.mem[base2 +  3] = 16'hEEEE; // B14 = EEEEBEBE
    u_mem.mem[base2 +  4] = 16'hBDBD;  u_mem.mem[base2 +  5] = 16'hDDDD; // B13 = DDDDBDBD
    u_mem.mem[base2 +  6] = 16'hBCBC;  u_mem.mem[base2 +  7] = 16'hCCCC; // B12 = CCCCBCBC
    u_mem.mem[base2 +  8] = 16'hB7B7;  u_mem.mem[base2 +  9] = 16'h7777; // B8  = 7777B7B7
    u_mem.mem[base2 + 10] = 16'hB3B3;  u_mem.mem[base2 + 11] = 16'h3333; // B4  = 3333B3B3
    u_mem.mem[base2 + 12] = 16'hB2B2;  u_mem.mem[base2 + 13] = 16'h2222; // B2  = 2222B2B2
    u_mem.mem[base2 + 14] = 16'hB1B1;  u_mem.mem[base2 + 15] = 16'h1111; // B1  = 1111B1B1

    // =========================== PHASE 1 ==================================
    // Load A-file sentinels for the registers in MASK1 (skip A1=Rp).
    p = 0;
    foreach (LIST1[i]) begin
      p = place_movi_il(p, 1'b0, 4'(LIST1[i]), reg_sentinel(LIST1[i]));
    end
    p = place_movi_il(p, 1'b0, 4'd1, RP1_INIT);          // A1 = Rp

    // MMTM A1, MASK1 — push the 7 registers. Encoding 0x0981 + mask.
    p = place_word(p, 16'h0981);
    p = place_word(p, MASK1);

    // Corrupt every pushed register so a failed restore is visible.
    foreach (LIST1[i]) begin
      p = place_movi_il(p, 1'b0, 4'(LIST1[i]), GARBAGE);
    end

    // MMFM A1, MASK1 — pop them back. Encoding 0x09A1 + mask.
    //   top11=00001001_101, R=0, DDDD=1 ⇒ 0x09A1.
    p = place_word(p, 16'h09A1);
    p = place_word(p, MASK1);

    // =========================== PHASE 2 ==================================
    p = place_movi_il(p, 1'b1, 4'd0, RP2_INIT);          // B0 = Rp (B file)
    // MMFM B0, MASK2 — encoding 0x09B0 + mask.
    //   top11=00001001_101, R=1, DDDD=0 ⇒ 0x09B0.
    p = place_word(p, 16'h09B0);
    p = place_word(p, MASK2);

    // Halt sentinel.
    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;

    // ~30 MOVIs + 2 MMTM/MMFM (8 transactions each) ≈ a few hundred
    // cycles. Be generous.
    repeat (6000) @(posedge clk);
    #1;

    // -------- PHASE-2 checks (TI page 12-110 published results) -----------
    check_reg("MMFM spec: SP  = FFFFBFBF", u_core.u_regfile.sp_q,       32'hFFFF_BFBF);
    check_reg("MMFM spec: B14 = EEEEBEBE", u_core.u_regfile.b_regs[14], 32'hEEEE_BEBE);
    check_reg("MMFM spec: B13 = DDDDBDBD", u_core.u_regfile.b_regs[13], 32'hDDDD_BDBD);
    check_reg("MMFM spec: B12 = CCCCBCBC", u_core.u_regfile.b_regs[12], 32'hCCCC_BCBC);
    check_reg("MMFM spec: B8  = 7777B7B7", u_core.u_regfile.b_regs[8],  32'h7777_B7B7);
    check_reg("MMFM spec: B4  = 3333B3B3", u_core.u_regfile.b_regs[4],  32'h3333_B3B3);
    check_reg("MMFM spec: B2  = 2222B2B2", u_core.u_regfile.b_regs[2],  32'h2222_B2B2);
    check_reg("MMFM spec: B1  = 1111B1B1", u_core.u_regfile.b_regs[1],  32'h1111_B1B1);
    // Final Rp = initial + 8*32 = 0x10000 + 0x100 = 0x10100.
    check_reg("MMFM spec: B0 (Rp) = 0x10100", u_core.u_regfile.b_regs[0], 32'h0001_0100);

    // -------- PHASE-1 checks (round-trip restores the sentinels) ----------
    check_reg("MMFM rt: A0  restored", u_core.u_regfile.a_regs[0],  reg_sentinel(0));
    check_reg("MMFM rt: A2  restored", u_core.u_regfile.a_regs[2],  reg_sentinel(2));
    check_reg("MMFM rt: A4  restored", u_core.u_regfile.a_regs[4],  reg_sentinel(4));
    check_reg("MMFM rt: A8  restored", u_core.u_regfile.a_regs[8],  reg_sentinel(8));
    check_reg("MMFM rt: A12 restored", u_core.u_regfile.a_regs[12], reg_sentinel(12));
    check_reg("MMFM rt: A13 restored", u_core.u_regfile.a_regs[13], reg_sentinel(13));
    check_reg("MMFM rt: A14 restored", u_core.u_regfile.a_regs[14], reg_sentinel(14));
    // Round-trip Rp: 0x800 - 7*32 (MMTM) + 7*32 (MMFM) = 0x800.
    check_reg("MMFM rt: A1 (Rp) back to RP1_INIT", u_core.u_regfile.a_regs[1], RP1_INIT);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (MMFM: TI spec example exact; MMTM/MMFM round-trip restores)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #5_000_000;
    $display("TEST_RESULT: FAIL: tb_mmfm hard timeout");
    $fatal(1);
  end

endmodule : tb_mmfm
