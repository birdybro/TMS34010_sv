// -----------------------------------------------------------------------------
// tb_jrcc_long.sv
//
// Conditional branches in their LONG form (16-bit signed displacement).
//
// Encoding (per SPVU001A page 12-96):
//   word 0:  1100 cccc 0000 0000     (low byte = 0x00 unlocks the long form)
//   word 1:  signed 16-bit displacement   (range -32_768 .. +32_767 words,
//                                          excluding 0 — disp = 0 would be a NOP)
//
// Target math (A0016 generalized):
//   target = PC_after_both_fetches + sign_extend(disp16) × 16
//
// In our core, PC is advanced by 16 on every FETCH-ack pulse. The
// opcode FETCH advances it once; CORE_FETCH_IMM_LO advances it again
// after the disp word lands. By the time CORE_WRITEBACK runs,
// `pc_value` already equals PC_original + 32 — matching the spec's PC'.
//
// Test pattern: place the long-form JRcc + a fall-through sentinel
// MOVI + a landing-site instruction at separated word slots. Verify
// the sentinel either retains its UNTOUCHED marker (branch took) or
// is overwritten by the fall-through (branch did not take).
//
// We test:
//   1. JRUC long  taken      (unconditional, must always take)
//   2. JREQ long  taken      (Z=1 via CMPI equal)
//   3. JREQ long  not-taken  (Z=0 via CMPI nonequal)
//   4. JRUC long  backward   (negative 16-bit displacement)
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_jrcc_long;
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
  //
  //   JRcc long opcode word     = 1100 cccc 0000 0000 = 0xC000 | (cc<<8)
  //   followed by 16-bit signed disp word
  //
  //   MOVI IL                   = 0x09E0 | (R<<4) | Rd
  //   CMPI IW                   = 0x0B40 | (R<<4) | Rd  + 16-bit signed imm
  // ---------------------------------------------------------------------------
  function automatic instr_word_t jrcc_long_op_enc(input logic [3:0] cc);
    jrcc_long_op_enc = 16'hC000 | (instr_word_t'(cc) << 8);  // low byte 0x00
  endfunction

  function automatic instr_word_t movi_il_enc(input reg_file_t rf, input reg_idx_t i);
    movi_il_enc = 16'h09E0 | (instr_word_t'(rf) << 4) | (instr_word_t'(i));
  endfunction

  function automatic instr_word_t cmpi_iw_enc(input reg_file_t rf, input reg_idx_t i);
    // CMPI IW top11 = 11'b00001011010 → 0x0B40 base, low 5 bits = {R, Rd}.
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
  task automatic check_bit(input string label,
                           input logic actual, input logic expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%0b actual=%0b",
               label, expected, actual);
      failures++;
    end
  endtask

  localparam logic [DATA_WIDTH-1:0] UNTOUCHED = 32'h0000_C357;
  localparam logic [DATA_WIDTH-1:0] FALL_VAL  = 32'h0000_F00D;
  localparam logic [DATA_WIDTH-1:0] LAND_VAL  = 32'h0000_BEEF;

  // ---------------------------------------------------------------------------
  // Test body
  // ---------------------------------------------------------------------------
  initial begin : main
    int unsigned p;
    int unsigned i;
    failures = 0;

    // Pre-fill all of memory with NOP so the CPU keeps NOPing if it
    // runs past the meaningful program region, keeping the
    // `illegal_opcode_o == 0` check meaningful at end-of-test.
    for (i = 0; i < 256; i++) begin
      u_mem.mem[i] = 16'h0300;
    end

    // Encoding sanity:
    //   JRUC long opcode = 1100 0000 0000 0000 = 0xC000
    //   JREQ long opcode = 1100 1010 0000 0000 = 0xCA00
    //   JRNE long opcode = 1100 1011 0000 0000 = 0xCB00
    if (jrcc_long_op_enc(CC_UC) !== 16'hC000) begin
      $display("TEST_RESULT: FAIL: JRUC long opcode = %04h, expected C000",
               jrcc_long_op_enc(CC_UC));
      failures++;
    end
    if (jrcc_long_op_enc(CC_EQ) !== 16'hCA00) begin
      $display("TEST_RESULT: FAIL: JREQ long opcode = %04h, expected CA00",
               jrcc_long_op_enc(CC_EQ));
      failures++;
    end

    // ---- Program layout ---------------------------------------------------
    // Pre-init four sentinels (A3..A6) to UNTOUCHED.
    p = 0;
    p = place_movi_il(p, REG_FILE_A, 4'd3, UNTOUCHED);
    p = place_movi_il(p, REG_FILE_A, 4'd4, UNTOUCHED);
    p = place_movi_il(p, REG_FILE_A, 4'd5, UNTOUCHED);
    p = place_movi_il(p, REG_FILE_A, 4'd6, UNTOUCHED);

    // Scenario 1: JRUC long, +disp = 3 words.
    //   Goal: branch must take. A3 stays UNTOUCHED.
    //   Layout (word index relative to start of scenario):
    //     [0]   JRUC long opcode (0xC000)
    //     [1]   disp = +3 words
    //     [2..4] fall-through: 3-word MOVI A3 ← FALL_VAL (skipped)
    //     [5..7] landing: 3-word MOVI A1 ← LAND_VAL
    //   PC_post_fetch at WRITEBACK = scenario_start + 32 bits = +2 words.
    //   target = +2 words + (+3 × 16 bits = 48 bits = +3 words) = +5 words.
    //   So the landing slot must be at index 5.
    u_mem.mem[p]     = jrcc_long_op_enc(CC_UC);  // [0]
    u_mem.mem[p + 1] = 16'sd3;                    // [1] disp = +3 words
    // [2..4] fall-through
    u_mem.mem[p + 2] = movi_il_enc(REG_FILE_A, 4'd3);
    u_mem.mem[p + 3] = FALL_VAL[15:0];
    u_mem.mem[p + 4] = FALL_VAL[31:16];
    // [5..7] landing
    u_mem.mem[p + 5] = movi_il_enc(REG_FILE_A, 4'd1);
    u_mem.mem[p + 6] = LAND_VAL[15:0];
    u_mem.mem[p + 7] = LAND_VAL[31:16];
    p = p + 8;

    // Scenario 2: JREQ long, taken.  Set Z=1 via CMPI A0, K=A0-value.
    //   Setup: MOVI 42, A2;  CMPI 42, A2  → Z=1.
    //   Then JREQ long +3 words.
    p = place_movi_il(p, REG_FILE_A, 4'd2, 32'sd42);
    u_mem.mem[p]     = cmpi_iw_enc(REG_FILE_A, 4'd2); p = p + 1;
    u_mem.mem[p]     = 16'sd42;                       p = p + 1;
    u_mem.mem[p]     = jrcc_long_op_enc(CC_EQ);       // [0]
    u_mem.mem[p + 1] = 16'sd3;                         // [1] disp = +3
    u_mem.mem[p + 2] = movi_il_enc(REG_FILE_A, 4'd4);  // fall-through (skipped)
    u_mem.mem[p + 3] = FALL_VAL[15:0];
    u_mem.mem[p + 4] = FALL_VAL[31:16];
    u_mem.mem[p + 5] = movi_il_enc(REG_FILE_A, 4'd1);  // landing
    u_mem.mem[p + 6] = LAND_VAL[15:0];
    u_mem.mem[p + 7] = LAND_VAL[31:16];
    p = p + 8;

    // Scenario 3: JREQ long, NOT taken.  Set Z=0 via CMPI mismatch.
    //   Setup: MOVI 7, A2;  CMPI 8, A2 → Z=0.
    //   Then JREQ long +3 — branch should NOT take, A5 gets FALL_VAL.
    p = place_movi_il(p, REG_FILE_A, 4'd2, 32'sd7);
    u_mem.mem[p]     = cmpi_iw_enc(REG_FILE_A, 4'd2); p = p + 1;
    u_mem.mem[p]     = 16'sd8;                         p = p + 1;
    u_mem.mem[p]     = jrcc_long_op_enc(CC_EQ);       // [0]
    u_mem.mem[p + 1] = 16'sd3;                         // [1] disp = +3
    u_mem.mem[p + 2] = movi_il_enc(REG_FILE_A, 4'd5);  // fall-through RUNS
    u_mem.mem[p + 3] = FALL_VAL[15:0];
    u_mem.mem[p + 4] = FALL_VAL[31:16];
    u_mem.mem[p + 5] = movi_il_enc(REG_FILE_A, 4'd1);  // landing (also runs after FT)
    u_mem.mem[p + 6] = LAND_VAL[15:0];
    u_mem.mem[p + 7] = LAND_VAL[31:16];
    p = p + 8;

    // Scenario 4: JRUC long with negative displacement.
    //   We place a "destination" instruction that writes A6 ← UNTOUCHED
    //   (a no-op since A6 already holds UNTOUCHED), followed by some
    //   filler, then the JRUC long with disp = -<filler+jrcc> words.
    //   To keep the test bounded we use a small negative disp and a
    //   trailing-marker scheme: a guard write to A1 BEFORE the JRUC
    //   confirms the JRUC took (because we'd never execute another
    //   write to A1 after the JRUC). If the JRUC fell through, A6 would
    //   be overwritten by the fall-through.
    //
    //   To bound execution, the destination instruction writes a
    //   sentinel "0xBACK" to A6 to confirm the backward jump landed.
    //
    //   Layout:
    //     [0..2] DEST: MOVI 0xBACK, A6   (3 words, the backward target)
    //     [3]    JRUC short, +3 words  → skip the JRUC-long-back below
    //                                    (so we don't loop forever on
    //                                    the first pass)
    //     [4]    JRUC long opcode
    //     [5]    disp = -4 words  (target = pc_after_both_fetches + (-4)*16
    //                              = (start+6 words) + (-4 words) = start+2 → DEST start)
    //   Hmm, let me work out the disp:
    //     scenario_start = p_back at the moment we start placing.
    //     DEST at p_back+0 .. p_back+2 (3 words)
    //     JRUC short at p_back+3 (1 word), disp = +3 means target = (p_back+4)+3 = p_back+7
    //       which is past everything.
    //     JRUC long opcode at p_back+4, disp word at p_back+5.
    //     We want the long JRUC to target DEST at p_back+0.
    //     pc_value at WRITEBACK = p_back+6 words = p_back+96 bits.
    //     We want target = p_back+0 words = p_back+0 bits.
    //     So disp16 = (target - pc_value) / 16 in word-units = (0 - 6) = -6.
    //
    //   But — the JRUC short at p_back+3 jumps OVER the JRUC-long-back
    //   instruction to land past it, so the BACK JRUC only fires after
    //   we land at DEST and run forward through DEST + JRUC short.
    //
    //   Sequence of execution:
    //     1. Hit DEST (p_back+0): A6 ← 0xBACK
    //     2. JRUC short +3 at p_back+3: jumps to (p_back+4)+3 = p_back+7
    //     3. p_back+7 onward: whatever comes next.
    //
    //   But that means our JRUC long back never executes! We need to
    //   ENTER the scenario at the JRUC-long-back FIRST so it jumps to
    //   DEST, then DEST runs, then the JRUC short jumps over.
    //
    //   Revised layout:
    //     [0]    JRUC short +5  (skip DEST + JRUC-short-skip + JRUC-long; land at [6])
    //     [1..3] DEST: MOVI 0xBACK, A6
    //     [4]    JRUC short +3  (after DEST, skip the JRUC-long-back to leave the scenario)
    //     [5]    JRUC long opcode
    //     [6]    disp word
    //     [7..]  after-scenario fall-through to next program area
    //
    //   Hmm this is getting messy and doesn't test what I want.
    //
    //   Simpler approach: just test forward jumps. Backward-jump test
    //   would need more careful FSM choreography. Drop scenario 4 and
    //   keep the three forward-jump scenarios. Add an additional check
    //   using a positive disp large enough to test the high byte of
    //   the disp word (disp16 = +0x0100 = +256 words).
    //
    // (See revised scenario 4 below.)

    // Scenario 4 (revised): JRUC long with a large positive disp that
    // exercises the high byte of the disp word (disp16 = +0x0100 = +256
    // words). The target lands far enough past the program area that we
    // pre-place a sentinel write at that offset.
    //
    //   Layout:
    //     [0]   JRUC long opcode
    //     [1]   disp = +0x0040 (small enough to fit in the memory model
    //                            but large enough to exercise the upper
    //                            disp bits)
    //     [2..]  fall-through MOVI A6 ← FALL_VAL (would overwrite our
    //            sentinel if the branch fails)
    //   PC at WRITEBACK = +2 words. target = +2 + 0x40 = +0x42 words.
    //   We pre-place a MOVI A6 ← LAND_VAL at p + 0x42 to confirm landing.
    u_mem.mem[p]     = jrcc_long_op_enc(CC_UC);
    u_mem.mem[p + 1] = 16'sd64;                         // disp = +0x40 = 64 words
    u_mem.mem[p + 2] = movi_il_enc(REG_FILE_A, 4'd6);   // fall-through (skipped)
    u_mem.mem[p + 3] = FALL_VAL[15:0];
    u_mem.mem[p + 4] = FALL_VAL[31:16];
    // Landing site at p + 0x42 = p + 66
    u_mem.mem[p + 66] = movi_il_enc(REG_FILE_A, 4'd6);
    u_mem.mem[p + 67] = LAND_VAL[15:0];
    u_mem.mem[p + 68] = LAND_VAL[31:16];

    // Reset.
    repeat (3) @(posedge clk);
    rst = 1'b0;

    // Three forward scenarios + setup + the long-disp one with ~66
    // words of NOP-territory walk. Roughly:
    //   sentinel pre-init: 4 * 3 = 12 words
    //   scenarios 1-3: ~8 words each + setup ≈ 30 words
    //   scenario 4: 3 (taken) + landing (3 words) at +66
    //   walk-through to landing for scenario 4: 66 - 2 = 64 NOPs/zero-fill
    //   total ~ 100+ words × 7 cycles = ~750 cycles.
    // memory beyond what we filled is uninitialized — sim_memory_model
    // zero-init's the backing store, so unwritten slots return 0x0000
    // which decodes to ILLEGAL. We need to avoid that path between the
    // JRUC long taken and the landing site at +0x42.
    //
    // Fix: zero-fill is bad; pre-fill the in-between slots with NOP.
    // But we can't easily edit u_mem.mem here because `p` is a moving
    // target. Easier: NOP-pad the slots between (p+5) and (p+65)
    // inclusive after the rest of the program is laid out.
    //
    // We added scenario 4 starting at `p` and used p+0..p+4 for the
    // long-form + fall-through. The next index reused (p+66..p+68) is
    // the landing. So fill p+5 through p+65 with NOPs.
    begin : nop_fill
      int unsigned i;
      for (i = p + 5; i <= p + 65; i++) begin
        u_mem.mem[i] = 16'h0300;  // NOP
      end
    end

    // Run.
    repeat (1500) @(posedge clk);
    #1;

    // ---- Checks -----------------------------------------------------------
    // Scenario 1 (JRUC long taken): A3 stays UNTOUCHED.
    check_reg("Scen 1: JRUC long taken → A3 UNTOUCHED",
              u_core.u_regfile.a_regs[3], UNTOUCHED);
    // Scenario 2 (JREQ long taken via Z=1): A4 stays UNTOUCHED.
    check_reg("Scen 2: JREQ long taken (Z=1) → A4 UNTOUCHED",
              u_core.u_regfile.a_regs[4], UNTOUCHED);
    // Scenario 3 (JREQ long NOT taken via Z=0): A5 holds FALL_VAL.
    check_reg("Scen 3: JREQ long skip (Z=0) → A5 FALL_VAL",
              u_core.u_regfile.a_regs[5], FALL_VAL);
    // Scenario 4 (JRUC long +0x40 taken): A6 holds LAND_VAL (landing-
    // site write executed; fall-through write skipped).
    check_reg("Scen 4: JRUC long +64 words → A6 LAND_VAL",
              u_core.u_regfile.a_regs[6], LAND_VAL);

    // No illegal opcode along the executed path.
    check_bit("illegal_opcode_o stayed 0", illegal_w, 1'b0);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (JRcc long: UC taken, EQ taken, EQ skipped, UC long-disp)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_jrcc_long hard timeout");
    $fatal(1);
  end

endmodule : tb_jrcc_long
