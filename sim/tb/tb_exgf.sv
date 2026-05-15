// -----------------------------------------------------------------------------
// tb_exgf.sv
//
// EXGF Rd, F — Exchange Field Definition. Per SPVU001A page 12-77 +
// summary table line 26954. Encoding `1101 01F1 000R DDDD`:
//
//   bits[15:10] = 6'b110101 (= 0x35)
//   bit[9]      = F (selector: 0 = FE0/FS0; 1 = FE1/FS1)
//   bit[8]      = 1 (constant)
//   bits[7:5]   = 000 (sub-op)
//   bit[4]      = R (file)
//   bits[3:0]   = Rd index
//
// Atomic swap: Rd[5:0] ↔ {FE<F>, FS<F>}. Rd's upper 26 bits cleared.
// Status bits N, C, Z, V all "Unaffected".
//
// The spec page 12-77 worked-example table has two scenarios:
//
//   EXGF A5,0  Before A5=0xFFFFFFC0, ST=0xF00000FFF
//              After  A5=0x0000003F, ST=0xF00000FC0
//
//   EXGF A5,1  Before A5=0xFFFFFFC0, ST=0xF00000FFF
//              After  A5=0x0000003F, ST=0xF000003F
//
// Notes:
//   - In both cases, A5_after = 0x3F because the FE0/FS0 and FE1/FS1
//     happen to both be 6'b111111 in ST_before.
//   - ST_after differs because F=0 modifies bits[5:0]; F=1 modifies
//     bits[11:6].
//
// Verification strategy: PUTST to set ST = 0xF00000FFF, MOVI to load
// A5 = 0xFFFFFFC0, run EXGF, capture A5 and ST via GETST. Then reset
// ST/A5 and run the F=1 case. Each scenario uses a distinct
// destination register to avoid clobbering across runs.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_exgf;
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
  //   EXGF Rd, F : bits[15:10]=110101, bit[9]=F, bit[8]=1, bits[7:5]=000,
  //                bit[4]=R, bits[3:0]=Rd
  //   Base = (110101 << 10) | (1 << 8) = 0xD500.
  //   So EXGF A5, 0 = 0xD500 | 0 | 0 | 5 = 0xD505.
  //   And EXGF A5, 1 = 0xD500 | (1<<9) | 5 = 0xD705.
  // ---------------------------------------------------------------------------
  function automatic instr_word_t exgf_enc(input logic f, input reg_idx_t rd);
    exgf_enc = 16'hD500 | (instr_word_t'(f) << 9) | instr_word_t'(rd);
  endfunction

  function automatic instr_word_t getst_enc(input reg_idx_t rd);
    getst_enc = 16'h0180 | instr_word_t'(rd);
  endfunction
  function automatic instr_word_t putst_enc(input reg_idx_t rs);
    putst_enc = 16'h01A0 | instr_word_t'(rs);
  endfunction
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

  initial begin : main
    int unsigned p;
    int unsigned i;
    failures = 0;

    // Encoding sanity:  EXGF A5, 0 = 0xD505; EXGF A5, 1 = 0xD705.
    if (exgf_enc(1'b0, 4'd5) !== 16'hD505) begin
      $display("TEST_RESULT: FAIL: exgf_enc(0,A5) = %04h, expected D505",
               exgf_enc(1'b0, 4'd5));
      failures++;
    end
    if (exgf_enc(1'b1, 4'd5) !== 16'hD705) begin
      $display("TEST_RESULT: FAIL: exgf_enc(1,A5) = %04h, expected D705",
               exgf_enc(1'b1, 4'd5));
      failures++;
    end

    // NOP-fill.
    for (i = 0; i < 256; i++) begin
      u_mem.mem[i] = 16'h0300;
    end

    p = 0;

    // ============================================================
    // Scenario 1: EXGF A1, F=0
    //   Before: A1 = 0xFFFFFFC0, ST = 0xF000_0FFF
    //   After:  A1 = 0x0000003F, ST = 0xF000_0FC0
    //
    // CRITICAL: MOVI updates ST.{N,C,Z,V}, so we must PUTST AFTER
    // all the data-loading MOVIs. Sequence:
    //   1. MOVI A0 = target_ST_value   (ST clobbered — OK)
    //   2. MOVI A1 = target_A1_value   (ST clobbered — OK)
    //   3. PUTST A0                     (ST ← A0)
    //   4. EXGF A1, 0                   (atomic swap)
    //   5. GETST A2                     (capture new ST)
    // ============================================================
    p = place_movi_il(p, 4'd0, 32'hF000_0FFF);
    p = place_movi_il(p, 4'd1, 32'hFFFF_FFC0);
    u_mem.mem[p] = putst_enc(4'd0); p = p + 1;
    u_mem.mem[p] = exgf_enc(1'b0, 4'd1); p = p + 1;
    u_mem.mem[p] = getst_enc(4'd2); p = p + 1;

    // ============================================================
    // Scenario 2: EXGF A3, F=1
    //   Same setup pattern as scen 1, but EXGF F=1.
    // ============================================================
    p = place_movi_il(p, 4'd0, 32'hF000_0FFF);
    p = place_movi_il(p, 4'd3, 32'hFFFF_FFC0);
    u_mem.mem[p] = putst_enc(4'd0); p = p + 1;
    u_mem.mem[p] = exgf_enc(1'b1, 4'd3); p = p + 1;
    u_mem.mem[p] = getst_enc(4'd4); p = p + 1;

    // Halt
    u_mem.mem[p] = 16'hC0FF;

    repeat (3) @(posedge clk);
    rst = 1'b0;

    repeat (1500) @(posedge clk);
    #1;

    // ---- Checks ------------------------------------------------------------
    // Scenario 1
    check_reg("EXGF A1, F=0: A1 = 0x0000003F (the FE0/FS0 bits)",
              u_core.u_regfile.a_regs[1], 32'h0000_003F);
    check_reg("EXGF A1, F=0: ST snapshot A2 = 0xF000_0FC0",
              u_core.u_regfile.a_regs[2], 32'hF000_0FC0);

    // Scenario 2
    check_reg("EXGF A3, F=1: A3 = 0x0000003F",
              u_core.u_regfile.a_regs[3], 32'h0000_003F);
    check_reg("EXGF A3, F=1: ST snapshot A4 = 0xF000_003F",
              u_core.u_regfile.a_regs[4], 32'hF000_003F);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (EXGF F=0 and F=1: both spec vectors from page 12-77)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_exgf hard timeout");
    $fatal(1);
  end

endmodule : tb_exgf
