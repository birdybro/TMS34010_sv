// -----------------------------------------------------------------------------
// tb_int_entry.sv
//
// Maskable-interrupt recognition + entry sequence in the core (Task 0100).
// The core's int_ctrl asserts int_req when ST.IE=1 and an enabled INTPEND bit
// is set; at the CORE_FETCH boundary the core then runs the entry sequence:
//
//   1) SP -= 32; mem[SP] <- PC   (resume address)
//   2) SP -= 32; mem[SP] <- ST   (old ST, IE still 1)
//   3) PC <- mem[vector]         (ISR entry address)
//   4) ST <- 0x00000010          (fresh interrupt service context)
//
// (1988 UG §8 interrupt processing; the push order matches RETI's pop and the
// TRAP push.) NMI/host (HSTCTL) interrupts are separate and not covered here.
//
// Test plan (DI = display interrupt, bit 10, vector 0xFFFFFEA0):
//   - Set SP and INTENB.DI via MOVE absolute, pulse the display-timing
//     sideband that latches INTPEND.DI, then PUTST a distinguishable word with
//     IE=1. The next fetch must divert into the entry sequence (the marker
//     MOVI A6 right after PUTST must not run).
//   - The ISR at word 100 writes A5 = 0xBEEF and halts.
//   Verify: A5 = 0xBEEF (PC reached the vector), A6 = 0 (marker skipped),
//   SP = SP-64, pushed PC = marker address, pushed ST = old ST (IE=1),
//   current ST = ST_RESET_VALUE while the exact old ST is stacked.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_int_entry;
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
    .lint1_n_i(1'b1), .lint2_n_i(1'b1), .hcs_n_i(1'b0), .host_ctl_we_i(1'b0), .host_ctl_be_i(2'b00), .host_ctl_wdata_i(16'h0000), .host_ctl_rdata_o(), .hint_n_o(),
    .dpyint_set_i(dpyint_set), .refresh_req_o(), .refresh_row_o(), .refresh_cbr_o(), .video_hsync_o(), .video_vsync_o(), .video_hblank_o(), .video_vblank_o(), .video_blank_o(), .screen_refresh_req_o(), .screen_refresh_ack_i(1'b0), .screen_refresh_srfaddr_o(), .screen_refresh_dpytap_o()
  );

  // 1024 words → word_idx = mem_addr[13:4]. DI vector 0xFFFFFEA0 aliases to
  // (0xFFFFFEA0>>4)&0x3FF = 0x3EA = 1002 (low half), 1003 (high half).
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
  // MOVE Rs,@DAddr store: 0x0580 | Rs, then addr LSW, MSW.
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
  // IE=1 plus nondefault flags/field definitions; distinguishes full
  // architectural ST initialization from the old "clear IE only" behavior.
  localparam logic [DATA_WIDTH-1:0] PRE_INT_ST = 32'hF0E0_0C3F;
  localparam logic [31:0] A_INTENB =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_INTENB) << 4); // C0000110
  localparam logic [15:0] DI_MASK   = 16'(1 << INT_DI_BIT);                 // 0x0400
  localparam int unsigned VEC_WORD_LO = 1002;
  localparam int unsigned VEC_WORD_HI = 1003;

  initial begin : main
    int unsigned p, i, marker_word;
    logic [DATA_WIDTH-1:0] pushed_pc, pushed_st;
    failures = 0;
    dpyint_set = 1'b0;

    for (i = 0; i < 1024; i++) u_mem.mem[i] = 16'h0300; // NOP fill

    // ---- ISR at word 100: A5 <- 0xBEEF, then halt ----------------------
    p = 100;
    p = place_movi_il(p, 4'd5, 32'h0000_BEEF);
    u_mem.mem[p] = 16'hC0FF;

    // ---- Trap vector (DI) = SERVICE_PC ---------------------------------
    u_mem.mem[VEC_WORD_LO] = SERVICE_PC[15:0];
    u_mem.mem[VEC_WORD_HI] = SERVICE_PC[31:16];

    // ---- Main program at word 0 ----------------------------------------
    p = 0;
    // SP <- SP_INIT (MOVI A2, SP_INIT ; MOVE A2,A15 = 0x4C4F).
    p = place_movi_il(p, 4'd2, SP_INIT);
    p = place_word(p, 16'h4C4F);
    // INTENB.DI <- 1 (enable display interrupt).
    p = place_movi_il(p, 4'd0, {16'h0, DI_MASK});
    p = place_store_abs(p, 4'd0, A_INTENB);
    // Install a nondefault ST whose IE bit is set. The interrupt must be
    // taken at the next fetch boundary after PUTST.
    p = place_movi_il(p, 4'd3, PRE_INT_ST);
    p = place_word(p, 16'h01A3); // PUTST A3
    // Marker that must be skipped. Its address is the resume PC that gets
    // pushed.
    marker_word = p;
    p = place_movi_il(p, 4'd6, 32'h0000_DEAD);
    p = place_word(p, 16'hC0FF);     // halt (only reached if interrupt missed)

    repeat (3) @(posedge clk);
    #1;
    rst = 1'b0;
    // Display timing is not integrated yet; emulate its one-cycle hardware
    // request. DIP latches even while disabled and survives until software
    // writes zero to INTPEND.
    @(negedge clk);
    dpyint_set = 1'b1;
    @(negedge clk);
    dpyint_set = 1'b0;
    repeat (3000) @(posedge clk);
    #1;

    // -------- Checks ----------------------------------------------------
    // PC reached the ISR via the vector → A5 = 0xBEEF.
    check_reg("INT: ISR executed (A5 = 0xBEEF)",
              u_core.u_regfile.a_regs[5], 32'h0000_BEEF);
    // Marker after EINT was skipped → A6 still 0 (not 0xDEAD).
    check_reg("INT: marker after EINT skipped (A6 = 0)",
              u_core.u_regfile.a_regs[6], 32'h0000_0000);
    // SP decremented by 64 (two 32-bit pushes).
    check_reg("INT: SP <- SP_INIT - 64",
              u_core.u_regfile.sp_q, SP_INIT - 32'd64);
    // Full live ST is initialized on entry; ISR's positive/nonzero MOVI
    // leaves the reset flags unchanged.
    check_reg("INT: live ST initialized to ST_RESET_VALUE",
              u_core.u_status_reg.st_q, ST_RESET_VALUE);

    // Pushed PC at SP-32 (words 126/127) = marker address (resume PC).
    pushed_pc = {u_mem.mem[127], u_mem.mem[126]};
    check_reg("INT: pushed PC = marker (resume) address",
              pushed_pc, 32'(marker_word) << 4);
    // Pushed ST at SP-64 (words 124/125) is the exact pre-entry word.
    pushed_st = {u_mem.mem[125], u_mem.mem[124]};
    check_reg("INT: pushed ST = exact pre-entry ST",
              pushed_st, PRE_INT_ST);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0)
      $display("TEST_RESULT: PASS (interrupt recognised; PC/ST pushed, live ST initialized, vector taken)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #500_000;
    $display("TEST_RESULT: FAIL: tb_int_entry hard timeout");
    $fatal(1);
  end

endmodule : tb_int_entry
