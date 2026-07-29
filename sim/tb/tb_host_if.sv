// -----------------------------------------------------------------------------
// tb_host_if.sv
//
// Direct regression for the synchronous host register/indirect-memory engine
// (1988 TMS34010 User's Guide §10.2 and §10.3.3, pages 10-2 through 10-21).
//
// Covers processor no-side-effect access, HSTCTL pass-through, LBL=0/1
// byte-last triggering, address prefetch, INCR/INCW ordering and wraparound,
// HSTDATA buffering, held local requests, and host backpressure.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_host_if;
  import tms34010_pkg::*;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  logic                        host_req;
  logic                        host_we;
  host_reg_sel_t               host_reg;
  logic [1:0]                  host_be;
  local_word_t                 host_wdata;
  local_word_t                 host_rdata;
  logic                        host_ack;
  logic                        host_busy;

  logic                        ctl_we;
  logic [1:0]                  ctl_be;
  local_word_t                 ctl_wdata;
  local_word_t                 ctl_rdata;
  local_word_t                 hstctlh;

  logic                        cpu_we;
  host_reg_sel_t               cpu_reg;
  local_word_t                 cpu_wdata;
  local_word_t                 cpu_rdata;

  logic                        local_req;
  logic                        local_we;
  logic [ADDR_WIDTH-1:0]       local_addr;
  local_word_t                 local_wdata;
  local_word_t                 local_rdata;
  logic                        local_ack;

  tms34010_host_if u_dut (
    .clk           (clk),
    .rst           (rst),
    .host_req_i    (host_req),
    .host_we_i     (host_we),
    .host_reg_i    (host_reg),
    .host_be_i     (host_be),
    .host_wdata_i  (host_wdata),
    .host_rdata_o  (host_rdata),
    .host_ack_o    (host_ack),
    .host_busy_o   (host_busy),
    .ctl_we_o      (ctl_we),
    .ctl_be_o      (ctl_be),
    .ctl_wdata_o   (ctl_wdata),
    .ctl_rdata_i   (ctl_rdata),
    .hstctlh_i     (hstctlh),
    .cpu_we_i      (cpu_we),
    .cpu_reg_i     (cpu_reg),
    .cpu_wdata_i   (cpu_wdata),
    .cpu_rdata_o   (cpu_rdata),
    .local_req_o   (local_req),
    .local_we_o    (local_we),
    .local_addr_o  (local_addr),
    .local_wdata_o (local_wdata),
    .local_rdata_i (local_rdata),
    .local_ack_i   (local_ack)
  );

  int unsigned failures;
  int unsigned ctl_write_count;
  logic [1:0]  last_ctl_be;
  local_word_t last_ctl_wdata;

  always @(posedge clk) begin
    if (rst) begin
      ctl_write_count <= 0;
      last_ctl_be      <= 2'b00;
      last_ctl_wdata   <= '0;
    end else if (ctl_we) begin
      ctl_write_count <= ctl_write_count + 1;
      last_ctl_be      <= ctl_be;
      last_ctl_wdata   <= ctl_wdata;
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

  task automatic check_addr(
    input string                   label,
    input logic [ADDR_WIDTH-1:0]   actual,
    input logic [ADDR_WIDTH-1:0]   expected
  );
    begin
      if (actual !== expected) begin
        $display("TEST_RESULT: FAIL: %s expected=%08h actual=%08h",
                 label, expected, actual);
        failures++;
      end
    end
  endtask

  task automatic cpu_write(
    input host_reg_sel_t write_reg,
    input local_word_t   write_data
  );
    begin
      @(negedge clk);
      cpu_we    = 1'b1;
      cpu_reg   = write_reg;
      cpu_wdata = write_data;
      @(negedge clk);
      cpu_we = 1'b0;
    end
  endtask

  task automatic cpu_check(
    input string         label,
    input host_reg_sel_t read_reg,
    input local_word_t   expected
  );
    begin
      cpu_reg = read_reg;
      #1;
      check_word(label, cpu_rdata, expected);
    end
  endtask

  task automatic host_access(
    input  logic          write_access,
    input  host_reg_sel_t selected_reg,
    input  logic [1:0]    byte_enable,
    input  local_word_t   write_data,
    output local_word_t   read_data
  );
    int unsigned wait_cycles;
    begin
      @(negedge clk);
      host_req   = 1'b1;
      host_we    = write_access;
      host_reg   = selected_reg;
      host_be    = byte_enable;
      host_wdata = write_data;

      wait_cycles = 0;
      while (!host_ack && (wait_cycles < 100)) begin
        @(posedge clk);
        #1;
        wait_cycles++;
      end
      if (!host_ack) begin
        $display("TEST_RESULT: FAIL: host access timed out");
        failures++;
      end
      read_data = host_rdata;

      @(negedge clk);
      host_req = 1'b0;
      host_we  = 1'b0;
      host_be  = 2'b00;
      @(posedge clk);
      #1;
    end
  endtask

  task automatic complete_local(
    input string                   label,
    input logic                    expected_we,
    input logic [ADDR_WIDTH-1:0]   expected_addr,
    input local_word_t             expected_wdata,
    input local_word_t             response_data,
    input int unsigned             stall_cycles
  );
    logic [ADDR_WIDTH-1:0] held_addr;
    logic                  held_we;
    local_word_t           held_wdata;
    begin
      if (!local_req) begin
        $display("TEST_RESULT: FAIL: %s local request was not asserted",
                 label);
        failures++;
      end
      held_addr  = local_addr;
      held_we    = local_we;
      held_wdata = local_wdata;
      check_bit ({label, " write direction"}, held_we, expected_we);
      check_addr({label, " address"}, held_addr, expected_addr);
      if (expected_we)
        check_word({label, " write data"}, held_wdata, expected_wdata);

      repeat (stall_cycles) begin
        @(posedge clk);
        #1;
        check_bit ({label, " request held"}, local_req, 1'b1);
        check_bit ({label, " direction held"}, local_we, held_we);
        check_addr({label, " address held"}, local_addr, held_addr);
        check_word({label, " data held"}, local_wdata, held_wdata);
      end

      @(negedge clk);
      local_rdata = response_data;
      local_ack   = 1'b1;
      @(posedge clk);
      #1;
      @(negedge clk);
      local_ack = 1'b0;
      @(posedge clk);
      #1;
      check_bit({label, " request retired"}, local_req, 1'b0);
    end
  endtask

  initial begin : main
    local_word_t rd;
    int unsigned ctl_count_before;

    failures       = 0;
    host_req       = 1'b0;
    host_we        = 1'b0;
    host_reg       = HOST_REG_HSTADRL;
    host_be        = 2'b00;
    host_wdata     = '0;
    ctl_rdata      = 16'hA55A;
    hstctlh        = '0;
    cpu_we         = 1'b0;
    cpu_reg        = HOST_REG_HSTADRL;
    cpu_wdata      = '0;
    local_rdata    = '0;
    local_ack      = 1'b0;

    repeat (3) @(posedge clk);
    #1;
    check_bit("reset host ack", host_ack, 1'b0);
    check_bit("reset host busy", host_busy, 1'b0);
    check_bit("reset local request", local_req, 1'b0);
    cpu_check("reset HSTADRL", HOST_REG_HSTADRL, 16'h0000);
    cpu_check("reset HSTADRH", HOST_REG_HSTADRH, 16'h0000);
    cpu_check("reset HSTDATA", HOST_REG_HSTDATA, 16'h0000);
    rst = 1'b0;

    // Processor accesses are plain register operations. HSTADR remains
    // word-aligned and none of these accesses initiates a local cycle.
    cpu_write(HOST_REG_HSTADRL, 16'h123F);
    cpu_write(HOST_REG_HSTADRH, 16'hABCD);
    cpu_write(HOST_REG_HSTDATA, 16'hBEEF);
    cpu_check("CPU HSTADRL alignment", HOST_REG_HSTADRL, 16'h1230);
    cpu_check("CPU HSTADRH write", HOST_REG_HSTADRH, 16'hABCD);
    cpu_check("CPU HSTDATA write", HOST_REG_HSTDATA, 16'hBEEF);
    check_bit("CPU accesses have no local side effect", local_req, 1'b0);

    // HSTCTL storage stays in the I/O block. Reads return its supplied view;
    // writes pass through exactly once with byte enables intact.
    host_access(1'b0, HOST_REG_HSTCTL, 2'b11, 16'h0000, rd);
    check_word("HSTCTL read pass-through", rd, 16'hA55A);
    ctl_count_before = ctl_write_count;
    host_access(1'b1, HOST_REG_HSTCTL, 2'b10, 16'h5A00, rd);
    check_addr("one HSTCTL write pulse",
               ADDR_WIDTH'(ctl_write_count),
               ADDR_WIDTH'(ctl_count_before + 1));
    check_word("HSTCTL write byte enable",
               {14'h0000, last_ctl_be}, 16'h0002);
    check_word("HSTCTL write data", last_ctl_wdata, 16'h5A00);

    // LBL=0: upper byte of HSTADRH is last. Earlier address bytes update
    // storage but do not start the prefetch.
    hstctlh = '0;
    host_access(1'b1, HOST_REG_HSTADRL, 2'b11, 16'h101F, rd);
    check_bit("LBL0 HSTADRL does not trigger", local_req, 1'b0);
    host_access(1'b1, HOST_REG_HSTADRH, 2'b01, 16'h0020, rd);
    check_bit("LBL0 HSTADRH low byte does not trigger", local_req, 1'b0);
    host_access(1'b1, HOST_REG_HSTADRH, 2'b10, 16'h3400, rd);
    complete_local("LBL0 address prefetch", 1'b0, 32'h3420_1010,
                   16'h0000, 16'h1111, 3);
    cpu_check("prefetch loads HSTDATA", HOST_REG_HSTDATA, 16'h1111);

    // INCR advances before the read initiated by an HSTDATA read. The host
    // receives the old prefetched word while the next word is requested.
    hstctlh = 16'h0001 << HSTCTL_INCR_BIT;
    host_access(1'b0, HOST_REG_HSTDATA, 2'b11, 16'h0000, rd);
    check_word("HSTDATA returns prefetched word", rd, 16'h1111);
    cpu_check("INCR pointer advances before read",
              HOST_REG_HSTADRL, 16'h1020);

    // A second host access presented while the local read is outstanding is
    // held off until the previous local side effect completes.
    @(negedge clk);
    host_req   = 1'b1;
    host_we    = 1'b0;
    host_reg   = HOST_REG_HSTCTL;
    host_be    = 2'b11;
    host_wdata = 16'h0000;
    repeat (2) begin
      @(posedge clk);
      #1;
      check_bit("busy host request is backpressured", host_ack, 1'b0);
      check_bit("busy output asserted", host_busy, 1'b1);
      check_addr("INCR local read address held",
                 local_addr, 32'h3420_1020);
    end
    @(negedge clk);
    local_rdata = 16'h2222;
    local_ack   = 1'b1;
    @(posedge clk);
    #1;
    @(negedge clk);
    local_ack = 1'b0;
    while (!host_ack) begin
      @(posedge clk);
      #1;
    end
    check_word("backpressured HSTCTL read response",
               host_rdata, 16'hA55A);
    @(negedge clk);
    host_req = 1'b0;
    host_be  = 2'b00;
    @(posedge clk);
    #1;
    check_bit("INCR request retired", local_req, 1'b0);
    cpu_check("INCR read updates HSTDATA",
              HOST_REG_HSTDATA, 16'h2222);

    // LBL=0 data writes launch only on the upper byte. INCW advances after
    // the acknowledged write, never before it.
    hstctlh = 16'h0001 << HSTCTL_INCW_BIT;
    host_access(1'b1, HOST_REG_HSTDATA, 2'b01, 16'h00AA, rd);
    check_bit("LBL0 HSTDATA low byte does not trigger", local_req, 1'b0);
    cpu_check("partial low HSTDATA merge",
              HOST_REG_HSTDATA, 16'h22AA);
    host_access(1'b1, HOST_REG_HSTDATA, 2'b10, 16'hBB00, rd);
    cpu_check("INCW pointer unchanged before write ack",
              HOST_REG_HSTADRL, 16'h1020);
    complete_local("LBL0 HSTDATA write", 1'b1, 32'h3420_1020,
                   16'hBBAA, 16'h0000, 2);
    cpu_check("INCW pointer advances after write ack",
              HOST_REG_HSTADRL, 16'h1030);
    cpu_check("written HSTDATA retained",
              HOST_REG_HSTDATA, 16'hBBAA);

    // LBL=1 reverses both address-completion and data-completion bytes.
    hstctlh = 16'h0001 << HSTCTL_LBL_BIT;
    host_access(1'b1, HOST_REG_HSTADRH, 2'b11, 16'hFFFF, rd);
    check_bit("LBL1 HSTADRH does not trigger", local_req, 1'b0);
    host_access(1'b1, HOST_REG_HSTADRL, 2'b10, 16'hFF00, rd);
    check_bit("LBL1 HSTADRL high byte does not trigger", local_req, 1'b0);
    host_access(1'b1, HOST_REG_HSTADRL, 2'b01, 16'h000F, rd);
    complete_local("LBL1 address prefetch", 1'b0, 32'hFFFF_FF00,
                   16'h0000, 16'h3333, 1);
    cpu_check("LBL1 prefetch data", HOST_REG_HSTDATA, 16'h3333);

    hstctlh = (16'h0001 << HSTCTL_LBL_BIT)
            | (16'h0001 << HSTCTL_INCW_BIT);
    host_access(1'b1, HOST_REG_HSTDATA, 2'b10, 16'hCC00, rd);
    check_bit("LBL1 HSTDATA high byte does not trigger", local_req, 1'b0);
    host_access(1'b1, HOST_REG_HSTDATA, 2'b01, 16'h00DD, rd);
    complete_local("LBL1 HSTDATA write", 1'b1, 32'hFFFF_FF00,
                   16'hCCDD, 16'h0000, 1);
    cpu_check("LBL1 INCW postincrement",
              HOST_REG_HSTADRL, 16'hFF10);

    // Pointer arithmetic wraps naturally at the 32-bit boundary.
    cpu_write(HOST_REG_HSTADRH, 16'hFFFF);
    cpu_write(HOST_REG_HSTADRL, 16'hFFF0);
    host_access(1'b1, HOST_REG_HSTDATA, 2'b11, 16'h4455, rd);
    complete_local("INCW wrap write", 1'b1, 32'hFFFF_FFF0,
                   16'h4455, 16'h0000, 1);
    cpu_check("INCW wrap HSTADRL", HOST_REG_HSTADRL, 16'h0000);
    cpu_check("INCW wrap HSTADRH", HOST_REG_HSTADRH, 16'h0000);

    // Simultaneous CPU/host register writes are architecturally invalid.
    // The isolated deterministic rule is host priority over processor data.
    hstctlh = '0;
    cpu_write(HOST_REG_HSTDATA, 16'hCAFE);
    @(negedge clk);
    cpu_we       = 1'b1;
    cpu_reg      = HOST_REG_HSTDATA;
    cpu_wdata    = 16'h1234;
    host_req     = 1'b1;
    host_we      = 1'b1;
    host_reg     = HOST_REG_HSTDATA;
    host_be      = 2'b01;
    host_wdata   = 16'h00EE;
    @(posedge clk);
    #1;
    @(negedge clk);
    cpu_we   = 1'b0;
    host_req = 1'b0;
    host_we  = 1'b0;
    host_be  = 2'b00;
    @(posedge clk);
    #1;
    cpu_check("simultaneous explicit write host priority",
              HOST_REG_HSTDATA, 16'hCAEE);
    check_bit("non-last collision has no local side effect",
              local_req, 1'b0);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (host registers, LBL triggers, INCR/INCW, held local requests, backpressure)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_host_if hard timeout");
    $fatal(1);
  end

endmodule : tb_host_if
