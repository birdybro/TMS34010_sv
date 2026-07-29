// -----------------------------------------------------------------------------
// tb_emu_bridge.sv
//
// Focused asynchronous-clock regression for the physical HLDA/EMUA bridge.
// It proves lossless one-shot delivery, exact Q1/Q2 EMUA phasing, phase-safe
// halt entry/exit, and independent Q3/Q4 HLDA selection.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_emu_bridge;
  import tms34010_pkg::*;

  logic            src_clk = 1'b0;
  logic            dst_clk = 1'b0;
  logic            src_rst = 1'b1;
  logic            dst_rst = 1'b1;
  logic            src_event = 1'b0;
  logic            src_halt = 1'b0;
  local_subphase_t subphase = LOCAL_PHASE_Q1A;
  logic            lclk1;
  logic            hlda_n = 1'b1;
  logic            hlda_emua_n;
  integer          errors = 0;

  always #7 src_clk = ~src_clk;
  always #2 dst_clk = ~dst_clk;

  always_ff @(posedge dst_clk) begin
    if (dst_rst)
      subphase <= LOCAL_PHASE_Q1A;
    else if (subphase == LOCAL_PHASE_Q4B)
      subphase <= LOCAL_PHASE_Q1A;
    else
      subphase <= local_subphase_t'(subphase + 3'd1);
  end

  assign lclk1 = (subphase <= LOCAL_PHASE_Q2B);

  tms34010_emu_bridge dut (
    .src_clk_i       (src_clk),
    .src_rst_i       (src_rst),
    .src_event_i     (src_event),
    .src_halt_i      (src_halt),
    .dst_clk_i       (dst_clk),
    .dst_rst_i       (dst_rst),
    .dst_subphase_i  (subphase),
    .dst_lclk1_i     (lclk1),
    .dst_hlda_n_i    (hlda_n),
    .hlda_emua_n_o   (hlda_emua_n)
  );

  task automatic check(input logic condition, input string message);
    begin
      if (!condition) begin
        $display("CHECK_FAIL: %s at t=%0t phase=%0d",
                 message, $time, subphase);
        errors = errors + 1;
      end
    end
  endtask

  task automatic wait_phase(input local_subphase_t wanted);
    begin
      @(negedge dst_clk);
      while (subphase != wanted)
        @(negedge dst_clk);
    end
  endtask

  task automatic send_event;
    begin
      @(negedge src_clk);
      src_event = 1'b1;
      @(negedge src_clk);
      src_event = 1'b0;
    end
  endtask

  task automatic check_one_emu_pulse(
    input string label,
    input logic  expect_next_q1_active
  );
    int unsigned watchdog;
    begin
      watchdog = 0;
      while (!((subphase == LOCAL_PHASE_Q1A) && !hlda_emua_n)
             && (watchdog < 200)) begin
        @(negedge dst_clk);
        watchdog++;
      end
      check(watchdog < 200, {label, " pulse timed out"});
      check(subphase == LOCAL_PHASE_Q1A,
            {label, " pulse did not start at Q1A"});
      check(!hlda_emua_n, {label, " inactive in Q1A"});
      wait_phase(LOCAL_PHASE_Q1B);
      check(!hlda_emua_n, {label, " inactive in Q1B"});
      wait_phase(LOCAL_PHASE_Q2A);
      check(!hlda_emua_n, {label, " inactive in Q2A"});
      wait_phase(LOCAL_PHASE_Q2B);
      check(!hlda_emua_n, {label, " inactive in Q2B"});
      wait_phase(LOCAL_PHASE_Q3A);
      check(hlda_emua_n, {label, " leaked into Q3"});
      wait_phase(LOCAL_PHASE_Q1A);
      check(hlda_emua_n == !expect_next_q1_active,
            {label, " next Q1 state"});
    end
  endtask

  initial begin
    repeat (4) @(posedge src_clk);
    @(negedge src_clk);
    src_rst = 1'b0;
    dst_rst = 1'b0;

    // A one-source-clock event at an arbitrary destination phase must survive
    // CDC and become exactly one complete Q1/Q2 low pulse.
    wait_phase(LOCAL_PHASE_Q2A);
    send_event();
    check_one_emu_pulse("first EMU", 1'b0);

    // Allow the four-phase acknowledge to return and prove re-arming with a
    // second event launched at a different phase.
    repeat (6) @(posedge src_clk);
    wait_phase(LOCAL_PHASE_Q3B);
    send_event();
    check_one_emu_pulse("second EMU", 1'b0);

    // A sampled-low EMU execution raises the event and halt level together.
    // The one-shot window must flow directly into repeating halt windows,
    // with no empty Q1/Q2 half even though the clock ratio is non-integer.
    repeat (6) @(posedge src_clk);
    wait_phase(LOCAL_PHASE_Q1B);
    @(negedge src_clk);
    src_event = 1'b1;
    src_halt = 1'b1;
    @(negedge src_clk);
    src_event = 1'b0;
    check_one_emu_pulse("halt entry", 1'b1);
    wait_phase(LOCAL_PHASE_Q1A);
    check(!hlda_emua_n, "halt did not repeat in the next Q1/Q2");
    wait_phase(LOCAL_PHASE_Q3A);
    check(hlda_emua_n, "halt indication leaked into Q3/Q4");

    // With HOLD acknowledged at the same time, EMUA owns Q1/Q2 and HLDA owns
    // Q3/Q4, making the shared pin continuously low without cross-coupling.
    wait_phase(LOCAL_PHASE_Q2B);
    hlda_n = 1'b0;
    wait_phase(LOCAL_PHASE_Q3A);
    check(!hlda_emua_n, "active HLDA missing in Q3");
    wait_phase(LOCAL_PHASE_Q1A);
    check(!hlda_emua_n, "halted EMUA missing in Q1 during HOLD");

    // Releasing halt mid-cycle cannot truncate the current half-cycle. After
    // synchronizer latency, the first inactive indication must still begin
    // exactly at Q1A. HLDA remains independently active in Q3/Q4.
    wait_phase(LOCAL_PHASE_Q1B);
    @(negedge src_clk);
    src_halt = 1'b0;
    begin : wait_halt_release
      int unsigned watchdog;
      watchdog = 0;
      while (!((subphase == LOCAL_PHASE_Q1A) && hlda_emua_n)
             && (watchdog < 200)) begin
        @(negedge dst_clk);
        watchdog++;
      end
      check(watchdog < 200, "halt release timed out");
      check(subphase == LOCAL_PHASE_Q1A,
            "halt release was not aligned to Q1A");
    end
    wait_phase(LOCAL_PHASE_Q3A);
    check(!hlda_emua_n, "HLDA disappeared when EMUA released");

    wait_phase(LOCAL_PHASE_Q2B);
    hlda_n = 1'b1;
    wait_phase(LOCAL_PHASE_Q3A);
    check(hlda_emua_n, "shared pin did not release inactive HLDA");

    if (errors == 0)
      $display("TEST_RESULT: PASS");
    else
      $display("TEST_RESULT: FAIL (%0d errors)", errors);
    $finish;
  end

  initial begin
    #20000;
    $display("TEST_RESULT: FAIL (timeout)");
    $finish;
  end

endmodule : tb_emu_bridge

`default_nettype wire
