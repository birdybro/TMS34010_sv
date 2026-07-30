// -----------------------------------------------------------------------------
// tb_local_bus_hold.sv
//
// Focused original-pin HOLD/HOLDA regression for User's Guide §11.4.11.
// It verifies end-Q1 HOLD sampling, quiescent grant qualification, Q3/Q4
// early HLDA, the Q2/Q3 staggered high-impedance release, symmetric resume,
// active-cycle completion, and command suppression while the bus is released.
// Task 0171 makes the active-cycle case an SRT RTM and proves HOLD cannot
// truncate the W/TR-at-RAS transfer signature.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_local_bus_hold;
  import tms34010_pkg::*;

  logic              clk8x = 1'b0;
  logic              rst = 1'b1;
  logic              cycle_req = 1'b0;
  local_cycle_kind_t cycle_kind = LOCAL_CYCLE_WORD_READ;
  logic [ADDR_WIDTH-1:0] cycle_addr = 32'h0000_0200;
  local_word_t       cycle_wdata = 16'h0000;
  local_word_t       cycle_rdata;
  logic              cycle_ack;
  logic              cycle_busy;
  logic              init_done;
  logic              hold_n = 1'b1;
  logic              hold_req;
  logic              hold_grant = 1'b0;
  logic              hlda_n;
  local_word_t       lad_o;
  logic              lad_oe;
  logic              lclk1;
  logic              lclk2;
  logic              ras_n;
  logic              lal_n;
  logic              cas_n;
  logic              we_n;
  logic              tr_qe_n;
  logic              den_n;
  logic              ddout;
  logic              ras_oe;
  logic              lal_oe;
  logic              cas_oe;
  logic              we_oe;
  logic              tr_qe_oe;
  logic              den_oe;
  logic              ddout_oe;
  local_subphase_t   subphase;

  always #1 clk8x = ~clk8x;

  tms34010_local_bus dut (
    .clk8x_i            (clk8x),
    .rst                (rst),
    .cycle_req_i        (cycle_req),
    .cycle_kind_i       (cycle_kind),
    .cycle_addr_i       (cycle_addr),
    .cycle_wdata_i      (cycle_wdata),
    .cycle_iaq_i        (1'b0),
    .cycle_srfaddr_i    (14'h0000),
    .cycle_dpytap_i     (16'h0000),
    .cycle_screen_org_i (1'b0),
    .cycle_dram_row_i   (8'h00),
    .io_rdata_i         (16'h0000),
    .cycle_rdata_o      (cycle_rdata),
    .cycle_ack_o        (cycle_ack),
    .cycle_busy_o       (cycle_busy),
    .init_done_o        (init_done),
    .hold_n_i           (hold_n),
    .hold_req_o         (hold_req),
    .hold_grant_i       (hold_grant),
    .hlda_n_o           (hlda_n),
    .lrdy_i             (1'b1),
    .lad_i              (16'hCAFE),
    .lad_o              (lad_o),
    .lad_oe_o           (lad_oe),
    .lclk1_o            (lclk1),
    .lclk2_o            (lclk2),
    .ras_n_o            (ras_n),
    .lal_n_o            (lal_n),
    .cas_n_o            (cas_n),
    .we_n_o             (we_n),
    .tr_qe_n_o          (tr_qe_n),
    .den_n_o            (den_n),
    .ddout_o            (ddout),
    .ras_oe_o           (ras_oe),
    .lal_oe_o           (lal_oe),
    .cas_oe_o           (cas_oe),
    .we_oe_o            (we_oe),
    .tr_qe_oe_o         (tr_qe_oe),
    .den_oe_o           (den_oe),
    .ddout_oe_o         (ddout_oe),
    .subphase_o         (subphase)
  );

  int unsigned failures;

  task automatic check(input logic condition, input string message);
    begin
      if (!condition) begin
        $display("TEST_RESULT: FAIL: %s at t=%0t phase=%0d",
                 message, $time, subphase);
        failures++;
      end
    end
  endtask

  task automatic wait_phase(input local_subphase_t wanted);
    begin
      @(negedge clk8x);
      while (subphase != wanted)
        @(negedge clk8x);
    end
  endtask

  task automatic check_majority_oe(
    input logic expected,
    input string label
  );
    begin
      check(ras_oe == expected, {label, " RAS OE"});
      check(lal_oe == expected, {label, " LAL OE"});
      check(cas_oe == expected, {label, " CAS OE"});
      check(we_oe == expected, {label, " W OE"});
      check(tr_qe_oe == expected, {label, " TR/QE OE"});
      if (!expected)
        check(!lad_oe, {label, " LAD OE"});
    end
  endtask

  task automatic check_slow_oe(
    input logic expected,
    input string label
  );
    begin
      check(den_oe == expected, {label, " DEN OE"});
      check(ddout_oe == expected, {label, " DDOUT OE"});
    end
  endtask

  task automatic release_and_resume;
    begin
      // Deassert before the end-Q1 sample. HLDA becomes inactive in the
      // immediately following Q3/Q4, but all bus outputs stay released.
      wait_phase(LOCAL_PHASE_Q1A);
      hold_n = 1'b1;
      wait_phase(LOCAL_PHASE_Q2A);
      check(!hold_req, "released HOLD was not sampled at end Q1");
      check(hlda_n, "HLDA must be inactive during Q2");
      check_majority_oe(1'b0, "release-sample Q2");
      check_slow_oe(1'b0, "release-sample Q2");
      wait_phase(LOCAL_PHASE_Q3A);
      check(hlda_n, "HLDA must be inactive in release Q3/Q4");
      check_majority_oe(1'b0, "release-sample Q3");
      check_slow_oe(1'b0, "release-sample Q3");

      // The following Q2 reacquires LAD/majority controls. DEN/DDOUT wait
      // one more quarter and resume at Q3.
      wait_phase(LOCAL_PHASE_Q2A);
      check_majority_oe(1'b1, "resume Q2");
      check_slow_oe(1'b0, "resume Q2");
      wait_phase(LOCAL_PHASE_Q3A);
      check_majority_oe(1'b1, "resume Q3");
      check_slow_oe(1'b1, "resume Q3");
      check(hlda_n, "HLDA remained active after resume");
    end
  endtask

  initial begin : main
    logic saw_rtm_ras;

    failures = 0;
    saw_rtm_ras = 1'b0;

    repeat (4) @(posedge clk8x);
    @(negedge clk8x);
    rst = 1'b0;
    wait (init_done);
    wait_phase(LOCAL_PHASE_Q1A);

    // Sampling HOLD without a quiescent core grant must not acknowledge or
    // release any bus output.
    hold_n = 1'b0;
    wait_phase(LOCAL_PHASE_Q2A);
    check(hold_req, "active-low HOLD was not sampled at end Q1");
    check(hlda_n, "HLDA asserted before the core grant");
    check_majority_oe(1'b1, "ungranted HOLD");
    check_slow_oe(1'b1, "ungranted HOLD");
    wait_phase(LOCAL_PHASE_Q3A);
    check(hlda_n, "ungranted HOLD asserted during Q3");

    // Supply the quiescent grant before another sample. The first Q3/Q4
    // pulse is the early acknowledge; outputs remain driven until next Q2.
    wait_phase(LOCAL_PHASE_Q1A);
    hold_grant = 1'b1;
    wait_phase(LOCAL_PHASE_Q2A);
    check(hlda_n, "HLDA must be inactive in Q1/Q2");
    check_majority_oe(1'b1, "early-ack Q2");
    check_slow_oe(1'b1, "early-ack Q2");
    wait_phase(LOCAL_PHASE_Q3A);
    check(!hlda_n, "early HLDA missing in Q3");
    check_majority_oe(1'b1, "early-ack Q3");
    check_slow_oe(1'b1, "early-ack Q3");
    wait_phase(LOCAL_PHASE_Q1A);
    check(hlda_n, "HLDA leaked into Q1/Q2");

    wait_phase(LOCAL_PHASE_Q2A);
    check_majority_oe(1'b0, "release Q2");
    check_slow_oe(1'b1, "release Q2");
    wait_phase(LOCAL_PHASE_Q3A);
    check(!hlda_n, "held HLDA missing in Q3");
    check_majority_oe(1'b0, "release Q3");
    check_slow_oe(1'b0, "release Q3");

    // A command offered during HOLD remains pending and cannot drive pins.
    cycle_req = 1'b1;
    repeat (8) begin
      @(negedge clk8x);
      check(!lad_oe, "pending held command drove LAD");
      check_majority_oe(1'b0, "held pending command");
      check_slow_oe(1'b0, "held pending command");
      check(!cycle_ack, "pending held command acknowledged");
    end

    cycle_req = 1'b0;
    release_and_resume();
    hold_grant = 1'b0;

    // Start an SRT register-to-memory transfer, then assert HOLD with grant
    // already high.
    // Local-cycle completion must occur before even the early HLDA pulse.
    wait_phase(LOCAL_PHASE_Q4A);
    cycle_kind = LOCAL_CYCLE_PIXEL_RTM;
    cycle_req  = 1'b1;
    hold_grant = 1'b1;
    wait_phase(LOCAL_PHASE_Q1A);
    hold_n = 1'b0;
    wait_phase(LOCAL_PHASE_Q2A);
    check(hold_req, "active-cycle HOLD was not sampled");
    check(hlda_n, "active cycle received premature HLDA");

    while (!cycle_ack) begin
      @(negedge clk8x);
      check(hlda_n, "HLDA asserted before active-cycle completion");
      if (!ras_n && !tr_qe_n && !we_n)
        saw_rtm_ras = 1'b1;
    end
    check(saw_rtm_ras,
          "active SRT RTM did not reach its W/TR-at-RAS transfer point");
    cycle_req = 1'b0;

    // Once idle, the next qualified sample starts the early acknowledge.
    wait_phase(LOCAL_PHASE_Q3A);
    check(!hlda_n, "post-cycle early HLDA missing");
    check_majority_oe(1'b1, "post-cycle early HLDA");
    check_slow_oe(1'b1, "post-cycle early HLDA");
    wait_phase(LOCAL_PHASE_Q2A);
    check_majority_oe(1'b0, "post-cycle release Q2");
    check_slow_oe(1'b1, "post-cycle release Q2");
    wait_phase(LOCAL_PHASE_Q3A);
    check_majority_oe(1'b0, "post-cycle release Q3");
    check_slow_oe(1'b0, "post-cycle release Q3");

    release_and_resume();
    hold_grant = 1'b0;

    if (failures == 0)
      $display("TEST_RESULT: PASS");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #200_000;
    $display("TEST_RESULT: FAIL: tb_local_bus_hold hard timeout");
    $fatal(1);
  end

endmodule : tb_local_bus_hold

`default_nettype wire
