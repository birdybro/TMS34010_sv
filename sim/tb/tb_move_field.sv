// -----------------------------------------------------------------------------
// tb_move_field.sv
//
// Field-size-aware MOVE register<->indirect (Task 0077). Per SPVU001A pages
// 12-127 (MOVE Rs,*Rd store) / 12-135 (MOVE *Rs,Rd load): the move transfers
// an FS-bit field, where FS / FE come from the F-selected (instr bit 9) ST
// pair (FS0/FE0 or FS1/FE1). FS=0 encodes 32. Stores write the low FS bits;
// loads extend the field to 32 bits per FE (1=sign, 0=zero). Indirect pointers
// auto-step by ±FS.
//
// Cases: FS=8 zero-extend round-trip, FS=8 sign-extend load, FS=16 sign-extend
// round-trip, FS=8 zero field (Z=1), FS-aware postincrement (+8), and an FS=16
// field straddling a 16-bit word boundary (unaligned bit address).
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_move_field;
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
    movi_il_enc = 16'h09E0 | instr_word_t'(i);   // A-file MOVI IL
  endfunction
  function automatic instr_word_t store_enc(input reg_idx_t rs, input reg_idx_t rd);
    store_enc = 16'h8000 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);  // MOVE Rs,*Rd
  endfunction
  function automatic instr_word_t load_enc(input reg_idx_t rs, input reg_idx_t rd);
    load_enc = 16'h8400 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);   // MOVE *Rs,Rd
  endfunction
  function automatic instr_word_t store_postinc_enc(input reg_idx_t rs, input reg_idx_t rd);
    store_postinc_enc = 16'h9000 | (instr_word_t'(rs) << 5) | instr_word_t'(rd); // MOVE Rs,*Rd+
  endfunction
  function automatic instr_word_t getst_enc(input reg_idx_t rd);
    getst_enc = 16'h0180 | instr_word_t'(rd);
  endfunction
  // SETF: {6'b000001, F, 1'b1, 2'b01, FE, FS[4:0]}.
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

  // Pointer constants (bit addresses). Word index = addr >> 4.
  localparam logic [31:0] P_A = 32'h0000_0800;  // word 128, aligned
  localparam logic [31:0] P_B = 32'h0000_0900;  // word 144, aligned
  localparam logic [31:0] P_C = 32'h0000_0A00;  // word 160, aligned
  localparam logic [31:0] P_D = 32'h0000_0B08;  // word 176, bit offset 8 (straddles)

  initial begin : main
    int unsigned p, i;
    failures = 0;
    for (i = 0; i < 256; i++) u_mem.mem[i] = 16'h0300;   // NOP fill
    for (i = 120; i < 200; i++) u_mem.mem[i] = 16'h0000; // clear data region

    p = 0;
    // 1) FS=8, FE=0 (zext): store 0xA5 at P_A, load back -> 0x000000A5. N=0,Z=0.
    p = place_word(p, setf_enc(5'd8, 1'b0, 1'b0));        // FS0=8, FE0=0
    p = place_movi_il(p, 4'd1, 32'h0000_00A5);            // data
    p = place_movi_il(p, 4'd2, P_A);                      // pointer
    p = place_word(p, store_enc(4'd1, 4'd2));             // mem[P_A] <- A1 (8b)
    p = place_word(p, load_enc(4'd2, 4'd3));              // A3 <- field (zext)
    p = place_word(p, getst_enc(4'd8));                   // snapshot ST

    // 2) FS=8, FE=1 (sext): load the same 0xA5 (bit7=1) -> 0xFFFFFFA5. N=1.
    p = place_word(p, setf_enc(5'd8, 1'b1, 1'b0));        // FS0=8, FE0=1
    p = place_word(p, load_enc(4'd2, 4'd4));              // A4 <- field (sext)
    p = place_word(p, getst_enc(4'd9));

    // 3) FS=16, FE=1 (sext): store 0x8000 at P_B, load back -> 0xFFFF8000. N=1.
    p = place_word(p, setf_enc(5'd16, 1'b1, 1'b0));       // FS0=16, FE0=1
    p = place_movi_il(p, 4'd5, 32'h0000_8000);            // data (bit15=1)
    p = place_movi_il(p, 4'd6, P_B);
    p = place_word(p, store_enc(4'd5, 4'd6));             // mem[P_B] <- A5 (16b)
    p = place_word(p, load_enc(4'd6, 4'd7));              // A7 <- field (sext)
    p = place_word(p, getst_enc(4'd10));

    // 4) FS=8, FE=0: zero field at P_C -> Z=1, N=0.
    p = place_word(p, setf_enc(5'd8, 1'b0, 1'b0));
    p = place_movi_il(p, 4'd11, 32'h0000_0000);           // data 0
    p = place_movi_il(p, 4'd12, P_C);
    p = place_word(p, store_enc(4'd11, 4'd12));
    p = place_word(p, load_enc(4'd12, 4'd13));            // A13 <- 0
    p = place_word(p, getst_enc(4'd14));

    // 5) FS-aware postincrement: FS=8, MOVE A1,*A2+ steps A2 by 8.
    //    Reload A2 = P_A first, then postinc store.
    p = place_word(p, setf_enc(5'd8, 1'b0, 1'b0));
    p = place_movi_il(p, 4'd2, P_A);
    p = place_word(p, store_postinc_enc(4'd1, 4'd2));     // A2 -> P_A + 8

    // 6) FS=16 field straddling a word boundary at P_D (bit offset 8):
    //    store 0xBEEF, load back -> 0x0000BEEF (zext). Round-trip through core.
    p = place_word(p, setf_enc(5'd16, 1'b0, 1'b0));       // FS0=16, FE0=0
    p = place_movi_il(p, 4'd5, 32'h0000_BEEF);
    p = place_movi_il(p, 4'd6, P_D);
    p = place_word(p, store_enc(4'd5, 4'd6));             // mem[P_D] <- 0xBEEF (16b @boff8)
    p = place_word(p, load_enc(4'd6, 4'd0));              // A0 <- field

    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (3000) @(posedge clk);
    #1;

    // 1) FS=8 zext.
    check_word("1: mem[128] = 0x00A5", 128, 16'h00A5);
    check_reg ("1: A3 = 0x000000A5",   u_core.u_regfile.a_regs[3], 32'h0000_00A5);
    check_nz  ("1: load N=0 Z=0",      u_core.u_regfile.a_regs[8], 1'b0, 1'b0);
    // 2) FS=8 sext.
    check_reg ("2: A4 = 0xFFFFFFA5",   u_core.u_regfile.a_regs[4], 32'hFFFF_FFA5);
    check_nz  ("2: load N=1 Z=0",      u_core.u_regfile.a_regs[9], 1'b1, 1'b0);
    // 3) FS=16 sext.
    check_word("3: mem[144] = 0x8000", 144, 16'h8000);
    check_reg ("3: A7 = 0xFFFF8000",   u_core.u_regfile.a_regs[7], 32'hFFFF_8000);
    check_nz  ("3: load N=1 Z=0",      u_core.u_regfile.a_regs[10], 1'b1, 1'b0);
    // 4) zero field.
    check_reg ("4: A13 = 0",           u_core.u_regfile.a_regs[13], 32'h0000_0000);
    check_nz  ("4: load N=0 Z=1",      u_core.u_regfile.a_regs[14], 1'b0, 1'b1);
    // 5) postincrement pointer stepped by FS=8.
    check_reg ("5: A2 = P_A + 8",      u_core.u_regfile.a_regs[2], P_A + 32'd8);
    // 6) straddling 16-bit field round-trip.
    //    0xBEEF at boff 8: word176[15:8]=0xEF, word177[7:0]=0xBE.
    check_word("6: mem[176] = 0xEF00", 176, 16'hEF00);
    check_word("6: mem[177] = 0x00BE", 177, 16'h00BE);
    check_reg ("6: A0 = 0x0000BEEF",   u_core.u_regfile.a_regs[0], 32'h0000_BEEF);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (MOVE field: FS!=32 store/load, FE sign/zero extend, FS pointer step, straddling)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #3_000_000;
    $display("TEST_RESULT: FAIL: tb_move_field hard timeout");
    $fatal(1);
  end

endmodule : tb_move_field
