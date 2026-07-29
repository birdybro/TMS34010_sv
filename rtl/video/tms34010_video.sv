// -----------------------------------------------------------------------------
// tms34010_video.sv
//
// Video timing generator for the TMS34010 (1988 User's Guide §9 "Video
// Timing" and the corresponding Chapter 6 I/O-register pages). Free-running
// horizontal and vertical counters driven by the video clock (VCLK) produce
// HSYNC/VSYNC and blanking, plus a display-interrupt strobe.
//
//   HCOUNT increments every clock; when HCOUNT == HTOTAL it wraps to 0 and the
//   horizontal sync interval restarts. On each HCOUNT wrap, VCOUNT increments;
//   when VCOUNT == VTOTAL it wraps to 0 (a new frame).
//
//   HSYNC is asserted while HCOUNT <= HESYNC (the sync interval that begins at
//   the HTOTAL wrap). HBLANK is asserted while HCOUNT <= HEBLNK (the leading
//   blank, including the sync interval) or HCOUNT > HSBLNK (the trailing
//   blank); the visible region is HEBLNK+1..HSBLNK. These inclusive/exclusive
//   endpoints model the guide's one-VCLK delay after each equality compare.
//   The vertical signals use the analogous compares on VCOUNT. BLANK is
//   asserted when either axis is blanking or DPYCTL.ENV is clear.
//   DPYINT_PULSE is a one-clock strobe at the HSBLNK equality event on the
//   line selected by DPYINT.
//
// Scope (Task 0139): internal, noninterlaced functional timing. The I/O block
// drives this module from the project clock under A0004 until the dedicated
// VCLK/CDC boundary lands. External-sync correction and interlaced half-line
// timing remain separate video work. The original device advances HCOUNT on
// falling VCLK; this positive-edge implementation preserves count ordering
// but does not claim original pin phase (A0006).
//
// Spec source:
//   third_party/TMS34010_Info/docs/ti-official/1988_TI_TMS34010_Users_Guide.pdf
//   pages 6-18..6-25, 6-31, 6-47, and §9.7.
// -----------------------------------------------------------------------------

`default_nettype none
module tms34010_video
  import tms34010_pkg::*;
(
  input  logic        clk,        // VCLK (video / pixel clock)
  input  logic        rst,

  // Horizontal timing registers.
  input  logic [15:0] hesync,     // end of horizontal sync
  input  logic [15:0] heblnk,     // end of horizontal blank (display starts)
  input  logic [15:0] hsblnk,     // start of horizontal blank
  input  logic [15:0] htotal,     // total - 1 line length (HCOUNT wrap)
  // Vertical timing registers.
  input  logic [15:0] vesync,     // end of vertical sync
  input  logic [15:0] veblnk,     // end of vertical blank
  input  logic [15:0] vsblnk,     // start of vertical blank
  input  logic [15:0] vtotal,     // total - frame length (VCOUNT wrap)
  // Display-interrupt scan line.
  input  logic [15:0] dpyint,
  input  logic        display_enable, // DPYCTL.ENV

  // Processor counter writes. In the eventual VCLK implementation these
  // become explicit clock-domain transactions; they are same-clock loads in
  // the current A0004 functional model.
  input  logic        hcount_load,
  input  logic [15:0] hcount_wdata,
  input  logic        vcount_load,
  input  logic [15:0] vcount_wdata,

  output logic [15:0] hcount,
  output logic [15:0] vcount,
  output logic        hsync,      // 1 = within the horizontal sync interval
  output logic        vsync,      // 1 = within the vertical sync interval
  output logic        hblank,     // 1 = horizontal blanking
  output logic        vblank,     // 1 = vertical blanking
  output logic        blank,      // 1 = blanked (either axis)
  output logic        dpyint_pulse// one-clock strobe at the DPYINT scan line start
);

  logic hwrap;
  assign hwrap = (hcount == htotal);

  always_ff @(posedge clk) begin
    if (rst) begin
      hcount <= 16'd0;
      vcount <= 16'd0;
    end else begin
      if (hcount_load) begin
        hcount <= hcount_wdata;
      end else if (hwrap) begin
        hcount <= 16'd0;
      end else begin
        hcount <= hcount + 16'd1;
      end

      if (vcount_load) begin
        vcount <= vcount_wdata;
      end else if (!hcount_load && hwrap) begin
        if (vcount == vtotal) begin
          vcount <= 16'd0;
        end else begin
          vcount <= vcount + 16'd1;
        end
      end
    end
  end

  // Sync/blank intervals in count space. The User's Guide specifies that the
  // output transition occurs one VCLK after the corresponding equality, so
  // each end value remains active and each start value remains inactive.
  assign hsync  = (hcount <= hesync);
  assign vsync  = (vcount <= vesync);
  assign hblank = (hcount <= heblnk) || (hcount > hsblnk);
  assign vblank = (vcount <= veblnk) || (vcount > vsblnk);
  assign blank  = !display_enable || hblank || vblank;

  // Display interrupt: DPYINT matches VCOUNT at the start of horizontal
  // blanking (HCOUNT == HSBLNK), at the end of the selected scan line.
  // DPYCTL.ENV=0 inhibits new display-interrupt requests.
  assign dpyint_pulse =
      display_enable && (hcount == hsblnk) && (vcount == dpyint);

endmodule : tms34010_video

`default_nettype wire
