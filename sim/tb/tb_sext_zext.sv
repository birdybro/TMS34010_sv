// -----------------------------------------------------------------------------
// tb_sext_zext.sv
//
// SEXT Rd, F  (Sign Extend to Long)  — SPVU001A page 12-238.
// ZEXT Rd, F  (Zero Extend to Long)  — SPVU001A page 12-256.
//
// Both instructions read the F-selected field-size (FS0 if F=0, FS1
// if F=1) from the status register and extend the low FS bits of Rd
// to 32 bits.
//
// Encodings:
//   SEXT: bits[15:10]=6'b000001, bit[9]=F, bit[8]=1, bits[7:5]=3'b000,
//         bit[4]=R, bits[3:0]=Rd  →  base 0x0500
//   ZEXT: same but bits[7:5]=3'b001  →  base 0x0520
//
// Flag policies:
//   SEXT: N, Z updated; C, V Unaffected.
//   ZEXT: Z updated;    N, C, V Unaffected.
//
// Test scenarios use the worked examples from pages 12-238 and 12-256.
// SETF is used to load FS0 / FS1 with the values the spec uses.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_sext_zext;
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
  //   SEXT Rd, F : 0x0500 | (F<<9) | (R<<4) | Rd
  //   ZEXT Rd, F : 0x0520 | (F<<9) | (R<<4) | Rd
  //   SETF       : bits = {6'b000001, F, 1'b1, 2'b01, FE, FS}
  //   MOVI IL Rd : 0x09E0 | (R<<4) | Rd  + LO + HI
  // ---------------------------------------------------------------------------
  function automatic instr_word_t sext_enc(input logic f, input reg_idx_t rd);
    sext_enc = 16'h0500 | (instr_word_t'(f) << 9) | instr_word_t'(rd);
  endfunction
  function automatic instr_word_t zext_enc(input logic f, input reg_idx_t rd);
    zext_enc = 16'h0520 | (instr_word_t'(f) << 9) | instr_word_t'(rd);
  endfunction
  function automatic instr_word_t setf_enc(input logic [4:0] fs,
                                           input logic       fe,
                                           input logic       f_sel);
    setf_enc = 16'h0540
             | (instr_word_t'(f_sel) << 9)
             | (instr_word_t'(fe) << 5)
             | instr_word_t'(fs);
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

    // NOP-fill.
    for (i = 0; i < 256; i++) begin
      u_mem.mem[i] = 16'h0300;
    end

    p = 0;

    // ============================================================
    // SEXT spec worked examples (page 12-238)
    //   SEXT AO,0  FS0=17  AO=0x00008000  →  AO = 0x00008000
    //   SEXT AO,0  FS0=16  AO=0x00008000  →  AO = 0xFFFF8000  (N=1)
    //   SEXT AO,0  FS0=15  AO=0x00008000  →  AO = 0x00000000  (Z=1)
    //   SEXT AO,1  FS1=17  AO=0x00008000  →  AO = 0x00008000
    //   SEXT AO,1  FS1=16  AO=0x00008000  →  AO = 0xFFFF8000
    //   SEXT AO,1  FS1=15  AO=0x00008000  →  AO = 0x00000000
    //
    // Each scenario: SETF (load FS); MOVI A0=0x00008000;
    //   SEXT to a fresh destination register so we can check each
    //   result independently.
    // ============================================================

    // Scen 1: FS0=17, SEXT A1, F=0 → A1 = 0x00008000 (unchanged)
    u_mem.mem[p] = setf_enc(5'd17, 1'b0, 1'b0); p = p + 1;
    p = place_movi_il(p, 4'd1, 32'h0000_8000);
    u_mem.mem[p] = sext_enc(1'b0, 4'd1);        p = p + 1;

    // Scen 2: FS0=16, SEXT A2, F=0 → A2 = 0xFFFF8000
    u_mem.mem[p] = setf_enc(5'd16, 1'b0, 1'b0); p = p + 1;
    p = place_movi_il(p, 4'd2, 32'h0000_8000);
    u_mem.mem[p] = sext_enc(1'b0, 4'd2);        p = p + 1;

    // Scen 3: FS0=15, SEXT A3, F=0 → A3 = 0x00000000
    u_mem.mem[p] = setf_enc(5'd15, 1'b0, 1'b0); p = p + 1;
    p = place_movi_il(p, 4'd3, 32'h0000_8000);
    u_mem.mem[p] = sext_enc(1'b0, 4'd3);        p = p + 1;

    // Scen 4: FS1=17, SEXT A4, F=1 → A4 = 0x00008000 (unchanged)
    u_mem.mem[p] = setf_enc(5'd17, 1'b0, 1'b1); p = p + 1;
    p = place_movi_il(p, 4'd4, 32'h0000_8000);
    u_mem.mem[p] = sext_enc(1'b1, 4'd4);        p = p + 1;

    // Scen 5: FS1=16, SEXT A5, F=1 → A5 = 0xFFFF8000
    u_mem.mem[p] = setf_enc(5'd16, 1'b0, 1'b1); p = p + 1;
    p = place_movi_il(p, 4'd5, 32'h0000_8000);
    u_mem.mem[p] = sext_enc(1'b1, 4'd5);        p = p + 1;

    // Scen 6: FS1=15, SEXT A6, F=1 → A6 = 0x00000000
    u_mem.mem[p] = setf_enc(5'd15, 1'b0, 1'b1); p = p + 1;
    p = place_movi_il(p, 4'd6, 32'h0000_8000);
    u_mem.mem[p] = sext_enc(1'b1, 4'd6);        p = p + 1;

    // ============================================================
    // ZEXT spec worked examples (page 12-256)
    //   ZEXT AO,0  FS0=32  AO=0xFFFFFFFF  →  AO = 0xFFFFFFFF  (no change)
    //   ZEXT AO,0  FS0=31  AO=0xFFFFFFFF  →  AO = 0x7FFFFFFF
    //   ZEXT AO,0  FS0= 1  AO=0xFFFFFFFF  →  AO = 0x00000001
    //   ZEXT AO,0  FS0=16  AO=0xFFFF0000  →  AO = 0x00000000  (Z=1)
    //   ZEXT AO,1  FS1=16  AO=0xFFFF0000  →  AO = 0x00000000  (Z=1)
    // ============================================================

    // Scen 7: FS0=0 (encodes 32), ZEXT A7 → A7 unchanged
    u_mem.mem[p] = setf_enc(5'd0, 1'b0, 1'b0); p = p + 1;
    p = place_movi_il(p, 4'd7, 32'hFFFF_FFFF);
    u_mem.mem[p] = zext_enc(1'b0, 4'd7);        p = p + 1;

    // Scen 8: FS0=31, ZEXT A8 → A8 = 0x7FFFFFFF
    u_mem.mem[p] = setf_enc(5'd31, 1'b0, 1'b0); p = p + 1;
    p = place_movi_il(p, 4'd8, 32'hFFFF_FFFF);
    u_mem.mem[p] = zext_enc(1'b0, 4'd8);        p = p + 1;

    // Scen 9: FS0=1, ZEXT A9 → A9 = 0x00000001
    u_mem.mem[p] = setf_enc(5'd1, 1'b0, 1'b0); p = p + 1;
    p = place_movi_il(p, 4'd9, 32'hFFFF_FFFF);
    u_mem.mem[p] = zext_enc(1'b0, 4'd9);        p = p + 1;

    // Scen 10: FS0=16, ZEXT A10 → A10 = 0x00000000 (Z=1 expected)
    u_mem.mem[p] = setf_enc(5'd16, 1'b0, 1'b0); p = p + 1;
    p = place_movi_il(p, 4'd10, 32'hFFFF_0000);
    u_mem.mem[p] = zext_enc(1'b0, 4'd10);       p = p + 1;

    // Scen 11: FS1=16, ZEXT A11 F=1 → A11 = 0x00000000
    u_mem.mem[p] = setf_enc(5'd16, 1'b0, 1'b1); p = p + 1;
    p = place_movi_il(p, 4'd11, 32'hFFFF_0000);
    u_mem.mem[p] = zext_enc(1'b1, 4'd11);       p = p + 1;

    // Halt.
    u_mem.mem[p] = 16'hC0FF;

    repeat (3) @(posedge clk);
    rst = 1'b0;

    repeat (3000) @(posedge clk);
    #1;

    // ---- SEXT spec-vector checks ----------------------------------------
    check_reg("SEXT FS0=17 A0=0x00008000 → A1 unchanged",
              u_core.u_regfile.a_regs[1], 32'h0000_8000);
    check_reg("SEXT FS0=16 A0=0x00008000 → A2 = 0xFFFF8000",
              u_core.u_regfile.a_regs[2], 32'hFFFF_8000);
    check_reg("SEXT FS0=15 A0=0x00008000 → A3 = 0x00000000",
              u_core.u_regfile.a_regs[3], 32'h0000_0000);
    check_reg("SEXT FS1=17 → A4 unchanged",
              u_core.u_regfile.a_regs[4], 32'h0000_8000);
    check_reg("SEXT FS1=16 → A5 = 0xFFFF8000",
              u_core.u_regfile.a_regs[5], 32'hFFFF_8000);
    check_reg("SEXT FS1=15 → A6 = 0x00000000",
              u_core.u_regfile.a_regs[6], 32'h0000_0000);

    // ---- ZEXT spec-vector checks ----------------------------------------
    check_reg("ZEXT FS0=32 (encoding 0) A0=0xFFFFFFFF → A7 unchanged",
              u_core.u_regfile.a_regs[7], 32'hFFFF_FFFF);
    check_reg("ZEXT FS0=31 → A8 = 0x7FFFFFFF",
              u_core.u_regfile.a_regs[8], 32'h7FFF_FFFF);
    check_reg("ZEXT FS0=1 → A9 = 0x00000001",
              u_core.u_regfile.a_regs[9], 32'h0000_0001);
    check_reg("ZEXT FS0=16 A0=0xFFFF0000 → A10 = 0",
              u_core.u_regfile.a_regs[10], 32'h0000_0000);
    check_reg("ZEXT FS1=16 → A11 = 0",
              u_core.u_regfile.a_regs[11], 32'h0000_0000);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (SEXT + ZEXT: 11 spec-vector tests including FS=0→32 edge)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #4_000_000;
    $display("TEST_RESULT: FAIL: tb_sext_zext hard timeout");
    $fatal(1);
  end

endmodule : tb_sext_zext
