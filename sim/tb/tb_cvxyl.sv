// -----------------------------------------------------------------------------
// tb_cvxyl.sv
//
// CVXYL (convert XY address to linear) — Task 0084. Per SPVU001A page 12-59:
//   linear = [(Y << (31 - CONVDP[4:0])) OR (X << log2(PSIZE))] + OFFSET
// X = Rs[15:0] (positive), Y = Rs[31:16] (signed). OFFSET is B-file B4;
// CONVDP and PSIZE are I/O registers. All status bits Unaffected.
//
// Vectors are TI's CVXYL example table (A0 = 0x00400030, i.e. X=0x30, Y=0x40).
// The table's PSIZE=4 / OFFSET!=0 rows are OCR-corrupted in the source (they
// drop the low X byte 0xC0); this test uses the rows the OCR preserved plus
// the recomputed exact values for the corrupted ones.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_cvxyl;
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
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack),
    .state_o(state_w), .pc_o(pc_w), .instr_word_o(instr_w), .illegal_opcode_o(illegal_w), .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1), .lint2_n_i(1'b1), .host_int_set_i(1'b0), .dpyint_set_i(1'b0), .refresh_req_o(), .refresh_row_o(), .refresh_cbr_o()
  );

  sim_memory_model #(.DEPTH_WORDS(256)) u_mem (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack)
  );

  function automatic instr_word_t movi_il_enc(input reg_idx_t i);
    movi_il_enc = 16'h09E0 | instr_word_t'(i);             // A-file MOVI IL
  endfunction
  function automatic instr_word_t movi_il_b_enc(input reg_idx_t i);
    movi_il_b_enc = 16'h09F0 | instr_word_t'(i);           // B-file MOVI IL (R=1)
  endfunction
  function automatic instr_word_t setf_enc(input logic [4:0] fs,
                                           input logic fe, input logic f_sel);
    setf_enc = 16'b0000_0100_0000_0000
             | (instr_word_t'(f_sel) << 9) | 16'b0000_0001_0000_0000
             | 16'b0000_0000_0100_0000 | (instr_word_t'(fe) << 5)
             | instr_word_t'(fs);
  endfunction
  function automatic instr_word_t cvxyl_enc(input reg_idx_t rs, input reg_idx_t rd);
    cvxyl_enc = 16'hE800 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
  endfunction
  // MOVE Rs,@DAddr store (set an I/O register): 0x0580 | Rs, addr LSW, MSW.
  function automatic int unsigned place_store_abs(input int unsigned p,
                                                  input reg_idx_t rs,
                                                  input logic [31:0] addr);
    u_mem.mem[p]     = 16'h0580 | instr_word_t'(rs);
    u_mem.mem[p + 1] = addr[15:0];
    u_mem.mem[p + 2] = addr[31:16];
    place_store_abs = p + 3;
  endfunction

  function automatic int unsigned place_movi_il(input int unsigned p,
                                                input reg_idx_t i,
                                                input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]     = movi_il_enc(i);
    u_mem.mem[p + 1] = imm[15:0];
    u_mem.mem[p + 2] = imm[31:16];
    place_movi_il = p + 3;
  endfunction
  function automatic int unsigned place_movi_il_b(input int unsigned p,
                                                  input reg_idx_t i,
                                                  input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]     = movi_il_b_enc(i);
    u_mem.mem[p + 1] = imm[15:0];
    u_mem.mem[p + 2] = imm[31:16];
    place_movi_il_b = p + 3;
  endfunction
  function automatic int unsigned place_word(input int unsigned p, input instr_word_t w);
    u_mem.mem[p] = w;  place_word = p + 1;
  endfunction

  int unsigned failures;
  task automatic check_reg(input string label,
                           input logic [DATA_WIDTH-1:0] actual, expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%08h actual=%08h", label, expected, actual);
      failures++;
    end
  endtask

  localparam logic [31:0] A_CONVDP = IO_BASE_ADDR + (IO_IDX_CONVDP << 4);
  localparam logic [31:0] A_PSIZE  = IO_BASE_ADDR + (IO_IDX_PSIZE  << 4);

  // Helper: build a program that sets PSIZE+CONVDP+OFFSET(B4)+A0, runs CVXYL
  // A0,A1, and leaves the result in A1. We just rebuild the whole program per
  // case in a loop driven from the testbench instead — simpler: one big
  // program covering several cases with distinct destination registers.
  initial begin : main
    int unsigned p, i;
    failures = 0;
    for (i = 0; i < 256; i++) u_mem.mem[i] = 16'h0300;   // NOP fill
    for (i = 120; i < 200; i++) u_mem.mem[i] = 16'h0000;

    p = 0;
    p = place_word(p, setf_enc(5'd16, 1'b0, 1'b0));      // FS0=16 for MOVE-to-I/O

    // Common: A0 = 0x00400030 (X=0x30, Y=0x40), OFFSET(B4)=0, CONVDP=0x14.
    p = place_movi_il  (p, 4'd0, 32'h0040_0030);         // A0 = XY
    p = place_movi_il_b(p, 4'd4, 32'h0000_0000);         // B4 = OFFSET = 0
    p = place_movi_il  (p, 4'd2, 32'h0000_0014);         // temp for CONVDP
    p = place_store_abs(p, 4'd2, A_CONVDP);              // CONVDP = 0x14

    // 1) PSIZE=16 -> A1 = 0x00020300.
    p = place_movi_il  (p, 4'd2, 32'h0000_0010);
    p = place_store_abs(p, 4'd2, A_PSIZE);
    p = place_word(p, cvxyl_enc(4'd0, 4'd1));            // A1 = CVXYL(A0)
    // 2) PSIZE=8  -> A3 = 0x00020180.
    p = place_movi_il  (p, 4'd2, 32'h0000_0008);
    p = place_store_abs(p, 4'd2, A_PSIZE);
    p = place_word(p, cvxyl_enc(4'd0, 4'd3));
    // 3) PSIZE=4  -> A5 = 0x000200C0  (exact; table OCR shows 0x00020000).
    p = place_movi_il  (p, 4'd2, 32'h0000_0004);
    p = place_store_abs(p, 4'd2, A_PSIZE);
    p = place_word(p, cvxyl_enc(4'd0, 4'd5));
    // 4) PSIZE=2  -> A6 = 0x00020060.
    p = place_movi_il  (p, 4'd2, 32'h0000_0002);
    p = place_store_abs(p, 4'd2, A_PSIZE);
    p = place_word(p, cvxyl_enc(4'd0, 4'd6));
    // 5) PSIZE=1  -> A7 = 0x00020030.
    p = place_movi_il  (p, 4'd2, 32'h0000_0001);
    p = place_store_abs(p, 4'd2, A_PSIZE);
    p = place_word(p, cvxyl_enc(4'd0, 4'd7));
    // 6) PSIZE=1, CONVDP=0x13 -> A8 = 0x00040030.
    p = place_movi_il  (p, 4'd2, 32'h0000_0013);
    p = place_store_abs(p, 4'd2, A_CONVDP);
    p = place_word(p, cvxyl_enc(4'd0, 4'd8));
    // 7) Nonzero OFFSET: B4=0x00008000, PSIZE=1, CONVDP=0x13 -> 0x00048030.
    p = place_movi_il_b(p, 4'd4, 32'h0000_8000);
    p = place_word(p, cvxyl_enc(4'd0, 4'd9));

    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (4000) @(posedge clk);
    #1;

    check_reg("1: PSIZE=16  -> 0x00020300", u_core.u_regfile.a_regs[1], 32'h0002_0300);
    check_reg("2: PSIZE=8   -> 0x00020180", u_core.u_regfile.a_regs[3], 32'h0002_0180);
    check_reg("3: PSIZE=4   -> 0x000200C0", u_core.u_regfile.a_regs[5], 32'h0002_00C0);
    check_reg("4: PSIZE=2   -> 0x00020060", u_core.u_regfile.a_regs[6], 32'h0002_0060);
    check_reg("5: PSIZE=1   -> 0x00020030", u_core.u_regfile.a_regs[7], 32'h0002_0030);
    check_reg("6: CONVDP=13 -> 0x00040030", u_core.u_regfile.a_regs[8], 32'h0004_0030);
    check_reg("7: OFFSET    -> 0x00048030", u_core.u_regfile.a_regs[9], 32'h0004_8030);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (CVXYL: XY->linear per TI example table, PSIZE/CONVDP/OFFSET)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #4_000_000;
    $display("TEST_RESULT: FAIL: tb_cvxyl hard timeout");
    $fatal(1);
  end

endmodule : tb_cvxyl
