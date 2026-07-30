// -----------------------------------------------------------------------------
// tb_fpga_io.sv
//
// Direct pad-adapter regression. It proves byte-lane host direction, complete
// local-bus direction, HOLD-style control release, and active-low
// video-pin conversion without involving the functional core.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_fpga_io;

  wire [15:0] hd;
  logic [15:0] hd_i;
  logic [15:0] hd_o = 16'h0000;
  logic [1:0]  hd_oe = 2'b00;
  logic [15:0] hd_external_data = 16'h0000;
  logic        hd_external_oe = 1'b0;

  wire [15:0] lad;
  logic [15:0] lad_i;
  logic [15:0] lad_o = 16'h0000;
  logic        lad_oe = 1'b0;
  logic [15:0] lad_external_data = 16'h0000;
  logic        lad_external_oe = 1'b0;

  wire hsync_n;
  wire vsync_n;
  logic hsync_n_i;
  logic vsync_n_i;
  logic hsync = 1'b0;
  logic vsync = 1'b0;
  logic hsync_oe = 1'b0;
  logic vsync_oe = 1'b0;
  logic blank = 1'b0;
  logic blank_n;
  logic hsync_external = 1'b1;
  logic vsync_external = 1'b1;
  logic hsync_external_oe = 1'b0;
  logic vsync_external_oe = 1'b0;

  wire ras_n;
  wire lal_n;
  wire cas_n;
  wire we_n;
  wire tr_qe_n;
  wire den_n;
  wire ddout;
  logic ras_value = 1'b1;
  logic lal_value = 1'b1;
  logic cas_value = 1'b1;
  logic we_value = 1'b1;
  logic tr_qe_value = 1'b1;
  logic den_value = 1'b1;
  logic ddout_value = 1'b0;
  logic ras_oe = 1'b0;
  logic lal_oe = 1'b0;
  logic cas_oe = 1'b0;
  logic we_oe = 1'b0;
  logic tr_qe_oe = 1'b0;
  logic den_oe = 1'b0;
  logic ddout_oe = 1'b0;

  integer errors = 0;

  assign hd = hd_external_oe ? hd_external_data : 16'bz;
  assign lad = lad_external_oe ? lad_external_data : 16'bz;
  assign hsync_n = hsync_external_oe ? hsync_external : 1'bz;
  assign vsync_n = vsync_external_oe ? vsync_external : 1'bz;

  tms34010_fpga_io dut (
    .hd_io         (hd),
    .hd_i_o        (hd_i),
    .hd_o_i        (hd_o),
    .hd_oe_i       (hd_oe),
    .lad_io        (lad),
    .lad_i_o       (lad_i),
    .lad_o_i       (lad_o),
    .lad_oe_i      (lad_oe),
    .hsync_n_io    (hsync_n),
    .vsync_n_io    (vsync_n),
    .hsync_n_i_o   (hsync_n_i),
    .vsync_n_i_o   (vsync_n_i),
    .hsync_i       (hsync),
    .vsync_i       (vsync),
    .hsync_oe_i    (hsync_oe),
    .vsync_oe_i    (vsync_oe),
    .blank_i       (blank),
    .blank_n_o     (blank_n),
    .ras_n_io      (ras_n),
    .lal_n_io      (lal_n),
    .cas_n_io      (cas_n),
    .we_n_io       (we_n),
    .tr_qe_n_io    (tr_qe_n),
    .den_n_io      (den_n),
    .ddout_io      (ddout),
    .ras_n_i       (ras_value),
    .lal_n_i       (lal_value),
    .cas_n_i       (cas_value),
    .we_n_i        (we_value),
    .tr_qe_n_i     (tr_qe_value),
    .den_n_i       (den_value),
    .ddout_i       (ddout_value),
    .ras_oe_i      (ras_oe),
    .lal_oe_i      (lal_oe),
    .cas_oe_i      (cas_oe),
    .we_oe_i       (we_oe),
    .tr_qe_oe_i    (tr_qe_oe),
    .den_oe_i      (den_oe),
    .ddout_oe_i    (ddout_oe)
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
    check(hd === 16'bz, "released HD must be high impedance");
    check(lad === 16'bz, "released LAD must be high impedance");
    check(ras_n === 1'bz && lal_n === 1'bz && cas_n === 1'bz,
          "released row/column controls must be high impedance");
    check(we_n === 1'bz && tr_qe_n === 1'bz && den_n === 1'bz
          && ddout === 1'bz,
          "released data controls must be high impedance");

    hd_external_data = 16'ha55a;
    hd_external_oe = 1'b1;
    #1;
    check(hd_i == 16'ha55a, "external HD data must reach the input bundle");
    hd_external_oe = 1'b0;
    hd_o = 16'hc33c;
    hd_oe = 2'b01;
    #1;
    check(hd[7:0] === 8'h3c && hd[15:8] === 8'bz,
          "lower HD lane must drive independently");
    hd_oe = 2'b10;
    #1;
    check(hd[7:0] === 8'bz && hd[15:8] === 8'hc3,
          "upper HD lane must drive independently");
    hd_oe = 2'b11;
    #1;
    check(hd === 16'hc33c, "both HD lanes must drive the full word");
    hd_oe = 2'b00;

    lad_external_data = 16'h5aa5;
    lad_external_oe = 1'b1;
    #1;
    check(lad_i == 16'h5aa5, "external LAD data must reach the input bundle");
    lad_external_oe = 1'b0;
    lad_o = 16'h0f96;
    lad_oe = 1'b1;
    #1;
    check(lad === 16'h0f96, "LAD output enable must drive the complete word");
    lad_oe = 1'b0;
    #1;
    check(lad === 16'bz, "LAD release must restore high impedance");

    hsync_external = 1'b0;
    vsync_external = 1'b1;
    hsync_external_oe = 1'b1;
    vsync_external_oe = 1'b1;
    #1;
    check(!hsync_n_i && vsync_n_i,
          "external active-low sync levels must reach the video inputs");
    hsync_external_oe = 1'b0;
    vsync_external_oe = 1'b0;
    hsync = 1'b1;
    vsync = 1'b0;
    hsync_oe = 1'b1;
    vsync_oe = 1'b1;
    #1;
    check(hsync_n === 1'b0 && vsync_n === 1'b1,
          "functional sync intervals must invert onto active-low pins");
    check(!hsync_n_i && vsync_n_i,
          "bidirectional sync inputs must reflect the driven pin levels");
    hsync_oe = 1'b0;
    vsync_oe = 1'b0;
    #1;
    check(hsync_n === 1'bz && vsync_n === 1'bz,
          "disabled sync outputs must release both pins");
    blank = 1'b1;
    #1;
    check(blank_n === 1'b0,
          "functional blank interval must assert active-low BLANK pin");
    blank = 1'b0;
    #1;
    check(blank_n === 1'b1,
          "visible interval must release active-low BLANK pin");

    ras_value = 1'b0;
    lal_value = 1'b1;
    cas_value = 1'b0;
    we_value = 1'b1;
    tr_qe_value = 1'b0;
    den_value = 1'b1;
    ddout_value = 1'b1;
    ras_oe = 1'b1;
    lal_oe = 1'b1;
    cas_oe = 1'b1;
    we_oe = 1'b1;
    tr_qe_oe = 1'b1;
    den_oe = 1'b1;
    ddout_oe = 1'b1;
    #1;
    check(ras_n === 1'b0 && lal_n === 1'b1 && cas_n === 1'b0,
          "row/column control values must reach their pads");
    check(we_n === 1'b1 && tr_qe_n === 1'b0 && den_n === 1'b1
          && ddout === 1'b1,
          "write/data control values must reach their pads");
    cas_oe = 1'b0;
    ddout_oe = 1'b0;
    #1;
    check(cas_n === 1'bz && ddout === 1'bz,
          "each control output enable must release independently");

    if (errors == 0) begin
      $display("TEST_RESULT: PASS");
    end else begin
      $display("TEST_RESULT: FAIL (%0d errors)", errors);
    end
    $finish;
  end

endmodule : tb_fpga_io

`default_nettype wire
