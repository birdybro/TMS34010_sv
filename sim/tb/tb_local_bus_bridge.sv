// -----------------------------------------------------------------------------
// tb_local_bus_bridge.sv
//
// Focused CDC regression for the two-phase command/response bridge. The clocks
// use a non-integer frequency ratio, the destination inserts variable waits,
// and every command payload field plus returned read data is checked.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_local_bus_bridge;
  import tms34010_pkg::*;

  logic             src_clk = 1'b0;
  logic             dst_clk = 1'b0;
  logic             rst = 1'b1;
  logic             src_req = 1'b0;
  local_cycle_cmd_t src_cmd;
  local_word_t      src_rdata;
  logic             src_ack;
  logic             src_busy;
  logic             dst_req;
  local_cycle_cmd_t dst_cmd;
  local_word_t      dst_rdata;
  logic             dst_ack;

  integer errors = 0;
  integer accepted_count = 0;
  integer completed_count = 0;
  integer wait_count_q = 0;
  local_cycle_cmd_t accepted_cmd_q;
  local_word_t      response_q;

  typedef enum logic [1:0] {
    TARGET_IDLE = 2'd0,
    TARGET_WAIT = 2'd1,
    TARGET_ACK  = 2'd2,
    TARGET_DROP = 2'd3
  } target_state_t;
  target_state_t target_state_q = TARGET_IDLE;

  always #7 src_clk = ~src_clk;
  always #2 dst_clk = ~dst_clk;

  tms34010_local_bus_bridge dut (
    .src_clk_i   (src_clk),
    .src_rst_i   (rst),
    .src_req_i   (src_req),
    .src_cmd_i   (src_cmd),
    .src_rdata_o (src_rdata),
    .src_ack_o   (src_ack),
    .src_busy_o  (src_busy),
    .dst_clk_i   (dst_clk),
    .dst_rst_i   (rst),
    .dst_req_o   (dst_req),
    .dst_cmd_o   (dst_cmd),
    .dst_rdata_i (dst_rdata),
    .dst_ack_i   (dst_ack)
  );

  assign dst_ack   = (target_state_q == TARGET_ACK);
  assign dst_rdata = response_q;

  task automatic check(input logic condition, input string message);
    begin
      if (!condition) begin
        $display("CHECK_FAIL: %s at t=%0t", message, $time);
        errors = errors + 1;
      end
    end
  endtask

  function automatic local_word_t command_response(
    input local_cycle_cmd_t command
  );
    return ~command.wdata ^ command.addr[15:0]
           ^ {8'h00, command.dram_row};
  endfunction

  // Variable-latency destination target. TARGET_DROP prevents the held
  // destination request from being mistaken for a second transfer on the
  // acknowledge edge.
  always_ff @(posedge dst_clk) begin
    if (rst) begin
      target_state_q  <= TARGET_IDLE;
      accepted_cmd_q  <= '0;
      response_q      <= '0;
      wait_count_q    <= 0;
      accepted_count  <= 0;
      completed_count <= 0;
    end else begin
      unique case (target_state_q)
        TARGET_IDLE: begin
          if (dst_req) begin
            accepted_cmd_q <= dst_cmd;
            response_q     <= command_response(dst_cmd);
            wait_count_q   <= (accepted_count % 4) + 1;
            accepted_count <= accepted_count + 1;
            target_state_q <= TARGET_WAIT;
          end
        end

        TARGET_WAIT: begin
          check(dst_req, "destination request dropped before acknowledge");
          check(dst_cmd == accepted_cmd_q,
                "destination command changed while stalled");
          if (wait_count_q == 0) begin
            target_state_q <= TARGET_ACK;
          end else begin
            wait_count_q <= wait_count_q - 1;
          end
        end

        TARGET_ACK: begin
          check(dst_req, "destination request absent during acknowledge");
          check(dst_cmd == accepted_cmd_q,
                "destination command changed during acknowledge");
          completed_count <= completed_count + 1;
          target_state_q  <= TARGET_DROP;
        end

        TARGET_DROP: begin
          if (!dst_req)
            target_state_q <= TARGET_IDLE;
        end

        default: target_state_q <= TARGET_IDLE;
      endcase
    end
  end

  task automatic issue_command(input local_cycle_cmd_t command);
    integer accepted_before;
    local_word_t expected_response;
    begin
      accepted_before  = accepted_count;
      expected_response = command_response(command);

      @(negedge src_clk);
      src_cmd = command;
      src_req = 1'b1;

      wait (src_busy);
      // The producer-facing bus may change after acceptance; the source MCP
      // register, not this live input, must be what reaches the destination.
      @(negedge src_clk);
      src_cmd = '1;

      wait (src_ack);
      check(src_rdata == expected_response,
            "returned response did not match accepted command");
      check(accepted_count == (accepted_before + 1),
            "command was not accepted exactly once");
      check(accepted_cmd_q == command,
            "destination command did not preserve every payload field");

      // Hold the request past acknowledge as the real arbiter does. The
      // source-side arming rule must suppress a duplicate launch.
      repeat (2) @(posedge src_clk);
      check(accepted_count == (accepted_before + 1),
            "held source request launched a duplicate command");

      @(negedge src_clk);
      src_req = 1'b0;
      src_cmd = '0;
      repeat (2) @(posedge src_clk);
      check(!src_busy, "bridge remained busy after returned acknowledge");
    end
  endtask

  initial begin
    local_cycle_cmd_t command;

    src_cmd = '0;
    repeat (5) @(posedge src_clk);
    @(negedge src_clk);
    rst = 1'b0;

    command = '0;
    command.kind       = LOCAL_CYCLE_WORD_READ;
    command.addr       = 32'h1234_5670;
    command.wdata      = 16'hA55A;
    command.io_rdata   = 16'h3CC3;
    command.iaq        = 1'b1;
    command.srfaddr    = 14'h1234;
    command.dpytap     = 16'h0F3C;
    command.screen_org = 1'b1;
    command.dram_row   = 8'hC7;
    issue_command(command);

    command.kind       = LOCAL_CYCLE_WORD_WRITE;
    command.addr       = 32'hFEDC_BA90;
    command.wdata      = 16'h5AA5;
    command.io_rdata   = 16'hC33C;
    command.iaq        = 1'b0;
    command.srfaddr    = 14'h2AAA;
    command.dpytap     = 16'hF0C3;
    command.screen_org = 1'b0;
    command.dram_row   = 8'h18;
    issue_command(command);

    command.kind       = LOCAL_CYCLE_SCREEN_REFRESH;
    command.addr       = 32'hCAFE_0010;
    command.wdata      = 16'h1357;
    command.io_rdata   = 16'h89AB;
    command.iaq        = 1'b1;
    command.srfaddr    = 14'h3E12;
    command.dpytap     = 16'hA63D;
    command.screen_org = 1'b1;
    command.dram_row   = 8'h9B;
    issue_command(command);

    command.kind       = LOCAL_CYCLE_DRAM_CBR;
    command.addr       = 32'h0BAD_F000;
    command.wdata      = 16'h2468;
    command.io_rdata   = 16'h7654;
    command.iaq        = 1'b0;
    command.srfaddr    = 14'h0555;
    command.dpytap     = 16'h55AA;
    command.screen_org = 1'b0;
    command.dram_row   = 8'hE1;
    issue_command(command);

    command.kind       = LOCAL_CYCLE_IO_READ;
    command.addr       = 32'hC000_0140;
    command.wdata      = 16'hBEEF;
    command.io_rdata   = 16'hD00D;
    command.iaq        = 1'b0;
    command.srfaddr    = 14'h0001;
    command.dpytap     = 16'h0002;
    command.screen_org = 1'b1;
    command.dram_row   = 8'h03;
    issue_command(command);

    wait (completed_count == 5);
    check(accepted_count == 5, "unexpected destination transfer count");
    check(completed_count == 5, "unexpected destination completion count");
    check(!src_ack, "source acknowledge must be a one-clock pulse");

    if (errors == 0) begin
      $display("TEST_RESULT: PASS");
    end else begin
      $display("TEST_RESULT: FAIL (%0d errors)", errors);
    end
    $finish;
  end

  initial begin
    #10000;
    $display("TEST_RESULT: FAIL (timeout)");
    $finish;
  end

endmodule : tb_local_bus_bridge

`default_nettype wire
