// -----------------------------------------------------------------------------
// tb_shift_k.sv
//
// Tests the five K-form shift instructions:
//   SLA K, Rd     Rd << K   (arithmetic; may set V)
//   SLL K, Rd     Rd << K   (logical)
//   SRA K, Rd     Rd >>> K  (arithmetic / sign-extend)
//   SRL K, Rd     Rd >> K   (logical, MSB ← 0)
//   RL  K, Rd     Rd ROL K  (rotate left)
//
// Encodings (SPVU001A A-14):
//   SLA K, Rd  = 0010 00KK KKKR DDDD
//   SLL K, Rd  = 0010 01KK KKKR DDDD
//   SRA K, Rd  = 0010 10KK KKKR DDDD
//   SRL K, Rd  = 0010 11KK KKKR DDDD
//   RL  K, Rd  = 0011 00KK KKKR DDDD
//
// All five exercise the shifter writeback path (use_shifter = 1).
// K=0 is NOT tested — the TMS34010 K=0→32 hypothesis is deferred
// to A0019 along with the equivalent for ADDK/SUBK.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_shift_k;
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
  // Build a K-form shift instruction. top6 is the 6-bit prefix.
  function automatic instr_word_t shift_k_enc(input logic [5:0] top6,
                                              input logic [4:0] k,
                                              input reg_file_t  rf,
                                              input reg_idx_t   rd);
    shift_k_enc = (instr_word_t'(top6) << 10)
                | (instr_word_t'(k)    << 5)
                | (instr_word_t'(rf)   << 4)
                | (instr_word_t'(rd));
  endfunction

  localparam logic [5:0] SLA_K_TOP6 = 6'b001000;
  localparam logic [5:0] SLL_K_TOP6 = 6'b001001;
  localparam logic [5:0] SRA_K_TOP6 = 6'b001010;
  localparam logic [5:0] SRL_K_TOP6 = 6'b001011;
  localparam logic [5:0] RL_K_TOP6  = 6'b001100;

  function automatic int unsigned place_movi_il(input int unsigned p,
                                                input reg_file_t   rf,
                                                input reg_idx_t    i,
                                                input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]     = movi_il_enc(rf, i);
    u_mem.mem[p + 1] = imm[15:0];
    u_mem.mem[p + 2] = imm[31:16];
    place_movi_il = p + 3;
  endfunction
  function automatic int unsigned place_shift_k(input int unsigned p,
                                                input logic [5:0]  top6,
                                                input logic [4:0]  k,
                                                input reg_file_t   rf,
                                                input reg_idx_t    rd);
    u_mem.mem[p] = shift_k_enc(top6, k, rf, rd);
    place_shift_k = p + 1;
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
    //   SLA 1, A0 = 0010_00_00001_0_0000 = 0010 0000 0010 0000 = 0x2020
    //   SLL 4, A0 = 0010_01_00100_0_0000 = 0010 0100 1000 0000 = 0x2480
    //   SRA 1, A0 = 0010_10_00001_0_0000 = 0010 1000 0010 0000 = 0x2820
    //   SRL 4, A0 = 0010_11_00100_0_0000 = 0010 1100 1000 0000 = 0x2C80
    //   RL  16,A0 = 0011_00_10000_0_0000 = 0011 0010 0000 0000 = 0x3200
    if (shift_k_enc(SLA_K_TOP6, 5'd1, REG_FILE_A, 4'd0) !== 16'h2020) begin
      $display("TEST_RESULT: FAIL: SLA 1,A0 = %04h, expected 2020",
               shift_k_enc(SLA_K_TOP6, 5'd1, REG_FILE_A, 4'd0));
      failures++;
    end
    if (shift_k_enc(RL_K_TOP6, 5'd16, REG_FILE_A, 4'd0) !== 16'h3200) begin
      $display("TEST_RESULT: FAIL: RL 16,A0 = %04h, expected 3200",
               shift_k_enc(RL_K_TOP6, 5'd16, REG_FILE_A, 4'd0));
      failures++;
    end

    // Program:
    //   MOVI 0x00000001, A1 ; SLL 4, A1   → A1 = 0x10
    //   MOVI 0x80000000, A2 ; SRA 4, A2   → A2 = 0xF8000000 (sign-extend)
    //   MOVI 0x80000000, A3 ; SRL 4, A3   → A3 = 0x08000000 (logical)
    //   MOVI 0x0000F0F0, A4 ; SLA 8, A4   → A4 = 0x00F0F000
    //   MOVI 0x1234_5678, A5; RL  16, A5  → A5 = 0x5678_1234
    //   MOVI 0xCAFE_BABE, B1; SRL 4,  B1  → B1 = 0x0CAF_EBAB (B-file)
    p = 0;
    p = place_movi_il(p, REG_FILE_A, 4'd1, 32'h0000_0001);
    p = place_shift_k(p, SLL_K_TOP6, 5'd4, REG_FILE_A, 4'd1);

    p = place_movi_il(p, REG_FILE_A, 4'd2, 32'h8000_0000);
    p = place_shift_k(p, SRA_K_TOP6, 5'd4, REG_FILE_A, 4'd2);

    p = place_movi_il(p, REG_FILE_A, 4'd3, 32'h8000_0000);
    p = place_shift_k(p, SRL_K_TOP6, 5'd4, REG_FILE_A, 4'd3);

    p = place_movi_il(p, REG_FILE_A, 4'd4, 32'h0000_F0F0);
    p = place_shift_k(p, SLA_K_TOP6, 5'd8, REG_FILE_A, 4'd4);

    p = place_movi_il(p, REG_FILE_A, 4'd5, 32'h1234_5678);
    p = place_shift_k(p, RL_K_TOP6, 5'd16, REG_FILE_A, 4'd5);

    p = place_movi_il(p, REG_FILE_B, 4'd1, 32'hCAFE_BABE);
    p = place_shift_k(p, SRL_K_TOP6, 5'd4, REG_FILE_B, 4'd1);

    repeat (3) @(posedge clk);
    rst = 1'b0;

    repeat (300) @(posedge clk);
    #1;

    check_reg("SLL 4 of 0x1 → 0x10",        u_core.u_regfile.a_regs[1], 32'h0000_0010);
    check_reg("SRA 4 of 0x80000000 (sign-ext)", u_core.u_regfile.a_regs[2], 32'hF800_0000);
    check_reg("SRL 4 of 0x80000000 (logical)",  u_core.u_regfile.a_regs[3], 32'h0800_0000);
    check_reg("SLA 8 of 0x0000F0F0 → 0x00F0F000", u_core.u_regfile.a_regs[4], 32'h00F0_F000);
    check_reg("RL 16 of 0x12345678 (halfword swap)", u_core.u_regfile.a_regs[5], 32'h5678_1234);
    check_reg("SRL 4 of 0xCAFE_BABE (B-file)",       u_core.u_regfile.b_regs[1], 32'h0CAF_EBAB);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (5 K-form shifts verified across 6 cases; shifter wired)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #500_000;
    $display("TEST_RESULT: FAIL: tb_shift_k hard timeout");
    $fatal(1);
  end

endmodule : tb_shift_k
