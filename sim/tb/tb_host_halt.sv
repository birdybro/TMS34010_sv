// -----------------------------------------------------------------------------
// tb_host_halt.sv
//
// Core-level host halt regression for the 1988 User's Guide pages 6-35,
// 8-10 through 8-13, and 10-18 through 10-20:
//   - HCS high at reset defers the level-0 vector fetch until HLT is cleared.
//   - A run-time HLT waits for the current instruction to finish.
//   - No memory or interrupt work occurs while halted; video and DRAM refresh
//     state continue clocking.
//   - NMI held pending during a halt is taken after resume.
//   - Simultaneous NMI+HLT completes NMI entry, then halts before the first
//     service-routine instruction.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_host_halt;
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
  logic                          hcs_n;
  logic                          host_req;
  logic                          host_we;
  host_reg_sel_t                 host_reg;
  logic [1:0]                    host_be;
  logic [15:0]                   host_wdata;
  logic [15:0]                   host_rdata;
  logic                          host_ack;
  logic                          hint_n;
  logic                          refresh_req;
  logic                          refresh_cbr;

  localparam logic [DATA_WIDTH-1:0] BOOT_PC = 32'h0000_0280;
  localparam logic [DATA_WIDTH-1:0] NMI_PC  = 32'h0000_0640;
  localparam int unsigned BOOT_WORD = 40;
  localparam int unsigned NMI_WORD  = 100;
  localparam int unsigned NMI_VEC_LO = 1006;
  localparam int unsigned NMI_VEC_HI = 1007;
  localparam logic [ADDR_WIDTH-1:0] A_HTOTAL =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_HTOTAL) << 4);
  localparam logic [15:0] HLT_MASK =
      16'h0001 << HSTCTL_HLT_BIT;
  localparam logic [15:0] NMI_NMIM_MASK =
      (16'h0001 << HSTCTL_NMI_BIT)
    | (16'h0001 << HSTCTL_NMIM_BIT);

  tms34010_core u_core (
    .clk             (clk), .vclk_i(clk),
    .rst             (rst),
    .mem_req         (mem_req),
    .mem_we          (mem_we),
    .mem_addr        (mem_addr),
    .mem_size        (mem_size),
    .mem_wdata       (mem_wdata),
    .mem_rdata       (mem_rdata),
    .mem_ack         (mem_ack),
    .run_emu_n_i     (1'b1),
    .emua_n_o        (),
    .hcs_n_i         (hcs_n),
    .host_req_i      (host_req),
    .host_we_i       (host_we),
    .host_reg_i      (host_reg),
    .host_be_i       (host_be),
    .host_wdata_i    (host_wdata),
    .host_rdata_o    (host_rdata),
    .host_ack_o      (host_ack),
    .host_busy_o     (),
    .hint_n_o        (hint_n),
    .host_mem_req_o  (),
    .host_mem_we_o   (),
    .host_mem_addr_o (),
    .host_mem_wdata_o(),
    .host_mem_rdata_i(16'h0000),
    .host_mem_ack_i  (1'b0),
    .lint1_n_i       (1'b1),
    .lint2_n_i       (1'b1),
    .dpyint_set_i    (1'b0),
    .refresh_req_o   (refresh_req),
    .refresh_row_o   (),
    .refresh_cbr_o   (refresh_cbr),
    .video_hsync_o   (),
    .video_vsync_o   (),
    .video_hblank_o  (),
    .video_vblank_o  (),
    .video_blank_o   (),
    .screen_refresh_req_o(),
    .screen_refresh_ack_i(1'b0),
    .screen_refresh_srfaddr_o(),
    .screen_refresh_dpytap_o(),
    .state_o         (state_w),
    .pc_o            (pc_w),
    .instr_word_o    (instr_w),
    .illegal_opcode_o(illegal_w)
  );

  sim_memory_model #(.DEPTH_WORDS(1024)) u_mem (
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

  function automatic instr_word_t movi_il_enc(input reg_idx_t idx);
    movi_il_enc = 16'h09E0 | instr_word_t'(idx);
  endfunction

  function automatic instr_word_t addk_enc(input logic [4:0] k,
                                           input reg_idx_t rd);
    addk_enc = 16'h1000
             | (instr_word_t'(k) << 5)
             | instr_word_t'(rd);
  endfunction

  function automatic int unsigned place_movi_il(
    input int unsigned p,
    input reg_idx_t    idx,
    input logic [DATA_WIDTH-1:0] immediate
  );
    u_mem.mem[p]     = movi_il_enc(idx);
    u_mem.mem[p + 1] = immediate[15:0];
    u_mem.mem[p + 2] = immediate[31:16];
    place_movi_il = p + 3;
  endfunction

  function automatic int unsigned place_store_abs(
    input int unsigned p,
    input reg_idx_t    source,
    input logic [ADDR_WIDTH-1:0] store_addr
  );
    u_mem.mem[p]     = 16'h0580 | instr_word_t'(source);
    u_mem.mem[p + 1] = store_addr[15:0];
    u_mem.mem[p + 2] = store_addr[31:16];
    place_store_abs = p + 3;
  endfunction

  int unsigned failures;
  int unsigned reset_vector_requests;
  int unsigned refresh_while_halted;
  int unsigned video_steps_while_halted;
  logic [15:0] previous_hcount;

  task automatic host_cycle(
    input logic        write_access,
    input logic [15:0] write_data
  );
    begin
      @(negedge clk);
      host_req   = 1'b1;
      host_we    = write_access;
      host_reg   = HOST_REG_HSTCTL;
      host_be    = 2'b10;
      host_wdata = write_data;
      while (!host_ack) begin
        @(posedge clk);
        #1;
      end
      @(negedge clk);
      host_req = 1'b0;
      host_we  = 1'b0;
      host_be  = 2'b00;
      @(posedge clk);
      #1;
    end
  endtask

  task automatic host_high_write(input logic [15:0] write_data);
    host_cycle(1'b1, write_data);
  endtask

  task automatic host_ctl_read;
    host_cycle(1'b0, 16'h0000);
  endtask

  task automatic check_word(
    input string                  label,
    input logic [DATA_WIDTH-1:0] actual,
    input logic [DATA_WIDTH-1:0] expected
  );
    begin
      if (actual !== expected) begin
        $display("TEST_RESULT: FAIL: %s expected=%08h actual=%08h",
                 label, expected, actual);
        failures++;
      end
    end
  endtask

  task automatic check_bit(
    input string label,
    input logic  actual,
    input logic  expected
  );
    begin
      if (actual !== expected) begin
        $display("TEST_RESULT: FAIL: %s expected=%0b actual=%0b",
                 label, expected, actual);
        failures++;
      end
    end
  endtask

  always @(posedge clk) begin
    if (!rst && mem_req && mem_addr == RESET_VECTOR_ADDR)
      reset_vector_requests++;

    if (!rst && (state_w == CORE_RESET_HALT
                 || state_w == CORE_HOST_HALT)) begin
      if (refresh_req)
        refresh_while_halted++;
      if (u_core.u_io_regs.hcount_o != previous_hcount)
        video_steps_while_halted++;
      previous_hcount <= u_core.u_io_regs.hcount_o;
    end else begin
      previous_hcount <= u_core.u_io_regs.hcount_o;
    end
  end

  initial begin : main
    int unsigned p;
    int unsigned i;
    logic [ADDR_WIDTH-1:0] halted_pc;

    failures               = 0;
    reset_vector_requests  = 0;
    refresh_while_halted   = 0;
    video_steps_while_halted = 0;
    previous_hcount        = 16'h0000;
    hcs_n                  = 1'b1;
    host_req               = 1'b0;
    host_we                = 1'b0;
    host_reg               = HOST_REG_HSTCTL;
    host_be                = 2'b00;
    host_wdata             = 16'h0000;

    for (i = 0; i < 1024; i++)
      u_mem.mem[i] = 16'h0300;

    u_mem.level0_vector = BOOT_PC;
    u_mem.mem[NMI_VEC_LO] = NMI_PC[15:0];
    u_mem.mem[NMI_VEC_HI] = NMI_PC[31:16];

    // Boot program: make HCOUNT visibly advance, then execute a long MOVI
    // during which the host requests a run-time halt.
    p = BOOT_WORD;
    p = place_movi_il(p, 4'd0, 32'd7);
    p = place_store_abs(p, 4'd0, A_HTOTAL);
    p = place_movi_il(p, 4'd2, 32'h1234_5678);
    u_mem.mem[p] = 16'hC0FF;

    // NMI service routine increments A5 exactly once per entry, then runs a
    // one-word loop. This distinguishes entry completion from instruction
    // execution when NMI and HLT arrive together.
    u_mem.mem[NMI_WORD]     = addk_enc(5'd1, 4'd5);
    u_mem.mem[NMI_WORD + 1] = 16'hC0FF;

    repeat (3) @(posedge clk);
    rst = 1'b0;

    wait (state_w == CORE_RESET_HALT);
    host_ctl_read();
    #1;
    check_word("host-present reset PC held", pc_w, RESET_PC);
    check_bit("host-present reset memory quiescent", mem_req, 1'b0);
    check_bit("host-present reset HLT visible",
              host_rdata[HSTCTL_HLT_BIT], 1'b1);
    repeat (40) begin
      @(posedge clk);
      #1;
      check_bit("reset halt state held", state_w == CORE_RESET_HALT, 1'b1);
      check_bit("reset halt memory quiescent", mem_req, 1'b0);
    end
    if (reset_vector_requests != 0) begin
      $display("TEST_RESULT: FAIL: reset vector requested %0d time(s) before HLT clear",
               reset_vector_requests);
      failures++;
    end
    if (refresh_while_halted == 0) begin
      $display("TEST_RESULT: FAIL: no DRAM-refresh event during reset halt");
      failures++;
    end

    // Clearing the reset HLT starts the vector fetch and reset routine.
    host_high_write(16'h0000);
    wait (state_w == CORE_FETCH_IMM_HI && pc_w >= BOOT_PC + 32'd128);
    host_high_write(HLT_MASK);
    wait (state_w == CORE_HOST_HALT);
    host_ctl_read();
    #1;
    halted_pc = pc_w;
    check_word("current long instruction completed before halt",
               u_core.u_regfile.a_regs[2], 32'h1234_5678);
    check_bit("run-time halt memory quiescent", mem_req, 1'b0);
    check_bit("run-time HLT visible",
              host_rdata[HSTCTL_HLT_BIT], 1'b1);

    // NMI asserted while already halted remains pending and performs no entry.
    host_high_write(HLT_MASK | NMI_NMIM_MASK);
    repeat (20) begin
      @(posedge clk);
      #1;
      check_bit("pending-NMI halt held", state_w == CORE_HOST_HALT, 1'b1);
      check_word("pending-NMI halt PC held", pc_w, halted_pc);
      check_bit("pending-NMI halt memory quiescent", mem_req, 1'b0);
      check_word("pending NMI did not execute handler",
                 u_core.u_regfile.a_regs[5], 32'h0000_0000);
    end

    // Clear only HLT. The retained NMI request is then serviced.
    host_high_write(NMI_NMIM_MASK);
    wait (u_core.u_regfile.a_regs[5] == 32'h0000_0001);
    host_ctl_read();
    #1;
    check_bit("resumed NMI auto-cleared",
              host_rdata[HSTCTL_NMI_BIT], 1'b0);

    // With the core running in the handler loop, assert NMI and HLT together.
    // NMI entry must complete first, then HLT stops before the first handler
    // instruction can increment A5 a second time.
    wait (state_w == CORE_EXECUTE);
    host_high_write(HLT_MASK | NMI_NMIM_MASK);
    wait (state_w == CORE_HOST_HALT);
    host_ctl_read();
    #1;
    check_word("simultaneous NMI+HLT entered before handler instruction",
               u_core.u_regfile.a_regs[5], 32'h0000_0001);
    check_word("simultaneous NMI+HLT service PC", pc_w, NMI_PC);
    check_bit("simultaneous NMI auto-cleared",
              host_rdata[HSTCTL_NMI_BIT], 1'b0);
    check_bit("simultaneous HLT retained",
              host_rdata[HSTCTL_HLT_BIT], 1'b1);

    repeat (20) @(posedge clk);
    if (video_steps_while_halted == 0) begin
      $display("TEST_RESULT: FAIL: video HCOUNT did not advance while halted");
      failures++;
    end
    if (refresh_while_halted < 2) begin
      $display("TEST_RESULT: FAIL: insufficient refresh activity while halted (%0d)",
               refresh_while_halted);
      failures++;
    end

    host_high_write(16'h0000);
    wait (u_core.u_regfile.a_regs[5] == 32'h0000_0002);
    host_ctl_read();
    #1;
    check_bit("final HLT clear visible",
              host_rdata[HSTCTL_HLT_BIT], 1'b0);
    check_bit("HINT remains inactive", hint_n, 1'b1);
    check_bit("no illegal opcode", illegal_w, 1'b0);
    check_bit("refresh mode remains RAS-only", refresh_cbr, 1'b0);
    if (reset_vector_requests == 0) begin
      $display("TEST_RESULT: FAIL: no reset-vector request after HLT clear");
      failures++;
    end

    if (failures == 0)
      $display("TEST_RESULT: PASS (HCS reset halt, boundary HLT, refresh/video continuation, pending/simultaneous NMI)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_host_halt hard timeout");
    $fatal(1);
  end

endmodule : tb_host_halt
