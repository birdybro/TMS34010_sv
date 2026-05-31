// -----------------------------------------------------------------------------
// tb_move_m2m_incdec.sv
//
// MOVE *Rs+,*Rd+ / -*Rs,-*Rd — indirect-to-indirect with auto inc/dec
// (Task 0062), field-size 32, word-aligned. Per SPVU001A page 12-138.
//   MOVE *Rs+,*Rd+ (0x9800): mem[Rd] <- mem[Rs]; Rs += 32; Rd += 32.
//   MOVE -*Rs,-*Rd (0xA800): Rs -= 32; Rd -= 32; mem[Rd] <- mem[Rs].
// Both leave all status bits Unaffected.
//
// Two memory transactions (read then write). The source pointer (Rs) is
// updated at the step-0 read ack; the destination pointer (Rd) at
// WRITEBACK. Edge case (spec 12-138): for a postincrement with Rs==Rd,
// the data is written to the INCREMENTED location and the register ends
// up incremented once — Case C verifies this.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_move_m2m_incdec;
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
    .state_o(state_w), .pc_o(pc_w), .instr_word_o(instr_w), .illegal_opcode_o(illegal_w)
  );

  sim_memory_model #(.DEPTH_WORDS(512)) u_mem (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack)
  );

  function automatic instr_word_t movi_il_enc(input reg_idx_t i);
    movi_il_enc = 16'h09E0 | instr_word_t'(i);
  endfunction
  // base | (Rs<<5) | (R<<4)=0 | Rd, F=0.
  function automatic instr_word_t mv_enc(input instr_word_t base,
                                         input reg_idx_t rs, input reg_idx_t rd);
    mv_enc = base | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
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
    u_mem.mem[w] = v[15:0];  u_mem.mem[w + 1] = v[31:16];
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

  localparam instr_word_t M2M_POSTINC = 16'h9800;
  localparam instr_word_t M2M_PREDEC  = 16'hA800;

  initial begin : main
    int unsigned p, i;
    failures = 0;
    for (i = 0; i < 512; i++) u_mem.mem[i] = 16'h0300;

    // Seeds: Case A src 0x800, Case B src 0xC00, Case C src 0xE00.
    seed_mem32(32'h800 >> 4, 32'h1111_2222);
    seed_mem32(32'hC00 >> 4, 32'h3333_4444);
    seed_mem32(32'hE00 >> 4, 32'h5555_6666);

    p = 0;
    // Case A: postinc, Rs!=Rd. src A1=0x800, dst A2=0xA00.
    p = place_movi_il(p, 4'd1, 32'h0000_0800);
    p = place_movi_il(p, 4'd2, 32'h0000_0A00);
    p = place_word(p, mv_enc(M2M_POSTINC, 4'd1, 4'd2));   // MOVE *A1+,*A2+
    // Case B: predec, Rs!=Rd. src A3=0xC20 (reads 0xC00), dst A4=0xD20 (writes 0xD00).
    p = place_movi_il(p, 4'd3, 32'h0000_0C20);
    p = place_movi_il(p, 4'd4, 32'h0000_0D20);
    p = place_word(p, mv_enc(M2M_PREDEC, 4'd3, 4'd4));    // MOVE -*A3,-*A4
    // Case C: postinc, Rs==Rd. A0=0xE00; read 0xE00, write 0xE20, A0=0xE20.
    p = place_movi_il(p, 4'd0, 32'h0000_0E00);
    p = place_word(p, mv_enc(M2M_POSTINC, 4'd0, 4'd0));   // MOVE *A0+,*A0+
    p = place_word(p, 16'hC0FF);                          // halt

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (2000) @(posedge clk);
    #1;

    // ---- Case A: postincrement, Rs != Rd ----
    check_mem32("A: mem[0xA00] = data (dst write)", 32'hA00 >> 4, 32'h1111_2222);
    check_mem32("A: mem[0x800] unchanged (src)",    32'h800 >> 4, 32'h1111_2222);
    check_reg("A: A1 = 0x820 (src += 32)", u_core.u_regfile.a_regs[1], 32'h0000_0820);
    check_reg("A: A2 = 0xA20 (dst += 32)", u_core.u_regfile.a_regs[2], 32'h0000_0A20);

    // ---- Case B: predecrement, Rs != Rd ----
    check_mem32("B: mem[0xD00] = data (dst write)", 32'hD00 >> 4, 32'h3333_4444);
    check_mem32("B: mem[0xC00] unchanged (src)",    32'hC00 >> 4, 32'h3333_4444);
    check_reg("B: A3 = 0xC00 (src -= 32)", u_core.u_regfile.a_regs[3], 32'h0000_0C00);
    check_reg("B: A4 = 0xD00 (dst -= 32)", u_core.u_regfile.a_regs[4], 32'h0000_0D00);

    // ---- Case C: postincrement, Rs == Rd (data to incremented loc) ----
    check_mem32("C: mem[0xE20] = data (incremented dst)", 32'hE20 >> 4, 32'h5555_6666);
    check_mem32("C: mem[0xE00] unchanged (src read)",     32'hE00 >> 4, 32'h5555_6666);
    check_reg("C: A0 = 0xE20 (single increment, not 0xE40)",
              u_core.u_regfile.a_regs[0], 32'h0000_0E20);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (MOVE *Rs+,*Rd+ / -*Rs,-*Rd: post/pre + Rs==Rd incremented-loc)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #5_000_000;
    $display("TEST_RESULT: FAIL: tb_move_m2m_incdec hard timeout");
    $fatal(1);
  end

endmodule : tb_move_m2m_incdec
