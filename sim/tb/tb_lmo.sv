// -----------------------------------------------------------------------------
// tb_lmo.sv
//
// LMO Rs, Rd (Find Leftmost-One priority encoder). Per SPVU001A
// page 12-108. Encoding `0110 101S SSSR DDDD` (top7 = 7'b0110_101).
//
// Semantics:
//   Rd ← 31 - bit_pos(leftmost-1 in Rs)  (bottom 5 bits, upper 27 = 0)
//   if Rs == 0: Rd ← 0; Z ← 1
//   else: Z ← 0
//   N, C, V: Unaffected
//
// Test vectors lifted directly from SPVU001A page 12-108's worked
// example table:
//
//   LMO A0, A1   Rs=0x00000000  → Rd = 0          Z=1
//   LMO A0, A1   Rs=0x00000001  → Rd = 0x1F (31)  Z=0
//   LMO A0, A1   Rs=0x00000010  → Rd = 0x1B (27)  Z=0
//   LMO A0, A1   Rs=0x08000000  → Rd = 0x04 (4)   Z=0
//   LMO A0, A1   Rs=0x80000000  → Rd = 0x00 (0)   Z=0
//
// Each scenario uses a distinct destination register so the
// end-of-test checks see independent results.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_lmo;
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
  //   LMO Rs, Rd = 0x6A00 | (Rs<<5) | (R<<4) | Rd  (top7=0x35; base 0x35<<9)
  // ---------------------------------------------------------------------------
  function automatic instr_word_t lmo_enc(input reg_idx_t  rs,
                                          input reg_file_t rf,
                                          input reg_idx_t  rd);
    lmo_enc = 16'h6A00
            | (instr_word_t'(rs) << 5)
            | (instr_word_t'(rf) << 4)
            | (instr_word_t'(rd));
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

  initial begin : main
    int unsigned p;
    int unsigned i;
    failures = 0;

    // Encoding sanity: LMO A1, A2 = 0x6A00 | (1<<5) | 2 = 0x6A22
    if (lmo_enc(4'd1, REG_FILE_A, 4'd2) !== 16'h6A22) begin
      $display("TEST_RESULT: FAIL: lmo_enc(A1,A2) = %04h, expected 6A22",
               lmo_enc(4'd1, REG_FILE_A, 4'd2));
      failures++;
    end

    // NOP-fill.
    for (i = 0; i < 256; i++) begin
      u_mem.mem[i] = 16'h0300;
    end

    p = 0;

    // ---- Spec test vectors from page 12-108 ------------------------------
    // For each scenario: load A0 with the Rs value, then LMO A0, A<dst>.
    //
    // Each scenario writes its result to a distinct destination
    // register so end-of-test we can check all five.
    //
    //   A1 ← LMO(0x00000000)  →  0x00000000  (Z=1)
    //   A2 ← LMO(0x00000001)  →  0x0000001F
    //   A3 ← LMO(0x00000010)  →  0x0000001B
    //   A4 ← LMO(0x08000000)  →  0x00000004
    //   A5 ← LMO(0x80000000)  →  0x00000000  (note: Z=0 here since Rs != 0)

    p = place_movi_il(p, REG_FILE_A, 4'd0, 32'h0000_0000);
    u_mem.mem[p] = lmo_enc(4'd0, REG_FILE_A, 4'd1); p = p + 1;

    p = place_movi_il(p, REG_FILE_A, 4'd0, 32'h0000_0001);
    u_mem.mem[p] = lmo_enc(4'd0, REG_FILE_A, 4'd2); p = p + 1;

    p = place_movi_il(p, REG_FILE_A, 4'd0, 32'h0000_0010);
    u_mem.mem[p] = lmo_enc(4'd0, REG_FILE_A, 4'd3); p = p + 1;

    p = place_movi_il(p, REG_FILE_A, 4'd0, 32'h0800_0000);
    u_mem.mem[p] = lmo_enc(4'd0, REG_FILE_A, 4'd4); p = p + 1;

    p = place_movi_il(p, REG_FILE_A, 4'd0, 32'h8000_0000);
    u_mem.mem[p] = lmo_enc(4'd0, REG_FILE_A, 4'd5); p = p + 1;

    // ---- N/C/V-preservation check ---------------------------------------
    // Set ST.N = ST.C = ST.V = 1 via the CMP trick used in tb_btst, then
    // run an LMO and verify N, C, V are preserved.
    //   A6 = 0x7FFFFFFE, A7 = 0xFFFFFFFE.  CMP A7, A6 → NCZV = 1101.
    p = place_movi_il(p, REG_FILE_A, 4'd6, 32'h7FFF_FFFE);
    p = place_movi_il(p, REG_FILE_A, 4'd7, 32'hFFFF_FFFE);
    u_mem.mem[p] = 16'h4800 | (instr_word_t'(7) << 5) | 4'd6; p = p + 1;  // CMP A7, A6
    //   After CMP: ST.NCZV = 1101.
    //   Re-load A0 = 0x0000_0010 and run LMO A0, A8.  Expected:
    //     A8 = 0x1B; Z=0; N, C, V preserved from CMP (1, 1, 1).
    p = place_movi_il(p, REG_FILE_A, 4'd0, 32'h0000_0010);
    // BUT the MOVI just clobbered ST. Re-do the CMP setup.
    p = place_movi_il(p, REG_FILE_A, 4'd6, 32'h7FFF_FFFE);
    p = place_movi_il(p, REG_FILE_A, 4'd7, 32'hFFFF_FFFE);
    u_mem.mem[p] = 16'h4800 | (instr_word_t'(7) << 5) | 4'd6; p = p + 1;
    //   ST.NCZV = 1101 again. Now LMO A0, A8.
    u_mem.mem[p] = lmo_enc(4'd0, REG_FILE_A, 4'd8); p = p + 1;
    //   After LMO: A8 = 0x1B (bit 4 set in A0=0x10 → LMO = 31-4 = 27 = 0x1B).
    //   ST.Z = 0 (A0 != 0). ST.N, C, V = 1 (preserved).

    // Halt
    u_mem.mem[p] = 16'hC0FF;

    repeat (3) @(posedge clk);
    rst = 1'b0;

    repeat (1500) @(posedge clk);
    #1;

    // ---- Spec-vector checks ---------------------------------------------
    check_reg("LMO 0x00000000 → A1 = 0",
              u_core.u_regfile.a_regs[1], 32'h0000_0000);
    check_reg("LMO 0x00000001 → A2 = 0x1F",
              u_core.u_regfile.a_regs[2], 32'h0000_001F);
    check_reg("LMO 0x00000010 → A3 = 0x1B",
              u_core.u_regfile.a_regs[3], 32'h0000_001B);
    check_reg("LMO 0x08000000 → A4 = 0x04",
              u_core.u_regfile.a_regs[4], 32'h0000_0004);
    check_reg("LMO 0x80000000 → A5 = 0",
              u_core.u_regfile.a_regs[5], 32'h0000_0000);

    // ---- N/C/V preservation across LMO ----------------------------------
    check_reg("LMO 0x00000010 → A8 = 0x1B (post-CMP setup)",
              u_core.u_regfile.a_regs[8], 32'h0000_001B);
    check_bit("LMO preserves ST.N (set by prior CMP)", u_core.u_status_reg.n_o, 1'b1);
    check_bit("LMO preserves ST.C (set by prior CMP)", u_core.u_status_reg.c_o, 1'b1);
    check_bit("LMO clears ST.Z (Rs was nonzero)",      u_core.u_status_reg.z_o, 1'b0);
    check_bit("LMO preserves ST.V (set by prior CMP)", u_core.u_status_reg.v_o, 1'b1);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (LMO: 5 spec vectors + N/C/V preservation)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_lmo hard timeout");
    $fatal(1);
  end

endmodule : tb_lmo
