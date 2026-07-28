// -----------------------------------------------------------------------------
// tb_move_m2m.sv
//
// MOVE *Rs,*Rd — indirect-to-indirect field move (Task 0061). Per SPVU001A
// page 12-137. Encoding 1000 10FS SSSR DDDD (base 0x8800).
//
// Reads the 32-bit field at mem[*Rs] and writes it to mem[*Rd]. Both Rs
// and Rd are bit-address pointers (unchanged for this plain form). Two
// memory transactions: read at *Rs (step 0), write at *Rd (step 1). All
// status bits Unaffected. Scope: field-size-32, word-aligned (the
// inc/dec indirect-to-indirect forms are deferred).
//
// Test: two independent memory-to-memory copies, verifying the
// destination receives the value, the source is unchanged, and the
// pointer registers are unchanged.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_move_m2m;
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
    .state_o(state_w), .pc_o(pc_w), .instr_word_o(instr_w), .illegal_opcode_o(illegal_w), .run_emu_n_i(1'b1), .emua_n_o()
  );

  sim_memory_model #(.DEPTH_WORDS(512)) u_mem (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack)
  );

  function automatic instr_word_t movi_il_enc(input reg_idx_t i);
    movi_il_enc = 16'h09E0 | instr_word_t'(i);
  endfunction
  // MOVE *Rs,*Rd: 0x8800 | (Rs<<5) | (R<<4) | Rd,  F=0.
  function automatic instr_word_t move_m2m_enc(input reg_idx_t rs, input reg_idx_t rd);
    move_m2m_enc = 16'h8800 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
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
    u_mem.mem[p] = w;  place_word = p + 1;
  endfunction
  task automatic seed_mem32(input int unsigned w, input logic [DATA_WIDTH-1:0] v);
    u_mem.mem[w]     = v[15:0];
    u_mem.mem[w + 1] = v[31:16];
  endtask

  int unsigned failures;
  task automatic check_mem32(input string label, input int unsigned w,
                             input logic [DATA_WIDTH-1:0] expected);
    logic [DATA_WIDTH-1:0] actual;
    actual = {u_mem.mem[w + 1], u_mem.mem[w]};
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%08h actual=%08h", label, expected, actual);
      failures++;
    end
  endtask
  task automatic check_reg(input string label,
                           input logic [DATA_WIDTH-1:0] actual, expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%08h actual=%08h", label, expected, actual);
      failures++;
    end
  endtask

  // Pointers (word-aligned bit addresses).
  localparam logic [DATA_WIDTH-1:0] SRC1 = 32'h0000_0800;  // word 128
  localparam logic [DATA_WIDTH-1:0] DST1 = 32'h0000_0900;  // word 144
  localparam logic [DATA_WIDTH-1:0] SRC2 = 32'h0000_0A00;  // word 160
  localparam logic [DATA_WIDTH-1:0] DST2 = 32'h0000_0B00;  // word 176

  initial begin : main
    int unsigned p, i;
    failures = 0;
    for (i = 0; i < 512; i++) u_mem.mem[i] = 16'h0300;

    // Pre-seed the two source locations.
    seed_mem32(SRC1 >> 4, 32'hDEAD_BEEF);
    seed_mem32(SRC2 >> 4, 32'h0123_4567);

    p = 0;
    // MOVE M2M now honors the field size: set FS0 = 0 (encodes a 32-bit
    // field) so these full-word copies move 32 bits. Reset ST has FS0=16.
    p = place_word(p, 16'h0540);   // SETF FS=0, FE=0, F=0
    // Copy mem[SRC1] -> mem[DST1] via MOVE *A1,*A2.
    p = place_movi_il(p, 4'd1, SRC1);
    p = place_movi_il(p, 4'd2, DST1);
    p = place_word(p, move_m2m_enc(4'd1, 4'd2));
    // Copy mem[SRC2] -> mem[DST2] via MOVE *A3,*A4.
    p = place_movi_il(p, 4'd3, SRC2);
    p = place_movi_il(p, 4'd4, DST2);
    p = place_word(p, move_m2m_enc(4'd3, 4'd4));
    p = place_word(p, 16'hC0FF);                   // halt

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (2000) @(posedge clk);
    #1;

    // Destinations received the data.
    check_mem32("copy1: mem[DST1] = 0xDEADBEEF", DST1 >> 4, 32'hDEAD_BEEF);
    check_mem32("copy2: mem[DST2] = 0x01234567", DST2 >> 4, 32'h0123_4567);
    // Sources unchanged.
    check_mem32("copy1: mem[SRC1] unchanged", SRC1 >> 4, 32'hDEAD_BEEF);
    check_mem32("copy2: mem[SRC2] unchanged", SRC2 >> 4, 32'h0123_4567);
    // Pointer registers unchanged.
    check_reg("A1 (src1) unchanged", u_core.u_regfile.a_regs[1], SRC1);
    check_reg("A2 (dst1) unchanged", u_core.u_regfile.a_regs[2], DST1);
    check_reg("A3 (src2) unchanged", u_core.u_regfile.a_regs[3], SRC2);
    check_reg("A4 (dst2) unchanged", u_core.u_regfile.a_regs[4], DST2);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (MOVE *Rs,*Rd: two memory-to-memory copies, FS=32 word-aligned)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #5_000_000;
    $display("TEST_RESULT: FAIL: tb_move_m2m hard timeout");
    $fatal(1);
  end

endmodule : tb_move_m2m
