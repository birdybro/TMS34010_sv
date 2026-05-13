// -----------------------------------------------------------------------------
// tb_nop.sv
//
// End-to-end test for `NOP` (No Operation).
//
// Strategy:
//   Program three instructions back-to-back:
//     1. MOVI IW 0xFFFF, A0   — writes A0 = sign_ext(0xFFFF) = 0xFFFF_FFFF
//                               and sets ST.N = 1, ST.Z = 0.
//     2. NOP                  — must NOT touch A0 or ST, must advance PC.
//     3. MOVK 7, B5           — single-word writeback to B5; MOVK does
//                               not modify ST.
//
//   After the program runs we verify five things:
//     - A0 still holds the MOVI value (NOP did not clobber it).
//     - ST.N still 1, ST.Z still 0 (NOP did not update flags).
//     - B5 = 7 (the post-NOP instruction reached executable state → PC
//       advanced through the NOP correctly).
//     - illegal_opcode_o stayed 0 throughout (NOP was recognized as
//       valid, not flagged).
//     - Encoding helper produces 0x0300 (matches SPVU001A 12-170 / A0021).
//
// Spec citation: third_party/TMS34010_Info/docs/ti-official/
//                1988_TI_TMS34010_Users_Guide.pdf §"NOP" page 12-170
//                (also instruction-summary table). Encoding = 0x0300.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_nop;
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
  //   NOP            = 0x0300                              (A0021)
  //   MOVI IW K, Rd  = 0x09C0 | (R<<4) | N, + 16-bit imm   (A0012)
  //   MOVK K, Rd     = 0x1800 | (K<<5) | (R<<4) | N         (A0013)
  // ---------------------------------------------------------------------------
  function automatic instr_word_t nop_enc();
    nop_enc = 16'h0300;
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

    // Encoding sanity-check: NOP must be exactly 0x0300.
    if (nop_enc() !== 16'h0300) begin
      $display("TEST_RESULT: FAIL: nop_enc() = %04h, expected 0300",
               nop_enc());
      failures++;
    end

    // Default-fill every memory word with NOP so the CPU keeps NOPing if
    // it runs past the meaningful program. This keeps the
    // `illegal_opcode_o == 0` check meaningful at end-of-test (vs. tb_movi
    // which gives that check up once 0x0000 fetches start). It also
    // exercises NOP many more times.
    for (i = 0; i < 64; i++) begin
      u_mem.mem[i] = nop_enc();
    end

    // Program layout (overwrites the NOP fill at the relevant slots):
    //   word 0: MOVI IW A0          ← opcode
    //   word 1: 0xFFFF              ← 16-bit immediate, sign-extends to all-ones
    //   word 2: NOP                  ← the one we explicitly want under test
    //   word 3: MOVK 7, B5
    u_mem.mem[0] = movi_iw_enc(REG_FILE_A, 4'd0);
    u_mem.mem[1] = 16'hFFFF;
    u_mem.mem[2] = nop_enc();
    u_mem.mem[3] = movk_enc(5'd7, REG_FILE_B, 4'd5);

    // Reset.
    repeat (3) @(posedge clk);
    rst = 1'b0;

    // Three instructions:
    //   MOVI IW: 1 opcode fetch + 1 imm fetch + DECODE + EXECUTE + WB ≈ 7 cy
    //   NOP    : 1 opcode fetch + DECODE + EXECUTE + WB                ≈ 5 cy
    //   MOVK   : 1 opcode fetch + DECODE + EXECUTE + WB                ≈ 5 cy
    // ~20 cycles; use 60 for headroom.
    repeat (60) @(posedge clk);
    #1;

    // A0 holds the sign-extended MOVI value — NOP did not clobber it.
    check_word("A0 after MOVI;NOP;MOVK", u_core.u_regfile.a_regs[0],
               32'hFFFF_FFFF);

    // B5 holds the post-NOP MOVK value — PC advanced through NOP.
    check_word("B5 after MOVK following NOP", u_core.u_regfile.b_regs[5],
               32'h0000_0007);

    // ST.N and ST.Z still reflect the MOVI result — NOP did not update flags,
    // and MOVK (per A0011/A0013) does not update flags either.
    check_bit("ST.N preserved across NOP+MOVK", u_core.u_status_reg.n_o, 1'b1);
    check_bit("ST.Z preserved across NOP+MOVK", u_core.u_status_reg.z_o, 1'b0);

    // NOP must NOT trip the illegal-opcode latch.
    check_bit("illegal_opcode_o after valid program", illegal_w, 1'b0);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (NOP decoded, no Rd/ST writes, PC advanced)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #100_000;
    $display("TEST_RESULT: FAIL: tb_nop hard timeout");
    $fatal(1);
  end

endmodule : tb_nop
