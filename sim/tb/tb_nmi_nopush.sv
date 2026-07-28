// -----------------------------------------------------------------------------
// tb_nmi_nopush.sv
//
// Nonmaskable interrupt, no-context-save mode (NMIM=1). Per 1988 UG §8: when
// HSTCTLH.NMIM=1, the device saves NOTHING on the stack — it vectors straight
// to the NMI handler (trap 8, 0xFFFFFEE0) and auto-clears the NMI bit. SP is
// left unchanged, but §8.5 still initializes the live ST for the service
// context. This exercises the no-push branch of the entry FSM.
//
//   main:  set SP/ST, write HSTCTLH = NMI|NMIM ; (next instr skipped)
//   ISR :  MOVI A6,0xCAFE, halt
//
// Checks: A6=0xCAFE (handler reached), SP=SP_INIT (nothing pushed),
// ST=ST_RESET_VALUE, HSTCTLH.NMI auto-cleared.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_nmi_nopush;
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
    .state_o(state_w), .pc_o(pc_w), .instr_word_o(instr_w), .illegal_opcode_o(illegal_w)
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
  bit saw_push_state;
  task automatic check_reg(input string label, input logic [DATA_WIDTH-1:0] actual, expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%08h actual=%08h", label, expected, actual);
      failures++;
    end
  endtask

  localparam logic [DATA_WIDTH-1:0] SP_INIT    = 32'h0000_0800;
  localparam logic [DATA_WIDTH-1:0] SERVICE_PC = 32'h0000_0640; // word 100
  localparam logic [DATA_WIDTH-1:0] PRE_NMI_ST = 32'hF5A5_0C3F;
  localparam logic [31:0] A_HSTCTLH =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_HSTCTLH) << 4);
  localparam logic [15:0] NMI_REQ_NMIM1 =
      16'((1 << HSTCTL_NMI_BIT) | (1 << HSTCTL_NMIM_BIT)); // 0x0300
  localparam int unsigned VEC_LO = 1006, VEC_HI = 1007;

  always @(posedge clk) begin
    if (!rst && ((state_w == CORE_INT_PUSH_PC) ||
                 (state_w == CORE_INT_PUSH_ST))) begin
      saw_push_state = 1'b1;
    end
  end

  initial begin : main
    int unsigned p, i;
    failures = 0;
    saw_push_state = 1'b0;
    for (i = 0; i < 1024; i++) u_mem.mem[i] = 16'h0300;

    // ISR (word 100): A6 <- 0xCAFE, halt. No RETI (NMIM=1 saved no context).
    p = 100;
    p = place_movi_il(p, 4'd6, 32'h0000_CAFE);
    p = place_word(p, 16'hC0FF);

    u_mem.mem[VEC_LO] = SERVICE_PC[15:0];
    u_mem.mem[VEC_HI] = SERVICE_PC[31:16];

    p = 0;
    p = place_movi_il(p, 4'd2, SP_INIT);
    p = place_word(p, 16'h4C4F);                   // MOVE A2,A15 (SP)
    p = place_movi_il(p, 4'd1, PRE_NMI_ST);
    p = place_word(p, 16'h01A1);                   // PUTST A1
    p = place_movi_il(p, 4'd0, {16'h0, NMI_REQ_NMIM1});
    p = place_store_abs(p, 4'd0, A_HSTCTLH);       // HSTCTLH <- NMI|NMIM
    // Following instruction would-be A5=0xDEAD; must be skipped (no resume).
    p = place_movi_il(p, 4'd5, 32'h0000_DEAD);
    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    #1;
    rst = 1'b0;
    repeat (4000) @(posedge clk);
    #1;

    check_reg("NMI NMIM=1: handler reached (A6=0xCAFE)",
              u_core.u_regfile.a_regs[6], 32'h0000_CAFE);
    check_reg("NMI NMIM=1: nothing pushed (SP unchanged)",
              u_core.u_regfile.sp_q, SP_INIT);
    check_reg("NMI NMIM=1: live ST initialized",
              u_core.u_status_reg.st_q, ST_RESET_VALUE);
    check_reg("NMI NMIM=1: instruction after request skipped (A5 not 0xDEAD)",
              u_core.u_regfile.a_regs[5], 32'h0000_0000);
    if (saw_push_state) begin
      $display("TEST_RESULT: FAIL: NMIM=1 entered a stack-push state");
      failures++;
    end
    if (u_core.u_io_regs.io_reg[IO_IDX_HSTCTLH][HSTCTL_NMI_BIT] !== 1'b0) begin
      $display("TEST_RESULT: FAIL: HSTCTLH.NMI not auto-cleared");
      failures++;
    end
    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set"); failures++;
    end

    if (failures == 0)
      $display("TEST_RESULT: PASS (NMI NMIM=1: no push, SP unchanged, ST initialized, vector taken)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #500_000;
    $display("TEST_RESULT: FAIL: tb_nmi_nopush hard timeout");
    $fatal(1);
  end
endmodule : tb_nmi_nopush
