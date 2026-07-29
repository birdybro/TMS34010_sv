// -----------------------------------------------------------------------------
// tb_int_priority.sv
//
// NMI + maskable interrupt pending simultaneously (Task 0104). Both are armed
// before the first instruction boundary; the core must take the NMI first
// (NMI has priority and ignores ST.IE), and the maskable display interrupt
// (DI) only afterwards. Ordering is guaranteed by construction: the NMI entry
// (NMIM=0) clears ST.IE, so DI — which requires IE=1 — cannot preempt the NMI
// handler; it can only fire once NMI's RETI restores IE=1. So if both handlers
// ran, RETI'd, and SP returned to its start, the NMI necessarily ran first.
//
//   main:  SP; INTENB.DI; hardware-set DIP; HSTCTLH.NMI(NMIM=0); EINT
//          <resume: MOVI A7,0x1234> ; halt
//   NMI ISR (vec 0xFFFFFEE0, word 100):  MOVI A5,0xBEEF ; RETI
//   DI  ISR (vec 0xFFFFFEA0, word 120):  MOVI A6,0xCAFE ; clear INTPEND ; RETI
//
// Sequence: NMI → RETI → DI → RETI → resume runs A7 → halt.
// Checks: A5,A6,A7 all set, SP=SP_INIT (both round-trips balanced), NMI and
// INTPEND cleared.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_int_priority;
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
  function automatic int unsigned place_movi_il(input int unsigned p, input reg_idx_t i,
                                                input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]=movi_il_enc(i); u_mem.mem[p+1]=imm[15:0]; u_mem.mem[p+2]=imm[31:16];
    place_movi_il = p + 3;
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
  task automatic check_reg(input string label, input logic [DATA_WIDTH-1:0] actual, expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%08h actual=%08h", label, expected, actual);
      failures++;
    end
  endtask

  // SP well clear of the handler code: word 300 (pushes land at words 296-299),
  // away from the main program (0..~40) and the NMI/DI handlers (100..129).
  localparam logic [DATA_WIDTH-1:0] SP_INIT     = 32'h0000_12C0; // word 300
  localparam logic [DATA_WIDTH-1:0] SERVICE_NMI = 32'h0000_0640; // word 100
  localparam logic [DATA_WIDTH-1:0] SERVICE_DI  = 32'h0000_0780; // word 120
  localparam logic [31:0] A_INTENB  = IO_BASE_ADDR + (IO_IDX_INTENB  << 4);
  localparam logic [31:0] A_INTPEND = IO_BASE_ADDR + (IO_IDX_INTPEND << 4);
  localparam logic [31:0] A_HSTCTLH = IO_BASE_ADDR + (IO_IDX_HSTCTLH << 4);
  localparam logic [15:0] DI_MASK   = 16'(1 << INT_DI_BIT);
  localparam logic [15:0] NMI_REQ   = 16'(1 << HSTCTL_NMI_BIT);  // NMIM=0
  localparam int unsigned NMI_VEC_LO = 1006, NMI_VEC_HI = 1007;  // 0xFFFFFEE0
  localparam int unsigned DI_VEC_LO  = 1002, DI_VEC_HI  = 1003;  // 0xFFFFFEA0

  initial begin : main
    int unsigned p, i;
    failures = 0;
    dpyint_set = 1'b0;
    for (i = 0; i < 1024; i++) u_mem.mem[i] = 16'h0300;

    // NMI ISR (word 100): A5 <- 0xBEEF, RETI.
    p = 100;
    p = place_movi_il(p, 4'd5, 32'h0000_BEEF);
    p = place_word(p, 16'h0940);
    // DI ISR (word 120): A6 <- 0xCAFE, clear INTPEND, RETI.
    p = 120;
    p = place_movi_il(p, 4'd6, 32'h0000_CAFE);
    p = place_movi_il(p, 4'd3, 32'h0);
    p = place_store_abs(p, 4'd3, A_INTPEND);
    p = place_word(p, 16'h0940);

    u_mem.mem[NMI_VEC_LO] = SERVICE_NMI[15:0]; u_mem.mem[NMI_VEC_HI] = SERVICE_NMI[31:16];
    u_mem.mem[DI_VEC_LO]  = SERVICE_DI[15:0];  u_mem.mem[DI_VEC_HI]  = SERVICE_DI[31:16];

    // Main: arm both, then EINT.
    p = 0;
    p = place_movi_il(p, 4'd2, SP_INIT);
    p = place_word(p, 16'h4C4F);                 // MOVE A2,A15
    p = place_movi_il(p, 4'd0, {16'h0, DI_MASK});
    p = place_store_abs(p, 4'd0, A_INTENB);      // INTENB.DI
    p = place_movi_il(p, 4'd4, {16'h0, NMI_REQ});
    p = place_store_abs(p, 4'd4, A_HSTCTLH);     // HSTCTLH.NMI (NMIM=0)
    p = place_word(p, 16'h0D60);                 // EINT
    p = place_movi_il(p, 4'd7, 32'h0000_1234);   // resume target
    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    @(negedge clk);
    dpyint_set = 1'b1;
    @(negedge clk);
    dpyint_set = 1'b0;
    repeat (6000) @(posedge clk);
    #1;

    check_reg("priority: NMI handler ran (A5=0xBEEF)", u_core.u_regfile.a_regs[5], 32'h0000_BEEF);
    check_reg("priority: DI handler ran (A6=0xCAFE)",  u_core.u_regfile.a_regs[6], 32'h0000_CAFE);
    check_reg("priority: resume ran after both (A7=0x1234)", u_core.u_regfile.a_regs[7], 32'h0000_1234);
    check_reg("priority: SP balanced (both RETI undid their push)",
              u_core.u_regfile.sp_q, SP_INIT);
    if (u_core.u_io_regs.io_reg[IO_IDX_HSTCTLH][HSTCTL_NMI_BIT] !== 1'b0) begin
      $display("TEST_RESULT: FAIL: HSTCTLH.NMI not cleared"); failures++;
    end
    if (u_core.u_io_regs.io_reg[IO_IDX_INTPEND] !== 16'h0000) begin
      $display("TEST_RESULT: FAIL: INTPEND not cleared"); failures++;
    end
    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set"); failures++;
    end

    if (failures == 0)
      $display("TEST_RESULT: PASS (NMI+maskable priority: NMI first then DI via RETI chain, SP balanced)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #800_000;
    $display("TEST_RESULT: FAIL: tb_int_priority hard timeout");
    $fatal(1);
  end
endmodule : tb_int_priority
