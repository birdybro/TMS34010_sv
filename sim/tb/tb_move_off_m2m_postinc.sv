// -----------------------------------------------------------------------------
// tb_move_off_m2m_postinc.sv
//
// End-to-end coverage for:
//   MOVE *Rs(offset),*Rd+ [,F] = 1101 00FS SSSR DDDD + signed offset16
//
// The source effective bit address is Rs + sign_extend(offset); Rs is
// unchanged. The field is written through the original Rd, then Rd advances
// by the selected FS. Memory-to-memory fields are not FE-extended and all
// status bits are unaffected.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_move_off_m2m_postinc;
  import tms34010_pkg::*;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  logic                        mem_req;
  logic                        mem_we;
  logic [ADDR_WIDTH-1:0]       mem_addr;
  logic [FIELD_SIZE_WIDTH-1:0] mem_size;
  logic [DATA_WIDTH-1:0]       mem_wdata;
  logic [DATA_WIDTH-1:0]       mem_rdata;
  logic                        mem_ack;
  core_state_t                 state_w;
  logic [ADDR_WIDTH-1:0]       pc_w;
  instr_word_t                 instr_w;
  logic                        illegal_w;

  tms34010_core u_core (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
    .mem_size(mem_size), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
    .mem_ack(mem_ack), .state_o(state_w), .pc_o(pc_w),
    .instr_word_o(instr_w), .illegal_opcode_o(illegal_w), .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1), .lint2_n_i(1'b1), .host_int_set_i(1'b0), .dpyint_set_i(1'b0), .refresh_req_o(), .refresh_row_o(), .refresh_cbr_o(), .video_hsync_o(), .video_vsync_o(), .video_hblank_o(), .video_vblank_o(), .video_blank_o(), .screen_refresh_req_o(), .screen_refresh_ack_i(1'b0), .screen_refresh_srfaddr_o(), .screen_refresh_dpytap_o()
  );

  sim_memory_model #(.DEPTH_WORDS(512)) u_mem (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
    .mem_size(mem_size), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
    .mem_ack(mem_ack)
  );

  function automatic instr_word_t movi_il_enc(input reg_idx_t rd);
    movi_il_enc = 16'h09E0 | instr_word_t'(rd);
  endfunction

  function automatic instr_word_t putst_enc(input reg_idx_t rs);
    putst_enc = 16'h01A0 | instr_word_t'(rs);
  endfunction

  function automatic instr_word_t getst_b_enc(input reg_idx_t rd);
    getst_b_enc = 16'h0190 | instr_word_t'(rd);
  endfunction

  function automatic instr_word_t move_enc(input logic f_sel,
                                           input reg_idx_t rs,
                                           input reg_idx_t rd);
    move_enc = 16'hD000
             | (instr_word_t'(f_sel) << 9)
             | (instr_word_t'(rs) << 5)
             | instr_word_t'(rd);
  endfunction

  function automatic int unsigned place_movi(input int unsigned p,
                                             input reg_idx_t rd,
                                             input logic [DATA_WIDTH-1:0] value);
    u_mem.mem[p]     = movi_il_enc(rd);
    u_mem.mem[p + 1] = value[15:0];
    u_mem.mem[p + 2] = value[31:16];
    place_movi = p + 3;
  endfunction

  function automatic int unsigned place_move(input int unsigned p,
                                             input logic f_sel,
                                             input reg_idx_t rs,
                                             input reg_idx_t rd,
                                             input logic [15:0] offset);
    u_mem.mem[p]     = move_enc(f_sel, rs, rd);
    u_mem.mem[p + 1] = offset;
    place_move = p + 2;
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

  task automatic check_word(input string label,
                            input int unsigned index,
                            input logic [15:0] expected);
    if (u_mem.mem[index] !== expected) begin
      $display("TEST_RESULT: FAIL: %s: mem[%0d] expected=%04h actual=%04h",
               label, index, expected, u_mem.mem[index]);
      failures++;
    end
  endtask

  initial begin : main
    int unsigned p;
    int unsigned i;
    failures = 0;

    for (i = 0; i < 512; i++) begin
      u_mem.mem[i] = 16'h0300;
    end
    for (i = 120; i < 240; i++) begin
      u_mem.mem[i] = 16'h0000;
    end

    // Case 1 source: 32-bit 0xCAFEBABE at bit address 0x820.
    u_mem.mem[130] = 16'hBABE;
    u_mem.mem[131] = 16'hCAFE;

    // Case 2 source: FS1=8 value 0xA5 at bit address 0xA15 (word 161,
    // bit offset 5). Destination starts with sentinel bits outside the
    // 8-bit field at 0xB07.
    u_mem.mem[161] = 16'h14A0;
    u_mem.mem[176] = 16'h8001;

    // Case 3 source: FS0=12 value 0xABC at bit address 0xC0B, straddling
    // words 192/193. Destination 0xD0D also straddles.
    u_mem.mem[192] = 16'hE000;
    u_mem.mem[193] = 16'h0055;

    if (move_enc(1'b0, 4'd1, 4'd2) !== 16'hD022) begin
      $display("TEST_RESULT: FAIL: F0 encoding expected D022, got %04h",
               move_enc(1'b0, 4'd1, 4'd2));
      failures++;
    end
    if (move_enc(1'b1, 4'd3, 4'd4) !== 16'hD264) begin
      $display("TEST_RESULT: FAIL: F1 encoding expected D264, got %04h",
               move_enc(1'b1, 4'd3, 4'd4));
      failures++;
    end

    p = 0;

    // 1) F0/FS=32, positive offset +0x20:
    //    mem[0x820] -> mem[0x900], A1 unchanged, A2 += 32.
    p = place_movi(p, 4'd14, 32'hD000_0000);
    p = place_movi(p, 4'd1, 32'h0000_0800);
    p = place_movi(p, 4'd2, 32'h0000_0900);
    u_mem.mem[p] = putst_enc(4'd14); p++;
    p = place_move(p, 1'b0, 4'd1, 4'd2, 16'h0020);
    u_mem.mem[p] = getst_b_enc(4'd0); p++;

    // 2) F1/FS=8, negative offset -11:
    //    A3=0xA20 -> source 0xA15; destination 0xB07; A4 += 8.
    p = place_movi(p, 4'd14, 32'hD000_0200);
    p = place_movi(p, 4'd3, 32'h0000_0A20);
    p = place_movi(p, 4'd4, 32'h0000_0B07);
    u_mem.mem[p] = putst_enc(4'd14); p++;
    p = place_move(p, 1'b1, 4'd3, 4'd4, 16'hFFF5);
    u_mem.mem[p] = getst_b_enc(4'd1); p++;

    // 3) F0/FS=12, positive offset +11, both fields straddling:
    //    source 0xC0B; destination 0xD0D; A6 += 12.
    p = place_movi(p, 4'd14, 32'hD000_000C);
    p = place_movi(p, 4'd5, 32'h0000_0C00);
    p = place_movi(p, 4'd6, 32'h0000_0D0D);
    u_mem.mem[p] = putst_enc(4'd14); p++;
    p = place_move(p, 1'b0, 4'd5, 4'd6, 16'h000B);
    u_mem.mem[p] = getst_b_enc(4'd2); p++;

    u_mem.mem[p] = 16'hC0FF;

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (2400) @(posedge clk);
    #1;

    check_word("1: destination low",  144, 16'hBABE);
    check_word("1: destination high", 145, 16'hCAFE);
    check_reg("1: Rs unchanged", u_core.u_regfile.a_regs[1], 32'h0000_0800);
    check_reg("1: Rd += 32",     u_core.u_regfile.a_regs[2], 32'h0000_0920);
    check_reg("1: status unchanged", u_core.u_regfile.b_regs[0], 32'hD000_0000);

    check_word("2: unaligned destination/preservation", 176, 16'hD281);
    check_reg("2: Rs unchanged", u_core.u_regfile.a_regs[3], 32'h0000_0A20);
    check_reg("2: Rd += 8",      u_core.u_regfile.a_regs[4], 32'h0000_0B0F);
    check_reg("2: status unchanged", u_core.u_regfile.b_regs[1], 32'hD000_0200);

    check_word("3: straddling destination low",  208, 16'h8000);
    check_word("3: straddling destination high", 209, 16'h0157);
    check_reg("3: Rs unchanged", u_core.u_regfile.a_regs[5], 32'h0000_0C00);
    check_reg("3: Rd += 12",     u_core.u_regfile.a_regs[6], 32'h0000_0D19);
    check_reg("3: status unchanged", u_core.u_regfile.b_regs[2], 32'hD000_000C);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (MOVE *Rs(offset),*Rd+: F0/F1, FS32/8/12, signed offsets, straddles, status)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #3_000_000;
    $display("TEST_RESULT: FAIL: tb_move_off_m2m_postinc hard timeout");
    $fatal(1);
  end

endmodule : tb_move_off_m2m_postinc
