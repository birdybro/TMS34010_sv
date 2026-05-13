// -----------------------------------------------------------------------------
// tb_dsjs.sv
//
// Decrement-and-Skip-Jump SHORT form (single-word). Per SPVU001A
// pages 12-74/75 + summary table line 13844.
//
// Encoding: `0011 1Dxx xxxR DDDD`
//   bits[15:11] = 5'b00111
//   bit[10]     = D (direction; 0 = forward, 1 = backward)
//   bits[9:5]   = 5-bit unsigned offset (words from PC')
//   bit[4]      = R (file)
//   bits[3:0]   = Rd index
//
// Semantics: Rd ← Rd - 1; if Rd' != 0 → branch (PC' ± offset×16); else
// fall through. Status bits N/C/Z/V unaffected.
//
// Four scenarios:
//   1. Forward DSJS, Rd=9 → 8, take.
//   2. Forward DSJS, Rd=1 → 0, NOT take (fall-through writes sentinel).
//   3. Backward DSJS, Rd=5 → 4, take (verifies D=1 path).
//   4. Forward DSJS, Rd=0 → 0xFFFFFFFF, take (verifies decrement-of-0 case).
//
// Each scenario uses a distinct counter register (A1..A4) so end-of-
// test checks don't get clobbered.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_dsjs;
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
  //   DSJS encoding = 0x3800 | (D<<10) | (offset<<5) | (R<<4) | Rd
  // (top5 = 5'b00111 occupies bits[15:11]; base = {5'b00111, 11'b0} = 0x3800)
  // ---------------------------------------------------------------------------
  function automatic instr_word_t dsjs_enc(input logic        d,
                                           input logic [4:0]  offset,
                                           input reg_file_t   rf,
                                           input reg_idx_t    idx);
    dsjs_enc = 16'h3800
             | (instr_word_t'(d) << 10)
             | (instr_word_t'(offset) << 5)
             | (instr_word_t'(rf) << 4)
             | (instr_word_t'(idx));
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

  localparam logic [DATA_WIDTH-1:0] UNTOUCHED = 32'h0000_C357;
  localparam logic [DATA_WIDTH-1:0] FALL_VAL  = 32'h0000_F00D;

  initial begin : main
    int unsigned p;
    int unsigned i;
    int unsigned back_target_word;
    failures = 0;

    // Encoding sanity:
    //   DSJS A5, +5 forward = 0x3800 | (0<<10) | (5<<5) | (0<<4) | 5
    //                       = 0x3800 | 0x00A0 | 5 = 0x38A5
    //   DSJS A5, +5 backward = 0x3800 | (1<<10) | (5<<5) | 5
    //                        = 0x3800 | 0x0400 | 0x00A0 | 5 = 0x3CA5
    if (dsjs_enc(1'b0, 5'd5, REG_FILE_A, 4'd5) !== 16'h38A5) begin
      $display("TEST_RESULT: FAIL: DSJS A5 +5 fwd = %04h, expected 38A5",
               dsjs_enc(1'b0, 5'd5, REG_FILE_A, 4'd5));
      failures++;
    end
    if (dsjs_enc(1'b1, 5'd5, REG_FILE_A, 4'd5) !== 16'h3CA5) begin
      $display("TEST_RESULT: FAIL: DSJS A5 -5 bwd = %04h, expected 3CA5",
               dsjs_enc(1'b1, 5'd5, REG_FILE_A, 4'd5));
      failures++;
    end

    // Pre-fill memory with NOP.
    for (i = 0; i < 256; i++) begin
      u_mem.mem[i] = 16'h0300;
    end

    // ---- Pre-init sentinel registers (A11, A12, A13, A14) -------------------
    p = 0;
    p = place_movi_il(p, REG_FILE_A, 4'd11, UNTOUCHED);
    p = place_movi_il(p, REG_FILE_A, 4'd12, UNTOUCHED);
    p = place_movi_il(p, REG_FILE_A, 4'd13, UNTOUCHED);
    p = place_movi_il(p, REG_FILE_A, 4'd14, UNTOUCHED);

    // ---- Scenario 1: DSJS A1, +3 forward, Rd=9 → 8, TAKE -------------------
    //   Setup: MOVI A1 = 9.
    //   Then DSJS A1 with offset=3 forward.
    //   DSJS is at scenario_start + 3 (after the 3-word MOVI).
    //   pc_value at WB = (scen_start + 3 + 1) * 16 = (scen_start + 4) * 16.
    //   target = pc_value + 3*16 = (scen_start + 7) * 16. Word index 7.
    //   So at word offset 7 we place the landing-site sentinel write
    //   (sentinel = A11 — must NOT be overwritten by fall-through).
    //   Fall-through MOVI at word offset 4 writes A11 = FALL_VAL
    //   (would overwrite the sentinel if the branch fails).
    p = place_movi_il(p, REG_FILE_A, 4'd1, 32'd9);
    u_mem.mem[p] = dsjs_enc(1'b0, 5'd3, REG_FILE_A, 4'd1);  p = p + 1;
    p = place_movi_il(p, REG_FILE_A, 4'd11, FALL_VAL);     // fall-through (skipped)
    // landing: benign MOVI A15 = 1 so the FSM has somewhere to go.
    p = place_movi_il(p, REG_FILE_A, 4'd15, 32'd1);

    // ---- Scenario 2: DSJS A2, +3 forward, Rd=1 → 0, NOT TAKE ----------------
    //   Same shape as Scen 1 but Rd=1 so the post-decrement is 0 and
    //   the branch is NOT taken. Fall-through MOVI runs and writes
    //   the sentinel A12 = FALL_VAL.
    p = place_movi_il(p, REG_FILE_A, 4'd2, 32'd1);
    u_mem.mem[p] = dsjs_enc(1'b0, 5'd3, REG_FILE_A, 4'd2);  p = p + 1;
    p = place_movi_il(p, REG_FILE_A, 4'd12, FALL_VAL);
    p = place_movi_il(p, REG_FILE_A, 4'd15, 32'd1);

    // ---- Scenario 3: DSJS A3 backward, Rd=5 → 4, TAKE ----------------------
    //   For a backward DSJS, the branch target points BEFORE the
    //   DSJS. We arrange this by pre-placing a "back-landing" word
    //   ahead of the DSJS that lands at sentinel A13 = LAND_BACK.
    //
    //   Layout:
    //     word L: MOVI A13 = LAND_BACK (3 words: L, L+1, L+2). The
    //             "L" is the back-target word.
    //     word L+3: JRUC short +4 to skip over the DSJS instruction
    //               and the fall-through landing block, going to
    //               the next scenario directly. Otherwise we'd
    //               loop forever from the DSJS back to MOVI A13 and
    //               continue executing.
    //
    //   ACTUALLY — simpler approach for the backward test: pre-init
    //   A3 = 1 in the scenario setup (so the DSJS decrement to 0
    //   skips the backward jump), and verify that the FALL-THROUGH
    //   path runs correctly. That avoids the loop-control complexity.
    //
    //   But that wouldn't test the BACKWARD-jump path. Let me design
    //   a backward-jump scenario more carefully.
    //
    //   Simpler design for backward:
    //     word L:   MOVI A13 = LAND_BACK_VAL  (back target; 3 words)
    //     word L+3: JRUC short to skip DSJS and continue at L+5+...
    //               (to next scenario). Use disp = +1 so we land
    //               1 word past the DSJS at L+5.
    //     word L+4: DSJS A3 backward, offset = 1.
    //               (DSJS at L+4. pc_at_WB = L+5. target = L+5 - 1*16
    //                = L+5 - 1 = L+4 in word units = the DSJS itself.
    //                That's not a good test either — would loop the DSJS.)
    //
    //   Better:
    //     word L:   MOVI A13 = LAND_BACK_VAL  (3 words)
    //     word L+3: JRUC short to "after scenario 3" (skip past
    //               the DSJS so it doesn't run on the first pass).
    //     word L+4: DSJS A3 with offset that targets word L.
    //               If we want target = L (word), and pc_at_WB =
    //               L+5 word (since DSJS at L+4 advances to L+5):
    //                 target_word = L+5 + (D ? -off : +off)
    //                 L = L+5 - off  →  off = 5.
    //               So D=1, offset=5.
    //     ...but the first-pass JRUC short skips past the DSJS so
    //     it doesn't execute. To EXECUTE the DSJS, we need to
    //     loop back somehow.
    //
    //   Wait — the spec says backward DSJS subtracts the offset from
    //   PC'. With pc_at_WB = L+5, off=5: target = L+5 - 5 = L. So
    //   target lands at the start of the MOVI A13.
    //
    //   But if we PRE-EXECUTE MOVI A13 first (so A13 is already at
    //   LAND_BACK_VAL when DSJS lands there again), the second pass
    //   just rewrites A13 to the same value — no observable harm.
    //
    //   Sequence:
    //     1. Execute MOVI A3=5 (counter init).
    //     2. JRUC long forward to L (skip into the scenario block).
    //     3. At L: MOVI A13 = LAND_BACK_VAL. Then JRUC short forward
    //        to skip past DSJS to "exit" the scenario.
    //     4. The DSJS at L+4 is reached how? Via another forward
    //        jump? This is getting twisted.
    //
    //   SIMPLEST WORKING DESIGN: just test the backward-jump TARGET
    //   COMPUTATION without requiring the branch to actually execute
    //   recursively. We do this by checking: after one backward DSJS,
    //   the program ends up at the target. We arrange the target
    //   to be a MOVI that writes a known sentinel value.
    //
    //   Layout:
    //     [0..2]  MOVI A3 = 5
    //     [3]     JRUC short +N (jump past back-target/DSJS to
    //             "main flow")
    //     [4..6]  MOVI A13 = LAND_BACK_VAL (back-target; 3 words)
    //     [7]     JRUC short +M (skip past DSJS after back-target
    //             executes once, so we don't fall into DSJS twice)
    //     [8]     DSJS A3 backward, offset such that target = word 4.
    //     [9..11] Skip-target / continue.
    //
    //   PC flow:
    //     start: MOVI A3=5 → PC = scen_start + 3.
    //     JRUC +N at scen_start+3 → target = scen_start+4+N words.
    //     We want it to skip over [4..7] (4 words) and land at [8]
    //     (the DSJS). disp = 8 - 4 = 4 words. So N=4.
    //     pc_at_WB = scen_start+4. target = (scen_start+4) + 4*16 bits
    //              = scen_start+8 (word). ✓
    //   At [8]: DSJS A3 backward. A3=5. alu_result=4. nonzero. Branch take.
    //     pc_at_WB = scen_start+9 (after the single-word fetch).
    //     We want target = scen_start+4 (word) = the MOVI A13 site.
    //     target_word = (scen_start+9) + (-off) words = scen_start+4.
    //     off = 5. With D=1: target = pc_at_WB - 5*16 bits.
    //   Then MOVI A13 executes (writing A13=LAND_BACK_VAL again).
    //   After MOVI A13, we hit [7]: JRUC short +M to skip past the
    //   DSJS to scen_start+9..+11 (continue). We want to land at
    //   scen_start+9 (after the DSJS, where execution continues).
    //   But the JRUC short at [7] has pc_at_WB = scen_start+8.
    //   target = (scen_start+8) + M*16 = scen_start+8+M words.
    //   We want target = scen_start+9, so M=1.
    //
    //   So:
    //     [0..2]  MOVI A3 = 5
    //     [3]     JRUC short +4  (= 0xC004)
    //     [4..6]  MOVI A13 = LAND_BACK_VAL
    //     [7]     JRUC short +1  (= 0xC001)
    //     [8]     DSJS A3 backward, off=5  (D=1, off=5, file=A, idx=3)
    //              = dsjs_enc(1, 5, A, 3) = 0x3800 | 0x0400 | 0xA0 | 3 = 0x3CA3
    //     [9..11] "Continue" — MOVI A15=1 to terminate or 0xC0FF halt.
    //
    //   At end-of-test: A13 = LAND_BACK_VAL (the DSJS backward jump
    //   succeeded and landed at the MOVI A13).
    //
    //   That's a lot of choreography. Let me code it.

    back_target_word = p + 4;  // index of the "back-target" MOVI A13 site
    p = place_movi_il(p, REG_FILE_A, 4'd3, 32'd5);                       // [0..2] MOVI A3 = 5
    u_mem.mem[p] = 16'hC004;                                  p = p + 1; // [3]    JRUC short +4
    p = place_movi_il(p, REG_FILE_A, 4'd13, 32'h0000_BEEF);              // [4..6] MOVI A13 = 0xBEEF (back-target)
    u_mem.mem[p] = 16'hC001;                                  p = p + 1; // [7]    JRUC short +1
    u_mem.mem[p] = dsjs_enc(1'b1, 5'd5, REG_FILE_A, 4'd3);    p = p + 1; // [8]    DSJS A3 bwd
    p = place_movi_il(p, REG_FILE_A, 4'd15, 32'd1);                      // [9..11] continuation

    // ---- Scenario 4: DSJS A4 +3 forward, Rd=0 → 0xFFFFFFFF, TAKE -----------
    p = place_movi_il(p, REG_FILE_A, 4'd4, 32'd0);
    u_mem.mem[p] = dsjs_enc(1'b0, 5'd3, REG_FILE_A, 4'd4);  p = p + 1;
    p = place_movi_il(p, REG_FILE_A, 4'd14, FALL_VAL);
    p = place_movi_il(p, REG_FILE_A, 4'd15, 32'd1);

    // ---- Halt at end ----------------------------------------------------------
    u_mem.mem[p] = 16'hC0FF;

    // Reset.
    repeat (3) @(posedge clk);
    rst = 1'b0;

    // ~50 instructions, ~700 cycles. Use 2000.
    repeat (2000) @(posedge clk);
    #1;

    // ---- Checks ------------------------------------------------------------
    // Scenario 1: DSJS A1 9→8, taken. A11 stays UNTOUCHED. A1 = 8.
    check_reg("Scen 1: DSJS A1 fwd 9→8 took → A11 UNTOUCHED",
              u_core.u_regfile.a_regs[11], UNTOUCHED);
    check_reg("Scen 1: counter A1 = 8 after DSJS 9→8",
              u_core.u_regfile.a_regs[1], 32'd8);

    // Scenario 2: DSJS A2 1→0, NOT taken. A12 = FALL_VAL. A2 = 0.
    check_reg("Scen 2: DSJS A2 fwd 1→0 NOT taken → A12 FALL_VAL",
              u_core.u_regfile.a_regs[12], FALL_VAL);
    check_reg("Scen 2: counter A2 = 0 after DSJS 1→0",
              u_core.u_regfile.a_regs[2], 32'd0);

    // Scenario 3: DSJS A3 backward, target = back-target MOVI A13.
    //   A13 should hold 0xBEEF (back-target MOVI value).
    //   A3 should be 4 after the decrement.
    check_reg("Scen 3: DSJS A3 bwd 5→4 took → A13 = 0xBEEF (back-target landed)",
              u_core.u_regfile.a_regs[13], 32'h0000_BEEF);
    check_reg("Scen 3: counter A3 = 4 after DSJS 5→4",
              u_core.u_regfile.a_regs[3], 32'd4);

    // Scenario 4: DSJS A4 0→0xFFFFFFFF, taken. A14 stays UNTOUCHED.
    check_reg("Scen 4: DSJS A4 fwd 0→0xFFFFFFFF took → A14 UNTOUCHED",
              u_core.u_regfile.a_regs[14], UNTOUCHED);
    check_reg("Scen 4: counter A4 = 0xFFFFFFFF after DSJS 0→-1",
              u_core.u_regfile.a_regs[4], 32'hFFFF_FFFF);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (DSJS: forward take/skip, backward take, 0→-1 take)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #4_000_000;
    $display("TEST_RESULT: FAIL: tb_dsjs hard timeout");
    $fatal(1);
  end

endmodule : tb_dsjs
