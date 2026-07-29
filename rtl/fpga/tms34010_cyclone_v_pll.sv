// -----------------------------------------------------------------------------
// tms34010_cyclone_v_pll.sv
//
// Cyclone V clock wrapper for the DE10-Nano realization. The 50 MHz
// FPGA_CLK1 oscillator produces:
//   * 50 MHz core_clk_o; and
//   * 200 MHz bus_clk8x_o, yielding 25 MHz LCLK1/LCLK2 periods after the
//     local-bus engine's eight subphases.
//
// TMS34010_QUARTUS selects the Intel PLL primitive during the Quartus build.
// Portable lint/simulation deliberately bypasses the frequency conversion;
// clock-ratio behavior remains covered at the split pin-system boundary.
//
// Justification: Cyclone V derived clocks must come from a PLL rather than a
// fabric divider (HDL guideline 11 and assumption A0049).
// -----------------------------------------------------------------------------

`default_nettype none

module tms34010_cyclone_v_pll (
  input  logic ref_clk_i,
  input  logic pll_rst_i,
  output logic core_clk_o,
  output logic bus_clk8x_o,
  output logic locked_o
);

`ifdef TMS34010_QUARTUS
  logic [1:0] pll_clks;

  altera_pll #(
    .fractional_vco_multiplier("false"),
    .reference_clock_frequency("50.0 MHz"),
    .operation_mode("normal"),
    .number_of_clocks(2),
    .output_clock_frequency0("50.0 MHz"),
    .phase_shift0("0 ps"),
    .duty_cycle0(50),
    .output_clock_frequency1("200.0 MHz"),
    .phase_shift1("0 ps"),
    .duty_cycle1(50),
    .pll_type("General"),
    .pll_subtype("General")
  ) u_pll (
    .outclk  (pll_clks),
    .locked  (locked_o),
    .fboutclk(),
    .fbclk   (1'b0),
    .rst     (pll_rst_i),
    .refclk  (ref_clk_i)
  );

  assign core_clk_o   = pll_clks[0];
  assign bus_clk8x_o  = pll_clks[1];
`else
  // Portable elaboration model only. Tests that need independent or
  // non-integer clock ratios instantiate tms34010_pin_system directly.
  assign core_clk_o  = ref_clk_i;
  assign bus_clk8x_o = ref_clk_i;
  assign locked_o    = !pll_rst_i;
`endif

endmodule : tms34010_cyclone_v_pll

`default_nettype wire
