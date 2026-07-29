// -----------------------------------------------------------------------------
// tb_addxy_subxy.sv
//
// ADDXY / SUBXY — add/subtract the X (low 16) and Y (high 16) halves of
// Rs and Rd independently, with no carry/borrow between halves. Per
// SPVU001A pages 12-41 (ADDXY) and 12-252 (SUBXY). Encodings
// 1110 000S SSSR DDDD (ADDXY, 0xE000) / 1110 001S SSSR DDDD (SUBXY,
// 0xE200). Rs and Rd same file.
//
// Status bits (graphics clipping):
//   ADDXY: N=(Xres==0), V=Xres[15], Z=(Yres==0), C=Yres[15].
//   SUBXY: N=(RsX==RdX), V=(RsX>RdX), Z=(RsY==RdY), C=(RsY>RdY).
//          X/Y are signed 16-bit coordinates per User's Guide page 4-11.
//
// Cases taken from TI's example tables; flags captured with GETST.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_addxy_subxy;
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

  sim_memory_model #(.DEPTH_WORDS(128)) u_mem (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack)
  );

  function automatic instr_word_t movi_il_enc(input reg_idx_t i);
    movi_il_enc = 16'h09E0 | instr_word_t'(i);
  endfunction
  function automatic instr_word_t addxy_enc(input reg_idx_t rs, input reg_idx_t rd);
    addxy_enc = 16'hE000 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
  endfunction
  function automatic instr_word_t subxy_enc(input reg_idx_t rs, input reg_idx_t rd);
    subxy_enc = 16'hE200 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
  endfunction
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
  // expected_nczv: 4 bits {N,C,Z,V} matching TI's column order.
  task automatic check_nczv(input string label, input logic [DATA_WIDTH-1:0] st,
                            input logic [3:0] nczv);
    logic [3:0] got;
    got = {st[ST_N_BIT], st[ST_C_BIT], st[ST_Z_BIT], st[ST_V_BIT]};
    if (got !== nczv) begin
      $display("TEST_RESULT: FAIL: %s: expected NCZV=%04b actual=%04b", label, nczv, got);
      failures++;
    end
  endtask

  initial begin : main
    int unsigned p, i;
    failures = 0;
    for (i = 0; i < 128; i++) u_mem.mem[i] = 16'h0300;

    p = 0;
    // ADDXY A1,A0: Rd=0x80008000, Rs=0 -> 0x80008000, NCZV=0101 (V,C set).
    p = place_movi_il(p, 4'd0, 32'h8000_8000);
    p = place_movi_il(p, 4'd1, 32'h0000_0000);
    p = place_word(p, addxy_enc(4'd1, 4'd0));
    p = place_word(p, getst_enc(4'd8));
    // ADDXY A3,A2: Rd=0x0000FFFF, Rs=0x00000001 -> 0, NCZV=1010 (N,Z set).
    p = place_movi_il(p, 4'd2, 32'h0000_FFFF);
    p = place_movi_il(p, 4'd3, 32'h0000_0001);
    p = place_word(p, addxy_enc(4'd3, 4'd2));
    p = place_word(p, getst_enc(4'd9));
    // SUBXY A5,A4: Rd=0x00090009, Rs=0x00090009 -> 0, NCZV=1010.
    p = place_movi_il(p, 4'd4, 32'h0009_0009);
    p = place_movi_il(p, 4'd5, 32'h0009_0009);
    p = place_word(p, subxy_enc(4'd5, 4'd4));
    p = place_word(p, getst_enc(4'd10));
    // SUBXY A7,A6: Rd=0x00090009, Rs=0x00100010 -> 0xFFF9FFF9, NCZV=0101.
    p = place_movi_il(p, 4'd6, 32'h0009_0009);
    p = place_movi_il(p, 4'd7, 32'h0010_0010);
    p = place_word(p, subxy_enc(4'd7, 4'd6));
    p = place_word(p, getst_enc(4'd11));
    // Signedness discriminator:
    //   X: Rs=-1, Rd=+1 -> source is NOT greater, V=0
    //   Y: Rs=+1, Rd=-1 -> source IS greater, C=1
    // Unsigned comparisons would produce the opposite C/V pair.
    p = place_movi_il(p, 4'd12, 32'hFFFF_0001);
    p = place_movi_il(p, 4'd13, 32'h0001_FFFF);
    p = place_word(p, subxy_enc(4'd13, 4'd12));
    p = place_word(p, getst_enc(4'd14));

    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (1500) @(posedge clk);
    #1;

    check_reg("ADDXY1: A0 = 0x80008000", u_core.u_regfile.a_regs[0], 32'h8000_8000);
    check_nczv("ADDXY1 NCZV=0101", u_core.u_regfile.a_regs[8], 4'b0101);
    check_reg("ADDXY2: A2 = 0", u_core.u_regfile.a_regs[2], 32'h0000_0000);
    check_nczv("ADDXY2 NCZV=1010", u_core.u_regfile.a_regs[9], 4'b1010);
    check_reg("SUBXY1: A4 = 0", u_core.u_regfile.a_regs[4], 32'h0000_0000);
    check_nczv("SUBXY1 NCZV=1010", u_core.u_regfile.a_regs[10], 4'b1010);
    check_reg("SUBXY2: A6 = 0xFFF9FFF9", u_core.u_regfile.a_regs[6], 32'hFFF9_FFF9);
    check_nczv("SUBXY2 NCZV=0101", u_core.u_regfile.a_regs[11], 4'b0101);
    check_reg("SUBXY signed: A12 = 0xFFFE0002",
              u_core.u_regfile.a_regs[12], 32'hFFFE_0002);
    check_nczv("SUBXY signed discriminator NCZV=0100",
               u_core.u_regfile.a_regs[14], 4'b0100);
    // Sources unchanged.
    check_reg("ADDXY1: A1 (src) unchanged", u_core.u_regfile.a_regs[1], 32'h0000_0000);
    check_reg("SUBXY2: A7 (src) unchanged", u_core.u_regfile.a_regs[7], 32'h0010_0010);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (ADDXY/SUBXY: dual 16-bit add/sub + graphics NCZV per TI tables)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_addxy_subxy hard timeout");
    $fatal(1);
  end

endmodule : tb_addxy_subxy
