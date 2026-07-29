// -----------------------------------------------------------------------------
// tb_int_reti.sv
//
// Full maskable-interrupt lifecycle: recognition + entry (Task 0100) followed
// by the ISR clearing the request and returning via RETI (Task 0102). This
// closes the loop the entry test (tb_int_entry) opened — it verifies the
// interrupt is taken exactly once, the ISR runs, RETI restores PC+ST (so
// execution resumes at the instruction that was about to run when the
// interrupt fired and ST.IE is re-enabled), and SP returns to its start.
//
//   main:  set SP, INTENB.DI, hardware-set INTPEND.DI, EINT
//          <resume target: MOVI A6,0x1234>   ; skipped on entry, run after RETI
//          halt
//   ISR :  clear INTPEND (MOVE 0), MOVI A5,0xBEEF, RETI
//
// Checks: A5=0xBEEF (ISR ran), A6=0x1234 (resumed + ran the target after RETI),
// SP=SP_INIT (push of 64 undone by RETI pop), ST.IE=1 (restored), INTPEND
// cleared (no re-entry).  1988 UG §8 + RETI (page 12-230).
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_int_reti;
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
  logic                          dpyint_set;

  tms34010_core u_core (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack),
    .state_o(state_w), .pc_o(pc_w), .instr_word_o(instr_w),
    .illegal_opcode_o(illegal_w), .run_emu_n_i(1'b1), .emua_n_o(),
    .lint1_n_i(1'b1), .lint2_n_i(1'b1), .host_int_set_i(1'b0),
    .dpyint_set_i(dpyint_set), .refresh_req_o(), .refresh_row_o(), .refresh_cbr_o()
  );

  sim_memory_model #(.DEPTH_WORDS(1024)) u_mem (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack)
  );

  function automatic instr_word_t movi_il_enc(input reg_idx_t i);
    movi_il_enc = 16'h09E0 | instr_word_t'(i);
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
    u_mem.mem[p] = w; place_word = p + 1;
  endfunction
  function automatic int unsigned place_store_abs(input int unsigned p,
                                                  input reg_idx_t rs,
                                                  input logic [31:0] addr);
    u_mem.mem[p]     = 16'h0580 | instr_word_t'(rs);
    u_mem.mem[p + 1] = addr[15:0];
    u_mem.mem[p + 2] = addr[31:16];
    place_store_abs = p + 3;
  endfunction

  int unsigned failures;
  task automatic check_reg(input string label,
                           input logic [DATA_WIDTH-1:0] actual, expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%08h actual=%08h", label, expected, actual);
      failures++;
    end
  endtask

  localparam logic [DATA_WIDTH-1:0] SP_INIT    = 32'h0000_0800; // word 128
  localparam logic [DATA_WIDTH-1:0] SERVICE_PC = 32'h0000_0640; // word 100 (ISR)
  localparam logic [31:0] A_INTENB  = IO_BASE_ADDR + (IO_IDX_INTENB  << 4);
  localparam logic [31:0] A_INTPEND = IO_BASE_ADDR + (IO_IDX_INTPEND << 4);
  localparam logic [15:0] DI_MASK   = 16'(1 << INT_DI_BIT);
  localparam int unsigned VEC_WORD_LO = 1002;
  localparam int unsigned VEC_WORD_HI = 1003;

  initial begin : main
    int unsigned p, i;
    failures = 0;
    dpyint_set = 1'b0;

    for (i = 0; i < 1024; i++) u_mem.mem[i] = 16'h0300; // NOP fill

    // ---- ISR at word 100: clear INTPEND, A5<-0xBEEF, RETI ---------------
    p = 100;
    p = place_movi_il(p, 4'd3, 32'h0);          // A3 <- 0
    p = place_store_abs(p, 4'd3, A_INTPEND);    // INTPEND <- 0 (clear request)
    p = place_movi_il(p, 4'd5, 32'h0000_BEEF);  // A5 <- 0xBEEF (ISR ran)
    p = place_word(p, 16'h0940);                // RETI

    // ---- Trap vector (DI) = SERVICE_PC ---------------------------------
    u_mem.mem[VEC_WORD_LO] = SERVICE_PC[15:0];
    u_mem.mem[VEC_WORD_HI] = SERVICE_PC[31:16];

    // ---- Main program at word 0 ----------------------------------------
    p = 0;
    p = place_movi_il(p, 4'd2, SP_INIT);
    p = place_word(p, 16'h4C4F);                // MOVE A2,A15 (SP <- SP_INIT)
    p = place_movi_il(p, 4'd0, {16'h0, DI_MASK});
    p = place_store_abs(p, 4'd0, A_INTENB);     // INTENB.DI <- 1
    p = place_word(p, 16'h0D60);                // EINT
    // Resume target: skipped on entry, executed after RETI returns here.
    p = place_movi_il(p, 4'd6, 32'h0000_1234);
    p = place_word(p, 16'hC0FF);                // halt

    repeat (3) @(posedge clk);
    rst = 1'b0;
    @(negedge clk);
    dpyint_set = 1'b1;
    @(negedge clk);
    dpyint_set = 1'b0;
    repeat (4000) @(posedge clk);
    #1;

    check_reg("RETI-loop: ISR ran (A5 = 0xBEEF)",
              u_core.u_regfile.a_regs[5], 32'h0000_BEEF);
    check_reg("RETI-loop: resumed after RETI, ran target (A6 = 0x1234)",
              u_core.u_regfile.a_regs[6], 32'h0000_1234);
    check_reg("RETI-loop: SP restored to SP_INIT (push undone)",
              u_core.u_regfile.sp_q, SP_INIT);
    // ST.IE restored to 1 by RETI; A6's MOVI leaves flags 0 → ST = 0x00200010.
    check_reg("RETI-loop: ST.IE re-enabled (ST = 0x00200010)",
              u_core.u_status_reg.st_q, 32'h0020_0010);
    // INTPEND cleared by the ISR → no re-entry.
    if (u_core.u_io_regs.io_reg[IO_IDX_INTPEND] !== 16'h0000) begin
      $display("TEST_RESULT: FAIL: INTPEND not cleared: %04h",
               u_core.u_io_regs.io_reg[IO_IDX_INTPEND]);
      failures++;
    end

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0)
      $display("TEST_RESULT: PASS (interrupt+RETI round-trip: ISR ran once, resumed, SP/ST restored, no re-entry)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #500_000;
    $display("TEST_RESULT: FAIL: tb_int_reti hard timeout");
    $fatal(1);
  end

endmodule : tb_int_reti
