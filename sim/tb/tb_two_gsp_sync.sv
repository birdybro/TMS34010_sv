`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// tb_two_gsp_sync.sv
//
// 1988 UG 9.9.1, "A Two-GSP System": GSP #1 generates the video timing
// (DXV=1); GSP #2 runs in external sync mode (DXV=0, HSD=0) from GSP #1's
// HSYNC and VSYNC. With GSP #2 programmed as Table 9-1 (HEBLNK2 = HEBLNK1-3,
// HSBLNK2 = HSBLNK1-3, HTOTAL2 = VTOTAL2 = 65535, VEBLNK2/VSBLNK2 = GSP #1's,
// HESYNC2/VESYNC2 half way), "the BLANK signals from GSP #1 and GSP #2 are the
// same, and switch in unison on the same VCLK edges". Checks BLANK (the pin)
// and HBLANK of the two units on every clock of four frames after two to lock,
// for two sets of timing values and for the Exterminator's own (master and
// slave registers as the game writes them, from the MAME survey: exactly
// Table 9-1). The internal VBLANK flags differ for the 3 clocks by which GSP
// #2's line starts later (HCOUNT2 is cleared three VCLK periods after
// HCOUNT1); they are counted and must stay inside horizontal blanking. The
// chip ends GSP #2's vertical blanking when it detects the external HSYNC
// (6-49), so this skew is the model's; it is hidden only while HBLANK covers
// it. Limit: HEBLNK1 >= 3 only. With HEBLNK1 < 3 (the guide's worked example)
// HEBLNK2 wraps, and tms34010_video's window compares blank GSP #2's whole
// line where the guide's set/reset on equality (9-6) would not.
// -----------------------------------------------------------------------------
module tb_two_gsp_sync;
  import tms34010_pkg::*;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  logic [15:0] hes1, heb1, hsb1, htot1, ves1, veb1, vsb1, vtot1;
  logic [15:0] hes2, heb2, hsb2, ves2, veb2, vsb2;
  logic [15:0] hc1, vc1, hc2, vc2;
  logic        hs1, vs1, hb1, vb1, bl1, hs2, vs2, hb2, vb2, bl2;
  int unsigned failures = 0;

  tms34010_video u_gsp1 (
    .clk(clk), .rst(rst), .ce(1'b1),
    .hesync(hes1), .heblnk(heb1), .hsblnk(hsb1), .htotal(htot1),
    .vesync(ves1), .veblnk(veb1), .vsblnk(vsb1), .vtotal(vtot1),
    .dpyint(16'd0), .display_enable(1'b1), .noninterlaced(1'b1),
    .disable_external_video(1'b1), .hsync_direction(1'b0),
    .hsync_n_i(1'b1), .vsync_n_i(1'b1),
    .hcount_load(1'b0), .hcount_wdata('0), .vcount_load(1'b0), .vcount_wdata('0),
    .hcount(hc1), .vcount(vc1), .hsync(hs1), .vsync(vs1),
    .hblank(hb1), .vblank(vb1), .blank(bl1), .hsync_oe(), .vsync_oe(),
    .hblank_start(), .dpyint_pulse(), .odd_field()
  );

  // GSP #1's sync pins (active low) drive GSP #2's sync inputs.
  tms34010_video u_gsp2 (
    .clk(clk), .rst(rst), .ce(1'b1),
    .hesync(hes2), .heblnk(heb2), .hsblnk(hsb2), .htotal(16'hFFFF),
    .vesync(ves2), .veblnk(veb2), .vsblnk(vsb2), .vtotal(16'hFFFF),
    .dpyint(16'd0), .display_enable(1'b1), .noninterlaced(1'b1),
    .disable_external_video(1'b0), .hsync_direction(1'b0),
    .hsync_n_i(!hs1), .vsync_n_i(!vs1),
    .hcount_load(1'b0), .hcount_wdata('0), .vcount_load(1'b0), .vcount_wdata('0),
    .hcount(hc2), .vcount(vc2), .hsync(hs2), .vsync(vs2),
    .hblank(hb2), .vblank(vb2), .blank(bl2), .hsync_oe(), .vsync_oe(),
    .hblank_start(), .dpyint_pulse(), .odd_field()
  );

  task automatic run(input string name,
                     input int h_es, input int h_eb, input int h_sb, input int h_tot,
                     input int v_es, input int v_eb, input int v_sb, input int v_tot);
    int unsigned frame, bad, checked, vdiff;
    begin
      hes1 = 16'(h_es); heb1 = 16'(h_eb); hsb1 = 16'(h_sb); htot1 = 16'(h_tot);
      ves1 = 16'(v_es); veb1 = 16'(v_eb); vsb1 = 16'(v_sb); vtot1 = 16'(v_tot);
      // Table 9-1
      heb2 = 16'(h_eb - 3); hsb2 = 16'(h_sb - 3);
      hes2 = 16'((h_eb - 3 + h_sb - 3) / 2);
      veb2 = 16'(v_eb); vsb2 = 16'(v_sb); ves2 = 16'((v_eb + v_sb) / 2);
      rst = 1'b1; repeat (4) @(posedge clk); @(negedge clk); rst = 1'b0;
      // let GSP #2 lock: two full frames
      repeat (2 * (h_tot + 1) * (v_tot + 1)) @(posedge clk);
      bad = 0; checked = 0; vdiff = 0;
      repeat (4 * (h_tot + 1) * (v_tot + 1)) begin
        @(negedge clk);
        checked++;
        if (vb1 !== vb2) begin
          vdiff++;
          if (!hb1 || !hb2) begin
            $display("  %s: VBLANK differs outside horizontal blanking (H=%0d V=%0d)", name, hc1, vc1);
            bad++;
          end
        end
        if (bl1 !== bl2 || hb1 !== hb2) begin
          if (bad < 5)
            $display("  %s: GSP1 H=%0d V=%0d blank %0b/%0b/%0b  GSP2 H=%0d V=%0d blank %0b/%0b/%0b",
                     name, hc1, vc1, bl1, hb1, vb1, hc2, vc2, bl2, hb2, vb2);
          bad++;
        end
      end
      if (bad != 0) begin
        $display("FAIL: %s: BLANK differs in %0d of %0d clocks", name, bad, checked);
        failures++;
      end else
        $display("ok: %s: BLANK and HBLANK equal on all %0d clocks (VBLANK flags differ in %0d, all in horizontal blanking)",
                 name, checked, vdiff);
    end
  endtask

  initial begin
    run("short lines", 3, 6, 28, 31, 1, 3, 20, 23);
    run("wider blanking", 10, 20, 100, 127, 2, 5, 40, 47);
    run("Exterminator", 'h9, 'h28, 'h128, 'h13D, 'hE, 'h10, 'h100, 'h107);
    if (failures == 0)
      $display("TEST_RESULT: PASS (two GSPs, 9.9.1/Table 9-1: BLANK switches in unison)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end
  initial begin
    #50_000_000;
    $display("TEST_RESULT: FAIL: tb_two_gsp_sync hard timeout");
    $finish;
  end
endmodule
