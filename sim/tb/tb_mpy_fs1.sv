// -----------------------------------------------------------------------------
// tb_mpy_fs1.sv
//
// MPYS / MPYU with a variable multiplier width (FS1 != 32). Per SPVU001A
// pages 12-164 (MPYS) / 12-166 (MPYU): the Rs multiplier is an FS1-bit
// field. The low FS1 bits are sign-extended (MPYS) or zero-extended (MPYU)
// to 32 bits before the multiply; Rd (the multiplicand) stays full 32-bit.
// FS1 is set with SETF (F=1). FS1=0 encodes width 32 (covered by tb_mpy).
//
// MPYU validation rows are TI's MPYU example with Rd=0xFFFF0000,
// Rs=0x10001010 at successive field sizes:
//   FS1=16  field=0x1010 -> 0x0000100F_EFF00000
//   FS1=8   field=0x0010 -> 0x0000000F_FFF00000
//   FS1=4   field=0x0000 -> 0x00000000_00000000
// MPYS rows exercise the sign-extension of the extracted field.
//
//   Even Rd: 64-bit result -> {Rd = hi32, Rd+1 = lo32}.
//   Odd  Rd: low 32 bits -> Rd.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_mpy_fs1;
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
    .state_o(state_w), .pc_o(pc_w), .instr_word_o(instr_w), .illegal_opcode_o(illegal_w), .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1), .lint2_n_i(1'b1), .host_int_set_i(1'b0), .dpyint_set_i(1'b0), .refresh_req_o(), .refresh_row_o(), .refresh_cbr_o(), .video_hsync_o(), .video_vsync_o(), .video_hblank_o(), .video_vblank_o(), .video_blank_o()
  );

  sim_memory_model #(.DEPTH_WORDS(128)) u_mem (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack)
  );

  function automatic instr_word_t movi_il_enc(input reg_idx_t i);
    movi_il_enc = 16'h09E0 | instr_word_t'(i);   // A-file MOVI IL
  endfunction
  function automatic instr_word_t mpys_enc(input reg_idx_t rs, input reg_idx_t rd);
    mpys_enc = 16'h5C00 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
  endfunction
  function automatic instr_word_t mpyu_enc(input reg_idx_t rs, input reg_idx_t rd);
    mpyu_enc = 16'h5E00 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
  endfunction
  // SETF: bits = {6'b000001, F, 1'b1, 2'b01, FE, FS[4:0]}.
  function automatic instr_word_t setf_enc(input logic [4:0] fs,
                                           input logic       fe,
                                           input logic       f_sel);
    setf_enc = 16'b0000_0100_0000_0000
             | (instr_word_t'(f_sel) << 9)
             | 16'b0000_0001_0000_0000
             | 16'b0000_0000_0100_0000
             | (instr_word_t'(fe) << 5)
             | instr_word_t'(fs);
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

  initial begin : main
    int unsigned p, i;
    failures = 0;
    for (i = 0; i < 128; i++) u_mem.mem[i] = 16'h0300;

    p = 0;
    // 1) MPYU FS1=16, even Rd: A0=0xFFFF0000 (Rd), A1=0x10001010 (Rs).
    //    field=0x1010 -> 0x0000100F_EFF00000. A0=0x0000100F, A1=0xEFF00000.
    p = place_word(p, setf_enc(5'd16, 1'b0, 1'b1));
    p = place_movi_il(p, 4'd0, 32'hFFFF_0000);
    p = place_movi_il(p, 4'd1, 32'h1000_1010);
    p = place_word(p, mpyu_enc(4'd1, 4'd0));
    // 2) MPYU FS1=8, even Rd: A2=0xFFFF0000 (Rd), A3=0x10001010 (Rs).
    //    field=0x10 -> 0x0000000F_FFF00000. A2=0x0000000F, A3=0xFFF00000.
    p = place_word(p, setf_enc(5'd8, 1'b0, 1'b1));
    p = place_movi_il(p, 4'd2, 32'hFFFF_0000);
    p = place_movi_il(p, 4'd3, 32'h1000_1010);
    p = place_word(p, mpyu_enc(4'd3, 4'd2));
    // 3) MPYU FS1=4, even Rd: A4=0xFFFF0000 (Rd), A5=0x10001010 (Rs).
    //    field=0x0 -> 0. A4=0, A5=0.
    p = place_word(p, setf_enc(5'd4, 1'b0, 1'b1));
    p = place_movi_il(p, 4'd4, 32'hFFFF_0000);
    p = place_movi_il(p, 4'd5, 32'h1000_1010);
    p = place_word(p, mpyu_enc(4'd5, 4'd4));
    // 4) MPYS FS1=8 negative field, even Rd: A8=5 (Rd), A9=0x000000FF (Rs).
    //    field=0xFF (bit7=1) sign-extends to -1; 5*-1 = -5.
    //    A8=0xFFFFFFFF (hi), A9=0xFFFFFFFB (lo).
    p = place_word(p, setf_enc(5'd8, 1'b0, 1'b1));
    p = place_movi_il(p, 4'd8, 32'h0000_0005);
    p = place_movi_il(p, 4'd9, 32'h0000_00FF);
    p = place_word(p, mpys_enc(4'd9, 4'd8));
    // 5) MPYS FS1=8 positive field, odd Rd: A11=2 (Rd odd), A10=0x0000007F.
    //    field=0x7F (bit7=0) = +127; 2*127 = 254. A11=0x000000FE (low only).
    p = place_word(p, setf_enc(5'd8, 1'b0, 1'b1));
    p = place_movi_il(p, 4'd11, 32'h0000_0002);
    p = place_movi_il(p, 4'd10, 32'h0000_007F);
    p = place_word(p, mpys_enc(4'd10, 4'd11));

    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (2500) @(posedge clk);
    #1;

    // 1) MPYU FS1=16.
    check_reg("1: A0 = 0x0000100F (hi)", u_core.u_regfile.a_regs[0], 32'h0000_100F);
    check_reg("1: A1 = 0xEFF00000 (lo)", u_core.u_regfile.a_regs[1], 32'hEFF0_0000);
    // 2) MPYU FS1=8.
    check_reg("2: A2 = 0x0000000F (hi)", u_core.u_regfile.a_regs[2], 32'h0000_000F);
    check_reg("2: A3 = 0xFFF00000 (lo)", u_core.u_regfile.a_regs[3], 32'hFFF0_0000);
    // 3) MPYU FS1=4 -> 0.
    check_reg("3: A4 = 0 (hi)", u_core.u_regfile.a_regs[4], 32'h0000_0000);
    check_reg("3: A5 = 0 (lo)", u_core.u_regfile.a_regs[5], 32'h0000_0000);
    // 4) MPYS FS1=8 negative field.
    check_reg("4: A8 = 0xFFFFFFFF (hi)", u_core.u_regfile.a_regs[8], 32'hFFFF_FFFF);
    check_reg("4: A9 = 0xFFFFFFFB (lo)", u_core.u_regfile.a_regs[9], 32'hFFFF_FFFB);
    // 5) MPYS FS1=8 positive field, odd Rd.
    check_reg("5: A11 = 0x000000FE (lo only)", u_core.u_regfile.a_regs[11], 32'h0000_00FE);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (MPYS/MPYU variable FS1: field extract + sign/zero-extend per TI tables)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_mpy_fs1 hard timeout");
    $fatal(1);
  end

endmodule : tb_mpy_fs1
