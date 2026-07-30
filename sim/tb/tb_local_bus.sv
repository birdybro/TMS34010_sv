`timescale 1ns/1ps
`default_nettype none

// Focused original-pin local-bus regression. It checks the half-quarter
// phase schedule, every landed cycle family, exact address/status encoding,
// repeated LRDY service, middle-Q4 reads, I/O LRDY bypass, and the eight
// automatic zero-row RAS-only cycles following reset.
module tb_local_bus;
  import tms34010_pkg::*;

  logic                              clk8x;
  logic                              rst;
  logic                              cycle_req;
  local_cycle_kind_t                 cycle_kind;
  logic [ADDR_WIDTH-1:0]             cycle_addr;
  local_word_t                       cycle_wdata;
  logic                              cycle_iaq;
  logic [13:0]                       cycle_srfaddr;
  logic [15:0]                       cycle_dpytap;
  logic                              cycle_screen_org;
  logic [7:0]                        cycle_dram_row;
  local_word_t                       io_rdata;
  local_word_t                       cycle_rdata;
  logic                              cycle_ack;
  logic                              cycle_busy;
  logic                              init_done;
  logic                              lrdy;
  local_word_t                       lad_i;
  local_word_t                       lad_o;
  logic                              lad_oe;
  logic                              lclk1;
  logic                              lclk2;
  logic                              ras_n;
  logic                              lal_n;
  logic                              cas_n;
  logic                              we_n;
  logic                              tr_qe_n;
  logic                              den_n;
  logic                              ddout;
  local_subphase_t                   subphase;

  integer errors;
  integer init_ras_count;
  logic   previous_ras_n;

  tms34010_local_bus dut (
    .clk8x_i             (clk8x),
    .rst                 (rst),
    .cycle_req_i         (cycle_req),
    .cycle_kind_i        (cycle_kind),
    .cycle_addr_i        (cycle_addr),
    .cycle_wdata_i       (cycle_wdata),
    .cycle_iaq_i         (cycle_iaq),
    .cycle_srfaddr_i     (cycle_srfaddr),
    .cycle_dpytap_i      (cycle_dpytap),
    .cycle_screen_org_i  (cycle_screen_org),
    .cycle_dram_row_i    (cycle_dram_row),
    .io_rdata_i          (io_rdata),
    .cycle_rdata_o       (cycle_rdata),
    .cycle_ack_o         (cycle_ack),
    .cycle_busy_o        (cycle_busy),
    .init_done_o         (init_done),
    .hold_n_i            (1'b1),
    .hold_req_o          (),
    .hold_grant_i        (1'b0),
    .hlda_n_o            (),
    .lrdy_i              (lrdy),
    .lad_i               (lad_i),
    .lad_o               (lad_o),
    .lad_oe_o            (lad_oe),
    .lclk1_o             (lclk1),
    .lclk2_o             (lclk2),
    .ras_n_o             (ras_n),
    .lal_n_o             (lal_n),
    .cas_n_o             (cas_n),
    .we_n_o              (we_n),
    .tr_qe_n_o           (tr_qe_n),
    .den_n_o             (den_n),
    .ddout_o             (ddout),
    .ras_oe_o            (),
    .lal_oe_o            (),
    .cas_oe_o            (),
    .we_oe_o             (),
    .tr_qe_oe_o          (),
    .den_oe_o            (),
    .ddout_oe_o          (),
    .subphase_o          (subphase)
  );

  initial begin
    clk8x = 1'b0;
    forever #1 clk8x = ~clk8x;
  end

  task automatic check(input logic condition, input string message);
    begin
      if (!condition) begin
        $display("CHECK_FAIL: %s at t=%0t phase=%0d", message, $time, subphase);
        errors = errors + 1;
      end
    end
  endtask

  task automatic wait_phase(input local_subphase_t wanted);
    begin
      @(negedge clk8x);
      while (subphase != wanted)
        @(negedge clk8x);
    end
  endtask

  task automatic begin_command(
    input local_cycle_kind_t             kind,
    input logic [ADDR_WIDTH-1:0]         address,
    input local_word_t                   wdata,
    input logic                          iaq,
    input logic [13:0]                   srfaddr,
    input logic [15:0]                   dpytap,
    input logic                          screen_org,
    input logic [7:0]                    dram_row
  );
    begin
      @(negedge clk8x);
      cycle_kind       = kind;
      cycle_addr       = address;
      cycle_wdata      = wdata;
      cycle_iaq        = iaq;
      cycle_srfaddr    = srfaddr;
      cycle_dpytap     = dpytap;
      cycle_screen_org = screen_org;
      cycle_dram_row   = dram_row;
      cycle_req        = 1'b1;
      wait_phase(LOCAL_PHASE_Q1A);
      check(cycle_busy, "accepted command must report busy");
      check(!cycle_ack, "command must not acknowledge in first Q1");
    end
  endtask

  task automatic finish_command;
    begin
      check(subphase == LOCAL_PHASE_Q4B,
            "finish_command must be called during Q4B");
      check(cycle_ack, "command must acknowledge at completing Q4B");
      cycle_req = 1'b0;
      wait_phase(LOCAL_PHASE_Q1A);
      check(!cycle_ack, "acknowledge must be a single subphase");
      check(ras_n && lal_n && cas_n && we_n && tr_qe_n && den_n,
            "idle controls must be inactive");
    end
  endtask

  function automatic local_word_t expected_word_row(
    input logic [ADDR_WIDTH-1:0] address
  );
    return {1'b1, address[26:12]};
  endfunction

  function automatic local_word_t expected_word_column(
    input logic [ADDR_WIDTH-1:0] address,
    input logic                  iaq
  );
    return {iaq, 1'b1, address[29:27], address[14:4]};
  endfunction

  function automatic local_word_t expected_refresh_row(
    input logic [7:0] row
  );
    return {1'b0, row[6:0], row};
  endfunction

  function automatic local_word_t expected_screen_row(
    input logic [13:0] address
  );
    return {1'b1, 3'b000, address[13:2]};
  endfunction

  function automatic local_word_t expected_screen_column(
    input logic [13:0] address,
    input logic [15:0] tap
  );
    return {
      2'b00,
      tap[13:12],
      tap[11:6] | address[5:0],
      tap[5:0]
    };
  endfunction

  // Continuous checks cover the two output clocks and count reset-time RAS
  // starts. At each RAS fall, the reset refresh row/status and inactive
  // non-RAS controls must match Figure 11-7.
  always @(negedge clk8x) begin
    check(lclk1 == (subphase <= LOCAL_PHASE_Q2B),
          "LCLK1 phase decode");
    check(lclk2 == ((subphase >= LOCAL_PHASE_Q2A)
                   && (subphase <= LOCAL_PHASE_Q3B)),
          "LCLK2 phase decode");

    if (rst) begin
      init_ras_count = 0;
      previous_ras_n = 1'b1;
    end else begin
      if (!init_done && previous_ras_n && !ras_n) begin
        init_ras_count = init_ras_count + 1;
        check(subphase == LOCAL_PHASE_Q3B,
              "reset RAS must fall at Q3B");
        check(lad_oe && (lad_o == 16'h0000),
              "reset RAS row/status must be all zero");
        check(lal_n && cas_n && we_n && tr_qe_n && den_n && ddout,
              "reset RAS fall must leave all other controls inactive");
      end
      previous_ras_n = ras_n;
    end
  end

  initial begin
    logic [ADDR_WIDTH-1:0] word_address;
    local_word_t           word_row;
    local_word_t           word_column;
    logic [13:0]           screen_address;
    local_word_t           screen_row;
    local_word_t           screen_column;
    local_word_t           refresh_row;

    errors           = 0;
    init_ras_count   = 0;
    previous_ras_n   = 1'b1;
    rst              = 1'b1;
    cycle_req        = 1'b0;
    cycle_kind       = LOCAL_CYCLE_WORD_READ;
    cycle_addr       = '0;
    cycle_wdata      = '0;
    cycle_iaq        = 1'b0;
    cycle_srfaddr    = '0;
    cycle_dpytap     = '0;
    cycle_screen_org = 1'b0;
    cycle_dram_row   = '0;
    io_rdata         = 16'h0000;
    lrdy             = 1'b1;
    lad_i            = 16'h0000;

    repeat (4) @(posedge clk8x);
    @(negedge clk8x);
    rst = 1'b0;

    // Extend the first automatic initialization cycle by exactly one local
    // clock. RAS/LAL must remain low throughout the repeated access period.
    wait (init_ras_count == 1);
    wait_phase(LOCAL_PHASE_Q1A);
    lrdy = 1'b0;
    wait_phase(LOCAL_PHASE_Q1A);
    check(!ras_n && !lal_n,
          "LRDY-low reset cycle must retain RAS and LAL");
    check(cas_n && we_n && tr_qe_n && den_n && ddout,
          "LRDY-low reset cycle must remain RAS-only");
    check(!init_done && !cycle_ack,
          "reset initialization wait must not complete early");
    lrdy = 1'b1;

    wait (init_done);
    @(negedge clk8x);
    check(init_ras_count == 8,
          "exactly eight post-reset RAS-only cycles are required");
    check(!cycle_ack, "automatic reset cycles must not acknowledge a client");

    // Ordinary late write, including exact RF/TR/IAQ address placement.
    lrdy        = 1'b1;
    word_address = 32'h2A5B_C9D0;
    word_row     = expected_word_row(word_address);
    word_column  = expected_word_column(word_address, 1'b0);
    begin_command(
        LOCAL_CYCLE_WORD_WRITE, word_address, 16'hA55A, 1'b0,
        14'h0000, 16'h0000, 1'b0, 8'h00);

    wait_phase(LOCAL_PHASE_Q2A);
    check(lad_oe && (lad_o == word_row),
          "word-write row address");
    wait_phase(LOCAL_PHASE_Q3B);
    check(!ras_n && lal_n && cas_n,
          "word-write RAS fall ordering");
    check(lad_o == word_row, "row must remain valid at RAS fall");
    wait_phase(LOCAL_PHASE_Q4A);
    check(lad_o == word_column && ras_n == 1'b0
          && lal_n && cas_n,
          "word-write column before LAL/CAS");
    wait_phase(LOCAL_PHASE_Q4B);
    check(!lal_n && cas_n, "word-write LAL must precede CAS");
    wait_phase(LOCAL_PHASE_Q1A);
    check(lad_oe && (lad_o == 16'hA55A) && !den_n && cas_n,
          "write data and DEN must precede CAS");
    wait_phase(LOCAL_PHASE_Q1B);
    check(!cas_n && we_n, "write CAS must precede W");
    wait_phase(LOCAL_PHASE_Q2B);
    check(!we_n && !cas_n && !ras_n,
          "late-write strobe phase");
    wait_phase(LOCAL_PHASE_Q4A);
    check(!we_n && !cas_n && !ras_n && (lad_o == 16'hA55A),
          "write data/control hold through Q4A");
    wait_phase(LOCAL_PHASE_Q4B);
    check(cycle_ack && ras_n && cas_n && we_n && !lal_n && !den_n,
          "word-write completion levels");
    finish_command();

    // Ordinary read with one inserted wait state. IAQ is high only for the
    // first opcode word, so this cycle directly verifies LAD15 at column time.
    word_address = 32'h1234_5670;
    word_row     = expected_word_row(word_address);
    word_column  = expected_word_column(word_address, 1'b1);
    lrdy         = 1'b0;
    begin_command(
        LOCAL_CYCLE_WORD_READ, word_address, 16'h0000, 1'b1,
        14'h0000, 16'h0000, 1'b0, 8'h00);

    wait_phase(LOCAL_PHASE_Q3B);
    check(!ras_n && (lad_o == word_row),
          "word-read row at RAS fall");
    wait_phase(LOCAL_PHASE_Q4A);
    check(lad_o == word_column && word_column[15],
          "word-read IAQ column status");
    wait_phase(LOCAL_PHASE_Q1B);
    check(!cas_n && ddout == 1'b0,
          "read direction must change after CAS");
    wait_phase(LOCAL_PHASE_Q2A);
    check(!tr_qe_n && !den_n && !lad_oe,
          "read memory/buffer enables and LAD high impedance");
    wait_phase(LOCAL_PHASE_Q4B);
    check(!cycle_ack && !ras_n && !lal_n && !cas_n
          && !tr_qe_n && !den_n && !ddout,
          "LRDY-low read must retain every active-low control");
    wait_phase(LOCAL_PHASE_Q1A);
    check(!ras_n && !lal_n && !cas_n && !tr_qe_n && !den_n,
          "read controls must remain low across repeated period");
    lrdy = 1'b1;
    wait_phase(LOCAL_PHASE_Q3A);
    lad_i = 16'hC35A;
    wait_phase(LOCAL_PHASE_Q4A);
    check(!cycle_ack, "read must sample before end-Q4 acknowledge");
    wait_phase(LOCAL_PHASE_Q4B);
    check(cycle_ack && (cycle_rdata == 16'hC35A),
          "middle-Q4 LAD sample must accompany read acknowledge");
    check(ras_n && cas_n && tr_qe_n && den_n && !ddout,
          "read strobes release before DDOUT at completion");
    finish_command();

    // Screen refresh uses the DPYADR/DPYTAP-specific address network and
    // releases TR/QE before RAS even if the access period continues.
    screen_address = ~14'h12A5;
    screen_row     = expected_screen_row(screen_address);
    screen_column  = expected_screen_column(screen_address, 16'h2D63);
    lrdy           = 1'b0;
    begin_command(
        LOCAL_CYCLE_SCREEN_REFRESH, 32'h0000_0000, 16'h0000, 1'b0,
        14'h12A5, 16'h2D63, 1'b0, 8'h00);

    wait_phase(LOCAL_PHASE_Q2A);
    check(lad_o == screen_row && !tr_qe_n,
          "screen row and early transfer indication");
    wait_phase(LOCAL_PHASE_Q3B);
    check(!ras_n && !tr_qe_n,
          "screen TR/QE must be low at RAS fall");
    wait_phase(LOCAL_PHASE_Q4A);
    check(lad_o == screen_column && lal_n,
          "screen column before LAL fall");
    wait_phase(LOCAL_PHASE_Q4B);
    check(!lal_n && !tr_qe_n, "screen LAL/transfer overlap");
    wait_phase(LOCAL_PHASE_Q1B);
    check(!cas_n && !tr_qe_n,
          "screen CAS must fall before TR/QE rises");
    wait_phase(LOCAL_PHASE_Q3A);
    check(tr_qe_n && !ras_n && !cas_n,
          "screen TR/QE must release before RAS");
    wait_phase(LOCAL_PHASE_Q4B);
    check(!cycle_ack && tr_qe_n && !ras_n && !cas_n && !lal_n,
          "screen wait must extend strobes but not TR/QE");
    wait_phase(LOCAL_PHASE_Q1A);
    check(tr_qe_n && !ras_n && !cas_n && !lal_n,
          "screen TR/QE must stay released in repeated period");
    lrdy = 1'b1;
    wait_phase(LOCAL_PHASE_Q4B);
    check(cycle_ack && ras_n && cas_n && tr_qe_n,
          "screen completion");
    finish_command();

    // ORG=1 exposes the stored SRFADR directly. Together with the ORG=0
    // case above, this distinguishes pin representation from the raw
    // DPYADR counter update performed by the display scheduler.
    screen_address = 14'h12A5;
    screen_row = expected_screen_row(screen_address);
    screen_column = expected_screen_column(screen_address, 16'h2D63);
    begin_command(
        LOCAL_CYCLE_SCREEN_REFRESH, 32'h0000_0000, 16'h0000, 1'b0,
        14'h12A5, 16'h2D63, 1'b1, 8'h00);
    wait_phase(LOCAL_PHASE_Q2A);
    check(lad_o == screen_row, "ORG=1 direct screen row");
    wait_phase(LOCAL_PHASE_Q4A);
    check(lad_o == screen_column, "ORG=1 direct screen column/tap");
    wait_phase(LOCAL_PHASE_Q4B);
    wait_phase(LOCAL_PHASE_Q4B);
    check(cycle_ack, "ORG=1 screen completion");
    finish_command();

    // Program-controlled memory-to-register transfers retain the ordinary
    // pixel address, force IAQ inactive and TR status active at column time,
    // and use the same two-period VRAM transfer envelope as screen refresh.
    word_address = 32'h31A5_67B0;
    word_row     = expected_word_row(word_address);
    word_column  = expected_word_column(word_address, 1'b0);
    word_column[14] = 1'b0;
    lrdy = 1'b0;
    begin_command(
        LOCAL_CYCLE_PIXEL_MTR, word_address, 16'hFFFF, 1'b1,
        14'h0000, 16'h0000, 1'b0, 8'h00);
    check(!den_n && !ddout && we_n,
          "MTR must initially enable the input data path");
    wait_phase(LOCAL_PHASE_Q2A);
    check(lad_oe && (lad_o == word_row) && den_n && ddout
          && !tr_qe_n && we_n,
          "MTR row and transfer setup");
    wait_phase(LOCAL_PHASE_Q3B);
    check(!ras_n && !tr_qe_n && we_n && (lad_o == word_row),
          "MTR transfer indication at RAS fall");
    wait_phase(LOCAL_PHASE_Q4A);
    check((lad_o == word_column) && !word_column[15]
          && !word_column[14] && we_n,
          "MTR column TR/IAQ status and inactive W");
    wait_phase(LOCAL_PHASE_Q1A);
    check(lad_oe && (lad_o == 16'h0000) && !ras_n && !lal_n
          && cas_n && !tr_qe_n,
          "MTR undefined second-period LAD and transfer hold");
    wait_phase(LOCAL_PHASE_Q1B);
    check(!cas_n && !tr_qe_n,
          "MTR CAS must fall while transfer remains active");
    wait_phase(LOCAL_PHASE_Q3A);
    check(tr_qe_n && !ras_n && !cas_n,
          "MTR transfer indication must release before RAS");
    wait_phase(LOCAL_PHASE_Q4B);
    check(!cycle_ack && tr_qe_n && !ras_n && !cas_n,
          "MTR wait must extend strobes but not TR/QE");
    wait_phase(LOCAL_PHASE_Q1A);
    check(tr_qe_n && !ras_n && !cas_n,
          "MTR repeated period must keep TR/QE released");
    lrdy = 1'b1;
    wait_phase(LOCAL_PHASE_Q4B);
    check(cycle_ack && (cycle_rdata == 16'h0000),
          "MTR completes without returning LAD data to the CPU");
    finish_command();

    // Register-to-memory uses the same explicit transfer cycle, with W low
    // at the RAS falling edge and released again before the column address.
    word_address = 32'h06D4_2A90;
    word_row     = expected_word_row(word_address);
    word_column  = expected_word_column(word_address, 1'b0);
    word_column[14] = 1'b0;
    lrdy = 1'b0;
    begin_command(
        LOCAL_CYCLE_PIXEL_RTM, word_address, 16'hA55A, 1'b1,
        14'h0000, 16'h0000, 1'b0, 8'h00);
    check(!den_n && !ddout && we_n,
          "RTM must initially enable the input data path");
    wait_phase(LOCAL_PHASE_Q2A);
    check((lad_o == word_row) && !tr_qe_n && !we_n,
          "RTM row, transfer, and early W setup");
    wait_phase(LOCAL_PHASE_Q3B);
    check(!ras_n && !tr_qe_n && !we_n && (lad_o == word_row),
          "RTM must present low W at RAS fall");
    wait_phase(LOCAL_PHASE_Q4A);
    check((lad_o == word_column) && we_n
          && !word_column[15] && !word_column[14],
          "RTM must release W before TR/IAQ column status");
    wait_phase(LOCAL_PHASE_Q1B);
    check(lad_oe && (lad_o == 16'h0000) && !cas_n && !tr_qe_n
          && we_n,
          "RTM second period carries no CPU write data");
    wait_phase(LOCAL_PHASE_Q3A);
    check(tr_qe_n && !ras_n && !cas_n && we_n,
          "RTM transfer release ordering");
    wait_phase(LOCAL_PHASE_Q4B);
    check(!cycle_ack && tr_qe_n && we_n && !ras_n && !cas_n,
          "RTM wait must extend only RAS/CAS/LAL");
    wait_phase(LOCAL_PHASE_Q1A);
    check(tr_qe_n && we_n && !ras_n && !cas_n,
          "RTM repeated period must not extend W/TR/QE");
    lrdy = 1'b1;
    wait_phase(LOCAL_PHASE_Q4B);
    check(cycle_ack && ras_n && cas_n && tr_qe_n && we_n,
          "RTM completion");
    finish_command();

    // RAS-only refresh emits the duplicated REFCNT row mapping and activates
    // no control other than RAS/LAL.
    refresh_row = expected_refresh_row(8'hA6);
    begin_command(
        LOCAL_CYCLE_DRAM_RAS, 32'h0000_0000, 16'h0000, 1'b0,
        14'h0000, 16'h0000, 1'b0, 8'hA6);
    wait_phase(LOCAL_PHASE_Q3B);
    check((lad_o == refresh_row) && !ras_n,
          "RAS-only refresh row mapping");
    check(lal_n && cas_n && we_n && tr_qe_n && den_n && ddout,
          "RAS-only non-RAS controls at row strobe");
    wait_phase(LOCAL_PHASE_Q4B);
    check(!lal_n && cas_n && we_n && tr_qe_n && den_n && ddout,
          "RAS-only LAL phase");
    wait_phase(LOCAL_PHASE_Q4B);
    check(cycle_ack && ras_n && cas_n,
          "RAS-only completion");
    finish_command();

    // CAS-before-RAS refresh keeps the same row stable through Q4 and orders
    // CAS, LAL, then RAS exactly as Figure 11-8.
    refresh_row = expected_refresh_row(8'h3C);
    begin_command(
        LOCAL_CYCLE_DRAM_CBR, 32'h0000_0000, 16'h0000, 1'b0,
        14'h0000, 16'h0000, 1'b0, 8'h3C);
    wait_phase(LOCAL_PHASE_Q2A);
    check((lad_o == refresh_row) && !cas_n && lal_n && ras_n,
          "CBR CAS-first phase");
    wait_phase(LOCAL_PHASE_Q3A);
    check((lad_o == refresh_row) && !cas_n && !lal_n && ras_n,
          "CBR LAL-before-RAS phase");
    wait_phase(LOCAL_PHASE_Q4A);
    check((lad_o == refresh_row) && !cas_n && !lal_n && !ras_n,
          "CBR RAS fall and stable row");
    wait_phase(LOCAL_PHASE_Q1A);
    check(!ras_n && !lal_n && !cas_n,
          "CBR strobes must remain active in access period");
    wait_phase(LOCAL_PHASE_Q4B);
    check(cycle_ack && ras_n && cas_n && !lal_n,
          "CBR completion");
    finish_command();

    // I/O reads ignore LRDY, drive zero address bits with inactive status,
    // keep CAS/W/TR/DEN/DDOUT high, and return the on-chip data input.
    lrdy     = 1'b0;
    io_rdata = 16'h5AA5;
    begin_command(
        LOCAL_CYCLE_IO_READ, IO_BASE_ADDR, 16'h0000, 1'b0,
        14'h0000, 16'h0000, 1'b0, 8'h00);
    wait_phase(LOCAL_PHASE_Q2A);
    check(lad_o == 16'h8000,
          "I/O row address and inactive RF status");
    wait_phase(LOCAL_PHASE_Q4A);
    check(lad_o == 16'h4000,
          "I/O column address and inactive TR/IAQ status");
    wait_phase(LOCAL_PHASE_Q2A);
    check(!lad_oe && !ras_n && !lal_n,
          "I/O read data phase and active controls");
    check(cas_n && we_n && tr_qe_n && den_n && ddout,
          "I/O read must leave non-RAS/LAL controls inactive");
    wait_phase(LOCAL_PHASE_Q4B);
    check(cycle_ack && (cycle_rdata == 16'h5AA5),
          "I/O read must ignore LRDY and return internal data");
    finish_command();

    // I/O write data appears on LAD, but even W and DEN remain inactive.
    begin_command(
        LOCAL_CYCLE_IO_WRITE, IO_BASE_ADDR + 32'h0000_0010,
        16'h96E1, 1'b0, 14'h0000, 16'h0000, 1'b0, 8'h00);
    wait_phase(LOCAL_PHASE_Q4A);
    check(lad_o == 16'h4000,
          "I/O write column address and inactive TR/IAQ status");
    wait_phase(LOCAL_PHASE_Q2A);
    check(lad_oe && (lad_o == 16'h96E1) && !ras_n && !lal_n,
          "I/O write data phase");
    check(cas_n && we_n && tr_qe_n && den_n && ddout,
          "I/O write must leave CAS/W/TR/DEN/DDOUT inactive");
    wait_phase(LOCAL_PHASE_Q4B);
    check(cycle_ack, "I/O write must ignore LRDY");
    finish_command();

    lrdy = 1'b1;
    if (errors == 0) begin
      $display("TEST_RESULT: PASS");
    end else begin
      $display("TEST_RESULT: FAIL (%0d errors)", errors);
    end
    $finish;
  end

endmodule

`default_nettype wire
