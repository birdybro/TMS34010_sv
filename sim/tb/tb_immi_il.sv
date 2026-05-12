// -----------------------------------------------------------------------------
// tb_immi_il.sv
//
// Tests the six IL-form immediate instructions (32-bit immediate):
//   ADDI IL K, Rd     Rd + K32 → Rd     (N/C/Z/V)
//   SUBI IL K, Rd     Rd - K32 → Rd     (N/C/Z/V)
//   CMPI IL K, Rd     flags from Rd - K32; Rd unchanged
//   ANDI IL K, Rd     Rd & K32 → Rd     (N, Z)
//   ORI  IL K, Rd     Rd | K32 → Rd     (N, Z)
//   XORI IL K, Rd     Rd ^ K32 → Rd     (N, Z)
//
// All six reuse MOVI IL's CORE_FETCH_IMM_LO/HI path.
// SUBI IL has a different base prefix (0000_1101 instead of 0000_1011).
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_immi_il;
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

  function automatic instr_word_t movi_il_enc(input reg_file_t rf, input reg_idx_t i);
    movi_il_enc = 16'h09E0 | (instr_word_t'(rf) << 4) | (instr_word_t'(i));
  endfunction
  function automatic instr_word_t imm_il_enc(input logic [10:0] top11,
                                             input reg_file_t   rf,
                                             input reg_idx_t    rd);
    imm_il_enc = (instr_word_t'(top11) << 5)
               | (instr_word_t'(rf) << 4)
               | (instr_word_t'(rd));
  endfunction

  localparam logic [10:0] ADDI_IL_TOP11 = 11'b0000_1011_001;
  localparam logic [10:0] CMPI_IL_TOP11 = 11'b0000_1011_011;
  localparam logic [10:0] ANDI_IL_TOP11 = 11'b0000_1011_100;
  localparam logic [10:0] ORI_IL_TOP11  = 11'b0000_1011_101;
  localparam logic [10:0] XORI_IL_TOP11 = 11'b0000_1011_110;
  localparam logic [10:0] SUBI_IL_TOP11 = 11'b0000_1101_000;

  function automatic int unsigned place_movi_il(input int unsigned p,
                                                input reg_file_t   rf,
                                                input reg_idx_t    i,
                                                input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]     = movi_il_enc(rf, i);
    u_mem.mem[p + 1] = imm[15:0];
    u_mem.mem[p + 2] = imm[31:16];
    place_movi_il = p + 3;
  endfunction
  function automatic int unsigned place_imm_il(input int unsigned p,
                                               input logic [10:0] top11,
                                               input reg_file_t   rf,
                                               input reg_idx_t    rd,
                                               input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]     = imm_il_enc(top11, rf, rd);
    u_mem.mem[p + 1] = imm[15:0];
    u_mem.mem[p + 2] = imm[31:16];
    place_imm_il = p + 3;
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
    failures = 0;

    // Encoding sanity:
    //   ADDI IL _, A0 = 11'b0000_1011_001 << 5 = 0000 1011 0010 0000 = 0x0B20
    //   SUBI IL _, A0 = 11'b0000_1101_000 << 5 = 0000 1101 0000 0000 = 0x0D00
    if (imm_il_enc(ADDI_IL_TOP11, REG_FILE_A, 4'd0) !== 16'h0B20) begin
      $display("TEST_RESULT: FAIL: ADDI IL _,A0=%04h, expected 0B20",
               imm_il_enc(ADDI_IL_TOP11, REG_FILE_A, 4'd0));
      failures++;
    end
    if (imm_il_enc(SUBI_IL_TOP11, REG_FILE_A, 4'd0) !== 16'h0D00) begin
      $display("TEST_RESULT: FAIL: SUBI IL _,A0=%04h, expected 0D00",
               imm_il_enc(SUBI_IL_TOP11, REG_FILE_A, 4'd0));
      failures++;
    end

    // Program:
    //   MOVI 0x00010000, A1; ADDI IL 0x00020000, A1   → A1 = 0x00030000
    //   MOVI 0x01000000, A2; SUBI IL 0x00010000, A2   → A2 = 0x00FF0000
    //   MOVI 0xCAFE_BABE, A3; CMPI IL 0xCAFE_BABE, A3 → A3 unchanged; Z=1
    //   MOVI 0xF0F0F0F0, A4; ANDI IL 0x0FF0FF0F, A4   → A4 = 0x00F0F000
    //   MOVI 0x0F0F0F0F, A5; ORI  IL 0xF0F0F0F0, A5   → A5 = 0xFFFFFFFF
    //   MOVI 0xAAAA_AAAA, B1; XORI IL 0xFFFF_FFFF, B1 → B1 = 0x55555555
    p = 0;
    p = place_movi_il(p, REG_FILE_A, 4'd1, 32'h0001_0000);
    p = place_imm_il (p, ADDI_IL_TOP11, REG_FILE_A, 4'd1, 32'h0002_0000);

    p = place_movi_il(p, REG_FILE_A, 4'd2, 32'h0100_0000);
    p = place_imm_il (p, SUBI_IL_TOP11, REG_FILE_A, 4'd2, 32'h0001_0000);

    p = place_movi_il(p, REG_FILE_A, 4'd3, 32'hCAFE_BABE);
    p = place_imm_il (p, CMPI_IL_TOP11, REG_FILE_A, 4'd3, 32'hCAFE_BABE);

    p = place_movi_il(p, REG_FILE_A, 4'd4, 32'hF0F0_F0F0);
    p = place_imm_il (p, ANDI_IL_TOP11, REG_FILE_A, 4'd4, 32'h0FF0_FF0F);

    p = place_movi_il(p, REG_FILE_A, 4'd5, 32'h0F0F_0F0F);
    p = place_imm_il (p, ORI_IL_TOP11, REG_FILE_A, 4'd5, 32'hF0F0_F0F0);

    p = place_movi_il(p, REG_FILE_B, 4'd1, 32'hAAAA_AAAA);
    p = place_imm_il (p, XORI_IL_TOP11, REG_FILE_B, 4'd1, 32'hFFFF_FFFF);

    repeat (3) @(posedge clk);
    rst = 1'b0;

    repeat (500) @(posedge clk);
    #1;

    check_reg("ADDI IL", u_core.u_regfile.a_regs[1], 32'h0003_0000);
    check_reg("SUBI IL", u_core.u_regfile.a_regs[2], 32'h00FF_0000);
    check_reg("CMPI IL: A3 unchanged", u_core.u_regfile.a_regs[3], 32'hCAFE_BABE);
    check_reg("ANDI IL", u_core.u_regfile.a_regs[4], 32'h00F0_F000);
    check_reg("ORI  IL", u_core.u_regfile.a_regs[5], 32'hFFFF_FFFF);
    check_reg("XORI IL (B)", u_core.u_regfile.b_regs[1], 32'h5555_5555);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (6 IL-immediate instructions verified)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #1_000_000;
    $display("TEST_RESULT: FAIL: tb_immi_il hard timeout");
    $fatal(1);
  end

endmodule : tb_immi_il
