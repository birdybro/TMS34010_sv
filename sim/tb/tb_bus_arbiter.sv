// -----------------------------------------------------------------------------
// tb_bus_arbiter.sv
//
// Focused fixed-priority local-bus arbitration regression. Checks the complete
// HOLD > screen > DRAM > host > CPU order, held ownership through controller
// stalls, response routing, and capture of a one-clock DRAM-refresh event.
// The simultaneous CPU client is an SRT pixel read, proving it survives every
// higher-priority client without losing or changing its MTR classification.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_bus_arbiter;
  import tms34010_pkg::*;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  logic                      hold_req;
  logic                      hold_ack;
  logic                      screen_req;
  logic [13:0]               screen_srfaddr;
  logic [15:0]               screen_dpytap;
  logic                      screen_org;
  logic                      screen_ack;
  logic                      dram_req;
  logic [7:0]                dram_row;
  logic                      dram_cbr;
  logic                      dram_ack;
  logic                      host_req;
  logic                      host_we;
  logic [ADDR_WIDTH-1:0]     host_addr;
  local_word_t               host_wdata;
  logic                      host_io;
  local_word_t               host_io_rdata;
  local_word_t               host_rdata;
  logic                      host_ack;
  logic                      cpu_req;
  logic                      cpu_we;
  logic [ADDR_WIDTH-1:0]     cpu_addr;
  local_word_t               cpu_wdata;
  logic                      cpu_io;
  local_word_t               cpu_io_rdata;
  logic                      cpu_iaq;
  logic                      cpu_srt;
  logic                      cpu_rmw_lock;
  local_word_t               cpu_rdata;
  logic                      cpu_ack;
  logic                      cpu_restart;
  logic                      cycle_req;
  local_cycle_kind_t         cycle_kind;
  logic [ADDR_WIDTH-1:0]     cycle_addr;
  local_word_t               cycle_wdata;
  local_word_t               cycle_io_rdata;
  logic                      cycle_iaq;
  logic [13:0]               cycle_srfaddr;
  logic [15:0]               cycle_dpytap;
  logic                      cycle_screen_org;
  logic [7:0]                cycle_dram_row;
  local_word_t               cycle_rdata;
  logic                      cycle_ack;

  tms34010_bus_arbiter u_dut (
    .clk               (clk),
    .rst               (rst),
    .hold_req_i        (hold_req),
    .hold_ack_o        (hold_ack),
    .screen_req_i      (screen_req),
    .screen_srfaddr_i  (screen_srfaddr),
    .screen_dpytap_i   (screen_dpytap),
    .screen_org_i      (screen_org),
    .screen_ack_o      (screen_ack),
    .dram_req_i        (dram_req),
    .dram_row_i        (dram_row),
    .dram_cbr_i        (dram_cbr),
    .dram_ack_o        (dram_ack),
    .host_req_i        (host_req),
    .host_we_i         (host_we),
    .host_addr_i       (host_addr),
    .host_wdata_i      (host_wdata),
    .host_io_i         (host_io),
    .host_io_rdata_i   (host_io_rdata),
    .host_rdata_o      (host_rdata),
    .host_ack_o        (host_ack),
    .cpu_req_i         (cpu_req),
    .cpu_we_i          (cpu_we),
    .cpu_addr_i        (cpu_addr),
    .cpu_wdata_i       (cpu_wdata),
    .cpu_io_i          (cpu_io),
    .cpu_io_rdata_i    (cpu_io_rdata),
    .cpu_iaq_i         (cpu_iaq),
    .cpu_srt_i         (cpu_srt),
    .cpu_rmw_lock_i    (cpu_rmw_lock),
    .cpu_rdata_o       (cpu_rdata),
    .cpu_ack_o         (cpu_ack),
    .cpu_restart_o     (cpu_restart),
    .cycle_req_o       (cycle_req),
    .cycle_kind_o      (cycle_kind),
    .cycle_addr_o      (cycle_addr),
    .cycle_wdata_o     (cycle_wdata),
    .cycle_io_rdata_o  (cycle_io_rdata),
    .cycle_iaq_o       (cycle_iaq),
    .cycle_srfaddr_o   (cycle_srfaddr),
    .cycle_dpytap_o    (cycle_dpytap),
    .cycle_screen_org_o(cycle_screen_org),
    .cycle_dram_row_o  (cycle_dram_row),
    .cycle_rdata_i     (cycle_rdata),
    .cycle_ack_i       (cycle_ack)
  );

  int unsigned failures;
  int unsigned protocol_failures_q;
  logic        cycle_open_q;
  local_cycle_kind_t held_kind_q;
  logic [ADDR_WIDTH-1:0] held_addr_q;
  local_word_t            held_wdata_q;
  local_word_t            held_io_rdata_q;
  logic                   held_iaq_q;
  logic [13:0]            held_srfaddr_q;
  logic [15:0]            held_dpytap_q;
  logic                   held_screen_org_q;
  logic [7:0]             held_dram_row_q;

  // The controller-facing request and every payload field must remain stable
  // from first assertion through the acknowledgement edge.
  always_ff @(posedge clk) begin
    if (rst) begin
      protocol_failures_q <= 0;
      cycle_open_q        <= 1'b0;
      held_kind_q         <= LOCAL_CYCLE_WORD_READ;
      held_addr_q         <= '0;
      held_wdata_q        <= '0;
      held_io_rdata_q     <= '0;
      held_iaq_q          <= 1'b0;
      held_srfaddr_q      <= '0;
      held_dpytap_q       <= '0;
      held_screen_org_q   <= 1'b0;
      held_dram_row_q     <= '0;
    end else if (!cycle_open_q) begin
      if (cycle_req) begin
        cycle_open_q    <= !cycle_ack;
        held_kind_q     <= cycle_kind;
        held_addr_q     <= cycle_addr;
        held_wdata_q    <= cycle_wdata;
        held_io_rdata_q <= cycle_io_rdata;
        held_iaq_q      <= cycle_iaq;
        held_srfaddr_q  <= cycle_srfaddr;
        held_dpytap_q   <= cycle_dpytap;
        held_screen_org_q <= cycle_screen_org;
        held_dram_row_q <= cycle_dram_row;
      end
    end else begin
      if (!cycle_req
          || (cycle_kind != held_kind_q)
          || (cycle_addr != held_addr_q)
          || (cycle_wdata != held_wdata_q)
          || (cycle_io_rdata != held_io_rdata_q)
          || (cycle_iaq != held_iaq_q)
          || (cycle_srfaddr != held_srfaddr_q)
          || (cycle_dpytap != held_dpytap_q)
          || (cycle_screen_org != held_screen_org_q)
          || (cycle_dram_row != held_dram_row_q)) begin
        protocol_failures_q <= protocol_failures_q + 1;
      end
      if (cycle_ack) cycle_open_q <= 1'b0;
    end
  end

  task automatic check_bit(
    input string label,
    input logic  actual,
    input logic  expected
  );
    begin
      if (actual !== expected) begin
        $display("TEST_RESULT: FAIL: %s expected=%0b actual=%0b",
                 label, expected, actual);
        failures++;
      end
    end
  endtask

  task automatic check_word(
    input string       label,
    input local_word_t actual,
    input local_word_t expected
  );
    begin
      if (actual !== expected) begin
        $display("TEST_RESULT: FAIL: %s expected=%04h actual=%04h",
                 label, expected, actual);
        failures++;
      end
    end
  endtask

  task automatic wait_cycle(
    input string             label,
    input local_cycle_kind_t expected_kind
  );
    int unsigned watchdog;
    begin
      watchdog = 0;
      while ((cycle_req !== 1'b1) || (cycle_kind !== expected_kind)) begin
        @(negedge clk);
        watchdog++;
        if (watchdog > 40) begin
          $display("TEST_RESULT: FAIL: %s timeout kind=%0d req/kind=%0b/%0d",
                   label, expected_kind, cycle_req, cycle_kind);
          failures++;
          return;
        end
      end
    end
  endtask

  task automatic ack_cycle(
    input string label,
    input logic  expect_screen,
    input logic  expect_dram,
    input logic  expect_host,
    input logic  expect_cpu
  );
    begin
      cycle_ack = 1'b1;
      #1;
      check_bit({label, " screen ack"}, screen_ack, expect_screen);
      check_bit({label, " DRAM ack"}, dram_ack, expect_dram);
      check_bit({label, " host ack"}, host_ack, expect_host);
      check_bit({label, " CPU ack"}, cpu_ack, expect_cpu);
      @(negedge clk);
      cycle_ack = 1'b0;
    end
  endtask

  initial begin : main
    failures       = 0;
    hold_req       = 1'b0;
    screen_req     = 1'b0;
    screen_srfaddr = 14'h0000;
    screen_dpytap  = 16'h0000;
    screen_org     = 1'b0;
    dram_req       = 1'b0;
    dram_row       = 8'h00;
    dram_cbr       = 1'b0;
    host_req       = 1'b0;
    host_we        = 1'b0;
    host_addr      = '0;
    host_wdata     = '0;
    host_io        = 1'b0;
    host_io_rdata  = '0;
    cpu_req        = 1'b0;
    cpu_we         = 1'b0;
    cpu_addr       = '0;
    cpu_wdata      = '0;
    cpu_io         = 1'b0;
    cpu_io_rdata   = '0;
    cpu_iaq        = 1'b0;
    cpu_srt        = 1'b0;
    cpu_rmw_lock   = 1'b0;
    cycle_rdata    = 16'h0000;
    cycle_ack      = 1'b0;

    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    @(negedge clk);
    check_bit("reset cycle request", cycle_req, 1'b0);
    check_bit("reset HOLD acknowledge", hold_ack, 1'b0);
    check_bit("reset CPU restart", cpu_restart, 1'b0);

    // Offer every client together. The DRAM request is deliberately only one
    // clock, proving that it remains pending while HOLD and screen win.
    hold_req       = 1'b1;
    screen_req     = 1'b1;
    screen_srfaddr = 14'h1234;
    screen_dpytap  = 16'h05A0;
    screen_org     = 1'b1;
    dram_req       = 1'b1;
    dram_row       = 8'hA5;
    dram_cbr       = 1'b0;
    host_req       = 1'b1;
    host_we        = 1'b1;
    host_addr      = 32'h0000_0200;
    host_wdata     = 16'hCAFE;
    cpu_req        = 1'b1;
    cpu_we         = 1'b0;
    cpu_addr       = 32'h0000_0300;
    cpu_iaq        = 1'b1;
    cpu_srt        = 1'b1;
    @(negedge clk);
    dram_req = 1'b0;
    check_bit("HOLD has highest priority", hold_ack, 1'b1);
    check_bit("HOLD suppresses physical cycle", cycle_req, 1'b0);
    repeat (2) begin
      @(negedge clk);
      check_bit("HOLD remains acknowledged", hold_ack, 1'b1);
      check_bit("HOLD remains cycle-free", cycle_req, 1'b0);
    end

    hold_req = 1'b0;
    wait_cycle("screen after HOLD", LOCAL_CYCLE_SCREEN_REFRESH);
    if ((cycle_srfaddr !== 14'h1234)
        || (cycle_dpytap !== 16'h05A0)
        || (cycle_screen_org !== 1'b1)) begin
      $display("TEST_RESULT: FAIL: screen payload expected=1234/05a0/1 actual=%04h/%04h/%0b",
               cycle_srfaddr, cycle_dpytap, cycle_screen_org);
      failures++;
    end
    ack_cycle("screen", 1'b1, 1'b0, 1'b0, 1'b0);
    screen_req = 1'b0;

    wait_cycle("captured DRAM after screen", LOCAL_CYCLE_DRAM_RAS);
    if (cycle_dram_row !== 8'hA5) begin
      $display("TEST_RESULT: FAIL: captured DRAM row expected=a5 actual=%02h",
               cycle_dram_row);
      failures++;
    end
    ack_cycle("DRAM", 1'b0, 1'b1, 1'b0, 1'b0);

    wait_cycle("host after DRAM", LOCAL_CYCLE_WORD_WRITE);
    if ((cycle_addr !== 32'h0000_0200)
        || (cycle_wdata !== 16'hCAFE)) begin
      $display("TEST_RESULT: FAIL: host payload expected=00000200/cafe actual=%08h/%04h",
               cycle_addr, cycle_wdata);
      failures++;
    end
    cycle_rdata = 16'h1357;
    ack_cycle("host", 1'b0, 1'b0, 1'b1, 1'b0);
    check_word("host response routing", host_rdata, 16'h1357);
    host_req = 1'b0;

    wait_cycle("CPU SRT pixel last", LOCAL_CYCLE_PIXEL_MTR);
    if (cycle_addr !== 32'h0000_0300) begin
      $display("TEST_RESULT: FAIL: CPU address expected=00000300 actual=%08h",
               cycle_addr);
      failures++;
    end
    check_bit("CPU SRT IAQ forced inactive", cycle_iaq, 1'b0);
    cycle_rdata = 16'h0000;
    ack_cycle("CPU", 1'b0, 1'b0, 1'b0, 1'b1);
    check_word("CPU MTR response routing", cpu_rdata, 16'h0000);
    cpu_req = 1'b0;
    cpu_srt = 1'b0;

    // Processor I/O bypasses word sequencing but retains the CPU priority and
    // completion route. Read data is on-chip payload, not external LAD data.
    cpu_req      = 1'b1;
    cpu_we       = 1'b0;
    cpu_io       = 1'b1;
    cpu_addr     = IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_PMASK) << 4);
    cpu_io_rdata = 16'hD00D;
    wait_cycle("CPU I/O read", LOCAL_CYCLE_IO_READ);
    check_word("CPU I/O read payload", cycle_io_rdata, 16'hD00D);
    check_bit("CPU I/O IAQ inactive", cycle_iaq, 1'b0);
    cycle_rdata = cycle_io_rdata;
    ack_cycle("CPU I/O read", 1'b0, 1'b0, 1'b0, 1'b1);
    check_word("CPU I/O response routing", cpu_rdata, 16'hD00D);
    cpu_req = 1'b0;
    @(negedge clk);

    cpu_req   = 1'b1;
    cpu_we    = 1'b1;
    cpu_srt   = 1'b1;
    cpu_addr  = IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_PMASK) << 4);
    cpu_wdata = 16'hBEEF;
    wait_cycle("CPU I/O write", LOCAL_CYCLE_IO_WRITE);
    check_word("CPU I/O write payload", cycle_wdata, 16'hBEEF);
    check_bit("CPU I/O takes precedence over SRT", cycle_iaq, 1'b0);
    ack_cycle("CPU I/O write", 1'b0, 1'b0, 1'b0, 1'b1);
    cpu_req = 1'b0;
    cpu_we  = 1'b0;
    cpu_io  = 1'b0;
    @(negedge clk);

    // DPYCTL.SRT changes only graphics pixel reads and writes into explicit
    // VRAM register transfers. The ordinary address is preserved and IAQ is
    // always inactive for both transfer directions.
    cpu_req  = 1'b1;
    cpu_addr = 32'h1234_5670;
    cpu_iaq  = 1'b1;
    wait_cycle("CPU pixel MTR", LOCAL_CYCLE_PIXEL_MTR);
    if (cycle_addr !== 32'h1234_5670) begin
      $display("TEST_RESULT: FAIL: CPU MTR address expected=12345670 actual=%08h",
               cycle_addr);
      failures++;
    end
    check_bit("CPU MTR IAQ inactive", cycle_iaq, 1'b0);
    cycle_rdata = 16'h0000;
    ack_cycle("CPU pixel MTR", 1'b0, 1'b0, 1'b0, 1'b1);
    check_word("CPU MTR response routing", cpu_rdata, 16'h0000);
    cpu_req = 1'b0;
    @(negedge clk);

    cpu_req   = 1'b1;
    cpu_we    = 1'b1;
    cpu_addr  = 32'h2A5B_C9D0;
    cpu_wdata = 16'hCAFE;
    wait_cycle("CPU pixel RTM", LOCAL_CYCLE_PIXEL_RTM);
    if (cycle_addr !== 32'h2A5B_C9D0) begin
      $display("TEST_RESULT: FAIL: CPU RTM address expected=2a5bc9d0 actual=%08h",
               cycle_addr);
      failures++;
    end
    check_word("CPU RTM payload remains available", cycle_wdata, 16'hCAFE);
    check_bit("CPU RTM IAQ inactive", cycle_iaq, 1'b0);
    ack_cycle("CPU pixel RTM", 1'b0, 1'b0, 1'b0, 1'b1);
    cpu_req = 1'b0;
    cpu_we  = 1'b0;
    cpu_srt = 1'b0;

    // Host-indirect I/O retains host priority and completion routing, but
    // selects the special cycle kinds. Live internal read data is sampled
    // when the host wins and must not change during a stalled command.
    host_req      = 1'b1;
    host_we       = 1'b0;
    host_io       = 1'b1;
    host_addr     = IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_PSIZE) << 4);
    host_io_rdata = 16'hA55A;
    wait_cycle("host I/O read", LOCAL_CYCLE_IO_READ);
    check_word("host I/O read payload", cycle_io_rdata, 16'hA55A);
    host_io_rdata = 16'hFFFF;
    @(negedge clk);
    check_word("host I/O sampled payload remains stable",
               cycle_io_rdata, 16'hA55A);
    cycle_rdata = cycle_io_rdata;
    ack_cycle("host I/O read", 1'b0, 1'b0, 1'b1, 1'b0);
    check_word("host I/O response routing", host_rdata, 16'hA55A);
    host_req = 1'b0;
    @(negedge clk);

    host_req   = 1'b1;
    host_we    = 1'b1;
    host_addr  = IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_PSIZE) << 4);
    host_wdata = 16'h1234;
    wait_cycle("host I/O write", LOCAL_CYCLE_IO_WRITE);
    check_word("host I/O write payload", cycle_wdata, 16'h1234);
    check_bit("host I/O IAQ inactive", cycle_iaq, 1'b0);
    ack_cycle("host I/O write", 1'b0, 1'b0, 1'b1, 1'b0);
    host_req = 1'b0;
    host_we  = 1'b0;
    host_io  = 1'b0;

    // A stalled host cycle must finish even when screen and a pulsed DRAM
    // refresh arrive. Payload stability is also checked by the monitor above.
    host_req   = 1'b1;
    host_we    = 1'b0;
    host_addr  = 32'h0000_0440;
    host_wdata = 16'h55AA;
    wait_cycle("stalled host", LOCAL_CYCLE_WORD_READ);
    screen_req     = 1'b1;
    screen_srfaddr = 14'h2BCD;
    screen_dpytap  = 16'h03C0;
    screen_org     = 1'b0;
    dram_req       = 1'b1;
    dram_row       = 8'h3C;
    dram_cbr       = 1'b1;
    repeat (2) begin
      @(negedge clk);
      dram_req = 1'b0;
      check_bit("higher priority cannot truncate host", cycle_req, 1'b1);
      if ((cycle_kind !== LOCAL_CYCLE_WORD_READ)
          || (cycle_addr !== 32'h0000_0440)) begin
        $display("TEST_RESULT: FAIL: stalled host owner/payload changed");
        failures++;
      end
    end
    ack_cycle("stalled host", 1'b0, 1'b0, 1'b1, 1'b0);
    host_req = 1'b0;

    wait_cycle("queued screen", LOCAL_CYCLE_SCREEN_REFRESH);
    ack_cycle("queued screen", 1'b1, 1'b0, 1'b0, 1'b0);
    screen_req = 1'b0;

    wait_cycle("queued CBR refresh", LOCAL_CYCLE_DRAM_CBR);
    if (cycle_dram_row !== 8'h3C) begin
      $display("TEST_RESULT: FAIL: queued CBR row expected=3c actual=%02h",
               cycle_dram_row);
      failures++;
    end
    // A new refresh event on the old cycle's completion edge must remain
    // pending rather than being lost with the retired event.
    dram_req = 1'b1;
    dram_row = 8'h7E;
    dram_cbr = 1'b0;
    ack_cycle("queued CBR", 1'b0, 1'b1, 1'b0, 1'b0);
    dram_req = 1'b0;

    wait_cycle("same-edge replacement refresh", LOCAL_CYCLE_DRAM_RAS);
    if (cycle_dram_row !== 8'h7E) begin
      $display("TEST_RESULT: FAIL: replacement DRAM row expected=7e actual=%02h",
               cycle_dram_row);
      failures++;
    end
    ack_cycle("replacement DRAM", 1'b0, 1'b1, 1'b0, 1'b0);

    repeat (2) @(negedge clk);
    check_bit("arbiter returns idle", cycle_req, 1'b0);
    if (protocol_failures_q != 0) begin
      $display("TEST_RESULT: FAIL: %0d controller payload stability violation(s)",
               protocol_failures_q);
      failures++;
    end

    if (failures == 0)
      $display("TEST_RESULT: PASS (fixed priority, held grant, response routing, DRAM retention)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #1_000_000;
    $display("TEST_RESULT: FAIL: tb_bus_arbiter hard timeout");
    $fatal(1);
  end

endmodule : tb_bus_arbiter
