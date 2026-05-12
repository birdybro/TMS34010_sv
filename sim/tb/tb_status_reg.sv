// -----------------------------------------------------------------------------
// tb_status_reg.sv
//
// Unit test for tms34010_status_reg.
//
// Coverage:
//   1. Reset clears ST and all flag outputs.
//   2. `flag_update_en` writes the four flag bits without touching the
//      other 28 bits of ST.
//   3. `st_write_en` writes the entire 32-bit ST.
//   4. `st_write_en` takes precedence over `flag_update_en` when both are
//      asserted in the same cycle.
//   5. Named flag outputs (n_o/c_o/z_o/v_o) track the named bits of ST.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_status_reg;
  import tms34010_pkg::*;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  // ---------------------------------------------------------------------------
  // DUT wiring
  // ---------------------------------------------------------------------------
  logic                  flag_update_en;
  alu_flags_t            flags_in;
  logic                  st_write_en;
  logic [DATA_WIDTH-1:0] st_write_data;

  logic [DATA_WIDTH-1:0] st_o;
  logic                  n_o, c_o, z_o, v_o;

  tms34010_status_reg dut (
    .clk           (clk),
    .rst           (rst),
    .flag_update_en(flag_update_en),
    .flags_in      (flags_in),
    .st_write_en   (st_write_en),
    .st_write_data (st_write_data),
    .st_o          (st_o),
    .n_o           (n_o),
    .c_o           (c_o),
    .z_o           (z_o),
    .v_o           (v_o)
  );

  int unsigned failures;

  task automatic check(input string label,
                       input logic [DATA_WIDTH-1:0] exp_st,
                       input logic exp_n,
                       input logic exp_c,
                       input logic exp_z,
                       input logic exp_v);
    if (st_o !== exp_st || n_o !== exp_n || c_o !== exp_c ||
        z_o !== exp_z || v_o !== exp_v) begin
      $display("TEST_RESULT: FAIL: %s: got ST=%08h n=%0b c=%0b z=%0b v=%0b; expected ST=%08h n=%0b c=%0b z=%0b v=%0b",
               label, st_o, n_o, c_o, z_o, v_o,
               exp_st, exp_n, exp_c, exp_z, exp_v);
      failures++;
    end
  endtask

  // Build a 32-bit ST from individual flag values + base (non-flag bits).
  function automatic logic [DATA_WIDTH-1:0] build_st(
      input logic [DATA_WIDTH-1:0] base,
      input logic n_in, logic c_in, logic z_in, logic v_in);
    logic [DATA_WIDTH-1:0] r;
    r = base;
    r[ST_N_BIT] = n_in;
    r[ST_C_BIT] = c_in;
    r[ST_Z_BIT] = z_in;
    r[ST_V_BIT] = v_in;
    return r;
  endfunction

  initial begin : main
    failures        = 0;
    flag_update_en  = 1'b0;
    flags_in        = '0;
    st_write_en     = 1'b0;
    st_write_data   = '0;

    // 1. Reset clears ST.
    repeat (3) @(posedge clk);
    #1;
    check("after reset", 32'd0, 1'b0, 1'b0, 1'b0, 1'b0);

    rst = 1'b0;
    #1;

    // 2. Selective flag update: n=1, c=0, z=1, v=0. Other ST bits remain 0.
    flags_in       = '{n: 1'b1, c: 1'b0, z: 1'b1, v: 1'b0};
    flag_update_en = 1'b1;
    @(posedge clk);
    flag_update_en = 1'b0;
    #1;
    check("flag update n=1 z=1",
          build_st(32'd0, 1'b1, 1'b0, 1'b1, 1'b0),
          1'b1, 1'b0, 1'b1, 1'b0);

    // 3. Another flag update: all set.
    flags_in       = '{n: 1'b1, c: 1'b1, z: 1'b1, v: 1'b1};
    flag_update_en = 1'b1;
    @(posedge clk);
    flag_update_en = 1'b0;
    #1;
    check("flag update all-1",
          build_st(32'd0, 1'b1, 1'b1, 1'b1, 1'b1),
          1'b1, 1'b1, 1'b1, 1'b1);

    // 4. Full ST write (POPST style).
    begin : full_write_test
      logic [DATA_WIDTH-1:0] full_val;
      full_val      = 32'h1234_ABCD;
      st_write_data = full_val;
      st_write_en   = 1'b1;
      @(posedge clk);
      st_write_en   = 1'b0;
      #1;
      check("full ST write 1234_ABCD",
            full_val,
            full_val[ST_N_BIT],
            full_val[ST_C_BIT],
            full_val[ST_Z_BIT],
            full_val[ST_V_BIT]);
    end

    // 5. Non-flag bits preserved across a flag update.
    flags_in       = '{n: 1'b0, c: 1'b0, z: 1'b0, v: 1'b0};
    flag_update_en = 1'b1;
    @(posedge clk);
    flag_update_en = 1'b0;
    #1;
    // ST should be 32'h1234_ABCD with the four flag bits cleared.
    check("non-flag bits preserved",
          build_st(32'h1234_ABCD & ~((32'd1 << ST_N_BIT) |
                                     (32'd1 << ST_C_BIT) |
                                     (32'd1 << ST_Z_BIT) |
                                     (32'd1 << ST_V_BIT)),
                   1'b0, 1'b0, 1'b0, 1'b0),
          1'b0, 1'b0, 1'b0, 1'b0);

    // 6. st_write_en wins over flag_update_en when both are asserted.
    begin : write_wins_test
      logic [DATA_WIDTH-1:0] full_val;
      full_val       = 32'hAAAA_5555;
      flags_in       = '{n: 1'b1, c: 1'b1, z: 1'b1, v: 1'b1};
      flag_update_en = 1'b1;
      st_write_data  = full_val;
      st_write_en    = 1'b1;
      @(posedge clk);
      flag_update_en = 1'b0;
      st_write_en    = 1'b0;
      #1;
      check("st_write wins over flag_update",
            full_val,
            full_val[ST_N_BIT],
            full_val[ST_C_BIT],
            full_val[ST_Z_BIT],
            full_val[ST_V_BIT]);
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (all ST checks passed)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d ST check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #50_000;
    $display("TEST_RESULT: FAIL: tb_status_reg hard timeout");
    $fatal(1);
  end

endmodule : tb_status_reg
