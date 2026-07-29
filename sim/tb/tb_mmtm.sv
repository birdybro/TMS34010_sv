// -----------------------------------------------------------------------------
// tb_mmtm.sv
//
// MMTM Rp, register list — Move Multiple Registers to Memory. Per
// SPVU001A page 12-111. Encoding `0000 1001 100R DDDD` + 16-bit mask
// word. For each register Rn in the list (lowest-order first), Rp is
// predecremented by 32 and Rn's 32-bit value is written to mem[Rp].
//
// This is the first instruction in the project where the *number* of
// memory transactions is data-dependent — it equals the population
// count of the second instruction word. Up to 16 32-bit writes.
//
// Assumption A0026 (also called out in tms34010_core.sv): bit N of
// the mask = register R(N). The spec's actual chart is a graphical
// figure that didn't survive pdftotext extraction; this reading is
// consistent with the spec's "lowest-order register is always saved
// first" requirement when the iterator scans LSB-first.
//
// Test plan:
//   1. Pre-load A0..A14 with recognisable values (0xAnAnAnAn-style).
//   2. Set Rp (A1) to a mid-memory bit address (0x0000_0800 = word 128).
//   3. MMTM A1, {A0, A2, A4, A8, A12, A13, A14, A15(=SP)}:
//        mask = bit 0 + 2 + 4 + 8 + 12 + 13 + 14 + 15 = 0xF115.
//        ⇒ second word = 0xF115.
//   4. Verify final A1 = 0x0800 - 8*32 = 0x0800 - 0x100 = 0x0700.
//   5. Verify memory layout (lowest addr has highest-order register):
//        mem[bit 0x0700] = SP (A15)
//        mem[bit 0x0720] = A14
//        mem[bit 0x0740] = A13
//        mem[bit 0x0760] = A12
//        mem[bit 0x0780] = A8
//        mem[bit 0x07A0] = A4
//        mem[bit 0x07C0] = A2
//        mem[bit 0x07E0] = A0
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_mmtm;
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
    .illegal_opcode_o(illegal_w), .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1), .lint2_n_i(1'b1), .host_int_set_i(1'b0), .dpyint_set_i(1'b0), .refresh_req_o(), .refresh_row_o(), .refresh_cbr_o()
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

  function automatic instr_word_t movi_il_enc(input reg_idx_t i);
    movi_il_enc = 16'h09E0 | instr_word_t'(i);
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
  task automatic check_mem32(input string label,
                             input int unsigned word_idx_lo,
                             input logic [DATA_WIDTH-1:0] expected);
    logic [DATA_WIDTH-1:0] actual;
    actual = {u_mem.mem[word_idx_lo + 1], u_mem.mem[word_idx_lo]};
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%08h actual=%08h (mem[%0d:%0d])",
               label, expected, actual, word_idx_lo + 1, word_idx_lo);
      failures++;
    end
  endtask

  // Rp = A1; initial Rp bit-address = 0x0800 = word 128.
  localparam logic [DATA_WIDTH-1:0] RP_INIT = 32'h0000_0800;
  // Mask for {A0, A2, A4, A8, A12, A13, A14, A15} = bits 0,2,4,8,12,13,14,15
  // = 0xF115 (1111_0001_0001_0101).
  localparam logic [15:0]           MASK    = 16'hF115;

  // Per-register sentinel values for A0..A15. A1 (Rp) is set
  // separately and must NOT be in the list per spec.
  function automatic logic [DATA_WIDTH-1:0] reg_sentinel(input int idx);
    reg_sentinel = {16'(idx) * 16'h0101, 16'(idx) * 16'h1010};
  endfunction

  initial begin : main
    int unsigned p;
    int unsigned i;
    failures = 0;

    // NOP-fill.
    for (i = 0; i < 512; i++) begin
      u_mem.mem[i] = 16'h0300;
    end

    // ---- Pre-program: load A0..A14 (skip A1 which we'll set last
    //      since its value is Rp), then load A15 (SP), then MMTM. -----
    p = 0;
    for (i = 0; i < 15; i++) begin
      if (i == 1) continue; // skip A1 (Rp) — set last so subsequent
                            // MOVI flag updates don't matter
      p = place_movi_il(p, 4'(i), reg_sentinel(i));
    end
    // MOVI A14, sentinel for A15: load A14 with sentinel, then MOVE A14, A15.
    // Cheaper: MOVI A14 already loaded with its own sentinel above. We
    // want SP = sentinel(15). Use a separate MOVI on A14 (overwrite)
    // then MOVE.
    p = place_movi_il(p, 4'd14, reg_sentinel(15));   // A14 = sentinel(15)
    // MOVE A14, A15 (SPVU001A p.12-126): top6=010011 (0x4C00), M=0, Rs=14, R=0, Rd=15 ⇒ 0x4DCF.
    u_mem.mem[p] = 16'h4DCF; p = p + 1;              // MOVE A14, A15 (SP <- A14)
    p = place_movi_il(p, 4'd14, reg_sentinel(14));   // restore A14 sentinel
    // Now load A1 (= Rp).
    p = place_movi_il(p, 4'd1, RP_INIT);

    // ---- MMTM A1, mask ------------------------------------------------
    // Encoding: 0000 1001 100R DDDD | mask
    //   top11 = 11'b00001001_100, R=0 (A file), DDDD = 1 (A1).
    //   First word = 0b00001001_1000_0001 = 0x0981.
    u_mem.mem[p] = 16'h0981; p = p + 1;
    u_mem.mem[p] = MASK;     p = p + 1;

    // Halt sentinel after MMTM so the core doesn't wander into the
    // NOP-fill / pushed-register region and assert illegal_opcode_o
    // unrelated to MMTM.
    u_mem.mem[p] = 16'hC0FF; p = p + 1;

    repeat (3) @(posedge clk);
    rst = 1'b0;

    // 8 pushes × ~3 cycles each + setup ≈ 100 cycles. Be generous.
    repeat (4000) @(posedge clk);
    #1;

    // -------- Checks --------------------------------------------------
    // Final A1 = RP_INIT - 8*32 = 0x0800 - 0x100 = 0x0700.
    check_reg("MMTM: A1 (Rp) = RP_INIT - 8*32",
              u_core.u_regfile.a_regs[1], RP_INIT - 32'(8*32));

    // Stack layout: lowest-order register (A0) at HIGHEST address;
    // highest-order register (A15=SP) at LOWEST address.
    // Push order LSB→MSB: A0, A2, A4, A8, A12, A13, A14, A15(=SP).
    // Address (in bit-units): RP_INIT - 32, RP_INIT - 64, ...
    // Word index (= bit_addr / 16):
    //   A0  at bit 0x07E0 = word 126 (low) + 127 (high)
    //   A2  at bit 0x07C0 = word 124..125
    //   A4  at bit 0x07A0 = word 122..123
    //   A8  at bit 0x0780 = word 120..121
    //   A12 at bit 0x0760 = word 118..119
    //   A13 at bit 0x0740 = word 116..117
    //   A14 at bit 0x0720 = word 114..115
    //   A15 at bit 0x0700 = word 112..113   ← final Rp
    check_mem32("MMTM: mem[Rp-32]  = A0",  126, reg_sentinel(0));
    check_mem32("MMTM: mem[Rp-64]  = A2",  124, reg_sentinel(2));
    check_mem32("MMTM: mem[Rp-96]  = A4",  122, reg_sentinel(4));
    check_mem32("MMTM: mem[Rp-128] = A8",  120, reg_sentinel(8));
    check_mem32("MMTM: mem[Rp-160] = A12", 118, reg_sentinel(12));
    check_mem32("MMTM: mem[Rp-192] = A13", 116, reg_sentinel(13));
    check_mem32("MMTM: mem[Rp-224] = A14", 114, reg_sentinel(14));
    check_mem32("MMTM: mem[Rp-256] = SP",  112, reg_sentinel(15));

    // N flag (SPVU001A page 12-111) = sign of (0 - Rp) = ~Rp[31]. The
    // initial Rp (0x0800) is positive, so N must be 1. C/Z/V Unaffected.
    // The trailing 0xC0FF (JRUC -1) halt doesn't touch flags, so the
    // MMTM-set N persists to here.
    if (u_core.st_n !== 1'b1) begin
      $display("TEST_RESULT: FAIL: MMTM N flag: expected 1 (Rp positive), actual %0b",
               u_core.st_n);
      failures++;
    end

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (MMTM: 8 registers pushed LSB-first; Rp = RP_INIT - 256)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #5_000_000;
    $display("TEST_RESULT: FAIL: tb_mmtm hard timeout");
    $fatal(1);
  end

endmodule : tb_mmtm
