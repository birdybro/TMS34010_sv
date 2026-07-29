// -----------------------------------------------------------------------------
// tb_io_access.sv
//
// I/O register access through the core's memory path (Task 0082). The I/O
// register file is now instantiated inside the core: an access whose address
// decodes as I/O space (0xC0000000-0xC00001FF) reads/writes the on-chip
// register instead of external memory. This test uses MOVE absolute (FS=16,
// the reset field size) to write a register and read it back, and confirms a
// normal external MOVE still works through the same read-data mux.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_io_access;
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
    .state_o(state_w), .pc_o(pc_w), .instr_word_o(instr_w), .illegal_opcode_o(illegal_w), .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1), .lint2_n_i(1'b1), .host_int_set_i(1'b0), .dpyint_set_i(1'b0)
  );

  sim_memory_model #(.DEPTH_WORDS(256)) u_mem (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack)
  );

  function automatic instr_word_t movi_il_enc(input reg_idx_t i);
    movi_il_enc = 16'h09E0 | instr_word_t'(i);
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
  // MOVE Rs,@DAddr store: 0x0580 | Rs, then addr LSW, MSW.
  function automatic int unsigned place_store_abs(input int unsigned p,
                                                  input reg_idx_t rs,
                                                  input logic [31:0] addr);
    u_mem.mem[p]     = 16'h0580 | instr_word_t'(rs);
    u_mem.mem[p + 1] = addr[15:0];
    u_mem.mem[p + 2] = addr[31:16];
    place_store_abs = p + 3;
  endfunction
  // MOVE @SAddr,Rd load: 0x05A0 | Rd, then addr LSW, MSW.
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
  task automatic check_io(input string label, input logic [IO_REG_IDX_W-1:0] idx,
                          input logic [15:0] expected);
    if (u_core.u_io_regs.io_reg[idx] !== expected) begin
      $display("TEST_RESULT: FAIL: %s: io_reg[%02h] expected=%04h actual=%04h",
               label, idx, expected, u_core.u_io_regs.io_reg[idx]);
      failures++;
    end
  endtask

  localparam logic [31:0] A_PSIZE = IO_BASE_ADDR + (IO_IDX_PSIZE << 4); // C0000150
  localparam logic [31:0] A_PMASK = IO_BASE_ADDR + (IO_IDX_PMASK << 4); // C0000160

  initial begin : main
    int unsigned p, i;
    failures = 0;
    for (i = 0; i < 256; i++) u_mem.mem[i] = 16'h0300;   // NOP fill
    for (i = 120; i < 160; i++) u_mem.mem[i] = 16'h0000; // clear data region

    p = 0;
    p = place_word(p, setf_enc(5'd16, 1'b0, 1'b0));      // FS0=16 (= reset value)
    // 1) Write PSIZE = 0x1234 via MOVE absolute, read it back.
    p = place_movi_il(p, 4'd1, 32'h0000_1234);
    p = place_store_abs(p, 4'd1, A_PSIZE);               // io_reg[PSIZE] <- 0x1234
    p = place_load_abs (p, 4'd2, A_PSIZE);               // A2 <- 0x00001234
    // 2) Write PMASK = 0xABCD, read it back (no aliasing with PSIZE).
    p = place_movi_il(p, 4'd3, 32'h0000_ABCD);
    p = place_store_abs(p, 4'd3, A_PMASK);
    p = place_load_abs (p, 4'd4, A_PMASK);               // A4 <- 0x0000ABCD
    // 3) A normal external MOVE still works through the read-data mux.
    p = place_movi_il(p, 4'd5, 32'h0000_9999);
    p = place_store_abs(p, 4'd5, 32'h0000_0800);         // mem[word128] <- 0x9999
    p = place_load_abs (p, 4'd6, 32'h0000_0800);         // A6 <- 0x00009999

    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (2500) @(posedge clk);
    #1;

    // 1) PSIZE round-trip.
    check_reg("1: A2 = 0x00001234",      u_core.u_regfile.a_regs[2], 32'h0000_1234);
    check_io ("1: io_reg[PSIZE]=0x1234", IO_IDX_PSIZE, 16'h1234);
    // 2) PMASK round-trip; PSIZE unchanged (no aliasing).
    check_reg("2: A4 = 0x0000ABCD",      u_core.u_regfile.a_regs[4], 32'h0000_ABCD);
    check_io ("2: io_reg[PMASK]=0xABCD", IO_IDX_PMASK, 16'hABCD);
    check_io ("2: io_reg[PSIZE] still 0x1234", IO_IDX_PSIZE, 16'h1234);
    // 3) External MOVE unaffected by the I/O mux.
    check_reg("3: A6 = 0x00009999",      u_core.u_regfile.a_regs[6], 32'h0000_9999);
    if (u_mem.mem[128] !== 16'h9999) begin
      $display("TEST_RESULT: FAIL: 3: ext mem[128] expected=9999 actual=%04h", u_mem.mem[128]);
      failures++;
    end

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (I/O access: MOVE store/load to PSIZE/PMASK on-chip; external MOVE intact)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_io_access hard timeout");
    $fatal(1);
  end

endmodule : tb_io_access
