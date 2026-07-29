// -----------------------------------------------------------------------------
// tb_move_m2m_field.sv
//
// Field-size-aware MOVE indirect-to-indirect (Task 0079). Per SPVU001A page
// 12-137 (MOVE *Rs,*Rd) / 12-138 (inc/dec). The two-step CORE_MEMORY sequence
// now reads an FS-bit field at mem[*Rs] into move_data_q and writes its low FS
// bits to mem[*Rd], with both pointers stepping by ±FS. mem->mem, so there is
// no FE extension. FS comes from the F-selected ST pair (F = instr bit 9 = 0
// here -> FS0).
//
// Cases: FS=8 plain copy, FS=8 postincrement (both pointers +8), and an FS=12
// copy where source and destination fields both straddle 16-bit word boundaries.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_move_m2m_field;
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

  sim_memory_model #(.DEPTH_WORDS(256)) u_mem (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack)
  );

  function automatic instr_word_t movi_il_enc(input reg_idx_t i);
    movi_il_enc = 16'h09E0 | instr_word_t'(i);
  endfunction
  function automatic instr_word_t m2m_enc(input reg_idx_t rs, input reg_idx_t rd);
    m2m_enc = 16'h8800 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);       // MOVE *Rs,*Rd
  endfunction
  function automatic instr_word_t m2m_postinc_enc(input reg_idx_t rs, input reg_idx_t rd);
    m2m_postinc_enc = 16'h9800 | (instr_word_t'(rs) << 5) | instr_word_t'(rd); // MOVE *Rs+,*Rd+
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

  initial begin : main
    int unsigned p, i;
    failures = 0;
    for (i = 0; i < 256; i++) u_mem.mem[i] = 16'h0300;   // NOP fill
    for (i = 120; i < 200; i++) u_mem.mem[i] = 16'h0000; // clear data region

    // Preloaded source fields.
    u_mem.mem[128] = 16'h00C3;   // case 1 src: 8-bit field 0xC3 @ bit 0x800
    u_mem.mem[136] = 16'h005A;   // case 2 src: 8-bit field 0x5A @ bit 0x880
    u_mem.mem[160] = 16'hBC00;   // case 3 src: 12-bit field 0xABC @ bit 0xA08
    u_mem.mem[161] = 16'h000A;   //             (boff 8: word160[15:8]=BC, word161[3:0]=A)

    p = 0;
    // 1) FS=8 plain copy: mem[0x800] (0xC3) -> mem[0x900].
    p = place_word(p, setf_enc(5'd8, 1'b0, 1'b0));
    p = place_movi_il(p, 4'd1, 32'h0000_0800);   // src ptr
    p = place_movi_il(p, 4'd2, 32'h0000_0900);   // dst ptr (word144)
    p = place_word(p, m2m_enc(4'd1, 4'd2));      // mem[0x900] <- mem[0x800] (8b)

    // 2) FS=8 postincrement: mem[0x880] (0x5A) -> mem[0x980]; A3,A4 += 8.
    p = place_movi_il(p, 4'd3, 32'h0000_0880);   // src ptr (word136)
    p = place_movi_il(p, 4'd4, 32'h0000_0980);   // dst ptr (word152)
    p = place_word(p, m2m_postinc_enc(4'd3, 4'd4));

    // 3) FS=12 straddling: mem[0xA08] (0xABC, straddles 160/161) ->
    //    mem[0xB08] (boff 8, straddles 176/177).
    p = place_word(p, setf_enc(5'd12, 1'b0, 1'b0));
    p = place_movi_il(p, 4'd5, 32'h0000_0A08);   // src ptr
    p = place_movi_il(p, 4'd6, 32'h0000_0B08);   // dst ptr
    p = place_word(p, m2m_enc(4'd5, 4'd6));

    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (3000) @(posedge clk);
    #1;

    // 1) FS=8 plain copy.
    check_word("1: mem[144] = 0x00C3", 144, 16'h00C3);
    // 2) FS=8 postinc: field copied + pointers stepped by 8.
    check_word("2: mem[152] = 0x005A", 152, 16'h005A);
    check_reg ("2: A3 = 0x888 (+8)",   u_core.u_regfile.a_regs[3], 32'h0000_0888);
    check_reg ("2: A4 = 0x988 (+8)",   u_core.u_regfile.a_regs[4], 32'h0000_0988);
    // 3) FS=12 straddling copy: 0xABC at dst boff 8 -> word176[15:8]=0xBC,
    //    word177[3:0]=0xA.
    check_word("3: mem[176] = 0xBC00", 176, 16'hBC00);
    check_word("3: mem[177] = 0x000A", 177, 16'h000A);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (MOVE M2M field: FS!=32 copy, FS pointer step, straddling src+dst)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #3_000_000;
    $display("TEST_RESULT: FAIL: tb_move_m2m_field hard timeout");
    $fatal(1);
  end

endmodule : tb_move_m2m_field
