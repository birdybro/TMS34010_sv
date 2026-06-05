// -----------------------------------------------------------------------------
// tb_int_ctrl.sv
//
// Unit test for tms34010_int_ctrl — the maskable-interrupt priority encoder.
// Checks: gating by INTENB and the global IE bit, the priority order
// (HI > DI > WV > INT1 > INT2, internal before external), and the trap-vector
// mapping. Purely combinational — drive inputs, settle, check outputs.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_int_ctrl;
  import tms34010_pkg::*;

  logic [15:0]           intpend, intenb;
  logic                  ie;
  logic                  int_req;
  logic [ADDR_WIDTH-1:0] int_vector;

  tms34010_int_ctrl u_int (
    .intpend(intpend), .intenb(intenb), .ie(ie),
    .int_req(int_req), .int_vector(int_vector)
  );

  int unsigned failures;

  task automatic check(input string label,
                       input logic [15:0] pend, input logic [15:0] enb, input logic g,
                       input logic exp_req, input logic [ADDR_WIDTH-1:0] exp_vec);
    intpend = pend; intenb = enb; ie = g;
    #1;
    if (int_req !== exp_req) begin
      $display("TEST_RESULT: FAIL: %s: int_req exp=%0b got=%0b", label, exp_req, int_req);
      failures++;
    end
    // Vector only meaningful when an interrupt is taken.
    if (exp_req && (int_vector !== exp_vec)) begin
      $display("TEST_RESULT: FAIL: %s: vector exp=%08h got=%08h", label, exp_vec, int_vector);
      failures++;
    end
  endtask

  localparam logic [15:0] B_HI = 16'd1 << INT_HI_BIT;
  localparam logic [15:0] B_DI = 16'd1 << INT_DI_BIT;
  localparam logic [15:0] B_WV = 16'd1 << INT_WV_BIT;
  localparam logic [15:0] B_X1 = 16'd1 << INT_X1_BIT;
  localparam logic [15:0] B_X2 = 16'd1 << INT_X2_BIT;
  localparam logic [15:0] ALL  = B_HI | B_DI | B_WV | B_X1 | B_X2;

  initial begin : main
    failures = 0;

    // No requests.
    check("none",          16'h0, ALL, 1'b1, 1'b0, '0);
    // Single sources, enabled, IE=1.
    check("HI",            B_HI, ALL, 1'b1, 1'b1, INT_VEC_HI);
    check("DI",            B_DI, ALL, 1'b1, 1'b1, INT_VEC_DI);
    check("WV",            B_WV, ALL, 1'b1, 1'b1, INT_VEC_WV);
    check("X1",            B_X1, ALL, 1'b1, 1'b1, INT_VEC_X1);
    check("X2",            B_X2, ALL, 1'b1, 1'b1, INT_VEC_X2);
    // Priority: higher source wins.
    check("HI>DI",         B_HI | B_DI,       ALL, 1'b1, 1'b1, INT_VEC_HI);
    check("DI>WV",         B_DI | B_WV,       ALL, 1'b1, 1'b1, INT_VEC_DI);
    check("WV>X1 (int>ext)",B_WV | B_X1,      ALL, 1'b1, 1'b1, INT_VEC_WV);
    check("X1>X2",         B_X1 | B_X2,       ALL, 1'b1, 1'b1, INT_VEC_X1);
    check("all",           ALL,               ALL, 1'b1, 1'b1, INT_VEC_HI);
    // Masked off by INTENB: HI pending but not enabled -> no req.
    check("HI pend, not enabled", B_HI, ~B_HI, 1'b1, 1'b0, '0);
    // DI pending+enabled but WV not enabled, both pending -> DI wins (WV masked).
    check("WV masked -> DI", B_DI | B_WV, B_DI, 1'b1, 1'b1, INT_VEC_DI);
    // Global IE = 0 inhibits everything.
    check("IE=0",          ALL, ALL, 1'b0, 1'b0, '0);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (int_ctrl: INTENB/IE gating, priority HI>DI>WV>X1>X2, vectors)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #1_000_000;
    $display("TEST_RESULT: FAIL: tb_int_ctrl hard timeout");
    $fatal(1);
  end

endmodule : tb_int_ctrl
