// -----------------------------------------------------------------------------
// tb_move_abs.sv
//
// MOVE Rs,@DAddress (store) and MOVE @SAddress,Rd (load) — absolute
// addressing, field-size 32, word-aligned (Task 0063). Per SPVU001A
// pages 12-134 (store) and 12-153 (load).
//
//   MOVE Rs,@DAddr : 0000 01F1 100R SSSS + 32-bit addr. mem[DAddr] <- Rs.
//                    All flags Unaffected.
//   MOVE @SAddr,Rd : 0000 01F1 101R DDDD + 32-bit addr. Rd <- mem[SAddr].
//                    Implicit compare-to-0: N=sign, Z=zero, V=0, C Unaff.
//
// The absolute bit-address is the two words after the opcode (LSBs
// first), fetched via the imm32 path. Three store->load round-trips:
// negative (N=1), zero (Z=1), positive (N=0/Z=0); load flags captured
// with GETST snapshots.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_move_abs;
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
    .clk(clk), .vclk_i(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack),
    .state_o(state_w), .pc_o(pc_w), .instr_word_o(instr_w), .illegal_opcode_o(illegal_w), .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1), .lint2_n_i(1'b1), .hcs_n_i(1'b0), .host_req_i(1'b0), .host_we_i(1'b0), .host_reg_i(HOST_REG_HSTCTL), .host_be_i(2'b00), .host_wdata_i(16'h0000), .host_rdata_o(), .host_ack_o(), .host_busy_o(), .hint_n_o(), .host_mem_req_o(), .host_mem_we_o(), .host_mem_addr_o(), .host_mem_wdata_o(), .host_mem_rdata_i(16'h0000), .host_mem_ack_i(1'b0), .dpyint_set_i(1'b0), .refresh_req_o(), .refresh_row_o(), .refresh_cbr_o(), .video_hsync_o(), .video_vsync_o(), .video_hblank_o(), .video_vblank_o(), .video_blank_o(), .screen_refresh_req_o(), .screen_refresh_ack_i(1'b0), .screen_refresh_srfaddr_o(), .screen_refresh_dpytap_o()
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
  // MOVE Rs,@DAddr (store): 0x0580 | Rs, then addr LSW, addr MSW.
  function automatic int unsigned place_store_abs(input int unsigned p,
                                                  input reg_idx_t rs,
                                                  input logic [DATA_WIDTH-1:0] addr);
    u_mem.mem[p]     = 16'h0580 | instr_word_t'(rs);
    u_mem.mem[p + 1] = addr[15:0];
    u_mem.mem[p + 2] = addr[31:16];
    place_store_abs = p + 3;
  endfunction
  // MOVE @SAddr,Rd (load): 0x05A0 | Rd, then addr LSW, addr MSW.
  function automatic int unsigned place_load_abs(input int unsigned p,
                                                 input reg_idx_t rd,
                                                 input logic [DATA_WIDTH-1:0] addr);
    u_mem.mem[p]     = 16'h05A0 | instr_word_t'(rd);
    u_mem.mem[p + 1] = addr[15:0];
    u_mem.mem[p + 2] = addr[31:16];
    place_load_abs = p + 3;
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

  localparam logic [DATA_WIDTH-1:0] ADDR1 = 32'h0000_0800;  // word 128
  localparam logic [DATA_WIDTH-1:0] ADDR2 = 32'h0000_0900;  // word 144
  localparam logic [DATA_WIDTH-1:0] ADDR3 = 32'h0000_0A00;  // word 160

  initial begin : main
    int unsigned p, i;
    failures = 0;
    for (i = 0; i < 512; i++) u_mem.mem[i] = 16'h0300;

    p = 0;
    // MOVE absolute now honors the field size: set FS0 = 0 (encodes a 32-bit
    // field) so these full-word moves transfer 32 bits. Reset ST has FS0=16.
    p = place_word(p, 16'h0540);   // SETF FS=0, FE=0, F=0
    // Case 1: negative value round-trip via ADDR1.
    p = place_movi_il(p, 4'd1, 32'hCAFE_BABE);
    p = place_store_abs(p, 4'd1, ADDR1);     // MOVE A1,@ADDR1
    p = place_load_abs(p, 4'd2, ADDR1);      // MOVE @ADDR1,A2
    p = place_word(p, getst_enc(4'd3));      // snapshot flags

    // Case 2: zero round-trip via ADDR2.
    p = place_movi_il(p, 4'd4, 32'h0000_0000);
    p = place_store_abs(p, 4'd4, ADDR2);
    p = place_load_abs(p, 4'd5, ADDR2);
    p = place_word(p, getst_enc(4'd6));

    // Case 3: positive value round-trip via ADDR3.
    p = place_movi_il(p, 4'd7, 32'h1234_5678);
    p = place_store_abs(p, 4'd7, ADDR3);
    p = place_load_abs(p, 4'd8, ADDR3);
    p = place_word(p, getst_enc(4'd9));

    p = place_word(p, 16'hC0FF);             // halt

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (2000) @(posedge clk);
    #1;

    // Stores landed in memory.
    check_mem32("store: mem[ADDR1] = 0xCAFEBABE", ADDR1 >> 4, 32'hCAFE_BABE);
    check_mem32("store: mem[ADDR2] = 0x00000000", ADDR2 >> 4, 32'h0000_0000);
    check_mem32("store: mem[ADDR3] = 0x12345678", ADDR3 >> 4, 32'h1234_5678);
    // Loads recovered into registers.
    check_reg("load: A2 = 0xCAFEBABE", u_core.u_regfile.a_regs[2], 32'hCAFE_BABE);
    check_reg("load: A5 = 0x00000000", u_core.u_regfile.a_regs[5], 32'h0000_0000);
    check_reg("load: A8 = 0x12345678", u_core.u_regfile.a_regs[8], 32'h1234_5678);
    // Load flags.
    check_bit("C1 N=1", u_core.u_regfile.a_regs[3][ST_N_BIT], 1'b1);
    check_bit("C1 Z=0", u_core.u_regfile.a_regs[3][ST_Z_BIT], 1'b0);
    check_bit("C2 N=0", u_core.u_regfile.a_regs[6][ST_N_BIT], 1'b0);
    check_bit("C2 Z=1", u_core.u_regfile.a_regs[6][ST_Z_BIT], 1'b1);
    check_bit("C3 N=0", u_core.u_regfile.a_regs[9][ST_N_BIT], 1'b0);
    check_bit("C3 Z=0", u_core.u_regfile.a_regs[9][ST_Z_BIT], 1'b0);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (MOVE Rs,@DAddr / @SAddr,Rd: 3 store->load round-trips + load N/Z)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #5_000_000;
    $display("TEST_RESULT: FAIL: tb_move_abs hard timeout");
    $fatal(1);
  end

endmodule : tb_move_abs
