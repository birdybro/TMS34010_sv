// -----------------------------------------------------------------------------
// tb_reset_vector.sv
//
// Architectural reset-vector fetch (1988 TI TMS34010 User's Guide pp. 8-10
// and 8-12): after reset, read the 32-bit level-0 vector at 0xFFFF_FFE0,
// load PC from it, and begin fetching there without pushing PC or ST.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_reset_vector;
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
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
    .mem_size(mem_size), .mem_wdata(mem_wdata),
    .mem_rdata(mem_rdata), .mem_ack(mem_ack),
    .state_o(state_w), .pc_o(pc_w), .instr_word_o(instr_w),
    .illegal_opcode_o(illegal_w), .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1), .lint2_n_i(1'b1), .host_int_set_i(1'b0), .dpyint_set_i(1'b0), .refresh_req_o(), .refresh_row_o(), .refresh_cbr_o(), .video_hsync_o(), .video_vsync_o(), .video_hblank_o(), .video_vblank_o(), .video_blank_o()
  );

  sim_memory_model #(.DEPTH_WORDS(128)) u_mem (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
    .mem_size(mem_size), .mem_wdata(mem_wdata),
    .mem_rdata(mem_rdata), .mem_ack(mem_ack)
  );

  localparam logic [ADDR_WIDTH-1:0] BOOT_PC = 32'h0000_0280; // word 40
  localparam int unsigned BOOT_WORD = 40;

  int unsigned failures;
  int unsigned reset_acks;
  int unsigned fetch_acks;
  int unsigned writes_seen;
  logic        reset_request_seen;
  logic [ADDR_WIDTH-1:0] held_reset_addr;
  logic [FIELD_SIZE_WIDTH-1:0] held_reset_size;

  task automatic fail(input string message);
    $display("TEST_RESULT: FAIL: %s", message);
    failures++;
  endtask

  // Active-region monitor observes the request and acknowledge that the core
  // actually presented at each clock edge.
  always @(posedge clk) begin
    if (mem_we) writes_seen++;

    if (rst) begin
      if (mem_req) fail("mem_req asserted while rst was active");
    end else if (state_w == CORE_RESET) begin
      if (!mem_req) fail("CORE_RESET dropped mem_req before vector ack");
      if (mem_we) fail("reset-vector transaction was a write");
      if (mem_addr !== RESET_VECTOR_ADDR)
        fail($sformatf("reset address expected=%08h actual=%08h",
                       RESET_VECTOR_ADDR, mem_addr));
      if (mem_size !== MEM_SIZE_32)
        fail($sformatf("reset size expected=%0d actual=%0d",
                       MEM_SIZE_32, mem_size));
      if (pc_w !== RESET_PC)
        fail($sformatf("PC changed before vector ack: %08h", pc_w));

      if (!reset_request_seen) begin
        reset_request_seen = 1'b1;
        held_reset_addr = mem_addr;
        held_reset_size = mem_size;
      end else begin
        if (mem_addr !== held_reset_addr)
          fail("reset-vector address changed while request was pending");
        if (mem_size !== held_reset_size)
          fail("reset-vector size changed while request was pending");
      end

      if (mem_ack) reset_acks++;
    end

    if (!rst && state_w == CORE_FETCH && mem_ack) begin
      if (fetch_acks == 0) begin
        if (pc_w !== BOOT_PC)
          fail($sformatf("first fetch PC expected=%08h actual=%08h", BOOT_PC, pc_w));
        if (mem_addr !== BOOT_PC)
          fail($sformatf("first fetch address expected=%08h actual=%08h",
                         BOOT_PC, mem_addr));
      end
      fetch_acks++;
    end
  end

  initial begin : main
    failures = 0;
    reset_acks = 0;
    fetch_acks = 0;
    writes_seen = 0;
    reset_request_seen = 1'b0;
    held_reset_addr = '0;
    held_reset_size = '0;

    // Avoid time-zero ordering with the model's own initialization.
    #1;
    u_mem.level0_vector = BOOT_PC;
    // MOVK 17,A5 is flag-neutral and proves execution began at BOOT_PC.
    u_mem.mem[BOOT_WORD] = 16'h1A25;
    u_mem.mem[BOOT_WORD + 1] = 16'hC0FF;

    repeat (3) @(posedge clk);
    #1;
    if (state_w !== CORE_RESET) fail("FSM did not remain in CORE_RESET during rst");
    if (pc_w !== RESET_PC) fail("PC reset value was not RESET_PC");
    rst = 1'b0;

    // Wait until the vector-target instruction executes.
    fork
      begin
        wait (u_core.u_regfile.a_regs[5] == 32'd17);
      end
      begin
        repeat (100) @(posedge clk);
        if (u_core.u_regfile.a_regs[5] != 32'd17)
          fail("vector-target instruction did not execute");
      end
    join_any
    disable fork;
    #1;

    if (!reset_request_seen) fail("no reset-vector request was observed");
    if (reset_acks != 1)
      fail($sformatf("expected one reset-vector ack, observed %0d", reset_acks));
    if (fetch_acks == 0) fail("no instruction fetch was observed at the vector target");
    if (writes_seen != 0)
      fail($sformatf("reset/boot unexpectedly issued %0d write(s)", writes_seen));
    if (u_core.u_regfile.sp_q !== 32'h0000_0000)
      fail("SP changed during reset boot");
    if (illegal_w) fail("illegal_opcode_o was set");

    if (failures == 0)
      $display("TEST_RESULT: PASS (level-0 reset vector fetched and executed)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #100_000;
    $display("TEST_RESULT: FAIL: tb_reset_vector hard timeout");
    $fatal(1);
  end

endmodule : tb_reset_vector
