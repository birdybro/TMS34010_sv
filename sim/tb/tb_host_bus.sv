// -----------------------------------------------------------------------------
// tb_host_bus.sv
//
// Focused regression for the asynchronous original-pin host bridge. Host
// edges are deliberately offset from the core clock. The test proves
// immediate HRDY waits, coherent bundled capture, selected-byte HD direction,
// HCS-only HSTCTL delay, invalid direction rejection, indirect-busy carryover,
// completed-access ready hold, and inactive-level CDC re-arming.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_host_bus;
  import tms34010_pkg::*;

  logic          clk = 1'b0;
  logic          rst = 1'b1;
  logic          hcs_n = 1'b1;
  logic          hread_n = 1'b1;
  logic          hwrite_n = 1'b1;
  logic          hlds_n = 1'b1;
  logic          huds_n = 1'b1;
  logic [1:0]    hfs = HOST_REG_HSTADRL;
  local_word_t   hd_i = '0;
  local_word_t   hd_o;
  logic [1:0]    hd_oe;
  logic          hrdy;
  logic          host_req;
  logic          host_we;
  host_reg_sel_t host_reg;
  logic [1:0]    host_be;
  local_word_t   host_wdata;
  local_word_t   host_rdata = '0;
  logic          host_ack = 1'b0;
  logic          host_busy = 1'b0;
  integer        errors = 0;

  always #5 clk = ~clk;

  tms34010_host_bus dut (
    .clk          (clk),
    .rst          (rst),
    .hcs_n_i      (hcs_n),
    .hread_n_i    (hread_n),
    .hwrite_n_i   (hwrite_n),
    .hlds_n_i     (hlds_n),
    .huds_n_i     (huds_n),
    .hfs_i        (hfs),
    .hd_i         (hd_i),
    .hd_o         (hd_o),
    .hd_oe_o      (hd_oe),
    .hrdy_o       (hrdy),
    .host_req_o   (host_req),
    .host_we_o    (host_we),
    .host_reg_o   (host_reg),
    .host_be_o    (host_be),
    .host_wdata_o (host_wdata),
    .host_rdata_i (host_rdata),
    .host_ack_i   (host_ack),
    .host_busy_i  (host_busy)
  );

  task automatic check(input logic condition, input string message);
    begin
      if (!condition) begin
        $display("CHECK_FAIL: %s at t=%0t", message, $time);
        errors = errors + 1;
      end
    end
  endtask

  task automatic start_access(
    input logic          write_access,
    input host_reg_sel_t selected_reg,
    input logic [1:0]    byte_enable,
    input local_word_t   write_data
  );
    begin
      @(negedge clk);
      hfs      = selected_reg;
      hd_i     = write_data;
      hread_n  = write_access;
      hwrite_n = !write_access;
      hlds_n   = !byte_enable[0];
      huds_n   = !byte_enable[1];
      #2;
      hcs_n = 1'b0;
      #1;
      check(!hrdy, "active access did not lower HRDY immediately");
      check(hd_oe == 2'b00, "HD drove before a read response was ready");
    end
  endtask

  task automatic wait_request(
    input logic          expected_we,
    input host_reg_sel_t expected_reg,
    input logic [1:0]    expected_be,
    input local_word_t   expected_wdata
  );
    int unsigned watchdog;
    begin
      watchdog = 0;
      while (!host_req && (watchdog < 12)) begin
        @(posedge clk);
        #1;
        watchdog++;
      end
      check(host_req, "synchronized host request timed out");
      check(host_we == expected_we, "captured host direction mismatch");
      check(host_reg == expected_reg, "captured HFS selection mismatch");
      check(host_be == expected_be, "captured host byte enables mismatch");
      if (expected_we)
        check(host_wdata == expected_wdata,
              "captured host write data mismatch");

      // The host keeps the physical bundle stable through HRDY. Confirm that
      // the corresponding synchronous request and payload are likewise held
      // unchanged until their acknowledge.
      @(posedge clk);
      #1;
      check(host_req, "host request was not held until acknowledge");
      check(host_we == expected_we, "held host direction changed");
      check(host_reg == expected_reg, "held HFS selection changed");
      check(host_be == expected_be, "held byte enables changed");
      if (expected_we)
        check(host_wdata == expected_wdata, "held write data changed");
    end
  endtask

  task automatic acknowledge(input local_word_t read_data);
    begin
      @(negedge clk);
      host_rdata = read_data;
      host_ack   = 1'b1;
      @(posedge clk);
      #1;
      host_ack = 1'b0;
      check(!host_req, "request did not retire after acknowledge");
    end
  endtask

  task automatic end_access;
    begin
      @(negedge clk);
      hcs_n    = 1'b1;
      hread_n  = 1'b1;
      hwrite_n = 1'b1;
      hlds_n   = 1'b1;
      huds_n   = 1'b1;
      hd_i     = '0;
      #1;
      check(hrdy, "HRDY was not high while HCS was inactive");
      check(hd_oe == 2'b00, "HD drove while HCS was inactive");
      // The combined access must propagate inactive through the two-flop
      // synchronizer before another transaction begins.
      repeat (3) @(posedge clk);
      #1;
      check(!host_req, "request did not re-arm after inactive access");
    end
  endtask

  initial begin
    int unsigned watchdog;

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    #1;
    check(hrdy, "idle HRDY was not high after reset");
    check(hd_oe == 2'b00, "idle HD output enables were active");

    // Upper-byte write: HCS is the last active strobe and creates the wait.
    start_access(1'b1, HOST_REG_HSTADRH, 2'b10, 16'hA55A);
    wait_request(1'b1, HOST_REG_HSTADRH, 2'b10, 16'hA55A);
    acknowledge(16'h0000);
    check(hrdy, "completed write did not release HRDY");
    check(hd_oe == 2'b00, "write access enabled an HD output lane");
    end_access();

    // Lower-byte read: no HD lane may drive until the response is latched.
    start_access(1'b0, HOST_REG_HSTDATA, 2'b01, 16'h0000);
    wait_request(1'b0, HOST_REG_HSTDATA, 2'b01, 16'h0000);
    acknowledge(16'hC35A);
    check(hrdy, "completed read did not release HRDY");
    check(hd_o == 16'hC35A, "read response was not retained on HD");
    check(hd_oe == 2'b01, "read did not enable only the selected HD lane");
    end_access();

    // HREAD and HWRITE may never both be active. Such a pin combination is
    // not an access and must neither wait nor reach the synchronous engine.
    @(negedge clk);
    hfs      = HOST_REG_HSTADRL;
    hread_n  = 1'b0;
    hwrite_n = 1'b0;
    hlds_n   = 1'b0;
    huds_n   = 1'b0;
    #2;
    hcs_n = 1'b0;
    repeat (4) @(posedge clk);
    #1;
    check(hrdy, "illegal simultaneous read/write lowered HRDY");
    check(!host_req, "illegal simultaneous read/write launched a request");
    check(hd_oe == 2'b00, "illegal simultaneous read/write drove HD");
    end_access();

    // HSTCTL alone must lower HRDY from HCS and stable HFS before direction
    // or byte strobes arrive, then release it after the mandatory interval.
    @(negedge clk);
    hfs      = HOST_REG_HSTCTL;
    hread_n  = 1'b1;
    hwrite_n = 1'b1;
    hlds_n   = 1'b1;
    huds_n   = 1'b1;
    #2;
    hcs_n = 1'b0;
    #1;
    check(!hrdy, "HSTCTL HCS-only selection did not lower HRDY");
    watchdog = 0;
    while (!hrdy && (watchdog < 8)) begin
      @(posedge clk);
      #1;
      watchdog++;
    end
    check(hrdy, "HSTCTL HCS-only wait did not finish");
    check(watchdog >= 2, "HSTCTL HCS-only wait was shorter than two clocks");
    check(!host_req, "HSTCTL HCS-only selection launched a request");

    // Completing the remaining strobes creates the normal coherent request.
    @(negedge clk);
    hread_n = 1'b0;
    hlds_n  = 1'b0;
    #1;
    check(!hrdy, "late HSTCTL read strobe did not lower HRDY");
    wait_request(1'b0, HOST_REG_HSTCTL, 2'b01, 16'h0000);
    acknowledge(16'h7E19);
    check(hrdy, "completed HSTCTL read did not release HRDY");
    check(hd_oe == 2'b01, "HSTCTL read enabled the wrong HD lanes");
    end_access();

    // A side effect may make the engine busy before its register response is
    // returned. Response readiness wins for this access; after its strobe
    // ends with HCS still selected, that busy state becomes visible.
    start_access(1'b1, HOST_REG_HSTDATA, 2'b11, 16'h2468);
    wait_request(1'b1, HOST_REG_HSTDATA, 2'b11, 16'h2468);
    @(negedge clk);
    host_busy  = 1'b1;
    host_rdata = 16'h0000;
    host_ack   = 1'b1;
    @(posedge clk);
    #1;
    host_ack = 1'b0;
    check(hrdy, "new busy state blocked the already-completed access");
    @(negedge clk);
    hread_n  = 1'b1;
    hwrite_n = 1'b1;
    hlds_n   = 1'b1;
    huds_n   = 1'b1;
    #1;
    check(!hrdy, "busy state did not appear after the access ended");
    hcs_n = 1'b1;
    #1;
    check(hrdy, "inactive HCS did not override host busy");
    repeat (3) @(posedge clk);

    // Busy from the preceding indirect operation waits the following access.
    start_access(1'b0, HOST_REG_HSTADRL, 2'b11, 16'h0000);
    wait_request(1'b0, HOST_REG_HSTADRL, 2'b11, 16'h0000);
    repeat (2) begin
      @(posedge clk);
      #1;
      check(!hrdy, "busy following access released HRDY");
      check(host_req, "busy following request was not held");
    end
    @(negedge clk);
    host_busy = 1'b0;
    acknowledge(16'h1357);
    check(hrdy, "following access did not complete after busy cleared");
    check(hd_o == 16'h1357, "following access returned wrong read data");
    check(hd_oe == 2'b11, "word read did not enable both HD lanes");
    end_access();

    // A final transaction proves that the inactive access level re-armed the
    // bridge and that no prior response can satisfy a new access.
    start_access(1'b1, HOST_REG_HSTADRL, 2'b01, 16'h00AA);
    check(!hrdy, "back-to-back re-armed access reused an old response");
    wait_request(1'b1, HOST_REG_HSTADRL, 2'b01, 16'h00AA);
    acknowledge(16'h0000);
    check(hrdy, "back-to-back re-armed write did not complete");
    end_access();

    if (errors == 0)
      $display("TEST_RESULT: PASS");
    else
      $display("TEST_RESULT: FAIL (%0d errors)", errors);
    $finish;
  end

  initial begin
    #10000;
    $display("TEST_RESULT: FAIL (timeout)");
    $finish;
  end

endmodule : tb_host_bus

`default_nettype wire
