// -----------------------------------------------------------------------------
// tb_reset_sync.sv
//
// Reset-boundary regression: assertion is immediate, release occurs only
// after two destination-clock edges, and a later asynchronous assertion
// safely refills the release chain.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_reset_sync;

  logic clk = 1'b0;
  logic async_reset = 1'b0;
  logic rst;
  integer errors = 0;

  always #5 clk = !clk;

  tms34010_reset_sync dut (
    .clk_i         (clk),
    .async_reset_i (async_reset),
    .rst_o         (rst)
  );

  task automatic check(input logic condition, input string message);
    begin
      if (!condition) begin
        $display("CHECK_FAIL: %s at t=%0t", message, $time);
        errors = errors + 1;
      end
    end
  endtask

  initial begin
    #1;
    async_reset = 1'b1;
    #1;
    check(rst, "asynchronous request must assert reset immediately");

    #2;
    async_reset = 1'b0;
    #2;
    check(rst, "first release edge must retain reset");
    #10;
    check(!rst, "second release edge must deassert reset");

    #3;
    async_reset = 1'b1;
    #1;
    check(rst, "runtime asynchronous request must reassert reset");
    #3;
    async_reset = 1'b0;
    #3;
    check(rst, "runtime first release edge must retain reset");
    #10;
    check(!rst, "runtime second release edge must deassert reset");

    if (errors == 0) begin
      $display("TEST_RESULT: PASS");
    end else begin
      $display("TEST_RESULT: FAIL (%0d errors)", errors);
    end
    $finish;
  end

endmodule : tb_reset_sync

`default_nettype wire
