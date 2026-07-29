// -----------------------------------------------------------------------------
// tb_bus_arbiter_rmw.sv
//
// Integration regression for the field sequencer's CPU RMW lock and the
// fixed-priority arbiter. Checks indivisibility, preemption between different
// field words, and the User's Guide §11.3 HOLD restart exception.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_bus_arbiter_rmw;
  import tms34010_pkg::*;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  logic                              field_req;
  logic                              field_we;
  logic [ADDR_WIDTH-1:0]             field_addr;
  logic [FIELD_SIZE_WIDTH-1:0]       field_size;
  logic [DATA_WIDTH-1:0]             field_wdata;
  logic [DATA_WIDTH-1:0]             field_rdata;
  logic                              field_ack;
  logic                              cpu_req;
  logic                              cpu_we;
  logic [ADDR_WIDTH-1:0]             cpu_addr;
  local_word_t                       cpu_wdata;
  local_word_t                       cpu_rdata;
  logic                              cpu_ack;
  logic                              cpu_rmw_lock;
  logic                              cpu_restart;

  logic                              hold_req;
  logic                              hold_ack;
  logic                              screen_req;
  logic [13:0]                       screen_srfaddr;
  logic [15:0]                       screen_dpytap;
  logic                              screen_ack;
  logic                              dram_req;
  logic [7:0]                        dram_row;
  logic                              dram_cbr;
  logic                              dram_ack;
  logic                              host_req;
  logic                              host_we;
  logic [ADDR_WIDTH-1:0]             host_addr;
  local_word_t                       host_wdata;
  local_word_t                       host_rdata;
  logic                              host_ack;

  logic                              cycle_req;
  local_cycle_kind_t                 cycle_kind;
  logic [ADDR_WIDTH-1:0]             cycle_addr;
  local_word_t                       cycle_wdata;
  logic [13:0]                       cycle_srfaddr;
  logic [15:0]                       cycle_dpytap;
  logic [7:0]                        cycle_dram_row;
  local_word_t                       cycle_rdata;
  logic                              cycle_ack;

  tms34010_field_sequencer u_field (
    .clk             (clk),
    .rst             (rst),
    .field_req_i     (field_req),
    .field_we_i      (field_we),
    .field_addr_i    (field_addr),
    .field_size_i    (field_size),
    .field_wdata_i   (field_wdata),
    .field_rdata_o   (field_rdata),
    .field_ack_o     (field_ack),
    .word_req_o      (cpu_req),
    .word_we_o       (cpu_we),
    .word_addr_o     (cpu_addr),
    .word_wdata_o    (cpu_wdata),
    .word_rdata_i    (cpu_rdata),
    .word_ack_i      (cpu_ack),
    .word_restart_i  (cpu_restart),
    .word_rmw_lock_o (cpu_rmw_lock)
  );

  tms34010_bus_arbiter u_arbiter (
    .clk               (clk),
    .rst               (rst),
    .hold_req_i        (hold_req),
    .hold_ack_o        (hold_ack),
    .screen_req_i      (screen_req),
    .screen_srfaddr_i  (screen_srfaddr),
    .screen_dpytap_i   (screen_dpytap),
    .screen_org_i      (1'b0),
    .screen_ack_o      (screen_ack),
    .dram_req_i        (dram_req),
    .dram_row_i        (dram_row),
    .dram_cbr_i        (dram_cbr),
    .dram_ack_o        (dram_ack),
    .host_req_i        (host_req),
    .host_we_i         (host_we),
    .host_addr_i       (host_addr),
    .host_wdata_i      (host_wdata),
    .host_rdata_o      (host_rdata),
    .host_ack_o        (host_ack),
    .cpu_req_i         (cpu_req),
    .cpu_we_i          (cpu_we),
    .cpu_addr_i        (cpu_addr),
    .cpu_wdata_i       (cpu_wdata),
    .cpu_io_i          (1'b0),
    .cpu_io_rdata_i    (16'h0000),
    .cpu_iaq_i         (1'b0),
    .cpu_rmw_lock_i    (cpu_rmw_lock),
    .cpu_rdata_o       (cpu_rdata),
    .cpu_ack_o         (cpu_ack),
    .cpu_restart_o     (cpu_restart),
    .cycle_req_o       (cycle_req),
    .cycle_kind_o      (cycle_kind),
    .cycle_addr_o      (cycle_addr),
    .cycle_wdata_o     (cycle_wdata),
    .cycle_io_rdata_o  (),
    .cycle_iaq_o       (),
    .cycle_srfaddr_o   (cycle_srfaddr),
    .cycle_dpytap_o    (cycle_dpytap),
    .cycle_screen_org_o(),
    .cycle_dram_row_o  (cycle_dram_row),
    .cycle_rdata_i     (cycle_rdata),
    .cycle_ack_i       (cycle_ack)
  );

  int unsigned failures;
  int unsigned read_count;
  int unsigned write_count;

  always_ff @(posedge clk) begin
    if (rst) begin
      read_count  <= 0;
      write_count <= 0;
    end else if (cycle_req && cycle_ack) begin
      if (cycle_kind == LOCAL_CYCLE_WORD_READ)
        read_count <= read_count + 1;
      else if (cycle_kind == LOCAL_CYCLE_WORD_WRITE)
        write_count <= write_count + 1;
    end
  end

  task automatic wait_cycle(
    input string             label,
    input local_cycle_kind_t expected_kind,
    input logic [ADDR_WIDTH-1:0] expected_addr
  );
    int unsigned watchdog;
    begin
      watchdog = 0;
      while ((cycle_req !== 1'b1)
             || (cycle_kind !== expected_kind)
             || (((expected_kind == LOCAL_CYCLE_WORD_READ)
                  || (expected_kind == LOCAL_CYCLE_WORD_WRITE))
                 && (cycle_addr !== expected_addr))) begin
        @(negedge clk);
        watchdog++;
        if (watchdog > 60) begin
          $display("TEST_RESULT: FAIL: %s timeout expected kind/addr=%0d/%08h actual=%0b/%0d/%08h",
                   label, expected_kind, expected_addr,
                   cycle_req, cycle_kind, cycle_addr);
          failures++;
          return;
        end
      end
    end
  endtask

  task automatic complete_cycle(input local_word_t rdata);
    begin
      cycle_rdata = rdata;
      cycle_ack   = 1'b1;
      @(negedge clk);
      cycle_ack   = 1'b0;
    end
  endtask

  task automatic wait_field_ack(input string label);
    int unsigned watchdog;
    begin
      watchdog = 0;
      while (field_ack !== 1'b1) begin
        @(negedge clk);
        watchdog++;
        if (watchdog > 80) begin
          $display("TEST_RESULT: FAIL: %s field acknowledgement timeout", label);
          failures++;
          return;
        end
      end
      field_req = 1'b0;
      @(negedge clk);
    end
  endtask

  initial begin : main
    int unsigned reads_before;
    int unsigned writes_before;

    failures       = 0;
    field_req      = 1'b0;
    field_we       = 1'b0;
    field_addr     = '0;
    field_size     = '0;
    field_wdata    = '0;
    hold_req       = 1'b0;
    screen_req     = 1'b0;
    screen_srfaddr = 14'h0000;
    screen_dpytap  = 16'h0000;
    dram_req       = 1'b0;
    dram_row       = 8'h00;
    dram_cbr       = 1'b0;
    host_req       = 1'b0;
    host_we        = 1'b0;
    host_addr      = '0;
    host_wdata     = '0;
    cycle_rdata    = '0;
    cycle_ack      = 1'b0;

    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    // A screen and host request arriving during the partial read must wait
    // until its matching write completes, despite their nominal priority.
    field_req   = 1'b1;
    field_we    = 1'b1;
    field_addr  = 32'd35;
    field_size  = 6'd5;
    field_wdata = 32'h0000_001B;
    wait_cycle("locked RMW read", LOCAL_CYCLE_WORD_READ, 32'd32);
    screen_req     = 1'b1;
    screen_srfaddr = 14'h0555;
    screen_dpytap  = 16'h0120;
    host_req       = 1'b1;
    host_we        = 1'b0;
    host_addr      = 32'h0000_0500;
    complete_cycle(16'hA55A);

    wait_cycle("locked RMW write", LOCAL_CYCLE_WORD_WRITE, 32'd32);
    if (cycle_wdata !== 16'hA5DA) begin
      $display("TEST_RESULT: FAIL: locked RMW merge expected=a5da actual=%04h",
               cycle_wdata);
      failures++;
    end
    complete_cycle('0);
    wait_field_ack("locked RMW");

    wait_cycle("screen after locked pair",
               LOCAL_CYCLE_SCREEN_REFRESH, '0);
    complete_cycle('0);
    screen_req = 1'b0;
    wait_cycle("host after screen", LOCAL_CYCLE_WORD_READ, 32'h0000_0500);
    complete_cycle(16'h1111);
    host_req = 1'b0;

    // Different words of one field are preemptable. Queue host during the
    // first word's write; it must run before the second word's partial read.
    field_req   = 1'b1;
    field_we    = 1'b1;
    field_addr  = 32'd264;
    field_size  = 6'd12;
    field_wdata = 32'h0000_0ABC;
    wait_cycle("first-word read", LOCAL_CYCLE_WORD_READ, 32'd256);
    complete_cycle(16'h0011);
    wait_cycle("first-word write", LOCAL_CYCLE_WORD_WRITE, 32'd256);
    if (cycle_wdata !== 16'hBC11) begin
      $display("TEST_RESULT: FAIL: first-word merge expected=bc11 actual=%04h",
               cycle_wdata);
      failures++;
    end
    host_req   = 1'b1;
    host_we    = 1'b1;
    host_addr  = 32'h0000_0600;
    host_wdata = 16'hDEAD;
    complete_cycle('0);

    wait_cycle("host between field words",
               LOCAL_CYCLE_WORD_WRITE, 32'h0000_0600);
    complete_cycle('0);
    host_req = 1'b0;
    wait_cycle("second-word read", LOCAL_CYCLE_WORD_READ, 32'd272);
    complete_cycle(16'h2220);
    wait_cycle("second-word write", LOCAL_CYCLE_WORD_WRITE, 32'd272);
    if (cycle_wdata !== 16'h222A) begin
      $display("TEST_RESULT: FAIL: second-word merge expected=222a actual=%04h",
               cycle_wdata);
      failures++;
    end
    complete_cycle('0);
    wait_field_ack("two-word RMW");

    // HOLD arriving during the read is accepted only after that active cycle
    // completes. The not-yet-issued write is suppressed, and the read repeats
    // after release so the merge uses the new memory contents.
    reads_before  = read_count;
    writes_before = write_count;
    field_req   = 1'b1;
    field_we    = 1'b1;
    field_addr  = 32'd35;
    field_size  = 6'd5;
    field_wdata = 32'h0000_001B;
    wait_cycle("pre-HOLD RMW read", LOCAL_CYCLE_WORD_READ, 32'd32);
    hold_req = 1'b1;
    complete_cycle(16'h0F0F);
    if (cpu_restart !== 1'b1) begin
      $display("TEST_RESULT: FAIL: HOLD did not request RMW restart");
      failures++;
    end
    @(negedge clk);
    if ((hold_ack !== 1'b1) || (cycle_req !== 1'b0)) begin
      $display("TEST_RESULT: FAIL: HOLD not acknowledged quiescently");
      failures++;
    end
    repeat (2) begin
      @(negedge clk);
      if ((hold_ack !== 1'b1) || (cycle_req !== 1'b0)) begin
        $display("TEST_RESULT: FAIL: HOLD did not retain the bus");
        failures++;
      end
    end

    hold_req = 1'b0;
    wait_cycle("restarted RMW read", LOCAL_CYCLE_WORD_READ, 32'd32);
    complete_cycle(16'hF0F0);
    wait_cycle("post-HOLD RMW write", LOCAL_CYCLE_WORD_WRITE, 32'd32);
    if (cycle_wdata !== 16'hF0D8) begin
      $display("TEST_RESULT: FAIL: restarted merge expected=f0d8 actual=%04h",
               cycle_wdata);
      failures++;
    end
    complete_cycle('0);
    wait_field_ack("HOLD-restarted RMW");

    if ((read_count - reads_before) != 2) begin
      $display("TEST_RESULT: FAIL: HOLD RMW expected two reads actual=%0d",
               read_count - reads_before);
      failures++;
    end
    if ((write_count - writes_before) != 1) begin
      $display("TEST_RESULT: FAIL: HOLD RMW expected one write actual=%0d",
               write_count - writes_before);
      failures++;
    end

    if (failures == 0)
      $display("TEST_RESULT: PASS (RMW reservation, inter-word preemption, HOLD restart)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #1_500_000;
    $display("TEST_RESULT: FAIL: tb_bus_arbiter_rmw hard timeout");
    $fatal(1);
  end

endmodule : tb_bus_arbiter_rmw
