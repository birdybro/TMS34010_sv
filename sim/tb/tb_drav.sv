// -----------------------------------------------------------------------------
// tb_drav.sv
//
// DRAV Rs,Rd — Draw and Advance (SPVU001A page 12-67, encoding 0xF600).
// Writes COLOR1 (B9) to the pixel at Rd's XY address (PSIZE-bit, with the
// CONTROL pixel-processing options), then advances Rd by Rs as an XY add
// (X+X, Y+Y, no carry between halves). W=0 (no windowing) — A0031.
//
// Setup: PSIZE=8, CONVDP=0x1B (Y shift 4), OFFSET(B4)=0x800, COLOR1(B9)=0xAA,
// CONTROL=0 (PPOP=replace, T=0, PMASK=0, W=0).
//   Rd=A2 = XY(0x20,1) → linear (1<<4)|(0x20<<3)+0x800 = 0x910 (word 145, low
//   byte = X=0x20). Rs=A1 = XY(1,0) (advance X by 1).
// Two DRAVs draw both pixels of word 145 and chain the advance:
//   #1 draws X=0x20 (low byte) → A2 = (0x21,1);
//   #2 draws X=0x21 (high byte) → A2 = (0x22,1). word145 = 0xAAAA.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_drav;
  import tms34010_pkg::*;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  logic                          mem_req, mem_we, mem_ack;
  logic [ADDR_WIDTH-1:0]         mem_addr;
  logic [FIELD_SIZE_WIDTH-1:0]   mem_size;
  logic [DATA_WIDTH-1:0]         mem_wdata, mem_rdata;
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
  sim_memory_model #(.DEPTH_WORDS(256)) u_mem (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack)
  );

  function automatic instr_word_t movi_il_enc(input reg_idx_t i);
    movi_il_enc = 16'h09E0 | instr_word_t'(i);
  endfunction
  function automatic instr_word_t movi_il_b_enc(input reg_idx_t i);
    movi_il_b_enc = 16'h09F0 | instr_word_t'(i);
  endfunction
  function automatic instr_word_t setf_enc(input logic [4:0] fs, input logic fe, f_sel);
    setf_enc = 16'b0000_0100_0000_0000
             | (instr_word_t'(f_sel) << 9) | 16'b0000_0001_0000_0000
             | 16'b0000_0000_0100_0000 | (instr_word_t'(fe) << 5) | instr_word_t'(fs);
  endfunction
  function automatic instr_word_t drav_enc(input reg_file_t rf, input reg_idx_t rs, rd);
    drav_enc = 16'hF600 | (instr_word_t'(rs) << 5) | (instr_word_t'(rf) << 4) | instr_word_t'(rd);
  endfunction
  function automatic int unsigned place_movi_il(input int unsigned p, input reg_idx_t i,
                                                input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]=movi_il_enc(i); u_mem.mem[p+1]=imm[15:0]; u_mem.mem[p+2]=imm[31:16];
    place_movi_il = p + 3;
  endfunction
  function automatic int unsigned place_movi_il_b(input int unsigned p, input reg_idx_t i,
                                                  input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]=movi_il_b_enc(i); u_mem.mem[p+1]=imm[15:0]; u_mem.mem[p+2]=imm[31:16];
    place_movi_il_b = p + 3;
  endfunction
  function automatic int unsigned place_word(input int unsigned p, input instr_word_t w);
    u_mem.mem[p]=w; place_word=p+1;
  endfunction
  function automatic int unsigned place_store_abs(input int unsigned p, input reg_idx_t rs,
                                                  input logic [31:0] addr);
    u_mem.mem[p]=16'h0580|instr_word_t'(rs); u_mem.mem[p+1]=addr[15:0]; u_mem.mem[p+2]=addr[31:16];
    place_store_abs = p + 3;
  endfunction

  int unsigned failures;
  task automatic check_word(input string label, input int unsigned widx, input logic [15:0] expected);
    if (u_mem.mem[widx] !== expected) begin
      $display("TEST_RESULT: FAIL: %s: mem[%0d] expected=%04h actual=%04h",
               label, widx, expected, u_mem.mem[widx]);
      failures++;
    end
  endtask
  task automatic check_reg(input string label, input logic [DATA_WIDTH-1:0] actual, expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%08h actual=%08h", label, expected, actual);
      failures++;
    end
  endtask

  localparam logic [31:0] A_PSIZE  = IO_BASE_ADDR + (IO_IDX_PSIZE  << 4);
  localparam logic [31:0] A_CONVDP = IO_BASE_ADDR + (IO_IDX_CONVDP << 4);

  initial begin : main
    int unsigned p, i;
    failures = 0;
    for (i = 0; i < 256; i++) u_mem.mem[i] = 16'h0300;
    for (i = 120; i < 200; i++) u_mem.mem[i] = 16'h0000;

    p = 0;
    p = place_word(p, setf_enc(5'd16, 1'b0, 1'b0));      // FS0=16 for MOVE-to-I/O
    p = place_movi_il  (p, 4'd0, 32'h0000_0008);
    p = place_store_abs(p, 4'd0, A_PSIZE);               // PSIZE = 8
    p = place_movi_il  (p, 4'd0, 32'h0000_001B);
    p = place_store_abs(p, 4'd0, A_CONVDP);              // CONVDP = 0x1B
    p = place_movi_il_b(p, 4'd4, 32'h0000_0800);         // OFFSET (B4)
    p = place_movi_il_b(p, 4'd9, 32'h0000_00AA);         // COLOR1 (B9)
    p = place_movi_il  (p, 4'd1, 32'h0000_0001);         // Rs=A1 : XY (X=1,Y=0)
    p = place_movi_il  (p, 4'd2, 32'h0001_0020);         // Rd=A2 : XY (X=0x20,Y=1)
    p = place_word(p, drav_enc(REG_FILE_A, 4'd1, 4'd2)); // DRAV A1,A2  (= 0xF622)
    p = place_word(p, drav_enc(REG_FILE_A, 4'd1, 4'd2)); // DRAV A1,A2  (chained)
    p = place_word(p, 16'hC0FF);

    // Encoding sanity.
    if (drav_enc(REG_FILE_A, 4'd1, 4'd2) !== 16'hF622) begin
      $display("TEST_RESULT: FAIL: DRAV A1,A2 enc=%04h exp F622",
               drav_enc(REG_FILE_A, 4'd1, 4'd2));
      failures++;
    end

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (3000) @(posedge clk);
    #1;

    // Both pixels of word 145 drawn (low byte = X=0x20, high byte = X=0x21).
    check_word("DRAV: word145 = 0xAAAA (both pixels drawn)", 145, 16'hAAAA);
    // Rd advanced twice by Rs(1,0): (0x20,1) -> (0x21,1) -> (0x22,1).
    check_reg("DRAV: A2 advanced to XY(0x22,1)", u_core.u_regfile.a_regs[2], 32'h0001_0022);
    // Neighboring word untouched.
    check_word("DRAV: word146 untouched", 146, 16'h0000);
    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set"); failures++;
    end

    if (failures == 0)
      $display("TEST_RESULT: PASS (DRAV: COLOR1 drawn at Rd's XY, Rd advanced by Rs, chained)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_drav hard timeout");
    $fatal(1);
  end
endmodule : tb_drav
