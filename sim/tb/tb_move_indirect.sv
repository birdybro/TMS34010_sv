// -----------------------------------------------------------------------------
// tb_move_indirect.sv
//
// MOVE Rs,*Rd (store) and MOVE *Rs,Rd (load) — register <-> indirect
// memory, field-size 32, word-aligned. Per SPVU001A pages 12-127 (store)
// and 12-135 (load).
//
//   MOVE Rs,*Rd : 1000 00FS SSSR DDDD  (top6=100000). mem[*Rd] <- Rs.
//                 Rd is a bit-address pointer (unchanged). All flags
//                 Unaffected.
//   MOVE *Rs,Rd : 1000 01FS SSSR DDDD  (top6=100001). Rd <- mem[*Rs].
//                 Rs is a bit-address pointer. Implicit compare-to-0:
//                 N=data[31], Z=(data==0), V=0, C Unaffected.
//
// Task 0059 scope: field size 32 (FS selected = 32, the reset default),
// word-aligned pointers. At FS=32 the field is the full 32-bit word, so
// sign/zero extension (FE) is a no-op and the access maps to the
// existing 32-bit aligned memory path. Smaller field sizes, unaligned
// pointers, the inc/dec/offset/absolute addressing modes, and FE
// handling are deferred (assumptions.md A0020).
//
// Test plan: three store->load round-trips covering a negative value
// (N=1), zero (Z=1), and a positive value (N=0,Z=0). Each verifies:
//   - the stored value lands in memory (32-bit, low word first),
//   - the load recovers it into Rd,
//   - the pointer register is unchanged by the store,
//   - the load's N/Z flags (captured with a GETST snapshot, since later
//     instructions would clobber ST).
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_move_indirect;
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
    .illegal_opcode_o(illegal_w), .run_emu_n_i(1'b1), .emua_n_o()
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
    movi_il_enc = 16'h09E0 | instr_word_t'(i);   // A-file MOVI IL
  endfunction
  // MOVE Rs,*Rd (store): 0x8000 | (Rs<<5) | (R<<4) | Rd,  F=0.
  function automatic instr_word_t move_store_enc(input reg_idx_t rs, input reg_idx_t rd);
    move_store_enc = 16'h8000 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
  endfunction
  // MOVE *Rs,Rd (load): 0x8400 | (Rs<<5) | (R<<4) | Rd,  F=0.
  function automatic instr_word_t move_load_enc(input reg_idx_t rs, input reg_idx_t rd);
    move_load_enc = 16'h8400 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
  endfunction
  // GETST Rd (A-file): 0x0180 | Rd.
  function automatic instr_word_t getst_enc(input reg_idx_t rd);
    getst_enc = 16'h0180 | instr_word_t'(rd);
  endfunction

  function automatic int unsigned place_movi_il(input int unsigned p,
                                                input reg_idx_t i,
                                                input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]     = movi_il_enc(i);
    u_mem.mem[p + 1] = imm[15:0];
    u_mem.mem[p + 2] = imm[31:16];
    place_movi_il = p + 3;
  endfunction
  function automatic int unsigned place_word(input int unsigned p, input instr_word_t w);
    u_mem.mem[p] = w;
    place_word   = p + 1;
  endfunction

  int unsigned failures;
  task automatic check_reg(input string label,
                           input logic [DATA_WIDTH-1:0] actual,
                           input logic [DATA_WIDTH-1:0] expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%08h actual=%08h", label, expected, actual);
      failures++;
    end
  endtask
  task automatic check_mem32(input string label,
                             input int unsigned word_idx_lo,
                             input logic [DATA_WIDTH-1:0] expected);
    logic [DATA_WIDTH-1:0] actual;
    actual = {u_mem.mem[word_idx_lo + 1], u_mem.mem[word_idx_lo]};
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%08h actual=%08h", label, expected, actual);
      failures++;
    end
  endtask
  task automatic check_bit(input string label, input logic actual, input logic expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%0b actual=%0b", label, expected, actual);
      failures++;
    end
  endtask

  // Pointers (word-aligned bit addresses). word index = addr/16.
  localparam logic [DATA_WIDTH-1:0] PTR1 = 32'h0000_0800;  // word 128
  localparam logic [DATA_WIDTH-1:0] PTR2 = 32'h0000_0900;  // word 144
  localparam logic [DATA_WIDTH-1:0] PTR3 = 32'h0000_0A00;  // word 160

  initial begin : main
    int unsigned p;
    int unsigned i;
    failures = 0;

    for (i = 0; i < 512; i++) u_mem.mem[i] = 16'h0300;   // NOP-fill

    p = 0;
    // MOVE now honors the field size: set FS0 = 0 (encodes a 32-bit field)
    // so these full-word round-trips move 32 bits. Reset ST has FS0 = 16.
    p = place_word(p, 16'h0540);   // SETF FS=0, FE=0, F=0
    // ---- Case 1: negative value 0xCAFEBABE via PTR1 (A2) ----------------
    //   A1=data, A2=PTR1 ; MOVE A1,*A2 ; MOVE *A2,A3 ; GETST A8
    p = place_movi_il(p, 4'd1, 32'hCAFE_BABE);
    p = place_movi_il(p, 4'd2, PTR1);
    p = place_word(p, move_store_enc(4'd1, 4'd2));   // mem[A2] <- A1
    p = place_word(p, move_load_enc(4'd2, 4'd3));    // A3 <- mem[A2]
    p = place_word(p, getst_enc(4'd8));              // A8 <- ST (snapshot)

    // ---- Case 2: zero value via PTR2 (A6) -------------------------------
    p = place_movi_il(p, 4'd4, 32'h0000_0000);
    p = place_movi_il(p, 4'd6, PTR2);
    p = place_word(p, move_store_enc(4'd4, 4'd6));   // mem[A6] <- A4 (=0)
    p = place_word(p, move_load_enc(4'd6, 4'd5));    // A5 <- mem[A6]
    p = place_word(p, getst_enc(4'd9));              // A9 <- ST

    // ---- Case 3: positive value 0x12345678 via PTR3 (A7) ----------------
    p = place_movi_il(p, 4'd10, 32'h1234_5678);
    p = place_movi_il(p, 4'd7,  PTR3);
    p = place_word(p, move_store_enc(4'd10, 4'd7));  // mem[A7] <- A10
    p = place_word(p, move_load_enc(4'd7,  4'd11));  // A11 <- mem[A7]
    p = place_word(p, getst_enc(4'd12));             // A12 <- ST

    p = place_word(p, 16'hC0FF);                     // halt

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (2000) @(posedge clk);
    #1;

    // -------- Data integrity --------
    check_mem32("store: mem[PTR1] = 0xCAFEBABE", PTR1 >> 4, 32'hCAFE_BABE);
    check_mem32("store: mem[PTR2] = 0x00000000", PTR2 >> 4, 32'h0000_0000);
    check_mem32("store: mem[PTR3] = 0x12345678", PTR3 >> 4, 32'h1234_5678);
    check_reg("load: A3 = 0xCAFEBABE",  u_core.u_regfile.a_regs[3],  32'hCAFE_BABE);
    check_reg("load: A5 = 0x00000000",  u_core.u_regfile.a_regs[5],  32'h0000_0000);
    check_reg("load: A11 = 0x12345678", u_core.u_regfile.a_regs[11], 32'h1234_5678);

    // -------- Pointer registers unchanged by the store --------
    check_reg("ptr A2 unchanged", u_core.u_regfile.a_regs[2], PTR1);
    check_reg("ptr A6 unchanged", u_core.u_regfile.a_regs[6], PTR2);
    check_reg("ptr A7 unchanged", u_core.u_regfile.a_regs[7], PTR3);

    // -------- Load flags (snapshots A8/A9/A12) --------
    // Case 1: 0xCAFEBABE -> N=1, Z=0.
    check_bit("load flags C1 N=1", u_core.u_regfile.a_regs[8][ST_N_BIT], 1'b1);
    check_bit("load flags C1 Z=0", u_core.u_regfile.a_regs[8][ST_Z_BIT], 1'b0);
    // Case 2: 0x00000000 -> N=0, Z=1.
    check_bit("load flags C2 N=0", u_core.u_regfile.a_regs[9][ST_N_BIT], 1'b0);
    check_bit("load flags C2 Z=1", u_core.u_regfile.a_regs[9][ST_Z_BIT], 1'b1);
    // Case 3: 0x12345678 -> N=0, Z=0.
    check_bit("load flags C3 N=0", u_core.u_regfile.a_regs[12][ST_N_BIT], 1'b0);
    check_bit("load flags C3 Z=0", u_core.u_regfile.a_regs[12][ST_Z_BIT], 1'b0);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (MOVE Rs,*Rd / *Rs,Rd: store+load round-trips, FS=32 word-aligned, load N/Z flags)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #5_000_000;
    $display("TEST_RESULT: FAIL: tb_move_indirect hard timeout");
    $fatal(1);
  end

endmodule : tb_move_indirect
