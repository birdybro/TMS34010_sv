// -----------------------------------------------------------------------------
// tb_logical_rr.sv
//
// End-to-end test for the four reg-reg logical instructions:
//   AND  Rs, Rd     Rd = Rd & Rs   (0101 000S SSSR DDDD)
//   ANDN Rs, Rd     Rd = Rd & ~Rs  (0101 001S SSSR DDDD)
//   OR   Rs, Rd     Rd = Rd | Rs   (0101 010S SSSR DDDD)
//   XOR  Rs, Rd     Rd = Rd ^ Rs   (0101 011S SSSR DDDD)
//
// All four are reg-reg ops with the same encoding shape. Both registers
// must be in the same file (TMS34010 architectural constraint, A0014).
//
// Flag policy (A0009): N = result[31], Z = (result == 0), C = 0, V = 0.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_logical_rr;
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

  // Encoding helpers (each prefix from SPVU001A A-14).
  function automatic instr_word_t movi_il_enc(input reg_file_t rf, input reg_idx_t i);
    movi_il_enc = 16'h09E0 | (instr_word_t'(rf) << 4) | (instr_word_t'(i));
  endfunction

  function automatic instr_word_t logical_rr_enc(input logic [6:0] top7,
                                                 input reg_file_t rf,
                                                 input reg_idx_t  rs,
                                                 input reg_idx_t  rd);
    logical_rr_enc = (instr_word_t'(top7) << 9)
                   | (instr_word_t'(rs)   << 5)
                   | (instr_word_t'(rf)   << 4)
                   | (instr_word_t'(rd));
  endfunction

  localparam logic [6:0] AND_TOP7  = 7'b0101_000;
  localparam logic [6:0] ANDN_TOP7 = 7'b0101_001;
  localparam logic [6:0] OR_TOP7   = 7'b0101_010;
  localparam logic [6:0] XOR_TOP7  = 7'b0101_011;

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

  function automatic int unsigned place_movi_il(input int unsigned p,
                                                input reg_file_t   rf,
                                                input reg_idx_t    i,
                                                input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]     = movi_il_enc(rf, i);
    u_mem.mem[p + 1] = imm[15:0];
    u_mem.mem[p + 2] = imm[31:16];
    place_movi_il = p + 3;
  endfunction
  function automatic int unsigned place_logical(input int unsigned p,
                                                input logic [6:0]  top7,
                                                input reg_file_t   rf,
                                                input reg_idx_t    rs,
                                                input reg_idx_t    rd);
    u_mem.mem[p] = logical_rr_enc(top7, rf, rs, rd);
    place_logical = p + 1;
  endfunction

  initial begin : main
    int unsigned p;
    failures = 0;

    // Encoding sanity (cross-check against XOR A0,A0 = 0x5600 verified
    // in the SPVU004 listing).
    if (logical_rr_enc(XOR_TOP7, REG_FILE_A, 4'd0, 4'd0) !== 16'h5600) begin
      $display("TEST_RESULT: FAIL: XOR A0,A0 enc = %04h, expected 5600",
               logical_rr_enc(XOR_TOP7, REG_FILE_A, 4'd0, 4'd0));
      failures++;
    end

    // Program:
    //   A1 = 0xF0F0_F0F0; A2 = 0x0FF0_FF0F
    //   AND  A1, A2  →  A2 = 0x00F0_F000
    //   A3 = 0xFFFF_FFFF; A4 = 0xF0F0_F0F0
    //   ANDN A4, A3  →  A3 = A3 & ~A4 = 0x0F0F_0F0F
    //   A5 = 0x0F0F_0F0F; A6 = 0xF0F0_F0F0
    //   OR   A5, A6  →  A6 = 0xFFFF_FFFF
    //   B1 = 0xAAAA_AAAA; B2 = 0x5555_5555
    //   XOR  B1, B2  →  B2 = 0xFFFF_FFFF
    p = 0;
    p = place_movi_il(p, REG_FILE_A, 4'd1, 32'hF0F0_F0F0);
    p = place_movi_il(p, REG_FILE_A, 4'd2, 32'h0FF0_FF0F);
    p = place_logical(p, AND_TOP7, REG_FILE_A, 4'd1, 4'd2);

    p = place_movi_il(p, REG_FILE_A, 4'd3, 32'hFFFF_FFFF);
    p = place_movi_il(p, REG_FILE_A, 4'd4, 32'hF0F0_F0F0);
    p = place_logical(p, ANDN_TOP7, REG_FILE_A, 4'd4, 4'd3);

    p = place_movi_il(p, REG_FILE_A, 4'd5, 32'h0F0F_0F0F);
    p = place_movi_il(p, REG_FILE_A, 4'd6, 32'hF0F0_F0F0);
    p = place_logical(p, OR_TOP7, REG_FILE_A, 4'd5, 4'd6);

    p = place_movi_il(p, REG_FILE_B, 4'd1, 32'hAAAA_AAAA);
    p = place_movi_il(p, REG_FILE_B, 4'd2, 32'h5555_5555);
    p = place_logical(p, XOR_TOP7, REG_FILE_B, 4'd1, 4'd2);

    repeat (3) @(posedge clk);
    rst = 1'b0;

    // 12 instructions, avg ~9 cycles. Use 250 for headroom.
    repeat (250) @(posedge clk);
    #1;

    check_reg("AND A2 = F0F0F0F0 & 0FF0FF0F = 00F0F000",
              u_core.u_regfile.a_regs[2], 32'h00F0_F000);
    check_reg("ANDN A3 = FFFFFFFF & ~F0F0F0F0 = 0F0F0F0F",
              u_core.u_regfile.a_regs[3], 32'h0F0F_0F0F);
    check_reg("OR  A6 = 0F0F0F0F | F0F0F0F0 = FFFFFFFF",
              u_core.u_regfile.a_regs[6], 32'hFFFF_FFFF);
    check_reg("XOR B2 = AAAAAAAA ^ 55555555 = FFFFFFFF",
              u_core.u_regfile.b_regs[2], 32'hFFFF_FFFF);

    // Final ST reflects the last instruction (XOR B1, B2 = 0xFFFF_FFFF).
    // N=1 (MSB set), Z=0, C=0, V=0.
    check_bit("ST.N after XOR -> FFFFFFFF", u_core.u_status_reg.n_o, 1'b1);
    check_bit("ST.Z after XOR -> FFFFFFFF", u_core.u_status_reg.z_o, 1'b0);
    check_bit("ST.C (logical clears C)",     u_core.u_status_reg.c_o, 1'b0);
    check_bit("ST.V (logical clears V)",     u_core.u_status_reg.v_o, 1'b0);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (4 logical RR cases verified; encoding helper matches XOR A0,A0=0x5600)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #500_000;
    $display("TEST_RESULT: FAIL: tb_logical_rr hard timeout");
    $fatal(1);
  end

endmodule : tb_logical_rr
