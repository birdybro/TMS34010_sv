// -----------------------------------------------------------------------------
// tb_setf.sv
//
// SETF FS, FE, F — Set Field Parameters. Per SPVU001A page 12-237 +
// summary table line 26978. Encoding:
//
//   bits[15:10] = 6'b000001
//   bit[9]      = F  (selector: 0 = FS0/FE0; 1 = FS1/FE1)
//   bit[8]      = 1  (constant)
//   bits[7:6]   = 2'b01 (sub-op marker)
//   bit[5]      = FE  (new FE value)
//   bits[4:0]   = FS  (new FS value; 5'b00000 → field-size 32)
//
// Status bits all "Unaffected" per spec.
//
// We can't easily encode all of this as a simple base + bitfield-OR
// because the bits aren't contiguous. The encoding helper composes
// the bits explicitly.
//
// Test plan:
//   1. After reset, ST = 0x0000_0010 (FS0=16, FE0=0, FS1=0, FE1=0).
//   2. SETF 17, 1, 0  → ST.FS0=17, ST.FE0=1. Other ST bits unchanged.
//   3. SETF 8,  0, 1  → ST.FS1=8, ST.FE1=0. FS0/FE0 from step 2 unchanged.
//   4. SETF 0,  1, 0  → ST.FS0=0 (encoding for size 32), ST.FE0=1.
//   5. SETF 31, 1, 1  → ST.FS1=31, ST.FE1=1.
//   6. After a CMP that sets NCZV=1101, then SETF — verify N, C, Z, V
//      are preserved (the "status unaffected" guarantee).
//
// We use GETST to snapshot ST after each SETF into a distinct register
// so we can verify the bit-fields independently.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_setf;
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
  //   SETF: bits = {6'b000001, F, 1'b1, 2'b01, FE, FS[4:0]}
  //   GETST Rd : 0x0180 | (R<<4) | Rd
  //   CMP Rs, Rd : 0x4800 | (Rs<<5) | (R<<4) | Rd
  //   MOVI IL Rd : 0x09E0 | (R<<4) | Rd
  // ---------------------------------------------------------------------------
  function automatic instr_word_t setf_enc(input logic [4:0] fs,
                                           input logic       fe,
                                           input logic       f_sel);
    setf_enc = (16'b0000_0100_0000_0000)           // bits[15:10] = 6'b000001
             | (instr_word_t'(f_sel) << 9)         // bit[9] = F
             | 16'b0000_0001_0000_0000              // bit[8] = 1
             | (16'b0000_0000_0100_0000)            // bits[7:6] = 2'b01
             | (instr_word_t'(fe) << 5)            // bit[5] = FE
             | instr_word_t'(fs);                   // bits[4:0] = FS
  endfunction

  function automatic instr_word_t getst_enc(input reg_idx_t rd);
    getst_enc = 16'h0180 | instr_word_t'(rd);
  endfunction

  function automatic instr_word_t cmp_rr_enc(input reg_idx_t rs, input reg_idx_t rd);
    cmp_rr_enc = 16'h4800 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
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

    // Encoding sanity:
    //   SETF FS=17, FE=1, F=0 = bits {000001, 0, 1, 01, 1, 10001}
    //     = 0000_0101_0011_0001 = 0x0531? Let me compute via the helper.
    //   The helper builds: 0x0400 | 0 | 0x0100 | 0x40 | 0x20 | 17 = 0x0571.
    //
    //   Hmm: 0x0400 | 0x100 | 0x40 | 0x20 | 0x11 (17) = 0x0571.
    //   So SETF 17, 1, 0 = 0x0571.
    if (setf_enc(5'd17, 1'b1, 1'b0) !== 16'h0571) begin
      $display("TEST_RESULT: FAIL: setf_enc(17,1,0) = %04h, expected 0571",
               setf_enc(5'd17, 1'b1, 1'b0));
      failures++;
    end
    //   SETF FS=8, FE=0, F=1 = 0x0400 | 0x200 (F=1) | 0x100 | 0x40 | 0 (FE) | 8 = 0x0748.
    if (setf_enc(5'd8, 1'b0, 1'b1) !== 16'h0748) begin
      $display("TEST_RESULT: FAIL: setf_enc(8,0,1) = %04h, expected 0748",
               setf_enc(5'd8, 1'b0, 1'b1));
      failures++;
    end

    // NOP-fill memory.
    for (i = 0; i < 256; i++) begin
      u_mem.mem[i] = 16'h0300;
    end

    p = 0;

    // ---- Scenario 1: SETF 17, 1, 0 — update FS0/FE0 ----------------------
    //   Initial ST = 0x0000_0010. After: FS0 = 17, FE0 = 1, all else unchanged.
    //   Expected ST = (32'h0000_0010 with bits[4:0] = 17 and bit[5] = 1)
    //               = 0x0000_0031 (FS0=17=0x11, FE0=1 → bit 5 set, so 0x20|0x11=0x31).
    u_mem.mem[p] = setf_enc(5'd17, 1'b1, 1'b0); p = p + 1;
    u_mem.mem[p] = getst_enc(4'd1);             p = p + 1;
    // A1 should now hold the ST snapshot.

    // ---- Scenario 2: SETF 8, 0, 1 — update FS1/FE1 ------------------------
    //   FS1 ← 8, FE1 ← 0. FS0/FE0 from Scen 1 must remain (17/1).
    //   ST after = previous (0x0031) + FS1=8 (bits[10:6]=01000=0x200) + FE1=0
    //            = 0x0231.
    u_mem.mem[p] = setf_enc(5'd8, 1'b0, 1'b1); p = p + 1;
    u_mem.mem[p] = getst_enc(4'd2);             p = p + 1;

    // ---- Scenario 3: SETF 0, 1, 0 — set FS0 = 0 (encodes field-size 32) ---
    //   FS0 ← 0, FE0 ← 1. FS1/FE1 unchanged from Scen 2.
    //   ST after = previous (0x0231) with bits[4:0]=0 and bit[5]=1
    //            = 0x0220 (FS0=0, FE0=1, FS1=8, FE1=0).
    u_mem.mem[p] = setf_enc(5'd0, 1'b1, 1'b0); p = p + 1;
    u_mem.mem[p] = getst_enc(4'd3);             p = p + 1;

    // ---- Scenario 4: SETF 31, 1, 1 — set FS1=31, FE1=1 -------------------
    //   ST after = previous (0x0220) with bits[10:6]=31=11111 (= 0x7C0) and
    //              bit[11]=1 (= 0x800)
    //            = (0x0220 & ~0xFC0) | 0xFC0 | 0  (FS0=0, FE0=1 untouched
    //              at bits[5:0] = 0x20).
    //   Bits: bit[11]=1, bits[10:6]=11111, bit[5]=1, bits[4:0]=0
    //       = 0x0800 | 0x07C0 | 0x20 | 0 = 0x0FE0.
    u_mem.mem[p] = setf_enc(5'd31, 1'b1, 1'b1); p = p + 1;
    u_mem.mem[p] = getst_enc(4'd4);             p = p + 1;

    // ---- Scenario 5: Status-bit preservation across SETF -----------------
    //   Use the CMP-NCZV=1101 trick from earlier tests. Then SETF FS=4 F=0,
    //   then GETST. Verify the top NCZV bits survive in the captured ST.
    p = place_movi_il(p, 4'd5, 32'h7FFF_FFFE);
    p = place_movi_il(p, 4'd6, 32'hFFFF_FFFE);
    u_mem.mem[p] = cmp_rr_enc(4'd6, 4'd5);     p = p + 1;
    //   After this CMP: NCZV = 1101 (N=1, C=1, Z=0, V=1).
    u_mem.mem[p] = setf_enc(5'd4, 1'b0, 1'b0); p = p + 1;
    u_mem.mem[p] = getst_enc(4'd7);             p = p + 1;
    //   After SETF 4,0,0: FS0=4, FE0=0. FS1/FE1 unchanged from Scen 4
    //   (FS1=31, FE1=1, so bit[11]=1, bits[10:6]=11111).
    //   Status bits N, C, Z, V from CMP preserved at 31..28.
    //   So expected ST = bit[31]=1, bit[30]=1, bit[29]=0, bit[28]=1,
    //                    bits[27..12]=0, bit[11]=1, bits[10:6]=11111,
    //                    bit[5]=0, bits[4:0]=00100 (FS=4)
    //                  = N|C|0|V|reserved|FE1|FS1|FE0|FS0
    //                  = 0xD000_0FE4? Let me compute:
    //   bit[31] = 1 (N) → 0x8000_0000
    //   bit[30] = 1 (C) → 0x4000_0000
    //   bit[29] = 0 (Z) → 0
    //   bit[28] = 1 (V) → 0x1000_0000
    //   bit[11] = 1 (FE1) → 0x0000_0800
    //   bits[10:6] = 11111 (FS1=31) → 0x0000_07C0
    //   bit[5] = 0 (FE0) → 0
    //   bits[4:0] = 00100 (FS0=4) → 0x0000_0004
    //   Total = 0xD000_0FC4.

    // Halt
    u_mem.mem[p] = 16'hC0FF;

    repeat (3) @(posedge clk);
    rst = 1'b0;

    repeat (1500) @(posedge clk);
    #1;

    // ---- Checks ------------------------------------------------------------
    check_reg("Scen 1: SETF 17,1,0 → A1 = 0x0031",
              u_core.u_regfile.a_regs[1], 32'h0000_0031);
    check_reg("Scen 2: SETF 8,0,1 → A2 = 0x0231",
              u_core.u_regfile.a_regs[2], 32'h0000_0231);
    check_reg("Scen 3: SETF 0,1,0 → A3 = 0x0220",
              u_core.u_regfile.a_regs[3], 32'h0000_0220);
    check_reg("Scen 4: SETF 31,1,1 → A4 = 0x0FE0",
              u_core.u_regfile.a_regs[4], 32'h0000_0FE0);
    check_reg("Scen 5: CMP+SETF preserves NCZV → A7 = 0xD0000FC4",
              u_core.u_regfile.a_regs[7], 32'hD000_0FC4);

    // Final ST should match the Scen-5 result.
    check_bit("Final ST.N preserved through SETF", u_core.u_status_reg.n_o, 1'b1);
    check_bit("Final ST.C preserved through SETF", u_core.u_status_reg.c_o, 1'b1);
    check_bit("Final ST.V preserved through SETF", u_core.u_status_reg.v_o, 1'b1);
    check_bit("illegal_opcode_o stayed 0",         illegal_w,                1'b0);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (SETF: FS0/FE0 + FS1/FE1 updates, FS=0 → 32, status preservation)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_setf hard timeout");
    $fatal(1);
  end

endmodule : tb_setf
