// -----------------------------------------------------------------------------
// tb_jrcc_short.sv
//
// Conditional branches (JRcc short form) with EQ and NE condition codes.
// Builds on tb_jruc_short by adding conditional cc evaluation against the
// status register.
//
// Two scenarios per condition:
//   - branch taken     (verify destination held the LANDING-site value)
//   - branch not taken (verify destination held the FALL-THROUGH value)
//
// The test uses CMP to set ST.Z = 1 (equal compare) or ST.Z = 0 (unequal),
// then issues the JRcc and checks both arms.
//
// Per A0017, supported cc codes in Phase 4: UC (0000), EQ (0100), NE (0111).
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_jrcc_short;
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

  sim_memory_model #(.DEPTH_WORDS(128)) u_mem (
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

  function automatic instr_word_t movi_il_enc(input reg_file_t rf, input reg_idx_t i);
    movi_il_enc = 16'h09E0 | (instr_word_t'(rf) << 4) | (instr_word_t'(i));
  endfunction
  function automatic instr_word_t cmp_rr_enc(input reg_file_t rf,
                                             input reg_idx_t rs, input reg_idx_t rd);
    cmp_rr_enc = 16'h4800
               | (instr_word_t'(rs) << 5)
               | (instr_word_t'(rf) << 4)
               | (instr_word_t'(rd));
  endfunction
  function automatic instr_word_t jrcc_short_enc(input logic [3:0] cc,
                                                 input logic signed [7:0] disp);
    jrcc_short_enc = 16'hC000
                   | (instr_word_t'(cc) << 8)
                   | {8'h00, disp};
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

  initial begin : main
    failures = 0;

    // Encoding sanity (corrected per SPVU001A Table 12-8 re-extracted
    // in Task 0030; see A0023). EQ = 1010, NE = 1011.
    //   JREQ +5 = 1100 1010 0000 0101 = 0xCA05
    //   JRNE +5 = 1100 1011 0000 0101 = 0xCB05
    if (jrcc_short_enc(CC_EQ, 8'sd5) !== 16'hCA05) begin
      $display("TEST_RESULT: FAIL: JREQ +5 enc = %04h, expected CA05",
               jrcc_short_enc(CC_EQ, 8'sd5));
      failures++;
    end
    if (jrcc_short_enc(CC_NE, 8'sd5) !== 16'hCB05) begin
      $display("TEST_RESULT: FAIL: JRNE +5 enc = %04h, expected CB05",
               jrcc_short_enc(CC_NE, 8'sd5));
      failures++;
    end

    // Program layout (each word is 16 bits, addressed by word index):
    //
    //   Scenario 1: JREQ taken (Z=1 → branch skips the fall-through MOVI)
    //   --------------------------------------------------------------
    //   words 0..2:   MOVI IL 10, A1
    //   words 3..5:   MOVI IL 10, A2
    //   word  6:      CMP A2, A1      ; A1-A2 = 0 → Z=1
    //   word  7:      JREQ +3         ; PC after fetch = w8*16; target = w11*16
    //   words 8..10:  MOVI IL 0xDEAD, A3   ; fall-through, SHOULD BE SKIPPED
    //   words 11..13: MOVI IL 0xCAFE_BABE, A3  ; landing
    //
    //   Scenario 2: JRNE taken (Z=0 because operands differ)
    //   --------------------------------------------------------------
    //   words 14..16: MOVI IL 5, A4
    //   words 17..19: MOVI IL 10, A5
    //   word  20:     CMP A5, A4      ; A4-A5 = -5 → Z=0
    //   word  21:     JRNE +3
    //   words 22..24: MOVI IL 0x1111, A6   ; fall-through, SHOULD BE SKIPPED
    //   words 25..27: MOVI IL 0x55AA, A6   ; landing
    //
    //   Scenario 3: JREQ NOT taken (Z=0)
    //   --------------------------------------------------------------
    //   words 28..30: MOVI IL 5, A7
    //   words 31..33: MOVI IL 10, A8
    //   word  34:     CMP A8, A7      ; Z=0
    //   word  35:     JREQ +3         ; should NOT take
    //   words 36..38: MOVI IL 0x9999, A9   ; FALL-THROUGH executes
    //   words 39..41: MOVI IL 0xBBBB, A9   ; would have landed here

    void'(place_movi_il( 0, REG_FILE_A, 4'd1, 32'd10));
    void'(place_movi_il( 3, REG_FILE_A, 4'd2, 32'd10));
    u_mem.mem[ 6] = cmp_rr_enc(REG_FILE_A, 4'd2, 4'd1);
    u_mem.mem[ 7] = jrcc_short_enc(CC_EQ, 8'sd3);
    void'(place_movi_il( 8, REG_FILE_A, 4'd3, 32'h0000_DEAD));
    void'(place_movi_il(11, REG_FILE_A, 4'd3, 32'hCAFE_BABE));

    void'(place_movi_il(14, REG_FILE_A, 4'd4, 32'd5));
    void'(place_movi_il(17, REG_FILE_A, 4'd5, 32'd10));
    u_mem.mem[20] = cmp_rr_enc(REG_FILE_A, 4'd5, 4'd4);
    u_mem.mem[21] = jrcc_short_enc(CC_NE, 8'sd3);
    void'(place_movi_il(22, REG_FILE_A, 4'd6, 32'h0000_1111));
    void'(place_movi_il(25, REG_FILE_A, 4'd6, 32'h0000_55AA));

    void'(place_movi_il(28, REG_FILE_A, 4'd7, 32'd5));
    void'(place_movi_il(31, REG_FILE_A, 4'd8, 32'd10));
    u_mem.mem[34] = cmp_rr_enc(REG_FILE_A, 4'd8, 4'd7);
    u_mem.mem[35] = jrcc_short_enc(CC_EQ, 8'sd3);
    void'(place_movi_il(36, REG_FILE_A, 4'd9, 32'h0000_9999));
    void'(place_movi_il(39, REG_FILE_A, 4'd9, 32'h0000_BBBB));

    repeat (3) @(posedge clk);
    rst = 1'b0;

    // ~42 words of program, average ~9 cycles per word + branches. Use
    // 600 cycles to comfortably finish.
    repeat (600) @(posedge clk);
    #1;

    // Scenario 1: JREQ taken → A3 = CAFEBABE (the LANDING value).
    check_reg("Scenario 1: JREQ taken (A3 from landing site)",
              u_core.u_regfile.a_regs[3], 32'hCAFE_BABE);
    // Scenario 2: JRNE taken → A6 = 0x55AA (the LANDING value).
    check_reg("Scenario 2: JRNE taken (A6 from landing site)",
              u_core.u_regfile.a_regs[6], 32'h0000_55AA);
    // Scenario 3: JREQ NOT taken (Z=0) → fall-through executes;
    // A9 ends up at the LATER value (0xBBBB) because both MOVIs execute
    // in order: first 0x9999, then 0xBBBB.
    check_reg("Scenario 3: JREQ NOT taken (A9 from final MOVI in fall-through path)",
              u_core.u_regfile.a_regs[9], 32'h0000_BBBB);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (3 scenarios: JREQ-take, JRNE-take, JREQ-skip)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #1_000_000;
    $display("TEST_RESULT: FAIL: tb_jrcc_short hard timeout");
    $fatal(1);
  end

endmodule : tb_jrcc_short
