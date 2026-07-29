// -----------------------------------------------------------------------------
// tb_logical_flags.sv
//
// Primary-spec status and encoding coverage for the complete logical family.
// Every logical instruction updates Z only and preserves N/C/V. ANDI and
// ANDNI share one hardware opcode that computes Rd & ~extension:
//   ANDI  IL,Rd stores ~IL in the two extension words.
//   ANDNI IL,Rd stores  IL in the two extension words.
//
// Also executes CLR as its exact XOR Rd,Rd alias. DEC's exact SUBK 1,Rd
// encoding assertion lives in tb_addk_subk.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_logical_flags;
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
    .clk             (clk), .vclk_i(clk), .video_hsync_n_i(1'b1), .video_vsync_n_i(1'b1),
    .rst             (rst),
    .mem_req         (mem_req),
    .mem_we          (mem_we),
    .mem_addr        (mem_addr),
    .mem_size        (mem_size),
    .mem_wdata       (mem_wdata),
    .mem_rdata       (mem_rdata),
    .mem_ack         (mem_ack),
    .state_o         (state_w),
    .pc_o            (pc_w),
    .instr_word_o    (instr_w),
    .illegal_opcode_o(illegal_w), .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1), .lint2_n_i(1'b1), .hcs_n_i(1'b0), .host_req_i(1'b0), .host_we_i(1'b0), .host_reg_i(HOST_REG_HSTCTL), .host_be_i(2'b00), .host_wdata_i(16'h0000), .host_rdata_o(), .host_ack_o(), .host_busy_o(), .hint_n_o(), .host_mem_req_o(), .host_mem_we_o(), .host_mem_addr_o(), .host_mem_wdata_o(), .host_mem_rdata_i(16'h0000), .host_mem_ack_i(1'b0), .dpyint_set_i(1'b0), .refresh_req_o(), .refresh_row_o(), .refresh_cbr_o(), .video_hsync_o(), .video_vsync_o(), .video_hblank_o(), .video_vblank_o(), .video_blank_o(), .video_hsync_oe_o(), .video_vsync_oe_o(), .screen_refresh_req_o(), .screen_refresh_ack_i(1'b0), .screen_refresh_srfaddr_o(), .screen_refresh_dpytap_o()
  );

  sim_memory_model #(.DEPTH_WORDS(512)) u_mem (
    .clk      (clk),
    .rst      (rst),
    .mem_req  (mem_req),
    .mem_we   (mem_we),
    .mem_addr (mem_addr),
    .mem_size (mem_size),
    .mem_wdata(mem_wdata),
    .mem_rdata(mem_rdata),
    .mem_ack  (mem_ack)
  );

  localparam logic [6:0] AND_TOP7  = 7'b0101_000;
  localparam logic [6:0] ANDN_TOP7 = 7'b0101_001;
  localparam logic [6:0] OR_TOP7   = 7'b0101_010;
  localparam logic [6:0] XOR_TOP7  = 7'b0101_011;
  localparam logic [10:0] LOGICAL_IL_TOP11 = 11'b0000_1011_100;
  localparam logic [10:0] ORI_IL_TOP11     = 11'b0000_1011_101;
  localparam logic [10:0] XORI_IL_TOP11    = 11'b0000_1011_110;

  localparam logic [DATA_WIDTH-1:0] ST_SEED    = 32'hD000_0010;
  localparam logic [DATA_WIDTH-1:0] ST_Z_CLEAR = 32'hD000_0010;
  localparam logic [DATA_WIDTH-1:0] ST_Z_SET   = 32'hF000_0010;

  function automatic instr_word_t movi_il_enc(input reg_file_t rf,
                                              input reg_idx_t rd);
    movi_il_enc = 16'h09E0
                | (instr_word_t'(rf) << 4)
                | instr_word_t'(rd);
  endfunction

  function automatic instr_word_t logical_rr_enc(input logic [6:0] top7,
                                                 input reg_idx_t rs,
                                                 input reg_idx_t rd);
    logical_rr_enc = (instr_word_t'(top7) << 9)
                   | (instr_word_t'(rs) << 5)
                   | instr_word_t'(rd);
  endfunction

  function automatic instr_word_t logical_il_enc(input logic [10:0] top11,
                                                 input reg_idx_t rd);
    logical_il_enc = (instr_word_t'(top11) << 5)
                   | instr_word_t'(rd);
  endfunction

  function automatic instr_word_t putst_enc(input reg_idx_t rs);
    putst_enc = 16'h01A0 | instr_word_t'(rs);
  endfunction

  function automatic instr_word_t getst_b_enc(input reg_idx_t rd);
    getst_b_enc = 16'h0190 | instr_word_t'(rd);
  endfunction

  function automatic instr_word_t not_enc(input reg_idx_t rd);
    not_enc = 16'h03E0 | instr_word_t'(rd);
  endfunction

  function automatic int unsigned place_movi(input int unsigned p,
                                             input reg_idx_t rd,
                                             input logic [DATA_WIDTH-1:0] value);
    u_mem.mem[p]     = movi_il_enc(REG_FILE_A, rd);
    u_mem.mem[p + 1] = value[15:0];
    u_mem.mem[p + 2] = value[31:16];
    place_movi = p + 3;
  endfunction

  function automatic int unsigned place_logical_il(
      input int unsigned p,
      input logic [10:0] top11,
      input reg_idx_t rd,
      input logic [DATA_WIDTH-1:0] extension);
    u_mem.mem[p]     = logical_il_enc(top11, rd);
    u_mem.mem[p + 1] = extension[15:0];
    u_mem.mem[p + 2] = extension[31:16];
    place_logical_il = p + 3;
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

  initial begin : main
    int unsigned p;
    int unsigned i;
    failures = 0;

    for (i = 0; i < 512; i++) begin
      u_mem.mem[i] = 16'h0300;
    end

    // Seed register kept intact for PUTST before every logical operation.
    p = 0;
    p = place_movi(p, 4'd14, ST_SEED);

    // AND A0,A1 -> nonzero; capture ST in B0.
    p = place_movi(p, 4'd0, 32'hF0F0_F0F0);
    p = place_movi(p, 4'd1, 32'h0FF0_FF0F);
    u_mem.mem[p] = putst_enc(4'd14); p++;
    u_mem.mem[p] = logical_rr_enc(AND_TOP7, 4'd0, 4'd1); p++;
    u_mem.mem[p] = getst_b_enc(4'd0); p++;

    // ANDN A2,A3 -> nonzero; capture ST in B1.
    p = place_movi(p, 4'd2, 32'hF0F0_F0F0);
    p = place_movi(p, 4'd3, 32'hFFFF_FFFF);
    u_mem.mem[p] = putst_enc(4'd14); p++;
    u_mem.mem[p] = logical_rr_enc(ANDN_TOP7, 4'd2, 4'd3); p++;
    u_mem.mem[p] = getst_b_enc(4'd1); p++;

    // OR A4,A5 -> nonzero; capture ST in B2.
    p = place_movi(p, 4'd4, 32'h0F0F_0F0F);
    p = place_movi(p, 4'd5, 32'hF0F0_F0F0);
    u_mem.mem[p] = putst_enc(4'd14); p++;
    u_mem.mem[p] = logical_rr_enc(OR_TOP7, 4'd4, 4'd5); p++;
    u_mem.mem[p] = getst_b_enc(4'd2); p++;

    // XOR A6,A7 -> nonzero; capture ST in B3.
    p = place_movi(p, 4'd6, 32'hAAAA_AAAA);
    p = place_movi(p, 4'd7, 32'h5555_5555);
    u_mem.mem[p] = putst_enc(4'd14); p++;
    u_mem.mem[p] = logical_rr_enc(XOR_TOP7, 4'd6, 4'd7); p++;
    u_mem.mem[p] = getst_b_enc(4'd3); p++;

    // CLR A8 is exactly XOR A8,A8 -> zero; capture ST in B4.
    p = place_movi(p, 4'd8, 32'hDEAD_BEEF);
    u_mem.mem[p] = putst_enc(4'd14); p++;
    u_mem.mem[p] = logical_rr_enc(XOR_TOP7, 4'd8, 4'd8); p++;
    u_mem.mem[p] = getst_b_enc(4'd4); p++;

    // NOT A9 -> zero; capture ST in B5.
    p = place_movi(p, 4'd9, 32'hFFFF_FFFF);
    u_mem.mem[p] = putst_enc(4'd14); p++;
    u_mem.mem[p] = not_enc(4'd9); p++;
    u_mem.mem[p] = getst_b_enc(4'd5); p++;

    // ANDI 0x0FF0FF0F,A10: assembler stores complemented extension.
    p = place_movi(p, 4'd10, 32'hF0F0_F0F0);
    u_mem.mem[p] = putst_enc(4'd14); p++;
    p = place_logical_il(p, LOGICAL_IL_TOP11, 4'd10, 32'hF00F_00F0);
    u_mem.mem[p] = getst_b_enc(4'd6); p++;

    // ANDNI 0xF0F0F0F0,A11: same opcode, direct extension.
    p = place_movi(p, 4'd11, 32'hFFFF_FFFF);
    u_mem.mem[p] = putst_enc(4'd14); p++;
    p = place_logical_il(p, LOGICAL_IL_TOP11, 4'd11, 32'hF0F0_F0F0);
    u_mem.mem[p] = getst_b_enc(4'd7); p++;

    // ORI and XORI use direct extensions and the same Z-only mask.
    p = place_movi(p, 4'd12, 32'h0000_0000);
    u_mem.mem[p] = putst_enc(4'd14); p++;
    p = place_logical_il(p, ORI_IL_TOP11, 4'd12, 32'h0000_0001);
    u_mem.mem[p] = getst_b_enc(4'd8); p++;

    p = place_movi(p, 4'd13, 32'hAAAA_AAAA);
    u_mem.mem[p] = putst_enc(4'd14); p++;
    p = place_logical_il(p, XORI_IL_TOP11, 4'd13, 32'hAAAA_AAAA);
    u_mem.mem[p] = getst_b_enc(4'd9); p++;

    // JRUC -1 loops on itself after the test program.
    u_mem.mem[p] = 16'hC0FF;

    repeat (3) @(posedge clk);
    rst = 1'b0;

    repeat (1800) @(posedge clk);
    #1;

    check_reg("AND result",   u_core.u_regfile.a_regs[1],  32'h00F0_F000);
    check_reg("ANDN result",  u_core.u_regfile.a_regs[3],  32'h0F0F_0F0F);
    check_reg("OR result",    u_core.u_regfile.a_regs[5],  32'hFFFF_FFFF);
    check_reg("XOR result",   u_core.u_regfile.a_regs[7],  32'hFFFF_FFFF);
    check_reg("CLR result",   u_core.u_regfile.a_regs[8],  32'h0000_0000);
    check_reg("NOT result",   u_core.u_regfile.a_regs[9],  32'h0000_0000);
    check_reg("ANDI result",  u_core.u_regfile.a_regs[10], 32'h00F0_F000);
    check_reg("ANDNI result", u_core.u_regfile.a_regs[11], 32'h0F0F_0F0F);
    check_reg("ORI result",   u_core.u_regfile.a_regs[12], 32'h0000_0001);
    check_reg("XORI result",  u_core.u_regfile.a_regs[13], 32'h0000_0000);

    check_reg("AND flags",   u_core.u_regfile.b_regs[0], ST_Z_CLEAR);
    check_reg("ANDN flags",  u_core.u_regfile.b_regs[1], ST_Z_CLEAR);
    check_reg("OR flags",    u_core.u_regfile.b_regs[2], ST_Z_CLEAR);
    check_reg("XOR flags",   u_core.u_regfile.b_regs[3], ST_Z_CLEAR);
    check_reg("CLR flags",   u_core.u_regfile.b_regs[4], ST_Z_SET);
    check_reg("NOT flags",   u_core.u_regfile.b_regs[5], ST_Z_SET);
    check_reg("ANDI flags",  u_core.u_regfile.b_regs[6], ST_Z_CLEAR);
    check_reg("ANDNI flags", u_core.u_regfile.b_regs[7], ST_Z_CLEAR);
    check_reg("ORI flags",   u_core.u_regfile.b_regs[8], ST_Z_CLEAR);
    check_reg("XORI flags",  u_core.u_regfile.b_regs[9], ST_Z_SET);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (all logical forms preserve N/C/V, update Z; ANDI/ANDNI conventions and CLR alias verified)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_logical_flags hard timeout");
    $fatal(1);
  end

endmodule : tb_logical_flags
