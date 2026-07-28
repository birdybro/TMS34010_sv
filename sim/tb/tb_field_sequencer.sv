// -----------------------------------------------------------------------------
// tb_field_sequencer.sv
//
// Physical-word sequencing regression for tms34010_field_sequencer.
//
// The 1988 User's Guide §4.1 pages 4-3 through 4-5 defines seven field
// insertion cases. This bench checks the exact read/write count, order,
// addresses, write data, and partial-word RMW lock for all seven. It also
// covers one-, two-, and three-word reads, fixed wait states, payload
// stability while stalled, and reset cancellation/recovery.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_field_sequencer;
  import tms34010_pkg::*;

  localparam int unsigned DEPTH_WORDS = 64;
  localparam int unsigned LOG_DEPTH   = 96;
  localparam int unsigned STALL_CYCLES = 2;

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
  logic                              word_req;
  logic                              word_we;
  logic [ADDR_WIDTH-1:0]             word_addr;
  local_word_t                       word_wdata;
  local_word_t                       word_rdata;
  logic                              word_ack;
  logic                              word_rmw_lock;

  tms34010_field_sequencer u_dut (
    .clk             (clk),
    .rst             (rst),
    .field_req_i     (field_req),
    .field_we_i      (field_we),
    .field_addr_i    (field_addr),
    .field_size_i    (field_size),
    .field_wdata_i   (field_wdata),
    .field_rdata_o   (field_rdata),
    .field_ack_o     (field_ack),
    .word_req_o      (word_req),
    .word_we_o       (word_we),
    .word_addr_o     (word_addr),
    .word_wdata_o    (word_wdata),
    .word_rdata_i    (word_rdata),
    .word_ack_i      (word_ack),
    .word_rmw_lock_o (word_rmw_lock)
  );

  local_word_t backing [0:DEPTH_WORDS-1];

  typedef enum logic [1:0] {
    WORD_IDLE = 2'd0,
    WORD_WAIT = 2'd1,
    WORD_ACK  = 2'd2
  } word_state_t;

  word_state_t state_q;
  logic [$clog2(STALL_CYCLES+1)-1:0] wait_q;
  logic                              latched_we_q;
  logic [ADDR_WIDTH-1:0]             latched_addr_q;
  local_word_t                       latched_wdata_q;
  int unsigned                       transaction_count_q;
  int unsigned                       protocol_failures_q;

  logic [ADDR_WIDTH-1:0] transaction_addr [0:LOG_DEPTH-1];
  logic                  transaction_we   [0:LOG_DEPTH-1];
  local_word_t           transaction_data [0:LOG_DEPTH-1];
  logic                  transaction_lock [0:LOG_DEPTH-1];

  logic [$clog2(DEPTH_WORDS)-1:0] latched_word_index;
  assign latched_word_index =
      latched_addr_q[$clog2(DEPTH_WORDS)+LOCAL_WORD_ADDR_LSB-1
                     : LOCAL_WORD_ADDR_LSB];
  assign word_ack   = (state_q == WORD_ACK);
  assign word_rdata = backing[latched_word_index];

  // Stalling physical-word target. A new request is captured only in IDLE;
  // each accepted payload is checked for stability until its ACK cycle.
  always_ff @(posedge clk) begin
    if (rst) begin
      state_q              <= WORD_IDLE;
      wait_q               <= '0;
      latched_we_q         <= 1'b0;
      latched_addr_q       <= '0;
      latched_wdata_q      <= '0;
      transaction_count_q  <= 0;
      protocol_failures_q  <= 0;
    end else begin
      unique case (state_q)
        WORD_IDLE: begin
          if (word_req) begin
            latched_we_q    <= word_we;
            latched_addr_q  <= word_addr;
            latched_wdata_q <= word_wdata;
            wait_q          <= $clog2(STALL_CYCLES+1)'(STALL_CYCLES);
            state_q         <= WORD_WAIT;
            if (transaction_count_q < LOG_DEPTH) begin
              transaction_addr[transaction_count_q] <= word_addr;
              transaction_we[transaction_count_q]   <= word_we;
              transaction_data[transaction_count_q] <= word_wdata;
              transaction_lock[transaction_count_q] <= word_rmw_lock;
            end
            transaction_count_q <= transaction_count_q + 1;
          end
        end

        WORD_WAIT: begin
          if (!word_req || (word_we != latched_we_q)
              || (word_addr != latched_addr_q)
              || (word_wdata != latched_wdata_q)) begin
            protocol_failures_q <= protocol_failures_q + 1;
          end
          if (wait_q == 1) begin
            state_q <= WORD_ACK;
          end else begin
            wait_q <= wait_q - 1'b1;
          end
        end

        WORD_ACK: begin
          if (!word_req || (word_we != latched_we_q)
              || (word_addr != latched_addr_q)
              || (word_wdata != latched_wdata_q)) begin
            protocol_failures_q <= protocol_failures_q + 1;
          end
          if (latched_we_q)
            backing[latched_word_index] <= latched_wdata_q;
          state_q <= WORD_IDLE;
        end

        default: state_q <= WORD_IDLE;
      endcase
    end
  end

  int unsigned failures;

  task automatic do_field(
    input  logic                            we,
    input  logic [ADDR_WIDTH-1:0]           addr,
    input  logic [FIELD_SIZE_WIDTH-1:0]     size,
    input  logic [DATA_WIDTH-1:0]           wdata,
    output logic [DATA_WIDTH-1:0]           rdata
  );
    int unsigned watchdog;
    begin
      @(negedge clk);
      field_req   = 1'b1;
      field_we    = we;
      field_addr  = addr;
      field_size  = size;
      field_wdata = wdata;
      watchdog = 0;
      do begin
        @(negedge clk);
        watchdog++;
        if (watchdog > 200) begin
          $display("TEST_RESULT: FAIL: field request timeout addr=%08h size=%0d",
                   addr, size);
          failures++;
          break;
        end
      end while (field_ack !== 1'b1);
      rdata     = field_rdata;
      field_req = 1'b0;
      @(negedge clk);
    end
  endtask

  task automatic do_write(
    input logic [ADDR_WIDTH-1:0]         addr,
    input logic [FIELD_SIZE_WIDTH-1:0]   size,
    input logic [DATA_WIDTH-1:0]         data
  );
    logic [DATA_WIDTH-1:0] unused;
    begin
      do_field(1'b1, addr, size, data, unused);
    end
  endtask

  task automatic check_read(
    input string                          label,
    input logic [ADDR_WIDTH-1:0]          addr,
    input logic [FIELD_SIZE_WIDTH-1:0]    size,
    input logic [DATA_WIDTH-1:0]          expected
  );
    logic [DATA_WIDTH-1:0] actual;
    begin
      do_field(1'b0, addr, size, '0, actual);
      if (actual !== expected) begin
        $display("TEST_RESULT: FAIL: %s expected=%08h actual=%08h",
                 label, expected, actual);
        failures++;
      end
    end
  endtask

  task automatic check_word(
    input string       label,
    input int unsigned index,
    input local_word_t expected
  );
    begin
      if (backing[index] !== expected) begin
        $display("TEST_RESULT: FAIL: %s word[%0d] expected=%04h actual=%04h",
                 label, index, expected, backing[index]);
        failures++;
      end
    end
  endtask

  task automatic check_count(
    input string       label,
    input int unsigned base,
    input int unsigned expected_delta
  );
    begin
      if ((transaction_count_q - base) != expected_delta) begin
        $display("TEST_RESULT: FAIL: %s transaction count expected=%0d actual=%0d",
                 label, expected_delta, transaction_count_q - base);
        failures++;
      end
    end
  endtask

  task automatic check_transaction(
    input string                         label,
    input int unsigned                   index,
    input logic                          expected_we,
    input logic [ADDR_WIDTH-1:0]         expected_addr,
    input local_word_t                   expected_data,
    input logic                          expected_lock
  );
    begin
      if (transaction_we[index] !== expected_we
          || transaction_addr[index] !== expected_addr
          || (expected_we && transaction_data[index] !== expected_data)
          || transaction_lock[index] !== expected_lock) begin
        $display("TEST_RESULT: FAIL: %s expected we/addr/data/lock=%0b/%08h/%04h/%0b actual=%0b/%08h/%04h/%0b",
                 label, expected_we, expected_addr, expected_data, expected_lock,
                 transaction_we[index], transaction_addr[index],
                 transaction_data[index], transaction_lock[index]);
        failures++;
      end
    end
  endtask

  initial begin : main
    int unsigned i;
    int unsigned base;
    logic [DATA_WIDTH-1:0] unused;

    failures   = 0;
    field_req  = 1'b0;
    field_we   = 1'b0;
    field_addr = '0;
    field_size = '0;
    field_wdata = '0;
    for (i = 0; i < DEPTH_WORDS; i++) backing[i] = '0;

    repeat (3) @(posedge clk);
    rst = 1'b0;

    // Case A: aligned 16-bit field -> one direct write.
    backing[0] = 16'hAAAA;
    base = transaction_count_q;
    do_write(32'd0, 6'd16, 32'h0000_BEEF);
    check_count("Case A", base, 1);
    check_transaction("Case A write", base, 1'b1, 32'd0, 16'hBEEF, 1'b0);
    check_word("Case A result", 0, 16'hBEEF);

    // Case B: sub-16-bit partial field -> read, locked write.
    backing[2] = 16'hA55A;
    base = transaction_count_q;
    do_write(32'd35, 6'd5, 32'h0000_001B);
    check_count("Case B", base, 2);
    check_transaction("Case B read",  base,   1'b0, 32'd32, '0,      1'b1);
    check_transaction("Case B write", base+1, 1'b1, 32'd32, 16'hA5DA, 1'b1);
    check_word("Case B result", 2, 16'hA5DA);

    // Case C: aligned 32-bit field -> two direct writes.
    backing[4] = 16'h1111;
    backing[5] = 16'h2222;
    base = transaction_count_q;
    do_write(32'd64, 6'd32, 32'h1234_5678);
    check_count("Case C", base, 2);
    check_transaction("Case C low",  base,   1'b1, 32'd64, 16'h5678, 1'b0);
    check_transaction("Case C high", base+1, 1'b1, 32'd80, 16'h1234, 1'b0);
    check_word("Case C low result",  4, 16'h5678);
    check_word("Case C high result", 5, 16'h1234);

    // Case D: partial first word, full final word.
    backing[8] = 16'h0123;
    backing[9] = 16'hFFFF;
    base = transaction_count_q;
    do_write(32'd140, 6'd20, 32'h000A_BCDE);
    check_count("Case D", base, 3);
    check_transaction("Case D read first",  base,   1'b0, 32'd128, '0,       1'b1);
    check_transaction("Case D write first", base+1, 1'b1, 32'd128, 16'hE123, 1'b1);
    check_transaction("Case D write last",  base+2, 1'b1, 32'd144, 16'hABCD, 1'b0);
    check_word("Case D first result", 8, 16'hE123);
    check_word("Case D last result",  9, 16'hABCD);

    // Case E: full first word, partial final word.
    backing[12] = 16'h1111;
    backing[13] = 16'h5550;
    base = transaction_count_q;
    do_write(32'd192, 6'd20, 32'h000A_BCDE);
    check_count("Case E", base, 3);
    check_transaction("Case E write first", base,   1'b1, 32'd192, 16'hBCDE, 1'b0);
    check_transaction("Case E read last",   base+1, 1'b0, 32'd208, '0,       1'b1);
    check_transaction("Case E write last",  base+2, 1'b1, 32'd208, 16'h555A, 1'b1);
    check_word("Case E first result", 12, 16'hBCDE);
    check_word("Case E last result",  13, 16'h555A);

    // Case F: two partial words -> two separately locked RMW pairs.
    backing[16] = 16'h0011;
    backing[17] = 16'h2220;
    base = transaction_count_q;
    do_write(32'd264, 6'd12, 32'h0000_0ABC);
    check_count("Case F", base, 4);
    check_transaction("Case F read first",  base,   1'b0, 32'd256, '0,       1'b1);
    check_transaction("Case F write first", base+1, 1'b1, 32'd256, 16'hBC11, 1'b1);
    check_transaction("Case F read last",   base+2, 1'b0, 32'd272, '0,       1'b1);
    check_transaction("Case F write last",  base+3, 1'b1, 32'd272, 16'h222A, 1'b1);
    check_word("Case F first result", 16, 16'hBC11);
    check_word("Case F last result",  17, 16'h222A);

    // Case G: partial/full/partial across three words -> five cycles.
    backing[24] = 16'h00AA;
    backing[25] = 16'hCCCC;
    backing[26] = 16'hBB00;
    base = transaction_count_q;
    do_write(32'd392, 6'd32, 32'h1234_5678);
    check_count("Case G", base, 5);
    check_transaction("Case G read first",   base,   1'b0, 32'd384, '0,       1'b1);
    check_transaction("Case G write first",  base+1, 1'b1, 32'd384, 16'h78AA, 1'b1);
    check_transaction("Case G write middle", base+2, 1'b1, 32'd400, 16'h3456, 1'b0);
    check_transaction("Case G read last",    base+3, 1'b0, 32'd416, '0,       1'b1);
    check_transaction("Case G write last",   base+4, 1'b1, 32'd416, 16'hBB12, 1'b1);
    check_word("Case G first result",  24, 16'h78AA);
    check_word("Case G middle result", 25, 16'h3456);
    check_word("Case G last result",   26, 16'hBB12);

    // Extraction: exactly one, two, or three ascending reads.
    backing[32] = 16'hCAFE;
    base = transaction_count_q;
    check_read("one-word read", 32'd512, 6'd16, 32'h0000_CAFE);
    check_count("one-word read", base, 1);
    check_transaction("one-word read txn", base, 1'b0, 32'd512, '0, 1'b0);

    base = transaction_count_q;
    check_read("masked one-word subfield", 32'd516, 6'd4, 32'h0000_000F);
    check_count("masked one-word subfield", base, 1);
    check_transaction("masked one-word subfield txn",
                      base, 1'b0, 32'd512, '0, 1'b0);

    backing[33] = 16'hBEEF;
    backing[34] = 16'hDEAD;
    base = transaction_count_q;
    check_read("two-word read", 32'd528, 6'd32, 32'hDEAD_BEEF);
    check_count("two-word read", base, 2);
    check_transaction("two-word read low",  base,   1'b0, 32'd528, '0, 1'b0);
    check_transaction("two-word read high", base+1, 1'b0, 32'd544, '0, 1'b0);

    backing[35] = 16'h7800;
    backing[36] = 16'h3456;
    backing[37] = 16'h0012;
    base = transaction_count_q;
    check_read("three-word read", 32'd568, 6'd32, 32'h1234_5678);
    check_count("three-word read", base, 3);
    check_transaction("three-word read first",  base,   1'b0, 32'd560, '0, 1'b0);
    check_transaction("three-word read middle", base+1, 1'b0, 32'd576, '0, 1'b0);
    check_transaction("three-word read last",   base+2, 1'b0, 32'd592, '0, 1'b0);

    if (protocol_failures_q != 0) begin
      $display("TEST_RESULT: FAIL: %0d pre-reset word payload stability violation(s)",
               protocol_failures_q);
      failures++;
    end

    // Reset cancels a stalled word request and leaves the sequencer reusable.
    @(negedge clk);
    field_req   = 1'b1;
    field_we    = 1'b0;
    field_addr  = 32'd512;
    field_size  = 6'd16;
    field_wdata = '0;
    do @(negedge clk); while (word_req !== 1'b1);
    rst = 1'b1;
    repeat (2) @(posedge clk);
    #1;
    if (field_ack !== 1'b0 || word_req !== 1'b0) begin
      $display("TEST_RESULT: FAIL: reset did not quiesce field/word handshake");
      failures++;
    end
    field_req = 1'b0;
    @(negedge clk);
    rst = 1'b0;
    check_read("post-reset recovery", 32'd512, 6'd16, 32'h0000_CAFE);

    if (protocol_failures_q != 0) begin
      $display("TEST_RESULT: FAIL: %0d stalled word payload stability violation(s)",
               protocol_failures_q);
      failures++;
    end

    if (failures == 0)
      $display("TEST_RESULT: PASS (field sequencer cases A-G, reads, stalls, RMW lock, reset)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #5_000_000;
    $display("TEST_RESULT: FAIL: tb_field_sequencer hard timeout");
    $fatal(1);
  end

endmodule : tb_field_sequencer
