// -----------------------------------------------------------------------------
// tb_display_matrix.sv
//
// Generated primary-spec matrix for the TMS34010 display-address controller.
// It covers every defined DUDATE value, LCSTRT cadence, SRE state, ORG pin
// representation, NIL mode, and stored field phase. The reference model keeps
// the architecturally visible DPYADR value in its raw representation: SRFADR
// always decrements, while ORG=0 makes that an effective increment by
// complementing the value at the local-bus pins.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_display_matrix;
  import tms34010_pkg::*;

  logic clk = 1'b0;
  logic rst;
  always #5 clk = ~clk;

  logic        hblank_start;
  logic [15:0] vcount;
  logic        odd_field;
  logic [15:0] veblnk;
  logic [15:0] vsblnk;
  logic [15:0] dpystart;
  logic [15:0] dpyctl;
  logic [15:0] dpytap;
  logic        dpyadr_load;
  logic [15:0] dpyadr_wdata;
  logic [15:0] dpyadr;
  logic        refresh_req;
  logic        refresh_ack;
  logic [13:0] refresh_srfaddr;
  logic [15:0] refresh_dpytap;
  logic        refresh_org;

  int unsigned failures;
  int unsigned cases_run;
  int unsigned requests_checked;

  tms34010_display_addr u_dut (
    .clk             (clk),
    .rst             (rst),
    .hblank_start    (hblank_start),
    .vcount          (vcount),
    .odd_field       (odd_field),
    .veblnk          (veblnk),
    .vsblnk          (vsblnk),
    .dpystart        (dpystart),
    .dpyctl          (dpyctl),
    .dpytap          (dpytap),
    .dpyadr_load     (dpyadr_load),
    .dpyadr_wdata    (dpyadr_wdata),
    .dpyadr          (dpyadr),
    .refresh_req     (refresh_req),
    .refresh_ack     (refresh_ack),
    .refresh_srfaddr (refresh_srfaddr),
    .refresh_dpytap  (refresh_dpytap),
    .refresh_org     (refresh_org)
  );

  task automatic check(input logic condition, input string message);
    begin
      if (!condition) begin
        $display("CHECK_FAIL: %s case=%0d DPYADR=%04h ctl=%04h",
                 message, cases_run, dpyadr, dpyctl);
        failures++;
      end
    end
  endtask

  task automatic reset_case;
    begin
      @(negedge clk);
      rst = 1'b1;
      hblank_start = 1'b0;
      refresh_ack = 1'b0;
      dpyadr_load = 1'b0;
      @(negedge clk);
      check(dpyadr == 16'h0000, "reset DPYADR");
      check(!refresh_req, "reset request");
      rst = 1'b0;
    end
  endtask

  task automatic pulse_hblank(input logic [15:0] line);
    begin
      @(negedge clk);
      vcount = line;
      hblank_start = 1'b1;
      @(negedge clk);
      hblank_start = 1'b0;
    end
  endtask

  task automatic pulse_ack;
    begin
      @(negedge clk);
      refresh_ack = 1'b1;
      @(negedge clk);
      refresh_ack = 1'b0;
    end
  endtask

  task automatic load_dpyadr(input logic [15:0] value);
    begin
      @(negedge clk);
      dpyadr_wdata = value;
      dpyadr_load = 1'b1;
      @(negedge clk);
      dpyadr_load = 1'b0;
    end
  endtask

  task automatic run_case(
    input logic        noninterlaced,
    input logic        field_odd,
    input logic        org,
    input logic        sre,
    input logic [1:0]  lcstrt,
    input logic [7:0]  dudate
  );
    logic [13:0] start_raw;
    logic [13:0] frame_raw;
    logic [13:0] after_first;
    logic [13:0] after_second;
    logic [15:0] active_line;
    logic [1:0]  remaining_count;
    begin
      cases_run++;
      start_raw = 14'h2800 + {7'h00, cases_run[6:0]};
      frame_raw = (!noninterlaced && field_odd)
          ? start_raw - {7'h00, dudate[7:1]}
          : start_raw;
      after_first = frame_raw - {6'h00, dudate};
      after_second = after_first - {6'h00, dudate};

      odd_field = field_odd;
      dpystart = {start_raw, lcstrt};
      dpyctl = (16'(dudate) << DPYCTL_DUDATE_LO)
             | (16'(org) << DPYCTL_ORG_BIT)
             | (16'(sre) << DPYCTL_SRE_BIT)
             | (16'(noninterlaced) << DPYCTL_NIL_BIT)
             | (16'h0001 << DPYCTL_DXV_BIT);
      dpytap = 16'hE5A7;
      reset_case();
      load_dpyadr({14'h3A00, 2'b11});

      // The last active-line HBLANK reloads only SRFADR. In interlace the
      // blank in the stored odd field precedes the even field.
      pulse_hblank(vsblnk);
      check(dpyadr == {frame_raw, 2'b11}, "frame SRFADR reload");
      check(!refresh_req, "vertical blank request suppression");

      // The HBLANK preceding the first active line always reloads LNCNT and
      // schedules the first transfer only when SRE is active.
      pulse_hblank(veblnk);
      check(dpyadr == {frame_raw, lcstrt}, "first-active LCSTRT load");
      check(refresh_req == sre, "first-active SRE decision");

      if (sre) begin
        requests_checked++;
        check(refresh_srfaddr == frame_raw, "first request raw SRFADR");
        check(refresh_dpytap == 16'h25A7, "first request DPYTAP mask");
        check(refresh_org == org, "first request ORG capture");
        pulse_ack();
        check(dpyadr == {after_first, lcstrt},
              "completion raw DUDATE decrement");

        // LCSTRT=N means N nonrequesting active-line HBLANKs followed by
        // one requesting HBLANK.
        for (int unsigned interval = 0; interval <= lcstrt; interval++) begin
          active_line = veblnk + 16'd1 + {14'h0000, interval[1:0]};
          remaining_count = lcstrt - interval[1:0] - 2'd1;
          pulse_hblank(active_line);
          if (interval < lcstrt) begin
            check(!refresh_req, "cadence requested early");
            check(dpyadr[1:0] == remaining_count,
                  "cadence LNCNT decrement");
          end else begin
            check(refresh_req, "cadence request missing");
            check(refresh_srfaddr == after_first,
                  "second request raw SRFADR");
            check(refresh_org == org, "second request ORG capture");
          end
        end
        requests_checked++;
        pulse_ack();
        check(dpyadr == {after_second, lcstrt},
              "second completion raw DUDATE decrement");
      end else begin
        pulse_hblank(veblnk + 16'd1);
        check(!refresh_req, "SRE=0 generated request");
        check(dpyadr == {frame_raw, lcstrt}, "SRE=0 changed DPYADR");
      end
    end
  endtask

  initial begin : main
    logic [7:0] defined_dudate [0:8];

    defined_dudate[0] = 8'h00;
    defined_dudate[1] = 8'h01;
    defined_dudate[2] = 8'h02;
    defined_dudate[3] = 8'h04;
    defined_dudate[4] = 8'h08;
    defined_dudate[5] = 8'h10;
    defined_dudate[6] = 8'h20;
    defined_dudate[7] = 8'h40;
    defined_dudate[8] = 8'h80;

    failures = 0;
    cases_run = 0;
    requests_checked = 0;
    rst = 1'b1;
    hblank_start = 1'b0;
    vcount = 16'h0000;
    odd_field = 1'b0;
    veblnk = 16'd2;
    vsblnk = 16'd12;
    dpystart = 16'h0000;
    dpyctl = 16'h0000;
    dpytap = 16'h0000;
    dpyadr_load = 1'b0;
    dpyadr_wdata = 16'h0000;
    refresh_ack = 1'b0;

    repeat (2) @(negedge clk);

    for (int unsigned nil = 0; nil < 2; nil++) begin
      for (int unsigned field = 0; field < 2; field++) begin
        for (int unsigned org = 0; org < 2; org++) begin
          for (int unsigned sre = 0; sre < 2; sre++) begin
            for (int unsigned lc = 0; lc < 4; lc++) begin
              for (int unsigned du = 0; du < 9; du++) begin
                run_case(nil[0], field[0], org[0], sre[0], lc[1:0],
                         defined_dudate[du]);
              end
            end
          end
        end
      end
    end

    // Undefined multi-bit DUDATE is deliberately deterministic: the complete
    // field is treated as an unsigned raw decrement.
    run_case(1'b1, 1'b0, 1'b0, 1'b1, 2'b00, 8'hA5);

    // A held request keeps its address/tap/ORG payload, while completion uses
    // the live DUDATE field exactly when the memory cycle retires.
    dpystart = {14'h3100, 2'b10};
    dpyctl = (16'h0001 << DPYCTL_SRE_BIT)
           | (16'h0001 << DPYCTL_NIL_BIT)
           | (16'h0001 << DPYCTL_DXV_BIT)
           | (16'h0001 << DPYCTL_DUDATE_LO);
    dpytap = 16'h1111;
    odd_field = 1'b0;
    reset_case();
    load_dpyadr({14'h3100, 2'b00});
    pulse_hblank(veblnk);
    requests_checked++;
    check(refresh_req, "live-control request");
    dpytap = 16'h2222;
    dpyctl = (16'h0001 << DPYCTL_SRE_BIT)
           | (16'h0001 << DPYCTL_NIL_BIT)
           | (16'h0001 << DPYCTL_DXV_BIT)
           | (16'h0001 << DPYCTL_ORG_BIT)
           | (16'h0008 << DPYCTL_DUDATE_LO);
    check(refresh_srfaddr == 14'h3100, "held address changed");
    check(refresh_dpytap == 16'h1111, "held tap changed");
    check(!refresh_org, "held ORG changed");
    pulse_ack();
    check(dpyadr == {14'h30F8, 2'b10},
          "live completion DUDATE update");

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (display matrix: %0d cases, %0d requests)",
               cases_run, requests_checked);
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) in %0d cases",
               failures, cases_run);
    end
    $finish;
  end

  initial begin : watchdog
    #10_000_000;
    $display("TEST_RESULT: FAIL: tb_display_matrix hard timeout");
    $fatal(1);
  end

endmodule : tb_display_matrix

`default_nettype wire
