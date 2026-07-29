// -----------------------------------------------------------------------------
// tb_smoke.sv
//
// Phase 0 smoke test for tms34010_core.
//
// What it verifies:
//   1. The core elaborates cleanly with the current package.
//   2. After reset deasserts and the level-0 vector read is acknowledged, the
//      FSM transitions from CORE_RESET to CORE_FETCH.
//
// What it does NOT verify:
//   - Any instruction behavior.
//   - Detailed memory-interface protocol (covered by tb_reset_vector).
//   - Any timing relationships.
//
// Pass/fail convention:
//   Prints "TEST_RESULT: PASS" on success, "TEST_RESULT: FAIL: <reason>" on
//   failure. scripts/sim.sh greps for the PASS line to set its exit code.
//
// Not synthesizable — uses initial blocks, $display, $finish, $fatal.
// That is correct for a testbench; tb files live under sim/tb/, not rtl/.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_smoke;
  import tms34010_pkg::*;

  // ---------------------------------------------------------------------------
  // Clock and reset
  // ---------------------------------------------------------------------------
  logic clk = 1'b0;
  logic rst = 1'b1;

  // 100 MHz nominal in simulation.
  always #5 clk = ~clk;

  // ---------------------------------------------------------------------------
  // DUT wiring
  // ---------------------------------------------------------------------------
  logic                              mem_req;
  logic                              mem_we;
  logic [ADDR_WIDTH-1:0]             mem_addr;
  logic [FIELD_SIZE_WIDTH-1:0]       mem_size;
  logic [DATA_WIDTH-1:0]             mem_wdata;
  logic [DATA_WIDTH-1:0]             mem_rdata;
  logic                              mem_ack;
  core_state_t                       state_w;
  logic [ADDR_WIDTH-1:0]             pc_w;
  instr_word_t                       instr_w;
  logic                              illegal_w;

  tms34010_core dut (
    .clk      (clk),
    .rst      (rst),
    .mem_req  (mem_req),
    .mem_we   (mem_we),
    .mem_addr (mem_addr),
    .mem_size (mem_size),
    .mem_wdata(mem_wdata),
    .mem_rdata       (mem_rdata),
    .mem_ack         (mem_ack),
    .state_o         (state_w),
    .pc_o            (pc_w),
    .instr_word_o    (instr_w),
    .illegal_opcode_o(illegal_w), .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1), .lint2_n_i(1'b1), .host_int_set_i(1'b0), .dpyint_set_i(1'b0), .refresh_req_o(), .refresh_row_o(), .refresh_cbr_o(), .video_hsync_o(), .video_vsync_o(), .video_hblank_o(), .video_vblank_o(), .video_blank_o(), .screen_refresh_req_o(), .screen_refresh_ack_i(1'b0), .screen_refresh_srfaddr_o(), .screen_refresh_dpytap_o()
  );

  // The model's default level-0 vector is zero, so the first instruction
  // fetch begins at word 0 after the architectural reset transaction.
  sim_memory_model #(.DEPTH_WORDS(16)) u_mem (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
    .mem_size(mem_size), .mem_wdata(mem_wdata),
    .mem_rdata(mem_rdata), .mem_ack(mem_ack)
  );

  // ---------------------------------------------------------------------------
  // Test body
  // ---------------------------------------------------------------------------
  int unsigned cycles_after_release;
  bit          reached_fetch;

  initial begin : main
    cycles_after_release = 0;
    reached_fetch        = 1'b0;

    // Hold reset for a few cycles.
    repeat (3) @(posedge clk);
    if (state_w !== CORE_RESET) begin
      $display("TEST_RESULT: FAIL: state was %s during reset, expected CORE_RESET",
               state_w.name());
      $finish;
    end

    // Release reset on a clock edge so the next sampled state reflects the
    // post-reset transition.
    #1;
    rst = 1'b0;

    // Watch up to 12 cycles for the level-0 vector transaction to complete.
    for (int i = 0; i < 12; i++) begin
      @(posedge clk);
      #1;
      cycles_after_release++;
      if (state_w == CORE_FETCH) begin
        reached_fetch = 1'b1;
        break;
      end
    end

    // Independent check: in CORE_FETCH the skeleton must assert mem_req.
    if (reached_fetch && (mem_req !== 1'b1)) begin
      $display("TEST_RESULT: FAIL: in CORE_FETCH but mem_req not asserted (req=%0b)",
               mem_req);
      $finish;
    end

    // mem_addr in CORE_FETCH should match the PC.
    if (reached_fetch && (mem_addr !== pc_w)) begin
      $display("TEST_RESULT: FAIL: mem_addr=%08h does not match pc=%08h in CORE_FETCH",
               mem_addr, pc_w);
      $finish;
    end

    if (reached_fetch) begin
      $display("TEST_RESULT: PASS (reached CORE_FETCH after %0d cycle(s); mem_req=%0b, mem_size=%0d, pc=%08h)",
               cycles_after_release, mem_req, mem_size, pc_w);
    end else begin
      $display("TEST_RESULT: FAIL: stuck in %s after %0d cycle(s) post-reset",
               state_w.name(), cycles_after_release);
    end

    $finish;
  end

  // Hard timeout watchdog.
  initial begin : watchdog
    #10_000;
    $display("TEST_RESULT: FAIL: hard timeout at 10us simulated");
    $fatal(1);
  end

endmodule : tb_smoke
