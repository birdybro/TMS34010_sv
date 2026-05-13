// -----------------------------------------------------------------------------
// tb_dsj.sv
//
// DSJ / DSJEQ / DSJNE Rd, Address — Decrement Register and Skip Jump
// family. Per SPVU001A pages 12-70..12-73.
//
// Encodings (all share the "0000 1101 1xxR DDDD" shape, with a 16-bit
// signed word-offset in the following instruction word):
//
//   DSJ   : top11 = 11'b00001101_100 = 0x0D4   (unconditional decrement)
//   DSJEQ : top11 = 11'b00001101_101 = 0x0D5   (gated on Z=1)
//   DSJNE : top11 = 11'b00001101_110 = 0x0D6   (gated on Z=0)
//
// Semantics summary:
//   DSJ:   Rd ← Rd - 1;  if Rd' != 0 → branch, else fall through.
//   DSJEQ: if Z=1 then DSJ semantics; if Z=0 leave Rd alone and fall through.
//   DSJNE: if Z=0 then DSJ semantics; if Z=1 leave Rd alone and fall through.
//
// All three: N/C/Z/V unaffected by the instruction itself.
//
// The spec's worked examples (page 12-70 for DSJ, page 12-72 for
// DSJEQ, page 12-74 for DSJNE) cover the boundary cases. We adapt
// the key rows:
//
//   DSJ A5,LOOP   Rd_before=9        → Rd_after=8        Jump taken
//   DSJ A5,LOOP   Rd_before=1        → Rd_after=0        Jump NOT taken
//   DSJ A5,LOOP   Rd_before=0        → Rd_after=FFFFFFFF Jump taken
//
//   DSJEQ A5,LOOP Z=1, Rd_before=1   → Rd_after=0        Jump NOT taken
//   DSJEQ A5,LOOP Z=0, Rd_before=9   → Rd_after=9        Jump NOT taken (Z=0 → no work)
//   DSJEQ A5,LOOP Z=1, Rd_before=9   → Rd_after=8        Jump taken
//
//   DSJNE A5,LOOP Z=0, Rd_before=9   → Rd_after=8        Jump taken
//   DSJNE A5,LOOP Z=1, Rd_before=9   → Rd_after=9        Jump NOT taken (Z=1 → no work)
//
// To verify "jump taken" vs "not taken" we use the sentinel pattern:
// each scenario pre-initializes a sentinel register; the fall-through
// MOVI writes a different value into that sentinel; the landing-site
// write is benign. If the sentinel still holds its UNTOUCHED marker,
// the branch took. If it holds the fall-through value, the branch
// didn't take.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_dsj;
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

  sim_memory_model #(.DEPTH_WORDS(512)) u_mem (
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
  //   DSJ   = top11 11'b00001101_100 ⇒ {top11, 5'b0} = 0x06A0 (16'b0000_1101_1000_0000)
  //   DSJEQ = top11 11'b00001101_101 ⇒ 0x06C0
  //   Hmm wait: top11 occupies bits[15:5]. {11'b00001101_100, 5'b00000} = 16'h0D80? Let me compute.
  //
  //   top11 = 11'b 0000_1101_100 (the 11-bit prefix).
  //   Encoding = {top11, R, Rd[3:0]}.
  //   So bits[15:5] = top11; bits[4] = R; bits[3:0] = Rd.
  //   16-bit encoding = (top11 << 5) | (R << 4) | Rd
  //
  //   top11 for DSJ   = 11'b00001101_100 = 11'd108 = 11'h06C.
  //     108 << 5 = 3456 = 0x0D80.
  //   top11 for DSJEQ = 11'b00001101_101 = 11'd109 = 11'h06D.
  //     109 << 5 = 3488 = 0x0DA0.
  //   top11 for DSJNE = 11'b00001101_110 = 11'd110 = 11'h06E.
  //     110 << 5 = 3520 = 0x0DC0.
  //
  // Cross-check: 0000_1101_1000_0000 = 0x0D80 → DSJ A0 with offset=0
  //              base.  Matches.
  // ---------------------------------------------------------------------------
  function automatic instr_word_t dsj_enc(input reg_file_t rf, input reg_idx_t i);
    dsj_enc = 16'h0D80 | (instr_word_t'(rf) << 4) | (instr_word_t'(i));
  endfunction

  function automatic instr_word_t dsjeq_enc(input reg_file_t rf, input reg_idx_t i);
    dsjeq_enc = 16'h0DA0 | (instr_word_t'(rf) << 4) | (instr_word_t'(i));
  endfunction

  function automatic instr_word_t dsjne_enc(input reg_file_t rf, input reg_idx_t i);
    dsjne_enc = 16'h0DC0 | (instr_word_t'(rf) << 4) | (instr_word_t'(i));
  endfunction

  function automatic instr_word_t movi_il_enc(input reg_file_t rf, input reg_idx_t i);
    movi_il_enc = 16'h09E0 | (instr_word_t'(rf) << 4) | (instr_word_t'(i));
  endfunction

  function automatic instr_word_t cmpi_iw_enc(input reg_file_t rf, input reg_idx_t i);
    cmpi_iw_enc = 16'h0B40 | (instr_word_t'(rf) << 4) | (instr_word_t'(i));
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

  localparam logic [DATA_WIDTH-1:0] UNTOUCHED = 32'h0000_C357;
  localparam logic [DATA_WIDTH-1:0] FALL_VAL  = 32'h0000_F00D;

  // Place a "load counter / set Z / DSJxx / fall-through / landing"
  // scenario. The DSJxx instruction's 16-bit offset is set so the
  // branch (if taken) jumps over the 3-word fall-through MOVI.
  // disp = +3 words means the jump target is the landing slot.
  //
  // Uses the same return-the-new-p convention as `place_movi_il` —
  // `ref int unsigned p` turned out not to propagate updates across
  // function calls inside the task body reliably under Verilator, so
  // we explicitly return p and the caller writes `p = place_dsj_scenario(p, ...)`.
  function automatic int unsigned place_dsj_scenario(input int unsigned p,
                                                     input reg_idx_t counter_idx,
                                                     input logic [DATA_WIDTH-1:0] counter_init,
                                                     input instr_word_t  dsj_opcode,
                                                     input logic want_z,
                                                     input reg_idx_t sentinel_idx);
    int unsigned q;
    q = p;
    q = place_movi_il(q, REG_FILE_A, counter_idx, counter_init);
    u_mem.mem[q] = cmpi_iw_enc(REG_FILE_A, 4'd0);            q = q + 1;
    u_mem.mem[q] = want_z ? 16'sd7 : 16'sd99;                q = q + 1;
    u_mem.mem[q] = dsj_opcode;                               q = q + 1;
    u_mem.mem[q] = 16'sd3;  q = q + 1;  /* offset = +3 words */
    q = place_movi_il(q, REG_FILE_A, sentinel_idx, FALL_VAL);
    q = place_movi_il(q, REG_FILE_A, 4'd15, 32'h0000_0001);
    place_dsj_scenario = q;
  endfunction

  initial begin : main
    int unsigned p;
    int unsigned i;
    failures = 0;

    // Encoding sanity:
    //   DSJ A5 → 0x0D80 | 0x05 = 0x0D85
    //   DSJEQ A5 → 0x0DA0 | 0x05 = 0x0DA5
    //   DSJNE A5 → 0x0DC0 | 0x05 = 0x0DC5
    if (dsj_enc(REG_FILE_A, 4'd5) !== 16'h0D85) begin
      $display("TEST_RESULT: FAIL: DSJ A5 enc = %04h, expected 0D85",
               dsj_enc(REG_FILE_A, 4'd5));
      failures++;
    end
    if (dsjeq_enc(REG_FILE_A, 4'd5) !== 16'h0DA5) begin
      $display("TEST_RESULT: FAIL: DSJEQ A5 enc = %04h, expected 0DA5",
               dsjeq_enc(REG_FILE_A, 4'd5));
      failures++;
    end
    if (dsjne_enc(REG_FILE_A, 4'd5) !== 16'h0DC5) begin
      $display("TEST_RESULT: FAIL: DSJNE A5 enc = %04h, expected 0DC5",
               dsjne_enc(REG_FILE_A, 4'd5));
      failures++;
    end

    // NOP-fill memory.
    for (i = 0; i < 512; i++) begin
      u_mem.mem[i] = 16'h0300;
    end

    // Pre-init the scratch register A0 = 7 (for the Z-setting CMPI),
    // plus the sentinels we plan to check.
    p = 0;
    p = place_movi_il(p, REG_FILE_A, 4'd0, 32'd7);            // A0 = 7
    p = place_movi_il(p, REG_FILE_A, 4'd3, UNTOUCHED);        // DSJ scen 1 sentinel
    p = place_movi_il(p, REG_FILE_A, 4'd4, UNTOUCHED);        // DSJ scen 2 sentinel
    p = place_movi_il(p, REG_FILE_A, 4'd6, UNTOUCHED);        // DSJ scen 3 sentinel
    p = place_movi_il(p, REG_FILE_A, 4'd7, UNTOUCHED);        // DSJEQ Z=1 take sentinel
    p = place_movi_il(p, REG_FILE_A, 4'd8, UNTOUCHED);        // DSJEQ Z=1 skip sentinel
    p = place_movi_il(p, REG_FILE_A, 4'd9, UNTOUCHED);        // DSJEQ Z=0 skip sentinel
    p = place_movi_il(p, REG_FILE_A, 4'd10, UNTOUCHED);       // DSJNE Z=0 take sentinel
    p = place_movi_il(p, REG_FILE_A, 4'd11, UNTOUCHED);       // DSJNE Z=1 skip sentinel

    // Each scenario gets its OWN counter register so end-of-test checks
    // see the post-DSJ value from that scenario rather than a later one.
    //   Scen 1 → A1   (DSJ 9→8 take)
    //   Scen 2 → A2   (DSJ 1→0 skip)
    //   Scen 3 → A12  (DSJ 0→FFFFFFFF take)
    //   Scen 4 → A13  (DSJEQ Z=1 9→8 take)
    //   Scen 5 → A14  (DSJEQ Z=1 1→0 skip)
    //   Scen 6 → B1   (DSJEQ Z=0 → no-work)
    //   Scen 7 → B2   (DSJNE Z=0 9→8 take)
    //   Scen 8 → B12  (DSJNE Z=1 → no-work)

    p = place_dsj_scenario(p, 4'd1,  32'd9, dsj_enc(REG_FILE_A, 4'd1),
                       1'b1, 4'd3);
    p = place_dsj_scenario(p, 4'd2,  32'd1, dsj_enc(REG_FILE_A, 4'd2),
                       1'b1, 4'd4);
    p = place_dsj_scenario(p, 4'd12, 32'd0, dsj_enc(REG_FILE_A, 4'd12),
                       1'b1, 4'd6);
    p = place_dsj_scenario(p, 4'd13, 32'd9, dsjeq_enc(REG_FILE_A, 4'd13),
                       1'b1, 4'd7);
    p = place_dsj_scenario(p, 4'd14, 32'd1, dsjeq_enc(REG_FILE_A, 4'd14),
                       1'b1, 4'd8);
    // Scenarios 6-8 use B-file counters. The encoding helpers and
    // place_dsj_scenario both pass file=A inside, so we'll inline
    // explicitly using B-file encodings for these three.
    //   Scen 6: B1 counter init = 9, DSJEQ B1 with Z=0 → no-work
    p = place_movi_il(p, REG_FILE_B, 4'd1, 32'd9);
    u_mem.mem[p] = cmpi_iw_enc(REG_FILE_A, 4'd0);             p = p + 1;
    u_mem.mem[p] = 16'sd99;                                    p = p + 1;
    u_mem.mem[p] = dsjeq_enc(REG_FILE_B, 4'd1);                p = p + 1;
    u_mem.mem[p] = 16'sd3;                                     p = p + 1;
    p = place_movi_il(p, REG_FILE_A, 4'd9, FALL_VAL);          // fall-through sentinel A9
    p = place_movi_il(p, REG_FILE_A, 4'd15, 32'd1);            // landing
    //   Scen 7: B2 counter init = 9, DSJNE B2 with Z=0 → take
    p = place_movi_il(p, REG_FILE_B, 4'd2, 32'd9);
    u_mem.mem[p] = cmpi_iw_enc(REG_FILE_A, 4'd0);             p = p + 1;
    u_mem.mem[p] = 16'sd99;                                    p = p + 1;
    u_mem.mem[p] = dsjne_enc(REG_FILE_B, 4'd2);                p = p + 1;
    u_mem.mem[p] = 16'sd3;                                     p = p + 1;
    p = place_movi_il(p, REG_FILE_A, 4'd10, FALL_VAL);
    p = place_movi_il(p, REG_FILE_A, 4'd15, 32'd1);
    //   Scen 8: B12 counter init = 9, DSJNE B12 with Z=1 → no-work
    p = place_movi_il(p, REG_FILE_B, 4'd12, 32'd9);
    u_mem.mem[p] = cmpi_iw_enc(REG_FILE_A, 4'd0);             p = p + 1;
    u_mem.mem[p] = 16'sd7;                                     p = p + 1;
    u_mem.mem[p] = dsjne_enc(REG_FILE_B, 4'd12);               p = p + 1;
    u_mem.mem[p] = 16'sd3;                                     p = p + 1;
    p = place_movi_il(p, REG_FILE_A, 4'd11, FALL_VAL);
    p = place_movi_il(p, REG_FILE_A, 4'd15, 32'd1);

    // Place an infinite-loop "halt" (JRUC short with disp = -1, which
    // loops back to itself) at the end of the program. This prevents
    // execution from running past the end of our explicit setup and
    // wrapping around through memory to re-execute the program (and
    // thus clobber the registers we want to check).
    //
    // JRUC short encoding: 1100 0000 dddd dddd. With disp = 8'hFF
    // (signed -1): 0xC0FF. Target = pc_post_fetch + (-1)*16 = (W+1)*16
    // - 16 = W*16 → back to the JRUC itself. Infinite loop.
    u_mem.mem[p] = 16'hC0FF;

    // Reset.
    repeat (3) @(posedge clk);
    rst = 1'b0;

    // ~8 scenarios * ~13 words each = ~110 words + ~25 setup words.
    // Roughly 1000-1500 cycles. Use 3000.
    repeat (3000) @(posedge clk);
    #1;

    // ---- Checks ------------------------------------------------------------
    // Scenario 1: DSJ A1 9→8, jump taken. A3 untouched; A1 = 8.
    check_reg("Scen 1: DSJ A1 9→8 took → A3 UNTOUCHED",
              u_core.u_regfile.a_regs[3], UNTOUCHED);
    check_reg("Scen 1: counter A1 = 8 after DSJ 9→8",
              u_core.u_regfile.a_regs[1], 32'd8);

    // Scenario 2: DSJ A2 1→0, jump NOT taken. A4 = FALL_VAL; A2 = 0.
    check_reg("Scen 2: DSJ A2 1→0 NOT taken → A4 FALL_VAL",
              u_core.u_regfile.a_regs[4], FALL_VAL);
    check_reg("Scen 2: counter A2 = 0 after DSJ 1→0",
              u_core.u_regfile.a_regs[2], 32'd0);

    // Scenario 3: DSJ A12 0→0xFFFFFFFF, jump taken. A6 untouched; A12 = 0xFFFFFFFF.
    check_reg("Scen 3: DSJ A12 0→0xFFFFFFFF took → A6 UNTOUCHED",
              u_core.u_regfile.a_regs[6], UNTOUCHED);
    check_reg("Scen 3: counter A12 = 0xFFFFFFFF after DSJ 0→-1",
              u_core.u_regfile.a_regs[12], 32'hFFFF_FFFF);

    // Scenario 4: DSJEQ A13 Z=1 9→8, taken. A7 untouched; A13 = 8.
    check_reg("Scen 4: DSJEQ A13 Z=1 9→8 took → A7 UNTOUCHED",
              u_core.u_regfile.a_regs[7], UNTOUCHED);
    check_reg("Scen 4: counter A13 = 8 after DSJEQ Z=1 9→8",
              u_core.u_regfile.a_regs[13], 32'd8);

    // Scenario 5: DSJEQ A14 Z=1 1→0, NOT taken. A8 = FALL_VAL; A14 = 0.
    check_reg("Scen 5: DSJEQ A14 Z=1 1→0 NOT taken → A8 FALL_VAL",
              u_core.u_regfile.a_regs[8], FALL_VAL);
    check_reg("Scen 5: counter A14 = 0 after DSJEQ Z=1 1→0",
              u_core.u_regfile.a_regs[14], 32'd0);

    // Scenario 6: DSJEQ B1 Z=0 → no decrement, no jump. A9 = FALL_VAL; B1 = 9.
    check_reg("Scen 6: DSJEQ B1 Z=0 → no decrement, fall-through → A9 FALL_VAL",
              u_core.u_regfile.a_regs[9], FALL_VAL);
    check_reg("Scen 6: counter B1 stays at 9 (Z=0 → no decrement)",
              u_core.u_regfile.b_regs[1], 32'd9);

    // Scenario 7: DSJNE B2 Z=0 9→8, taken. A10 untouched; B2 = 8.
    check_reg("Scen 7: DSJNE B2 Z=0 9→8 took → A10 UNTOUCHED",
              u_core.u_regfile.a_regs[10], UNTOUCHED);
    check_reg("Scen 7: counter B2 = 8 after DSJNE Z=0 9→8",
              u_core.u_regfile.b_regs[2], 32'd8);

    // Scenario 8: DSJNE B12 Z=1 → no decrement, no jump. A11 = FALL_VAL; B12 = 9.
    check_reg("Scen 8: DSJNE B12 Z=1 → no decrement, fall-through → A11 FALL_VAL",
              u_core.u_regfile.a_regs[11], FALL_VAL);
    check_reg("Scen 8: counter B12 stays at 9 (Z=1 → no decrement)",
              u_core.u_regfile.b_regs[12], 32'd9);

    // No illegal opcode along the executed path.
    check_bit("illegal_opcode_o stayed 0", illegal_w, 1'b0);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (DSJ/DSJEQ/DSJNE: 8 scenarios spanning take, skip, no-work)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #6_000_000;
    $display("TEST_RESULT: FAIL: tb_dsj hard timeout");
    $fatal(1);
  end

endmodule : tb_dsj
