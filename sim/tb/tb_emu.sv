// -----------------------------------------------------------------------------
// tb_emu.sv
//
// End-to-end test for EMU (0x0100).
//
// The pin-level TMS34010 pulses active-low EMUA while sampling RUN/EMU. The
// abstract single-clock core exposes the same handshake as run_emu_n_i and
// emua_n_o:
//   - RUN high: EMU behaves as a NOP and EMUA is low for the execute cycle.
//   - EMU low:  EMU enters a quiescent halt with EMUA held low.
//   - Returning RUN high resumes at the instruction following EMU.
//
// Spec: 1988 TI TMS34010 User's Guide pages 12-77 and 2-10.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_emu;
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
  logic                          run_emu_n_i = 1'b1;
  logic                          emua_n_o;

  tms34010_core u_core (
    .clk             (clk),
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
    .illegal_opcode_o(illegal_w),
    .run_emu_n_i     (run_emu_n_i),
    .emua_n_o        (emua_n_o), .lint1_n_i(1'b1), .lint2_n_i(1'b1), .host_int_set_i(1'b0), .dpyint_set_i(1'b0), .refresh_req_o(), .refresh_row_o(), .refresh_cbr_o(), .video_hsync_o(), .video_vsync_o(), .video_hblank_o(), .video_vblank_o(), .video_blank_o(), .screen_refresh_req_o(), .screen_refresh_ack_i(1'b0), .screen_refresh_srfaddr_o(), .screen_refresh_dpytap_o()
  );

  sim_memory_model #(.DEPTH_WORDS(64)) u_mem (
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

  function automatic instr_word_t movi_il_enc(input reg_file_t rf,
                                              input reg_idx_t  idx);
    movi_il_enc = 16'h09E0
                | (instr_word_t'(rf) << 4)
                | instr_word_t'(idx);
  endfunction

  int unsigned failures;
  int unsigned run_ack_cycles;

  task automatic check_bit(input string label,
                           input logic  actual,
                           input logic  expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%0b actual=%0b",
               label, expected, actual);
      failures++;
    end
  endtask

  task automatic check_word(input string label,
                            input logic [DATA_WIDTH-1:0] actual,
                            input logic [DATA_WIDTH-1:0] expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%08h actual=%08h",
               label, expected, actual);
      failures++;
    end
  endtask

  // Count only the execute-cycle acknowledge for EMU in RUN state. EMUA
  // remains low throughout a requested halt, which is checked separately.
  always @(posedge clk) begin
    if (!rst && state_w == CORE_EXECUTE && instr_w == 16'h0100
        && run_emu_n_i && !emua_n_o) begin
      run_ack_cycles <= run_ack_cycles + 1;
    end
  end

  initial begin : main
    logic [DATA_WIDTH-1:0] st_before_halt;
    int unsigned i;

    failures      = 0;
    run_ack_cycles = 0;

    for (i = 0; i < 64; i++) begin
      u_mem.mem[i] = 16'h0300; // NOP
    end

    // First EMU runs as a NOP. The second samples EMU low and halts before
    // the A2 write, then resumes at that instruction when RUN returns high.
    u_mem.mem[0] = 16'h0100; // EMU in RUN state
    u_mem.mem[1] = movi_il_enc(REG_FILE_A, 4'd1);
    u_mem.mem[2] = 16'h2222;
    u_mem.mem[3] = 16'h1111;
    u_mem.mem[4] = 16'h0300; // time for the bench to select EMU
    u_mem.mem[5] = 16'h0100; // EMU in EMU state
    u_mem.mem[6] = movi_il_enc(REG_FILE_A, 4'd2);
    u_mem.mem[7] = 16'h4444;
    u_mem.mem[8] = 16'h3333;

    repeat (3) @(posedge clk);
    rst = 1'b0;

    wait (u_core.u_regfile.a_regs[1] == 32'h1111_2222);
    #1;
    check_bit("RUN-state EMU returned EMUA high", emua_n_o, 1'b1);
    st_before_halt = u_core.st_value;
    run_emu_n_i = 1'b0;

    wait (state_w == CORE_EMU_HALT);
    #1;
    check_word("halt resume PC", pc_w, 32'd96);
    check_bit("EMUA active during halt", emua_n_o, 1'b0);
    check_bit("no memory request on halt entry", mem_req, 1'b0);
    check_word("post-EMU A2 not executed", u_core.u_regfile.a_regs[2], 32'h0);
    check_word("ST unchanged on EMU entry", u_core.st_value, st_before_halt);

    repeat (10) begin
      @(posedge clk);
      #1;
      check_bit("halt state held", state_w == CORE_EMU_HALT, 1'b1);
      check_word("PC held while halted", pc_w, 32'd96);
      check_bit("memory quiescent while halted", mem_req, 1'b0);
      check_word("A2 held while halted", u_core.u_regfile.a_regs[2], 32'h0);
      check_word("ST held while halted", u_core.st_value, st_before_halt);
    end

    run_emu_n_i = 1'b1;
    @(posedge clk);
    #1;
    check_bit("RUN exits halt", state_w == CORE_FETCH, 1'b1);
    check_bit("EMUA inactive after resume", emua_n_o, 1'b1);

    wait (u_core.u_regfile.a_regs[2] == 32'h3333_4444);
    #1;
    check_word("execution resumed after EMU", u_core.u_regfile.a_regs[2],
               32'h3333_4444);
    check_word("EMU preserved ST", u_core.st_value, st_before_halt);
    check_bit("EMU recognized as legal", illegal_w, 1'b0);
    if (run_ack_cycles != 1) begin
      $display("TEST_RESULT: FAIL: RUN EMUA pulse cycles expected=1 actual=%0d",
               run_ack_cycles);
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (EMU pulse, halt, quiescence, and resume verified)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #200_000;
    $display("TEST_RESULT: FAIL: tb_emu hard timeout");
    $fatal(1);
  end

endmodule : tb_emu
