// -----------------------------------------------------------------------------
// tb_move_offabs_field.sv
//
// Field-size-aware MOVE offset and absolute forms (Task 0078). Per SPVU001A
// pages 12-132 (MOVE Rs,*Rd(off)) / 12-141 (MOVE *Rs(off),Rd) / 12-134
// (MOVE Rs,@DAddr) / 12-133 (MOVE @SAddr,Rd). FS/FE come from the F-selected
// ST pair (F = instr bit 9 = 0 here, so FS0/FE0). Stores write the low FS
// bits; loads extend the FS-bit field per FE. Neither form steps a pointer.
//
// Cases: offset FS=8 zero/sign-extend round-trip; absolute FS=16 zero/sign-
// extend round-trip; an absolute FS=12 field straddling a 16-bit word.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_move_offabs_field;
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
    .state_o(state_w), .pc_o(pc_w), .instr_word_o(instr_w), .illegal_opcode_o(illegal_w), .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1), .lint2_n_i(1'b1), .host_int_set_i(1'b0), .dpyint_set_i(1'b0), .refresh_req_o(), .refresh_row_o(), .refresh_cbr_o(), .video_hsync_o(), .video_vsync_o(), .video_hblank_o(), .video_vblank_o(), .video_blank_o(), .screen_refresh_req_o(), .screen_refresh_ack_i(1'b0), .screen_refresh_srfaddr_o(), .screen_refresh_dpytap_o()
  );

  sim_memory_model #(.DEPTH_WORDS(256)) u_mem (
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
  function automatic instr_word_t setf_enc(input logic [4:0] fs,
                                           input logic fe, input logic f_sel);
    setf_enc = 16'b0000_0100_0000_0000
             | (instr_word_t'(f_sel) << 9) | 16'b0000_0001_0000_0000
             | 16'b0000_0000_0100_0000 | (instr_word_t'(fe) << 5)
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
  // MOVE Rs,*Rd(off) store: 0xB000 | (Rs<<5) | Rd, then offset word.
  function automatic int unsigned place_store_off(input int unsigned p,
                                                  input reg_idx_t rs, input reg_idx_t rd,
                                                  input logic [15:0] off);
    u_mem.mem[p]     = 16'hB000 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
    u_mem.mem[p + 1] = off;
    place_store_off = p + 2;
  endfunction
  // MOVE *Rs(off),Rd load: 0xB400 | (Rs<<5) | Rd, then offset word.
  function automatic int unsigned place_load_off(input int unsigned p,
                                                 input reg_idx_t rs, input reg_idx_t rd,
                                                 input logic [15:0] off);
    u_mem.mem[p]     = 16'hB400 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
    u_mem.mem[p + 1] = off;
    place_load_off = p + 2;
  endfunction
  // MOVE Rs,@DAddr store: 0x0580 | Rs, then addr LSW, addr MSW.
  function automatic int unsigned place_store_abs(input int unsigned p,
                                                  input reg_idx_t rs,
                                                  input logic [31:0] addr);
    u_mem.mem[p]     = 16'h0580 | instr_word_t'(rs);
    u_mem.mem[p + 1] = addr[15:0];
    u_mem.mem[p + 2] = addr[31:16];
    place_store_abs = p + 3;
  endfunction
  // MOVE @SAddr,Rd load: 0x05A0 | Rd, then addr LSW, addr MSW.
  function automatic int unsigned place_load_abs(input int unsigned p,
                                                 input reg_idx_t rd,
                                                 input logic [31:0] addr);
    u_mem.mem[p]     = 16'h05A0 | instr_word_t'(rd);
    u_mem.mem[p + 1] = addr[15:0];
    u_mem.mem[p + 2] = addr[31:16];
    place_load_abs = p + 3;
  endfunction

  int unsigned failures;
  task automatic check_reg(input string label,
                           input logic [DATA_WIDTH-1:0] actual, expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%08h actual=%08h", label, expected, actual);
      failures++;
    end
  endtask
  task automatic check_word(input string label, input int unsigned widx,
                            input logic [15:0] expected);
    if (u_mem.mem[widx] !== expected) begin
      $display("TEST_RESULT: FAIL: %s: mem[%0d] expected=%04h actual=%04h",
               label, widx, expected, u_mem.mem[widx]);
      failures++;
    end
  endtask
  task automatic check_nz(input string label, input logic [DATA_WIDTH-1:0] st,
                          input logic n, input logic z);
    if (st[ST_N_BIT] !== n || st[ST_Z_BIT] !== z) begin
      $display("TEST_RESULT: FAIL: %s: exp NZ=%0b%0b got %0b%0b",
               label, n, z, st[ST_N_BIT], st[ST_Z_BIT]);
      failures++;
    end
  endtask

  initial begin : main
    int unsigned p, i;
    failures = 0;
    for (i = 0; i < 256; i++) u_mem.mem[i] = 16'h0300;   // NOP fill
    for (i = 120; i < 200; i++) u_mem.mem[i] = 16'h0000; // clear data region

    p = 0;
    // 1) OFFSET FS=8 zext: A2=0x800 ptr; store A1=0xA5 at off 0x40
    //    (addr 0x840 = word132); load back -> 0x000000A5. N=0,Z=0.
    p = place_word(p, setf_enc(5'd8, 1'b0, 1'b0));
    p = place_movi_il(p, 4'd1, 32'h0000_00A5);
    p = place_movi_il(p, 4'd2, 32'h0000_0800);
    p = place_store_off(p, 4'd1, 4'd2, 16'h0040);   // mem[0x840] <- A1 (8b)
    p = place_load_off (p, 4'd2, 4'd3, 16'h0040);   // A3 <- field (zext)
    p = place_word(p, getst_enc(4'd8));

    // 2) OFFSET FS=8 sext: load same 0xA5 -> 0xFFFFFFA5. N=1.
    p = place_word(p, setf_enc(5'd8, 1'b1, 1'b0));
    p = place_load_off(p, 4'd2, 4'd4, 16'h0040);    // A4 <- field (sext)
    p = place_word(p, getst_enc(4'd9));

    // 3) ABSOLUTE FS=16 zext: store A5=0x1234 @ 0x900 (word144); load -> 0x1234.
    p = place_word(p, setf_enc(5'd16, 1'b0, 1'b0));
    p = place_movi_il(p, 4'd5, 32'h0000_1234);
    p = place_store_abs(p, 4'd5, 32'h0000_0900);    // mem[0x900] <- A5 (16b)
    p = place_load_abs (p, 4'd7, 32'h0000_0900);    // A7 <- field (zext)
    p = place_word(p, getst_enc(4'd10));

    // 4) ABSOLUTE FS=16 sext: store A8=0x9ABC @ 0x920 (word146); load sext
    //    -> 0xFFFF9ABC. N=1.
    p = place_word(p, setf_enc(5'd16, 1'b1, 1'b0));
    p = place_movi_il(p, 4'd8, 32'h0000_9ABC);
    p = place_store_abs(p, 4'd8, 32'h0000_0920);
    p = place_load_abs (p, 4'd11, 32'h0000_0920);   // A11 <- field (sext)
    p = place_word(p, getst_enc(4'd12));

    // 5) ABSOLUTE FS=12 straddling: store A13=0xABC at bit 0xA08
    //    (word160, bit offset 8); load back -> 0x00000ABC (zext).
    p = place_word(p, setf_enc(5'd12, 1'b0, 1'b0));
    p = place_movi_il(p, 4'd13, 32'h0000_0ABC);
    p = place_store_abs(p, 4'd13, 32'h0000_0A08);
    p = place_load_abs (p, 4'd14, 32'h0000_0A08);   // A14 <- field (zext)

    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (3000) @(posedge clk);
    #1;

    // 1) OFFSET FS=8 zext.
    check_word("1: mem[132] = 0x00A5", 132, 16'h00A5);
    check_reg ("1: A3 = 0x000000A5",   u_core.u_regfile.a_regs[3], 32'h0000_00A5);
    check_nz  ("1: load N=0 Z=0",      u_core.u_regfile.a_regs[8], 1'b0, 1'b0);
    // 2) OFFSET FS=8 sext.
    check_reg ("2: A4 = 0xFFFFFFA5",   u_core.u_regfile.a_regs[4], 32'hFFFF_FFA5);
    check_nz  ("2: load N=1 Z=0",      u_core.u_regfile.a_regs[9], 1'b1, 1'b0);
    // 3) ABSOLUTE FS=16 zext.
    check_word("3: mem[144] = 0x1234", 144, 16'h1234);
    check_reg ("3: A7 = 0x00001234",   u_core.u_regfile.a_regs[7], 32'h0000_1234);
    check_nz  ("3: load N=0 Z=0",      u_core.u_regfile.a_regs[10], 1'b0, 1'b0);
    // 4) ABSOLUTE FS=16 sext.
    check_word("4: mem[146] = 0x9ABC", 146, 16'h9ABC);
    check_reg ("4: A11 = 0xFFFF9ABC",  u_core.u_regfile.a_regs[11], 32'hFFFF_9ABC);
    check_nz  ("4: load N=1 Z=0",      u_core.u_regfile.a_regs[12], 1'b1, 1'b0);
    // 5) ABSOLUTE FS=12 straddling: 0xABC at boff8 -> word160[15:8]=0xBC,
    //    word161[3:0]=0xA.
    check_word("5: mem[160] = 0xBC00", 160, 16'hBC00);
    check_word("5: mem[161] = 0x000A", 161, 16'h000A);
    check_reg ("5: A14 = 0x00000ABC",  u_core.u_regfile.a_regs[14], 32'h0000_0ABC);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (MOVE offset/absolute field: FS!=32 store/load, FE extend, straddling)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #3_000_000;
    $display("TEST_RESULT: FAIL: tb_move_offabs_field hard timeout");
    $fatal(1);
  end

endmodule : tb_move_offabs_field
