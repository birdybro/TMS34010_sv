// -----------------------------------------------------------------------------
// tb_fpga_refresh_ratio.sv
//
// Final-board clock-ratio proof for the architected minimum DRAM-refresh
// interval. A real REFCNT generator (RR=00), integrated memory fabric,
// core/8x MCP bridge, and original-pin phase engine run at the Task 0160
// 50/200 MHz clocks while an independent 50 MHz VCLK is kept running.
//
// With HOLD inactive and LRDY continuously ready, every one-clock REFCNT
// underflow event must survive arbitration/CDC and complete a physical
// refresh cycle before the next minimum-interval event 32 core clocks later.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_fpga_refresh_ratio;
  import tms34010_pkg::*;

  localparam int unsigned MIN_REFRESH_INTERVAL = 32;
  localparam int unsigned EVENT_COUNT = 4;

  logic core_clk = 1'b0;
  logic bus_clk8x = 1'b0;
  logic vclk = 1'b0;
  logic rst = 1'b1;

  logic [15:0] refcnt;
  logic [7:0] refresh_row;
  logic refresh_req;
  logic refcnt_load;
  logic [1:0] refresh_rr;

  logic fabric_req;
  local_cycle_kind_t fabric_kind;
  logic [ADDR_WIDTH-1:0] fabric_addr;
  local_word_t fabric_wdata;
  local_word_t fabric_io_rdata;
  logic fabric_iaq;
  logic [13:0] fabric_srfaddr;
  logic [15:0] fabric_dpytap;
  logic fabric_screen_org;
  logic [7:0] fabric_dram_row;
  local_word_t fabric_rdata;
  logic fabric_ack;

  local_cycle_cmd_t bridge_src_cmd;
  local_cycle_cmd_t bridge_dst_cmd;
  logic bridge_dst_req;
  local_word_t local_rdata;
  logic local_ack;
  logic local_busy;
  logic init_done;
  local_subphase_t subphase;
  logic ras_n;
  logic lal_n;
  logic cas_n;

  integer failures = 0;
  integer core_ticks = 0;
  integer event_count = 0;
  integer service_count = 0;
  integer maximum_latency = 0;
  integer event_tick [0:EVENT_COUNT-1];
  logic [7:0] event_row [0:EVENT_COUNT-1];
  logic vclk_seen = 1'b0;

  // Final PLL outputs: core=50 MHz, local phase engine=200 MHz, VCLK=50 MHz.
  always #10 core_clk = ~core_clk;
  always #2.5 bus_clk8x = ~bus_clk8x;
  always #10 vclk = ~vclk;

  tms34010_refresh u_refresh (
    .clk          (core_clk),
    .rst          (rst),
    .rr           (refresh_rr),
    .refcnt_load  (refcnt_load),
    .refcnt_wdata ({8'h40, 6'd0, 2'b00}),
    .refcnt       (refcnt),
    .refresh_row  (refresh_row),
    .refresh_req  (refresh_req)
  );

  tms34010_memory_fabric u_fabric (
    .clk                  (core_clk),
    .rst                  (rst),
    .cpu_field_req_i      (1'b0),
    .cpu_field_we_i       (1'b0),
    .cpu_field_addr_i     ('0),
    .cpu_field_size_i     ('0),
    .cpu_field_wdata_i    ('0),
    .cpu_field_iaq_i      (1'b0),
    .cpu_field_srt_i      (1'b0),
    .cpu_field_is_io_i    (1'b0),
    .cpu_field_io_we_i    (1'b0),
    .cpu_field_io_rdata_i ('0),
    .cpu_field_rdata_o    (),
    .cpu_field_ack_o      (),
    .host_req_i           (1'b0),
    .host_we_i            (1'b0),
    .host_addr_i          ('0),
    .host_wdata_i         ('0),
    .host_is_io_i         (1'b0),
    .host_io_rdata_i      ('0),
    .host_rdata_o         (),
    .host_ack_o           (),
    .screen_req_i         (1'b0),
    .screen_srfaddr_i     ('0),
    .screen_dpytap_i      ('0),
    .screen_org_i         (1'b0),
    .screen_ack_o         (),
    .dram_req_i           (refresh_req),
    .dram_row_i           (refresh_row),
    .dram_cbr_i           (1'b0),
    .hold_req_i           (1'b0),
    .hold_ack_o           (),
    .cycle_req_o          (fabric_req),
    .cycle_kind_o         (fabric_kind),
    .cycle_addr_o         (fabric_addr),
    .cycle_wdata_o        (fabric_wdata),
    .cycle_io_rdata_o     (fabric_io_rdata),
    .cycle_iaq_o          (fabric_iaq),
    .cycle_srfaddr_o      (fabric_srfaddr),
    .cycle_dpytap_o       (fabric_dpytap),
    .cycle_screen_org_o   (fabric_screen_org),
    .cycle_dram_row_o     (fabric_dram_row),
    .cycle_rdata_i        (fabric_rdata),
    .cycle_ack_i          (fabric_ack)
  );

  always_comb begin
    bridge_src_cmd            = '0;
    bridge_src_cmd.kind       = fabric_kind;
    bridge_src_cmd.addr       = fabric_addr;
    bridge_src_cmd.wdata      = fabric_wdata;
    bridge_src_cmd.io_rdata   = fabric_io_rdata;
    bridge_src_cmd.iaq        = fabric_iaq;
    bridge_src_cmd.srfaddr    = fabric_srfaddr;
    bridge_src_cmd.dpytap     = fabric_dpytap;
    bridge_src_cmd.screen_org = fabric_screen_org;
    bridge_src_cmd.dram_row   = fabric_dram_row;
  end

  tms34010_local_bus_bridge u_bridge (
    .src_clk_i   (core_clk),
    .src_rst_i   (rst),
    .src_req_i   (fabric_req),
    .src_cmd_i   (bridge_src_cmd),
    .src_rdata_o (fabric_rdata),
    .src_ack_o   (fabric_ack),
    .src_busy_o  (),
    .dst_clk_i   (bus_clk8x),
    .dst_rst_i   (rst),
    .dst_req_o   (bridge_dst_req),
    .dst_cmd_o   (bridge_dst_cmd),
    .dst_rdata_i (local_rdata),
    .dst_ack_i   (local_ack)
  );

  tms34010_local_bus u_local_bus (
    .clk8x_i             (bus_clk8x),
    .rst                 (rst),
    .cycle_req_i         (bridge_dst_req),
    .cycle_kind_i        (bridge_dst_cmd.kind),
    .cycle_addr_i        (bridge_dst_cmd.addr),
    .cycle_wdata_i       (bridge_dst_cmd.wdata),
    .cycle_iaq_i         (bridge_dst_cmd.iaq),
    .cycle_srfaddr_i     (bridge_dst_cmd.srfaddr),
    .cycle_dpytap_i      (bridge_dst_cmd.dpytap),
    .cycle_screen_org_i  (bridge_dst_cmd.screen_org),
    .cycle_dram_row_i    (bridge_dst_cmd.dram_row),
    .io_rdata_i          (bridge_dst_cmd.io_rdata),
    .cycle_rdata_o       (local_rdata),
    .cycle_ack_o         (local_ack),
    .cycle_busy_o        (local_busy),
    .init_done_o         (init_done),
    .hold_n_i            (1'b1),
    .hold_req_o          (),
    .hold_grant_i        (1'b0),
    .hlda_n_o            (),
    .lrdy_i              (1'b1),
    .lad_i               ('0),
    .lad_o               (),
    .lad_oe_o            (),
    .lclk1_o             (),
    .lclk2_o             (),
    .ras_n_o             (ras_n),
    .lal_n_o             (lal_n),
    .cas_n_o             (cas_n),
    .we_n_o              (),
    .tr_qe_n_o           (),
    .den_n_o             (),
    .ddout_o             (),
    .ras_oe_o            (),
    .lal_oe_o            (),
    .cas_oe_o            (),
    .we_oe_o             (),
    .tr_qe_oe_o          (),
    .den_oe_o            (),
    .ddout_oe_o          (),
    .subphase_o          (subphase)
  );

  task automatic check(input logic condition, input string message);
    if (!condition) begin
      $display("CHECK_FAIL: %s at t=%0t core_tick=%0d phase=%0d",
               message, $time, core_ticks, subphase);
      failures++;
    end
  endtask

  always @(posedge vclk) begin
    if (!rst)
      vclk_seen = 1'b1;
  end

  always @(posedge core_clk) begin
    integer latency;

    if (rst) begin
      core_ticks = 0;
    end else begin
      core_ticks++;

      if (refresh_req && (event_count < EVENT_COUNT)) begin
        event_tick[event_count] = core_ticks;
        event_row[event_count] = refresh_row;
        event_count++;
      end

      if (fabric_ack
          && ((fabric_kind == LOCAL_CYCLE_DRAM_RAS)
              || (fabric_kind == LOCAL_CYCLE_DRAM_CBR))) begin
        check(service_count < event_count,
              "physical refresh completed without a pending event");
        if (service_count < event_count) begin
          latency = core_ticks - event_tick[service_count];
          check(latency < MIN_REFRESH_INTERVAL,
                "pending refresh missed the next 32-clock deadline");
          check(fabric_kind == LOCAL_CYCLE_DRAM_RAS,
                "RR test unexpectedly selected CAS-before-RAS");
          check(fabric_dram_row == event_row[service_count],
                "captured refresh row changed before physical completion");
          if (latency > maximum_latency)
            maximum_latency = latency;
          service_count++;
        end
      end
    end
  end

  initial begin
    refcnt_load = 1'b0;
    refresh_rr = 2'b11;

    repeat (5) @(posedge core_clk);
    @(negedge core_clk);
    rst = 1'b0;

    wait (init_done && !local_busy);

    // Load RINTVL=0. RR=00 requests immediately, then exactly every 32 core
    // clocks because the six-bit interval subtracts two each clock.
    @(negedge core_clk);
    refresh_rr = 2'b00;
    refcnt_load = 1'b1;
    @(negedge core_clk);
    refcnt_load = 1'b0;

    wait (service_count == EVENT_COUNT);
    @(negedge core_clk);

    check(event_count == EVENT_COUNT,
          "did not observe four minimum-interval refresh events");
    check(service_count == EVENT_COUNT,
          "not every pending refresh reached physical completion");
    check(maximum_latency < MIN_REFRESH_INTERVAL,
          "maximum service latency violated the refresh interval");
    check(vclk_seen, "independent final 50 MHz VCLK did not run");
    check(ras_n && lal_n && cas_n,
          "local control pins did not return inactive after refresh");

    if (failures == 0)
      $display("TEST_RESULT: PASS (50/200/50 MHz refresh service: %0d events, max %0d core clocks < 32)",
               service_count, maximum_latency);
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin
    #100_000;
    $display("TEST_RESULT: FAIL: tb_fpga_refresh_ratio hard timeout");
    $fatal(1);
  end

endmodule : tb_fpga_refresh_ratio

`default_nettype wire
