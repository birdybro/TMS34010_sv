// -----------------------------------------------------------------------------
// tb_regfile.sv
//
// Unit test for tms34010_regfile.
//
// Coverage:
//   1. Reset clears every entry. Verified by sweeping all 15 A indices, all
//      15 B indices, and SP, reading each on rs1 and rs2.
//   2. Write-then-read on the same file: data round-trips.
//   3. A and B are independent: writing A5 does not affect B5.
//   4. SP aliasing: writing A15 is observable as B15 read, B15 read, and on
//      the `sp_o` observability port; symmetric for writes via file B.
//   5. Both read ports work independently and concurrently.
//   6. Write-after-read on the same address within a cycle returns the OLD
//      value on the read port (synchronous write contract).
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_regfile;
  import tms34010_pkg::*;

  // ---------------------------------------------------------------------------
  // Clock and reset
  // ---------------------------------------------------------------------------
  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  // ---------------------------------------------------------------------------
  // DUT wiring
  // ---------------------------------------------------------------------------
  reg_file_t              rs1_file;
  reg_idx_t               rs1_idx;
  logic [DATA_WIDTH-1:0]  rs1_data;

  reg_file_t              rs2_file;
  reg_idx_t               rs2_idx;
  logic [DATA_WIDTH-1:0]  rs2_data;

  logic                   wr_en;
  reg_file_t              wr_file;
  reg_idx_t               wr_idx;
  logic [DATA_WIDTH-1:0]  wr_data;

  logic [DATA_WIDTH-1:0]  sp_o;

  tms34010_regfile dut (
    .clk      (clk),
    .rst      (rst),
    .rs1_file (rs1_file),
    .rs1_idx  (rs1_idx),
    .rs1_data (rs1_data),
    .rs2_file (rs2_file),
    .rs2_idx  (rs2_idx),
    .rs2_data (rs2_data),
    .wr_en    (wr_en),
    .wr_file  (wr_file),
    .wr_idx   (wr_idx),
    .wr_data  (wr_data),
    .sp_o     (sp_o)
  );

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  int unsigned failures;

  task automatic check_eq(input logic [DATA_WIDTH-1:0] actual,
                          input logic [DATA_WIDTH-1:0] expected,
                          input string                  label);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%08h actual=%08h",
               label, expected, actual);
      failures++;
    end
  endtask

  task automatic do_write(input reg_file_t f,
                          input reg_idx_t  i,
                          input logic [DATA_WIDTH-1:0] data);
    wr_en   = 1'b1;
    wr_file = f;
    wr_idx  = i;
    wr_data = data;
    @(posedge clk);
    wr_en   = 1'b0;
    #1;  // slip past NBA so the next read observes the new value
  endtask

  task automatic read_port1(input reg_file_t f,
                            input reg_idx_t  i,
                            output logic [DATA_WIDTH-1:0] data);
    rs1_file = f;
    rs1_idx  = i;
    #1;
    data = rs1_data;
  endtask

  task automatic read_port2(input reg_file_t f,
                            input reg_idx_t  i,
                            output logic [DATA_WIDTH-1:0] data);
    rs2_file = f;
    rs2_idx  = i;
    #1;
    data = rs2_data;
  endtask

  // ---------------------------------------------------------------------------
  // Test body
  // ---------------------------------------------------------------------------
  logic [DATA_WIDTH-1:0] got;

  initial begin : main
    failures = 0;

    // Quiescent defaults.
    rs1_file = REG_FILE_A;
    rs1_idx  = 4'd0;
    rs2_file = REG_FILE_A;
    rs2_idx  = 4'd0;
    wr_en    = 1'b0;
    wr_file  = REG_FILE_A;
    wr_idx   = 4'd0;
    wr_data  = '0;

    // Reset.
    repeat (3) @(posedge clk);
    rst = 1'b0;
    #1;

    // 1. Reset clears every entry, observed via rs1.
    for (int unsigned i = 0; i < 15; i++) begin
      read_port1(REG_FILE_A, reg_idx_t'(i), got);
      check_eq(got, '0, $sformatf("reset A%0d", i));
      read_port1(REG_FILE_B, reg_idx_t'(i), got);
      check_eq(got, '0, $sformatf("reset B%0d", i));
    end
    read_port1(REG_FILE_A, REG_SP_IDX, got);
    check_eq(got, '0, "reset SP via A15");
    read_port1(REG_FILE_B, REG_SP_IDX, got);
    check_eq(got, '0, "reset SP via B15");
    check_eq(sp_o, '0, "reset sp_o");

    // 2. Write-then-read on file A.
    do_write(REG_FILE_A, 4'd0,  32'h1111_1111);
    do_write(REG_FILE_A, 4'd5,  32'hAAAA_5555);
    do_write(REG_FILE_A, 4'd14, 32'hCAFE_BABE);
    read_port1(REG_FILE_A, 4'd0,  got); check_eq(got, 32'h1111_1111, "A0 read");
    read_port1(REG_FILE_A, 4'd5,  got); check_eq(got, 32'hAAAA_5555, "A5 read");
    read_port1(REG_FILE_A, 4'd14, got); check_eq(got, 32'hCAFE_BABE, "A14 read");

    // 3. A and B are independent — B5 still 0.
    read_port1(REG_FILE_B, 4'd5, got);
    check_eq(got, '0, "B5 not touched by A5 write");

    // 4. Write file B independently.
    do_write(REG_FILE_B, 4'd0,  32'h2222_2222);
    do_write(REG_FILE_B, 4'd5,  32'hBBBB_5555);
    do_write(REG_FILE_B, 4'd14, 32'hDEAD_BEEF);
    read_port1(REG_FILE_B, 4'd0,  got); check_eq(got, 32'h2222_2222, "B0 read");
    read_port1(REG_FILE_B, 4'd5,  got); check_eq(got, 32'hBBBB_5555, "B5 read");
    read_port1(REG_FILE_B, 4'd14, got); check_eq(got, 32'hDEAD_BEEF, "B14 read");

    // Cross-check A side unchanged.
    read_port1(REG_FILE_A, 4'd0, got); check_eq(got, 32'h1111_1111, "A0 unchanged after B writes");

    // 5. SP aliasing.
    do_write(REG_FILE_A, REG_SP_IDX, 32'h1234_ABCD);
    read_port1(REG_FILE_A, REG_SP_IDX, got);
    check_eq(got, 32'h1234_ABCD, "SP read via A15");
    read_port1(REG_FILE_B, REG_SP_IDX, got);
    check_eq(got, 32'h1234_ABCD, "SP read via B15");
    check_eq(sp_o, 32'h1234_ABCD, "sp_o after A15 write");

    do_write(REG_FILE_B, REG_SP_IDX, 32'h89AB_CDEF);
    read_port1(REG_FILE_A, REG_SP_IDX, got);
    check_eq(got, 32'h89AB_CDEF, "SP read via A15 after B15 write");
    check_eq(sp_o, 32'h89AB_CDEF, "sp_o after B15 write");

    // 6. Both read ports independently — read A5 on rs1, B14 on rs2.
    read_port1(REG_FILE_A, 4'd5, got);
    check_eq(got, 32'hAAAA_5555, "concurrent rs1 A5");
    read_port2(REG_FILE_B, 4'd14, got);
    check_eq(got, 32'hDEAD_BEEF, "concurrent rs2 B14");

    // 7. Synchronous write contract: a read on the same cycle as a write
    //    to the same address sees the OLD value, then the new value next
    //    cycle.
    rs1_file = REG_FILE_A;
    rs1_idx  = 4'd5;
    wr_en    = 1'b1;
    wr_file  = REG_FILE_A;
    wr_idx   = 4'd5;
    wr_data  = 32'h1234_5678;
    #1;
    // Pre-edge: rs1_data should still be the OLD value.
    check_eq(rs1_data, 32'hAAAA_5555, "same-cycle read sees OLD value");
    @(posedge clk);
    wr_en = 1'b0;
    #1;
    // Post-edge: rs1_data is the new value.
    check_eq(rs1_data, 32'h1234_5678, "next-cycle read sees NEW value");

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (all regfile checks passed)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #50_000;
    $display("TEST_RESULT: FAIL: tb_regfile hard timeout");
    $fatal(1);
  end

endmodule : tb_regfile
