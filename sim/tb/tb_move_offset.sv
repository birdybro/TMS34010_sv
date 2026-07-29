// -----------------------------------------------------------------------------
// tb_move_offset.sv
//
// MOVE Rs,*Rd(offset) (store) and MOVE *Rs(offset),Rd (load) —
// register-indirect with a signed 16-bit offset, field-size 32,
// word-aligned (Task 0064). Per SPVU001A pages 12-132 (store) and
// 12-147 (load).
//
//   MOVE Rs,*Rd(off) : 1011 00FS SSSR DDDD + off. mem[Rd+sext(off)] <- Rs.
//                      Rd unchanged. All flags Unaffected.
//   MOVE *Rs(off),Rd : 1011 01FS SSSR DDDD + off. Rd <- mem[Rs+sext(off)].
//                      Rs unchanged. N=sign, Z=zero, V=0, C Unaffected.
//
// The offset is the 2nd instruction word (signed). Three store->load
// round-trips with positive, negative, and zero offsets; load flags via
// GETST snapshots. Offsets keep the effective address word-aligned.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_move_offset;
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
    .clk(clk), .vclk_i(clk), .video_hsync_n_i(1'b1), .video_vsync_n_i(1'b1), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack),
    .state_o(state_w), .pc_o(pc_w), .instr_word_o(instr_w), .illegal_opcode_o(illegal_w), .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1), .lint2_n_i(1'b1), .hcs_n_i(1'b0), .host_req_i(1'b0), .host_we_i(1'b0), .host_reg_i(HOST_REG_HSTCTL), .host_be_i(2'b00), .host_wdata_i(16'h0000), .host_rdata_o(), .host_ack_o(), .host_busy_o(), .hint_n_o(), .host_mem_req_o(), .host_mem_we_o(), .host_mem_addr_o(), .host_mem_wdata_o(), .host_mem_rdata_i(16'h0000), .host_mem_ack_i(1'b0), .dpyint_set_i(1'b0), .refresh_req_o(), .refresh_row_o(), .refresh_cbr_o(), .video_hsync_o(), .video_vsync_o(), .video_hblank_o(), .video_vblank_o(), .video_blank_o(), .video_hsync_oe_o(), .video_vsync_oe_o(), .screen_refresh_req_o(), .screen_refresh_ack_i(1'b0), .screen_refresh_srfaddr_o(), .screen_refresh_dpytap_o()
  );

  sim_memory_model #(.DEPTH_WORDS(512)) u_mem (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack)
  );

  function automatic instr_word_t movi_il_enc(input reg_idx_t i);
    movi_il_enc = 16'h09E0 | instr_word_t'(i);
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
  // MOVE Rs,*Rd(off) store: 0xB000 | (Rs<<5) | Rd, then offset.
  function automatic int unsigned place_store_off(input int unsigned p,
                                                  input reg_idx_t rs, input reg_idx_t rd,
                                                  input logic [15:0] off);
    u_mem.mem[p]     = 16'hB000 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
    u_mem.mem[p + 1] = off;
    place_store_off = p + 2;
  endfunction
  // MOVE *Rs(off),Rd load: 0xB400 | (Rs<<5) | Rd, then offset.
  function automatic int unsigned place_load_off(input int unsigned p,
                                                 input reg_idx_t rs, input reg_idx_t rd,
                                                 input logic [15:0] off);
    u_mem.mem[p]     = 16'hB400 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
    u_mem.mem[p + 1] = off;
    place_load_off = p + 2;
  endfunction
  function automatic int unsigned place_word(input int unsigned p, input instr_word_t w);
    u_mem.mem[p] = w;  place_word = p + 1;
  endfunction

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
  task automatic check_bit(input string label, input logic actual, expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%0b actual=%0b", label, expected, actual);
      failures++;
    end
  endtask

  initial begin : main
    int unsigned p, i;
    failures = 0;
    for (i = 0; i < 512; i++) u_mem.mem[i] = 16'h0300;

    p = 0;
    // MOVE offset now honors the field size: set FS0 = 0 (encodes a 32-bit
    // field) so these full-word moves transfer 32 bits. Reset ST has FS0=16.
    p = place_word(p, 16'h0540);   // SETF FS=0, FE=0, F=0
    // Case 1: positive offset +0x20, negative data. ptr A2=0x800 -> 0x820.
    p = place_movi_il(p, 4'd1, 32'hCAFE_BABE);
    p = place_movi_il(p, 4'd2, 32'h0000_0800);
    p = place_store_off(p, 4'd1, 4'd2, 16'h0020);   // mem[0x820] <- A1
    p = place_load_off(p, 4'd2, 4'd3, 16'h0020);    // A3 <- mem[0x820]
    p = place_word(p, getst_enc(4'd4));

    // Case 2: negative offset -0x20 (0xFFE0). ptr A6=0x900 -> 0x8E0.
    p = place_movi_il(p, 4'd5, 32'h1111_2222);
    p = place_movi_il(p, 4'd6, 32'h0000_0900);
    p = place_store_off(p, 4'd5, 4'd6, 16'hFFE0);   // mem[0x8E0] <- A5
    p = place_load_off(p, 4'd6, 4'd7, 16'hFFE0);    // A7 <- mem[0x8E0]

    // Case 3: zero offset, zero data. ptr A9=0xB00.
    p = place_movi_il(p, 4'd8, 32'h0000_0000);
    p = place_movi_il(p, 4'd9, 32'h0000_0B00);
    p = place_store_off(p, 4'd8, 4'd9, 16'h0000);   // mem[0xB00] <- A8
    p = place_load_off(p, 4'd9, 4'd10, 16'h0000);   // A10 <- mem[0xB00]
    p = place_word(p, getst_enc(4'd11));

    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (2000) @(posedge clk);
    #1;

    // Case 1: store@0x820, load back, N=1.
    check_mem32("C1: mem[0x820] = data (+off store)", 32'h820 >> 4, 32'hCAFE_BABE);
    check_reg("C1: A3 = data (+off load)", u_core.u_regfile.a_regs[3], 32'hCAFE_BABE);
    check_reg("C1: A2 (ptr) unchanged",    u_core.u_regfile.a_regs[2], 32'h0000_0800);
    check_bit("C1: load N=1", u_core.u_regfile.a_regs[4][ST_N_BIT], 1'b1);
    check_bit("C1: load Z=0", u_core.u_regfile.a_regs[4][ST_Z_BIT], 1'b0);

    // Case 2: store@0x8E0 (negative offset), load back.
    check_mem32("C2: mem[0x8E0] = data (-off store)", 32'h8E0 >> 4, 32'h1111_2222);
    check_reg("C2: A7 = data (-off load)", u_core.u_regfile.a_regs[7], 32'h1111_2222);
    check_reg("C2: A6 (ptr) unchanged",    u_core.u_regfile.a_regs[6], 32'h0000_0900);

    // Case 3: zero offset/data.
    check_mem32("C3: mem[0xB00] = 0 (zero off store)", 32'hB00 >> 4, 32'h0000_0000);
    check_reg("C3: A10 = 0 (zero off load)", u_core.u_regfile.a_regs[10], 32'h0000_0000);
    check_bit("C3: load N=0", u_core.u_regfile.a_regs[11][ST_N_BIT], 1'b0);
    check_bit("C3: load Z=1", u_core.u_regfile.a_regs[11][ST_Z_BIT], 1'b1);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (MOVE *Rd(off)/*Rs(off): +/-/zero offset store->load round-trips + N/Z)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #5_000_000;
    $display("TEST_RESULT: FAIL: tb_move_offset hard timeout");
    $fatal(1);
  end

endmodule : tb_move_offset
