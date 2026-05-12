// -----------------------------------------------------------------------------
// tb_move_rr.sv
//
// Tests MOVE Rs, Rd (register-to-register move, same file).
//
// Encoding (SPVU001A A-14): `1001 00FS SSSR DDDD`. Top6 = `6'b100100`.
// The F bit at position [9] selects field-size mode (FE0/FE1 in ST);
// Phase 4 ignores it per A0020.
//
// Operation: Rs → Rd. Source unchanged. Flag effects per A0009:
// N from result[31], Z from (result == 0), C and V cleared.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_move_rr;
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

  function automatic instr_word_t movi_il_enc(input reg_file_t rf, input reg_idx_t i);
    movi_il_enc = 16'h09E0 | (instr_word_t'(rf) << 4) | (instr_word_t'(i));
  endfunction
  function automatic instr_word_t move_rr_enc(input reg_file_t rf,
                                              input reg_idx_t rs,
                                              input reg_idx_t rd);
    // Top6 = 100100. F=0, S=4 bits Rs idx, R=file, DDDD=Rd idx.
    move_rr_enc = 16'h9000
                | (instr_word_t'(rs) << 5)
                | (instr_word_t'(rf) << 4)
                | (instr_word_t'(rd));
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

  initial begin : main
    int unsigned p;
    failures = 0;

    // Encoding sanity:
    //   MOVE A1, A2 = 1001_00_0_0001_0_0010 = 1001 0000 0010 0010 = 0x9022
    //   MOVE B5, B7 = 1001_00_0_0101_1_0111 = 1001 0000 1011 0111 = 0x90B7
    if (move_rr_enc(REG_FILE_A, 4'd1, 4'd2) !== 16'h9022) begin
      $display("TEST_RESULT: FAIL: MOVE A1,A2 = %04h, expected 9022",
               move_rr_enc(REG_FILE_A, 4'd1, 4'd2));
      failures++;
    end
    if (move_rr_enc(REG_FILE_B, 4'd5, 4'd7) !== 16'h90B7) begin
      $display("TEST_RESULT: FAIL: MOVE B5,B7 = %04h, expected 90B7",
               move_rr_enc(REG_FILE_B, 4'd5, 4'd7));
      failures++;
    end

    // Program:
    //   MOVI 0xCAFE_BABE, A1 ; MOVE A1, A2   → A2 = 0xCAFEBABE, A1 unchanged
    //   MOVI 0, A3           ; MOVE A3, A4    → A4 = 0 (Z=1)
    //   MOVI 0x8000_0000, A5 ; MOVE A5, A6   → A6 = MIN_INT (N=1)
    //   MOVI 0xDEAD_BEEF, B1 ; MOVE B1, B2   → B2 = DEADBEEF (B-file)
    p = 0;
    p = place_movi_il(p, REG_FILE_A, 4'd1, 32'hCAFE_BABE);
    u_mem.mem[p] = move_rr_enc(REG_FILE_A, 4'd1, 4'd2); p = p + 1;

    p = place_movi_il(p, REG_FILE_A, 4'd3, 32'd0);
    u_mem.mem[p] = move_rr_enc(REG_FILE_A, 4'd3, 4'd4); p = p + 1;

    p = place_movi_il(p, REG_FILE_A, 4'd5, 32'h8000_0000);
    u_mem.mem[p] = move_rr_enc(REG_FILE_A, 4'd5, 4'd6); p = p + 1;

    p = place_movi_il(p, REG_FILE_B, 4'd1, 32'hDEAD_BEEF);
    u_mem.mem[p] = move_rr_enc(REG_FILE_B, 4'd1, 4'd2); p = p + 1;

    repeat (3) @(posedge clk);
    rst = 1'b0;

    repeat (300) @(posedge clk);
    #1;

    check_reg("A1 unchanged",      u_core.u_regfile.a_regs[1], 32'hCAFE_BABE);
    check_reg("A2 = A1",           u_core.u_regfile.a_regs[2], 32'hCAFE_BABE);
    check_reg("A4 = A3 (zero)",    u_core.u_regfile.a_regs[4], 32'd0);
    check_reg("A6 = A5 (MIN_INT)", u_core.u_regfile.a_regs[6], 32'h8000_0000);
    check_reg("B2 = B1 (B-file)",  u_core.u_regfile.b_regs[2], 32'hDEAD_BEEF);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (MOVE Rs,Rd verified across 4 cases incl. zero, MIN_INT, A & B files)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #500_000;
    $display("TEST_RESULT: FAIL: tb_move_rr hard timeout");
    $fatal(1);
  end

endmodule : tb_move_rr
